import AppKit
import SwiftUI

struct PlacesSidebar: View {
    let window: WindowState
    private var store: PlacesStore { .shared }

    var body: some View {
        List(selection: Binding<URL?>(
            get: { window.activePane.url.standardizedFileURL },
            set: { url in
                guard let url else { return }
                if url.isFileURL { window.activePane.navigate(to: url) } else { window.connect(to: url) }
            })
        ) {
            Section("Places") {
                ForEach(store.places) { place in
                    PlaceRow(place: place, window: window)
                        .contextMenu {
                            placeMenu(place)
                            Divider()
                            Button("Remove from Places") { store.remove(place) }
                            Button("Reset Places") { store.resetToDefaults() }
                        }
                }
                .onMove { store.move(from: $0, to: $1) }
            }
            Section("Network") {
                ForEach(store.servers) { server in
                    Label(server.name, systemImage: server.symbol)
                        .tag(server.url)
                        .help(server.url.absoluteString)
                        .contextMenu {
                            Button("Connect") { window.connect(to: server.url) }
                            Button("Remove from Network") { store.removeServer(server) }
                        }
                }
                Button { window.showConnectSheet = true } label: {
                    Label("Connect to Server…", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Section("Devices") {
                ForEach(store.devices) { device in
                    PlaceRow(place: device, window: window)
                        .contextMenu {
                            placeMenu(device)
                            if device.isEjectable {
                                Divider()
                                Button("Eject") { window.run { try store.eject(device) } }
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private func placeMenu(_ place: Place) -> some View {
        Button("Open in New Tab") { window.newTab(url: place.url) }
        Button("Open in Split View") { window.activeTab.openInSplit(place.url) }
        Button("Show in Finder") { NSWorkspace.shared.open(place.url) }
        if place.url.standardizedFileURL == PlacesStore.trashURL.standardizedFileURL {
            Button("Empty Trash…") { Actions(window: window).emptyTrash() }
        }
    }
}

private struct PlaceRow: View {
    let place: Place
    let window: WindowState
    @State private var isTargeted = false

    private var capacity: (used: Double, description: String)? {
        guard let total = place.totalCapacity, let available = place.availableCapacity, total > 0 else { return nil }
        let used = Double(total - min(max(available, 0), total)) / Double(total)
        let free = ByteCountFormatter.string(fromByteCount: max(0, available), countStyle: .file)
        let size = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        return (used, "\(free) free of \(size)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(place.name, systemImage: place.symbol)
                Spacer()
                if place.isEjectable {
                    Button { window.run { try PlacesStore.shared.eject(place) } } label: {
                        Image(systemName: "eject.fill").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Eject")
                }
            }
            if let capacity {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule()
                            .fill(capacity.used > 0.9 ? Color.red : Color.accentColor)
                            .frame(width: proxy.size.width * capacity.used)
                    }
                }
                .frame(height: 3)
                .help(capacity.description)
            }
        }
        .tag(place.url.standardizedFileURL)
        .listRowBackground(isTargeted ? RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.25)) : nil)
        .dropDestination(for: URL.self) { urls, _ in
            if place.url.standardizedFileURL == PlacesStore.trashURL.standardizedFileURL {
                Actions(window: window).trash(urls)
                return true
            }
            return Actions(window: window).drop(urls, into: place.url)
        } isTargeted: { isTargeted = $0 }
    }
}
