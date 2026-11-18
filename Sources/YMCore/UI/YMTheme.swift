import SwiftUI
import AppKit

/// Structured color palette for each application theme, ensuring balanced contrast,
/// cohesive surfaces, and soft hierarchy across dark and light variants.
public struct YMThemePalette: Sendable {
    public let isLight: Bool
    public let bg: Color
    public let sidebarBg: Color
    public let playerBg: Color
    public let surface: Color
    public let surfaceHigh: Color
    public let surfaceComponent: Color
    public let surfaceComponentHover: Color
    public let border: Color
    public let borderHover: Color
    public let fg: Color
    public let fg80: Color
    public let fg60: Color
    public let fg40: Color
    public let accent: Color
    public let shadowColor: Color
    public let playerBarShadow: Color

    /// Soft graphite dark theme (#141519) with warm gold accent (#F2C12E)
    public static let graphite = YMThemePalette(
        isLight: false,
        bg: Color(red: 20 / 255, green: 21 / 255, blue: 25 / 255),             // #141519
        sidebarBg: Color(red: 24 / 255, green: 25 / 255, blue: 30 / 255),      // #18191E
        playerBg: Color(red: 22 / 255, green: 24 / 255, blue: 29 / 255),       // #16181D
        surface: Color(red: 30 / 255, green: 32 / 255, blue: 38 / 255),        // #1E2026
        surfaceHigh: Color(red: 39 / 255, green: 42 / 255, blue: 50 / 255),    // #272A32
        surfaceComponent: Color.white.opacity(0.07),
        surfaceComponentHover: Color.white.opacity(0.13),
        border: Color.white.opacity(0.07),
        borderHover: Color.white.opacity(0.18),
        fg: Color(red: 242 / 255, green: 243 / 255, blue: 247 / 255),          // #F2F3F7
        fg80: Color(red: 242 / 255, green: 243 / 255, blue: 247 / 255).opacity(0.80),
        fg60: Color(red: 242 / 255, green: 243 / 255, blue: 247 / 255).opacity(0.60),
        fg40: Color(red: 242 / 255, green: 243 / 255, blue: 247 / 255).opacity(0.42),
        accent: Color(red: 242 / 255, green: 193 / 255, blue: 46 / 255),       // #F2C12E
        shadowColor: Color.black.opacity(0.32),
        playerBarShadow: Color.black.opacity(0.42)
    )

    /// Deep muted slate-blue night theme (#111622) with warm gold accent (#F5C43D)
    public static let midnight = YMThemePalette(
        isLight: false,
        bg: Color(red: 17 / 255, green: 22 / 255, blue: 34 / 255),             // #111622
        sidebarBg: Color(red: 21 / 255, green: 27 / 255, blue: 41 / 255),      // #151B29
        playerBg: Color(red: 19 / 255, green: 25 / 255, blue: 38 / 255),       // #131926
        surface: Color(red: 27 / 255, green: 34 / 255, blue: 52 / 255),        // #1B2234
        surfaceHigh: Color(red: 35 / 255, green: 44 / 255, blue: 66 / 255),    // #232C42
        surfaceComponent: Color(red: 195 / 255, green: 214 / 255, blue: 255 / 255).opacity(0.08),
        surfaceComponentHover: Color(red: 195 / 255, green: 214 / 255, blue: 255 / 255).opacity(0.15),
        border: Color(red: 205 / 255, green: 220 / 255, blue: 255 / 255).opacity(0.07),
        borderHover: Color(red: 205 / 255, green: 220 / 255, blue: 255 / 255).opacity(0.20),
        fg: Color(red: 238 / 255, green: 242 / 255, blue: 250 / 255),          // #EEF2FA
        fg80: Color(red: 238 / 255, green: 242 / 255, blue: 250 / 255).opacity(0.82),
        fg60: Color(red: 210 / 255, green: 220 / 255, blue: 242 / 255).opacity(0.62),
        fg40: Color(red: 195 / 255, green: 208 / 255, blue: 235 / 255).opacity(0.44),
        accent: Color(red: 245 / 255, green: 196 / 255, blue: 61 / 255),       // #F5C43D
        shadowColor: Color(red: 4 / 255, green: 8 / 255, blue: 18 / 255).opacity(0.38),
        playerBarShadow: Color(red: 4 / 255, green: 8 / 255, blue: 18 / 255).opacity(0.46)
    )

