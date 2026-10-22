import AppKit
import SwiftUI

struct FileContextMenu: View {
    let window: WindowState
    let pane: PaneState

    private var actions: Actions { Actions(window: window, pane: pane) }
    private var selected: [FileItem] { pane.selectedItems }

    var body: some View {
        if selected.isEmpty {
            backgroundItems
        } else {
            itemMenu
        }
    }

    @ViewBuilder private var backgroundItems: some View {
        Menu("Create New") {
            Button("Folder…") { actions.newFolder() }
            Button("Text File…") { actions.newFile() }
        }
        Button("Paste") { actions.paste() }.disabled(!FileClipboard.hasContent)
        Divider()
        Button("Add to Places") { actions.addToPlaces() }
        Button("Copy Location") { actions.copyPath() }
        Button("Open Terminal Here") { actions.openInTerminalApp(pane.url) }
        Button("Show in Finder") { actions.revealInFinder() }
        Divider()
        Toggle("Show Hidden Files", isOn: Binding(get: { pane.showHidden }, set: { pane.showHidden = $0 }))
        Picker("Sort By", selection: Binding(get: { pane.sortKey }, set: { pane.sortKey = $0 })) {
            ForEach(SortKey.allCases) { Text($0.title).tag($0) }
        }
        Picker("View Mode", selection: Binding(get: { pane.viewMode }, set: { pane.viewMode = $0 })) {
            ForEach(ViewMode.allCases) { Text($0.title).tag($0) }
        }
        if pane.url.standardizedFileURL == PlacesStore.trashURL.standardizedFileURL {
            Divider()
            Button("Empty Trash") { actions.emptyTrash() }
        }
    }

    @ViewBuilder private var itemMenu: some View {
        Button("Open") { pane.openSelection() }
        if selected.contains(where: \.opensAsFolder) {
            Button("Open in New Tab") { actions.openInNewTab() }
            Button("Open in Split View") { actions.openInSplit() }
            Button("Open Terminal Here") { actions.openInTerminalApp() }
            Button("Add to Places") { actions.addToPlaces() }
        }
        if selected.count == 1, let item = selected.first, !item.opensAsFolder {
            OpenWithMenu(url: item.url)
        }
        Divider()
        Button("Cut") { actions.cut() }
        Button("Copy") { actions.copy() }
        Button("Paste") { actions.paste(into: selected.first(where: \.opensAsFolder)?.url) }
            .disabled(!FileClipboard.hasContent)
        if window.activeTab.isSplit {
            Button("Copy to Other View") { actions.copyToOtherPane() }
            Button("Move to Other View") { actions.moveToOtherPane() }
        }
        Divider()
        Button("Rename…") { actions.rename() }.disabled(selected.count != 1)
        Button("Duplicate") { actions.duplicate() }
        Button("Compress") { actions.compress() }
        Button("Copy Location") { actions.copyPath() }
        Button("Show in Finder") { actions.revealInFinder() }
        Button("Quick Look") { pane.quickLookURL = selected.first?.url }
        Divider()
        Button("Move to Trash") { actions.trash() }
        Button("Delete Permanently…") { actions.deletePermanently() }
        Divider()
        Button("Properties") { window.showInfo = true }
    }
}

private struct OpenWithMenu: View {
    let url: URL

    var body: some View {
        Menu("Open With") {
            let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
            let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: url)
            ForEach(apps, id: \.self) { app in
                Button {
                    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                } label: {
                    Label {
                        Text(FileManager.default.displayName(atPath: app.path) + (app == defaultApp ? " (default)" : ""))
                    } icon: {
                        Image(nsImage: IconCache.icon(for: app))
                    }
                }
            }
            Divider()
            Button("Other Application…") { chooseApplication() }
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK, let app = panel.url else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
