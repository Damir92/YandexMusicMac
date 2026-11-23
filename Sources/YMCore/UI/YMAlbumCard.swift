import SwiftUI

/// Elegant poster-style card for albums and singles with hover zoom, play overlay, and metadata.
public struct YMAlbumCard: View {
    public let album: YMAlbum
    public let onPlay: (() -> Void)?
    public let onSelect: (() -> Void)?

    @UIState private var isHovered = false

    public init(
        album: YMAlbum,
        onPlay: (() -> Void)? = nil,
        onSelect: (() -> Void)? = nil
    ) {
        self.album = album
        self.onPlay = onPlay
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    CachedCoverImage(
                        coverUri: album.coverUri,
                        size: .medium,
                        displaySize: 150,
                        cornerRadius: YMTheme.cornerRadiusMedium
                    )
                    .scaleEffect(isHovered ? 1.05 : 1.0)

                    if isHovered {
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.42)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .transition(.opacity)
                        .allowsHitTesting(false)
                    }
                }
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: YMTheme.cornerRadiusMedium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: YMTheme.cornerRadiusMedium, style: .continuous)
                        .strokeBorder(isHovered ? YMTheme.borderHover : YMTheme.border, lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .shadow(
                    color: YMTheme.shadowColor,
                    radius: isHovered ? 12 : 3,
                    y: isHovered ? 6 : 1
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)

                // Play button overlay on hover
                if isHovered, let onPlay = onPlay {
                    Button {
                        onPlay()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(YMTheme.accent))
                            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isHovered ? YMTheme.accent : YMTheme.fg)
                    .lineLimit(1)

                if let artists = album.artists, !artists.isEmpty {
                    Text(artists.map(\.name).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(YMTheme.fg60)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 4) {
                        if let year = album.year {
                            Text(String(year))
                        }
                        if let genre = album.genre, !genre.isEmpty {
                            Text("· \(genre.capitalized)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(YMTheme.fg40)
                    .lineLimit(1)
                }
            }
            .frame(width: 150, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?()
        }
        .onHover { inside in
            if inside && TrackHoverManager.shared.isScrollSuppressed { return }
            if isHovered != inside { isHovered = inside }
        }
        .onDisappear {
            if isHovered { isHovered = false }
        }
        .accessibilityAddTraits(.isButton)
    }
}

/// Circular avatar card for artists with name and hover scale.
public struct YMArtistCard: View {
    public let artist: YMArtist
    public let onSelect: (() -> Void)?

    @UIState private var isHovered = false

    public init(artist: YMArtist, onSelect: (() -> Void)? = nil) {
        self.artist = artist
        self.onSelect = onSelect
    }

    public var body: some View {
        Button {
            onSelect?()
        } label: {
            VStack(spacing: 6) {
                CachedCoverImage(
                    coverUri: artist.coverUri,
                    size: .medium,
                    displaySize: 104,
                    cornerRadius: 52
                )
                .frame(width: 104, height: 104)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(isHovered ? YMTheme.accent : YMTheme.border, lineWidth: isHovered ? 2.5 : 1)
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .shadow(color: isHovered ? YMTheme.accent.opacity(0.3) : Color.black.opacity(0.15), radius: isHovered ? 12 : 6, y: 3)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
                .padding(.top, 18)
                .padding(.bottom, 10)

                VStack(spacing: 2) {
                    Text(artist.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isHovered ? YMTheme.accent : YMTheme.fg)
                        .lineLimit(1)

                    Text("Исполнитель")
                        .font(.caption2)
                        .foregroundStyle(YMTheme.fg40)
                }
                .frame(width: 114)
            }
            .contentShape(Rectangle())
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
