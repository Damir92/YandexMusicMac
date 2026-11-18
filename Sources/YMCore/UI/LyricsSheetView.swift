import SwiftUI
import AppKit
import CoreImage

// MARK: - Fullscreen Synced Lyrics View (Apple Music Style)

/// Fullscreen "Now Playing" synchronized lyrics experience inspired by Apple Music.
/// Features an opaque pre-blurred atmospheric cover backdrop, adaptive two-column layout,
/// isolated 120 FPS karaoke list with Equatable rows, manual scroll auto-pause,
/// and instant mode switching to the compact above-player lyrics bar.
public struct LyricsSheetView: View {
    @UIState private var coordinator = NavigationCoordinator.shared
    @UIState private var audioEngine = AudioPlayerEngine.shared
    @UIState private var likesService = LikesService.shared
    @UIState private var themeManager = YMThemeManager.shared
    @UIState private var windowState = WindowState.shared

    @UIState private var syncedLyrics: YMSyncedLyrics? = nil
    @UIState private var supplement: YMTrackSupplement? = nil
    @UIState private var isLoading = true
    @UIState private var errorMessage: String? = nil

    @UIState private var blurredBackdropImage: NSImage? = nil
    @UIState private var blurredBackdropUri: String? = nil

    private let networkClient = YMNetworkClient.shared

    public init(track: YMTrack? = nil) {
        // Parameter retained for backward compatibility; coordinator & audioEngine determine the current track
    }

    private var currentTrack: YMTrack? {
        coordinator.lyricsTrack ?? audioEngine.currentTrack
    }

    private var headerContextTitle: String {
        if audioEngine.isWaveMode {
            let waveTitle = audioEngine.activeWaveContext.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !waveTitle.isEmpty {
                return waveTitle
            }
        }
        return "Сейчас играет"
    }

    public var body: some View {
        ZStack {
            atmosphericBackdrop

            VStack(spacing: 0) {
                headerBar

                GeometryReader { geo in
                    if geo.size.width >= 720 {
                        wideLayout(width: geo.size.width)
                    } else {
                        compactLayout
                    }
                }
            }
            .padding(.bottom, 76)
        }
        .task(id: currentTrack?.id) {
            await loadLyricsAsync()
        }
        .task(id: currentTrack?.effectiveCoverUri) {
            await loadBackdropImageAsync()
        }
        .onDisappear {
            if !coordinator.isLyricsPresented {
                coordinator.lyricsTrack = nil
            }
        }
    }

    // MARK: - Atmospheric Backdrop (Pre-Blurred Once Per Track)

    @ViewBuilder
    private var atmosphericBackdrop: some View {
        let isLight = YMTheme.isLight
        let baseColor = YMTheme.bg

        ZStack {
            // Opaque base prevents the underlying track list from bleeding through
            baseColor

            if let image = blurredBackdropImage {
                GeometryReader { geo in
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(1.12)
                        .opacity(isLight ? 0.24 : 0.34)
                        .clipped()
                }
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.40), value: blurredBackdropUri)
            }

