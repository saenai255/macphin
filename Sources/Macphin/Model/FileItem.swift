import AppKit
import Darwin
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
    let permissions: String
    let owner: String

    var id: URL { url }
    var opensAsFolder: Bool { isDirectory && !isPackage }
    var sizeForSort: Int64 { isDirectory ? -1 : size }
    var location: String { url.deletingLastPathComponent().path }

    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .creationDateKey, .contentTypeKey,
    ]

    private static let typeNameLock = NSLock()
    private static var typeNames: [String: String] = [:]

    // Per-file localized descriptions hit LaunchServices; caching per type keeps large folders fast.
    private static func typeName(for type: UTType?, isDirectory: Bool) -> String {
        guard let type else { return isDirectory ? "Folder" : "Document" }
        typeNameLock.lock()
        defer { typeNameLock.unlock() }
        if let cached = typeNames[type.identifier] { return cached }
        let name = type.localizedDescription ?? (isDirectory ? "Folder" : "Document")
        typeNames[type.identifier] = name
        return name
    }

    private static let ownerLock = NSLock()
    private static var ownerNames: [uid_t: String] = [:]

    init(url: URL) {
        let keys = Set(Self.resourceKeys)
        let values = try? url.resourceValues(forKeys: keys)
        self.url = url
        name = url.lastPathComponent
        isDirectory = values?.isDirectory ?? false
        isPackage = values?.isPackage ?? false
        isHidden = values?.isHidden ?? url.lastPathComponent.hasPrefix(".")
        isSymlink = values?.isSymbolicLink ?? false
        size = Int64(values?.fileSize ?? 0)
        modified = values?.contentModificationDate ?? .distantPast
        created = values?.creationDate ?? .distantPast
        kind = Self.typeName(for: values?.contentType, isDirectory: isDirectory)

        var info = stat()
        if lstat(url.path, &info) == 0 {
            permissions = Self.permissionString(mode: info.st_mode)
            owner = Self.ownerName(for: info.st_uid)
        } else {
            permissions = "?????????"
            owner = "?"
        }
    }

    private static func permissionString(mode: mode_t) -> String {
        let bits: [(mode_t, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x"),
        ]
        return String(bits.map { mode & $0.0 == 0 ? "-" : $0.1 })
    }

    private static func ownerName(for uid: uid_t) -> String {
        ownerLock.lock()
        defer { ownerLock.unlock() }
        if let cached = ownerNames[uid] { return cached }
        let name = getpwuid(uid).map { String(cString: $0.pointee.pw_name) }
            ?? (uid == getuid() ? NSUserName() : "?")
        ownerNames[uid] = name
        return name
    }

    var formattedSize: String {
        opensAsFolder ? "—" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum SortKey: String, CaseIterable, Identifiable {
    case name, size, modified, created, kind
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: "Name"
        case .size: "Size"
        case .modified: "Modified"
        case .created: "Created"
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
