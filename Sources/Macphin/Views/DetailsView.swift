import AppKit
import SwiftUI

struct DetailsView: View {
    let pane: PaneState
    let window: WindowState

    @State private var sortOrder: [KeyPathComparator<FileItem>] = []

    private var iconSize: CGFloat { max(16, min(32, pane.zoom / 4)) }
    private static let dateFormat = Date.FormatStyle(date: .abbreviated, time: .shortened)

    var body: some View {
        Table(of: FileItem.self, selection: Binding(get: { pane.selection }, set: { pane.selection = $0 }), sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 6) {
                    FileIcon(url: item.url, size: iconSize, thumbnails: false)
                    if pane.renamingURL == item.url {
                        InlineRename(item: item, pane: pane, window: window)
                    } else {
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                    }
                }
                .opacity(item.isHidden ? 0.55 : 1)
                .help(pane.isSearching ? item.url.path : item.name)
            }
            .width(min: 160, ideal: 320)
            TableColumn("Size", value: \.sizeForSort) { item in
                Text(item.formattedSize).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 60, ideal: 80)
            TableColumn("Modified", value: \.modified) { item in
                Text(item.modified, format: Self.dateFormat).foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 160)
            TableColumn("Type", value: \.kind) { item in
                Text(item.kind).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 120)
            if pane.isSearching {
                TableColumn("Location") { (item: FileItem) in
                    Text(item.url.deletingLastPathComponent().path).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
            }
        } rows: {
            ForEach(pane.visibleItems) { item in
                TableRow(item)
                    .itemProvider { NSItemProvider(object: item.url as NSURL) }
                    .dropDestination(for: URL.self) { urls in
                        guard item.opensAsFolder else { return }
                        _ = Actions(window: window, pane: pane).drop(urls, into: item.url)
                    }
            }
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            FileContextMenu(window: window, pane: pane)
                .onAppear { if !urls.isEmpty, urls.isDisjoint(with: pane.selection) { pane.selection = urls } }
        } primaryAction: { urls in
            pane.selection = urls
            pane.openSelection()
        }
        .onKeyPress(.space) { pane.toggleQuickLook(); return .handled }
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.key == .upArrow { pane.goUp() } else { pane.openSelection() }
            return .handled
        }
        .onChange(of: pane.selection) {
            if pane.quickLookURL != nil, let first = pane.selectedItems.first { pane.quickLookURL = first.url }
        }
        .onAppear { syncSortOrder() }
        .onChange(of: sortOrder) { applySortOrder() }
    }

    private func syncSortOrder() {
        let order: SortOrder = pane.sortAscending ? .forward : .reverse
        switch pane.sortKey {
        case .name: sortOrder = [KeyPathComparator(\.name, order: order)]
        case .size: sortOrder = [KeyPathComparator(\.sizeForSort, order: order)]
        case .modified: sortOrder = [KeyPathComparator(\.modified, order: order)]
        case .kind: sortOrder = [KeyPathComparator(\.kind, order: order)]
        }
    }

    private func applySortOrder() {
        guard let first = sortOrder.first else { return }
        switch first.keyPath {
        case \FileItem.sizeForSort: pane.sortKey = .size
        case \FileItem.modified: pane.sortKey = .modified
        case \FileItem.kind: pane.sortKey = .kind
        default: pane.sortKey = .name
        }
        pane.sortAscending = first.order == .forward
    }
}
