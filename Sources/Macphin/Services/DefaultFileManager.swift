import AppKit
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
enum DefaultFileManager {
    private static let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    private static let fileViewerKey = "NSFileViewer" as CFString

    static var isFolderHandler: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: .folder)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static var isFileViewer: Bool {
        CFPreferencesCopyAppValue(fileViewerKey, kCFPreferencesAnyApplication) as? String == Bundle.main.bundleIdentifier
    }

    static var isEnabled: Bool { isFolderHandler && isFileViewer }

    static func setEnabled(_ enabled: Bool) async throws {
        let app = enabled ? Bundle.main.bundleURL : finderURL
        try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: .folder)
        let viewer: CFString? = enabled ? Bundle.main.bundleIdentifier as CFString? : nil
        CFPreferencesSetValue(fileViewerKey, viewer, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    static var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    static func setOpensAtLogin(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static var isInstalledInApplications: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications"
    }
}

@MainActor
enum ExternalOpenRouter {
    // Folders open in a new tab; files are revealed (parent folder, file selected).
    static func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let window = SessionStore.shared.activeWindow else {
            SessionStore.shared.queueExternal(urls)
            return
        }
        for url in urls {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]))
                .map { $0.isDirectory == true && $0.isPackage != true } ?? false
            if isFolder {
                window.newTab(url: url)
            } else {
                window.newTab(url: url.deletingLastPathComponent())
                window.activePane.selection = [url]
                window.activePane.scrollTarget = url
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    static func reveal(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let parent = first.deletingLastPathComponent()
        guard let window = SessionStore.shared.activeWindow else {
            SessionStore.shared.queueExternal(urls)
            return
        }
        window.newTab(url: parent)
        window.activePane.selection = Set(urls.filter { $0.deletingLastPathComponent() == parent })
        window.activePane.scrollTarget = first
        NSApp.activate(ignoringOtherApps: true)
    }
}
