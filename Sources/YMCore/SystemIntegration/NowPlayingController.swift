import Foundation
import MediaPlayer
import AppKit

/// Controls macOS System Now Playing metadata in Control Center, menu bar, and lock screen.
/// Updates `MPNowPlayingInfoCenter` strictly on state events (play, pause, track change, queue change, seek finish)
/// to eliminate IPC overhead and keep memory low.
@MainActor
public final class NowPlayingController {
    public static let shared = NowPlayingController()

    private var currentArtworkTask: Task<Void, Never>?
    private var currentTrackId: String?

    public init() {}

    /// Updates Now Playing metadata on track change or initial playback, including queue position and collection metadata.
    public func updateTrack(
        _ track: YMTrack,
        isPlaying: Bool,
        currentTime: Double = 0,
        duration: Double? = nil,
        queueIndex: Int? = nil,
        queueCount: Int? = nil,
        collectionIdentifier: String? = nil
    ) {
        self.currentTrackId = track.id
        var info: [String: Any] = [:]

        info[MPMediaItemPropertyTitle] = track.displayTitle
        info[MPMediaItemPropertyArtist] = track.artistsString

        if let album = track.albums.first {
            info[MPMediaItemPropertyAlbumTitle] = album.title
        }

        let trackDuration = duration ?? (Double(track.durationMs ?? 0) / 1000.0)
        if trackDuration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = trackDuration
        }

        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyIsLiveStream] = false
        info[MPNowPlayingInfoPropertyExternalContentIdentifier] = track.id
        info[MPMediaItemPropertyPersistentID] = NSNumber(value: UInt64(bitPattern: Int64(track.id.hashValue)))

        if let count = queueCount, count > 0 {
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = count
            if let idx = queueIndex {
                info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = max(0, min(idx, count - 1))
            }
        }

        if let collectionId = collectionIdentifier, !collectionId.isEmpty {
            info[MPNowPlayingInfoCollectionIdentifier] = collectionId
        }

        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused

        // Fetch artwork asynchronously and downsample to 300x300 via shared ImagePipeline
        currentArtworkTask?.cancel()
        if let coverUri = track.effectiveCoverUri, !coverUri.isEmpty {
            currentArtworkTask = Task { [weak self] in
                guard let image = await ImagePipeline.shared.image(for: coverUri, size: .artwork) else {
                    return
                }
                guard !Task.isCancelled, let self = self, self.currentTrackId == track.id else { return }
                self.setArtwork(image: image)
            }
        }
    }

    /// Updates queue indices and optional collection identifier in `nowPlayingInfo` without reloading artwork.
    public func updateQueueInfo(
        currentIndex: Int,
        queueCount: Int,
        collectionIdentifier: String? = nil
    ) {
        let center = MPNowPlayingInfoCenter.default()
        guard var currentInfo = center.nowPlayingInfo else { return }

        if queueCount > 0 {
            currentInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = max(0, min(currentIndex, queueCount - 1))
            currentInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = queueCount
        } else {
            currentInfo.removeValue(forKey: MPNowPlayingInfoPropertyPlaybackQueueIndex)
            currentInfo.removeValue(forKey: MPNowPlayingInfoPropertyPlaybackQueueCount)
        }

        if let collectionId = collectionIdentifier, !collectionId.isEmpty {
            currentInfo[MPNowPlayingInfoCollectionIdentifier] = collectionId
        }

        center.nowPlayingInfo = currentInfo
    }

    /// Updates only the playback rate and elapsed time on play / pause toggle
    public func updatePlaybackState(isPlaying: Bool, currentTime: Double) {
        let center = MPNowPlayingInfoCenter.default()
        center.playbackState = isPlaying ? .playing : .paused
        guard var currentInfo = center.nowPlayingInfo else { return }
        currentInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        center.nowPlayingInfo = currentInfo
    }

    /// Updates elapsed time upon seek completion
    public func updatePlaybackPosition(seconds: Double, isPlaying: Bool) {
        let center = MPNowPlayingInfoCenter.default()
        center.playbackState = isPlaying ? .playing : .paused
        guard var currentInfo = center.nowPlayingInfo else { return }
        currentInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
        currentInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        center.nowPlayingInfo = currentInfo
    }

    public func updatePlaybackPosition(currentTime seconds: Double, isPlaying: Bool) {
        updatePlaybackPosition(seconds: seconds, isPlaying: isPlaying)
    }

    /// Sets downsampled artwork into the active nowPlayingInfo dictionary
    private func setArtwork(image: NSImage) {
        guard var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 300, height: 300)) { _ in
            return image
        }
        currentInfo[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
    }

    /// Clears Now Playing center when playback is stopped
    public func clearNowPlaying() {
        currentArtworkTask?.cancel()
        currentArtworkTask = nil
        currentTrackId = nil
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }
}
