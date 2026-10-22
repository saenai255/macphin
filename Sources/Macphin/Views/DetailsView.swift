import AppKit
import SwiftUI

struct DetailsView: View {
    let pane: PaneState
    let window: WindowState

    @State private var sortOrder: [KeyPathComparator<FileItem>] = []
    @AppStorage("detailsColumns") private var storedColumns = Data()

    private var iconSize: CGFloat { max(16, min(32, pane.zoom / 4)) }
    private static let dateFormat = Date.FormatStyle(date: .abbreviated, time: .shortened)

    private enum Column {
        static let name = "name"
        static let size = "size"
        static let modified = "modified"
        static let created = "created"
        static let permissions = "permissions"
        static let owner = "owner"
        static let kind = "kind"
        static let location = "location"
    }

    private var columnCustomization: Binding<TableColumnCustomization<FileItem>> {
        Binding {
            var customization = (try? JSONDecoder().decode(
                TableColumnCustomization<FileItem>.self, from: storedColumns)) ?? TableColumnCustomization()
            if pane.isSearching { customization[visibility: Column.location] = .visible }
            return customization
        } set: { customization in
            if let data = try? JSONEncoder().encode(customization) { storedColumns = data }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            table
                .onChange(of: pane.scrollTarget) {
                    guard let target = pane.scrollTarget else { return }
                    pane.scrollTarget = nil
                    proxy.scrollTo(target)
                }
        }
    }

    private var table: some View {
        Table(of: FileItem.self, selection: Binding(get: { pane.selection }, set: { pane.selection = $0 }),
              sortOrder: $sortOrder, columnCustomization: columnCustomization) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 6) {
                    FileIcon(url: item.url, size: iconSize, thumbnails: false)
                        .overlay(alignment: .bottomTrailing) { gitBadge(for: item) }
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
            .customizationID(Column.name)
            TableColumn("Size", value: \.sizeForSort) { item in
                Text(item.formattedSize).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 60, ideal: 80)
            .customizationID(Column.size)
            TableColumn("Modified", value: \.modified) { item in
                Text(item.modified, format: Self.dateFormat).foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 160)
            .customizationID(Column.modified)
            TableColumn("Created", value: \.created) { item in
                Text(item.created, format: Self.dateFormat).foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 160)
            .customizationID(Column.created)
            .defaultVisibility(.hidden)
            TableColumn("Permissions", value: \.permissions) { item in
                Text(item.permissions).foregroundStyle(.secondary).font(.system(.body, design: .monospaced))
            }
            .width(min: 80, ideal: 100)
            .customizationID(Column.permissions)
            .defaultVisibility(.hidden)
            TableColumn("Owner", value: \.owner) { item in
                Text(item.owner).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 120)
            .customizationID(Column.owner)
            .defaultVisibility(.hidden)
            TableColumn("Type", value: \.kind) { item in
                Text(item.kind).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 120)
            .customizationID(Column.kind)
            TableColumn("Location", value: \.location) { item in
                Text(item.location).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            .width(min: 100, ideal: 260)
            .customizationID(Column.location)
            .defaultVisibility(.hidden)
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
        .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters), phases: .down) { press in
            guard press.modifiers.isDisjoint(with: [.command, .control]) else { return .ignored }
            pane.typeAhead(press.characters)
            return .handled
        }
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

    @ViewBuilder private func gitBadge(for item: FileItem) -> some View {
        if let status = pane.gitStatus?.status(for: item.url) {
            Image(systemName: status.symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color(nsColor: status.color))
                .font(.system(size: iconSize * 0.5))
                .offset(x: 3, y: 2)
                .help(status.label)
        }
    }

    private func syncSortOrder() {
        let order: SortOrder = pane.sortAscending ? .forward : .reverse
        switch pane.sortKey {
        case .name: sortOrder = [KeyPathComparator(\.name, order: order)]
        case .size: sortOrder = [KeyPathComparator(\.sizeForSort, order: order)]
        case .modified: sortOrder = [KeyPathComparator(\.modified, order: order)]
        case .created: sortOrder = [KeyPathComparator(\.created, order: order)]
        case .kind: sortOrder = [KeyPathComparator(\.kind, order: order)]
        }
    }

    private func applySortOrder() {
        guard let first = sortOrder.first else { return }
        switch first.keyPath {
        case \FileItem.sizeForSort: pane.sortKey = .size
        case \FileItem.modified: pane.sortKey = .modified
        case \FileItem.created: pane.sortKey = .created
        case \FileItem.kind: pane.sortKey = .kind
        default: pane.sortKey = .name
        }
        pane.sortAscending = first.order == .forward
    }
}
