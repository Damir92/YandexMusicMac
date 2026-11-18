import Foundation
import AppKit

/// MainActor-isolated image cache pipeline with configurable RAM cost limit (default 15 MB)
/// and off-main-thread hardware-accelerated downsampling via ImageIO (`CGImage` crosses
/// concurrency boundaries cleanly across macOS 14/15/27 SDKs without requiring `NSImage: Sendable`).
@MainActor
public final class ImagePipeline {
    public static let shared = ImagePipeline()

    private let memoryCache: NSCache<NSString, NSImage>
    private var inFlightTasks: [String: Task<(CGImage, Int)?, Never>] = [:]

    public init(maxMemoryCost: Int = 15 * 1024 * 1024) {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = maxMemoryCost
        cache.countLimit = 250 // Жесткий потолок количества обложек в ОЗУ
        self.memoryCache = cache
    }

    /// Dynamically adjusts the memory cache cost limit in megabytes
    public func setMaxMemoryCost(mb: Int) {
        memoryCache.totalCostLimit = max(5, mb) * 1024 * 1024
    }

    /// Fetches image from cache or downloads and downsamples asynchronously off the main thread
    public func image(for coverUri: String?, size: YMCoverSize = .medium) async -> NSImage? {
        guard let coverUri = coverUri, !coverUri.isEmpty else { return nil }

        let keyString = "\(coverUri)_\(size.rawValue)"
        let cacheKey = keyString as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        if let existingTask = inFlightTasks[keyString] {
            if let (cgImage, _) = await existingTask.value {
                if let cached = memoryCache.object(forKey: cacheKey) {
                    return cached
                }
                let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                return image
            }
            return nil
        }

        guard let url = YMCoverURLBuilder.buildURL(from: coverUri, size: size) else {
            return nil
        }

        let maxPixelSize: CGFloat
        switch size {
        case .small: maxPixelSize = 100
        case .medium: maxPixelSize = 200
        case .artwork: maxPixelSize = 300
        case .large: maxPixelSize = 400
        }

        let task = Task.detached(priority: .userInitiated) { () -> (CGImage, Int)? in
            guard let result = await ImageDownsampler.fetchAndDownsampleCGImageWithCost(from: url, maxPixelSize: maxPixelSize),
                  !Task.isCancelled else {
                return nil
            }
            return result
        }

        inFlightTasks[keyString] = task
        let decoded = await task.value
        inFlightTasks.removeValue(forKey: keyString)

        guard let (cgImage, byteCost) = decoded else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        memoryCache.setObject(image, forKey: cacheKey, cost: byteCost)
        return image
    }

    public func clearCache() {
        memoryCache.removeAllObjects()
    }

    public func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }
}
