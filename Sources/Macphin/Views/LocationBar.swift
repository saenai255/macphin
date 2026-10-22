import AppKit
import SwiftUI

struct LocationBar: View {
    let pane: PaneState
    let window: WindowState

    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            if pane.isEditingLocation {
                TextField("Location", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    .onExitCommand { pane.isEditingLocation = false }
                    .onAppear {
                        text = pane.url.path
                        fieldFocused = true
                    }
                    .onChange(of: fieldFocused) { if !fieldFocused { pane.isEditingLocation = false } }
            } else {
                breadcrumbs
                Color.clear
                    .contentShape(Rectangle())
                    .frame(minWidth: 20, maxWidth: .infinity)
                    .onTapGesture { pane.isEditingLocation = true }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.bar)
    }

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    BreadcrumbButton(segment: segment, isCurrent: index == segments.count - 1, pane: pane, window: window)
                    SubfolderMenu(url: segment.url, pane: pane)
                }
            }
        }
        .defaultScrollAnchor(.trailing)
    }

    private var segments: [Segment] {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let current = pane.url.standardizedFileURL
        var result: [Segment] = []
        var url = current
        while true {
            if url.path == home.path {
                result.append(Segment(url: url, title: "Home", symbol: "house"))
                break
            }
            if url.path == "/" {
                result.append(Segment(url: url, title: "/", symbol: "internaldrive"))
                break
            }
            if url.deletingLastPathComponent().path == "/Volumes" {
                result.append(Segment(url: url, title: url.lastPathComponent, symbol: "externaldrive"))
                break
            }
            result.append(Segment(url: url, title: FileManager.default.displayName(atPath: url.path), symbol: nil))
            url = url.deletingLastPathComponent()
        }
        return result.reversed()
    }

    private func commit() {
        if let remote = RemoteMounter.parse(text) {
            pane.isEditingLocation = false
            window.connect(to: remote, in: pane)
            return
        }
        let expanded = (text.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : pane.url.appending(path: expanded)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue { pane.navigate(to: url) } else { NSWorkspace.shared.open(url) }
            pane.isEditingLocation = false
        } else {
            NSSound.beep()
        }
    }
}

struct Segment {
    let url: URL
    let title: String
    let symbol: String?
}

private struct BreadcrumbButton: View {
    let segment: Segment
    let isCurrent: Bool
    let pane: PaneState
    let window: WindowState

    @State private var isTargeted = false

    var body: some View {
        Button { pane.navigate(to: segment.url) } label: {
            HStack(spacing: 4) {
                if let symbol = segment.symbol { Image(systemName: symbol) }
                Text(segment.title).fontWeight(isCurrent ? .semibold : .regular)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(isTargeted ? Color.accentColor.opacity(0.25) : .clear))
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            Actions(window: window, pane: pane).drop(urls, into: segment.url)
        } isTargeted: { isTargeted = $0 }
    }
}

private struct SubfolderMenu: View {
    let url: URL
    let pane: PaneState

    var body: some View {
        Menu {
            let folders = subfolders
            if folders.isEmpty { Text("No subfolders") }
            ForEach(folders, id: \.self) { folder in
                Button(folder.lastPathComponent) { pane.navigate(to: folder) }
            }
        } label: {
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 2)
    }

    private var subfolders: [URL] {
        let options: FileManager.DirectoryEnumerationOptions = pane.showHidden ? [] : [.skipsHiddenFiles]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: options)) ?? []
        return urls
            .filter {
                let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                return values?.isDirectory == true && values?.isPackage != true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
