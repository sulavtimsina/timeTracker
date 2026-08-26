import Foundation

struct User: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// Removed from the picker but kept so historical sessions stay attributed.
    var isArchived: Bool
    let createdAt: Date

    init(id: UUID = UUID(), name: String, isArchived: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.isArchived = isArchived
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, name, isArchived, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

/// One uninterrupted stretch of work on a turn by one user.
struct WorkSession: Identifiable, Codable, Equatable {
    let id: UUID
    /// nil = recorded before users existed (legacy data).
    let userId: UUID?
    let start: Date
    var end: Date

    init(id: UUID = UUID(), userId: UUID?, start: Date, end: Date) {
        self.id = id
        self.userId = userId
        self.start = start
        self.end = end
    }

    var seconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

struct Turn: Identifiable, Codable, Equatable {
    let id: UUID
    var sessions: [WorkSession]
    var isClosed: Bool
    let createdAt: Date

    init(id: UUID = UUID(), sessions: [WorkSession] = [], isClosed: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.sessions = sessions
        self.isClosed = isClosed
        self.createdAt = createdAt
    }

    /// Committed (non-live) time on this turn — the sum of its sessions.
    var accumulatedSeconds: TimeInterval { sessions.reduce(0) { $0 + $1.seconds } }

    private enum CodingKeys: String, CodingKey { case id, sessions, isClosed, createdAt, accumulatedSeconds }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        isClosed = try c.decode(Bool.self, forKey: .isClosed)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        if let s = try c.decodeIfPresent([WorkSession].self, forKey: .sessions) {
            sessions = s
        } else {
            // Legacy file: a single accumulatedSeconds number. Preserve it as one unassigned session.
            let legacy = try c.decodeIfPresent(TimeInterval.self, forKey: .accumulatedSeconds) ?? 0
            sessions = legacy > 0
                ? [WorkSession(userId: nil, start: createdAt, end: createdAt.addingTimeInterval(legacy))]
                : []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sessions, forKey: .sessions)
        try c.encode(isClosed, forKey: .isClosed)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(accumulatedSeconds, forKey: .accumulatedSeconds) // informational; derived on decode
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
    /// Who is doing the work. nil only for data that predates users.
    var userId: UUID?
}

struct AppState: Codable, Equatable {
    var tasks: [TrackedTask]
    var users: [User]
    var activeUserId: UUID?
    var running: RunningRef?
    /// Set when the app auto-paused due to sleep/quit so we can auto-resume on wake/relaunch.
    var pendingResume: RunningRef?

    static let empty = AppState(tasks: [], users: [], activeUserId: nil, running: nil, pendingResume: nil)

    init(tasks: [TrackedTask], users: [User], activeUserId: UUID?, running: RunningRef?, pendingResume: RunningRef?) {
        self.tasks = tasks
        self.users = users
        self.activeUserId = activeUserId
        self.running = running
        self.pendingResume = pendingResume
    }

    private enum CodingKeys: String, CodingKey { case tasks, users, activeUserId, running, pendingResume }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try c.decodeIfPresent([TrackedTask].self, forKey: .tasks) ?? []
        users = try c.decodeIfPresent([User].self, forKey: .users) ?? []
        activeUserId = try c.decodeIfPresent(UUID.self, forKey: .activeUserId)
        running = try c.decodeIfPresent(RunningRef.self, forKey: .running)
        pendingResume = try c.decodeIfPresent(RunningRef.self, forKey: .pendingResume)
    }

    // MARK: - Lookups

    func user(id: UUID?) -> User? {
        guard let id else { return nil }
        return users.first { $0.id == id }
    }

    func userName(id: UUID?) -> String {
        guard let id else { return "Unassigned" }
        return users.first { $0.id == id }?.name ?? "Unknown user"
    }

    var activeUsers: [User] { users.filter { !$0.isArchived } }
}
