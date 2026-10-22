import AppKit
import SwiftUI

struct IconsView: View {
    let pane: PaneState
    let window: WindowState

    var body: some View {
        FileCollectionView(pane: pane, window: window, style: .icons)
            .contextMenu { FileContextMenu(window: window, pane: pane) }
    }
}

struct CompactView: View {
    let pane: PaneState
    let window: WindowState

    var body: some View {
        FileCollectionView(pane: pane, window: window, style: .compact)
            .contextMenu { FileContextMenu(window: window, pane: pane) }
    }
}

enum GridStyle {
    case icons, compact
}

struct GridBadge: Equatable {
    let symbol: String
    let color: NSColor
}

struct FileCollectionView: NSViewRepresentable {
    let pane: PaneState
    let window: WindowState
    let style: GridStyle

    func makeCoordinator() -> Coordinator { Coordinator(pane: pane, window: window, style: style) }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = GridFlowLayout()
        let collection = FileCollection()
        collection.coordinator = context.coordinator
        collection.collectionViewLayout = layout
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.backgroundColors = [.textBackgroundColor]
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        collection.register(FileGridCell.self, forItemWithIdentifier: FileGridCell.identifier)
        collection.registerForDraggedTypes([.fileURL])
        collection.setDraggingSourceOperationMask([.copy, .move, .link], forLocal: false)
        collection.setDraggingSourceOperationMask([.copy, .move], forLocal: true)

        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.hasVerticalScroller = style == .icons
        scroll.hasHorizontalScroller = style == .compact
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        context.coordinator.collection = collection
        context.coordinator.update()
        DispatchQueue.main.async { collection.window?.makeFirstResponder(collection) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.pane = pane
        context.coordinator.update()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
        var pane: PaneState
        let window: WindowState
        let style: GridStyle
        weak var collection: FileCollection?

        private var items: [FileItem] = []
        private var zoom: Double = 0
        private var gitVersion = 0
        private var dropTarget: URL?
        private var renameInProgress: URL?

        init(pane: PaneState, window: WindowState, style: GridStyle) {
            self.pane = pane
            self.window = window
            self.style = style
        }

        private var iconSize: CGFloat {
            style == .icons ? pane.zoom : max(16, min(48, pane.zoom / 2.5))
        }

        func update() {
            guard let collection, let layout = collection.collectionViewLayout as? GridFlowLayout else { return }
            let newItems = pane.visibleItems
            let zoomChanged = pane.zoom != zoom
            if zoomChanged || layout.itemSize == .zero {
                zoom = pane.zoom
                configure(layout)
            }
            if newItems != items || zoomChanged {
                items = newItems
                gitVersion = pane.gitStatusVersion
                collection.reloadData()
            } else if pane.gitStatusVersion != gitVersion {
                gitVersion = pane.gitStatusVersion
                refreshVisibleBadges()
            }
            syncSelection()
            if let target = pane.scrollTarget, let index = pane.index(of: target) {
                pane.scrollTarget = nil
                scrollTo(index)
            }
            beginRenameIfNeeded()
        }

        private func configure(_ layout: GridFlowLayout) {
            let size = iconSize
            switch style {
            case .icons:
                layout.scrollDirection = .vertical
                let width = max(size + 36, 90)
                layout.itemSize = NSSize(width: width, height: size + 46)
                layout.minimumInteritemSpacing = 8
                layout.minimumLineSpacing = 8
            case .compact:
                layout.scrollDirection = .horizontal
                layout.itemSize = NSSize(width: 230, height: size + 8)
                layout.minimumInteritemSpacing = 2
                layout.minimumLineSpacing = 12
            }
            layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
            layout.invalidateLayout()
        }

        private func syncSelection() {
            guard let collection else { return }
            let wanted = Set(pane.selection.compactMap { pane.index(of: $0) }.map { IndexPath(item: $0, section: 0) })
            if collection.selectionIndexPaths != wanted { collection.selectionIndexPaths = wanted }
        }

        private func scrollTo(_ index: Int) {
            collection?.scrollToItems(
                at: [IndexPath(item: index, section: 0)],
                scrollPosition: style == .icons ? .nearestHorizontalEdge : .nearestVerticalEdge)
        }

        private func beginRenameIfNeeded() {
            guard let url = pane.renamingURL else {
                renameInProgress = nil
                return
            }
            guard renameInProgress != url, let index = pane.index(of: url) else { return }
            scrollTo(index)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pane.renamingURL == url, self.renameInProgress != url,
                      let index = self.pane.index(of: url),
                      let cell = self.collection?.item(at: IndexPath(item: index, section: 0)) as? FileGridCell else { return }
                self.renameInProgress = url
                cell.beginRename { [weak self] newName in
                    guard let self else { return }
                    self.renameInProgress = nil
                    self.pane.renamingURL = nil
                    if let newName { Actions(window: self.window, pane: self.pane).commitRename(url, to: newName) }
                    self.collection?.window?.makeFirstResponder(self.collection)
                }
            }
        }

