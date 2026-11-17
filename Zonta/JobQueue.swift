import Foundation

enum JobLane: String, CaseIterable {
    /// Globe hold → transcript → Hermes reply → speech job.
    case chat
    /// Right ⌘ / Right ⌥ hold → transcript → cleanup or translation → paste.
    /// Completely independent from `chat`, so dictation is never held up by a
    /// slow Hermes answer.
    case dictation
    /// TTS synthesis + playback. Its own lane so a long answer never blocks
    /// the next question either.
    case speech
}

enum JobKind: String {
    case transcribe, chat, dictate, translate, speech
}

enum JobState: String {
    case queued, running, succeeded, failed, cancelled
}

struct JobRecord: Identifiable {
    let id: UUID
    let lane: JobLane
    let kind: JobKind
    let title: String
    let enqueuedAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var state: JobState = .queued
    var error: String?

    var duration: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    var statusText: String {
        switch state {
        case .queued: return "Queued"
        case .running:
            if let startedAt {
                return "Running \(Int(Date().timeIntervalSince(startedAt)))s"
            }
            return "Running"
        case .succeeded:
            if let duration { return "Done in \(String(format: "%.1f", duration))s" }
            return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

/// Serial, observable job lanes. Work is enqueued from anywhere and each lane
/// drains independently; failures are isolated and reported to `AppLog` and
/// to `onError`, never thrown back into the caller.
@MainActor
final class JobQueue: ObservableObject {
    static let shared = JobQueue()

    /// Newest first, so the debug view needs no sorting.
    @Published private(set) var jobs: [JobRecord] = []
    @Published private(set) var activeCount = 0

    /// Fired whenever job state changes, so the UI can derive its phase
    /// without jobs overwriting a recording that is already in progress.
    var onStateChange: (() -> Void)?
    /// Called for every failed job with (title, message).
    var onError: ((String, String) -> Void)?

    /// Currently executing jobs, newest first. Used to pick the menu-bar phase.
    var runningJobs: [JobRecord] { jobs.filter { $0.state == .running } }

    private struct Pending {
        let record: JobRecord
        let work: () async throws -> Void
    }

    private final class Lane {
        var pending: [Pending] = []
        var isDraining = false
        var current: Task<Void, Never>?
        var watchdog: Task<Void, Never>?
    }

    private var lanes: [JobLane: Lane] = Dictionary(
        uniqueKeysWithValues: JobLane.allCases.map { ($0, Lane()) }
    )

    /// Hermes can hold a chat request for minutes. A watchdog keeps a visible
    /// trail so a long wait is distinguishable from a hung app.
    private static let slowJobThreshold: TimeInterval = 25

    // MARK: - Enqueue

    @discardableResult
    func enqueue(
        lane: JobLane,
        kind: JobKind,
        title: String,
        work: @escaping () async throws -> Void
    ) -> UUID {
        let record = JobRecord(
            id: UUID(), lane: lane, kind: kind, title: title, enqueuedAt: Date()
        )
        jobs.insert(record, at: 0)
        onStateChange?()
        lanes[lane]!.pending.append(Pending(record: record, work: work))
        AppLog.shared.debug("Queued \(kind.rawValue): \(title)", subsystem: lane.rawValue.capitalized)
        drain(lane: lane)
        return record.id
    }

    // MARK: - Cancellation

    func hasActive(_ lane: JobLane) -> Bool {
        guard let lane = lanes[lane] else { return false }
        return lane.isDraining || !lane.pending.isEmpty
    }

    func cancel(lane: JobLane) {
        guard let state = lanes[lane] else { return }
        let queued = state.pending.count
        for pending in state.pending {
            update(pending.record.id) { $0.state = .cancelled; $0.finishedAt = Date() }
        }
        state.pending.removeAll()
        if queued > 0 || state.isDraining {
            AppLog.shared.warning(
                "Cancelled \(queued) queued job(s) and the running job on \(lane.rawValue)",
                subsystem: "Queue"
            )
        }
        state.current?.cancel()
        state.watchdog?.cancel()
    }

    func cancelAll() {
        for lane in JobLane.allCases { cancel(lane: lane) }
    }

    // MARK: - Draining

    private func drain(lane: JobLane) {
        guard let laneState = lanes[lane],
              !laneState.isDraining,
              !laneState.pending.isEmpty
        else { return }

        laneState.isDraining = true
        let next = laneState.pending.removeFirst()
        update(next.record.id) { $0.state = .running; $0.startedAt = Date() }
        activeCount += 1
        AppLog.shared.info("Started: \(next.record.title)", subsystem: lane.rawValue.capitalized)
        startWatchdog(for: next.record, lane: laneState)

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await next.work()
                self.update(next.record.id) { $0.state = .succeeded }
                AppLog.shared.info("Finished: \(next.record.title)", subsystem: lane.rawValue.capitalized)
            } catch is CancellationError {
                self.update(next.record.id) { $0.state = .cancelled }
                AppLog.shared.warning("Cancelled: \(next.record.title)", subsystem: lane.rawValue.capitalized)
            } catch {
                self.update(next.record.id) { $0.state = .failed; $0.error = error.localizedDescription }
                AppLog.shared.error(
                    "\(next.record.title) failed: \(error.localizedDescription)",
                    subsystem: lane.rawValue.capitalized
                )
                self.onError?(next.record.title, error.localizedDescription)
            }
            self.update(next.record.id) { $0.finishedAt = Date() }
            laneState.watchdog?.cancel()
            laneState.watchdog = nil
            laneState.isDraining = false
            laneState.current = nil
            self.activeCount -= 1

            self.drain(lane: lane)
        }
        laneState.current = task
    }

    private func startWatchdog(for record: JobRecord, lane: Lane) {
        guard record.kind == .chat || record.kind == .transcribe else { return }
        lane.watchdog = Task { @MainActor in
            var waited = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.slowJobThreshold))
                guard !Task.isCancelled else { return }
                waited += Int(Self.slowJobThreshold)
                AppLog.shared.warning(
                    "Still waiting after \(waited)s: \(record.title)",
                    subsystem: "Watchdog"
                )
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout JobRecord) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
        onStateChange?()
    }
}
