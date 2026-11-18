import SwiftUI
import AppKit

// MARK: - Native macOS Window Drag Handle

/// AppKit drag surface that initiates native macOS window dragging on mouse down
/// and standard macOS titlebar zoom on double click.
/// Placed in `.background(...)` behind interactive controls so buttons remain 100% clickable.
public struct YMWindowDragHandle: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> YMWindowDragNSView {
        YMWindowDragNSView()
    }

    public func updateNSView(_ nsView: YMWindowDragNSView, context: Context) {}
}

public final class YMWindowDragNSView: NSView {
    public override var mouseDownCanMoveWindow: Bool { true }

    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
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
                        withAnimation(.easeOut(duration: 0.22)) {
                            isScrolled = newValue
                        }
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
        ZStack(alignment: .top) {
            // Subtle top-edge drag strip when scrolled to top (does not block buttons lower down)
            if !isVisible {
                YMWindowDragHandle()
                    .frame(maxWidth: .infinity)
                    .frame(height: windowState.needsTopChromeClearance ? 44 : 24)
            }

            // Compact frosted glass sticky bar when scrolled past hero
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
            .allowsHitTesting(false)
            .padding(.leading, windowState.topToolbarLeadingInset)
            .padding(.trailing, 24)
            .frame(height: 42)
            .frame(maxWidth: .infinity)
            .background {
                ZStack(alignment: .bottom) {
                    VisualEffectBlur(material: .headerView, blendingMode: .withinWindow)
                    YMTheme.bg.opacity(YMTheme.isLight ? 0.78 : 0.74)
                    YMWindowDragHandle()
                    YMTheme.border.frame(height: 1)
                }
                .ignoresSafeArea(.container, edges: .top)
            }
            .shadow(color: YMTheme.shadowColor.opacity(isVisible ? 0.45 : 0), radius: 8, y: 2)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : -6)
            .allowsHitTesting(isVisible)
            .animation(.easeOut(duration: 0.22), value: isVisible)
        }
        .frame(maxWidth: .infinity, alignment: .top)
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
                    VisualEffectBlur(material: .headerView, blendingMode: .withinWindow)
                        .transition(.opacity)
                    YMTheme.bg.opacity(YMTheme.isLight ? 0.78 : 0.74)
                        .transition(.opacity)
                }
                YMWindowDragHandle()
                if isScrolled {
                    YMTheme.border
                        .frame(height: 1)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            .animation(.easeOut(duration: 0.20), value: isScrolled)
        }
        .shadow(color: YMTheme.shadowColor.opacity(isScrolled ? 0.40 : 0), radius: 8, y: 2)
    }
}
