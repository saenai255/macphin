import AppKit
import SwiftUI

struct InfoPanel: View {
    let pane: PaneState

    var body: some View {
        let selected = pane.selectedItems
        ScrollView {
            VStack(spacing: 12) {
                if selected.count > 1 {
                    Image(systemName: "doc.on.doc").font(.system(size: 64)).foregroundStyle(.secondary)
                    Text("\(selected.count) items selected").font(.headline)
                    InfoRow(label: "Total size", value: ByteCountFormatter.string(
                        fromByteCount: selected.reduce(0) { $0 + $1.size }, countStyle: .file))
                } else {
                    ItemInfo(url: selected.first?.url ?? pane.url)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ItemInfo: View {
    let url: URL
    @State private var details = Details()

    struct Details {
        var kind = ""
        var size = ""
        var contents: String?
        var created: Date?
        var modified: Date?
        var accessed: Date?
        var permissions = ""
        var owner = ""
        var dimensions: String?
    }

    var body: some View {
        VStack(spacing: 12) {
            FileIcon(url: url, size: 160)
                .shadow(radius: 2)
            Text(FileManager.default.displayName(atPath: url.path))
                .font(.headline)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                InfoRow(label: "Type", value: details.kind)
                InfoRow(label: "Size", value: details.size)
                if let contents = details.contents { InfoRow(label: "Contents", value: contents) }
                if let dimensions = details.dimensions { InfoRow(label: "Dimensions", value: dimensions) }
                if let created = details.created { InfoRow(label: "Created", value: created.formatted(date: .abbreviated, time: .shortened)) }
                if let modified = details.modified { InfoRow(label: "Modified", value: modified.formatted(date: .abbreviated, time: .shortened)) }
                if let accessed = details.accessed { InfoRow(label: "Accessed", value: accessed.formatted(date: .abbreviated, time: .shortened)) }
                InfoRow(label: "Permissions", value: details.permissions)
                InfoRow(label: "Owner", value: details.owner)
                InfoRow(label: "Location", value: url.deletingLastPathComponent().path)
            }
            .font(.callout)
        }
        .task(id: url) { details = await Self.load(url) }
    }

    private static func load(_ url: URL) async -> Details {
        await Task.detached(priority: .utility) {
            var d = Details()
            let keys: Set<URLResourceKey> = [.localizedTypeDescriptionKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                                             .isDirectoryKey, .isPackageKey, .creationDateKey,
                                             .contentModificationDateKey, .contentAccessDateKey]
            let values = try? url.resourceValues(forKeys: keys)
            d.kind = values?.localizedTypeDescription ?? ""
            d.created = values?.creationDate
            d.modified = values?.contentModificationDate
            d.accessed = values?.contentAccessDate
            if values?.isDirectory == true {
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])
                var total: Int64 = 0, files = 0, folders = 0
                let deadline = Date().addingTimeInterval(2)
                while let child = enumerator?.nextObject() as? URL, Date() < deadline {
                    let v = try? child.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                    if v?.isDirectory == true { folders += 1 } else { files += 1; total += Int64(v?.fileSize ?? 0) }
                }
                let partial = Date() >= deadline ? "≥ " : ""
                d.size = partial + ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                d.contents = "\(partial)\(files) files, \(folders) folders"
            } else {
                d.size = ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
                if let image = NSImageRep(contentsOf: url) {
                    d.dimensions = "\(image.pixelsWide) × \(image.pixelsHigh)"
                }
            }
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
                d.permissions = permissionString(mode)
                d.owner = "\(attributes[.ownerAccountName] as? String ?? "?"):\(attributes[.groupOwnerAccountName] as? String ?? "?")"
            }
            return d
        }.value
    }

    nonisolated private static func permissionString(_ mode: UInt16) -> String {
        let chars = Array("rwxrwxrwx")
        let bits = (0..<9).map { index in mode & (1 << (8 - index)) != 0 ? chars[index] : "-" }
        return String(bits) + String(format: " (%o)", mode)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).lineLimit(3).truncationMode(.middle)
        }
    }
}
