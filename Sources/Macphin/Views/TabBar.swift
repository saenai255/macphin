import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum TabDrag {
    static let prefix = "macphin-tab:"
    static var current: UUID?
}

struct TabBar: View {
    let window: WindowState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(window.tabs) { tab in
                        TabButton(tab: tab, window: window) { moveToNewWindow(tab) }
                    }
                }
            }
            Color.clear
                .frame(width: 24)
                .contentShape(Rectangle())
                .onDrop(of: [.utf8PlainText], delegate: TabDropDelegate(target: nil, window: window, isTargeted: .constant(false)))
            Button { window.newTab() } label: {
                Image(systemName: "plus").frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .help("New Tab")
        }
        .frame(height: 28)
        .background(.bar)
    }

    private func moveToNewWindow(_ tab: TabState) {
        guard let removed = window.removeTab(tab.id) else { return }
        SessionStore.shared.detach(removed)
        openWindow(id: "main")
    }
}

private struct TabButton: View {
    let tab: TabState
    let window: WindowState
    let moveToNewWindow: () -> Void
    @State private var isHovered = false
    @State private var isTargeted = false

    private var isActive: Bool { tab.id == window.activeTabID }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.isSplit ? "rectangle.split.2x1" : "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(tab.title).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            Button { window.closeTab(tab.id) } label: {
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isActive ? 1 : 0)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .frame(minWidth: 120, maxWidth: 220, minHeight: 26)
        .background(isActive ? Color(nsColor: .controlBackgroundColor) : isTargeted ? Color.accentColor.opacity(0.2) : Color.clear)
        .overlay(alignment: .bottom) {
            if isActive { Rectangle().fill(Color.accentColor).frame(height: 2) }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { window.activeTabID = tab.id }
        .help(tab.activePane.url.path)
        .onDrag {
            TabDrag.current = tab.id
            return NSItemProvider(object: (TabDrag.prefix + tab.id.uuidString) as NSString)
        }
        .onDrop(of: [.fileURL, .utf8PlainText], delegate: TabDropDelegate(target: tab, window: window, isTargeted: $isTargeted))
        .contextMenu {
            Button("New Tab") { window.newTab(url: tab.activePane.url) }
            Button("Move Tab to New Window") { moveToNewWindow() }.disabled(window.tabs.count < 2)
            Divider()
            Button("Close Tab") { window.closeTab(tab.id) }
            Button("Close Other Tabs") {
                window.tabs.removeAll { $0.id != tab.id }
                window.activeTabID = tab.id
            }
        }
    }
}

private struct TabDropDelegate: DropDelegate {
    let target: TabState?
    let window: WindowState
    @Binding var isTargeted: Bool

    private func isFileDrop(_ info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func validateDrop(info: DropInfo) -> Bool {
        isFileDrop(info) ? target != nil : TabDrag.current != nil
    }

    func dropEntered(info: DropInfo) {
        if isFileDrop(info) {
            isTargeted = true
            if let target { window.activeTabID = target.id }
        } else if let dragged = TabDrag.current, let target, window.tabs.contains(where: { $0.id == dragged }) {
            withAnimation(.snappy) { window.moveTab(dragged, before: target.id) }
        }
    }

    func dropExited(info: DropInfo) { isTargeted = false }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: isFileDrop(info) ? (NSEvent.modifierFlags.contains(.option) ? .copy : .move) : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        if isFileDrop(info) {
            guard let target else { return false }
            let destination = target.activePane.url
            let providers = info.itemProviders(for: [.fileURL])
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                        urls.append(url)
                    } else if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                }
                _ = Actions(window: window, pane: target.activePane).drop(urls, into: destination)
            }
            return true
        }
        guard let dragged = TabDrag.current else { return false }
        TabDrag.current = nil
        if window.tabs.contains(where: { $0.id == dragged }) {
            if target == nil, let tab = window.removeTab(dragged) { window.insertTab(tab, before: nil) }
            return true
        }
        guard let source = SessionStore.shared.window(containing: dragged),
              let tab = source.removeTab(dragged) else { return false }
        window.insertTab(tab, before: target?.id)
        return true
    }
}
