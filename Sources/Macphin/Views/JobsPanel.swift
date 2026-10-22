import SwiftUI

struct JobsPanel: View {
    private var center: JobCenter { .shared }

    var body: some View {
        let jobs = center.visibleJobs
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(jobs) { JobRow(job: $0) }
            }
            .padding(12)
            .frame(width: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            .shadow(radius: 8, y: 2)
            .padding(.trailing, 16)
            .padding(.bottom, 36)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct JobRow: View {
    let job: Job

    var body: some View {
        let snapshot = job.snapshot
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.title).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { job.cancel() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(job.isCancelling)
                    .help("Cancel")
            }
            ProgressView(value: snapshot.fraction)
            HStack {
                Text(job.isCancelling ? "Cancelling…" : snapshot.currentName)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                if snapshot.total > 0 {
                    Text(detail(snapshot)).monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func detail(_ snapshot: OperationProgress.Snapshot) -> String {
        let format = ByteCountFormatter()
        format.countStyle = .file
        guard snapshot.total > 1000 else { return "\(snapshot.completed) of \(snapshot.total)" }
        var text = "\(format.string(fromByteCount: snapshot.completed)) of \(format.string(fromByteCount: snapshot.total))"
        let elapsed = Date().timeIntervalSince(job.started)
        if snapshot.completed > 0, elapsed > 2 {
            let remaining = elapsed / Double(snapshot.completed) * Double(snapshot.total - snapshot.completed)
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.maximumUnitCount = 1
            if let eta = formatter.string(from: remaining) { text += " · \(eta) left" }
        }
        return text
    }
}
