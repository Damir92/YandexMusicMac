import SwiftUI
import AppKit

/// Modern native macOS track list with smooth lazy rendering, column headers,
/// interactive hover & selection cards, instant play buttons, and seamless context menus.
public struct TrackTableView: View {
    public let tracks: [YMTrack]
    public let onPlayTrack: (YMTrack) -> Void
    public var onTrackAppear: ((YMTrack) -> Void)? = nil
    public var onLoadMore: (() -> Void)? = nil
    public var onRemoveFromPlaylist: ((YMTrack, Int) -> Void)? = nil
    public var showHeader: Bool = true
    public var showAlbum: Bool = true

    @UIState private var audioEngine = AudioPlayerEngine.shared
    @UIState private var coordinator = NavigationCoordinator.shared
    @UIState private var windowState = WindowState.shared
    @UIState private var selectedTrackId: String? = nil
    @UIState private var lastClickedTrackId: String? = nil
    @UIState private var lastClickTimestamp: TimeInterval = 0

    public init(
        tracks: [YMTrack],
        onPlayTrack: @escaping (YMTrack) -> Void,
        onTrackAppear: ((YMTrack) -> Void)? = nil,
        onLoadMore: (() -> Void)? = nil,
        onRemoveFromPlaylist: ((YMTrack, Int) -> Void)? = nil,
        showHeader: Bool = true,
        showAlbum: Bool = true
    ) {
        self.tracks = tracks
        self.onPlayTrack = onPlayTrack
        self.onTrackAppear = onTrackAppear
        self.onLoadMore = onLoadMore
        self.onRemoveFromPlaylist = onRemoveFromPlaylist
        self.showHeader = showHeader
        self.showAlbum = showAlbum
    }

