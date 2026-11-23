import Foundation
import MediaPlayer

/// Manages macOS System Remote Command Center integration (Media Keys, Touch Bar, Control Center).
@MainActor
public final class RemoteCommandManager {
    public static let shared = RemoteCommandManager()

    private weak var playerEngine: AudioPlayerEngine?
    public var onLikeToggled: (@Sendable () -> Void)?
    nonisolated(unsafe) private var commandTargets: [(MPRemoteCommand, Any)] = []

    public init(playerEngine: AudioPlayerEngine = AudioPlayerEngine.shared) {
        self.playerEngine = playerEngine
        setupCommands()
    }

    deinit {
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
    }

    public func unregisterCommands() {
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
        commandTargets.removeAll()
    }

    public func configure(with engine: AudioPlayerEngine) {
        self.playerEngine = engine
    }

    public func updateLikeState(isLiked: Bool) {
        MPRemoteCommandCenter.shared().likeCommand.isActive = isLiked
    }

    private func setupCommands() {
        unregisterCommands()

        let commandCenter = MPRemoteCommandCenter.shared()

        // Play / Pause / Toggle
        commandCenter.playCommand.isEnabled = true
        let playTarget = commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playerEngine?.play()
            }
            return .success
        }
        commandTargets.append((commandCenter.playCommand, playTarget))

        commandCenter.pauseCommand.isEnabled = true
        let pauseTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playerEngine?.pause()
            }
            return .success
        }
        commandTargets.append((commandCenter.pauseCommand, pauseTarget))

        commandCenter.togglePlayPauseCommand.isEnabled = true
        let toggleTarget = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playerEngine?.togglePlayPause()
            }
            return .success
        }
        commandTargets.append((commandCenter.togglePlayPauseCommand, toggleTarget))

        // Track navigation
        commandCenter.nextTrackCommand.isEnabled = true
        let nextTarget = commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playerEngine?.next()
            }
            return .success
        }
        commandTargets.append((commandCenter.nextTrackCommand, nextTarget))

        commandCenter.previousTrackCommand.isEnabled = true
        let prevTarget = commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playerEngine?.previous()
            }
            return .success
        }
        commandTargets.append((commandCenter.previousTrackCommand, prevTarget))

        // Seek scrubber
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        let seekTarget = commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let positionTime = positionEvent.positionTime
            Task { @MainActor [weak self] in
                self?.playerEngine?.seek(to: positionTime)
                NowPlayingController.shared.updatePlaybackPosition(seconds: positionTime, isPlaying: self?.playerEngine?.isPlaying ?? false)
            }
            return .success
        }
        commandTargets.append((commandCenter.changePlaybackPositionCommand, seekTarget))

        // Like command
        commandCenter.likeCommand.isEnabled = true
        commandCenter.likeCommand.localizedTitle = "Мне нравится"
        let likeTarget = commandCenter.likeCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                if let onLikeToggled = self?.onLikeToggled {
                    onLikeToggled()
                } else if let currentTrack = self?.playerEngine?.currentTrack {
                    await LikesService.shared.toggleLike(track: currentTrack)
                    self?.updateLikeState(isLiked: LikesService.shared.isLiked(trackId: currentTrack.id))
                }
            }
            return .success
        }
        commandTargets.append((commandCenter.likeCommand, likeTarget))
    }
}
