import Foundation
import Testing
@testable import Macphin

struct GitStatusTests {
    private let root = URL(fileURLWithPath: "/tmp/macphin-repo", isDirectory: true)

    private func porcelain(_ fields: [String]) -> Data {
        Data((fields.joined(separator: "\0") + "\0").utf8)
    }

    private func url(_ relative: String) -> URL {
        URL(fileURLWithPath: relative, relativeTo: root).standardizedFileURL
    }

    @Test func parsesPorcelainEntries() {
        let snapshot = GitStatusProvider.parse(porcelain([
            " M Sources/a.swift",
            "?? Notes.txt",
            "?? build/",
            "!! .DS_Store",
            "R  Renamed.swift",
            "Original.swift",
            "UU Conflict.swift",
            "A  Added.swift",
            " D Removed.swift",
            "T  TypeChanged.swift",
        ]), root: root)

        #expect(snapshot.status(for: url("Sources/a.swift")) == .modified)
        #expect(snapshot.status(for: url("Notes.txt")) == .untracked)
        #expect(snapshot.status(for: url("build")) == .untracked)
        #expect(snapshot.status(for: url("build/output.o")) == .untracked)
        #expect(snapshot.status(for: url(".DS_Store")) == .ignored)
        #expect(snapshot.status(for: url("Renamed.swift")) == .renamed)
        #expect(snapshot.status(for: url("Original.swift")) == nil)
        #expect(snapshot.status(for: url("Conflict.swift")) == .conflicted)
        #expect(snapshot.status(for: url("Added.swift")) == .added)
        #expect(snapshot.status(for: url("Removed.swift")) == .deleted)
        #expect(snapshot.status(for: url("TypeChanged.swift")) == .modified)
        #expect(snapshot.status(for: url("Clean.txt")) == nil)
    }

    @Test func aggregatesDescendantStatuses() {
        let snapshot = GitStatusProvider.parse(porcelain([
            " M Folder/changed.txt",
            "?? Folder/new.txt",
            "!! Folder/cache.db",
        ]), root: root)

        #expect(snapshot.status(for: url("Folder")) == .modified)
        #expect(snapshot.status(for: root) == .modified)
    }

    @Test func ignoredEntriesDoNotMarkParents() {
        let snapshot = GitStatusProvider.parse(porcelain([
            "!! Logs/cache.db",
            "!! build/",
        ]), root: root)

        #expect(snapshot.status(for: url("Logs/cache.db")) == .ignored)
        #expect(snapshot.status(for: url("Logs")) == nil)
        #expect(snapshot.status(for: url("build")) == .ignored)
        #expect(snapshot.status(for: url("build/artifact.bin")) == .ignored)
        #expect(snapshot.status(for: root) == nil)
    }

    @Test func snapshotReadsRepository() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else { return }

        let fm = FileManager.default
        let repository = fm.temporaryDirectory.appending(path: "macphin-git-\(UUID().uuidString)")
        try fm.createDirectory(at: repository, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: repository) }

        guard git(["init"], in: repository) == 0 else { return }
        let tracked = repository.appending(path: "tracked.txt")
        let unchanged = repository.appending(path: "unchanged.txt")
        try "one".write(to: tracked, atomically: true, encoding: .utf8)
        try "two".write(to: unchanged, atomically: true, encoding: .utf8)
        guard git(["add", "tracked.txt", "unchanged.txt"], in: repository) == 0,
              git(["-c", "user.name=Macphin Tests", "-c", "user.email=tests@macphin.local",
                   "-c", "commit.gpgsign=false", "commit", "-m", "Initial"], in: repository) == 0 else { return }

        try "changed".write(to: tracked, atomically: true, encoding: .utf8)
        let untracked = repository.appending(path: "untracked.txt")
        try "new".write(to: untracked, atomically: true, encoding: .utf8)
        try "*.log\n".write(to: repository.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        let ignored = repository.appending(path: "ignored.log")
        try "ignored".write(to: ignored, atomically: true, encoding: .utf8)

        let snapshot = try #require(GitStatusProvider.snapshot(for: repository))
        #expect(snapshot.root.standardizedFileURL == repository.standardizedFileURL)
        #expect(snapshot.status(for: tracked) == .modified)
        #expect(snapshot.status(for: unchanged) == nil)
        #expect(snapshot.status(for: untracked) == .untracked)
        #expect(snapshot.status(for: ignored) == .ignored)
        #expect(snapshot.status(for: repository) == .modified)
    }

    private func git(_ arguments: [String], in directory: URL) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
