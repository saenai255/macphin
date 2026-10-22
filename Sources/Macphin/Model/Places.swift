import AppKit
import Observation

struct Place: Identifiable, Hashable {
    let url: URL
    let name: String
    let symbol: String
    var isEjectable = false
    var totalCapacity: Int64? = nil
    var availableCapacity: Int64? = nil
    var id: URL { url }
}

@MainActor
@Observable
final class PlacesStore {
    static let shared = PlacesStore()

    private(set) var places: [Place] = []
    private(set) var devices: [Place] = []
    private(set) var servers: [Place] = []
    private let defaultsKey = "customPlaces"
    private let serversKey = "servers"

    private init() {
        loadPlaces()
        loadServers()
        refreshDevices()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PlacesStore.shared.refreshDevices() }
            }
        }
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { PlacesStore.shared.refreshDevices() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    static var trashURL: URL {
        (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash")
    }

    private static var defaultPlaces: [Place] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        func dir(_ d: FileManager.SearchPathDirectory) -> URL? { fm.urls(for: d, in: .userDomainMask).first }
        return [
            Place(url: home, name: "Home", symbol: "house"),
            dir(.desktopDirectory).map { Place(url: $0, name: "Desktop", symbol: "menubar.dock.rectangle") },
            dir(.documentDirectory).map { Place(url: $0, name: "Documents", symbol: "doc") },
            dir(.downloadsDirectory).map { Place(url: $0, name: "Downloads", symbol: "arrow.down.circle") },
            dir(.picturesDirectory).map { Place(url: $0, name: "Pictures", symbol: "photo") },
            dir(.musicDirectory).map { Place(url: $0, name: "Music", symbol: "music.note") },
            dir(.moviesDirectory).map { Place(url: $0, name: "Videos", symbol: "film") },
            Place(url: URL(fileURLWithPath: "/Applications"), name: "Applications", symbol: "square.grid.3x3"),
            Place(url: URL(fileURLWithPath: "/"), name: "Root", symbol: "externaldrive"),
            Place(url: trashURL, name: "Trash", symbol: "trash"),
        ].compactMap { $0 }
    }

    private func loadPlaces() {
        guard let stored = UserDefaults.standard.array(forKey: defaultsKey) as? [[String: String]] else {
            places = Self.defaultPlaces
            return
        }
        places = stored.compactMap { entry in
            guard let path = entry["path"], let name = entry["name"] else { return nil }
            return Place(url: URL(fileURLWithPath: path), name: name, symbol: entry["symbol"] ?? "folder")
        }
    }

    private func save() {
        let stored = places.map { ["path": $0.url.path, "name": $0.name, "symbol": $0.symbol] }
        UserDefaults.standard.set(stored, forKey: defaultsKey)
    }

    func add(_ url: URL) {
        guard !places.contains(where: { $0.url == url }) else { return }
        places.append(Place(url: url, name: FileManager.default.displayName(atPath: url.path), symbol: "folder"))
        save()
    }

    func remove(_ place: Place) {
        places.removeAll { $0.url == place.url }
        save()
    }

    func rename(_ place: Place, to name: String) {
        guard let index = places.firstIndex(of: place), !name.isEmpty else { return }
        places[index] = Place(url: place.url, name: name, symbol: place.symbol)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        places.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func resetToDefaults() {
        places = Self.defaultPlaces
        save()
    }

    private func loadServers() {
        let stored = UserDefaults.standard.stringArray(forKey: serversKey) ?? []
        servers = stored.compactMap(URL.init(string:)).map(Self.serverPlace)
    }

    private static func serverPlace(_ url: URL) -> Place {
        let user = url.user.map { "\($0)@" } ?? ""
        let path = url.path.isEmpty || url.path == "/" ? "" : url.path
        return Place(url: url, name: "\(user)\(url.host ?? "")\(path)", symbol: "network")
    }

    func addServer(_ url: URL) {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        components.password = nil
        guard let clean = components.url, !servers.contains(where: { $0.url == clean }) else { return }
        servers.append(Self.serverPlace(clean))
        UserDefaults.standard.set(servers.map(\.url.absoluteString), forKey: serversKey)
    }

    func removeServer(_ place: Place) {
        servers.removeAll { $0.url == place.url }
        UserDefaults.standard.set(servers.map(\.url.absoluteString), forKey: serversKey)
    }

    func refreshDevices() {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey,
                                      .volumeIsInternalKey, .volumeIsLocalKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        devices = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let ejectable = (values?.volumeIsEjectable ?? false) || (values?.volumeIsRemovable ?? false)
            let isInternal = values?.volumeIsInternal ?? true
            let isNetwork = values?.volumeIsLocal == false
            let symbol = isNetwork ? "server.rack"
                : ejectable ? "externaldrive.badge.minus"
                : isInternal ? "internaldrive" : "externaldrive"
            let importantCapacity = values?.volumeAvailableCapacityForImportantUsage ?? 0
            let available = importantCapacity > 0 ? importantCapacity
                : values?.volumeAvailableCapacity.map(Int64.init)
            return Place(
                url: url,
                name: values?.volumeLocalizedName ?? url.lastPathComponent,
                symbol: symbol,
                isEjectable: ejectable || isNetwork || !isInternal,
                totalCapacity: values?.volumeTotalCapacity.map(Int64.init),
                availableCapacity: available)
        }
    }

    func eject(_ place: Place) throws {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: place.url)
        } catch {
            // FUSE mounts (sshfs) are not always ejectable through NSWorkspace.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = ["unmount", place.url.path]
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 { throw error }
        }
        refreshDevices()
    }
}
