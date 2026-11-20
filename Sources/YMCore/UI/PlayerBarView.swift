import SwiftUI
import AppKit

/// Bottom Player Bar anchored via safeAreaInset.
/// Modern macOS dark glass design with balanced symmetrical controls,
/// fixed-width quality pills, and isolated PlaybackProgressTracker redraw boundaries.
public struct PlayerBarView: View {
    @UIState private var audioEngine = AudioPlayerEngine.shared
    @UIState private var likesService = LikesService.shared
    @UIState private var windowState = WindowState.shared
    @UIState private var coordinator = NavigationCoordinator.shared
    @UIState private var isFlameActive = false
    @UIState private var isMuted = false
    @UIState private var previousVolume: Float = 1.0
    @UIState private var eqSettings = EqualizerSettings.shared

    public init() {}

    private var isFullscreenNowPlaying: Bool {
        coordinator.isLyricsPresented && coordinator.lyricsPosition == .right
    }

    public var body: some View {
        let nowPlayingStyle = isFullscreenNowPlaying

        HStack(spacing: 0) {
            // Left: Track cover, Title, Artist, Like
            leftTrackSection
                .frame(minWidth: windowState.isMiniWidth ? 90 : (windowState.isCompactWidth ? 130 : 160), maxWidth: 250, alignment: .leading)

            Spacer(minLength: 4)

            // Center: Symmetrical Playback Controls & Progress Scrubber
            centerControlsSection
                .frame(minWidth: windowState.isMiniWidth ? 140 : (windowState.isCompactWidth ? 200 : 280), maxWidth: 440)

            Spacer(minLength: 4)

            // Right: Lyrics, Fixed-width Quality Badge & Volume Control
            rightControlsSection
                .frame(minWidth: windowState.isMiniWidth ? 55 : (windowState.isCompactWidth ? 110 : 160), maxWidth: 250, alignment: .trailing)
        }
        .padding(.horizontal, windowState.isCompactWidth ? 12 : 20)
        .padding(.vertical, 8)
        .frame(height: 76)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                if nowPlayingStyle {
                    // Seamless bottom dissolve over the fullscreen atmospheric backdrop:
                    // no hard border, no glowing box on bright album covers, just a gentle vertical scrim.
                    let scrimBase = YMTheme.isLight ? YMTheme.bg : Color.black
                    LinearGradient(
                        stops: [
                            .init(color: Color.clear, location: 0.0),
                            .init(color: scrimBase.opacity(YMTheme.isLight ? 0.20 : 0.22), location: 0.42),
                            .init(color: scrimBase.opacity(YMTheme.isLight ? 0.38 : 0.42), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .padding(.top, -32)
                    .allowsHitTesting(false)
                } else {
                    ZStack(alignment: .top) {
                        VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                        YMTheme.playerBg.opacity(0.84)
                    }
                }

                // Свободные участки бара двигают окно; элементы управления лежат выше
                // и получают клики первыми, поэтому ползунки работают нормально.
                YMWindowDragHandle()
            }
        }
        .overlay(alignment: .top) {
            if !nowPlayingStyle {
                YMTheme.border
                    .frame(height: 1)
            }
        }
        .shadow(
            color: nowPlayingStyle ? Color.clear : YMTheme.playerBarShadow,
            radius: nowPlayingStyle ? 0 : 10,
            x: 0,
            y: nowPlayingStyle ? 0 : -4
        )
        .animation(.easeInOut(duration: 0.25), value: nowPlayingStyle)
    }

    // MARK: - Left Track Section

    @ViewBuilder
    private var leftTrackSection: some View {
        HStack(spacing: 10) {
            if let track = audioEngine.currentTrack {
                Button {
                    if let album = track.albums.first {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            coordinator.navigate(to: .album(id: album.id, title: album.title))
                        }
                    }
                } label: {
                    CachedCoverImage(
                        coverUri: track.effectiveCoverUri,
                        size: .small,
                        displaySize: 44,
                        cornerRadius: 6
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .help("Перейти к альбому")

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(YMTheme.fg)
                        .lineLimit(1)

                    if !track.artists.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(track.artists) { artist in
                                PlayerBarArtistButton(artist: artist) {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                        coordinator.navigate(to: .artist(id: artist.id, name: artist.name))
                                    }
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
                            .font(.system(size: 11))
                            .foregroundStyle(YMTheme.fg60)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                // Heart / Like button
                PlayerHoverIconButton(
                    systemName: likesService.isLiked(trackId: track.id) ? "heart.fill" : "heart",
                    fontSize: windowState.isMiniWidth ? 12 : 13,
                    foregroundColor: likesService.isLiked(trackId: track.id) ? YMTheme.heartRed : YMTheme.fg60,
                    isActive: false,
                    buttonSize: windowState.isMiniWidth ? 24 : 28,
                    helpText: likesService.isLiked(trackId: track.id) ? "Удалить из Мне нравится" : "Мне нравится"
                ) {
                    Task {
                        await likesService.toggleLike(track: track)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(YMTheme.surfaceComponent)
                    .frame(width: 44, height: 44)

                Text("Ничего не играет")
                    .font(.system(size: 13))
                    .foregroundStyle(YMTheme.fg40)
                    .lineLimit(1)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Center Controls Section (Strictly Symmetrical)

    @ViewBuilder
    private var centerControlsSection: some View {
        VStack(spacing: 6) {
            // Row 1: Symmetrical Playback Controls
            HStack(spacing: windowState.isMiniWidth ? 10 : 16) {
                if audioEngine.isWaveMode {
                    if !windowState.isMiniWidth {
                        // Button 1 (Leftmost): Dislike
                        PlayerHoverIconButton(
                            systemName: "hand.thumbsdown.fill",
                            fontSize: 12,
                            foregroundColor: YMTheme.fg60,
                            isActive: false,
                            isDisabled: audioEngine.currentTrack == nil,
                            helpText: "Меньше таких треков"
                        ) {
                            audioEngine.applyWaveTuning(.lessLikeThis)
                        }
                    }

                    // Button 2: Previous Track
                    previousButton

                    // Button 3 (Center): Play / Pause (Prominent Yellow Disc)
                    playPauseButton

                    // Button 4: Next Track
                    nextButton

                    if !windowState.isMiniWidth {
                        // Button 5 (Rightmost): Flame (More Like This)
                        PlayerHoverIconButton(
                            systemName: "flame.fill",
                            fontSize: 12,
                            foregroundColor: isFlameActive ? Color.orange : YMTheme.accent,
                            isActive: isFlameActive,
                            isDisabled: audioEngine.currentTrack == nil,
                            helpText: "Больше таких треков"
                        ) {
                            audioEngine.applyWaveTuning(.moreLikeThis)
                            isFlameActive = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                await MainActor.run {
                                    isFlameActive = false
                                }
                            }
                        }
                    }
                } else {
                    if !windowState.isMiniWidth {
                        // Button 1 (Leftmost): Shuffle
                        PlayerHoverIconButton(
                            systemName: "shuffle",
                            fontSize: 12,
                            foregroundColor: audioEngine.isShuffleEnabled ? YMTheme.accent : YMTheme.fg60,
                            isActive: audioEngine.isShuffleEnabled,
                            isDisabled: audioEngine.currentTrack == nil && audioEngine.queue.isEmpty,
                            helpText: audioEngine.isShuffleEnabled ? "Выключить перемешивание" : "Перемешать очередь"
                        ) {
                            audioEngine.toggleShuffle()
                        }
                    }

                    // Button 2: Previous Track
                    previousButton

                    // Button 3 (Center): Play / Pause
                    playPauseButton

                    // Button 4: Next Track
                    nextButton

                    if !windowState.isMiniWidth {
                        // Button 5 (Rightmost): Start Wave from Current Track
                        PlayerHoverIconButton(
                            systemName: "waveform.path.ecg",
                            fontSize: 12,
                            foregroundColor: YMTheme.fg60,
                            isActive: false,
                            isDisabled: audioEngine.currentTrack == nil,
                            helpText: "Запустить Мою волну по текущему треку"
                        ) {
                            if let track = audioEngine.currentTrack {
                                audioEngine.startWave(forTrack: track)
                            }
                        }
                    }
                }
            }

            // Row 2: Isolated Scrubber View
            IsolatedProgressSlider(
                progressTracker: audioEngine.progressTracker,
                onSeekCommit: { seconds in
                    audioEngine.seek(to: seconds)
                }
            )
        }
    }

    @ViewBuilder
    private var previousButton: some View {
        PlayerHoverIconButton(
            systemName: "backward.fill",
            fontSize: windowState.isMiniWidth ? 12 : 13,
            foregroundColor: audioEngine.currentTrack == nil ? YMTheme.fg40 : YMTheme.fg80,
            isActive: false,
            isDisabled: audioEngine.currentTrack == nil,
            buttonSize: windowState.isMiniWidth ? 24 : 28,
            helpText: "Предыдущий трек"
        ) {
            audioEngine.previous()
        }
    }

    @ViewBuilder
    private var playPauseButton: some View {
        Button {
            audioEngine.togglePlayPause()
        } label: {
            ZStack {
                Circle()
                    .fill(YMTheme.accentFill)
                    .frame(width: windowState.isMiniWidth ? 34 : 38, height: windowState.isMiniWidth ? 34 : 38)
                    .shadow(color: YMTheme.accentFill.opacity(audioEngine.isPlaying ? 0.30 : 0.14), radius: 6, y: 1)

                Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: windowState.isMiniWidth ? 14 : 15, weight: .bold))
                    .foregroundColor(Color.black)
                    .offset(x: audioEngine.isPlaying ? 0 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(audioEngine.currentTrack == nil)
        .help(audioEngine.isPlaying ? "Пауза (Пробел)" : "Воспроизведение (Пробел)")
    }

    @ViewBuilder
    private var nextButton: some View {
        PlayerHoverIconButton(
            systemName: "forward.fill",
            fontSize: windowState.isMiniWidth ? 12 : 13,
            foregroundColor: audioEngine.currentTrack == nil ? YMTheme.fg40 : YMTheme.fg80,
            isActive: false,
            isDisabled: audioEngine.currentTrack == nil,
            buttonSize: windowState.isMiniWidth ? 24 : 28,
            helpText: "Следующий трек"
        ) {
            audioEngine.next()
        }
    }

    // MARK: - Right Controls Section

    @ViewBuilder
    private var rightControlsSection: some View {
        HStack(spacing: windowState.isMiniWidth ? 6 : 10) {
            // Lyrics Button (available whenever track is loaded/playing)
            if let track = audioEngine.currentTrack {
                PlayerHoverIconButton(
                    systemName: coordinator.isLyricsPresented ? "quote.bubble.fill" : "quote.bubble",
                    fontSize: windowState.isMiniWidth ? 11 : 12,
                    foregroundColor: coordinator.isLyricsPresented ? YMTheme.accent : YMTheme.fg80,
                    isActive: coordinator.isLyricsPresented,
                    buttonSize: windowState.isMiniWidth ? 24 : 28,
                    helpText: coordinator.isLyricsPresented ? "Скрыть текст песни" : "Показать текст песни"
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        if coordinator.isLyricsPresented {
                            coordinator.isLyricsPresented = false
                            coordinator.lyricsTrack = nil
                        } else {
                            coordinator.showLyrics(for: track)
                        }
                    }
                }
            }

            // Equalizer Floating Card Button
            PlayerHoverIconButton(
                systemName: "slider.vertical.3",
                fontSize: windowState.isMiniWidth ? 11 : 12,
                foregroundColor: (eqSettings.isEnabled || coordinator.isEqualizerPresented) ? YMTheme.accent : YMTheme.fg80,
                isActive: eqSettings.isEnabled || coordinator.isEqualizerPresented,
                buttonSize: windowState.isMiniWidth ? 24 : 28,
                helpText: eqSettings.isEnabled ? "Эквалайзер (включён)" : "Эквалайзер"
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    coordinator.isEqualizerPresented.toggle()
                }
            }

            // Fixed-Width Quality Badge Menu (hidden in mini mode to prevent crowding)
            if !windowState.isMiniWidth {
                AudioQualityMenu(audioEngine: audioEngine)
            }

            // Volume Control (slider hidden in mini mode so playback controls & scrubber stay spacious at 440pt)
            HStack(spacing: 6) {
                PlayerHoverIconButton(
                    systemName: volumeIcon,
                    fontSize: windowState.isMiniWidth ? 11 : 12,
                    foregroundColor: YMTheme.fg60,
                    isActive: false,
                    buttonSize: windowState.isMiniWidth ? 24 : 28,
                    helpText: isMuted ? "Включить звук" : "Выключить звук"
                ) {
                    toggleMute()
                }

                if !windowState.isMiniWidth {
                    YMSlider(
                        value: Binding(
                            get: { Double(audioEngine.volume) },
                            set: {
                                audioEngine.volume = Float($0)
                                if $0 > 0 { isMuted = false }
                            }
                        ),
                        in: 0...1,
                        activeColor: YMTheme.fg,
                        trackColor: YMTheme.surfaceComponentHover,
                        height: 3
                    )
                    .frame(width: 68)
                }
            }
        }
    }

    private var volumeIcon: String {
        if isMuted || audioEngine.volume == 0 {
            return "speaker.slash.fill"
        } else if audioEngine.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if audioEngine.volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    private func toggleMute() {
        if isMuted {
            audioEngine.volume = previousVolume > 0 ? previousVolume : 0.5
            isMuted = false
        } else {
            previousVolume = audioEngine.volume
            audioEngine.volume = 0
            isMuted = true
        }
    }
}

// MARK: - Audio Quality Dropdown Menu (Fixed Width, No Icon)

private struct AudioQualityMenu: View {
    @Bindable var audioEngine: AudioPlayerEngine
    @Bindable var qualitySettings = AudioQualitySettings.shared

    var body: some View {
        Menu {
            Section("Качество звука") {
                ForEach(YMAudioQualityPreset.allCases) { preset in
                    Button {
                        audioEngine.setAudioQualityPreset(preset)
                    } label: {
                        HStack {
                            Text(preset.title)
                            if qualitySettings.preset == preset {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section("Предпочитаемый кодек") {
                ForEach(YMAudioCodecPreference.allCases) { codec in
                    Button {
                        audioEngine.setCodecPreference(codec)
                    } label: {
                        HStack {
                            Text(codec.title)
                            if qualitySettings.codecPreference == codec {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            if let formatDetails = audioEngine.currentAudioFormatDetails {
                Section("Аппаратный поток (AVPlayer)") {
                    Text(formatDetails)
                }
            }

            if !audioEngine.availableStreamInfos.isEmpty {
                Section("Доступные потоки трека") {
                    ForEach(audioEngine.availableStreamInfos) { info in
                        Button {
                            audioEngine.selectStreamVariant(info)
                        } label: {
                            HStack {
                                Text(info.displayDescription)
                                if audioEngine.currentStreamInfo?.matchesVariant(info) == true {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Text(badgeTitle)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .frame(width: 76, alignment: .center)
                .padding(.vertical, 4)
                .background(badgeBackground)
                .foregroundColor(badgeForeground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isLosslessActive ? YMTheme.accent.opacity(0.3) : YMTheme.border, lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .frame(width: 76)
        .fixedSize()
        .help("Настройки качества звука")
    }

    private var badgeTitle: String {
        if let info = audioEngine.currentStreamInfo {
            if info.isLossless {
                return "LOSSLESS"
            }
            let codec = info.displayCodec.replacingOccurrences(of: "(MP4)", with: "").trimmingCharacters(in: .whitespaces)
            return "\(info.bitrateInKbps)K \(codec)"
        }
        return audioEngine.qualitySettings.preset.shortBadge
    }

    private var isLosslessActive: Bool {
        audioEngine.currentStreamInfo?.isLossless == true || audioEngine.qualitySettings.preset == .lossless
    }

    private var badgeBackground: Color {
        if isLosslessActive {
            return YMTheme.accent.opacity(0.18)
        }
        return YMTheme.surfaceComponent
    }

    private var badgeForeground: Color {
        if isLosslessActive {
            return YMTheme.accent
        }
        return YMTheme.fg80
    }
}

// MARK: - Isolated Progress Slider

/// Low-frequency integer second time label to eliminate sub-second Text layout invalidations.
private struct FormattedTimeLabel: View {
    let totalSeconds: Int
    let alignment: Alignment
    let foregroundStyle: Color

    var body: some View {
        let mins = max(0, totalSeconds) / 60
        let secs = max(0, totalSeconds) % 60
        Text(String(format: "%d:%02d", mins, secs))
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(foregroundStyle)
            .frame(width: 36, alignment: alignment)
    }
}

extension FormattedTimeLabel: @preconcurrency Equatable {
    static func == (lhs: FormattedTimeLabel, rhs: FormattedTimeLabel) -> Bool {
        lhs.totalSeconds == rhs.totalSeconds &&
        lhs.alignment == rhs.alignment &&
        lhs.foregroundStyle == rhs.foregroundStyle
    }
}

/// Isolated Slider component bound only to `PlaybackProgressTracker`.
/// High-frequency ticks (up to 4-10 times/sec) do not re-render the parent PlayerBar or Navigation split view.
private struct IsolatedProgressSlider: View {
    @Bindable var progressTracker: PlaybackProgressTracker
    let onSeekCommit: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            FormattedTimeLabel(
                totalSeconds: Int(progressTracker.currentTime),
                alignment: .trailing,
                foregroundStyle: YMTheme.fg60
            )

            YMSlider(
                value: Binding(
                    get: { progressTracker.progress },
                    set: { progressTracker.progress = $0 }
                ),
                in: 0...1,
                activeColor: YMTheme.accent,
                trackColor: YMTheme.surfaceComponentHover,
                height: 3,
                onEditingChanged: { editing in
                    progressTracker.isUserSeeking = editing
                    if !editing {
                        onSeekCommit(progressTracker.currentTime)
                    }
                }
            )

            FormattedTimeLabel(
                totalSeconds: Int(progressTracker.duration),
                alignment: .leading,
                foregroundStyle: YMTheme.fg40
            )
        }
    }
}

// MARK: - Clean Hover-Only Circular Icon Button

/// Minimalist player bar icon button that stays uncluttered at rest and reveals a soft circular plate on hover.
private struct PlayerHoverIconButton: View {
    let systemName: String
    let fontSize: CGFloat
    let foregroundColor: Color
    var isActive: Bool = false
    var isDisabled: Bool = false
    var buttonSize: CGFloat = 28
    let helpText: String
    let action: () -> Void

    @UIState private var isHovered = false

    private var plateColor: Color {
        if isActive {
            return YMTheme.accent.opacity(isHovered ? 0.22 : 0.14)
        } else if isHovered && !isDisabled {
            return YMTheme.surfaceComponentHover
        } else {
            return Color.clear
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(width: buttonSize, height: buttonSize)
                .background(Circle().fill(plateColor))
                .contentShape(Circle())
                .animation(.easeInOut(duration: 0.14), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .help(helpText)
    }
}

// MARK: - Individual Artist Button for Player Bar

private struct PlayerBarArtistButton: View {
    let artist: YMArtist
    let onSelect: () -> Void

    @UIState private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            Text(artist.name)
                .font(.system(size: 11))
                .foregroundStyle(isHovered ? YMTheme.fg : YMTheme.fg60)
                .underline(isHovered)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Перейти к исполнителю: \(artist.name)")
    }
}
