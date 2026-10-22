import AppKit
import QuickLookThumbnailing
import SwiftUI

@MainActor
private enum ThumbnailCache {
    static let cache = NSCache<NSString, NSImage>()
}

struct FileIcon: View {
    let url: URL
    let size: CGFloat
    var thumbnails = true

    @State private var thumbnail: NSImage?

    var body: some View {
        Image(nsImage: thumbnail ?? IconCache.icon(for: url))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .task(id: TaskKey(url: url, size: bucket)) { await loadThumbnail() }
    }

    private var bucket: Int { size <= 32 ? 32 : size <= 64 ? 64 : size <= 128 ? 128 : 256 }

    private struct TaskKey: Hashable {
        let url: URL
        let size: Int
    }

    private func loadThumbnail() async {
        guard thumbnails, size >= 48 else { thumbnail = nil; return }
        let key = "\(url.path)#\(bucket)" as NSString
        if let cached = ThumbnailCache.cache.object(forKey: key) { thumbnail = cached; return }
        thumbnail = nil
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: bucket, height: bucket),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
              !Task.isCancelled else { return }
        let image = representation.nsImage
        ThumbnailCache.cache.setObject(image, forKey: key)
        thumbnail = image
    }
}
