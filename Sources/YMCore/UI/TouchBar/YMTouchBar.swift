import SwiftUI

/// Native macOS Touch Bar integration providing playback controls, current track info, and like button.
public struct YMPlaybackTouchBar: ViewModifier {
    @UIState private var audioEngine = AudioPlayerEngine.shared
    @UIState private var likesService = LikesService.shared

    public init() {}

    public func body(content: Content) -> some View {
        let currentTrack = audioEngine.currentTrack
        let isPlaying = audioEngine.isPlaying
        let isWaveMode = audioEngine.isWaveMode
        let isLiked = currentTrack.map { likesService.isLiked(trackId: $0.id) } ?? false

        content
            .touchBar {
                Button {
                    audioEngine.previous()
                } label: {
                    Image(systemName: "backward.fill")
                }
                .accessibilityLabel("Предыдущий трек")
                .disabled(currentTrack == nil)

                Button {
                    audioEngine.togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(isPlaying ? "Пауза" : "Воспроизведение")
                .disabled(currentTrack == nil)

                Button {
                    audioEngine.next()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .accessibilityLabel("Следующий трек")
                .disabled(currentTrack == nil)

                if let track = currentTrack {
                    Text("\(track.displayTitle) — \(track.artistsString)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 220)

                    Button {
                        Task {
                            await likesService.toggleLike(track: track)
                        }
                    } label: {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(isLiked ? YMTheme.heartRed : .primary)
                    }
                    .accessibilityLabel(isLiked ? "Удалить из Мне нравится" : "Мне нравится")

                    if isWaveMode {
                        Button {
                            audioEngine.applyWaveTuning(.moreLikeThis)
                        } label: {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(YMTheme.accent)
                        }
                        .accessibilityLabel("Больше таких треков")
                    }
                }
            }
    }
}

public extension View {
    func ymTouchBar() -> some View {
        modifier(YMPlaybackTouchBar())
    }
}
