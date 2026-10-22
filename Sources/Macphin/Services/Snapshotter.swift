import AppKit

// Debug aid: MACPHIN_SNAPSHOT_DIR=<dir> renders scripted UI states to PNGs, no screen-recording permission needed.
@MainActor
enum Snapshotter {
    static var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["MACPHIN_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static var startDirectory: URL? {
        ProcessInfo.processInfo.environment["MACPHIN_SNAPSHOT_START"].map { URL(fileURLWithPath: $0) }
    }

    static func runIfRequested() {
        guard let directory = outputDirectory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard let window = SessionStore.shared.firstWindow else { return quit() }
            NSApp.windows.first { $0.isVisible && $0.canBecomeMain }?.setFrame(NSRect(x: 80, y: 80, width: 1200, height: 760), display: true)
            if let start = startDirectory { window.activePane.navigate(to: start) }
            let steps: [(String, () -> Void)] = [
                ("01-icons", { window.activePane.viewMode = .icons }),
                ("02-icons-selected", {
                    let pane = window.activePane
                    pane.selection = Set(pane.visibleItems.prefix(3).map(\.url))
                }),
                ("03-compact", { window.activePane.viewMode = .compact }),
                ("04-details", { window.activePane.viewMode = .details }),
                ("05-split-info", {
                    window.activeTab.toggleSplit()
                    window.activePane.viewMode = .icons
                    window.showInfo = true
                }),
                ("06-terminal-tabs", {
                    window.showInfo = false
                    window.showTerminal = true
                    window.newTab()
                    window.activePane.isFilterBarVisible = true
                }),
                ("07-rename", {
                    window.showTerminal = false
                    let pane = window.activePane
                    pane.viewMode = .icons
                    if let first = pane.visibleItems.first(where: { !$0.opensAsFolder }) { pane.renamingURL = first.url }
                }),
            ]
            for (name, action) in steps {
                action()
                try? await Task.sleep(for: .seconds(1.5))
                capture(name, into: directory)
            }
            quit()
        }
    }

    private static func describeTables(in view: NSView, depth: Int = 0) -> [String] {
        var lines: [String] = []
        if let table = view as? NSTableView {
            lines.append("\(type(of: table)) rows=\(table.numberOfRows) frame=\(table.frame.integral)")
        }
        for subview in view.subviews { lines += describeTables(in: subview, depth: depth + 1) }
        return lines
    }

    private static func capture(_ name: String, into directory: URL) {
        if let root = NSApp.windows.first(where: \.isVisible)?.contentView {
            FileHandle.standardError.write(Data("[\(name)] \(describeTables(in: root).joined(separator: " | "))\n".utf8))
        }
        for (index, window) in NSApp.windows.enumerated() where window.isVisible && window.frame.width > 100 {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let suffix = index == 0 ? "" : "-w\(index)"
            try? bitmap.representation(using: .png, properties: [:])?
                .write(to: directory.appending(path: "\(name)\(suffix).png"))
        }
    }

    private static func quit() { NSApp.terminate(nil) }
}
