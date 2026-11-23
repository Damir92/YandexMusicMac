import SwiftUI
import AppKit

/// Per-row observable hover state that isolates SwiftUI view invalidation to O(1) affected rows.
@Observable
@MainActor
public final class TrackRowHoverState {
    public var isHovered: Bool = false

    public init() {}
}

/// Transparent AppKit anchor view providing exact geometric coordinates for track rows.
/// Always returns `nil` from `hitTest(_:)` so clicks, double-clicks, row buttons, and context menus
/// are never intercepted.
public final class TrackHoverAnchorNSView: NSView {
    var trackId: String = ""
    private var hoverTrackingArea: NSTrackingArea?

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard hoverTrackingArea == nil else { return }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        TrackHoverManager.shared.scheduleHoverResolve()
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        TrackHoverManager.shared.scheduleHoverResolve()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        if let clipView = enclosingScrollView?.contentView {
            TrackHoverManager.shared.observeScrollClipView(clipView)
        }
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let clipView = enclosingScrollView?.contentView {
            TrackHoverManager.shared.observeScrollClipView(clipView)
        }
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
        }
        if let clipView = nsView.enclosingScrollView?.contentView {
            TrackHoverManager.shared.observeScrollClipView(clipView)
        }
    }

    public static func dismantleNSView(_ nsView: TrackHoverAnchorNSView, coordinator: ()) {
        TrackHoverManager.shared.unregisterAnchor(nsView, for: nsView.trackId)
    }
}

/// Centralized, lightweight hybrid manager for high-performance track list hover interactions.
/// Guarantees:
/// 1. True AppKit geometric hit testing via `TrackHoverAnchorNSView` tracking areas and `NSClipView.boundsDidChangeNotification`.
/// 2. O(1) row redraw isolation via per-row `TrackRowHoverState` instances that never detach from live rows during scrolling.
/// 3. Zero scroll stutter: hover updates are suppressed during active scrolling via `onScrollPhaseChange` on macOS 15+ and watchdog on macOS 14.
/// 4. Instant responsiveness: coalesced `scheduleHoverResolve()` runs on frame end without dropping cursor moves,
///    resolving directly to the exact row underneath without 1..N row drift.
@MainActor
public final class TrackHoverManager {
    public static let shared = TrackHoverManager()

    private struct AnchorEntry {
        let trackId: String
        weak var view: NSView?
    }

    private struct WeakClipView {
        weak var view: NSClipView?
        var lastOrigin: NSPoint = NSPoint(x: -999_999, y: -999_999)
    }

    private var hoveredTrackId: String? = nil
    private var pointerCandidateTrackId: String? = nil
    private var isScrolling: Bool = false
    private var isScrollPhaseActive: Bool = false
    private var hasNativeScrollPhaseMonitor: Bool = false
    private var nativeScrollSettleTask: Task<Void, Never>? = nil
    private var lastResolvedScreenPoint: NSPoint? = nil
    private var forceNextResolve: Bool = false
    private var hoveredAnchorKey: ObjectIdentifier? = nil
    private var isHoverResolveScheduled: Bool = false
    private var rowStates: [String: TrackRowHoverState] = [:]
    private var visibleRowCounts: [String: Int] = [:]
    private var anchors: [ObjectIdentifier: AnchorEntry] = [:]

    private var observedClipViews: [ObjectIdentifier: WeakClipView] = [:]
    private var clipViewObservers: [ObjectIdentifier: any NSObjectProtocol] = [:]
    private var lastScrollEventNanos: UInt64 = 0

    private var scrollEndDeadlineNanos: UInt64 = 0
    private var scrollWatchdogTask: Task<Void, Never>? = nil
    private var eventMonitor: Any? = nil
    private var notificationObservers: [any NSObjectProtocol] = []

    // Public accessor for UI components (zero @Observable overhead)
    public var isScrollSuppressed: Bool { isScrolling || isScrollPhaseActive }
    var currentHoveredTrackId: String? { hoveredTrackId }
    var registeredRowStateCount: Int { rowStates.count }
    var registeredAnchorCount: Int { anchors.count }

    public init() {
        setupEventAndScrollDetection()
    }

    public func cleanup() {
        nativeScrollSettleTask?.cancel()
        nativeScrollSettleTask = nil
        hasNativeScrollPhaseMonitor = false
        lastResolvedScreenPoint = nil
        forceNextResolve = false
        hoveredAnchorKey = nil

        scrollWatchdogTask?.cancel()
        scrollWatchdogTask = nil
        scrollEndDeadlineNanos = 0
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()

        for observer in clipViewObservers.values {
            NotificationCenter.default.removeObserver(observer)
        }
        clipViewObservers.removeAll()
        observedClipViews.removeAll()

        anchors.removeAll()
        rowStates.removeAll()
        visibleRowCounts.removeAll()
        hoveredTrackId = nil
        pointerCandidateTrackId = nil
        isScrolling = false
        isScrollPhaseActive = false
        isHoverResolveScheduled = false
        lastScrollEventNanos = 0
    }

