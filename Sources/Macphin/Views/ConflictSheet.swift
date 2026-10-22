import SwiftUI

struct ConflictSheet: View {
    let request: ConflictRequest
    let dismiss: () -> Void

    private var title: String {
        let place = FileManager.default.displayName(atPath: request.destination.path)
        return request.conflicts.count == 1
            ? "“\(request.conflicts[0].lastPathComponent)” already exists in “\(place)”"
            : "\(request.conflicts.count) items already exist in “\(place)”"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text("Choose what to do with the items being \(request.isMove ? "moved" : "copied"). Replaced items go to the Trash.")
                .foregroundStyle(.secondary)
            List(request.conflicts, id: \.self) { source in
                ConflictRow(incoming: FileItem(url: source),
                            existing: FileItem(url: request.destination.appending(path: source.lastPathComponent)))
            }
            .frame(height: min(CGFloat(request.conflicts.count) * 64 + 12, 300))
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Skip") { choose(.skip) }
                Button("Replace") { choose(.replace) }
                Button("Keep Both") { choose(.keepBoth) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func choose(_ policy: ConflictPolicy) {
        dismiss()
        request.resolve(policy)
    }
}

private struct ConflictRow: View {
    let incoming: FileItem
    let existing: FileItem

    var body: some View {
        HStack(spacing: 10) {
            FileIcon(url: existing.url, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(incoming.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                detail("Existing", existing, isNewer: existing.modified > incoming.modified)
                detail("Incoming", incoming, isNewer: incoming.modified > existing.modified)
            }
        }
        .padding(.vertical, 2)
    }

    private func detail(_ label: String, _ item: FileItem, isNewer: Bool) -> some View {
        HStack(spacing: 4) {
            Text("\(label):").foregroundStyle(.secondary)
            Text(item.formattedSize)
            Text("·").foregroundStyle(.secondary)
            Text(item.modified.formatted(date: .abbreviated, time: .shortened))
            if isNewer { Text("newer").foregroundStyle(.tint) }
        }
        .font(.caption)
    }
}
