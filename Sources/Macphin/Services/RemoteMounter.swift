import AppKit
import NetFS

enum RemoteMounter {
    private static let netFSSchemes: Set<String> = ["smb", "cifs", "afp", "nfs", "ftp", "http", "https", "webdav", "webdavs"]
    private static let sshSchemes: Set<String> = ["sftp", "ssh", "fish"]
    private static let shareSchemes: Set<String> = ["smb", "cifs", "afp"]
    private static let sshfsCandidates = ["/opt/homebrew/bin/sshfs", "/usr/local/bin/sshfs", "/usr/bin/sshfs"]

    static func parse(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(),
              netFSSchemes.contains(scheme) || sshSchemes.contains(scheme),
              url.host?.isEmpty == false else { return nil }
        return url
    }

    static func mount(_ url: URL, user: String?, password: String?) async throws -> URL {
        let scheme = url.scheme?.lowercased() ?? ""
        let user = user?.isEmpty == false ? user : url.user
        let password = password?.isEmpty == false ? password : url.password
        if sshSchemes.contains(scheme) {
            return try await Task.detached { try mountSSHFS(url, user: user, password: password) }.value
        }
        return try await mountNetFS(url, user: user, password: password)
    }

    private static func mountNetFS(_ url: URL, user: String?, password: String?) async throws -> URL {
        let target = netFSURL(for: url)
        let mountPoint: String = try await withCheckedThrowingContinuation { continuation in
            var requestID: AsyncRequestID?
            let status = NetFSMountURLAsync(
                target as CFURL, nil, user as CFString?, password as CFString?, nil, nil,
                &requestID, DispatchQueue.global(qos: .userInitiated)
            ) { status, _, mountPoints in
                if status == 0, let path = (mountPoints as NSArray?)?.firstObject as? String {
                    continuation.resume(returning: path)
                } else if status == EEXIST, let existing = existingMount(for: target) {
                    continuation.resume(returning: existing.path)
                } else {
                    continuation.resume(throwing: mountError(status, host: target.host ?? ""))
                }
            }
            if status != 0 { continuation.resume(throwing: mountError(status, host: target.host ?? "")) }
        }
        var local = URL(fileURLWithPath: mountPoint, isDirectory: true)
        if shareSchemes.contains(target.scheme?.lowercased() ?? "") {
            for component in target.pathComponents.filter({ $0 != "/" }).dropFirst() {
                local.append(path: component)
            }
        }
        return local
    }

    private static func netFSURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        switch components.scheme?.lowercased() {
        case "webdav": components.scheme = "http"
        case "webdavs": components.scheme = "https"
        case "cifs": components.scheme = "smb"
        default: break
        }
        components.user = nil
        components.password = nil
        return components.url ?? url
    }

    private static func existingMount(for url: URL) -> URL? {
        let key: URLResourceKey = .volumeURLForRemountingKey
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [key], options: []) ?? []
        let share = url.pathComponents.dropFirst().first?.lowercased()
        return volumes.first { volume in
            guard let remote = try? volume.resourceValues(forKeys: [key]).volumeURLForRemounting,
                  remote.host?.lowercased() == url.host?.lowercased() else { return false }
            return share == nil || remote.pathComponents.dropFirst().first?.lowercased() == share
        }
    }

    private static func mountError(_ status: Int32, host: String) -> Error {
        // -128 is userCanceledErr from the system authentication sheet.
        if status == ECANCELED || status == -128 { return CancellationError() }
        let reason = status > 0
            ? String(cString: strerror(status))
            : "error \(status)"
        return CocoaError(.fileReadUnknown, userInfo: [
            NSLocalizedDescriptionKey: "Could not connect to “\(host)”: \(reason)."])
    }

    private static func mountSSHFS(_ url: URL, user: String?, password: String?) throws -> URL {
        guard let sshfs = sshfsCandidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw CocoaError(.featureUnsupported, userInfo: [NSLocalizedDescriptionKey:
                "SFTP needs macFUSE and sshfs. Install them (for example `brew install --cask macfuse` and `brew install gromgit/fuse/sshfs-mac`), then try again."])
        }
        guard let host = url.host else { throw CocoaError(.fileReadInvalidFileName) }
        let login = [user, host].compactMap { $0 }.joined(separator: "@")
        let mountName = login + (url.port.map { "-\($0)" } ?? "")
        let mountsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Macphin/Mounts")
        let mountPoint = mountsDirectory.appending(path: mountName, directoryHint: .isDirectory)

        let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        if mounted.contains(where: { $0.standardizedFileURL.path == mountPoint.standardizedFileURL.path }) {
            return mountPoint
        }
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        var arguments = ["\(login):\(url.path)", mountPoint.path,
                         "-o", "volname=\(host),reconnect,ServerAliveInterval=15,ConnectTimeout=10"]
        if let port = url.port { arguments += ["-p", String(port)] }
        arguments += ["-o", password == nil ? "BatchMode=yes" : "password_stdin"]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshfs)
        process.arguments = arguments
        let input = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardError = errors
        try process.run()
        if let password { input.fileHandleForWriting.write(Data((password + "\n").utf8)) }
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: mountPoint)
            let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let hint = password == nil && output.contains("Permission denied") ? " Enter a password or set up an SSH key." : ""
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey:
                "Could not connect to “\(host)”: \(output.isEmpty ? "sshfs failed" : output).\(hint)"])
        }
        return mountPoint
    }
}
