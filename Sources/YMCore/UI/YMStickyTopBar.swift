import SwiftUI
import AppKit

// MARK: - Native macOS Window Drag Handle

/// AppKit drag surface that initiates native macOS window dragging on mouse down
/// and standard macOS titlebar zoom on double click.
/// Placed in `.background(...)` behind interactive controls so buttons remain 100% clickable.
public struct YMWindowDragHandle: NSViewRepresentable {
    public var allowsDoubleClickZoom: Bool
    public init(allowsDoubleClickZoom: Bool = true) {
        self.allowsDoubleClickZoom = allowsDoubleClickZoom
    }
    public func makeNSView(context: Context) -> YMWindowDragNSView {
        let view = YMWindowDragNSView()
        view.allowsDoubleClickZoom = allowsDoubleClickZoom
        return view
    }
    public func updateNSView(_ nsView: YMWindowDragNSView, context: Context) {
        nsView.allowsDoubleClickZoom = allowsDoubleClickZoom
    }
}

public final class YMWindowDragNSView: NSView {
    public var allowsDoubleClickZoom: Bool = true
    public override var mouseDownCanMoveWindow: Bool { false }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override func mouseDown(with event: NSEvent) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        if event.clickCount == 2 {
            guard allowsDoubleClickZoom else { return }
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "None":
                return
            case "Minimize":
                window.performMiniaturize(nil)
            default:
                window.performZoom(nil)
            }
        } else {
            window.performDrag(with: event)
        }
    }
}

public extension View {
    @ViewBuilder
    func ymTrackScrollOffset(threshold: CGFloat, isScrolled: Binding<Bool>) -> some View {
        if #available(macOS 15.0, *) {
            self.onScrollGeometryChange(for: Bool.self) { geo in
                let y = geo.contentOffset.y + geo.contentInsets.top
                let hysteresis: CGFloat = 6
                return isScrolled.wrappedValue
                    ? (y > threshold - hysteresis)
                    : (y > threshold + hysteresis)
            } action: { _, newValue in
                if isScrolled.wrappedValue != newValue {
                    isScrolled.wrappedValue = newValue
                }
            }
            .ymTrackHoverScroll()
        } else {
            self
        }
    }
}

// MARK: - Zero-Overhead Scroll Threshold Sentinel (120 FPS)

/// Zero-height sentinel placed at the top of a `ScrollView`'s content stack.
/// Uses hysteresis and `.onChange(of: Bool)` so the parent view only redraws ONCE
/// when crossing the threshold — zero SwiftUI invalidations during continuous scrolling.
public struct YMScrollTopSentinel: View {
    let coordinateSpaceName: String
    let threshold: CGFloat
    @Binding var isScrolled: Bool

    public init(
        coordinateSpaceName: String,
        threshold: CGFloat = 60,
        isScrolled: Binding<Bool>
    ) {
        self.coordinateSpaceName = coordinateSpaceName
        self.threshold = threshold
        self._isScrolled = isScrolled
    }

    public var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named(coordinateSpaceName)).minY
            let hysteresis: CGFloat = 6
            let nextScrolled = isScrolled
                ? (minY < -(threshold - hysteresis))
                : (minY < -(threshold + hysteresis))

            Color.clear
                .onChange(of: nextScrolled) { _, newValue in
                    if isScrolled != newValue {
                        isScrolled = newValue
                    }
                }
                .onAppear {
                    let initial = geo.frame(in: .named(coordinateSpaceName)).minY < -threshold
                    if isScrolled != initial {
                        isScrolled = initial
                    }
                }
        }
        .frame(height: 0)
    }
}

// MARK: - Compact Sticky Top Bar (For Main Sections)

/// Sleek, compact macOS floating top bar (`42 pt`) that appears smoothly with frosted glass
/// when the user scrolls down past a screen's hero header, and provides a native draggable
/// titlebar area to easily move the app window around the desktop.
public struct YMStickyTopBar: View {
    public let title: String
    public var showLiveDot: Bool = false
    public let isVisible: Bool

