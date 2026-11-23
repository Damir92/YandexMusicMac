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

    private nonisolated static func stablePersistentID(for id: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

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
        info[MPMediaItemPropertyPersistentID] = NSNumber(value: Self.stablePersistentID(for: track.id))

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
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0

        currentArtworkTask?.cancel()
        currentArtworkTask = nil
        let coverUri = track.effectiveCoverUri
        if let coverUri = coverUri, !coverUri.isEmpty {
            if let cached = ImagePipeline.shared.cachedImage(for: coverUri, size: .artwork),
               let cgImage = cached.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                info[MPMediaItemPropertyArtwork] = Self.makeArtwork(from: cgImage)
            } else {
                currentArtworkTask = Task { [weak self] in
                    guard let image = await ImagePipeline.shared.image(for: coverUri, size: .artwork) else {
                        return
                    }
                    guard !Task.isCancelled, let self = self, self.currentTrackId == track.id else { return }
                    self.setArtwork(image: image)
                }
            }
        }

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
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

    /// Updates duration in nowPlayingInfo if significantly changed
    public func updateDuration(_ duration: Double) {
        guard duration.isFinite && duration > 0 else { return }
        let center = MPNowPlayingInfoCenter.default()
        guard var currentInfo = center.nowPlayingInfo else { return }
        let existingDuration = currentInfo[MPMediaItemPropertyPlaybackDuration] as? Double ?? 0
        if abs(existingDuration - duration) >= 0.5 {
            currentInfo[MPMediaItemPropertyPlaybackDuration] = duration
            center.nowPlayingInfo = currentInfo
        }
    }

    /// Sets downsampled artwork into the active nowPlayingInfo dictionary
    private func setArtwork(image: NSImage) {
        guard var currentInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            currentInfo[MPMediaItemPropertyArtwork] = Self.makeArtwork(from: cgImage)
        } else {
            currentInfo.removeValue(forKey: MPMediaItemPropertyArtwork)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = currentInfo
    }

    /// Builds `MPMediaItemArtwork` outside of the main actor directly from Sendable `CGImage`.
    private nonisolated static func makeArtwork(from cgImage: CGImage) -> MPMediaItemArtwork {
        let bounds = CGSize(width: 300, height: 300)
        return MPMediaItemArtwork(boundsSize: bounds) { @Sendable _ in
            NSImage(cgImage: cgImage, size: bounds)
        }
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
