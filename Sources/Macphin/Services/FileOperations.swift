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

final class OperationProgress: @unchecked Sendable {
    struct Snapshot {
        var completed: Int64
        var total: Int64
        var currentName: String
        var fraction: Double { total > 0 ? min(1, Double(completed) / Double(total)) : 0 }
    }

    private let lock = NSLock()
    private var completed: Int64 = 0
    private var total: Int64 = 0
    private var currentName = ""
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    var snapshot: Snapshot { lock.withLock { Snapshot(completed: completed, total: total, currentName: currentName) } }

    func cancel() { lock.withLock { cancelled = true } }
    func addTotal(_ amount: Int64) { lock.withLock { total += amount } }
    func advance(_ amount: Int64) { lock.withLock { completed += amount } }
    func setCurrent(_ name: String) { lock.withLock { currentName = name } }

    func checkCancelled() throws {
        if isCancelled { throw CancellationError() }
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

    static func copy(_ urls: [URL], to directory: URL, policy: ConflictPolicy = .keepBoth,
                     log: ChangeLog? = nil, progress: OperationProgress? = nil) throws {
        progress?.addTotal(urls.reduce(0) { $0 + totalSize(of: $1) })
        for url in urls {
            try progress?.checkCancelled()
            guard let destination = try destination(for: url, in: directory, policy: policy, isCopy: true, log: log) else {
                progress?.advance(totalSize(of: url))
                continue
            }
            try copyItem(at: url, to: destination, progress: progress)
            log?.record(.created([destination]))
        }
    }

    static func move(_ urls: [URL], to directory: URL, policy: ConflictPolicy = .keepBoth,
                     log: ChangeLog? = nil, progress: OperationProgress? = nil) throws {
        let crossVolume = urls.filter { !isSameVolume($0, directory) }
        progress?.addTotal(crossVolume.reduce(0) { $0 + totalSize(of: $1) } + Int64(urls.count - crossVolume.count))
        for url in urls {
            try progress?.checkCancelled()
            guard let destination = try destination(for: url, in: directory, policy: policy, isCopy: false, log: log) else {
                progress?.advance(crossVolume.contains(url) ? totalSize(of: url) : 1)
                continue
            }
            if crossVolume.contains(url) {
                try copyItem(at: url, to: destination, progress: progress)
                try FileManager.default.removeItem(at: url)
            } else {
                progress?.setCurrent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: destination)
                progress?.advance(1)
            }
            log?.record(.moved([FileMove(from: url, to: destination)]))
        }
    }

    static func duplicate(_ urls: [URL], log: ChangeLog? = nil, progress: OperationProgress? = nil) throws {
        progress?.addTotal(urls.reduce(0) { $0 + totalSize(of: $1) })
        for url in urls {
            try progress?.checkCancelled()
            let destination = uniqueURL(for: copyName(for: url), in: url.deletingLastPathComponent())
            try copyItem(at: url, to: destination, progress: progress)
            log?.record(.created([destination]))
        }
    }

    static func trash(_ urls: [URL], log: ChangeLog? = nil, progress: OperationProgress? = nil) throws {
        progress?.addTotal(Int64(urls.count))
        for url in urls {
            try progress?.checkCancelled()
            progress?.setCurrent(url.lastPathComponent)
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            if let trashed = resulting as URL? { log?.record(.trashed([FileMove(from: url, to: trashed)])) }
            progress?.advance(1)
        }
    }

    static func deletePermanently(_ urls: [URL], progress: OperationProgress? = nil) throws {
        progress?.addTotal(Int64(urls.count))
        for url in urls {
            try progress?.checkCancelled()
            progress?.setCurrent(url.lastPathComponent)
            try FileManager.default.removeItem(at: url)
            progress?.advance(1)
        }
    }

    static func totalSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true, values.isSymbolicLink != true else { return Int64(values.fileSize ?? 0) }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let child = enumerator?.nextObject() as? URL {
            total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    private static func isSameVolume(_ a: URL, _ b: URL) -> Bool {
        guard let va = try? a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject,
              let vb = try? b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject else { return true }
        return va.isEqual(vb)
    }

    private final class CopyContext {
        let progress: OperationProgress?
        var reportedForCurrentFile: Int64 = 0

        init(progress: OperationProgress?) { self.progress = progress }
    }

    // copyfile clones on APFS, reports byte progress and can be cancelled mid-file.
    private static func copyItem(at source: URL, to destination: URL, progress: OperationProgress?) throws {
        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }
        let context = CopyContext(progress: progress)
        let callback: copyfile_callback_t = { what, stage, state, source, _, rawContext in
            guard let rawContext else { return COPYFILE_CONTINUE }
            let context = Unmanaged<CopyContext>.fromOpaque(rawContext).takeUnretainedValue()
            guard let progress = context.progress else { return COPYFILE_CONTINUE }
            if progress.isCancelled { return COPYFILE_QUIT }
            switch (Int32(what), Int32(stage)) {
            case (COPYFILE_RECURSE_FILE, COPYFILE_START):
                context.reportedForCurrentFile = 0
                if let source { progress.setCurrent((String(cString: source) as NSString).lastPathComponent) }
            case (COPYFILE_COPY_DATA, COPYFILE_PROGRESS):
                var copied: off_t = 0
                copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                progress.advance(Int64(copied) - context.reportedForCurrentFile)
                context.reportedForCurrentFile = Int64(copied)
            case (COPYFILE_RECURSE_FILE, COPYFILE_FINISH):
                var info = stat()
                if let source, lstat(source, &info) == 0 {
                    progress.advance(max(0, Int64(info.st_size) - context.reportedForCurrentFile))
                }
                context.reportedForCurrentFile = 0
            default:
                break
            }
            return COPYFILE_CONTINUE
        }
        let unmanaged = Unmanaged.passRetained(context)
        defer { unmanaged.release() }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), unmanaged.toOpaque())
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_CLONE | COPYFILE_NOFOLLOW_SRC | COPYFILE_EXCL)
        guard copyfile(source.path, destination.path, state, flags) == 0 else {
            let code = errno
            if progress?.isCancelled == true || code == ECANCELED {
                try? FileManager.default.removeItem(at: destination)
                throw CancellationError()
            }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO, userInfo: [NSFilePathErrorKey: source.path])
        }
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