    @UIState private var windowState = WindowState.shared

    public init(title: String, showLiveDot: Bool = false, isVisible: Bool) {
        self.title = title
        self.showLiveDot = showLiveDot
        self.isVisible = isVisible
    }

    public var body: some View {
        let height: CGFloat = isVisible ? 42 : (windowState.needsTopChromeClearance ? 44 : 24)

        ZStack(alignment: .topLeading) {
            // 1. Frosted glass background layer strictly non-hit-testing
            if isVisible {
                ZStack(alignment: .bottom) {
                    VisualEffectBlur(
                        material: .headerView,
                        blendingMode: .withinWindow,
                        state: .followsWindowActiveState
                    )
                    YMTheme.bg.opacity(YMTheme.isLight ? 0.78 : 0.74)
                    YMTheme.border.frame(height: 1)
                }
                .frame(height: 42)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(.container, edges: .top)
                .shadow(color: YMTheme.shadowColor.opacity(0.45), radius: 8, y: 2)
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            // 2. Window Drag Handle on top of background
            YMWindowDragHandle()
                .frame(maxWidth: .infinity)
                .frame(height: height)

            // 3. Compact sticky bar title & badge on top of drag handle, strictly non-hit-testing
            if isVisible {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(YMTheme.fg)
                        .lineLimit(1)

                    if showLiveDot {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(YMTheme.accent)
                                .frame(width: 6, height: 6)
                            Text("в эфире")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(YMTheme.accent)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(YMTheme.accent.opacity(0.14)))
                    }

                    Spacer(minLength: 8)
                }
                .padding(.leading, windowState.topToolbarLeadingInset)
                .padding(.trailing, 24)
                .frame(height: 42)
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .offset(y: -6)))
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.22), value: isVisible)
    }
}

// MARK: - Sticky Detail Top Bar (With Pinned Back Button & Animated Title)

/// Compact pinned navigation header for detail views (Album, Artist, Playlist Detail).
/// Keeps the "Назад" button always accessible and the entire bar draggable,
/// while fading in the frosted glass backdrop and compact title smoothly on scroll.
public struct YMStickyDetailTopBar: View {
    public let backTitle: String
    public let title: String
    public let isScrolled: Bool
    public let onBack: () -> Void

    @UIState private var windowState = WindowState.shared

    public init(
        backTitle: String = "Назад",
        title: String,
        isScrolled: Bool,
        onBack: @escaping () -> Void
    ) {
        self.backTitle = backTitle
        self.title = title
        self.isScrolled = isScrolled
        self.onBack = onBack
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text(backTitle)
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(YMTheme.fg)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(YMTheme.surfaceComponent))
                .overlay(Capsule().strokeBorder(YMTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("[", modifiers: .command)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(YMTheme.fg)
                .lineLimit(1)
                .allowsHitTesting(false)
                .opacity(isScrolled ? 1 : 0)
                .offset(y: isScrolled ? 0 : 4)
                .animation(.easeOut(duration: 0.20), value: isScrolled)

            Spacer(minLength: 8)
        }
        .padding(.leading, windowState.topToolbarLeadingInset)
        .padding(.trailing, 24)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background {
            ZStack(alignment: .bottom) {
                if isScrolled {
                    ZStack(alignment: .bottom) {
                        VisualEffectBlur(
                            material: .headerView,
                            blendingMode: .withinWindow,
                            state: .followsWindowActiveState
                        )
                        YMTheme.bg.opacity(YMTheme.isLight ? 0.78 : 0.74)
                        YMTheme.border.frame(height: 1)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }

                YMWindowDragHandle()
            }
            .ignoresSafeArea(.container, edges: .top)
            .animation(.easeOut(duration: 0.20), value: isScrolled)
        }
        .shadow(color: YMTheme.shadowColor.opacity(isScrolled ? 0.40 : 0), radius: 8, y: 2)
    }
}
