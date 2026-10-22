import Foundation
import Testing
@testable import Macphin

struct FileOperationsTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "macphin-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @Test func uniqueNamesAvoidCollisions() throws {
        let first = try FileOperations.createFolder(in: root)
        let second = try FileOperations.createFolder(in: root)
        #expect(first.lastPathComponent == "New Folder")
        #expect(second.lastPathComponent == "New Folder 2")

        try FileOperations.createFile(in: root, name: "a.txt")
        #expect(FileOperations.uniqueURL(for: "a.txt", in: root).lastPathComponent == "a 2.txt")
    }

    @Test func copyIntoSameFolderMakesCopy() throws {
        let file = try FileOperations.createFile(in: root, name: "notes.md")
        try FileOperations.copy([file], to: root)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "notes copy.md").path))
    }

    @Test func moveIntoItselfIsRejected() throws {
        let folder = try FileOperations.createFolder(in: root, name: "outer")
        let inner = try FileOperations.createFolder(in: folder, name: "inner")
        #expect(throws: CocoaError.self) { try FileOperations.move([folder], to: inner) }
    }

    @Test func renameAndMove() throws {
        let file = try FileOperations.createFile(in: root, name: "x.txt")
        let renamed = try FileOperations.rename(file, to: "y.txt")
        let target = try FileOperations.createFolder(in: root, name: "target")
        try FileOperations.move([renamed], to: target)
        #expect(FileManager.default.fileExists(atPath: target.appending(path: "y.txt").path))
        #expect(!FileManager.default.fileExists(atPath: renamed.path))
    }

    @Test @MainActor func paneSortsFoldersFirstAndFilters() async throws {
        try FileOperations.createFile(in: root, name: "b.txt")
        try FileOperations.createFile(in: root, name: "A.txt")
        try FileOperations.createFolder(in: root, name: "zeta")
        let pane = PaneState(url: root)
        for _ in 0..<50 where pane.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        #expect(pane.items.map(\.name) == ["zeta", "A.txt", "b.txt"])
        pane.filterText = "b"
        #expect(pane.visibleItems.map(\.name) == ["b.txt"])
    }
}
