import Foundation
import Testing
@testable import Macphin

struct UndoAndConflictTests {
    let root: URL
    let fm = FileManager.default

    init() throws {
        root = fm.temporaryDirectory.appending(path: "macphin-undo-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func write(_ text: String, to name: String, in directory: URL? = nil) throws -> URL {
        let url = (directory ?? root).appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    @Test func undoAndRedoMove() throws {
        let file = try write("a", to: "a.txt")
        let target = try FileOperations.createFolder(in: root, name: "target")
        let log = ChangeLog()
        try FileOperations.move([file], to: target, log: log)
        let moved = target.appending(path: "a.txt")
        #expect(fm.fileExists(atPath: moved.path))

        let redo = try FileOperations.invert(try #require(log.combined))
        #expect(fm.fileExists(atPath: file.path))
        #expect(!fm.fileExists(atPath: moved.path))

        _ = try FileOperations.invert(redo)
        #expect(fm.fileExists(atPath: moved.path))
    }

    @Test func undoRenameRestoresName() throws {
        let file = try write("x", to: "old.txt")
        let log = ChangeLog()
        try FileOperations.rename(file, to: "new.txt", log: log)
        _ = try FileOperations.invert(try #require(log.combined))
        #expect(fm.fileExists(atPath: file.path))
    }

    @Test func caseOnlyRename() throws {
        let file = try write("x", to: "readme.md")
        let renamed = try FileOperations.rename(file, to: "README.md")
        let names = try fm.contentsOfDirectory(atPath: root.path)
        #expect(names == ["README.md"])
        #expect(renamed.lastPathComponent == "README.md")
    }

    @Test func undoTrashRestoresAndRedoTrashesAgain() throws {
        let file = try write("t", to: "trash-me-\(UUID().uuidString).txt")
        let log = ChangeLog()
        try FileOperations.trash([file], log: log)
        #expect(!fm.fileExists(atPath: file.path))

        let redo = try FileOperations.invert(try #require(log.combined))
        #expect(try read(file) == "t")

        let undoAgain = try FileOperations.invert(redo)
        #expect(!fm.fileExists(atPath: file.path))
        _ = try FileOperations.invert(undoAgain)
        #expect(fm.fileExists(atPath: file.path))
    }

    @Test func undoCopyRemovesCopies() throws {
        let source = try FileOperations.createFolder(in: root, name: "src")
        let file = try write("c", to: "c.txt", in: source)
        let log = ChangeLog()
        try FileOperations.copy([file], to: root, log: log)
        #expect(fm.fileExists(atPath: root.appending(path: "c.txt").path))
        _ = try FileOperations.invert(try #require(log.combined))
        #expect(!fm.fileExists(atPath: root.appending(path: "c.txt").path))
        #expect(fm.fileExists(atPath: file.path))
    }

    @Test func conflictPolicies() throws {
        let source = try FileOperations.createFolder(in: root, name: "src")
        let incoming = try write("new", to: "f.txt", in: source)
        let existing = try write("old", to: "f.txt")
        #expect(FileOperations.conflicts(for: [incoming], in: root) == [incoming])

        try FileOperations.copy([incoming], to: root, policy: .skip)
        #expect(try read(existing) == "old")

        try FileOperations.copy([incoming], to: root, policy: .keepBoth)
        #expect(try read(root.appending(path: "f 2.txt")) == "new")

        let log = ChangeLog()
        try FileOperations.copy([incoming], to: root, policy: .replace, log: log)
        #expect(try read(existing) == "new")

        _ = try FileOperations.invert(try #require(log.combined))
        #expect(try read(existing) == "old")
    }

    @Test func replaceRefusesToTrashAncestorOfSource() throws {
        let parent = try FileOperations.createFolder(in: root, name: "dup")
        let child = try FileOperations.createFolder(in: parent, name: "dup")
        #expect(throws: CocoaError.self) { try FileOperations.move([child], to: root, policy: .replace) }
        #expect(fm.fileExists(atPath: child.path))
    }

    @Test func sessionRoundTripFallsBackToHome() throws {
        let session = WindowSession(
            tabs: [TabSession(panes: [PaneSession(path: root.path, viewMode: .details),
                                      PaneSession(path: "/definitely/missing", viewMode: .icons)], activePane: 1)],
            activeTab: 0, showTerminal: true)
        let decoded = try JSONDecoder().decode(WindowSession.self, from: JSONEncoder().encode(session))
        #expect(decoded.tabs[0].panes[0].resolvedURL.path == root.path)
        #expect(decoded.tabs[0].panes[1].resolvedURL == fm.homeDirectoryForCurrentUser)
        #expect(decoded.tabs[0].panes[0].viewMode == .details)
    }

    @Test func remoteURLParsing() {
        #expect(RemoteMounter.parse("smb://nas.local/share") != nil)
        #expect(RemoteMounter.parse("sftp://me@host:2222/srv") != nil)
        #expect(RemoteMounter.parse("/Users/me") == nil)
        #expect(RemoteMounter.parse("file:///tmp") == nil)
        #expect(RemoteMounter.parse("smb://") == nil)
    }
}

struct ProgressTests {
    @Test func copyFolderReportsProgressAndCancels() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "macphin-progress-\(UUID().uuidString)")
        let source = root.appending(path: "src")
        try fm.createDirectory(at: source.appending(path: "nested"), withIntermediateDirectories: true)
        try Data(count: 300_000).write(to: source.appending(path: "a.bin"))
        try Data(count: 200_000).write(to: source.appending(path: "nested/b.bin"))
        let target = try FileOperations.createFolder(in: root, name: "target")

        let progress = OperationProgress()
        try FileOperations.copy([source], to: target, progress: progress)
        let snapshot = progress.snapshot
        #expect(snapshot.total == 500_000)
        #expect(snapshot.completed == snapshot.total)
        #expect(fm.fileExists(atPath: target.appending(path: "src/nested/b.bin").path))

        let cancelled = OperationProgress()
        cancelled.cancel()
        #expect(throws: CancellationError.self) { try FileOperations.copy([source], to: root, progress: cancelled) }
        #expect(!fm.fileExists(atPath: root.appending(path: "src copy").path))
    }
}