    public func setScrollPhaseActive(_ active: Bool) {
        hasNativeScrollPhaseMonitor = true
        if active {
            nativeScrollSettleTask?.cancel()
            nativeScrollSettleTask = nil
            scrollWatchdogTask?.cancel()
            scrollWatchdogTask = nil
            scrollEndDeadlineNanos = 0
            isScrollPhaseActive = true
            if !isScrolling {
                isScrolling = true
                clear()
            }
            lastScrollEventNanos = DispatchTime.now().uptimeNanoseconds
            lastResolvedScreenPoint = nil
        } else {
            // Короткий settle 35 мс гасит микродребезг фаз (.idle -> .decelerating)
            // и даёт AppKit/SwiftUI 1-2 кадра на фиксацию финального положения строк.
            // Hover появляется ОДИН раз, без подмигивания.
            nativeScrollSettleTask?.cancel()
            nativeScrollSettleTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 35_000_000)
                guard let self, !Task.isCancelled else { return }
                self.nativeScrollSettleTask = nil
                self.isScrollPhaseActive = false
                self.isScrolling = false
                self.forceNextResolve = true
                self.resolveHoverUnderCursor()
            }
        }
    }

    public func scheduleHoverResolve() {
        guard !isScrollSuppressed, !isHoverResolveScheduled else { return }
        isHoverResolveScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isHoverResolveScheduled = false
            guard !self.isScrollSuppressed else { return }
            self.resolveHoverUnderCursor()
        }
    }

    public func observeScrollClipView(_ clipView: NSClipView) {
        // Prune dead clip views
        var deadKeys: [ObjectIdentifier] = []
        for (key, weakRef) in observedClipViews {
            if weakRef.view == nil {
                deadKeys.append(key)
                if let obs = clipViewObservers[key] {
                    NotificationCenter.default.removeObserver(obs)
                    clipViewObservers.removeValue(forKey: key)
                }
            }
        }
        for key in deadKeys {
            observedClipViews.removeValue(forKey: key)
        }

        let id = ObjectIdentifier(clipView)
        guard observedClipViews[id] == nil else { return }

        clipView.postsBoundsChangedNotifications = true
        observedClipViews[id] = WeakClipView(view: clipView)

        let clipId = id
        let obs = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.hasNativeScrollPhaseMonitor { return }
                guard !self.anchors.isEmpty || !self.visibleRowCounts.isEmpty else { return }
                guard let entry = self.observedClipViews[clipId], let cv = entry.view else { return }
                let newOrigin = cv.bounds.origin
                let lastOrigin = entry.lastOrigin
                guard abs(newOrigin.y - lastOrigin.y) > 0.5 || abs(newOrigin.x - lastOrigin.x) > 0.5 else { return }
                self.observedClipViews[clipId]?.lastOrigin = newOrigin

                if self.isScrollPhaseActive {
                    return
                }

                self.notifyScrollActivity(debounceNanoseconds: 110_000_000)
            }
        }
        clipViewObservers[id] = obs
    }

    private func hasLiveAnchor(for trackId: String) -> Bool {
        anchors.values.contains { $0.trackId == trackId && $0.view != nil }
    }

    public func rowDidAppear(trackId: String) {
        visibleRowCounts[trackId, default: 0] += 1
    }

    public func rowDidDisappear(trackId: String) {
        guard let count = visibleRowCounts[trackId] else { return }
        if count <= 1 {
            visibleRowCounts.removeValue(forKey: trackId)
        } else {
            visibleRowCounts[trackId] = count - 1
        }
    }

    /// Lazily creates and returns the isolated `@Observable` hover state for a specific track row.
    public func state(for trackId: String) -> TrackRowHoverState {
        if let existing = rowStates[trackId] {
            return existing
        }

        if rowStates.count > 200 {
            for (key, _) in rowStates {
                if visibleRowCounts[key] == nil && key != hoveredTrackId && key != pointerCandidateTrackId && !hasLiveAnchor(for: key) {
                    rowStates.removeValue(forKey: key)
                }
            }
        }

        let state = TrackRowHoverState()
        if !isScrollSuppressed && hoveredTrackId == trackId {
            state.isHovered = true
        }
        rowStates[trackId] = state
        return state
    }

    /// Removes the cached row state when explicitly requested (unless it is currently active or anchored).
    public func unregister(trackId: String) {
        guard hoveredTrackId != trackId else { return }
        guard !hasLiveAnchor(for: trackId) else { return }
        rowStates.removeValue(forKey: trackId)
    }

    /// Lightweight entry point for SwiftUI `.onHover` on track rows.
    /// When anchors are present, AppKit geometry is the sole source of truth and SwiftUI `.onHover` is ignored.
    public func handleRowHover(trackId: String, isInside: Bool) {
        guard anchors.isEmpty else { return }
        if isInside {
            pointerCandidateTrackId = trackId
            if !isScrollSuppressed {
                setHovered(trackId)
            }
        } else {
            if pointerCandidateTrackId == trackId {
                pointerCandidateTrackId = nil
            }
            if !isScrollSuppressed {
                clearIfHovered(trackId)
            }
        }
    }

    public func setHovered(_ newId: String?) {
        guard !isScrollSuppressed else { return }
        guard hoveredTrackId != newId else { return }

        if let oldId = hoveredTrackId {
            rowStates[oldId]?.isHovered = false
        }
        hoveredTrackId = newId
        if let newId {
            state(for: newId).isHovered = true
        }
    }

    public func clear(resetScreenPoint: Bool = false) {
        if resetScreenPoint {
            lastResolvedScreenPoint = nil
        }
        hoveredAnchorKey = nil
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

        if !hasLiveAnchor(for: trackId) && visibleRowCounts[trackId] == nil && hoveredTrackId != trackId {
            unregister(trackId: trackId)
        }
    }

    public func notifyScrollActivity(debounceNanoseconds: UInt64 = 100_000_000) {
        lastScrollEventNanos = DispatchTime.now().uptimeNanoseconds
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

    /// Resolves the hovered row without invoking heavy WindowServer IPC calls.
    public func resolveHoverUnderCursor() {
        resolveHoverUnderCursor(eventWindow: nil, eventWindowPoint: nil)
    }

    private func resolveHoverUnderCursor(eventWindow: NSWindow?, eventWindowPoint: NSPoint?) {
        guard !isScrollSuppressed else { return }

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
            pointerCandidateTrackId = nil
            clear()
            return
        }

        if let eventWindow, eventWindow !== window {
            pointerCandidateTrackId = nil
            clear()
            return
        }

        let screenPoint = NSEvent.mouseLocation
        if !forceNextResolve,
           let last = lastResolvedScreenPoint,
           abs(last.x - screenPoint.x) < 0.5 && abs(last.y - screenPoint.y) < 0.5 {
            return
        }
        forceNextResolve = false
        lastResolvedScreenPoint = screenPoint

        guard window.frame.contains(screenPoint) else {
            pruneStaleAnchors()
            pointerCandidateTrackId = nil
            clear()
            return
        }

        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let hitTestPoint = contentView.superview?.convert(windowPoint, from: nil) ?? windowPoint
        guard let hitView = contentView.hitTest(hitTestPoint) else {
            pruneStaleAnchors()
            pointerCandidateTrackId = nil
            clear()
            return
        }

        guard let hitScrollView = (hitView as? NSScrollView) ?? hitView.enclosingScrollView else {
            pointerCandidateTrackId = nil
            clear()
            return
        }

        // O(1) fast-path: check if cursor is still inside the current hovered anchor
        if let activeKey = hoveredAnchorKey,
           let activeEntry = anchors[activeKey],
           let activeView = activeEntry.view {
            if activeView.window === window,
               !activeView.isHiddenOrHasHiddenAncestor,
               !activeView.bounds.isEmpty,
               !activeView.visibleRect.isEmpty,
               activeView.enclosingScrollView === hitScrollView {
                let localPoint = activeView.convert(windowPoint, from: nil)
                if activeView.bounds.contains(localPoint) && activeView.visibleRect.contains(localPoint) {
                    pointerCandidateTrackId = activeEntry.trackId
                    return
                }
            }
        }

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
                  anchorView.enclosingScrollView === hitScrollView
            else {
                continue
            }

            let localPoint = anchorView.convert(windowPoint, from: nil)
            if anchorView.bounds.contains(localPoint) && anchorView.visibleRect.contains(localPoint) {
                matchedTrackId = entry.trackId
                hoveredAnchorKey = key
            }
        }

        for key in staleKeys {
            anchors.removeValue(forKey: key)
        }

        if let matchedTrackId {
            setHovered(matchedTrackId)
            pointerCandidateTrackId = matchedTrackId
        } else {
            hoveredAnchorKey = nil
            pointerCandidateTrackId = nil
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
        let willStartLiveObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.hasNativeScrollPhaseMonitor { return }
                self.lastScrollEventNanos = DispatchTime.now().uptimeNanoseconds
                if !self.isScrollPhaseActive {
                    self.notifyScrollActivity(debounceNanoseconds: 100_000_000)
                }
            }
        }
        notificationObservers.append(willStartLiveObserver)

        let didLiveScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.hasNativeScrollPhaseMonitor { return }
                self.lastScrollEventNanos = DispatchTime.now().uptimeNanoseconds
                if !self.isScrollPhaseActive {
                    self.notifyScrollActivity(debounceNanoseconds: 85_000_000)
                }
            }
        }
        notificationObservers.append(didLiveScrollObserver)

        // Extend debounce on live scroll end so trackpad inertia never flickers hover
        let didEndLiveObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.hasNativeScrollPhaseMonitor { return }
                if !self.isScrollPhaseActive {
                    self.extendScrollDebounceIfScrolling(debounceNanoseconds: 55_000_000)
                }
            }
        }
        notificationObservers.append(didEndLiveObserver)

        // Clear hover when opening a modal window or switching to another app
        let resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pointerCandidateTrackId = nil
                self?.clear(resetScreenPoint: true)
            }
        }
        notificationObservers.append(resignKeyObserver)

        let becomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                NSApp.keyWindow?.acceptsMouseMovedEvents = true
                self?.forceNextResolve = true
                self?.scheduleHoverResolve()
            }
        }
        notificationObservers.append(becomeKeyObserver)

        // Clear hover when opening a context menu, resolve when closing
        let menuBeginObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clear(resetScreenPoint: true)
            }
        }
        notificationObservers.append(menuBeginObserver)

        let menuEndObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.forceNextResolve = true
                self?.scheduleHoverResolve()
            }
        }
        notificationObservers.append(menuEndObserver)

        // 2. Local AppKit event monitor for scrollWheel, mouseMoved, and mouseExited
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .mouseMoved, .mouseExited]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }

                switch event.type {
                case .mouseMoved:
                    if !self.anchors.isEmpty {
                        if self.isScrollPhaseActive {
                            break
                        }
                        if self.isScrolling {
                            // Pointer movement ends scroll suppression only if mouse moved significantly and at least 120ms passed
                            if (abs(event.deltaX) > 2.0 || abs(event.deltaY) > 2.0) &&
                               (DispatchTime.now().uptimeNanoseconds &- self.lastScrollEventNanos >= 120_000_000) {
                                self.notifyScrollEnded()
                            }
                        } else {
                            self.scheduleHoverResolve()
                        }
                    } else {
                        // Fallback when no AppKit anchors are registered
                        if !self.isScrolling && (self.hoveredTrackId != nil || self.pointerCandidateTrackId == nil) {
                            break
                        }
                        if self.isScrolling {
                            if abs(event.deltaX) > 1.0 || abs(event.deltaY) > 1.0 {
                                self.notifyScrollEnded()
                            }
                        } else if self.hoveredTrackId == nil, let candidate = self.pointerCandidateTrackId {
                            self.setHovered(candidate)
                        }
                    }

                case .mouseExited:
                    if event.window == nil {
                        self.pointerCandidateTrackId = nil
                        self.clear(resetScreenPoint: true)
                    } else if let app = NSApp,
                              let activeWindow = app.keyWindow ?? app.mainWindow,
                              event.window === activeWindow,
                              !activeWindow.frame.contains(NSEvent.mouseLocation) {
                        self.pointerCandidateTrackId = nil
                        self.clear(resetScreenPoint: true)
                    }

                case .scrollWheel:
                    if self.hasNativeScrollPhaseMonitor {
                        self.lastScrollEventNanos = DispatchTime.now().uptimeNanoseconds
                        break
                    }

                    if self.visibleRowCounts.isEmpty && self.anchors.isEmpty && self.hoveredTrackId == nil {
                        break
                    }

                    if self.isScrollPhaseActive {
                        self.lastScrollEventNanos = DispatchTime.now().uptimeNanoseconds
                        break
                    }

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
                        self.extendScrollDebounceIfScrolling(debounceNanoseconds: 90_000_000)
                    } else if isDiscreteWheel {
                        if hasSignificantDelta {
                            self.notifyScrollActivity(debounceNanoseconds: 110_000_000)
                        }
                    } else if isActiveGesture {
                        if hasSignificantDelta {
                            self.notifyScrollActivity(debounceNanoseconds: 110_000_000)
                        } else if hasAnyDelta {
                            self.extendScrollDebounceIfScrolling(debounceNanoseconds: 110_000_000)
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

public extension View {
    @ViewBuilder
    func ymTrackHoverScroll() -> some View {
        if #available(macOS 15.0, *) {
            self.onScrollPhaseChange { _, newPhase in
                TrackHoverManager.shared.setScrollPhaseActive(newPhase != .idle)
            }
        } else {
            self
        }
    }
}