            // Symmetrical soft contrast gradient preserving high text legibility across bright & dark album art
            LinearGradient(
                stops: isLight
                    ? [
                        .init(color: baseColor.opacity(0.66), location: 0.0),
                        .init(color: baseColor.opacity(0.56), location: 0.5),
                        .init(color: baseColor.opacity(0.66), location: 1.0)
                    ]
                    : [
                        .init(color: Color.black.opacity(0.56), location: 0.0),
                        .init(color: Color.black.opacity(0.46), location: 0.5),
                        .init(color: Color.black.opacity(0.56), location: 1.0)
                    ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    // MARK: - Top Header Bar

    @ViewBuilder
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: audioEngine.isWaveMode ? "waveform.path.ecg" : "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(YMTheme.accent)

                Text(headerContextTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(YMTheme.fg80)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(YMTheme.surfaceComponent)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(YMTheme.border, lineWidth: 1)
                    )
            )
            .allowsHitTesting(false)

            Spacer()

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        coordinator.lyricsPosition = .abovePlayer
                    }
                } label: {
                    Image(systemName: "rectangle.bottomthird.inset.filled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(YMTheme.fg80)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(YMTheme.surfaceComponent))
                }
                .buttonStyle(.plain)
                .help("Свернуть в компактную полосу над плеером")

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        coordinator.isLyricsPresented = false
                        coordinator.lyricsTrack = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(YMTheme.fg80)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(YMTheme.surfaceComponent))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Закрыть текст песни (Esc)")
            }
        }
        .padding(.leading, windowState.topToolbarLeadingInset)
        .padding(.trailing, 24)
        .padding(.top, windowState.isFullScreen ? 20 : 10)
        .padding(.bottom, 12)
        .background(YMWindowDragHandle())
    }

    // MARK: - Wide Two-Column Layout (width >= 720)

    @ViewBuilder
    private func wideLayout(width: CGFloat) -> some View {
        let leftColumnWidth = max(280, min(width * 0.40, 420))

        HStack(alignment: .center, spacing: 32) {
            // Left Column (~40%): Artwork, track info, clickable artists & album, like button
            VStack(spacing: 20) {
                Spacer(minLength: 0)

                if let track = currentTrack {
                    CachedCoverImage(
                        coverUri: track.effectiveCoverUri,
                        size: .large,
                        displaySize: 260,
                        cornerRadius: 16
                    )
                    .shadow(
                        color: Color.black.opacity(YMTheme.isLight ? 0.18 : 0.50),
                        radius: 28,
                        x: 0,
                        y: 14
                    )

                    VStack(spacing: 8) {
                        Text(track.displayTitle)
                            .font(.title2.bold())
                            .foregroundStyle(YMTheme.fg)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: 280)

                        if !track.artists.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(track.artists) { artist in
                                    Button {
                                        navigateAndDismiss(to: .artist(id: artist.id, name: artist.name))
                                    } label: {
                                        Text(artist.name)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(YMTheme.fg80)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)

                                    if artist.id != track.artists.last?.id {
                                        Text("•")
                                            .font(.system(size: 10))
                                            .foregroundStyle(YMTheme.fg40)
                                    }
                                }
                            }
                            .frame(maxWidth: 280)
                        } else if !track.artistsString.isEmpty {
                            Text(track.artistsString)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(YMTheme.fg80)
                                .lineLimit(1)
                                .frame(maxWidth: 280)
                        }

                        if let album = track.albums.first {
                            Button {
                                navigateAndDismiss(to: .album(id: album.id, title: album.title))
                            } label: {
                                Text(album.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(YMTheme.fg60)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: 260)
                        }

                        let isLiked = likesService.isLiked(trackId: track.id)
                        Button {
                            Task {
                                await likesService.toggleLike(track: track)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(isLiked ? YMTheme.heartRed : YMTheme.fg80)
                                Text(isLiked ? "В коллекции" : "Нравится")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(YMTheme.fg80)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(YMTheme.surfaceComponent)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(YMTheme.border, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                        .help(isLiked ? "Удалить из Мне нравится" : "Добавить в Мне нравится")
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .font(.system(size: 44))
                            .foregroundStyle(YMTheme.fg40)
                        Text("Ничего не воспроизводится")
                            .font(.headline)
                            .foregroundStyle(YMTheme.fg60)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(width: leftColumnWidth)
            .frame(maxHeight: .infinity)

            // Right Column (~60%): Masked scrollable lyrics viewport
            lyricsViewport
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
    }

    // MARK: - Compact Layout (width < 720)

    @ViewBuilder
    private var compactLayout: some View {
        VStack(spacing: 0) {
            if let track = currentTrack {
                HStack(alignment: .center, spacing: 12) {
                    CachedCoverImage(
                        coverUri: track.effectiveCoverUri,
                        size: .small,
                        displaySize: 44,
                        cornerRadius: 8
                    )
                    .shadow(color: YMTheme.shadowColor, radius: 6, x: 0, y: 3)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.displayTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(YMTheme.fg)
                            .lineLimit(1)

                        if !track.artists.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(track.artists) { artist in
                                    Button {
                                        navigateAndDismiss(to: .artist(id: artist.id, name: artist.name))
                                    } label: {
                                        Text(artist.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(YMTheme.fg60)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Перейти к исполнителю: \(artist.name)")

                                    if artist.id != track.artists.last?.id {
                                        Text("•")
                                            .font(.system(size: 8))
                                            .foregroundStyle(YMTheme.fg40)
                                    }
                                }
                            }
                        } else if !track.artistsString.isEmpty {
                            Text(track.artistsString)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(YMTheme.fg60)
                                .lineLimit(1)
                        }
                    }
                    .layoutPriority(1)

                    Spacer()

                    let isLiked = likesService.isLiked(trackId: track.id)
                    Button {
                        Task {
                            await likesService.toggleLike(track: track)
                        }
                    } label: {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isLiked ? YMTheme.heartRed : YMTheme.fg60)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(YMTheme.surfaceComponent))
                    }
                    .buttonStyle(.plain)
                    .help(isLiked ? "Удалить из Мне нравится" : "Добавить в Мне нравится")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            }

            lyricsViewport
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Lyrics Content Viewport

    @ViewBuilder
    private var lyricsViewport: some View {
        Group {
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let synced = syncedLyrics, !synced.isEmpty {
                SyncedKaraokeListView(
                    synced: synced,
                    themeId: themeManager.currentTheme.rawValue
                )
                .id(currentTrack?.id ?? "")
                .mask(lyricsEdgeFadeMask)
            } else if let lyrics = supplement?.lyrics, !lyrics.displayText.isEmpty {
                staticLyricsView(text: lyrics.displayText)
                    .mask(lyricsEdgeFadeMask)
            } else {
                emptyView
            }
        }
    }

    private var lyricsEdgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.10),
                .init(color: .black, location: 0.84),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Static Lyrics Fallback View

    @ViewBuilder
    private func staticLyricsView(text: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Color.clear.frame(height: 44)
                Text(text)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(YMTheme.fg80)
                    .lineSpacing(10)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - State Views

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Загрузка текста песни...")
                .font(.caption)
                .foregroundStyle(YMTheme.fg60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 36))
                .foregroundStyle(YMTheme.fg40)
            Text(msg)
                .font(.subheadline)
                .foregroundStyle(YMTheme.fg80)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 36))
                .foregroundStyle(YMTheme.fg40)
            Text("К сожалению, текст для этого трека пока не добавлен в Яндекс Музыку.")
                .font(.subheadline)
                .foregroundStyle(YMTheme.fg80)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers & Async Loading

    private func navigateAndDismiss(to route: AppRoute) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            coordinator.isLyricsPresented = false
            coordinator.lyricsTrack = nil
        }
        coordinator.navigate(to: route)
    }

    private func loadBackdropImageAsync() async {
        guard let coverUri = currentTrack?.effectiveCoverUri, !coverUri.isEmpty else {
            blurredBackdropImage = nil
            blurredBackdropUri = nil
            return
        }
        if blurredBackdropUri == coverUri && blurredBackdropImage != nil {
            return
        }

        let requestedUri = coverUri
        let blurred = await YMBackdropBlurProcessor.shared.blurredImage(for: requestedUri, radius: 14.0)
        guard !Task.isCancelled, currentTrack?.effectiveCoverUri == requestedUri else { return }

        blurredBackdropImage = blurred
        blurredBackdropUri = requestedUri
    }

    private func loadLyricsAsync() async {
        guard let track = currentTrack else {
            isLoading = false
            syncedLyrics = nil
            supplement = nil
            errorMessage = "Сейчас ничего не воспроизводится."
            return
        }

        let requestedTrackId = track.id
        isLoading = true
        errorMessage = nil
        syncedLyrics = nil
        supplement = nil

        // 1. Attempt to fetch synced LRC lyrics (cached in memory for instant mode switching)
        do {
            if let synced = try await networkClient.fetchTrackLyricsLRC(trackId: requestedTrackId), !synced.isEmpty {
                guard !Task.isCancelled, currentTrack?.id == requestedTrackId else { return }
                self.syncedLyrics = synced
                self.isLoading = false
                return
            }
        } catch {
            // Proceed to supplement fallback
        }

        guard !Task.isCancelled, currentTrack?.id == requestedTrackId else { return }

        // 2. Fallback to track supplement for static lyrics
        do {
            let supp = try await networkClient.fetchTrackSupplement(trackId: requestedTrackId)
            guard !Task.isCancelled, currentTrack?.id == requestedTrackId else { return }
            self.supplement = supp
            self.isLoading = false
            if supp.lyrics == nil || supp.lyrics?.displayText.isEmpty == true {
                self.errorMessage = "Текст для этого трека отсутствует."
            }
        } catch {
            guard !Task.isCancelled, currentTrack?.id == requestedTrackId else { return }
            self.isLoading = false
            self.errorMessage = "Не удалось загрузить слова песни: \(error.localizedDescription)"
        }
    }
}

