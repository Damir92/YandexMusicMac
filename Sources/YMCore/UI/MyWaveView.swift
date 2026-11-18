import SwiftUI

/// Modern, monolithic "Моя волна" hub.
/// Combines an atmospheric glass Hero Stage with a single unified adaptive grid for
/// the base wave, mood/tempo modifiers, and personalized Rotor dashboard stations,
/// plus on-demand full genre catalog search and infinite track queue.
/// Does NOT auto-play on navigation.
public struct MyWaveView: View {
    @UIState private var waveTracks: [YMTrack] = []
    @UIState private var rotorService = RotorService.shared
    @UIState private var audioEngine = AudioPlayerEngine.shared
    @UIState private var windowState = WindowState.shared
    @UIState private var coordinator = NavigationCoordinator.shared
    @UIState private var likesService = LikesService.shared
    @UIState private var authService = AuthService.shared
    @UIState private var rotorDiagnosticsStore = RotorDiagnosticsStore.shared

    @UIState private var selectedFilter: YMWaveCategoryFilter = .forYou
    @UIState private var dashboardStations: [YMPersonalWaveStation] = []
    @UIState private var isLoadingDashboard = false
    @UIState private var isCatalogSheetPresented = false

    @UIState private var isLoadingWave = false
    @UIState private var isLoadingMoreWave = false
    @UIState private var errorMessage: String? = nil
    @UIState private var toastMessage: String? = nil
    @UIState private var toastDismissTask: Task<Void, Never>? = nil
    @UIState private var waveStartTask: Task<Void, Never>? = nil

    @UIState private var isFlameActive: Bool = false
    @UIState private var isScrolled: Bool = false

    public init() {}

    private var displayedWaveTracks: [YMTrack] {
        if audioEngine.isWaveMode && !audioEngine.queue.isEmpty {
            return audioEngine.queue
        }
        return waveTracks
    }