    public var body: some View {
        let currentTrackId = audioEngine.currentTrack?.id
        let isEnginePlaying = audioEngine.isPlaying
        let isCompactWidth = windowState.isCompactWidth
        let isMiniWidth = windowState.isMiniWidth

        VStack(spacing: 0) {
            if showHeader && !tracks.isEmpty {
                headerView(isCompactWidth: isCompactWidth, isMiniWidth: isMiniWidth)
                Divider()
                    .overlay(YMTheme.border)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
            }

            LazyVStack(spacing: 2) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    let isCurrent = currentTrackId == track.id
                    ModernTrackRow(
                        track: track,
                        index: index,
                        isCurrentTrack: isCurrent,
                        isPlaying: isCurrent && isEnginePlaying,
                        isSelected: selectedTrackId == track.id,
                        showAlbum: showAlbum,
                        isCompactWidth: isCompactWidth,
                        isMiniWidth: isMiniWidth,
                        onPlay: {
                            selectedTrackId = track.id
                            onPlayTrack(track)
                        },
                        onTapRow: {
                            handleRowTap(track: track)
                        },
                        onArtistSelect: { artist in
                            coordinator.navigate(to: .artist(id: artist.id, name: artist.name))
                        },
                        onAlbumSelect: { album in
                            coordinator.navigate(to: .album(id: album.id, title: album.title))
                        },
                        onShowLyrics: {
                            coordinator.showLyrics(for: track)
                        },
                        onRemoveFromPlaylist: onRemoveFromPlaylist.map { handler in
                            { handler(track, index) }
                        }
                    )
                    .onAppear {
                        onTrackAppear?(track)
                        if index >= tracks.count - 6 {
                            onLoadMore?()
                        }
                    }
                }
            }
        }
    }

    private func handleRowTap(track: YMTrack) {
        let now = ProcessInfo.processInfo.systemUptime
        let clickCount = NSApp?.currentEvent?.clickCount ?? 1
        let isDouble = clickCount >= 2
            || (selectedTrackId == track.id
                && lastClickedTrackId == track.id
                && (now - lastClickTimestamp) <= NSEvent.doubleClickInterval)
        selectedTrackId = track.id
        lastClickedTrackId = track.id
        lastClickTimestamp = now
        if isDouble {
            onPlayTrack(track)
        }
    }

    @ViewBuilder
    private func headerView(isCompactWidth: Bool, isMiniWidth: Bool) -> some View {
        HStack(spacing: isMiniWidth ? 8 : 12) {
            Text("#")
                .frame(width: isMiniWidth ? 28 : 36, alignment: .center)

            Color.clear
                .frame(width: 40, height: 1)

            Text("ТРЕК")
                .frame(minWidth: isMiniWidth ? 100 : 180, alignment: .leading)

            Spacer(minLength: 4)

            if showAlbum && !isCompactWidth {
                Text("АЛЬБОМ")
                    .frame(width: 180, alignment: .leading)
            }

            Color.clear
                .frame(width: isMiniWidth ? 28 : 32, height: 1)

            Text("ВРЕМЯ")
                .frame(width: isMiniWidth ? 42 : 50, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(YMTheme.fg40)
        .padding(.horizontal, isMiniWidth ? 6 : 10)
        .padding(.vertical, 6)
    }
}

// MARK: - Modern Track Row

private struct ModernTrackRow: View {
    let track: YMTrack
    let index: Int
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let isSelected: Bool
    let showAlbum: Bool
    let isCompactWidth: Bool
    let isMiniWidth: Bool
    let onPlay: () -> Void
    let onTapRow: () -> Void
    let onArtistSelect: (YMArtist) -> Void
    let onAlbumSelect: (YMAlbum) -> Void
    let onShowLyrics: () -> Void
    let onRemoveFromPlaylist: (() -> Void)?

    @UIState private var likesService = LikesService.shared
    private let hoverManager = TrackHoverManager.shared

    private var isHovered: Bool {
        hoverManager.state(for: track.id).isHovered
    }

    private func triggerPlaybackAction() {
        if isCurrentTrack {
            AudioPlayerEngine.shared.togglePlayPause()
        } else {
            onPlay()
        }
    }

    var body: some View {
        HStack(spacing: isMiniWidth ? 8 : 12) {
            // Track Number (clean & simple, playback button is on the cover only)
            Text("\(index + 1)")
                .font(.system(size: 12, weight: isCurrentTrack ? .bold : .medium).monospacedDigit())
                .foregroundStyle(isCurrentTrack ? YMTheme.accent : YMTheme.fg40)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: isMiniWidth ? 30 : 38, alignment: .center)

            // Cover thumbnail (always clickable regardless of hover state)
            Button {
                triggerPlaybackAction()
            } label: {
                ZStack {
                    CachedCoverImage(
                        coverUri: track.effectiveCoverUri,
                        size: .small,
                        displaySize: 40,
                        cornerRadius: 6
                    )

                    if isHovered {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.55))
                            .frame(width: 40, height: 40)

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .foregroundColor(isCurrentTrack ? YMTheme.accent : Color.white)
                            .font(.system(size: isCurrentTrack ? 14 : 13, weight: isCurrentTrack ? .bold : .regular))
                    } else if isCurrentTrack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.55))
                            .frame(width: 40, height: 40)

                        YMPlayingEqualizerView(color: YMTheme.accent, barWidth: 2.5, maxHeight: 15, isPlaying: isPlaying)
                    }
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Пауза" : "Воспроизвести трек")

            // Title & Artists
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(.system(size: 13, weight: isCurrentTrack ? .bold : .medium))
                    .foregroundStyle(isCurrentTrack ? YMTheme.accent : YMTheme.fg)
                    .lineLimit(1)

                if !track.artists.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(track.artists) { artist in
                            Button {
                                onArtistSelect(artist)
                            } label: {
                                Text(artist.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(YMTheme.fg60)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)

                            if artist.id != track.artists.last?.id {
                                Text("•")
                                    .font(.system(size: 8))
                                    .foregroundStyle(YMTheme.fg40)
                            }
                        }
                    }
                } else {
                    Text(track.artistsString)
                        .font(.system(size: 12))
                        .foregroundStyle(YMTheme.fg60)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: isMiniWidth ? 100 : 180, alignment: .leading)

            Spacer(minLength: 4)

            // Album
            if showAlbum && !isCompactWidth {
                if let album = track.albums.first {
                    Button {
                        onAlbumSelect(album)
                    } label: {
                        Text(album.title)
                            .font(.system(size: 12))
                            .foregroundStyle(YMTheme.fg60)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 180, alignment: .leading)
                } else {
                    Color.clear
                        .frame(width: 180)
                }
            }

            // Like Heart Button
            Button {
                Task {
                    await likesService.toggleLike(track: track)
                }
            } label: {
                Image(systemName: likesService.isLiked(trackId: track.id) ? "heart.fill" : "heart")
                    .foregroundColor(likesService.isLiked(trackId: track.id) ? YMTheme.heartRed : YMTheme.fg40)
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .frame(width: isMiniWidth ? 28 : 32, alignment: .center)
            .help(likesService.isLiked(trackId: track.id) ? "Удалить из Мне нравится" : "Мне нравится")

            // Duration
            Text(track.formattedDuration)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(YMTheme.fg40)
                .frame(width: isMiniWidth ? 42 : 50, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, isMiniWidth ? 6 : 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? YMTheme.surfaceComponentHover
                        : (isCurrentTrack ? YMTheme.accent.opacity(0.12) : (isHovered ? YMTheme.surfaceComponent : Color.clear))
                )
        )
        .contentShape(Rectangle())
        .onHover { isInside in
            hoverManager.handleRowHover(trackId: track.id, isInside: isInside)
        }
        .onTapGesture {
            onTapRow()
        }
        .contextMenu {
            Button("Воспроизвести сейчас") {
                onPlay()
            }
            Button("Воспроизвести следующим") {
                AudioPlayerEngine.shared.insertNext(track)
            }
            Button("Добавить в конец очереди") {
                AudioPlayerEngine.shared.addToQueue([track])
            }
            Divider()
            Button("Запустить Мою волну по треку") {
                AudioPlayerEngine.shared.startWave(forTrack: track)
            }
            if let artist = track.artists.first {
                Button("Перейти к исполнителю: \(artist.name)") {
                    onArtistSelect(artist)
                }
            }
            if let album = track.albums.first {
                Button("Перейти к альбому: \(album.title)") {
                    onAlbumSelect(album)
                }
            }
            Button("Показать текст песни") {
                onShowLyrics()
            }
            Divider()
            AddToPlaylistContextMenu(track: track)
            if let onRemoveFromPlaylist = onRemoveFromPlaylist {
                Button("Удалить из плейлиста", role: .destructive) {
                    onRemoveFromPlaylist()
                }
            }
            Button(likesService.isLiked(trackId: track.id) ? "Удалить из Мне нравится" : "Добавить в Мне нравится") {
                Task {
                    await likesService.toggleLike(track: track)
                }
            }
        }
    }
}
