import SwiftUI
import AppKit

// MARK: - Isolated Like Heart Button

/// Isolated heart like button that subscribes to LikesService without re-rendering parent track rows.
public struct YMLikeHeartButton: View {
    public let track: YMTrack
    public var iconSize: CGFloat = 13
    public var buttonWidth: CGFloat = 32

    @UIState private var likesService = LikesService.shared
    @UIState private var isHovered = false

    public init(track: YMTrack, iconSize: CGFloat = 13, buttonWidth: CGFloat = 32) {
        self.track = track
        self.iconSize = iconSize
        self.buttonWidth = buttonWidth
    }

    public var body: some View {
        let isLiked = likesService.isLiked(trackId: track.id)
        Button {
            Task { await likesService.toggleLike(track: track) }
        } label: {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.system(size: iconSize, weight: isLiked ? .semibold : .regular))
                .foregroundStyle(isLiked ? YMTheme.heartRed : (isHovered ? YMTheme.fg80 : YMTheme.fg40))
                .scaleEffect(isHovered ? 1.12 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovered)
                .animation(.spring(response: 0.24, dampingFraction: 0.65), value: isLiked)
        }
        .buttonStyle(.plain)
        .frame(width: buttonWidth, height: 28, alignment: .center)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside && TrackHoverManager.shared.isScrollSuppressed { return }
            if isHovered != inside { isHovered = inside }
        }
        .onDisappear {
            if isHovered { isHovered = false }
        }
        .help(isLiked ? "Удалить из Мне нравится" : "Мне нравится")
    }
}

// MARK: - Isolated Like Context Menu Item

/// Context menu item isolating LikesService subscription
public struct LikeContextMenuItem: View {
    public let track: YMTrack
    @UIState private var likesService = LikesService.shared

    public init(track: YMTrack) {
        self.track = track
    }

    public var body: some View {
        let isLiked = likesService.isLiked(trackId: track.id)
        Button(isLiked ? "Удалить из Мне нравится" : "Добавить в Мне нравится") {
            Task {
                await likesService.toggleLike(track: track)
            }
        }
    }
}

// MARK: - Hover Link Text

/// Lightweight clickable text with hover underline and color transition.
public struct YMHoverLinkText: View {
    public let text: String
    public var font: Font = .system(size: 12)
    public var baseColor: Color = YMTheme.fg60
    public var hoverColor: Color = YMTheme.fg
    public let action: () -> Void

    @UIState private var isHovered = false

    public init(
        text: String,
        font: Font = .system(size: 12),
        baseColor: Color = YMTheme.fg60,
        hoverColor: Color = YMTheme.fg,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.font = font
        self.baseColor = baseColor
        self.hoverColor = hoverColor
        self.action = action
    }

    public var body: some View {
        Button {
            action()
        } label: {
            Text(text)
                .font(font)
                .foregroundStyle(isHovered ? hoverColor : baseColor)
                .underline(isHovered)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside && TrackHoverManager.shared.isScrollSuppressed { return }
            if isHovered != inside { isHovered = inside }
        }
        .onDisappear {
            if isHovered { isHovered = false }
        }
    }
}
