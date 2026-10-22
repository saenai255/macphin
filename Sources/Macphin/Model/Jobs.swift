import Foundation
import Observation

@MainActor
@Observable
final class Job: Identifiable {
    let id = UUID()
    let title: String
    let progress = OperationProgress()
    let started = Date()
    private(set) var snapshot = OperationProgress.Snapshot(completed: 0, total: 0, currentName: "")
    private(set) var isCancelling = false

    init(title: String) { self.title = title }

    func refresh() { snapshot = progress.snapshot }

    func cancel() {
        isCancelling = true
        progress.cancel()
    }
}

@MainActor
@Observable
final class JobCenter {
    static let shared = JobCenter()

    private(set) var jobs: [Job] = []
    @ObservationIgnored private var timer: Timer?

    // Short operations finish before this and never flash a progress row.
    var visibleJobs: [Job] { jobs.filter { Date().timeIntervalSince($0.started) > 0.4 } }

    func start(_ title: String) -> Job {
        let job = Job(title: title)
        jobs.append(job)
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                MainActor.assumeIsolated { JobCenter.shared.tick() }
            }
        }
        return job
    }

    func finish(_ job: Job) {
        jobs.removeAll { $0 === job }
        if jobs.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    private func tick() {
        jobs.forEach { $0.refresh() }
    }
}
