import Foundation

struct PaneSession: Codable {
    var path: String
    var viewMode: ViewMode

    var resolvedURL: URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: path)
    }
}

struct TabSession: Codable {
    var panes: [PaneSession]
    var activePane: Int
}

struct WindowSession: Codable {
    var tabs: [TabSession]
    var activeTab: Int
    var showTerminal: Bool
}

@MainActor
final class SessionStore {
    static let shared = SessionStore()

    private let defaultsKey = "session"
    private var pending: [WindowSession]
    private var windows: [WindowState] = []
    private var detachedTabs: [TabState] = []

    private init() {
        guard Settings.restoreSession, Snapshotter.outputDirectory == nil,
              let data = UserDefaults.standard.data(forKey: defaultsKey),
              let sessions = try? JSONDecoder().decode([WindowSession].self, from: data) else {
            pending = []
            return
        }
        pending = sessions
    }

    var hasPending: Bool { !pending.isEmpty }
    var firstWindow: WindowState? { windows.first }

    func detach(_ tab: TabState) { detachedTabs.append(tab) }

    func claimDetachedTab() -> TabState? {
        detachedTabs.isEmpty ? nil : detachedTabs.removeFirst()
    }

    func window(containing tabID: UUID) -> WindowState? {
        windows.first { window in window.tabs.contains { $0.id == tabID } }
    }

    func claim() -> WindowSession? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    func register(_ window: WindowState) {
        if !windows.contains(where: { $0 === window }) { windows.append(window) }
    }

    func unregister(_ window: WindowState) {
        // Closing the last window quits the app, so keep its layout.
        if windows.count == 1, windows[0] === window, Snapshotter.outputDirectory == nil { save([window.session]) }
        windows.removeAll { $0 === window }
    }

    func saveAll() {
        guard !windows.isEmpty, Snapshotter.outputDirectory == nil else { return }
        save(windows.map(\.session))
    }

    private func save(_ sessions: [WindowSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
