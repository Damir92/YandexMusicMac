import SwiftUI

/// Modern native macOS Artist detail view featuring hero banner, popular tracks, discography, and wave launcher.
public struct ArtistDetailView: View {
    public let artistId: String
    public let artistName: String

    @UIState private var briefInfo: YMArtistBriefInfo? = nil
    @UIState private var cachedPopularTracks: [YMTrack] = []
    @UIState private var isLoading = true
    @UIState private var errorMessage: String? = nil
    @UIState private var loadTask: Task<Void, Never>? = nil
    @UIState private var isScrolled = false

    @UIState private var audioEngine = AudioPlayerEngine.shared
    @UIState private var coordinator = NavigationCoordinator.shared
    @UIState private var windowState = WindowState.shared
    private let networkClient = YMNetworkClient.shared

    public init(artistId: String, artistName: String) {
        self.artistId = artistId
        self.artistName = artistName
    }

    public var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 28) {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Загрузка профиля артиста...")
                            .font(.caption)
                            .foregroundStyle(YMTheme.fg40)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .padding(.top, 52)
                } else if let error = errorMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Повторить") {
                            loadArtistData()
                        }
                        .buttonStyle(YMGlassPillButtonStyle(primary: true))
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .padding(.top, 52)
                } else if let info = briefInfo {
                    // Hero Banner with atmospheric cover glow
                    let avatarSize: CGFloat = windowState.isCompactWidth ? 104 : 150
                    HStack(alignment: .center, spacing: windowState.isCompactWidth ? 16 : 24) {
                        CachedCoverImage(
                            coverUri: info.artist.coverUri,
                            size: .medium,
                            displaySize: avatarSize,
                            cornerRadius: avatarSize / 2
                        )
                        .frame(width: avatarSize, height: avatarSize)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(YMTheme.border, lineWidth: 1))
                        .shadow(color: YMTheme.shadowColor, radius: 18, y: 8)

                        VStack(alignment: .leading, spacing: windowState.isCompactWidth ? 6 : 10) {
                            Text(info.artist.name)
                                .font(.system(size: windowState.isCompactWidth ? 22 : 32, weight: .bold))
                                .foregroundStyle(YMTheme.fg)
                                .lineLimit(2)

                            if let stats = info.stats, !stats.formattedListeners.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.2.fill")
                                        .font(.caption)
                                    Text(stats.formattedListeners)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(YMTheme.fg60)
                            }

                            // Adaptive Actions Bar
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 10) {
                                    if !info.popularTracks.isEmpty {
                                        Button {
                                            audioEngine.isWaveMode = false
                                            audioEngine.assignQueue(info.popularTracks, startingAt: 0)
                                        } label: {
                                            Label("Слушать популярное", systemImage: "play.fill")
                                                .fixedSize(horizontal: true, vertical: false)
                                        }
                                        .buttonStyle(YMGlassPillButtonStyle(primary: true, height: 34))
                                    }

                                    Button {
                                        audioEngine.startWave(forArtist: info.artist)
                                    } label: {
                                        Label("Моя волна по артисту", systemImage: "waveform.path.ecg")
                                            .fixedSize(horizontal: true, vertical: false)
                                    }
                                    .buttonStyle(YMGlassPillButtonStyle(primary: false, height: 34))
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    if !info.popularTracks.isEmpty {
                                        Button {
                                            audioEngine.isWaveMode = false
                                            audioEngine.assignQueue(info.popularTracks, startingAt: 0)
                                        } label: {
                                            Label(windowState.isMiniWidth ? "Популярное" : "Слушать популярное", systemImage: "play.fill")
                                        }
                                        .buttonStyle(YMGlassPillButtonStyle(primary: true, height: 30))
                                    }

                                    Button {
                                        audioEngine.startWave(forArtist: info.artist)
                                    } label: {
                                        Label(windowState.isMiniWidth ? "Волна" : "Моя волна по артисту", systemImage: "waveform.path.ecg")
                                    }
                                    .buttonStyle(YMGlassPillButtonStyle(primary: false, height: 30))
                                }
                            }
                            .padding(.top, 4)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, windowState.isMiniWidth ? 16 : 24)
                    .padding(.top, 54)
                    .padding(.bottom, 16)
                    .ymAmbientCoverGlow(coverUri: info.artist.coverUri, opacity: 0.24)

                    // Popular Tracks Section
                    if !info.popularTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Популярные треки")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(YMTheme.fg)
                                .padding(.horizontal, 24)

                            TrackTableView(
                                tracks: cachedPopularTracks,
                                onPlayTrack: { track in
                                    audioEngine.isWaveMode = false
                                    if let index = info.popularTracks.firstIndex(where: { $0.id == track.id }) {
                                        audioEngine.assignQueue(info.popularTracks, startingAt: index)
                                    }
                                },
                                showAlbum: true
                            )
                            .padding(.horizontal, 14)
                        }
                    }

                    // Direct Albums Section
                    if !info.albums.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Альбомы")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(YMTheme.fg)
                                .padding(.horizontal, 24)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(info.albums) { album in
                                        YMAlbumCard(album: album) {
                                            // Play album
                                            Task {
                                                if let fullAlbum = try? await networkClient.fetchAlbumWithTracks(albumId: album.id) {
                                                    audioEngine.isWaveMode = false
                                                    audioEngine.assignQueue(fullAlbum.allTracks, startingAt: 0)
                                                }
                                            }
                                        } onSelect: {
                                            coordinator.navigate(to: .album(id: album.id, title: album.title))
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                            }
                        }
                    }

                    // Singles & EPs Section
                    if !info.alsoAlbums.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Синглы и сборники")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(YMTheme.fg)
                                .padding(.horizontal, 24)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(info.alsoAlbums) { album in
                                        YMAlbumCard(album: album) {
                                            Task {
                                                if let fullAlbum = try? await networkClient.fetchAlbumWithTracks(albumId: album.id) {
                                                    audioEngine.isWaveMode = false
                                                    audioEngine.assignQueue(fullAlbum.allTracks, startingAt: 0)
                                                }
                                            }
                                        } onSelect: {
                                            coordinator.navigate(to: .album(id: album.id, title: album.title))
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                            }
                        }
                    }

                    // Similar Artists Section
                    if !info.similarArtists.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Похожие исполнители")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(YMTheme.fg)
                                .padding(.horizontal, 24)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 20) {
                                    ForEach(info.similarArtists) { similar in
                                        YMArtistCard(artist: similar) {
                                            coordinator.navigate(to: .artist(id: similar.id, name: similar.name))
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, 10)
                                .padding(.bottom, 8)
                            }
                        }
                    }

                    // Biography / Description Section
                    if let desc = info.description?.text, !desc.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Об исполнителе")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(YMTheme.fg)

                            Text(desc)
                                .font(.system(size: 13))
                                .foregroundStyle(YMTheme.fg80)
                                .lineSpacing(4)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: YMTheme.cornerRadiusMedium)
                                        .fill(YMTheme.surface)
                                        .overlay(RoundedRectangle(cornerRadius: YMTheme.cornerRadiusMedium).strokeBorder(YMTheme.border, lineWidth: 1))
                                )
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            .padding(.bottom, 24)
            .background(alignment: .top) {
                if #unavailable(macOS 15.0) {
                    YMScrollTopSentinel(
                        coordinateSpaceName: "artist_detail_scroll",
                        threshold: 84,
                        isScrolled: $isScrolled
                    )
                }
            }
        }
        .ymTrackScrollOffset(threshold: 84, isScrolled: $isScrolled)
        .coordinateSpace(name: "artist_detail_scroll")
        .overlay(alignment: .top) {
            YMStickyDetailTopBar(
                backTitle: "Назад",
                title: briefInfo?.artist.name ?? artistName,
                isScrolled: isScrolled
            ) {
                coordinator.pop()
            }
        }
        .ymScreenBackground()
        .task(id: artistId) {
            isScrolled = false
            loadArtistData()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func loadArtistData() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        let targetArtistId = artistId
        loadTask = Task {
            do {
                let info = try await networkClient.fetchArtistBriefInfo(artistId: targetArtistId)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.artistId == targetArtistId else { return }
                    self.briefInfo = info
                    self.cachedPopularTracks = Array(info.popularTracks.prefix(10))
                    self.isLoading = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.artistId == targetArtistId else { return }
                    self.errorMessage = "Не удалось загрузить данные артиста: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}
