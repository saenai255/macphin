import AppKit
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let isSymlink: Bool
    let size: Int64
    let modified: Date
    let created: Date
    let kind: String

    var id: URL { url }
    var opensAsFolder: Bool { isDirectory && !isPackage }
    var sizeForSort: Int64 { isDirectory ? -1 : size }

    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .creationDateKey, .localizedTypeDescriptionKey,
    ]

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys))
        self.url = url
        name = url.lastPathComponent
        isDirectory = values?.isDirectory ?? false
        isPackage = values?.isPackage ?? false
        isHidden = values?.isHidden ?? url.lastPathComponent.hasPrefix(".")
        isSymlink = values?.isSymbolicLink ?? false
        size = Int64(values?.fileSize ?? 0)
        modified = values?.contentModificationDate ?? .distantPast
        created = values?.creationDate ?? .distantPast
        kind = values?.localizedTypeDescription ?? (isDirectory ? "Folder" : "Document")
    }

    var formattedSize: String {
        opensAsFolder ? "—" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum SortKey: String, CaseIterable, Identifiable {
    case name, size, modified, kind
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: "Name"
        case .size: "Size"
        case .modified: "Modified"
        case .kind: "Type"
        }
    }
}

enum ViewMode: String, CaseIterable, Identifiable, Codable {
    case icons, compact, details
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .icons: "square.grid.2x2"
        case .compact: "rectangle.grid.1x2"
        case .details: "list.bullet"
        }
    }
}

@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        if let cached = cache[url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        if cache.count > 5000 { cache.removeAll() }
        cache[url.path] = image
        return image
    }

    static func invalidate() { cache.removeAll() }
}
