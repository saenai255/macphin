import AppKit
import SwiftTerm
import SwiftUI

struct TerminalPanel: NSViewRepresentable {
    let pane: PaneState

    func makeCoordinator() -> Coordinator { Coordinator(pane: pane) }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        terminal.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["TERM_PROGRAM"] = "Macphin"
        terminal.startProcess(
            executable: shell, args: ["-l"],
            environment: environment.map { "\($0.key)=\($0.value)" },
            execName: "-" + (shell as NSString).lastPathComponent,
            currentDirectory: pane.url.path)
        context.coordinator.terminal = terminal
        context.coordinator.lastDirectory = pane.url
        return terminal
    }

    func updateNSView(_ terminal: LocalProcessTerminalView, context: Context) {
        context.coordinator.pane = pane
        context.coordinator.sync(to: pane.url)
    }

    static func dismantleNSView(_ terminal: LocalProcessTerminalView, coordinator: Coordinator) {
        terminal.terminate()
    }

    @MainActor
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var pane: PaneState
        weak var terminal: LocalProcessTerminalView?
        var lastDirectory: URL?

        init(pane: PaneState) { self.pane = pane }

        func sync(to url: URL) {
            guard url != lastDirectory, let terminal else { return }
            lastDirectory = url
            let escaped = url.path.replacingOccurrences(of: "'", with: "'\\''")
            terminal.send(txt: " cd '\(escaped)'\r")
        }

        nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {}

        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            guard let directory, let url = URL(string: directory), url.isFileURL || directory.hasPrefix("/") else { return }
            let fileURL = url.isFileURL ? url : URL(fileURLWithPath: directory)
            Task { @MainActor in
                guard fileURL.standardizedFileURL != self.pane.url.standardizedFileURL else { return }
                self.lastDirectory = fileURL.standardizedFileURL
                self.pane.navigate(to: fileURL)
            }
        }
    }
}
