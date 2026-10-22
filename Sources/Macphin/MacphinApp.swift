import AppKit
import SwiftUI

@main
struct MacphinApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindow()
        }
        .defaultSize(width: 1100, height: 680)
        .commands { MacphinCommands() }

        SwiftUI.Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false
        Snapshotter.runIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { SessionStore.shared.saveAll() }
    }
}

private extension KeyEquivalent {
    static func function(_ number: Int) -> KeyEquivalent {
        KeyEquivalent(Character(UnicodeScalar(NSF1FunctionKey + number - 1)!))
    }
}

struct MacphinCommands: Commands {
    @FocusedValue(\.windowState) private var window

    private var pane: PaneState? { window?.activePane }
    private var actions: Actions? { window.map { Actions(window: $0) } }

    private var isEditingText: Bool { NSApp.keyWindow?.firstResponder is NSText }

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(FileUndoStack.shared.undoTitle) { textOr(Selector(("undo:"))) { actions?.undo() } }
                .keyboardShortcut("z")
            Button(FileUndoStack.shared.redoTitle) { textOr(Selector(("redo:"))) { actions?.redo() } }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(after: .newItem) {
            Button("New Tab") { window?.newTab() }.keyboardShortcut("t")
            Button("Close Tab") { window?.closeTab() }.keyboardShortcut("w")
            Divider()
            Button("New Folder") { actions?.newFolder() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Text File") { actions?.newFile() }.keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("Open") { textOr(#selector(NSResponder.moveToEndOfDocument(_:))) { pane?.openSelection() } }
                .keyboardShortcut(.downArrow)
            Button("Open in New Tab") { actions?.openInNewTab() }.keyboardShortcut(.return, modifiers: [.command, .shift])
            Button("Open Terminal Here") { actions?.openInTerminalApp() }.keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            Button("Rename…") { actions?.rename() }.keyboardShortcut(.function(2), modifiers: [])
            Button("Duplicate") { actions?.duplicate() }.keyboardShortcut("d")
            Button("Compress") { actions?.compress() }
            Button("Move to Trash") { if !isEditingText { actions?.trash() } }.keyboardShortcut(.delete)
            Button("Delete Permanently…") { actions?.deletePermanently() }.keyboardShortcut(.delete, modifiers: [.command, .option])
            Button("Add to Places") { actions?.addToPlaces() }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Properties") { window?.showInfo = true }.keyboardShortcut("i")
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { textOr(#selector(NSText.cut(_:))) { actions?.cut() } }.keyboardShortcut("x")
            Button("Copy") { textOr(#selector(NSText.copy(_:))) { actions?.copy() } }.keyboardShortcut("c")
            Button("Paste") { textOr(#selector(NSText.paste(_:))) { actions?.paste() } }.keyboardShortcut("v")
            Button("Copy Location") { actions?.copyPath() }.keyboardShortcut("c", modifiers: [.command, .option])
            Divider()
            Button("Select All") { textOr(#selector(NSText.selectAll(_:))) { pane?.selectAll() } }.keyboardShortcut("a")
            Button("Invert Selection") { invertSelection() }.keyboardShortcut("a", modifiers: [.command, .shift])
            Divider()
            Button("Filter…") { pane?.isFilterBarVisible.toggle() }.keyboardShortcut("f", modifiers: [.command, .option])
            Button("Edit Location") { pane?.isEditingLocation = true }.keyboardShortcut("l")
        }

        CommandGroup(before: .toolbar) {
            Picker("View Mode", selection: Binding(get: { pane?.viewMode ?? .icons }, set: { pane?.viewMode = $0 })) {
                Text("Icons").tag(ViewMode.icons).keyboardShortcut("1")
                Text("Compact").tag(ViewMode.compact).keyboardShortcut("2")
                Text("Details").tag(ViewMode.details).keyboardShortcut("3")
            }
            .pickerStyle(.inline)
            Divider()
            Button("Zoom In") { pane.map { $0.zoom = min(256, $0.zoom * 1.25) } }.keyboardShortcut("+")
            Button("Zoom Out") { pane.map { $0.zoom = max(16, $0.zoom / 1.25) } }.keyboardShortcut("-")
            Button("Reset Zoom") { pane?.zoom = 64 }.keyboardShortcut("0")
            Divider()
            Button(pane?.showHidden == true ? "Hide Hidden Files" : "Show Hidden Files") { pane?.showHidden.toggle() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Button("Reload") { pane?.reload() }.keyboardShortcut("r")
            Divider()
            Button(window?.activeTab.isSplit == true ? "Close Split View" : "Split View") { window?.activeTab.toggleSplit() }
                .keyboardShortcut(.function(3), modifiers: [])
            Button("Switch Active View") { switchPane() }.keyboardShortcut(.tab, modifiers: [.control, .shift])
            Divider()
            Button(window?.showPlaces == true ? "Hide Places" : "Show Places") { window?.showPlaces.toggle() }
                .keyboardShortcut(.function(9), modifiers: [])
            Button(window?.showTerminal == true ? "Hide Terminal" : "Show Terminal") { window?.showTerminal.toggle() }
                .keyboardShortcut(.function(4), modifiers: [])
            Button(window?.showInfo == true ? "Hide Information" : "Show Information") { window?.showInfo.toggle() }
                .keyboardShortcut(.function(11), modifiers: [])
            Divider()
        }

        CommandMenu("Go") {
            Button("Back") { pane?.goBack() }.keyboardShortcut("[").disabled(pane?.canGoBack != true)
            Button("Forward") { pane?.goForward() }.keyboardShortcut("]").disabled(pane?.canGoForward != true)
            Button("Up") { textOr(#selector(NSResponder.moveToBeginningOfDocument(_:))) { pane?.goUp() } }
                .keyboardShortcut(.upArrow)
            Divider()
            Button("Home") { go(FileManager.default.homeDirectoryForCurrentUser) }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Desktop") { go(FileManager.SearchPathDirectory.desktopDirectory) }.keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Documents") { go(FileManager.SearchPathDirectory.documentDirectory) }.keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Downloads") { go(FileManager.SearchPathDirectory.downloadsDirectory) }.keyboardShortcut("l", modifiers: [.command, .option])
            Button("Applications") { go(URL(fileURLWithPath: "/Applications")) }.keyboardShortcut("a", modifiers: [.command, .option])
            Button("Trash") { go(PlacesStore.trashURL) }
            Divider()
            Button("Connect to Server…") { window?.showConnectSheet = true }.keyboardShortcut("k")
            Divider()
            Button("Next Tab") { window?.cycleTab(by: 1) }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { window?.cycleTab(by: -1) }.keyboardShortcut("[", modifiers: [.command, .shift])
        }
    }

    private func textOr(_ selector: Selector, _ fileAction: () -> Void) {
        if isEditingText { NSApp.sendAction(selector, to: nil, from: nil) } else { fileAction() }
    }

    private func invertSelection() {
        guard let pane else { return }
        pane.selection = Set(pane.visibleItems.map(\.url)).subtracting(pane.selection)
    }

    private func switchPane() {
        guard let tab = window?.activeTab, tab.isSplit else { return }
        tab.activePaneIndex = tab.activePaneIndex == 0 ? 1 : 0
    }

    private func go(_ url: URL) { pane?.navigate(to: url) }

    private func go(_ directory: FileManager.SearchPathDirectory) {
        if let url = FileManager.default.urls(for: directory, in: .userDomainMask).first { go(url) }
    }
}