// MARK: - Isolated Synced Karaoke List Subview

/// Isolates `activeLineIndex` and `LyricsTimeObserverView` from `LyricsSheetView`,
/// so advancing to the next lyric line never re-evaluates the backdrop, artwork, or header,
/// and `Equatable` `KaraokeLineRow`s ensure only the 2 changing lines re-render.
private struct SyncedKaraokeListView: View {
    let synced: YMSyncedLyrics
    let themeId: String

    @UIState private var activeLineIndex: Int?
    @UIState private var isUserScrollingLyrics = false
    @UIState private var isInitialScrollPositioned = false
    @UIState private var resumeAutoScrollTask: Task<Void, Never>? = nil

    init(synced: YMSyncedLyrics, themeId: String) {
        self.synced = synced
        self.themeId = themeId
        let initialIndex = synced.activeLineIndex(for: AudioPlayerEngine.shared.progressTracker.currentTime)
        self._activeLineIndex = UIState(initialValue: initialIndex)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Color.clear
                        .frame(height: 84)

                    ForEach(synced.lines) { line in
                        let isActive = line.id == activeLineIndex
                        let isPast = (activeLineIndex != nil) && (line.id < activeLineIndex!)

                        KaraokeLineRow(
                            line: line,
                            isActive: isActive,
                            isPast: isPast,
                            themeId: themeId,
                            onSelect: {
                                resumeAutoScrollTask?.cancel()
                                resumeAutoScrollTask = nil
                                isUserScrollingLyrics = false
                                AudioPlayerEngine.shared.seek(to: line.time)
                                activeLineIndex = line.id
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    proxy.scrollTo(line.id, anchor: .center)
                                }
                            }
                        )
                        .equatable()
                        .id(line.id)
                    }

