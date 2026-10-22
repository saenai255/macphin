import AppKit

@MainActor
struct Actions {
    let window: WindowState
    let pane: PaneState

    init(window: WindowState, pane: PaneState? = nil) {
        self.window = window
        self.pane = pane ?? window.activePane
    }

    private var selectedURLs: [URL] { pane.selectedItems.map(\.url) }

    func copy() { FileClipboard.write(selectedURLs, cut: false) }
    func cut() { FileClipboard.write(selectedURLs, cut: true) }

    func paste(into directory: URL? = nil) {
        let (urls, isMove) = FileClipboard.takePasteOperation()
        transfer(urls, to: directory ?? pane.url, move: isMove)
    }

    func transfer(_ urls: [URL], to directory: URL, move: Bool) {
        let sources = urls.filter { $0.standardizedFileURL != directory.standardizedFileURL }
        guard !sources.isEmpty else { return }
        let window = self.window
        let subject = sources.count == 1 ? "“\(sources[0].lastPathComponent)”" : "\(sources.count) items"
        let title = "\(move ? "Moving" : "Copying") \(subject) to “\(directory.lastPathComponent)”"
        let run: (ConflictPolicy) -> Void = { policy in
            window.perform(move ? "Move" : "Copy", title: title) { log, progress in
                if move {
                    try FileOperations.move(sources, to: directory, policy: policy, log: log, progress: progress)
                } else {
                    try FileOperations.copy(sources, to: directory, policy: policy, log: log, progress: progress)
                }
            }
        }
        let conflicts = FileOperations.conflicts(for: sources, in: directory)
        if conflicts.isEmpty {
            run(.keepBoth)
        } else {
            window.pendingConflict = ConflictRequest(conflicts: conflicts, destination: directory, isMove: move, resolve: run)
        }
    }

    func newFolder() {
        window.performNow("New Folder") { log in
            let url = try FileOperations.createFolder(in: pane.url, log: log)
            pane.selection = [url]
            pane.renamingURL = url
        }
    }

    func newFile() {
        window.performNow("New File") { log in
            let url = try FileOperations.createFile(in: pane.url, log: log)
            pane.selection = [url]
            pane.renamingURL = url
        }
    }

    func rename() {
        guard let item = pane.selectedItems.first else { return }
        pane.renamingURL = item.url
    }

    func commitRename(_ url: URL, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != url.lastPathComponent else { return }
        guard !name.contains("/"), name != ".", name != ".." else {
            window.errorMessage = "“\(name)” is not a valid file name."
            return
        }
        window.performNow("Rename") { log in
            pane.selection = [try FileOperations.rename(url, to: name, log: log)]
        }
    }

    func duplicate() {
        let urls = selectedURLs
        window.perform("Duplicate", title: "Duplicating \(urls.count) item\(urls.count == 1 ? "" : "s")") {
            try FileOperations.duplicate(urls, log: $0, progress: $1)
        }
    }

    func trash(_ explicitURLs: [URL]? = nil) {
        let urls = explicitURLs ?? selectedURLs
        guard !urls.isEmpty else { return }
        if pane.url.standardizedFileURL == PlacesStore.trashURL.standardizedFileURL {
            window.pendingDelete = urls
            return
        }
        window.perform("Move to Trash", title: "Moving \(urls.count) item\(urls.count == 1 ? "" : "s") to the Trash") {
            try FileOperations.trash(urls, log: $0, progress: $1)
        }
    }

    func deletePermanently() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        window.pendingDelete = urls
    }

    func compress() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        window.perform("Compress", title: "Compressing \(urls.count) item\(urls.count == 1 ? "" : "s")") { log, _ in
            try FileOperations.compress(urls, log: log)
        }
    }

    func undo() { FileUndoStack.shared.undo { window.errorMessage = $0 } }
    func redo() { FileUndoStack.shared.redo { window.errorMessage = $0 } }

    func copyPath() {
        FileClipboard.copyPaths(selectedURLs.isEmpty ? [pane.url] : selectedURLs)
    }

    func revealInFinder() {
        let urls = selectedURLs
        if urls.isEmpty {
            NSWorkspace.shared.open(pane.url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    func openInTerminalApp(_ url: URL? = nil) {
        let target = url ?? pane.selectedItems.first(where: \.opensAsFolder)?.url ?? pane.url
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([target], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    func openInNewTab() {
        let folders = pane.selectedItems.filter(\.opensAsFolder)
        if folders.isEmpty { window.newTab(url: pane.url) }
        folders.forEach { window.newTab(url: $0.url) }
    }

    func openInSplit() {
        guard let folder = pane.selectedItems.first(where: \.opensAsFolder) else { return }
        window.activeTab.openInSplit(folder.url)
    }

    func addToPlaces() {
        let folders = pane.selectedItems.filter(\.opensAsFolder).map(\.url)
        (folders.isEmpty ? [pane.url] : folders).forEach { PlacesStore.shared.add($0) }
    }

    func copyToOtherPane() {
        guard let other = window.activeTab.otherPane else { return }
        transfer(selectedURLs, to: other.url, move: false)
    }

    func moveToOtherPane() {
        guard let other = window.activeTab.otherPane else { return }
        transfer(selectedURLs, to: other.url, move: true)
    }

    func emptyTrash() {
        let trash = PlacesStore.trashURL
        let contents = (try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
        guard !contents.isEmpty else { return }
        window.pendingDelete = contents
    }

    func drop(_ urls: [URL], into directory: URL, copy forceCopy: Bool = false) -> Bool {
        guard directory.isFileURL else { return false }
        let sources = urls.filter { $0.isFileURL && $0.standardizedFileURL != directory.standardizedFileURL }
        guard !sources.isEmpty else { return false }
        let copy = forceCopy || NSEvent.modifierFlags.contains(.option) || !sameVolume(sources[0], directory)
        transfer(sources, to: directory, move: !copy)
        return true
    }

    private func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key: URLResourceKey = .volumeIdentifierKey
        guard let va = try? a.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject,
              let vb = try? b.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject else { return true }
        return va.isEqual(vb)
    }
}
