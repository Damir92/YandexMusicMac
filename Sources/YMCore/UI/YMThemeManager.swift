import SwiftUI
import AppKit

public enum YMAppTheme: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case dark = "dark"
    case midnight = "midnight"
    case light = "light"
    case latte = "latte"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "Системная"
        case .dark: return "Графитовая"
        case .midnight: return "Полночь"
        case .light: return "Светлая"
        case .latte: return "Тёплый песок"
        }
    }

    public var subtitle: String {
        switch self {
        case .system: return "Автоматически повторяет оформление macOS"
        case .dark: return "Мягкая графитовая тёмная палитра с тёплым золотом"
        case .midnight: return "Глубокий сине-сланцевый вечерний интерфейс"
        case .light: return "Воздушный тёплый алебастр с янтарным акцентом"
        case .latte: return "Кремово-песочные тона и терракотовый акцент"
        }
    }

    public var iconName: String {
        switch self {
        case .system: return "circle.righthalf.filled"
        case .dark: return "moon.fill"
        case .midnight: return "moon.stars.fill"
        case .light: return "sun.max.fill"
        case .latte: return "cup.and.saucer.fill"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark, .midnight: return .dark
        case .light, .latte: return .light
        }
    }
}

/// Centralized application theme manager with UserDefaults persistence
/// and real-time AppKit window appearance synchronization.
@MainActor
@Observable
public final class YMThemeManager {
    public static let shared = YMThemeManager()

    private let themeKey = "ym_app_theme_preference"

    public private(set) var resolvedPalette: YMThemePalette = .graphite

    @ObservationIgnored private var distributedObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?

    public var currentTheme: YMAppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: themeKey)
            updateWindowAppearance()
        }
    }

    public init() {
        if let saved = UserDefaults.standard.string(forKey: themeKey),
           let theme = YMAppTheme(rawValue: saved) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .dark
        }
        refreshResolvedPalette()

        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.updateWindowAppearance()
                DispatchQueue.main.async {
                    self.refreshResolvedPalette()
                }
            }
        }

        if let app = NSApp {
            appearanceObservation = app.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    if self.currentTheme == .system {
                        self.refreshResolvedPalette()
                    }
                }
            }
        }
        // Do not call updateWindowAppearance() here:
        // YMThemeManager.shared is accessed during App.init, before NSApplication is fully running.
        // AppDelegate calls updateWindowAppearance() on launch once windows are ready.
    }

    public func cleanup() {
        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
            self.distributedObserver = nil
        }
        appearanceObservation?.invalidate()
        appearanceObservation = nil
    }

    public func refreshResolvedPalette() {
        let next = YMTheme.palette(for: currentTheme)
        if resolvedPalette != next {
            resolvedPalette = next
        }
    }

    public func setTheme(_ theme: YMAppTheme) {
        self.currentTheme = theme
    }

    public func updateWindowAppearance() {
        guard let app = NSApp else {
            refreshResolvedPalette()
            return
        }

        if appearanceObservation == nil {
            appearanceObservation = app.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    if self.currentTheme == .system {
                        self.refreshResolvedPalette()
                    }
                }
            }
        }

        let appKitAppearance: NSAppearance? = switch currentTheme {
        case .system: nil
        case .dark, .midnight: NSAppearance(named: .darkAqua)
        case .light, .latte: NSAppearance(named: .aqua)
        }

        if app.appearance?.name != appKitAppearance?.name {
            app.appearance = appKitAppearance
        }
        for window in app.windows where !(window is NSPanel) {
            if window.appearance?.name != appKitAppearance?.name {
                window.appearance = appKitAppearance
            }
        }
        refreshResolvedPalette()
    }
}
