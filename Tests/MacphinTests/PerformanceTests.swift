import Foundation
import Testing
@testable import Macphin

struct PerformanceTests {
    @Test @MainActor func largeFolderLoadsAndFiltersQuickly() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "macphin-large-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for index in 0..<20_000 {
            fm.createFile(atPath: root.appending(path: "file-\(index).txt").path, contents: nil)
        }

        let clock = ContinuousClock()
        let started = clock.now
        let pane = PaneState(url: root)
        while pane.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        let loadTime = clock.now - started
        #expect(pane.visibleItems.count == 20_000)
        #expect(loadTime < .seconds(5), "load took \(loadTime)")

        let filterStart = clock.now
        pane.filterText = "file-1999"
        #expect(pane.visibleItems.count == 11)
        #expect(clock.now - filterStart < .milliseconds(500))

        pane.filterText = ""
        pane.selectAll()
        let selectionStart = clock.now
        #expect(pane.selectedItems.count == 20_000)
        #expect(clock.now - selectionStart < .milliseconds(500))

        pane.typeAhead("file-777")
        #expect(pane.selectedItems.first?.name.hasPrefix("file-777") == true)
        print("20k load: \(loadTime)")
    }
}
