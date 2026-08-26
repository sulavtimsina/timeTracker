import Foundation
import Combine
import AppKit

@MainActor
final class TrackerStore: ObservableObject {
    @Published private(set) var state: AppState = .empty
    /// Ticks every second while a turn is running, to drive live UI updates.
    @Published private(set) var tick: Date = Date()

    private let storageURL: URL
    private var timerCancellable: AnyCancellable?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    init() {
        let fm = FileManager.default
        let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = (base ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("TimeTracker", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir.appendingPathComponent("state.json")

        load()
        // If a previous run left something running, auto-pause it (gap not counted) and mark for resume.
        if let running = state.running {
            var updated = running
            updated.startedAt = Date()
            // Fold any elapsed since startedAt into the turn — but since we don't know when the app died,
            // treat as clean auto-pause: don't count gap. Just remember it as pendingResume.
            state.running = nil
            state.pendingResume = updated
            save()
        }
        // Auto-resume anything that was pending from a prior sleep/quit.
        if let pending = state.pendingResume {
            resumePending(pending)
        }

        installLifecycleObservers()
        startTickTimer()
    }

    deinit {
        if let o = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let o = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        if let o = terminateObserver { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(AppState.self, from: data) {
            self.state = decoded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(state) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    // MARK: - Lifecycle observers

    private func installLifecycleObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver = ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.autoPauseForInterruption() }
        }
        wakeObserver = ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.autoResumeAfterInterruption() }
        }
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.autoPauseForInterruption() }
        }
    }

    private func autoPauseForInterruption() {
        guard let running = state.running else { return }
        commitElapsed(for: running)
        state.pendingResume = RunningRef(taskId: running.taskId, turnId: running.turnId, startedAt: Date())
        state.running = nil
        save()
    }

    private func autoResumeAfterInterruption() {
        guard let pending = state.pendingResume else { return }
        resumePending(pending)
    }

    private func resumePending(_ pending: RunningRef) {
        guard let (t, u) = locate(taskId: pending.taskId, turnId: pending.turnId), !state.tasks[t].turns[u].isClosed else {
            state.pendingResume = nil
            save()
            return
        }
        state.running = RunningRef(taskId: pending.taskId, turnId: pending.turnId, startedAt: Date())
        state.pendingResume = nil
        save()
    }

    // MARK: - Ticker

    private func startTickTimer() {
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.tick = date }
    }

    // MARK: - Queries

    func liveElapsed(for turn: Turn, in task: TrackedTask) -> TimeInterval {
        var total = turn.accumulatedSeconds
        if let r = state.running, r.taskId == task.id, r.turnId == turn.id {
            total += max(0, Date().timeIntervalSince(r.startedAt))
        }
        return total
    }

    func liveTotal(for task: TrackedTask) -> TimeInterval {
        task.turns.reduce(0) { $0 + liveElapsed(for: $1, in: task) }
    }

    func isRunning(taskId: UUID, turnId: UUID) -> Bool {
        state.running?.taskId == taskId && state.running?.turnId == turnId
    }

    var runningTask: TrackedTask? {
        guard let r = state.running else { return nil }
        return state.tasks.first { $0.id == r.taskId }
    }

    // MARK: - Mutations

    func addTask(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Task \(state.tasks.count + 1)" : trimmed
        state.tasks.append(TrackedTask(name: finalName))
        save()
    }

    func renameTask(taskId: UUID, to newName: String) {
        guard let i = state.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.tasks[i].name = trimmed
        save()
    }

    func deleteTask(taskId: UUID) {
        if state.running?.taskId == taskId { pauseRunning() }
        state.tasks.removeAll { $0.id == taskId }
        if state.pendingResume?.taskId == taskId { state.pendingResume = nil }
        save()
    }

    /// Start or resume a specific open turn. Auto-pauses whatever is currently running.
    func startOrResume(taskId: UUID, turnId: UUID) {
        guard let (t, u) = locate(taskId: taskId, turnId: turnId) else { return }
        guard !state.tasks[t].turns[u].isClosed else { return }
        if let running = state.running {
            if running.taskId == taskId && running.turnId == turnId { return } // already running
            commitElapsed(for: running)
        }
        state.running = RunningRef(taskId: taskId, turnId: turnId, startedAt: Date())
        state.pendingResume = nil
        save()
    }

    /// Create a fresh turn on this task and start it.
    func startNewTurn(taskId: UUID) {
        guard let t = state.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        if let running = state.running { commitElapsed(for: running) }
        let turn = Turn()
        state.tasks[t].turns.append(turn)
        state.running = RunningRef(taskId: taskId, turnId: turn.id, startedAt: Date())
        state.pendingResume = nil
        save()
    }

    /// Pause the currently running turn (keep it open — resumable).
    func pauseRunning() {
        guard let running = state.running else { return }
        commitElapsed(for: running)
        state.running = nil
        save()
    }

    /// Stop a specific turn — commit elapsed and close it so it can't be resumed.
    func stopTurn(taskId: UUID, turnId: UUID) {
        if let running = state.running, running.taskId == taskId, running.turnId == turnId {
            commitElapsed(for: running)
            state.running = nil
        }
        guard let (t, u) = locate(taskId: taskId, turnId: turnId) else { return }
        state.tasks[t].turns[u].isClosed = true
        save()
    }

    // MARK: - Helpers

    private func commitElapsed(for running: RunningRef) {
        guard let (t, u) = locate(taskId: running.taskId, turnId: running.turnId) else { return }
        let delta = max(0, Date().timeIntervalSince(running.startedAt))
        state.tasks[t].turns[u].accumulatedSeconds += delta
    }

    private func locate(taskId: UUID, turnId: UUID) -> (Int, Int)? {
        guard let t = state.tasks.firstIndex(where: { $0.id == taskId }) else { return nil }
        guard let u = state.tasks[t].turns.firstIndex(where: { $0.id == turnId }) else { return nil }
        return (t, u)
    }
}

// MARK: - Formatting

enum TimeFormat {
    static func hms(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        } else {
            return String(format: "%02d:%02d", m, sec)
        }
    }
}
