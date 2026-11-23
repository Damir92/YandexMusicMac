import SwiftUI

private struct CoverTaskID: Equatable {
    let uri: String?
    let size: YMCoverSize
}

/// SwiftUI component for smoothly rendering downsampled, cached album art
public struct CachedCoverImage: View {
    let coverUri: String?
    let size: YMCoverSize
    let displaySize: CGFloat
    let cornerRadius: CGFloat

    @UIState private var loadedImage: NSImage? = nil
    @UIState private var loadedTaskID: CoverTaskID? = nil

    private var currentTaskID: CoverTaskID {
        CoverTaskID(uri: coverUri, size: size)
    }

    private var resolvedImage: NSImage? {
        if let loadedImage, loadedTaskID == currentTaskID {
            return loadedImage
        }
        guard let coverUri, !coverUri.isEmpty else { return nil }
        return ImagePipeline.shared.cachedImage(for: coverUri, size: size)
    }

    public init(
        coverUri: String?,
        size: YMCoverSize = .small,
        displaySize: CGFloat = 40,
        cornerRadius: CGFloat = 6
    ) {
        self.coverUri = coverUri
        self.size = size
        self.displaySize = displaySize
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Group {
            if let nsImage = resolvedImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.secondary.opacity(0.15))
                    Image(systemName: "music.note")
                        .font(.system(size: displaySize * 0.4))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: displaySize, height: displaySize)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: currentTaskID) {
            let targetID = currentTaskID
            guard let coverUri = coverUri, !coverUri.isEmpty else {
                if loadedImage != nil {
                    loadedImage = nil
                    loadedTaskID = nil
                }
                return
            }
            // Уже есть в RAM-кэше и синхронно отрисовано через resolvedImage — не запускаем лишнюю перерисовку!
            if ImagePipeline.shared.cachedImage(for: coverUri, size: size) != nil {
                if loadedImage != nil && loadedTaskID != targetID {
                    loadedImage = nil
                    loadedTaskID = nil
                }
                return
            }
            if loadedImage != nil {
                loadedImage = nil
                loadedTaskID = nil
            }
            let image = await ImagePipeline.shared.image(for: coverUri, size: size)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.14)) {
                loadedImage = image
                loadedTaskID = targetID
            }
        }
    }
}
