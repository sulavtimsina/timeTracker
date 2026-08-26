import Foundation

struct Turn: Identifiable, Codable, Equatable {
    let id: UUID
    var accumulatedSeconds: TimeInterval
    var isClosed: Bool
    let createdAt: Date

    init(id: UUID = UUID(), accumulatedSeconds: TimeInterval = 0, isClosed: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.accumulatedSeconds = accumulatedSeconds
        self.isClosed = isClosed
        self.createdAt = createdAt
    }
}

struct TrackedTask: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var turns: [Turn]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, turns: [Turn] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.turns = turns
        self.createdAt = createdAt
    }

    var totalSeconds: TimeInterval {
        turns.reduce(0) { $0 + $1.accumulatedSeconds }
    }
}

struct RunningRef: Codable, Equatable {
    let taskId: UUID
    let turnId: UUID
    var startedAt: Date
}

struct AppState: Codable, Equatable {
    var tasks: [TrackedTask]
    var running: RunningRef?
    /// Set when the app auto-paused due to sleep/quit so we can auto-resume on wake/relaunch.
    var pendingResume: RunningRef?

    static let empty = AppState(tasks: [], running: nil, pendingResume: nil)
}