    /// Airy warm alabaster light theme (#F4F3EF) with amber accent (#C47600)
    public static let light = YMThemePalette(
        isLight: true,
        bg: Color(red: 244 / 255, green: 243 / 255, blue: 239 / 255),          // #F4F3EF
        sidebarBg: Color(red: 234 / 255, green: 232 / 255, blue: 226 / 255),   // #EAE8E2
        playerBg: Color(red: 247 / 255, green: 246 / 255, blue: 242 / 255),    // #F7F6F2
        surface: Color(red: 255 / 255, green: 255 / 255, blue: 255 / 255),     // #FFFFFF
        surfaceHigh: Color(red: 228 / 255, green: 225 / 255, blue: 218 / 255), // #E4E1DA
        surfaceComponent: Color(red: 28 / 255, green: 27 / 255, blue: 25 / 255).opacity(0.06),
        surfaceComponentHover: Color(red: 28 / 255, green: 27 / 255, blue: 25 / 255).opacity(0.11),
        border: Color(red: 28 / 255, green: 27 / 255, blue: 25 / 255).opacity(0.08),
        borderHover: Color(red: 28 / 255, green: 27 / 255, blue: 25 / 255).opacity(0.18),
        fg: Color(red: 28 / 255, green: 27 / 255, blue: 25 / 255),             // #1C1B19
        fg80: Color(red: 66 / 255, green: 64 / 255, blue: 61 / 255),
        fg60: Color(red: 112 / 255, green: 109 / 255, blue: 104 / 255),
        fg40: Color(red: 152 / 255, green: 149 / 255, blue: 143 / 255),
        accent: Color(red: 196 / 255, green: 118 / 255, blue: 0 / 255),        // #C47600
        shadowColor: Color(red: 30 / 255, green: 25 / 255, blue: 20 / 255).opacity(0.07),
        playerBarShadow: Color(red: 30 / 255, green: 25 / 255, blue: 20 / 255).opacity(0.06)
    )

    /// Soft cream-sand light theme (#EDE7DC) with warm terracotta-amber accent (#B86214)
    public static let latte = YMThemePalette(
        isLight: true,
        bg: Color(red: 237 / 255, green: 231 / 255, blue: 220 / 255),          // #EDE7DC
        sidebarBg: Color(red: 227 / 255, green: 219 / 255, blue: 205 / 255),   // #E3DBCD
        playerBg: Color(red: 242 / 255, green: 236 / 255, blue: 226 / 255),    // #F2ECE2
        surface: Color(red: 247 / 255, green: 243 / 255, blue: 235 / 255),     // #F7F3EB
        surfaceHigh: Color(red: 221 / 255, green: 212 / 255, blue: 196 / 255), // #DDD4C4
        surfaceComponent: Color(red: 46 / 255, green: 36 / 255, blue: 24 / 255).opacity(0.07),
        surfaceComponentHover: Color(red: 46 / 255, green: 36 / 255, blue: 24 / 255).opacity(0.13),
        border: Color(red: 46 / 255, green: 36 / 255, blue: 24 / 255).opacity(0.08),
        borderHover: Color(red: 46 / 255, green: 36 / 255, blue: 24 / 255).opacity(0.20),
        fg: Color(red: 38 / 255, green: 32 / 255, blue: 26 / 255),             // #26201A
        fg80: Color(red: 78 / 255, green: 68 / 255, blue: 58 / 255),
        fg60: Color(red: 122 / 255, green: 109 / 255, blue: 95 / 255),
        fg40: Color(red: 158 / 255, green: 145 / 255, blue: 130 / 255),
        accent: Color(red: 184 / 255, green: 98 / 255, blue: 20 / 255),        // #B86214
        shadowColor: Color(red: 46 / 255, green: 34 / 255, blue: 20 / 255).opacity(0.08),
        playerBarShadow: Color(red: 46 / 255, green: 34 / 255, blue: 20 / 255).opacity(0.07)
    )
}

/// Modern theme and visual design tokens backed by `YMThemePalette` across all 5 app themes.
@MainActor
public enum YMTheme {
    private static var isSystemAppearanceLight: Bool {
        if let appearance = NSApp?.effectiveAppearance {
            return appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        }
        return false
    }

    /// Resolves the concrete color palette for any given `YMAppTheme`.
    public static func palette(for theme: YMAppTheme) -> YMThemePalette {
        switch theme {
        case .system:
            return isSystemAppearanceLight ? .light : .graphite
        case .dark:
            return .graphite
        case .midnight:
            return .midnight
        case .light:
            return .light
        case .latte:
            return .latte
        }
    }

    /// Active palette for the currently selected theme.
    public static var palette: YMThemePalette {
        palette(for: YMThemeManager.shared.currentTheme)
    }

    /// Whether the active theme is a light palette (`.light`, `.latte`, or light `.system`).
    public static var isLight: Bool {
        palette.isLight
    }

    // MARK: - Backgrounds

    public static var bg: Color { palette.bg }
    public static var sidebarBg: Color { palette.sidebarBg }
    public static var playerBg: Color { palette.playerBg }
    public static var surface: Color { palette.surface }
    public static var surfaceHigh: Color { palette.surfaceHigh }
    public static var surfaceComponent: Color { palette.surfaceComponent }
    public static var surfaceComponentHover: Color { palette.surfaceComponentHover }

    // MARK: - Borders & Dividers

    public static var border: Color { palette.border }
    public static var borderHover: Color { palette.borderHover }

    // MARK: - Typography & Glyphs

    public static var fg: Color { palette.fg }
    public static var fg80: Color { palette.fg80 }
    public static var fg60: Color { palette.fg60 }
    public static var fg40: Color { palette.fg40 }

    // MARK: - Brand Accents

