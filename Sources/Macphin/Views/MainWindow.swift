import AppKit
import SwiftUI

struct MainWindow: View {
    @State private var window = WindowState()
    @State private var searchText = ""
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        layout
            .navigationTitle(window.activePane.title)
            .navigationSubtitle(window.activePane.isSearching ? "Search" : "")
            .toolbar { toolbar }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
            .onSubmit(of: .search) { window.activePane.startSearch(searchText) }
            .onChange(of: searchText) { if searchText.isEmpty { window.activePane.endSearch() } }
            .onChange(of: window.activePane.isSearching) { if !window.activePane.isSearching { searchText = "" } }
            .focusedSceneValue(\.windowState, window)
            .modifier(WindowDialogs(window: window))
            .overlay(alignment: .bottom) { connectingBadge }
            .overlay(alignment: .bottomTrailing) { JobsPanel().animation(.default, value: JobCenter.shared.visibleJobs.count) }
            .onAppear(perform: attachSession)
            .onDisappear { SessionStore.shared.unregister(window) }
            .onChange(of: scenePhase) { if scenePhase != .active { SessionStore.shared.saveAll() } }
            .frame(minWidth: 700, minHeight: 420)
    }

    private var layout: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { window.showPlaces ? .all : .detailOnly },
            set: { window.showPlaces = $0 != .detailOnly })
        ) {
            PlacesSidebar(window: window)
                .navigationSplitViewColumnWidth(min: 150, ideal: 190, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if window.tabs.count > 1 {
                    TabBar(window: window)
                    Divider()
                }
                VSplitView {
                    panes.frame(minHeight: 200)
                    if window.showTerminal {
                        TerminalPanel(pane: window.activePane)
                            .frame(minHeight: 80, idealHeight: 220)
                    }
                }
            }
            .inspector(isPresented: Binding(get: { window.showInfo }, set: { window.showInfo = $0 })) {
                InfoPanel(pane: window.activePane)
                    .inspectorColumnWidth(min: 220, ideal: 260, max: 400)
            }
        }
    }

    private var panes: some View {
        SplitPanes(tab: window.activeTab, window: window).id(window.activeTab.id)
    }

    @ViewBuilder private var connectingBadge: some View {
        if let host = window.connectingTo {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting to \(host)…")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 36)
        }
    }

    private func attachSession() {
        let sessions = SessionStore.shared
        if let tab = sessions.claimDetachedTab() {
            window.adopt(tab)
        } else if let session = sessions.claim() {
            window.restore(session)
        }
        sessions.register(window)
        if sessions.hasPending { openWindow(id: "main") }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        let pane = window.activePane
        ToolbarItemGroup(placement: .navigation) {
            Button { pane.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                .disabled(!pane.canGoBack).help("Back")
            Button { pane.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                .disabled(!pane.canGoForward).help("Forward")
            Button { pane.goUp() } label: { Label("Up", systemImage: "arrow.up") }
                .disabled(!pane.canGoUp).help("Parent Folder")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("View", selection: Binding(get: { pane.viewMode }, set: { pane.viewMode = $0 })) {
                ForEach(ViewMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .help("View Mode")
            Menu {
                Picker("Sort By", selection: Binding(get: { pane.sortKey }, set: { pane.sortKey = $0 })) {
                    ForEach(SortKey.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Toggle("Descending", isOn: Binding(get: { !pane.sortAscending }, set: { pane.sortAscending = !$0 }))
                Toggle("Folders First", isOn: Binding(get: { pane.foldersFirst }, set: { pane.foldersFirst = $0 }))
                Divider()
                Toggle("Show Hidden Files", isOn: Binding(get: { pane.showHidden }, set: { pane.showHidden = $0 }))
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort & Display")
            Button { window.activeTab.toggleSplit() } label: {
                Label("Split", systemImage: window.activeTab.isSplit ? "rectangle" : "rectangle.split.2x1")
            }
            .help(window.activeTab.isSplit ? "Close Split View (F3)" : "Split View (F3)")
            Button { window.showTerminal.toggle() } label: { Label("Terminal", systemImage: "terminal") }
                .help("Terminal Panel (F4)")
            Button { window.showInfo.toggle() } label: { Label("Info", systemImage: "info.circle") }
                .help("Information Panel (F11)")
        }
    }
}

private struct WindowDialogs: ViewModifier {
    let window: WindowState

    private var deletePrompt: String {
        let urls = window.pendingDelete
        let subject = urls.count == 1 ? "“\(urls[0].lastPathComponent)”" : "\(urls.count) items"
        return "Permanently delete \(subject)?"
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(deletePrompt, isPresented: Binding(
                get: { !window.pendingDelete.isEmpty },
                set: { if !$0 { window.pendingDelete = [] } })
            ) {
                Button("Delete", role: .destructive) {
                    let urls = window.pendingDelete
                    window.pendingDelete = []
                    window.perform("Delete", title: "Deleting \(urls.count) item\(urls.count == 1 ? "" : "s")") { _, progress in
                        try FileOperations.deletePermanently(urls, progress: progress)
                    }
                }
            } message: {
                Text("This cannot be undone.")
            }
            .sheet(item: Binding(get: { window.pendingConflict }, set: { window.pendingConflict = $0 })) { request in
                ConflictSheet(request: request) { window.pendingConflict = nil }
            }
            .sheet(isPresented: Binding(get: { window.showConnectSheet }, set: { window.showConnectSheet = $0 })) {
                ConnectServerSheet(window: window)
            }
            .alert("Error", isPresented: Binding(
                get: { window.errorMessage != nil },
                set: { if !$0 { window.errorMessage = nil } })
            ) {
                Button("OK") { window.errorMessage = nil }
            } message: {
                Text(window.errorMessage ?? "")
            }
    }
}

struct WindowStateKey: FocusedValueKey {
    typealias Value = WindowState
}

extension FocusedValues {
    var windowState: WindowState? {
        get { self[WindowStateKey.self] }
        set { self[WindowStateKey.self] = newValue }
    }
}
