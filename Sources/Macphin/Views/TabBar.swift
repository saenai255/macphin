import SwiftUI

struct TabBar: View {
    let window: WindowState

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(window.tabs) { tab in
                        TabButton(tab: tab, window: window)
                    }
                }
            }
            Button { window.newTab() } label: {
                Image(systemName: "plus").frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .help("New Tab")
        }
        .frame(height: 28)
        .background(.bar)
    }
}

private struct TabButton: View {
    let tab: TabState
    let window: WindowState
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
        .dropDestination(for: URL.self) { urls, _ in
            Actions(window: window, pane: tab.activePane).drop(urls, into: tab.activePane.url)
        } isTargeted: { targeted in
            isTargeted = targeted
            if targeted { window.activeTabID = tab.id }
        }
        .contextMenu {
            Button("New Tab") { window.newTab(url: tab.activePane.url) }
            Button("Close Tab") { window.closeTab(tab.id) }
            Button("Close Other Tabs") {
                window.tabs.removeAll { $0.id != tab.id }
                window.activeTabID = tab.id
            }
        }
    }
}
