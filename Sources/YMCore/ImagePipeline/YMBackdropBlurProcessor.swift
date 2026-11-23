import Foundation
import AppKit
import CoreImage

/// Sendable wrapper isolating the shared CIContext across concurrency boundaries.
private final class SendableCIContextBox: @unchecked Sendable {
    let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false
    ])
}

/// Centralized off-main-thread pre-blur processor for ambient cover art glows and backdrops.
/// Pre-blurs a small downsampled 100x100 bitmap ONCE per track change (<1 ms, ~40 KB)
/// so SwiftUI views can render atmospheric glow backgrounds as simple textured quads
/// without any live multi-pass GPU Gaussian blur shaders during scrolling (120 FPS).
@MainActor
public final class YMBackdropBlurProcessor {
    public static let shared = YMBackdropBlurProcessor()

    private nonisolated static let ciBox = SendableCIContextBox()
    private let memoryCache: NSCache<NSString, NSImage>
    private var inFlightTasks: [String: Task<CGImage?, Never>] = [:]

    public init() {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 25
        cache.totalCostLimit = 2 * 1024 * 1024 // 2 MB limit
        self.memoryCache = cache
    }

    /// Fetches the small cover art from ImagePipeline, applies hardware CoreImage blur once,
    /// and caches the resulting NSImage for instantaneous 120 FPS rendering.
    public func blurredImage(for coverUri: String?, radius: Double = 16.0) async -> NSImage? {
        guard let coverUri = coverUri, !coverUri.isEmpty else { return nil }

        let keyString = "\(coverUri)_\(Int(radius))"
        let cacheKey = keyString as NSString
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        if let existingTask = inFlightTasks[keyString] {
            if let blurredCG = await existingTask.value {
                if let cached = memoryCache.object(forKey: cacheKey) {
                    return cached
                }
                let result = NSImage(
                    cgImage: blurredCG,
                    size: NSSize(width: blurredCG.width, height: blurredCG.height)
                )
                return result
            }
            return nil
        }

        guard let smallImage = await ImagePipeline.shared.image(for: coverUri, size: .small),
              let cgImage = smallImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }

        let task = Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard !Task.isCancelled else { return nil }
            return Self.makeBlurredCGImage(from: cgImage, radius: radius)
        }

        inFlightTasks[keyString] = task
        let blurredCG = await task.value
        inFlightTasks.removeValue(forKey: keyString)

        guard let blurredCG, !Task.isCancelled else { return nil }

        let result = NSImage(
            cgImage: blurredCG,
            size: NSSize(width: blurredCG.width, height: blurredCG.height)
        )
        let cost = blurredCG.bytesPerRow * blurredCG.height
        memoryCache.setObject(result, forKey: cacheKey, cost: cost)
        return result
    }

    /// Applies `CIGaussianBlur` to a `CGImage` with clamped extent to prevent darkening around edges.
    public nonisolated static func makeBlurredCGImage(from cgImage: CGImage, radius: Double = 16.0) -> CGImage? {
        let input = CIImage(cgImage: cgImage)
        let extent = input.extent
        guard !extent.isEmpty else { return nil }

        let clamped = input.clampedToExtent()
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(clamped, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let output = filter.outputImage?.cropped(to: extent) else { return nil }
        return ciBox.context.createCGImage(output, from: extent)
    }

    public func clearCache() {
        for task in inFlightTasks.values {
            task.cancel()
        }
        inFlightTasks.removeAll()
        memoryCache.removeAllObjects()
    }
}
