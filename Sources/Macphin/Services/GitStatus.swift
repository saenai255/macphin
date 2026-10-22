import Foundation

enum GitFileStatus: Int, Sendable, Comparable {
    case ignored
    case untracked
    case deleted
    case renamed
    case added
    case modified
    case conflicted

    var label: String {
        switch self {
        case .ignored: "Ignored"
        case .untracked: "Untracked"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .added: "Added"
        case .modified: "Modified"
        case .conflicted: "Conflicted"
        }
    }

    var symbol: String {
        switch self {
        case .ignored: "eye.slash.circle.fill"
        case .untracked: "plus.circle.fill"
        case .deleted: "minus.circle.fill"
        case .renamed: "arrow.right.circle.fill"
        case .added: "plus.circle.fill"
        case .modified: "pencil.circle.fill"
        case .conflicted: "exclamationmark.triangle.fill"
        }
    }

    static func < (lhs: GitFileStatus, rhs: GitFileStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct GitStatusSnapshot: Sendable {
    let root: URL
    private let entries: [String: GitFileStatus]
    private let directories: [String: GitFileStatus]
    private let aggregated: [String: GitFileStatus]

    init(root: URL, entries: [String: GitFileStatus], directories: [String: GitFileStatus]) {
        let root = root.standardizedFileURL
        self.root = root
        self.entries = entries
        self.directories = directories

        var aggregated: [String: GitFileStatus] = [:]
        for (path, status) in entries where status != .ignored {
            for ancestor in Self.ancestors(of: path, in: root.path) {
                aggregated[ancestor] = max(aggregated[ancestor] ?? status, status)
            }
        }
        for (path, status) in directories where status != .ignored {
            for ancestor in Self.ancestors(of: path, in: root.path) {
                aggregated[ancestor] = max(aggregated[ancestor] ?? status, status)
            }
        }
        self.aggregated = aggregated
    }

    func status(for url: URL) -> GitFileStatus? {
        let path = url.standardizedFileURL.path
        if let status = entries[path] { return status }
        if let status = directories[path] { return status }
        var current = path
        while current != "/", !current.isEmpty {
            current = (current as NSString).deletingLastPathComponent
            if let status = directories[current] { return status }
        }
        return aggregated[path]
    }

    private static func ancestors(of path: String, in root: String) -> [String] {
        let prefix = root == "/" ? "/" : root + "/"
        guard path != root, path.hasPrefix(prefix) else { return [] }
        var result: [String] = []
        var current = path
        while current != root, current != "/", !current.isEmpty {
            current = (current as NSString).deletingLastPathComponent
            result.append(current)
        }
        return result
    }
}

enum GitStatusProvider {
    static func parse(_ output: Data, root: URL) -> GitStatusSnapshot {
        let root = root.standardizedFileURL
        var entries: [String: GitFileStatus] = [:]
        var directories: [String: GitFileStatus] = [:]
        let fields = String(decoding: output, as: UTF8.self)
            .split(separator: "\0", omittingEmptySubsequences: true)

        var index = 0
        while index < fields.count {
            let field = fields[index]
            index += 1
            guard field.count > 3 else { continue }

            let code = field.prefix(2)
            let path = field.dropFirst(3)
            if code.contains("R") || code.contains("C") {
                index += 1
            }
            guard let status = status(for: code) else { continue }

            let isDirectoryEntry = path.hasSuffix("/")
            let relative = isDirectoryEntry ? path.dropLast() : path
            let absolute = URL(fileURLWithPath: String(relative), relativeTo: root)
                .standardizedFileURL.path
            if isDirectoryEntry {
                directories[absolute] = status
            } else {
                entries[absolute] = status
            }
        }
        return GitStatusSnapshot(root: root, entries: entries, directories: directories)
    }

    static func snapshot(for directory: URL) -> GitStatusSnapshot? {
        let directory = directory.standardizedFileURL
        guard let topLevel = runGit(["--no-pager", "-C", directory.path, "rev-parse", "--show-toplevel"]) else { return nil }
        let path = String(decoding: topLevel, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }

        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let arguments = [
            "--no-pager", "-C", root.path, "status", "--porcelain=v1", "-z",
            "--ignored=matching", "--untracked-files=normal",
        ]
        guard let output = runGit(arguments) else { return nil }
        return parse(output, root: root)
    }

    private static func status(for code: Substring) -> GitFileStatus? {
        if code == "??" { return .untracked }
        if code == "!!" { return .ignored }
        if code.contains("U") || code == "AA" || code == "DD" { return .conflicted }

        let first = code.first
        let second = code.dropFirst().first
        if first == "R" || second == "R" { return .renamed }
        if first == "A" || second == "A" { return .added }
        if first == "D" || second == "D" { return .deleted }
        if first == "M" || first == "T" || second == "M" || second == "T" { return .modified }
        return nil
    }

    private static func runGit(_ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        let stdout = DataBox()
        let readers = DispatchGroup()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stdout.store(output.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            _ = errors.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }

        guard finished.wait(timeout: .now() + 3) == .success else {
            process.terminate()
            _ = finished.wait(timeout: .now() + 1)
            return nil
        }
        guard readers.wait(timeout: .now() + 1) == .success else { return nil }
        guard process.terminationStatus == 0 else { return nil }
        return stdout.data
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func store(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