    private var unifiedItems: [YMUnifiedWaveItem] {
        YMUnifiedWaveItem.items(for: selectedFilter, dashboardStations: dashboardStations)
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 22) {
                // 1. Atmospheric Hero Stage (Header + Active Filter Chips + Glass Stage Card)
                heroStageSection

                // Subscription notice (if authenticated without active Plus)
                if let user = authService.currentUser, !user.hasActiveSubscription {
                    subscriptionNoticeBanner
                }

                // Tuning / Wave Feedback Toast
                if let toast = toastMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundColor(YMTheme.accent)
                            .font(.system(size: 12, weight: .bold))
                        Text(toast)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(YMTheme.fg)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(YMTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(YMTheme.border, lineWidth: 1))
                            .shadow(color: YMTheme.shadowColor, radius: 8, y: 2)
                    )
                    .padding(.horizontal, windowState.isMiniWidth ? 16 : 24)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Error Banner
                if let error = errorMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Ошибка загрузки волны: \(error)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Повторить") {
                            startWave(context: audioEngine.activeWaveContext, vibe: audioEngine.activeWaveVibe)
                        }
                        .buttonStyle(YMGlassPillButtonStyle(primary: true, height: 28))
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
                    )
                    .padding(.horizontal, windowState.isMiniWidth ? 16 : 24)
                }

                // 2. Unified Adaptive Block: "Поток и настроение"
                unifiedWaveHubSection

                // 3. Upcoming Queue: "Далее в волне"
                upcomingQueueSection
            }
            .padding(.bottom, 80)
            .background(alignment: .top) {
                YMScrollTopSentinel(
                    coordinateSpaceName: "mywave_scroll",
                    threshold: 64,
                    isScrolled: $isScrolled
                )
            }
        }
        .coordinateSpace(name: "mywave_scroll")
        .overlay(alignment: .top) {
            YMStickyTopBar(
                title: "Моя волна",
                showLiveDot: audioEngine.isWaveMode,
                isVisible: isScrolled
            )
        }
        .ymScreenBackground()
        .sheet(isPresented: $isCatalogSheetPresented) {
            AllCatalogWavesSheet(
                rotorService: rotorService,
                activeContextSeeds: audioEngine.activeWaveContext.seeds,
                onSelectStation: { station in
                    isCatalogSheetPresented = false
                    startWave(context: station.toWaveContext(), vibe: audioEngine.activeWaveVibe)
                    showToast("Запущена волна «\(station.title)»")
                }
            )
        }
        .task {
            await loadDashboardStationsIfNeeded()
        }
        .onAppear {
            // NEVER auto-start playback on navigation
            if audioEngine.isWaveMode && !audioEngine.queue.isEmpty {
                waveTracks = audioEngine.queue
            }
            setupWaveChangeHooks()
        }
    }

    // MARK: - 1. Atmospheric Hero Stage

    @ViewBuilder
    private var heroStageSection: some View {
        let horizontalPad: CGFloat = windowState.isMiniWidth ? 16 : 24
        let activeTrack = audioEngine.isWaveMode ? audioEngine.currentTrack : nil

        VStack(alignment: .leading, spacing: 14) {
            // Compact Status Header + Removable Active Filter Chips
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    waveTitleHeader
                    Spacer(minLength: 12)
                    activeFilterChipsRow
                }

                VStack(alignment: .leading, spacing: 8) {
                    waveTitleHeader
                    if hasActiveWaveFilters {
                        activeFilterChipsRow
                    }
                }
            }

            // Central Glass Stage Card
            Group {
                if let track = activeTrack {
                    activeGlassStageCard(track: track)
                } else {
                    idleGlassStageCard
                }
            }
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(YMTheme.surface.opacity(YMTheme.isLight ? 0.72 : 0.76))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(YMTheme.border, lineWidth: 1)
            )
            .shadow(color: YMTheme.shadowColor, radius: 14, y: 5)
        }
        .padding(.horizontal, horizontalPad)
        .padding(.top, windowState.topChromeContentPadding)
        .padding(.bottom, 6)
        .ymAmbientCoverGlow(coverUri: activeTrack?.effectiveCoverUri, opacity: 0.28)
    }

    private var hasActiveWaveFilters: Bool {
        audioEngine.activeWaveContext != .myWaveDefault || audioEngine.activeWaveVibe != .defaultWave
    }

    @ViewBuilder
    private var waveTitleHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("Моя волна")
                    .font(.system(size: windowState.isCompactWidth ? 24 : 28, weight: .bold))
                    .foregroundStyle(YMTheme.fg)
                    .fixedSize(horizontal: true, vertical: false)

                if audioEngine.isWaveMode {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(YMTheme.accent)
                            .frame(width: 6, height: 6)
                        Text("в эфире")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(YMTheme.accent)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(YMTheme.accent.opacity(0.15)))
                }
            }

            Text(audioEngine.activeWaveContext.subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(YMTheme.fg60)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var activeFilterChipsRow: some View {
        HStack(spacing: 8) {
            if audioEngine.activeWaveContext != .myWaveDefault {
                removableFilterChip(title: audioEngine.activeWaveContext.title, icon: "waveform") {
                    startWave(context: .myWaveDefault, vibe: audioEngine.activeWaveVibe)
                    showToast("Возврат к базовой «Моей волне»")
                }
            }

            if audioEngine.activeWaveVibe != .defaultWave {
                removableFilterChip(title: audioEngine.activeWaveVibe.title, icon: audioEngine.activeWaveVibe.iconName) {
                    startWave(context: audioEngine.activeWaveContext, vibe: .defaultWave)
                    showToast("Сброс характера звучания")
                }
            }
        }
    }

    @ViewBuilder
    private func removableFilterChip(title: String, icon: String, onRemove: @escaping () -> Void) -> some View {
        Button(action: onRemove) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(YMTheme.accent)

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(YMTheme.fg)
                    .lineLimit(1)

                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(YMTheme.fg60)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(YMTheme.surfaceComponent)
                    .overlay(Capsule(style: .continuous).strokeBorder(YMTheme.accent.opacity(0.32), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .help("Сбросить фильтр «\(title)»")
    }

    // MARK: - Glass Stage Card (Active & Idle)

    @ViewBuilder
    private func activeGlassStageCard(track: YMTrack) -> some View {
        if windowState.isCompactWidth {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    activeTrackCoverButton(track: track, size: 64, cornerRadius: 10, eqMaxHeight: 20)
                    activeTrackMeta(track: track)
                    Spacer(minLength: 4)
                }

                activeTrackControls(
                    track: track,
                    playDiscSize: windowState.isMiniWidth ? 40 : 42,
                    playIconSize: 15,
                    spacing: windowState.isMiniWidth ? 8 : 12
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(windowState.isMiniWidth ? 12 : 16)
        } else {
            HStack(spacing: 18) {
                activeTrackCoverButton(track: track, size: 88, cornerRadius: 12, eqMaxHeight: 24)
                activeTrackMeta(track: track)
                Spacer(minLength: 12)
                activeTrackControls(track: track, playDiscSize: 46, playIconSize: 17, spacing: 10)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func activeTrackCoverButton(track: YMTrack, size: CGFloat, cornerRadius: CGFloat, eqMaxHeight: CGFloat) -> some View {
        Button {
            if let album = track.albums.first {
                coordinator.navigate(to: .album(id: album.id, title: album.title))
            }
        } label: {
            ZStack {
                CachedCoverImage(
                    coverUri: track.effectiveCoverUri,
                    size: .medium,
                    displaySize: size,
                    cornerRadius: cornerRadius
                )

                if audioEngine.isPlaying {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.black.opacity(0.50))
                            .frame(width: size, height: size)

                        YMPlayingEqualizerView(
                            color: YMTheme.accent,
                            barWidth: 3,
                            maxHeight: eqMaxHeight,
                            isPlaying: true
                        )
                    }
                    .frame(width: size, height: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: YMTheme.shadowColor, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .help("Перейти к альбому")
    }

    @ViewBuilder
    private func activeTrackMeta(track: YMTrack) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.displayTitle)
                .font(.system(size: windowState.isCompactWidth ? 15 : 17, weight: .bold))
                .foregroundStyle(YMTheme.fg)
                .lineLimit(1)

            if !track.artists.isEmpty {
                HStack(spacing: 4) {
                    ForEach(track.artists) { artist in
                        MyWaveHeroArtistButton(artist: artist) {
                            coordinator.navigate(to: .artist(id: artist.id, name: artist.name))
                        }

                        if artist.id != track.artists.last?.id {
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundStyle(YMTheme.fg40)
                        }
                    }
                }
            } else {
                Text(track.artistsString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(YMTheme.fg60)
                    .lineLimit(1)
            }

            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(YMTheme.accent)
                Text(aiInsightText(for: track))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(YMTheme.fg40)
                    .lineLimit(1)
            }
            .padding(.top, 2)
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private func activeTrackControls(track: YMTrack, playDiscSize: CGFloat, playIconSize: CGFloat, spacing: CGFloat) -> some View {
        let iconButtonSize: CGFloat = windowState.isMiniWidth ? 28 : 32

        HStack(spacing: spacing) {
            // 1. Dislike (Less Like This)
            stageIconButton(
                systemName: "hand.thumbsdown.fill",
                color: YMTheme.fg60,
                size: iconButtonSize,
                help: "Меньше таких треков"
            ) {
                audioEngine.applyWaveTuning(.lessLikeThis)
                showToast("Меньше таких треков в волне")
            }

            // 2. Previous
            stageIconButton(
                systemName: "backward.fill",
                color: YMTheme.fg80,
                size: iconButtonSize,
                showBackground: false,
                help: "Предыдущий трек"
            ) {
                audioEngine.previous()
            }

            // 3. Signature Golden Play / Pause Disc (46x46)
            Button {
                audioEngine.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(YMTheme.accentFill)
                        .frame(width: playDiscSize, height: playDiscSize)
                        .shadow(color: YMTheme.accentFill.opacity(audioEngine.isPlaying ? 0.34 : 0.16), radius: 9, y: 2)

                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: playIconSize, weight: .bold))
                        .foregroundColor(Color.black)
                        .offset(x: audioEngine.isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(.plain)
            .help(audioEngine.isPlaying ? "Пауза" : "Воспроизведение")

            // 4. Next
            stageIconButton(
                systemName: "forward.fill",
                color: YMTheme.fg80,
                size: iconButtonSize,
                showBackground: false,
                help: "Следующий трек"
            ) {
                audioEngine.next()
            }

            // 5. Flame (More Like This)
            stageIconButton(
                systemName: "flame.fill",
                color: isFlameActive ? Color.orange : YMTheme.accent,
                size: iconButtonSize,
                help: "Больше таких треков"
            ) {
                audioEngine.applyWaveTuning(.moreLikeThis)
                isFlameActive = true
                showToast("Больше треков в стиле «\(track.displayTitle)»")
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await MainActor.run { isFlameActive = false }
                }
            }

            // 6. Shake / Diversity ("Встряхнуть")
            stageIconButton(
                systemName: "sparkles",
                color: YMTheme.fg80,
                size: iconButtonSize,
                help: "Встряхнуть поток и добавить открытий"
            ) {
                audioEngine.applyWaveTuning(.moreDiversity)
                showToast("Перенастройка волны: добавлено больше открытий")
            }

            // 7. Like (Heart)
            stageIconButton(
                systemName: likesService.isLiked(trackId: track.id) ? "heart.fill" : "heart",
                color: likesService.isLiked(trackId: track.id) ? YMTheme.heartRed : YMTheme.fg60,
                size: iconButtonSize,
                help: likesService.isLiked(trackId: track.id) ? "Удалить из Мне нравится" : "Мне нравится"
            ) {
                Task {
                    await likesService.toggleLike(track: track)
                }
            }
        }
    }

    @ViewBuilder
    private func stageIconButton(
        systemName: String,
        color: Color,
        size: CGFloat,
        showBackground: Bool = true,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: windowState.isMiniWidth ? 12 : 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(showBackground ? YMTheme.surfaceComponent : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var idleGlassStageCard: some View {
        if windowState.isMiniWidth {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    idleWaveEmblem(size: 50, iconSize: 21)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Волна готова к запуску")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(YMTheme.fg)

                        Text("Нажмите кнопку или выберите настроение ниже")
                            .font(.system(size: 12))
                            .foregroundStyle(YMTheme.fg60)
                    }
                }

                Button {
                    startWave(context: audioEngine.activeWaveContext, vibe: audioEngine.activeWaveVibe)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Запустить Мою волну")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(YMGlassPillButtonStyle(primary: true, height: 36))
            }
            .padding(14)
        } else {
            HStack(spacing: 16) {
                idleWaveEmblem(size: 60, iconSize: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Волна готова к запуску")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(YMTheme.fg)

                    Text("Персональный бесконечный поток рекомендаций под ваш вкус и настроение")
                        .font(.system(size: 12.5))
                        .foregroundStyle(YMTheme.fg60)
                }

                Spacer(minLength: 12)

                Button {
                    startWave(context: audioEngine.activeWaveContext, vibe: audioEngine.activeWaveVibe)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Запустить Мою волну")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .buttonStyle(YMGlassPillButtonStyle(primary: true, height: 38))
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func idleWaveEmblem(size: CGFloat, iconSize: CGFloat) -> some View {
        YMPulsingWaveEmblem(size: size, iconSize: iconSize)
    }

    @ViewBuilder
    private var subscriptionNoticeBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundColor(YMTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Требуется подписка Яндекс Плюс")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(YMTheme.fg)
                Text("Для прослушивания Моей волны необходим активный Плюс")
                    .font(.system(size: 11))
                    .foregroundStyle(YMTheme.fg60)
            }
            Spacer()
            Button("Оформить") {
                if let url = URL(string: "https://plus.yandex.ru/") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(YMGlassPillButtonStyle(primary: true, height: 28))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(YMTheme.surfaceComponent)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(YMTheme.border, lineWidth: 1))
        )
        .padding(.horizontal, windowState.isMiniWidth ? 16 : 24)
    }

    // MARK: - 2. Unified Adaptive Block ("Поток и настроение")

    @ViewBuilder
    private var unifiedWaveHubSection: some View {
        let horizontalPad: CGFloat = windowState.isMiniWidth ? 16 : 24
        let columns = [
            GridItem(
                .adaptive(
                    minimum: windowState.isMiniWidth ? 145 : 170,
                    maximum: 230
                ),
                spacing: 10
            )
        ]

        VStack(alignment: .leading, spacing: 14) {
            // Section Header + Compact Segmented Filter + "+ Все жанры"
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Поток и настроение")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(YMTheme.fg)
                        .fixedSize(horizontal: true, vertical: false)

                    categorySegmentedControl(compact: false)

                    Spacer(minLength: 8)

                    allGenresButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        Text("Поток и настроение")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(YMTheme.fg)

                        Spacer()

                        allGenresButton
                    }

                    categorySegmentedControl(compact: windowState.isMiniWidth)
                }
            }
            .padding(.horizontal, horizontalPad)

            // Single Adaptive Grid of Unified Wave Cards
            if isLoadingDashboard && dashboardStations.isEmpty && selectedFilter == .genresAndArtists {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Подбираем персональные волны...")
                        .font(.caption)
                        .foregroundStyle(YMTheme.fg40)
                }
                .padding(.horizontal, horizontalPad)
                .padding(.vertical, 12)
            } else if unifiedItems.isEmpty {
                HStack(spacing: 12) {
                    Text("Персональные жанры пока не загружены.")
                        .font(.caption)
                        .foregroundStyle(YMTheme.fg60)
                    Button("Открыть все жанры") {
                        isCatalogSheetPresented = true
                    }
                    .buttonStyle(YMGlassPillButtonStyle(primary: false, height: 28))
                }
                .padding(.horizontal, horizontalPad)
                .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(unifiedItems) { item in
                        UnifiedWaveItemCard(
                            item: item,
                            isActive: isItemActive(item),
                            accentColor: accentColor(for: item)
                        ) {
                            handleUnifiedItemTap(item)
                        }
                    }
                }
                .padding(.horizontal, horizontalPad)
            }
        }
    }

    @ViewBuilder
    private func categorySegmentedControl(compact: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(YMWaveCategoryFilter.allCases) { filter in
                let isSelected = selectedFilter == filter
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selectedFilter = filter
                    }
                } label: {
                    Text(compact ? filter.compactTitle : filter.title)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.black : YMTheme.fg80)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? YMTheme.accentFill : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(YMTheme.surfaceComponent)
                .overlay(Capsule(style: .continuous).strokeBorder(YMTheme.border, lineWidth: 1))
        )
    }

    @ViewBuilder
    private var allGenresButton: some View {
        Button {
            isCatalogSheetPresented = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("Все жанры")
                    .font(.system(size: 11.5, weight: .semibold))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(YMTheme.fg80)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(YMTheme.surfaceComponent)
                    .overlay(Capsule(style: .continuous).strokeBorder(YMTheme.border, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .help("Открыть полный каталог жанров и волн Яндекс Музыки")
    }

    private func isItemActive(_ item: YMUnifiedWaveItem) -> Bool {
        switch item {
        case .baseWave:
            return audioEngine.isWaveMode
                && audioEngine.activeWaveContext == .myWaveDefault
                && audioEngine.activeWaveVibe == .defaultWave
        case .vibe(let preset):
            return audioEngine.activeWaveVibe == preset
        case .station(let station):
            return audioEngine.isWaveMode
                && audioEngine.activeWaveContext.seeds.contains(station.id)
        }
    }

    private func handleUnifiedItemTap(_ item: YMUnifiedWaveItem) {
        switch item {
        case .baseWave:
            startWave(context: .myWaveDefault, vibe: .defaultWave)
            showToast("Запущена базовая «Моя волна»")

        case .station(let station):
            let context = station.toWaveContext()
            startWave(context: context, vibe: audioEngine.activeWaveVibe)
            if audioEngine.activeWaveVibe != .defaultWave {
                showToast("Волна «\(station.title)» • \(audioEngine.activeWaveVibe.title)")
            } else {
                showToast("Запущена волна «\(station.title)»")
            }

        case .vibe(let preset):
            let nextVibe: YMWaveVibePreset = (audioEngine.activeWaveVibe == preset) ? .defaultWave : preset
            startWave(context: audioEngine.activeWaveContext, vibe: nextVibe)
            if nextVibe == .defaultWave {
                showToast("Характер звучания сброшен на «По умолчанию»")
            } else if audioEngine.activeWaveContext != .myWaveDefault {
                showToast("«\(audioEngine.activeWaveContext.title)» • \(nextVibe.title)")
            } else {
                showToast("Характер волны: \(nextVibe.title)")
            }
        }
    }

    private func accentColor(for item: YMUnifiedWaveItem) -> Color {
        switch item {
        case .baseWave:
            return YMTheme.accent
        case .vibe(let preset):
            return vibeColor(for: preset)
        case .station(let station):
            if let hex = station.accentHex, let parsed = Self.color(fromHex: hex) {
                return parsed
            }
            switch station.type.lowercased() {
            case "genre": return Color(red: 112 / 255, green: 146 / 255, blue: 228 / 255)
            case "mood": return Color(red: 230 / 255, green: 138 / 255, blue: 76 / 255)
            case "activity": return Color(red: 76 / 255, green: 184 / 255, blue: 146 / 255)
            case "epoch": return Color(red: 178 / 255, green: 126 / 255, blue: 218 / 255)
            case "artist": return YMTheme.accent
            default: return YMTheme.accent
            }
        }
    }

    private func vibeColor(for preset: YMWaveVibePreset) -> Color {
        switch preset {
        case .defaultWave: return YMTheme.accent.opacity(0.92)
        case .energetic: return YMTheme.isLight
            ? Color(red: 36 / 255, green: 148 / 255, blue: 112 / 255)
            : Color(red: 72 / 255, green: 188 / 255, blue: 146 / 255)
        case .unfamiliar: return YMTheme.isLight
            ? Color(red: 196 / 255, green: 118 / 255, blue: 42 / 255)
            : Color(red: 228 / 255, green: 154 / 255, blue: 72 / 255)
        case .familiar: return YMTheme.accent.opacity(0.90)
        case .popular: return YMTheme.isLight
            ? Color(red: 196 / 255, green: 76 / 255, blue: 86 / 255)
            : Color(red: 224 / 255, green: 106 / 255, blue: 114 / 255)
        case .calm: return YMTheme.isLight
            ? Color(red: 124 / 255, green: 92 / 255, blue: 186 / 255)
            : Color(red: 164 / 255, green: 132 / 255, blue: 224 / 255)
        case .joyful: return YMTheme.isLight
            ? Color(red: 204 / 255, green: 138 / 255, blue: 22 / 255)
            : Color(red: 245 / 255, green: 190 / 255, blue: 72 / 255)
        case .sad: return YMTheme.isLight
            ? Color(red: 76 / 255, green: 118 / 255, blue: 176 / 255)
            : Color(red: 118 / 255, green: 164 / 255, blue: 224 / 255)
        case .russian: return YMTheme.isLight
            ? Color(red: 182 / 255, green: 84 / 255, blue: 118 / 255)
            : Color(red: 222 / 255, green: 122 / 255, blue: 156 / 255)
        case .foreign: return YMTheme.isLight
            ? Color(red: 52 / 255, green: 132 / 255, blue: 176 / 255)
            : Color(red: 98 / 255, green: 178 / 255, blue: 224 / 255)
        case .focus: return YMTheme.isLight
            ? Color(red: 64 / 255, green: 138 / 255, blue: 132 / 255)
            : Color(red: 106 / 255, green: 192 / 255, blue: 184 / 255)
        case .workout: return YMTheme.isLight
            ? Color(red: 198 / 255, green: 94 / 255, blue: 56 / 255)
            : Color(red: 236 / 255, green: 132 / 255, blue: 88 / 255)
        }
    }

    // MARK: - 3. Upcoming Queue Section

    @ViewBuilder
    private var upcomingQueueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Далее в волне")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(YMTheme.fg)

                    Text("Треки, подобранные алгоритмом на основе ваших предпочтений")
                        .font(.caption)
                        .foregroundStyle(YMTheme.fg40)
                }

                Spacer()

                if isLoadingMoreWave {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, windowState.isMiniWidth ? 16 : 24)

            if displayedWaveTracks.isEmpty && isLoadingWave {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("Подбираем музыку для вашей волны...")
                        .font(.caption)
                        .foregroundStyle(YMTheme.fg40)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else if !displayedWaveTracks.isEmpty {
                TrackTableView(
                    tracks: displayedWaveTracks,
                    onPlayTrack: { track in
                        if let idx = displayedWaveTracks.firstIndex(where: { $0.id == track.id }) {
                            audioEngine.playTrack(at: idx)
                        }
                    },
                    onLoadMore: {
                        Task {
                            await loadMoreTracks()
                        }
                    }
                )
                .padding(.horizontal, windowState.isMiniWidth ? 8 : 14)
            }
        }
    }

    // MARK: - AI Context Insights

    private func aiInsightText(for track: YMTrack) -> String {
        if let dynamicInsight = rotorDiagnosticsStore.insight(for: track.id)?.formattedInsight {
            return dynamicInsight
        }

        switch audioEngine.activeWaveVibe {
        case .energetic:
            return "Бодрый ритм под настроение"
        case .calm:
            return "Спокойная атмосфера для отдыха"
        case .unfamiliar:
            return "Свежее открытие на основе вкусов"
        case .familiar:
            return "Проверенный трек из любимых"
        case .popular:
            return "Популярный трек в Яндекс Музыке"
        case .joyful:
            return "Лёгкий и жизнерадостный настрой"
        case .sad:
            return "Глубокое меланхоличное звучание"
        case .russian:
            return "Подборка на русском языке"
        case .foreign:
            return "Подборка зарубежной музыки"
        case .focus:
            return "Сбалансированный фон для работы и фокуса"
        case .workout:
            return "Драйвовый темп для тренировки"
        case .defaultWave:
            return "Поток рекомендаций Моей волны"
        }
    }

    // MARK: - Wave Logic & Telemetry

    private func loadDashboardStationsIfNeeded() async {
        guard dashboardStations.isEmpty && !isLoadingDashboard else { return }
        isLoadingDashboard = true
        let fetched = await rotorService.fetchRecommendedWaves()
        await MainActor.run {
            self.dashboardStations = fetched
            self.isLoadingDashboard = false
        }
    }

    private func startWave(context: YMWaveContext, vibe: YMWaveVibePreset) {
        waveStartTask?.cancel()
        isLoadingWave = true
        errorMessage = nil

        waveStartTask = Task {
            do {
                let initialTracks = try await rotorService.startWave(context: context, vibe: vibe)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.waveTracks = initialTracks
                    self.isLoadingWave = false
                    self.audioEngine.activeWaveContext = context
                    self.audioEngine.activeWaveVibe = vibe
                    self.audioEngine.isWaveMode = true
                    self.audioEngine.setQueue(initialTracks, startingAt: 0)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isLoadingWave = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadMoreTracks() async {
        let currentList = displayedWaveTracks
        guard !isLoadingMoreWave, let lastTrack = currentList.last else { return }
        isLoadingMoreWave = true
        defer { isLoadingMoreWave = false }

        do {
            let queueIds = currentList.suffix(25).map(\.rotorTrackIdentifier)
            let nextBatch = try await rotorService.fetchNextBatch(
                lastTrackId: lastTrack.rotorTrackIdentifier,
                queueHistory: queueIds
            )
            if audioEngine.isWaveMode {
                audioEngine.appendToQueue(nextBatch)
                waveTracks = audioEngine.queue
            } else {
                waveTracks.append(contentsOf: nextBatch)
            }
        } catch {
            print("[MyWaveView] Error loading more wave tracks: \(error)")
        }
    }

    private func setupWaveChangeHooks() {
        audioEngine.onQueueNeedsMoreTracks = {
            Task {
                await loadMoreTracks()
            }
        }

        audioEngine.onStartCustomWaveRequested = { [self] context, vibe in
            Task { @MainActor in
                self.startWave(context: context, vibe: vibe ?? .defaultWave)
            }
        }
    }

    private func showToast(_ message: String) {
        toastDismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toastMessage = message
        }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.toastMessage = nil
                }
            }
        }
    }

    fileprivate static func color(fromHex hex: String) -> Color? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Unified Wave Item Card (Clean Single-Layer Hover)

private struct UnifiedWaveItemCard: View {
    let item: YMUnifiedWaveItem
    let isActive: Bool
    let accentColor: Color
    let action: () -> Void

    @UIState private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accentColor.opacity(isActive ? 0.28 : (YMTheme.isLight ? 0.16 : 0.22)))
                        .frame(width: 34, height: 34)

                    if let iconUrl = item.iconUrl, !iconUrl.isEmpty {
                        CachedCoverImage(
                            coverUri: iconUrl,
                            size: .small,
                            displaySize: 34,
                            cornerRadius: 8
                        )
                    } else {
                        Image(systemName: item.iconName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isActive ? YMTheme.accent : accentColor)
                    }
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: isActive ? .bold : .semibold))
                        .foregroundStyle(isActive ? YMTheme.accent : YMTheme.fg)
                        .lineLimit(1)

                    Text(item.badgeText)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(YMTheme.fg40)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isActive {
                    Circle()
                        .fill(YMTheme.accent)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(YMTheme.surface)
                    .overlay(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(isActive ? 0.18 : (isHovered ? 0.13 : (YMTheme.isLight ? 0.07 : 0.09))),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Color.white.opacity(isHovered ? (YMTheme.isLight ? 0.20 : 0.035) : 0)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isActive ? YMTheme.accent.opacity(0.60) : (isHovered ? YMTheme.borderHover : YMTheme.border),
                        lineWidth: 1
                    )
            )
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(item.subtitle)
    }
}