    /// Dynamic brand accent for text, icons, progress bars, and outlines.
    public static var accent: Color { palette.accent }

    /// Softened warm-gold fill (#F5C428) for primary action discs/pills (Play button, "Слушать всё").
    /// Foreground inside must always be Color.black!
    public static let accentFill = Color(red: 245 / 255, green: 196 / 255, blue: 40 / 255)

    public static let heartRed = Color(red: 238 / 255, green: 68 / 255, blue: 78 / 255)

    // MARK: - Dynamic Shadows

    public static var shadowColor: Color { palette.shadowColor }
    public static var playerBarShadow: Color { palette.playerBarShadow }

    public static let cornerRadiusLarge: CGFloat = 14
    public static let cornerRadiusMedium: CGFloat = 10
    public static let cornerRadiusSmall: CGFloat = 6
}

// MARK: - Ambient Blurred Cover Glow (RAM-safe .small 100x100)

/// Subtle atmospheric cover-art glow backed strictly by `YMCoverSize.small` (100x100)
/// to preserve the strict 40–65 MB RAM budget while blending smoothly into `YMTheme.bg`.
public struct YMAmbientCoverGlowModifier: ViewModifier {
    let coverUri: String?
    let opacity: Double

    @UIState private var glowImage: NSImage? = nil

    public init(coverUri: String?, opacity: Double = 0.22) {
        self.coverUri = coverUri
        self.opacity = opacity
    }

    public func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if let image = glowImage {
                        GeometryReader { geo in
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .scaleEffect(1.3)
                                .blur(radius: 56)
                                .opacity(YMTheme.isLight ? opacity * 0.78 : opacity)
                                .mask(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .black, location: 0.0),
                                            .init(color: .black.opacity(0.65), location: 0.50),
                                            .init(color: .clear, location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .clipped()
                        }
                        .animation(.easeInOut(duration: 0.35), value: coverUri)
                    }
                }
                .allowsHitTesting(false)
            }
            .task(id: coverUri ?? "") {
                guard let uri = coverUri, !uri.isEmpty else {
                    glowImage = nil
                    return
                }
                let fetched = await ImagePipeline.shared.image(for: uri, size: .small)
                guard !Task.isCancelled else { return }
                glowImage = fetched
            }
    }
}

// MARK: - Glass & Translucency Modifiers

public struct YMGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?

    public func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(tint ?? YMTheme.surfaceComponent)
                    shape.stroke(YMTheme.border, lineWidth: 1)
                }
            }
    }
}

public extension View {
    func ymGlass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(YMGlassModifier(shape: shape, interactive: interactive, tint: tint))
    }

    func ymGlassCapsule(interactive: Bool = false, tint: Color? = nil) -> some View {
        ymGlass(in: Capsule(), interactive: interactive, tint: tint)
    }

    func ymScreenBackground() -> some View {
        background(YMTheme.bg.ignoresSafeArea())
    }

    func ymAmbientCoverGlow(coverUri: String?, opacity: Double = 0.22) -> some View {
        modifier(YMAmbientCoverGlowModifier(coverUri: coverUri, opacity: opacity))
    }
}

// MARK: - Interactive Card Hover Modifier

public struct YMCardHoverModifier: ViewModifier {
    @UIState private var isHovered = false
    let cornerRadius: CGFloat
    let scale: CGFloat

    public init(cornerRadius: CGFloat = YMTheme.cornerRadiusMedium, scale: CGFloat = 1.04) {
        self.cornerRadius = cornerRadius
        self.scale = scale
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isHovered ? YMTheme.borderHover : Color.clear, lineWidth: 1)
            }
            .shadow(
                color: YMTheme.shadowColor,
                radius: isHovered ? 12 : 3,
                y: isHovered ? 6 : 1
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
            .onHover { inside in
                isHovered = inside
            }
    }
}

public extension View {
    func ymCardHover(cornerRadius: CGFloat = YMTheme.cornerRadiusMedium, scale: CGFloat = 1.03) -> some View {
        modifier(YMCardHoverModifier(cornerRadius: cornerRadius, scale: scale))
    }
}

// MARK: - Buttons

/// Glass pill button with hover scaling and icon
public struct YMGlassPillButtonStyle: ButtonStyle {
    public var primary: Bool = false
    public var height: CGFloat = 32

    @UIState private var hover = false

    public init(primary: Bool = false, height: CGFloat = 32) {
        self.primary = primary
        self.height = height
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(primary ? Color.black : YMTheme.fg)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background {
                if primary {
                    Capsule()
                        .fill(hover ? YMTheme.accentFill.opacity(0.90) : YMTheme.accentFill)
                        .shadow(color: YMTheme.accentFill.opacity(hover ? 0.24 : 0.12), radius: 8, y: 2)
                } else {
                    Capsule()
                        .fill(hover ? YMTheme.surfaceComponentHover : YMTheme.surfaceComponent)
                        .overlay(Capsule().strokeBorder(YMTheme.border, lineWidth: 1))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : hover ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hover)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .onHover { hover = $0 }
    }
}
