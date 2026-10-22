import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileCell: View {
    let item: FileItem
    let pane: PaneState
    let window: WindowState
    let iconSize: CGFloat
    let horizontal: Bool

    @State private var isDropTarget = false

    private var isSelected: Bool { pane.selection.contains(item.url) }
    private var isRenaming: Bool { pane.renamingURL == item.url }

    var body: some View {
        content
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.25) : isDropTarget ? Color.accentColor.opacity(0.15) : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1))
            .opacity(item.isHidden ? 0.55 : 1)
            .contentShape(Rectangle())
            .help(item.name)
            .onTapGesture(count: 2) { pane.open(item) }
            .simultaneousGesture(TapGesture().onEnded {
                pane.click(item, modifiers: NSEvent.modifierFlags)
                window.activeTab.activePaneIndex = window.activeTab.panes.firstIndex { $0 === pane } ?? 0
            })
            .onDrag {
                let urls = isSelected ? pane.selectedItems.map(\.url) : [item.url]
                return NSItemProvider(object: (urls.first ?? item.url) as NSURL)
            }
            .modifier(FolderDropModifier(item: item, window: window, pane: pane, isTargeted: $isDropTarget))
            .contextMenu {
                FileContextMenu(window: window, pane: pane)
                    .onAppear { if !isSelected { pane.selection = [item.url] } }
            }
    }

    @ViewBuilder private var content: some View {
        if horizontal {
            HStack(spacing: 6) {
                FileIcon(url: item.url, size: iconSize, thumbnails: false)
                if isRenaming {
                    InlineRename(item: item, pane: pane, window: window)
                } else {
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
        } else {
            VStack(spacing: 4) {
                FileIcon(url: item.url, size: iconSize)
                if isRenaming {
                    InlineRename(item: item, pane: pane, window: window, centered: true)
                } else {
                    Text(item.name)
                        .font(.callout)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

struct FolderDropModifier: ViewModifier {
    let item: FileItem
    let window: WindowState
    let pane: PaneState
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        if item.opensAsFolder {
            content.dropDestination(for: URL.self) { urls, _ in
                Actions(window: window, pane: pane).drop(urls, into: item.url)
            } isTargeted: { isTargeted = $0 }
        } else {
            content
        }
    }
}

struct IconsView: View {
    let pane: PaneState
    let window: WindowState

    var body: some View {
        let size = pane.zoom
        let cellWidth = max(size + 36, 90)
        GeometryReader { geometry in
            let columns = max(1, Int((geometry.size.width - 16) / (cellWidth + 8)))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: 8, alignment: .top), count: columns),
                              alignment: .leading, spacing: 8) {
                        ForEach(pane.visibleItems) { item in
                            FileCell(item: item, pane: pane, window: window, iconSize: size, horizontal: false)
                                .frame(width: cellWidth)
                                .id(item.url)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: pane.renamingURL) { if let url = pane.renamingURL { proxy.scrollTo(url) } }
                .background(BackgroundTapCatcher(pane: pane, window: window))
                .gridKeyboard(pane: pane, rowStep: columns, columnStep: 1, proxy: proxy)
            }
        }
    }
}

struct CompactView: View {
    let pane: PaneState
    let window: WindowState

    var body: some View {
        let iconSize = max(16, min(48, pane.zoom / 2.5))
        let rowHeight = iconSize + 8
        GeometryReader { geometry in
            let rows = max(1, Int((geometry.size.height - 16) / (rowHeight + 2)))
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(rowHeight), spacing: 2), count: rows),
                              alignment: .top, spacing: 12) {
                        ForEach(pane.visibleItems) { item in
                            FileCell(item: item, pane: pane, window: window, iconSize: iconSize, horizontal: true)
                                .frame(width: 220, alignment: .leading)
                                .id(item.url)
                        }
                    }
                    .padding(8)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                }
                .background(BackgroundTapCatcher(pane: pane, window: window))
                .gridKeyboard(pane: pane, rowStep: 1, columnStep: rows, proxy: proxy)
            }
        }
    }
}

private struct BackgroundTapCatcher: View {
    let pane: PaneState
    let window: WindowState

    var body: some View {
        Color(nsColor: .textBackgroundColor)
            .contentShape(Rectangle())
            .onTapGesture { pane.selection = [] }
            .contextMenu {
                FileContextMenu(window: window, pane: pane).onAppear { pane.selection = [] }
            }
    }
}

private struct GridKeyboard: ViewModifier {
    let pane: PaneState
    let rowStep: Int
    let columnStep: Int
    let proxy: ScrollViewProxy

    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                let horizontal = rowStep == 1 && columnStep > 1
                let step: Int
                switch press.key {
                case .leftArrow: step = horizontal ? -columnStep : -1
                case .rightArrow: step = horizontal ? columnStep : 1
                case .upArrow: step = horizontal ? -1 : -rowStep
                default: step = horizontal ? 1 : rowStep
                }
                if press.modifiers.contains(.command), press.key == .upArrow { pane.goUp(); return .handled }
                if press.modifiers.contains(.command), press.key == .downArrow { pane.openSelection(); return .handled }
                pane.moveSelection(by: step, extend: press.modifiers.contains(.shift))
                if let url = pane.selectionAnchor { proxy.scrollTo(url) }
                return .handled
            }
            .onKeyPress(.return) { pane.openSelection(); return .handled }
            .onKeyPress(.space) { pane.toggleQuickLook(); return .handled }
            .onKeyPress(.escape) { pane.selection = []; pane.quickLookURL = nil; return .handled }
            .onAppear { focused = true }
    }
}

extension View {
    func gridKeyboard(pane: PaneState, rowStep: Int, columnStep: Int, proxy: ScrollViewProxy) -> some View {
        modifier(GridKeyboard(pane: pane, rowStep: rowStep, columnStep: columnStep, proxy: proxy))
    }
}