        private func refreshVisibleBadges() {
            guard let collection else { return }
            for indexPath in collection.indexPathsForVisibleItems() {
                guard indexPath.item < items.count, let cell = collection.item(at: indexPath) as? FileGridCell else { continue }
                cell.setBadge(badge(for: items[indexPath.item]))
            }
        }

        func badge(for item: FileItem) -> GridBadge? {
            pane.badge(for: item.url)
        }

        // MARK: Data source

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let cell = collectionView.makeItem(withIdentifier: FileGridCell.identifier, for: indexPath) as! FileGridCell
            let item = items[indexPath.item]
            cell.configure(item, iconSize: iconSize, horizontal: style == .compact, badge: badge(for: item))
            return cell
        }

        // MARK: Selection

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            selectionChanged()
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            selectionChanged()
        }

        private func selectionChanged() {
            guard let collection else { return }
            let urls = collection.selectionIndexPaths.compactMap { $0.item < items.count ? items[$0.item].url : nil }
            pane.selection = Set(urls)
            if let last = collection.selectionIndexPaths.max().map({ items[$0.item].url }) { pane.selectionAnchor = last }
            if pane.quickLookURL != nil, let first = pane.selectedItems.first { pane.quickLookURL = first.url }
        }

        // MARK: Mouse and keyboard

        func activatePane() {
            if let index = window.activeTab.panes.firstIndex(where: { $0 === pane }) {
                window.activeTab.activePaneIndex = index
            }
        }

        func open(at indexPath: IndexPath) {
            guard indexPath.item < items.count else { return }
            pane.open(items[indexPath.item])
        }

        func prepareContextMenu(at point: NSPoint) {
            guard let collection else { return }
            activatePane()
            if let indexPath = collection.indexPathForItem(at: point) {
                if !collection.selectionIndexPaths.contains(indexPath) {
                    collection.selectionIndexPaths = [indexPath]
                    selectionChanged()
                }
            } else {
                collection.selectionIndexPaths = []
                selectionChanged()
            }
        }

        func handleKey(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch event.keyCode {
            case 36, 76:
                pane.openSelection()
                return true
            case 49 where pane.quickLookURL != nil || modifiers.isEmpty:
                pane.toggleQuickLook()
                return true
            case 53:
                pane.selection = []
                pane.quickLookURL = nil
                return true
            case 51 where modifiers.isEmpty:
                pane.goBack()
                return true
            default:
                break
            }
            guard modifiers.isDisjoint(with: [.command, .control, .function]),
                  let characters = event.characters, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return false }
            pane.typeAhead(characters)
            return true
        }

        // MARK: Drag and drop

        func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
            pane.renamingURL == nil
        }

        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            items[indexPath.item].url as NSURL
        }

        func collectionView(
            _ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo,
            proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
        ) -> NSDragOperation {
            let index = proposedDropIndexPath.pointee.item
            let sources = draggedURLs(draggingInfo)
            if proposedDropOperation.pointee == .on, index < items.count, items[index].opensAsFolder,
               !sources.contains(items[index].url) {
                dropTarget = items[index].url
            } else {
                dropTarget = pane.url
                proposedDropOperation.pointee = .before
            }
            guard let target = dropTarget, !sources.isEmpty else { return [] }
            let copy = NSEvent.modifierFlags.contains(.option)
            if !copy, sources.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL == target.standardizedFileURL }) {
                return []
            }
            return copy || draggingInfo.draggingSourceOperationMask == .copy ? .copy : .move
        }

        func collectionView(
            _ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo,
            indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation
        ) -> Bool {
            guard let target = dropTarget else { return false }
            return Actions(window: window, pane: pane).drop(draggedURLs(draggingInfo), into: target)
        }

        private func draggedURLs(_ info: NSDraggingInfo) -> [URL] {
            info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        }
    }
}

final class FileCollection: NSCollectionView {
    weak var coordinator: FileCollectionView.Coordinator?

