import Foundation
import Observation

/// Persistent configuration service for audio stream quality and codec preferences.
@Observable
@MainActor
public final class AudioQualitySettings {
    public static let shared = AudioQualitySettings()

    private let presetKey = "ym_audio_quality_preset"
    private let codecKey = "ym_audio_codec_pref"
    private let preloadFavoritesKey = "ym_preload_favorites_bg"
    private let imageCacheLimitKey = "ym_image_cache_limit_mb"
    private let crossfadeDurationKey = "ym_audio_crossfade_seconds"

    public var preset: YMAudioQualityPreset {
        didSet {
            UserDefaults.standard.set(preset.rawValue, forKey: presetKey)
        }
    }

    public var codecPreference: YMAudioCodecPreference {
        didSet {
            UserDefaults.standard.set(codecPreference.rawValue, forKey: codecKey)
        }
    }

    /// Background preload mode for entire Favorites library (default false for 45-65 MB memory limit)
    public var preloadAllFavoritesInBackground: Bool {
        didSet {
            UserDefaults.standard.set(preloadAllFavoritesInBackground, forKey: preloadFavoritesKey)
            if preloadAllFavoritesInBackground {
                LikesService.shared.startBackgroundCatalogPreload()
            } else {
                LikesService.shared.stopBackgroundCatalogPreloadAndPrune()
            }
        }
    }

    /// Maximum memory limit for cover images in megabytes (10, 15, 20, 50; default 15 MB)
    public var imageCacheLimitMB: Int {
        didSet {
            UserDefaults.standard.set(imageCacheLimitMB, forKey: imageCacheLimitKey)
            ImagePipeline.shared.setMaxMemoryCost(mb: imageCacheLimitMB)
        }
    }

    /// Smooth crossfade duration between consecutive tracks in seconds (0.0...12.0; 0.0 = disabled)
    public var crossfadeDuration: Double {
        didSet {
            let clamped = max(0.0, min(12.0, crossfadeDuration))
            if crossfadeDuration != clamped {
                crossfadeDuration = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: crossfadeDurationKey)
        }
    }

    public init() {
        let savedPresetStr = UserDefaults.standard.string(forKey: presetKey)
        let resolvedPreset = savedPresetStr.flatMap(YMAudioQualityPreset.init(rawValue:)) ?? .high320

        let savedCodecStr = UserDefaults.standard.string(forKey: codecKey)
        let resolvedCodec = savedCodecStr.flatMap(YMAudioCodecPreference.init(rawValue:)) ?? .any

        let savedPreload = UserDefaults.standard.bool(forKey: preloadFavoritesKey)
        let savedImageLimit = UserDefaults.standard.integer(forKey: imageCacheLimitKey)
        let resolvedImageLimit = savedImageLimit > 0 ? savedImageLimit : 15

        let savedCrossfade = UserDefaults.standard.double(forKey: crossfadeDurationKey)
        let resolvedCrossfade = max(0.0, min(12.0, savedCrossfade))

        self.preset = resolvedPreset
        self.codecPreference = resolvedCodec
        self.preloadAllFavoritesInBackground = savedPreload
        self.imageCacheLimitMB = resolvedImageLimit
        self.crossfadeDuration = resolvedCrossfade

        ImagePipeline.shared.setMaxMemoryCost(mb: resolvedImageLimit)
    }

    public func setPreset(_ newPreset: YMAudioQualityPreset) {
        self.preset = newPreset
    }

    public func setCodecPreference(_ newCodec: YMAudioCodecPreference) {
        self.codecPreference = newCodec
    }

    public func setPreloadFavoritesInBackground(_ enabled: Bool) {
        self.preloadAllFavoritesInBackground = enabled
    }

    public func setImageCacheLimitMB(_ limit: Int) {
        self.imageCacheLimitMB = limit
    }

    public func setCrossfadeDuration(_ seconds: Double) {
        self.crossfadeDuration = max(0.0, min(12.0, seconds))
    }

    /// Drops unnecessary cached data, trims search buffer and clears image/network caches to drop RAM to 40-50 MB
    public func purgeUnusedMemory() {
        LikesService.shared.compressMemory()
        ImagePipeline.shared.clearMemoryCache()
        Task {
            await YMNetworkClient.shared.clearCache()
        }
    }
}
