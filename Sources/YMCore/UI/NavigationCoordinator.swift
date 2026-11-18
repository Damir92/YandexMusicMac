import SwiftUI

public enum AppRoute: Hashable, Sendable {
    case artist(id: String, name: String)
    case album(id: String, title: String)
}

/// Preferred position for displaying synchronized song lyrics
public enum YMLyricsPosition: String, CaseIterable, Identifiable, Sendable {
    case right = "right"                 // Справа
    case abovePlayer = "abovePlayer"     // Над плеером

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .right: return "Справа"
        case .abovePlayer: return "Над плеером"
        }
    }

    public var subtitle: String {
        switch self {
        case .right: return "Боковая панель с полной прокруткой текста"
        case .abovePlayer: return "Компактная полоса над плеером (3 строки)"
        }
    }
}

/// Centralized app navigation coordinator managing deep links, detail views, lyrics and sub-flows.
@Observable
public final class NavigationCoordinator: @unchecked Sendable {
    public static let shared = NavigationCoordinator()

    public var path: [AppRoute] = []
    public var selectedSection: SidebarSection = .myWave
    public var isLyricsPresented: Bool = false
    public var isEqualizerPresented: Bool = false
    public var lyricsTrack: YMTrack? = nil
    public var activeSimilarTrack: YMTrack? = nil

    public var lyricsPosition: YMLyricsPosition = {
        if let raw = UserDefaults.standard.string(forKey: "ym_lyrics_position"),
           let pos = YMLyricsPosition(rawValue: raw) {
            return pos
        }
        return .right
    }() {
        didSet {
            UserDefaults.standard.set(lyricsPosition.rawValue, forKey: "ym_lyrics_position")
        }
    }

    public init() {}

    public func showLyrics(for track: YMTrack? = nil) {
        self.lyricsTrack = track
        self.isLyricsPresented = true
    }

    public var canGoBack: Bool {
        !path.isEmpty
    }

    public func selectSection(_ section: SidebarSection) {
        self.selectedSection = section
        popToRoot()
        dismissFullscreenLyricsIfNeeded()
    }

    public func navigate(to route: AppRoute) {
        path.append(route)
        dismissFullscreenLyricsIfNeeded()
    }

    /// Closes the fullscreen "Now Playing" lyrics overlay (`.right`) when navigating to a menu section or detail screen,
    /// while preserving the user's preferred `lyricsPosition` setting and keeping compact `.abovePlayer` lyrics open.
    private func dismissFullscreenLyricsIfNeeded() {
        if isLyricsPresented && lyricsPosition == .right {
            isLyricsPresented = false
            lyricsTrack = nil
        }
    }

    public func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    public func popToRoot() {
        path.removeAll()
    }
}
