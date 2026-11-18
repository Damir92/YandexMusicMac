import SwiftUI
import AppKit

/// Per-row observable hover state that isolates SwiftUI view invalidation to O(1) affected rows.
@Observable
@MainActor
public final class TrackRowHoverState {
    public var isHovered: Bool = false

    public init() {}
}

/// Transparent AppKit anchor view preserved for API compatibility.
/// Always returns `nil` from `hitTest(_:)` so clicks, double-clicks, row buttons, and context menus
/// are never intercepted.
public final class TrackHoverAnchorNSView: NSView {
    var trackId: String = ""

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

/// SwiftUI bridge registering an optional `TrackHoverAnchorNSView` with `TrackHoverManager`.
public struct TrackHoverAnchor: NSViewRepresentable {
    public let trackId: String

    public init(trackId: String) {
        self.trackId = trackId
    }

    public func makeNSView(context: Context) -> TrackHoverAnchorNSView {
        let view = TrackHoverAnchorNSView()
        view.trackId = trackId
        TrackHoverManager.shared.registerAnchor(view, for: trackId)
        return view
    }

    public func updateNSView(_ nsView: TrackHoverAnchorNSView, context: Context) {
        if nsView.trackId != trackId {
            let oldTrackId = nsView.trackId
            nsView.trackId = trackId
            TrackHoverManager.shared.unregisterAnchor(nsView, for: oldTrackId)
            TrackHoverManager.shared.registerAnchor(nsView, for: trackId)
        } else {
            TrackHoverManager.shared.registerAnchor(nsView, for: trackId)
        }
    }

    public static func dismantleNSView(_ nsView: TrackHoverAnchorNSView, coordinator: ()) {
        TrackHoverManager.shared.unregisterAnchor(nsView, for: nsView.trackId)
    }
}

/// Centralized, lightweight hybrid manager for high-performance track list hover interactions.
/// Guarantees:
/// 1. Native SwiftUI `.onHover` feeds `pointerCandidateTrackId` with exact row coordinates (zero `NSViewRepresentable` per row).
/// 2. O(1) row redraw isolation via per-row `TrackRowHoverState` instances that never detach from live rows during scrolling.
/// 3. Zero scroll stutter: hover updates are suppressed during active scrolling and inertia via a single deadline watchdog.
/// 4. Instant responsiveness: moving the pointer explicitly ends scroll suppression immediately, and scroll completion
///    resolves hover to `pointerCandidateTrackId` without heavy WindowServer IPC calls.
@MainActor
public final class TrackHoverManager {
    public static let shared = TrackHoverManager()

    private struct AnchorEntry {
        let trackId: String
        weak var view: NSView?
    }

    private var hoveredTrackId: String? = nil
    private var pointerCandidateTrackId: String? = nil
    private var isScrolling: Bool = false
    private var rowStates: [String: TrackRowHoverState] = [:]
    private var anchors: [ObjectIdentifier: AnchorEntry] = [:]

    private var scrollEndDeadlineNanos: UInt64 = 0
    private var scrollWatchdogTask: Task<Void, Never>? = nil
    private var eventMonitor: Any? = nil

    // Internal accessors for unit tests (never read from SwiftUI view bodies)
    var isScrollSuppressed: Bool { isScrolling }
    var currentHoveredTrackId: String? { hoveredTrackId }
    var registeredRowStateCount: Int { rowStates.count }
    var registeredAnchorCount: Int { anchors.count }

    public init() {
        setupEventAndScrollDetection()
    }

    /// Lazily creates and returns the isolated `@Observable` hover state for a specific track row.
    public func state(for trackId: String) -> TrackRowHoverState {
        if let existing = rowStates[trackId] {
            return existing
        }
        let state = TrackRowHoverState()
        if !isScrolling && hoveredTrackId == trackId {
            state.isHovered = true
        }
        rowStates[trackId] = state
        return state
    }

    /// Removes the cached row state when explicitly requested (unless it is currently active).
    /// Not invoked during normal SwiftUI lazy scrolling so live rows never lose reactivity.
    public func unregister(trackId: String) {
        guard hoveredTrackId != trackId else { return }
        rowStates.removeValue(forKey: trackId)
    }