                    Color.clear
                        .frame(height: 160)
                }
                .padding(.horizontal, 16)
            }
            .opacity(isInitialScrollPositioned ? 1 : 0)
            .background {
                LyricsTimeObserverView(
                    syncedLyrics: synced,
                    activeLineIndex: $activeLineIndex
                )
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in
                        pauseAutoScrollTemporarily()
                    }
            )
            .onChange(of: activeLineIndex) { _, newActiveIndex in
                guard let id = newActiveIndex, !isUserScrollingLyrics else { return }
                if !isInitialScrollPositioned {
                    var noAnim = Transaction()
                    noAnim.disablesAnimations = true
                    withTransaction(noAnim) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    isInitialScrollPositioned = true
                } else {
                    withAnimation(.easeInOut(duration: 0.32)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onAppear {
                let targetId = activeLineIndex ?? synced.activeLineIndex(for: AudioPlayerEngine.shared.progressTracker.currentTime)
                var noAnim = Transaction()
                noAnim.disablesAnimations = true
                if let id = targetId {
                    if activeLineIndex != id {
                        withTransaction(noAnim) {
                            activeLineIndex = id
                        }
                    }
                    withTransaction(noAnim) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    // Confirm exact center offset after initial VStack geometry settles, without animation
                    DispatchQueue.main.async {
                        withTransaction(noAnim) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                        isInitialScrollPositioned = true
                    }
                } else {
                    isInitialScrollPositioned = true
                }
            }
            .onDisappear {
                resumeAutoScrollTask?.cancel()
                resumeAutoScrollTask = nil
            }
        }
    }

    private func pauseAutoScrollTemporarily() {
        isUserScrollingLyrics = true
        resumeAutoScrollTask?.cancel()
        resumeAutoScrollTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            isUserScrollingLyrics = false
            resumeAutoScrollTask = nil
        }
    }
}

// MARK: - Isolated Playback Time Observer

/// Dedicated 0x0 observer view isolating `PlaybackProgressTracker.currentTime` subscriptions.
/// Updates `activeLineIndex` directly without a global `withAnimation` transaction so only
/// local row transitions and `proxy.scrollTo` animate.
private struct LyricsTimeObserverView: View {
    let syncedLyrics: YMSyncedLyrics
    @Binding var activeLineIndex: Int?
    @UIState private var progressTracker = AudioPlayerEngine.shared.progressTracker

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: progressTracker.currentTime) { _, newTime in
                let newIndex = syncedLyrics.activeLineIndex(for: newTime)
                if newIndex != activeLineIndex {
                    activeLineIndex = newIndex
                }
            }
    }
}

// MARK: - Equatable Karaoke Line Row Subview (Zero Offscreen Shadow Passes)

private struct KaraokeLineRow: View, Equatable {
    let line: SyncedLyricLine
    let isActive: Bool
    let isPast: Bool
    let themeId: String
    let onSelect: () -> Void

    @UIState private var isHovered = false

    nonisolated static func == (lhs: KaraokeLineRow, rhs: KaraokeLineRow) -> Bool {
        lhs.line == rhs.line
            && lhs.isActive == rhs.isActive
            && lhs.isPast == rhs.isPast
            && lhs.themeId == rhs.themeId
    }

    // Identical base font metrics guarantee words never re-wrap or clip past trailing bounds
    private static let baseFont = Font.system(size: 22, weight: .bold, design: .rounded)

    private var textColor: Color {
        if isActive {
            return YMTheme.accent
        } else if isPast {
            return YMTheme.isLight ? YMTheme.fg.opacity(0.32) : Color.white.opacity(0.32)
        } else if isHovered {
            return YMTheme.fg.opacity(0.92)
        } else {
            return YMTheme.isLight ? YMTheme.fg.opacity(0.56) : Color.white.opacity(0.56)
        }
    }

    private var textScale: CGFloat {
        if isActive {
            return 1.0
        } else if isHovered {
            return 0.97
        } else {
            return 0.94
        }
    }

    var body: some View {
        Button(action: onSelect) {
            Text(line.text)
                .font(Self.baseFont)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaleEffect(textScale, anchor: .leading)
                .animation(.easeOut(duration: 0.22), value: isActive)
                .animation(.easeInOut(duration: 0.14), value: isHovered)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
