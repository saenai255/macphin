import AppKit

struct FileMove: Hashable, Sendable {
    let from: URL
    let to: URL
}

indirect enum FileChange: Sendable {
    case moved([FileMove])
    case created([URL])
    case trashed([FileMove])
    case group([FileChange])

    var isEmpty: Bool {
        switch self {
        case .moved(let moves), .trashed(let moves): moves.isEmpty
        case .created(let urls): urls.isEmpty
        case .group(let changes): changes.allSatisfy(\.isEmpty)
        }
    }
}

enum ConflictPolicy: Sendable {
    case keepBoth, replace, skip
}

final class ChangeLog: @unchecked Sendable {
    private(set) var changes: [FileChange] = []

    func record(_ change: FileChange) {
        if !change.isEmpty { changes.append(change) }
    }

    var combined: FileChange? {
        switch changes.count {
        case 0: nil
        case 1: changes[0]
        default: .group(changes)
        }
    }
}

enum FileOperations {
    static func itemExists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    static func uniqueURL(for name: String, in directory: URL) -> URL {
        var candidate = directory.appending(path: name)
        guard itemExists(candidate) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        repeat {
            let numbered = "\(base) \(counter)"
            candidate = directory.appending(path: ext.isEmpty ? numbered : "\(numbered).\(ext)")
            counter += 1
        } while itemExists(candidate)
        return candidate
    }

    static func conflicts(for sources: [URL], in directory: URL) -> [URL] {
        sources.filter { !isSameFolder($0, directory) && itemExists(directory.appending(path: $0.lastPathComponent)) }
    }

    @discardableResult
    static func createFolder(in directory: URL, name: String = "New Folder", log: ChangeLog? = nil) throws -> URL {
        let url = uniqueURL(for: name, in: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        log?.record(.created([url]))
        return url
    }

    @discardableResult
    static func createFile(in directory: URL, name: String = "Untitled.txt", log: ChangeLog? = nil) throws -> URL {
        let url = uniqueURL(for: name, in: directory)
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        log?.record(.created([url]))
        return url
    }

    @discardableResult
    static func rename(_ url: URL, to newName: String, log: ChangeLog? = nil) throws -> URL {
        let directory = url.deletingLastPathComponent()
        let destination = directory.appending(path: newName)
        guard newName != url.lastPathComponent else { return url }
        if newName.lowercased() == url.lastPathComponent.lowercased() {
            // Case-only renames need a hop on case-insensitive volumes.
            let temporary = uniqueURL(for: ".macphin-rename-\(UUID().uuidString)", in: directory)
            try FileManager.default.moveItem(at: url, to: temporary)
            try FileManager.default.moveItem(at: temporary, to: destination)
        } else {
            guard !itemExists(destination) else {
                throw CocoaError(.fileWriteFileExists, userInfo: [
                    NSLocalizedDescriptionKey: "An item named “\(newName)” already exists in this location."])
            }
            try FileManager.default.moveItem(at: url, to: destination)
        }
        log?.record(.moved([FileMove(from: url, to: destination)]))
        return destination
    }

    static func copy(_ urls: [URL], to directory: URL, policy: ConflictPolicy = .keepBoth, log: ChangeLog? = nil) throws {
        for url in urls {
            guard let destination = try destination(for: url, in: directory, policy: policy, isCopy: true, log: log) else { continue }
            try FileManager.default.copyItem(at: url, to: destination)
            log?.record(.created([destination]))
        }
    }

    static func move(_ urls: [URL], to directory: URL, policy: ConflictPolicy = .keepBoth, log: ChangeLog? = nil) throws {
        for url in urls {
            guard let destination = try destination(for: url, in: directory, policy: policy, isCopy: false, log: log) else { continue }
            try FileManager.default.moveItem(at: url, to: destination)
            log?.record(.moved([FileMove(from: url, to: destination)]))
        }
    }

    static func duplicate(_ urls: [URL], log: ChangeLog? = nil) throws {
        for url in urls {
            let destination = uniqueURL(for: copyName(for: url), in: url.deletingLastPathComponent())
            try FileManager.default.copyItem(at: url, to: destination)
            log?.record(.created([destination]))
        }
    }

    static func trash(_ urls: [URL], log: ChangeLog? = nil) throws {
        for url in urls {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            if let trashed = resulting as URL? { log?.record(.trashed([FileMove(from: url, to: trashed)])) }
        }
    }

    static func deletePermanently(_ urls: [URL]) throws {
        for url in urls { try FileManager.default.removeItem(at: url) }
    }

    static func compress(_ urls: [URL], log: ChangeLog? = nil) throws {
        guard let first = urls.first else { return }
        let directory = first.deletingLastPathComponent()
        let archiveName = urls.count == 1 ? "\(first.lastPathComponent).zip" : "Archive.zip"
        let destination = uniqueURL(for: archiveName, in: directory)
        let process = Process()
        if urls.count == 1 {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, destination.path]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = directory
            process.arguments = ["-r", "-q", destination.path] + urls.map(\.lastPathComponent)
        }
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "Compression failed."])
        }
        log?.record(.created([destination]))
    }

    static func invert(_ change: FileChange) throws -> FileChange {
        switch change {
        case .moved(let moves):
            var reversed: [FileMove] = []
            for move in moves.reversed() {
                let back = availableURL(move.from)
                try FileManager.default.moveItem(at: move.to, to: back)
                reversed.append(FileMove(from: move.to, to: back))
            }
            return .moved(reversed)
        case .created(let urls):
            let log = ChangeLog()
            try trash(urls.filter(itemExists), log: log)
            return log.combined ?? .group([])
        case .trashed(let moves):
            var restored: [URL] = []
            for move in moves.reversed() {
                let back = availableURL(move.from)
                try FileManager.default.createDirectory(at: back.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: move.to, to: back)
                restored.append(back)
            }
            return .created(restored)
        case .group(let changes):
            return .group(try changes.reversed().map(invert))
        }
    }

    private static func destination(for source: URL, in directory: URL, policy: ConflictPolicy, isCopy: Bool, log: ChangeLog?) throws -> URL? {
        if isSameFolder(source, directory) {
            return isCopy ? uniqueURL(for: copyName(for: source), in: directory) : nil
        }
        let sourcePath = source.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        guard directoryPath != sourcePath, !directoryPath.hasPrefix(sourcePath + "/") else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [
                NSLocalizedDescriptionKey: "Cannot put “\(source.lastPathComponent)” inside itself."])
        }
        let destination = directory.appending(path: source.lastPathComponent)
        guard itemExists(destination) else { return destination }
        switch policy {
        case .skip:
            return nil
        case .keepBoth:
            return uniqueURL(for: source.lastPathComponent, in: directory)
        case .replace:
            guard !sourcePath.hasPrefix(destination.standardizedFileURL.path + "/") else {
                throw CocoaError(.fileWriteInvalidFileName, userInfo: [
                    NSLocalizedDescriptionKey: "Cannot replace “\(destination.lastPathComponent)” with an item it contains."])
            }
            try trash([destination], log: log)
            return destination
        }
    }

    private static func isSameFolder(_ url: URL, _ directory: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
    }

    private static func availableURL(_ url: URL) -> URL {
        itemExists(url) ? uniqueURL(for: url.lastPathComponent, in: url.deletingLastPathComponent()) : url
    }

    private static func copyName(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        return ext.isEmpty ? "\(base) copy" : "\(base) copy.\(ext)"
    }
}