    /// Lightweight entry point for SwiftUI `.onHover` on track rows.
    /// Tracks the physical pointer candidate even while scrolling, while suppressing UI redraws until scrolling finishes.
    public func handleRowHover(trackId: String, isInside: Bool) {
        if isInside {
            pointerCandidateTrackId = trackId
            if !isScrolling {
                setHovered(trackId)
            }
        } else {
            if pointerCandidateTrackId == trackId {
                pointerCandidateTrackId = nil
            }
            if !isScrolling {
                clearIfHovered(trackId)
            }
        }
    }

    public func setHovered(_ newId: String?) {
        guard !isScrolling else { return }
        guard hoveredTrackId != newId else { return }

        if let oldId = hoveredTrackId {
            rowStates[oldId]?.isHovered = false
        }
        hoveredTrackId = newId
        if let newId {
            state(for: newId).isHovered = true
        }
    }

    public func clear() {
        if let oldId = hoveredTrackId {
            rowStates[oldId]?.isHovered = false
            hoveredTrackId = nil
        }
    }

    public func clearIfHovered(_ trackId: String) {
        guard hoveredTrackId == trackId else { return }
        clear()
    }

    func registerAnchor(_ view: NSView, for trackId: String) {
        anchors[ObjectIdentifier(view)] = AnchorEntry(trackId: trackId, view: view)
    }

    func unregisterAnchor(_ view: NSView, for trackId: String) {
        anchors.removeValue(forKey: ObjectIdentifier(view))

        let hasOtherLiveAnchor = anchors.values.contains { entry in
            entry.trackId == trackId && entry.view != nil
        }
        if !hasOtherLiveAnchor && hoveredTrackId != trackId {
            unregister(trackId: trackId)
        }
    }

    public func notifyScrollActivity(debounceNanoseconds: UInt64 = 100_000_000) {
        if !isScrolling {
            isScrolling = true
            clear()
        }
        let deadline = DispatchTime.now().uptimeNanoseconds &+ debounceNanoseconds
        if deadline > scrollEndDeadlineNanos {
            scrollEndDeadlineNanos = deadline
        }
        ensureScrollWatchdogRunning()
    }

    public func notifyScrollEnded() {
        scrollWatchdogTask?.cancel()
        scrollWatchdogTask = nil
        scrollEndDeadlineNanos = 0
        guard isScrolling else { return }
        isScrolling = false
        resolveHoverUnderCursor()
    }

    /// Resolves the hovered row when scrolling ends without invoking heavy WindowServer IPC calls.
    /// Uses native SwiftUI `.onHover` candidate tracking when no AppKit anchors are registered,
    /// with a lightweight anchor-based fallback if anchors exist.
    public func resolveHoverUnderCursor() {
        guard !isScrolling else { return }

        if anchors.isEmpty {
            if let candidate = pointerCandidateTrackId {
                setHovered(candidate)
            } else {
                clear()
            }
            return
        }

        // Lightweight fallback when AppKit anchors are registered (without WindowServer IPC)
        guard let app = NSApp,
              let window = app.keyWindow,
              window.isVisible,
              window.isKeyWindow,
              let contentView = window.contentView
        else {
            pruneStaleAnchors()
            if let candidate = pointerCandidateTrackId {
                setHovered(candidate)
            } else {
                clear()
            }
            return
        }

        let screenPoint = NSEvent.mouseLocation
        guard window.frame.contains(screenPoint) else {
            pruneStaleAnchors()
            clear()
            return
        }

        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let hitTestPoint = contentView.superview?.convert(windowPoint, from: nil) ?? windowPoint
        guard let hitView = contentView.hitTest(hitTestPoint) else {
            pruneStaleAnchors()
            clear()
            return
        }

        let hitScrollView = (hitView as? NSScrollView) ?? hitView.enclosingScrollView
        var matchedTrackId: String? = nil
        var staleKeys: [ObjectIdentifier] = []

        for (key, entry) in anchors {
            guard let anchorView = entry.view else {
                staleKeys.append(key)
                continue
            }

            guard matchedTrackId == nil else { continue }

            guard anchorView.window === window,
                  !anchorView.isHiddenOrHasHiddenAncestor,
                  !anchorView.bounds.isEmpty,
                  !anchorView.visibleRect.isEmpty,
                  let anchorScrollView = anchorView.enclosingScrollView,
                  let hitScrollView,
                  hitScrollView === anchorScrollView
            else {
                continue
            }

            let localPoint = anchorView.convert(windowPoint, from: nil)
            if anchorView.visibleRect.contains(localPoint) {
                matchedTrackId = entry.trackId
            }
        }

        for key in staleKeys {
            anchors.removeValue(forKey: key)
        }

        if let matchedTrackId {
            setHovered(matchedTrackId)
        } else if let candidate = pointerCandidateTrackId {
            setHovered(candidate)
        } else {
            clear()
        }
    }