// MARK: - On-Demand Full Catalog Sheet ("+ Все жанры")

private struct AllCatalogWavesSheet: View {
    let rotorService: RotorService
    let activeContextSeeds: [String]
    let onSelectStation: (YMPersonalWaveStation) -> Void

    @Environment(\.dismiss) private var dismiss
    @UIState private var catalogStations: [YMPersonalWaveStation] = []
    @UIState private var searchQuery: String = ""
    @UIState private var isLoading = true

    private var filteredStations: [YMPersonalWaveStation] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return catalogStations }
        return catalogStations.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.categoryLabel.localizedCaseInsensitiveContains(q)
                || $0.tag.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Все жанры и волны")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(YMTheme.fg)
                    Text("Полный каталог станций Rotor API")
                        .font(.system(size: 11.5))
                        .foregroundStyle(YMTheme.fg60)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(YMTheme.fg80)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(YMTheme.surfaceComponent))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(YMTheme.fg40)

                TextField("Найти жанр, настроение или эпоху...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(YMTheme.fg)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(YMTheme.fg40)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(YMTheme.surfaceComponent)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(YMTheme.border, lineWidth: 1))
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()
                .overlay(YMTheme.border)

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Загрузка каталога волн...")
                        .font(.caption)
                        .foregroundStyle(YMTheme.fg40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredStations.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(YMTheme.fg40)
                    Text("Ничего не найдено")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(YMTheme.fg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(filteredStations) { station in
                            let item = YMUnifiedWaveItem.station(station)
                            let accent = station.accentHex.flatMap(MyWaveView.color(fromHex:)) ?? YMTheme.accent
                            UnifiedWaveItemCard(
                                item: item,
                                isActive: activeContextSeeds.contains(station.id),
                                accentColor: accent
                            ) {
                                onSelectStation(station)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 560, height: 480)
        .ymScreenBackground()
        .task {
            let stations = await rotorService.fetchAllCatalogWaves()
            await MainActor.run {
                self.catalogStations = stations
                self.isLoading = false
            }
        }
    }
}

// MARK: - Individual Artist Button for My Wave Hero Stage

private struct MyWaveHeroArtistButton: View {
    let artist: YMArtist
    let onSelect: () -> Void

    @UIState private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            Text(artist.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovered ? YMTheme.fg : YMTheme.fg60)
                .underline(isHovered)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Перейти к исполнителю: \(artist.name)")
    }
}

/// Isolated emblem for idle state — static in idle for zero CPU load with responsive hover effect.
private struct YMPulsingWaveEmblem: View {
    let size: CGFloat
    let iconSize: CGFloat
    @UIState private var isHovered: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(YMTheme.accent.opacity(isHovered ? 0.22 : 0.14))
                .frame(width: size, height: size)

            Image(systemName: "waveform.path.ecg")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(YMTheme.accent)
                .scaleEffect(isHovered ? 1.06 : 1.0)
        }
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