@MainActor
enum FileClipboard {
    private static var cutURLs: [URL] = []

    static func write(_ urls: [URL], cut: Bool) {
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        cutURLs = cut ? urls : []
    }

    static var urls: [URL] {
        NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    static var hasContent: Bool { !urls.isEmpty }

    static func takePasteOperation() -> (urls: [URL], isMove: Bool) {
        let urls = self.urls
        let isMove = !cutURLs.isEmpty && Set(cutURLs) == Set(urls)
        if isMove { cutURLs = [] }
        return (urls, isMove)
    }

    static func copyPaths(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }
}

@MainActor
@Observable
final class FileUndoStack {
    static let shared = FileUndoStack()

    struct Entry: Sendable {
        let name: String
        let change: FileChange
    }

    private(set) var undoEntries: [Entry] = []
    private(set) var redoEntries: [Entry] = []
    private(set) var isBusy = false

    var undoTitle: String { undoEntries.last.map { "Undo \($0.name)" } ?? "Undo" }
    var redoTitle: String { redoEntries.last.map { "Redo \($0.name)" } ?? "Redo" }

    func register(_ name: String, _ change: FileChange?) {
        guard let change, !change.isEmpty else { return }
        undoEntries.append(Entry(name: name, change: change))
        if undoEntries.count > 100 { undoEntries.removeFirst() }
        redoEntries.removeAll()
    }

    func undo(onError: @escaping @MainActor (String) -> Void) { step(isUndo: true, onError: onError) }
    func redo(onError: @escaping @MainActor (String) -> Void) { step(isUndo: false, onError: onError) }

    private func step(isUndo: Bool, onError: @escaping @MainActor (String) -> Void) {
        guard !isBusy, let entry = isUndo ? undoEntries.popLast() : redoEntries.popLast() else { return }
        isBusy = true
        Task.detached {
            do {
                let inverse = Entry(name: entry.name, change: try FileOperations.invert(entry.change))
                await MainActor.run {
                    self.isBusy = false
                    if isUndo { self.redoEntries.append(inverse) } else { self.undoEntries.append(inverse) }
                }
            } catch {
                let message = "Could not \(isUndo ? "undo" : "redo") \(entry.name.lowercased()): \(error.localizedDescription)"
                await MainActor.run {
                    self.isBusy = false
                    onError(message)
                }
            }
        }
    }
}
