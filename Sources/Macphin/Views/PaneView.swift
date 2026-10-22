import AppKit
import QuickLook
import SwiftUI

struct PaneView: View {
    let pane: PaneState
    let window: WindowState
    let isActive: Bool

    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            LocationBar(pane: pane, window: window)
            Divider()
            if pane.isSearching { searchBanner }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { if isDropTarget { Rectangle().strokeBorder(Color.accentColor, lineWidth: 2) } }
                .dropDestination(for: URL.self) { urls, _ in
                    Actions(window: window, pane: pane).drop(urls, into: pane.url)
                } isTargeted: { isDropTarget = $0 }
            if pane.isFilterBarVisible {
                Divider()
                FilterBar(pane: pane)
            }
            Divider()
            StatusBar(pane: pane)
        }
        .overlay(alignment: .top) {
            if window.activeTab.isSplit && isActive {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
        .opacity(window.activeTab.isSplit && !isActive ? 0.92 : 1)
        .simultaneousGesture(TapGesture().onEnded { activate() })
        .quickLookPreview(Binding(get: { pane.quickLookURL }, set: { pane.quickLookURL = $0 }),
                          in: pane.visibleItems.map(\.url))
    }

    @ViewBuilder private var content: some View {
        if let error = pane.loadError {
            if pane.loadErrorIsPermission {
                permissionError
            } else {
                ContentUnavailableView("Cannot Open Folder", systemImage: "exclamationmark.triangle", description: Text(error))
            }
        } else if pane.visibleItems.isEmpty && !pane.isLoading {
            ContentUnavailableView(
                pane.isSearching ? "No Results" : pane.filterText.isEmpty ? "Folder is Empty" : "No Matches",
                systemImage: pane.isSearching || !pane.filterText.isEmpty ? "magnifyingglass" : "folder")
                .contextMenu { FileContextMenu(window: window, pane: pane) }
        } else {
            switch pane.viewMode {
            case .icons: IconsView(pane: pane, window: window)
            case .compact: CompactView(pane: pane, window: window)
            case .details: DetailsView(pane: pane, window: window)
            }
        }
    }

    private var permissionError: some View {
        ContentUnavailableView {
            Label("No Access to “\(pane.title)”", systemImage: "lock.shield")
        } description: {
            Text("macOS privacy protection blocks this folder until Macphin is allowed in System Settings > Privacy & Security (Full Disk Access, or Files and Folders).")
        } actions: {
            Button("Open Privacy Settings") { Privacy.openFullDiskAccessSettings() }
            Button("Try Again") { pane.reload() }
        }
    }

    private var searchBanner: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            Text("Search results in “\(pane.title)”")
            Spacer()
            Button("Done") { pane.endSearch() }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.1))
    }

    private func activate() {
        if let index = window.activeTab.panes.firstIndex(where: { $0 === pane }) {
            window.activeTab.activePaneIndex = index
        }
    }
}

struct FilterBar: View {
    let pane: PaneState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
            TextField("Filter…", text: Binding(get: { pane.filterText }, set: { pane.filterText = $0 }))
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand { close() }
            if !pane.filterText.isEmpty {
                Button { pane.filterText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Button { close() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(.bar)
        .onAppear { focused = true }
    }

    private func close() {
        pane.filterText = ""
        pane.isFilterBarVisible = false
    }
}

struct StatusBar: View {
    let pane: PaneState

    var body: some View {
        HStack(spacing: 10) {
            if pane.isLoading || pane.search.isGathering { ProgressView().controlSize(.small) }
            Text(summary).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let free = freeSpace { Text(free).foregroundStyle(.secondary) }
            Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
            Slider(value: Binding(get: { pane.zoom }, set: { pane.zoom = $0 }), in: 16...256)
                .controlSize(.mini)
                .frame(width: 100)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(.bar)
    }

    private var summary: String {
        let selected = pane.selectedItems
        if selected.count == 1 { return selected[0].name + (selected[0].opensAsFolder ? "" : " (\(selected[0].formattedSize))") }
        if !selected.isEmpty {
            let hasFiles = selected.contains { !$0.opensAsFolder }
            return "\(selected.count) selected" + (hasFiles ? " (\(totalSize(selected)))" : "")
        }
        let stats = pane.visibleStats
        let folders = stats.folders, files = stats.files
        var parts: [String] = []
        if folders > 0 { parts.append("\(folders) folder\(folders == 1 ? "" : "s")") }
        if files > 0 {
            parts.append("\(files) file\(files == 1 ? "" : "s") (\(ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .file)))")
        }
        return parts.isEmpty ? "Empty" : parts.joined(separator: ", ")
    }

    private func totalSize(_ items: [FileItem]) -> String {
        ByteCountFormatter.string(fromByteCount: items.filter { !$0.opensAsFolder }.reduce(0) { $0 + $1.size }, countStyle: .file)
    }

    private var freeSpace: String? {
        guard let values = try? pane.url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return ByteCountFormatter.string(fromByteCount: free, countStyle: .file) + " free"
    }
}
