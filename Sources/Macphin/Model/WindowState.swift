import AppKit
import Observation

@MainActor
@Observable
final class TabState: Identifiable {
    let id = UUID()
    var panes: [PaneState]
    var activePaneIndex = 0

    init(url: URL) { panes = [PaneState(url: url)] }

    init(session: TabSession) {
        let panes = session.panes.prefix(2).map { PaneState(url: $0.resolvedURL, viewMode: $0.viewMode) }
        self.panes = panes.isEmpty ? [PaneState(url: FileManager.default.homeDirectoryForCurrentUser)] : panes
        activePaneIndex = min(max(session.activePane, 0), self.panes.count - 1)
    }

    var session: TabSession {
        TabSession(panes: panes.map { PaneSession(path: $0.url.path, viewMode: $0.viewMode) }, activePane: activePaneIndex)
    }

    var activePane: PaneState { panes[min(activePaneIndex, panes.count - 1)] }
    var isSplit: Bool { panes.count > 1 }
    var title: String { activePane.title }

    func toggleSplit() {
        if isSplit {
            panes.remove(at: activePaneIndex)
            activePaneIndex = 0
        } else {
            panes.append(PaneState(url: activePane.url))
            activePaneIndex = 1
        }
    }

    func openInSplit(_ url: URL) {
        if isSplit {
            panes[activePaneIndex == 0 ? 1 : 0].navigate(to: url)
        } else {
            panes.append(PaneState(url: url))
        }
    }

    var otherPane: PaneState? { isSplit ? panes[activePaneIndex == 0 ? 1 : 0] : nil }
}

struct ConflictRequest: Identifiable {
    let id = UUID()
    let conflicts: [URL]
    let destination: URL
    let isMove: Bool
    let resolve: (ConflictPolicy) -> Void
}

@MainActor
@Observable
final class WindowState {
    var tabs: [TabState]
    var activeTabID: UUID
    var showPlaces = Settings.showPlaces { didSet { Settings.showPlaces = showPlaces } }
    var showInfo = Settings.showInfo { didSet { Settings.showInfo = showInfo } }
    var showTerminal = false
    var pendingDelete: [URL] = []
    var pendingConflict: ConflictRequest?
    var showConnectSheet = false
    var connectingTo: String?
    var errorMessage: String?

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let tab = TabState(url: url)
        tabs = [tab]
        activeTabID = tab.id
    }

    var activeTab: TabState { tabs.first { $0.id == activeTabID } ?? tabs[0] }
    var activePane: PaneState { activeTab.activePane }

    var session: WindowSession {
        WindowSession(
            tabs: tabs.map(\.session),
            activeTab: tabs.firstIndex { $0.id == activeTabID } ?? 0,
            showTerminal: showTerminal)
    }

    func restore(_ session: WindowSession) {
        let restored = session.tabs.map(TabState.init(session:))
        guard !restored.isEmpty else { return }
        tabs = restored
        activeTabID = restored[min(max(session.activeTab, 0), restored.count - 1)].id
        showTerminal = session.showTerminal
    }

    func newTab(url: URL? = nil) {
        let tab = TabState(url: url ?? activePane.url)
        if let index = tabs.firstIndex(where: { $0.id == activeTabID }) {
            tabs.insert(tab, at: index + 1)
        } else {
            tabs.append(tab)
        }
        activeTabID = tab.id
    }

    func closeTab(_ id: UUID? = nil) {
        let target = id ?? activeTabID
        guard tabs.count > 1 else {
            NSApp.keyWindow?.performClose(nil)
            return
        }
        guard let index = tabs.firstIndex(where: { $0.id == target }) else { return }
        tabs.remove(at: index)
        if target == activeTabID { activeTabID = tabs[min(index, tabs.count - 1)].id }
    }

    func cycleTab(by offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        activeTabID = tabs[(index + offset + tabs.count) % tabs.count].id
    }

    func run(_ operation: () throws -> Void) {
        do { try operation() } catch { errorMessage = error.localizedDescription }
    }

    func runAsync(_ operation: @escaping @Sendable () throws -> Void) {
        Task.detached {
            do { try operation() } catch {
                let message = error.localizedDescription
                await MainActor.run { self.errorMessage = message }
            }
        }
    }

    // Partial work is still registered for undo when the operation fails.
    func perform(_ name: String, _ operation: @escaping @Sendable (ChangeLog) throws -> Void) {
        Task.detached {
            let log = ChangeLog()
            var message: String?
            do { try operation(log) } catch { message = error.localizedDescription }
            let change = log.combined, failure = message
            await MainActor.run {
                FileUndoStack.shared.register(name, change)
                if let failure { self.errorMessage = failure }
            }
        }
    }

    func performNow(_ name: String, _ operation: (ChangeLog) throws -> Void) {
        let log = ChangeLog()
        do { try operation(log) } catch { errorMessage = error.localizedDescription }
        FileUndoStack.shared.register(name, log.combined)
    }

    func connect(to url: URL, user: String? = nil, password: String? = nil, in pane: PaneState? = nil) {
        let pane = pane ?? activePane
        connectingTo = url.host ?? url.absoluteString
        Task {
            defer { connectingTo = nil }
            do {
                let local = try await RemoteMounter.mount(url, user: user, password: password)
                PlacesStore.shared.refreshDevices()
                pane.navigate(to: local)
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum Settings {
    private static let defaults = UserDefaults.standard

    static var viewMode: ViewMode {
        get { ViewMode(rawValue: defaults.string(forKey: "viewMode") ?? "") ?? .icons }
        set { defaults.set(newValue.rawValue, forKey: "viewMode") }
    }
    static var showHidden: Bool {
        get { defaults.bool(forKey: "showHidden") }
        set { defaults.set(newValue, forKey: "showHidden") }
    }
    static var zoom: Double {
        get { defaults.object(forKey: "zoom") as? Double ?? 64 }
        set { defaults.set(newValue, forKey: "zoom") }
    }
    static var showPlaces: Bool {
        get { defaults.object(forKey: "showPlaces") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showPlaces") }
    }
    static var showInfo: Bool {
        get { defaults.bool(forKey: "showInfo") }
        set { defaults.set(newValue, forKey: "showInfo") }
    }
    static var restoreSession: Bool {
        get { defaults.object(forKey: "restoreSession") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "restoreSession") }
    }
}
