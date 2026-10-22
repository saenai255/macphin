import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum Thumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func bucket(for size: CGFloat) -> Int {
        size <= 32 ? 32 : size <= 64 ? 64 : size <= 128 ? 128 : 256
    }

    static func cached(_ url: URL, bucket: Int) -> NSImage? {
        cache.object(forKey: key(url, bucket))
    }

    static func load(_ url: URL, bucket: Int) async -> NSImage? {
        if let cached = cached(url, bucket: bucket) { return cached }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: bucket, height: bucket),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: representation(for: url))
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = representation.nsImage
        cache.setObject(image, forKey: key(url, bucket))
        return image
    }

    // Raw thumbnails of documents lack the page frame; the icon representation adds it, like Finder.
    private static func representation(for url: URL) -> QLThumbnailGenerator.Request.RepresentationTypes {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return .icon }
        return [.image, .movie, .pdf].contains(where: type.conforms(to:)) ? .thumbnail : .icon
    }

    private static func key(_ url: URL, _ bucket: Int) -> NSString { "\(url.path)#\(bucket)" as NSString }
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
            .task(id: TaskKey(url: url, size: Thumbnails.bucket(for: size))) { await loadThumbnail() }
    }

    private struct TaskKey: Hashable {
        let url: URL
        let size: Int
    }

    private func loadThumbnail() async {
        guard thumbnails, size >= 48 else { thumbnail = nil; return }
        let bucket = Thumbnails.bucket(for: size)
        thumbnail = Thumbnails.cached(url, bucket: bucket)
        guard thumbnail == nil, let image = await Thumbnails.load(url, bucket: bucket), !Task.isCancelled else { return }
        thumbnail = image
    }
}