    private func extendScrollDebounceIfScrolling(debounceNanoseconds: UInt64) {
        guard isScrolling else { return }
        let deadline = DispatchTime.now().uptimeNanoseconds &+ debounceNanoseconds
        if deadline > scrollEndDeadlineNanos {
            scrollEndDeadlineNanos = deadline
        }
        ensureScrollWatchdogRunning()
    }

    private func ensureScrollWatchdogRunning() {
        guard scrollWatchdogTask == nil else { return }
        scrollWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = DispatchTime.now().uptimeNanoseconds
                if now >= self.scrollEndDeadlineNanos {
                    self.scrollWatchdogTask = nil
                    self.scrollEndDeadlineNanos = 0
                    if self.isScrolling {
                        self.isScrolling = false
                        self.resolveHoverUnderCursor()
                    }
                    return
                }
                let remaining = self.scrollEndDeadlineNanos - now
                try? await Task.sleep(nanoseconds: remaining)
            }
        }
    }

    private func pruneStaleAnchors() {
        anchors = anchors.filter { $0.value.view != nil }
    }

    private func setupEventAndScrollDetection() {
        // 1. AppKit live scroll notifications for NSScrollView instances
        NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.notifyScrollActivity(debounceNanoseconds: 100_000_000)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.notifyScrollActivity(debounceNanoseconds: 85_000_000)
            }
        }

        // Extend debounce on live scroll end so trackpad inertia (1–16 ms later) never flickers hover
        NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.extendScrollDebounceIfScrolling(debounceNanoseconds: 55_000_000)
            }
        }

        // Clear hover when opening a context menu, modal sheet, or switching to another app
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pointerCandidateTrackId = nil
                self?.clear()
            }
        }

        // 2. Local AppKit event monitor for scrollWheel, mouseMoved, and mouseExited
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .mouseMoved, .mouseExited]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }

                switch event.type {
                case .mouseMoved:
                    if self.isScrolling {
                        // Explicit pointer movement immediately ends scroll suppression for snappy response
                        if abs(event.deltaX) > 1.0 || abs(event.deltaY) > 1.0 {
                            self.notifyScrollEnded()
                        }
                    } else if let candidate = self.pointerCandidateTrackId {
                        self.setHovered(candidate)
                    }

                case .mouseExited:
                    if event.window == nil {
                        self.pointerCandidateTrackId = nil
                        self.clear()
                    } else if let app = NSApp,
                              let activeWindow = app.keyWindow ?? app.mainWindow,
                              event.window === activeWindow,
                              !activeWindow.frame.contains(NSEvent.mouseLocation) {
                        self.pointerCandidateTrackId = nil
                        self.clear()
                    }

                case .scrollWheel:
                    let phase = event.phase
                    let momentumPhase = event.momentumPhase
                    let hasSignificantDelta = abs(event.scrollingDeltaX) > 0.5 || abs(event.scrollingDeltaY) > 0.5
                    let hasAnyDelta = abs(event.scrollingDeltaX) > 0.01 || abs(event.scrollingDeltaY) > 0.01

                    let isGestureEnd = momentumPhase == .ended
                        || momentumPhase == .cancelled
                        || ((phase == .ended || phase == .cancelled) && momentumPhase.isEmpty)
                    let isDiscreteWheel = phase.isEmpty && momentumPhase.isEmpty
                    let isActiveGesture = phase == .began || phase == .changed
                        || momentumPhase == .began || momentumPhase == .changed

                    if isGestureEnd {
                        self.extendScrollDebounceIfScrolling(debounceNanoseconds: 55_000_000)
                    } else if isDiscreteWheel {
                        if hasSignificantDelta {
                            self.notifyScrollActivity(debounceNanoseconds: 95_000_000)
                        }
                    } else if isActiveGesture {
                        if hasSignificantDelta {
                            self.notifyScrollActivity(debounceNanoseconds: 85_000_000)
                        } else if hasAnyDelta {
                            self.extendScrollDebounceIfScrolling(debounceNanoseconds: 85_000_000)
                        }
                    }

                default:
                    break
                }
            }

            return event
        }
    }
}
