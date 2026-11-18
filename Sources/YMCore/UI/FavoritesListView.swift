import SwiftUI

/// Modern, beautiful "Мне нравится" (Favorites) view featuring iconic gradient hero banner,
/// quick play/shuffle/wave actions, glass search filter, and seamless scrolling track list.
public struct FavoritesListView: View {
    @UIState private var likesService = LikesService.shared
    @UIState private var audioEngine = AudioPlayerEngine.shared
    @UIState private var windowState = WindowState.shared
    @UIState private var coordinator = NavigationCoordinator.shared

    @UIState private var filterQuery = ""
    @UIState private var isScrolled = false

    public init() {}

    private var displayedTracks: [YMTrack] {
        let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return likesService.likedTracks }
        return likesService.searchInLikes(query: q)
    }

    private var totalDurationFormatted: String {
        let totalMs = displayedTracks.compactMap(\.durationMs).reduce(0, +)
        guard totalMs > 0 else { return "" }
        let totalSeconds = totalMs / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours) ч \(minutes) мин"
        }
        return "\(minutes) мин"
    }

    public var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 20) {
                // Hero Header
                let tileSize: CGFloat = windowState.isMiniWidth ? 80 : (windowState.isCompactWidth ? 96 : 120)
                let iconSize: CGFloat = windowState.isMiniWidth ? 34 : (windowState.isCompactWidth ? 42 : 50)
                HStack(alignment: .bottom, spacing: windowState.isCompactWidth ? 16 : 20) {
                    // Iconic Gradient Heart Tile
                    ZStack {
                        RoundedRectangle(cornerRadius: windowState.isMiniWidth ? 12 : 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 228 / 255, green: 92 / 255, blue: 78 / 255),   // Deep coral
                                        Color(red: 196 / 255, green: 52 / 255, blue: 102 / 255),  // Rich crimson
                                        Color(red: 108 / 255, green: 44 / 255, blue: 132 / 255)   // Modern plum
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: tileSize, height: tileSize)
                            .overlay(
                                RoundedRectangle(cornerRadius: windowState.isMiniWidth ? 12 : 16, style: .continuous)
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color.white.opacity(0.24),
                                                Color.white.opacity(0.0)
                                            ],
                                            center: .topLeading,
                                            startRadius: 4,
                                            endRadius: tileSize * 0.8
                                        )
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: windowState.isMiniWidth ? 12 : 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .shadow(color: Color(red: 196 / 255, green: 52 / 255, blue: 102 / 255).opacity(0.28), radius: 18, y: 8)

                        Image(systemName: "heart.fill")
                            .font(.system(size: iconSize, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.24), radius: 6, y: 3)
                    }

                    // Metadata & Actions
                    VStack(alignment: .leading, spacing: windowState.isCompactWidth ? 6 : 8) {
                        Text("ПЛЕЙЛИСТ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(YMTheme.fg40)
                            .tracking(1.2)

                        Text("Мне нравится")
                            .font(.system(size: windowState.isCompactWidth ? 22 : 28, weight: .bold))
                            .foregroundStyle(YMTheme.fg)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text("\(likesService.likedTrackIds.count) треков")
                            if !totalDurationFormatted.isEmpty {
                                Text("• \(totalDurationFormatted)")
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(YMTheme.fg60)
                        .lineLimit(1)

                        // Adaptive Actions Bar
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                playAllButton(title: "Слушать всё", height: 32)
                                shuffleButton(title: "Перемешать", height: 32)
                                waveButton(title: "Волна по любимому", height: 32)
                            }

                            HStack(spacing: 8) {
                                playAllButton(title: "Слушать", height: 30)
                                shuffleButton(title: "Микс", height: 30)
                                waveButton(title: "Волна", height: 30)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    playAllButton(title: "Слушать", height: 30)
                                    shuffleButton(title: "Микс", height: 30)
                                }
                                waveButton(title: "Волна по любимому", height: 30)
                            }
                        }
                        .padding(.top, 2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, windowState.isMiniWidth ? 16 : 24)
                .padding(.top, windowState.topChromeContentPadding)

                // Search & Filter Input Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(YMTheme.fg40)

                    TextField("Поиск по моим трекам, исполнителям и альбомам...", text: $filterQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))

                    if likesService.isIndexingCatalog {
                        ProgressView()
                            .controlSize(.small)
                            .help("Индексация треков для поиска...")
                    }

                    if !filterQuery.isEmpty {
                        Text("\(displayedTracks.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(YMTheme.fg40)

                        Button {
                            filterQuery = ""
                            likesService.pruneSearchCatalogIfNeeded()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(YMTheme.fg40)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(YMTheme.surfaceComponent)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(YMTheme.border, lineWidth: 1))
                )
                .padding(.horizontal, 24)

                // Tracklist Content
                if likesService.isSyncing && displayedTracks.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Синхронизация ваших треков...")
                            .font(.caption)
                            .foregroundStyle(YMTheme.fg40)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else if likesService.likedTrackIds.isEmpty && displayedTracks.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "heart")
                            .font(.system(size: 44))
                            .foregroundStyle(YMTheme.fg40)
                        Text("Здесь будут ваши любимые треки")
                            .font(.headline)
                            .foregroundStyle(YMTheme.fg)
                        Text("Нажимайте на сердечко у любых треков, чтобы собрать свою коллекцию")
                            .font(.subheadline)
                            .foregroundStyle(YMTheme.fg60)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else if displayedTracks.isEmpty && !filterQuery.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(YMTheme.fg40)
                        Text("В Избранном ничего не найдено")
                            .font(.headline)
                            .foregroundStyle(YMTheme.fg)
                        Text("По запросу «\(filterQuery)» треков не найдено")
                            .font(.subheadline)
                            .foregroundStyle(YMTheme.fg60)
                        Button("Очистить поиск") {
                            filterQuery = ""
                        }
                        .buttonStyle(YMGlassPillButtonStyle(primary: false))
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    TrackTableView(
                        tracks: displayedTracks,
                        onPlayTrack: { track in
                            audioEngine.isWaveMode = false
                            let isFiltered = !filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            let playable = displayedTracks.filter { !$0.isPlaceholder && !$0.isSpacer }
                            if let idx = playable.firstIndex(where: { $0.id == track.id }) {
                                audioEngine.setQueue(playable, startingAt: idx)
                                if !isFiltered {
                                    attachSequentialLikesContinuation()
                                }
                            } else {
                                Task {
                                    if let resolved = await likesService.fetchTrackImmediately(trackId: track.id) {
                                        let updatedPlayable = displayedTracks.filter { !$0.isPlaceholder && !$0.isSpacer }
                                        if let newIdx = updatedPlayable.firstIndex(where: { $0.id == resolved.id }) {
                                            audioEngine.setQueue(updatedPlayable, startingAt: newIdx)
                                        } else {
                                            audioEngine.setQueue([resolved], startingAt: 0)
                                        }
                                        if !isFiltered {
                                            attachSequentialLikesContinuation()
                                        }
                                    }
                                }
                            }
                        },
                        onLoadMore: {
                            Task {
                                await likesService.loadMoreLikedTracks()
                            }
                        }
                    )
                    .padding(.horizontal, 14)

                    if likesService.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(.bottom, 80)
            .background(alignment: .top) {
                YMScrollTopSentinel(
                    coordinateSpaceName: "favorites_scroll",
                    threshold: 88,
                    isScrolled: $isScrolled
                )
            }
        }
        .coordinateSpace(name: "favorites_scroll")
        .overlay(alignment: .top) {
            YMStickyTopBar(title: "Мне нравится", isVisible: isScrolled)
        }
        .ymScreenBackground()
        .task {
            await likesService.ensureInitialLikesLoaded()
        }
        .task(id: filterQuery) {
            let trimmed = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await likesService.ensureAllLikedTracksLoadedForSearch()
        }
    }

    @ViewBuilder
    private func playAllButton(title: String, height: CGFloat) -> some View {
        Button {
            let isFiltered = !filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let playable = displayedTracks.filter { !$0.isPlaceholder && !$0.isSpacer }
            if !playable.isEmpty {
                audioEngine.isWaveMode = false
                audioEngine.setQueue(playable, startingAt: 0)
                if !isFiltered {
                    attachSequentialLikesContinuation()
                }
            }
        } label: {
            Label(title, systemImage: "play.fill")
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(YMGlassPillButtonStyle(primary: true, height: height))
    }

    @ViewBuilder
    private func shuffleButton(title: String, height: CGFloat) -> some View {
        Button {
            if !filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                audioEngine.playShuffled(displayedTracks)
            } else {
                Task {
                    let randomTracks = await likesService.fetchRandomLikedTracksForShuffle(limit: 50)
                    audioEngine.playShuffled(randomTracks)
                    attachShuffledLikesContinuation()
                }
            }
        } label: {
            Label(title, systemImage: "shuffle")
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(YMGlassPillButtonStyle(primary: false, height: height))
    }

    private func attachSequentialLikesContinuation() {
        let likes = likesService
        audioEngine.attachQueueContinuation { existingIds in
            await likes.loadNextLikedTracksForPlayback(excludingIds: existingIds, batchSize: 50)
        }
    }

    private func attachShuffledLikesContinuation() {
        let likes = likesService
        audioEngine.attachQueueContinuation { existingIds in
            await likes.fetchMoreRandomLikedTracksForShuffle(excludingIds: existingIds, limit: 50)
        }
    }

    @ViewBuilder
    private func waveButton(title: String, height: CGFloat) -> some View {
        Button {
            let playable = displayedTracks.filter { !$0.isPlaceholder && !$0.isSpacer }
            audioEngine.startWave(forPlaylist: YMPlaylist(uid: "user", kind: 3, title: "Мне нравится"), tracks: Array(playable))
        } label: {
            Label(title, systemImage: "waveform.path.ecg")
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(YMGlassPillButtonStyle(primary: false, height: height))
    }
}