    override func mouseDown(with event: NSEvent) {
        coordinator?.activatePane()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
        if event.clickCount == 2, let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil)) {
            coordinator?.open(at: indexPath)
        }
    }

    override func keyDown(with event: NSEvent) {
        if coordinator?.handleKey(event) != true { super.keyDown(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        coordinator?.prepareContextMenu(at: convert(event.locationInWindow, from: nil))
        return nil
    }
}

final class GridFlowLayout: NSCollectionViewFlowLayout {
    override func layoutAttributesForInterItemGap(before indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? { nil }
}

final class FileGridCell: NSCollectionViewItem, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("FileGridCell")

    private let highlight = NSView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let badgeView = NSImageView()
    private var horizontal = false
    private var iconSize: CGFloat = 64
    private var fileURL: URL?
    private var thumbnailTask: Task<Void, Never>?
    private var renameCompletion: ((String?) -> Void)?
    private var originalName = ""

    override func loadView() {
        let root = FlippedView()
        root.wantsLayer = true
        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 6
        highlight.layer?.borderWidth = 1
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.delegate = self
        label.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small) + 1)
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.truncatesLastVisibleLine = true
        badgeView.imageScaling = .scaleProportionallyUpOrDown
        for subview in [highlight, icon, label, badgeView] { root.addSubview(subview) }
        view = root
    }

    func configure(_ item: FileItem, iconSize: CGFloat, horizontal: Bool, badge: GridBadge?) {
        self.horizontal = horizontal
        self.iconSize = iconSize
        fileURL = item.url
        originalName = item.name
        label.stringValue = item.name
        label.toolTip = item.name
        label.alignment = horizontal ? .natural : .center
        label.maximumNumberOfLines = horizontal ? 1 : 2
        label.lineBreakMode = horizontal ? .byTruncatingMiddle : .byWordWrapping
        view.alphaValue = item.isHidden ? 0.55 : 1
        setBadge(badge)
        loadIcon(for: item.url)
        updateAppearance()
        view.needsLayout = true
    }

    func setBadge(_ badge: GridBadge?) {
        badgeView.isHidden = badge == nil
        guard let badge else { return }
        let configuration = NSImage.SymbolConfiguration(paletteColors: [.white, badge.color])
        badgeView.image = NSImage(systemSymbolName: badge.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private func loadIcon(for url: URL) {
        thumbnailTask?.cancel()
        let bucket = Thumbnails.bucket(for: iconSize)
        icon.image = Thumbnails.cached(url, bucket: bucket) ?? IconCache.icon(for: url)
        guard !horizontal, iconSize >= 48, Thumbnails.cached(url, bucket: bucket) == nil else { return }
        thumbnailTask = Task { [weak self] in
            guard let image = await Thumbnails.load(url, bucket: bucket), !Task.isCancelled,
                  let self, self.fileURL == url else { return }
            self.icon.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailTask?.cancel()
        endRename(commit: false)
    }

    override var isSelected: Bool { didSet { updateAppearance() } }
    override var highlightState: NSCollectionViewItem.HighlightState { didSet { updateAppearance() } }

    private func updateAppearance() {
        let accent = NSColor.controlAccentColor
        let active = isSelected || highlightState == .forSelection
        let dropTarget = highlightState == .asDropTarget
        highlight.layer?.backgroundColor = (active ? accent.withAlphaComponent(0.25)
            : dropTarget ? accent.withAlphaComponent(0.15) : .clear).cgColor
        highlight.layer?.borderColor = (active || dropTarget ? accent.withAlphaComponent(0.6) : .clear).cgColor
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let bounds = view.bounds
        highlight.frame = bounds
        let badgeSize = max(12, min(22, iconSize * 0.35))
        if horizontal {
            icon.frame = NSRect(x: 4, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
            let labelHeight = label.intrinsicContentSize.height
            label.frame = NSRect(x: iconSize + 10, y: (bounds.height - labelHeight) / 2,
                                 width: bounds.width - iconSize - 14, height: labelHeight)
        } else {
            icon.frame = NSRect(x: (bounds.width - iconSize) / 2, y: 4, width: iconSize, height: iconSize)
            label.frame = NSRect(x: 3, y: iconSize + 8, width: bounds.width - 6, height: bounds.height - iconSize - 10)
        }
        badgeView.frame = NSRect(x: icon.frame.maxX - badgeSize * 0.8, y: icon.frame.maxY - badgeSize * 0.9,
                                 width: badgeSize, height: badgeSize)
    }

    // MARK: Inline rename

    func beginRename(completion: @escaping (String?) -> Void) {
        renameCompletion = completion
        label.isEditable = true
        label.isSelectable = true
        label.isBezeled = true
        label.drawsBackground = true
        label.backgroundColor = .textBackgroundColor
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        label.cell?.isScrollable = true
        guard view.window?.makeFirstResponder(label) == true else { return }
        let isFolder = (try? fileURL?.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let length = isFolder == true ? originalName.utf16.count : (originalName as NSString).deletingPathExtension.utf16.count
        label.currentEditor()?.selectedRange = NSRange(location: 0, length: length)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            endRename(commit: false)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            endRename(commit: true)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        endRename(commit: true)
    }

    private func endRename(commit: Bool) {
        guard let completion = renameCompletion else { return }
        renameCompletion = nil
        let newName = label.stringValue
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.stringValue = originalName
        label.maximumNumberOfLines = horizontal ? 1 : 2
        label.lineBreakMode = horizontal ? .byTruncatingMiddle : .byWordWrapping
        DispatchQueue.main.async { completion(commit ? newName : nil) }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
