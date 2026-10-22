import Foundation

struct QuickAction: Identifiable, Hashable {
    let url: URL
    var name: String
    var id: URL { url }
}

enum QuickActions {
    static func available() -> [QuickAction] {
        let directories = [
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Services"),
            URL(fileURLWithPath: "/Library/Services", isDirectory: true),
        ]
        var actions: [QuickAction] = []
        for directory in directories {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for url in urls where url.pathExtension == "workflow" {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDirectory else { continue }
                actions.append(QuickAction(
                    url: url.standardizedFileURL,
                    name: FileManager.default.displayName(atPath: url.path)))
            }
        }
        return actions.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func run(_ action: QuickAction, on files: [URL]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/automator")
            process.arguments = ["-i", files.map(\.path).joined(separator: "\n"), action.url.path]
            process.standardOutput = FileHandle.nullDevice
            let errors = Pipe()
            process.standardError = errors
            try process.run()
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let output = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw CocoaError(.executableLoad, userInfo: [
                    NSLocalizedDescriptionKey: output.isEmpty
                        ? "“\(action.name)” failed."
                        : "“\(action.name)”: \(output)",
                ])
            }
        }.value
    }
}
