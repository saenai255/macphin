import AppKit
import Observation

@MainActor
@Observable
final class PaneState: Identifiable {
    let id = UUID()
    private(set) var url: URL
    private(set) var items: [FileItem] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    var selection: Set<URL> = []
    var viewMode: ViewMode { didSet { Settings.viewMode = viewMode } }
    var sortKey: SortKey = .name { didSet { resort() } }
    var sortAscending = true { didSet { resort() } }
    var foldersFirst = true { didSet { resort() } }
    var showHidden: Bool { didSet { Settings.showHidden = showHidden; reload() } }
    var zoom: Double { didSet { Settings.zoom = zoom } }
    var filterText = ""
    var isFilterBarVisible = false
    var isEditingLocation = false
    var quickLookURL: URL?
    var selectionAnchor: URL?
    var renamingURL: URL?
    var scrollTarget: URL?

    let search = SearchController()
    var isSearching = false

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var watcher: DirectoryWatcher?
    private var allItems: [FileItem] = []
    private var loadGeneration = 0

    init(url: URL, viewMode: ViewMode? = nil) {
        self.url = url
        self.viewMode = viewMode ?? Settings.viewMode
        showHidden = Settings.showHidden
        zoom = Settings.zoom
        search.onResults = { [weak self] in self?.applySearchResults($0) }
        load()
    }

    var title: String { FileManager.default.displayName(atPath: url.path) }
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { url.path != "/" }

    var visibleItems: [FileItem] {
        guard !filterText.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(filterText) }
    }

    var selectedItems: [FileItem] { visibleItems.filter { selection.contains($0.url) } }

    func navigate(to newURL: URL, recordHistory: Bool = true) {
        let target = newURL.standardizedFileURL
        guard target != url else { return }
        if recordHistory {
            backStack.append(url)
            forwardStack.removeAll()
        }
        url = target
        endSearch()
        filterText = ""
        selection = []
        renamingURL = nil
        load()
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(url)
        navigate(to: previous, recordHistory: false)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(url)
        navigate(to: next, recordHistory: false)
    }

    func goUp() {
        let child = url
        navigate(to: url.deletingLastPathComponent())
        selection = [child]
    }

    func open(_ item: FileItem) {
        if item.opensAsFolder {
            navigate(to: item.isSymlink ? item.url.resolvingSymlinksInPath() : item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func openSelection() {
        let selected = selectedItems
        if selected.count == 1 { open(selected[0]); return }
        selected.filter { !$0.opensAsFolder }.forEach { NSWorkspace.shared.open($0.url) }
    }

    func reload() {
        if isSearching { return }
        load()
    }

    func selectAll() { selection = Set(visibleItems.map(\.url)) }

    func toggleQuickLook() {
        quickLookURL = quickLookURL == nil ? selectedItems.first?.url : nil
    }

    func startSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { endSearch(); return }
        isSearching = true
        selection = []
        search.start(query: trimmed, scope: url)
    }

    func endSearch() {
        guard isSearching else { return }
        search.stop()
        isSearching = false
        load()
    }

    private func applySearchResults(_ urls: [URL]) {
        guard isSearching else { return }
        allItems = urls.map(FileItem.init(url:))
        resort()
    }

    private func load() {
        loadGeneration += 1
        let generation = loadGeneration
        let target = url
        let includeHidden = showHidden
        isLoading = true
        loadError = nil
        watcher = DirectoryWatcher(url: target) { [weak self] in self?.reload() }

        Task.detached(priority: .userInitiated) {
            let result: Result<[FileItem], Error>
            do {
                let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
                let urls = try FileManager.default.contentsOfDirectory(
                    at: target, includingPropertiesForKeys: FileItem.resourceKeys, options: options)
                result = .success(urls.map(FileItem.init(url:)))
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in
                guard let self, generation == self.loadGeneration else { return }
                self.isLoading = false
                switch result {
                case .success(let loaded):
                    self.allItems = loaded
                    self.resort()
                    self.selection = self.selection.intersection(loaded.map(\.url))
                case .failure(let error):
                    self.allItems = []
                    self.items = []
                    self.loadError = error.localizedDescription
                }
            }
        }
    }

    private func resort() {
        let key = sortKey, ascending = sortAscending, folders = foldersFirst
        items = allItems.sorted { a, b in
            if folders, a.opensAsFolder != b.opensAsFolder { return a.opensAsFolder }
            let ordered: Bool
            switch key {
            case .name: ordered = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .size: ordered = a.sizeForSort == b.sizeForSort
                ? a.name.localizedStandardCompare(b.name) == .orderedAscending
                : a.sizeForSort < b.sizeForSort
            case .modified: ordered = a.modified < b.modified
            case .kind: ordered = a.kind == b.kind
                ? a.name.localizedStandardCompare(b.name) == .orderedAscending
                : a.kind.localizedStandardCompare(b.kind) == .orderedAscending
            }
            return ascending ? ordered : !ordered
        }
    }
}

final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { source = nil; return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { onChange() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    deinit { source?.cancel() }
}

@MainActor
@Observable
final class SearchController: NSObject {
    private(set) var isGathering = false
    @ObservationIgnored var onResults: (([URL]) -> Void)?
    @ObservationIgnored private var query: NSMetadataQuery?

    func start(query text: String, scope: URL) {
        stop()
        let query = NSMetadataQuery()
        query.searchScopes = [scope]
        query.predicate = NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\(text)*")
        NotificationCenter.default.addObserver(
            self, selector: #selector(update), name: .NSMetadataQueryDidUpdate, object: query)
        NotificationCenter.default.addObserver(
            self, selector: #selector(update), name: .NSMetadataQueryDidFinishGathering, object: query)
        self.query = query
        isGathering = true
        query.start()
    }

    func stop() {
        guard let query else { return }
        query.stop()
        isGathering = false
        NotificationCenter.default.removeObserver(self, name: nil, object: query)
        self.query = nil
    }

    @objc private func update() {
        guard let query else { return }
        query.disableUpdates()
        let urls = (0..<min(query.resultCount, 2000)).compactMap { index -> URL? in
            guard let path = (query.result(at: index) as? NSMetadataItem)?
                .value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            return URL(fileURLWithPath: path)
        }
        query.enableUpdates()
        isGathering = query.isGathering
        onResults?(urls)
    }
}

extension PaneState {
    func click(_ item: FileItem, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
            selectionAnchor = item.url
        } else if modifiers.contains(.shift), let anchor = selectionAnchor,
                  let start = visibleItems.firstIndex(where: { $0.url == anchor }),
                  let end = visibleItems.firstIndex(where: { $0.url == item.url }) {
            selection = Set(visibleItems[min(start, end)...max(start, end)].map(\.url))
        } else {
            selection = [item.url]
            selectionAnchor = item.url
        }
    }

    func moveSelection(by offset: Int, extend: Bool = false) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        let current = items.lastIndex(where: { selection.contains($0.url) })
        let next = current.map { max(0, min(items.count - 1, $0 + offset)) } ?? 0
        let url = items[next].url
        if extend { selection.insert(url) } else { selection = [url] }
        selectionAnchor = url
        if quickLookURL != nil { quickLookURL = url }
    }
}
