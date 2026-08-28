import Foundation
import AppKit

/// Builds a self-contained HTML time report from an AppState.
enum ReportBuilder {

    /// A flattened session row used for all aggregations.
    private struct Row {
        let userId: UUID?
        let userName: String
        let taskName: String
        let turnIndex: Int
        let start: Date
        let end: Date
        let isLive: Bool
        var seconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
    }

    static func html(state: AppState, now: Date = Date()) -> String {
        let rows = flatten(state, now: now).sorted { $0.start < $1.start }
        let grand = rows.reduce(0) { $0 + $1.seconds }

        // Users: everyone who has time, in the order they were created; Unassigned last.
        var userOrder: [UUID?] = state.users.map { $0.id }
        if rows.contains(where: { $0.userId == nil }) { userOrder.append(nil) }
        userOrder = userOrder.filter { uid in rows.contains { $0.userId == uid } }

        func total(_ f: (Row) -> Bool) -> TimeInterval { rows.filter(f).reduce(0) { $0 + $1.seconds } }

        // ---------- Summary by user ----------
        var byUser = ""
        for uid in userOrder {
            let mine = rows.filter { $0.userId == uid }
            let secs = mine.reduce(0) { $0 + $1.seconds }
            let tasks = Set(mine.map { $0.taskName }).sorted().joined(separator: ", ")
            let first = mine.map { $0.start }.min()
            let last = mine.map { $0.end }.max()
            byUser += """
            <tr>
              <td class="name">\(esc(state.userName(id: uid)))</td>
              <td class="num">\(hm(secs))</td>
              <td class="bar"><div class="fill" style="width:\(pct(secs, grand))%"></div></td>
              <td class="num">\(mine.count)</td>
              <td>\(esc(tasks))</td>
              <td>\(first.map(dateTime) ?? "—")</td>
              <td>\(last.map(dateTime) ?? "—")</td>
            </tr>
            """
        }

        // ---------- Summary by task, with per-user breakdown ----------
        var byTask = ""
        var matrixHead = userOrder.map { "<th class=\"num\">\(esc(state.userName(id: $0)))</th>" }.joined()
        if matrixHead.isEmpty { matrixHead = "<th class=\"num\">—</th>" }
        for task in state.tasks where !task.isArchived || task.totalSeconds > 0 {
            let name = label(task)
            let secs = total { $0.taskName == name }
            let cells = userOrder.map { uid -> String in
                let s = total { $0.taskName == name && $0.userId == uid }
                return "<td class=\"num\(s == 0 ? " dim" : "")\">\(s == 0 ? "—" : hm(s))</td>"
            }.joined()
            byTask += """
            <tr>
              <td class="name">\(esc(name))</td>
              <td class="num">\(hm(secs))</td>
              <td class="bar"><div class="fill task" style="width:\(pct(secs, grand))%"></div></td>
              <td class="num">\(task.turns.count)</td>
              \(cells.isEmpty ? "<td class=\"num dim\">—</td>" : cells)
            </tr>
            """
        }

        // ---------- Daily log ----------
        let cal = Calendar.current
        let days = Dictionary(grouping: rows) { cal.startOfDay(for: $0.start) }
        var daily = ""
        for day in days.keys.sorted(by: >) {
            let dayRows = days[day]!.sorted { $0.start < $1.start }
            let daySecs = dayRows.reduce(0) { $0 + $1.seconds }
            var userCards = ""
            for uid in userOrder {
                let mine = dayRows.filter { $0.userId == uid }
                guard !mine.isEmpty else { continue }
                let secs = mine.reduce(0) { $0 + $1.seconds }
                let arrived = mine.map { $0.start }.min()!
                let left = mine.map { $0.end }.max()!
                let stillHere = mine.contains { $0.isLive }
                userCards += """
                <div class="card">
                  <div class="card-user">\(esc(state.userName(id: uid)))</div>
                  <div class="card-hours">\(hm(secs))</div>
                  <div class="card-meta">arrived \(time(arrived)) · \(stillHere ? "still working" : "left \(time(left))") · present \(hm(left.timeIntervalSince(arrived)))</div>
                </div>
                """
            }
            let sessionRows = dayRows.map { r -> String in
                """
                <tr\(r.isLive ? " class=\"live\"" : "")>
                  <td>\(esc(r.userName))</td>
                  <td>\(esc(r.taskName))</td>
                  <td class="num">Turn \(r.turnIndex)</td>
                  <td class="num">\(time(r.start))</td>
                  <td class="num">\(r.isLive ? "<span class=\"pill\">running</span>" : time(r.end))</td>
                  <td class="num">\(hm(r.seconds))</td>
                </tr>
                """
            }.joined()
            daily += """
            <section class="day">
              <h3>\(dayTitle(day)) <span class="day-total">\(hm(daySecs))</span></h3>
              <div class="cards">\(userCards)</div>
              <table>
                <thead><tr><th>User</th><th>Task</th><th class="num">Turn</th><th class="num">Start</th><th class="num">End</th><th class="num">Duration</th></tr></thead>
                <tbody>\(sessionRows)</tbody>
              </table>
            </section>
            """
        }

        let empty = rows.isEmpty ? "<p class=\"empty\">No time recorded yet.</p>" : ""

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Time Report</title>
        <style>
          :root { --bg:#fff; --fg:#1d1d1f; --muted:#6e6e73; --line:#e5e5ea; --row:#f5f5f7; --accent:#34c759; --accent2:#0a84ff; --live:#fff6d6; }
          @media (prefers-color-scheme: dark) {
            :root { --bg:#1c1c1e; --fg:#f2f2f7; --muted:#98989d; --line:#3a3a3c; --row:#2c2c2e; --live:#3a3520; }
          }
          * { box-sizing:border-box; }
          body { margin:0; padding:32px 40px 64px; background:var(--bg); color:var(--fg);
                 font:14px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", Helvetica, Arial, sans-serif; }
          h1 { font-size:26px; margin:0 0 4px; }
          h2 { font-size:18px; margin:36px 0 12px; }
          h3 { font-size:15px; margin:0 0 10px; display:flex; justify-content:space-between; }
          .sub { color:var(--muted); margin:0 0 8px; }
          .grand { font-size:40px; font-weight:600; letter-spacing:-0.5px; margin:8px 0 0; font-variant-numeric:tabular-nums; }
          table { border-collapse:collapse; width:100%; }
          th, td { text-align:left; padding:8px 10px; border-bottom:1px solid var(--line); vertical-align:middle; }
          th { font-size:12px; text-transform:uppercase; letter-spacing:.04em; color:var(--muted); font-weight:600; }
          tbody tr:nth-child(even) { background:var(--row); }
          td.num, th.num { text-align:right; font-variant-numeric:tabular-nums; white-space:nowrap; }
          td.name { font-weight:600; }
          td.dim { color:var(--muted); }
          td.bar { width:22%; }
          .fill { height:10px; border-radius:5px; background:var(--accent); min-width:2px; }
          .fill.task { background:var(--accent2); }
          .day { margin:0 0 28px; padding:16px 18px; border:1px solid var(--line); border-radius:12px; }
          .day-total { color:var(--muted); font-weight:500; font-variant-numeric:tabular-nums; }
          .cards { display:flex; flex-wrap:wrap; gap:10px; margin:0 0 12px; }
          .card { flex:1 1 220px; padding:10px 12px; background:var(--row); border-radius:10px; }
          .card-user { font-weight:600; }
          .card-hours { font-size:22px; font-weight:600; font-variant-numeric:tabular-nums; }
          .card-meta { color:var(--muted); font-size:12px; }
          tr.live td { background:var(--live); }
          .pill { display:inline-block; padding:1px 8px; border-radius:999px; background:var(--accent); color:#fff; font-size:11px; font-weight:600; }
          .empty { color:var(--muted); }
          .wrap { overflow-x:auto; }
          footer { margin-top:40px; color:var(--muted); font-size:12px; }
        </style>
        </head>
        <body>
          <h1>Time Report</h1>
          <p class="sub">Generated \(dateTime(now))</p>
          <div class="grand">\(hm(grand))</div>
          <p class="sub">total across \(userOrder.count) user\(userOrder.count == 1 ? "" : "s") and \(state.tasks.count) task\(state.tasks.count == 1 ? "" : "s")</p>
          \(empty)

          <h2>By user</h2>
          <div class="wrap"><table>
            <thead><tr><th>User</th><th class="num">Total</th><th></th><th class="num">Sessions</th><th>Tasks worked</th><th>First activity</th><th>Last activity</th></tr></thead>
            <tbody>\(byUser)</tbody>
          </table></div>

          <h2>By task</h2>
          <div class="wrap"><table>
            <thead><tr><th>Task</th><th class="num">Total</th><th></th><th class="num">Turns</th>\(matrixHead)</tr></thead>
            <tbody>\(byTask)</tbody>
          </table></div>

          <h2>Daily log</h2>
          \(daily)

          <footer>Source: ~/Library/Application Support/TimeTracker/state.json · times shown in \(TimeZone.current.identifier)</footer>
        </body>
        </html>
        """
    }

    // MARK: - Flatten

    private static func label(_ task: TrackedTask) -> String {
        task.isArchived ? "\(task.name) (deleted)" : task.name
    }

    private static func flatten(_ state: AppState, now: Date) -> [Row] {
        var rows: [Row] = []
        for task in state.tasks {
            for (i, turn) in task.turns.enumerated() {
                for s in turn.sessions {
                    rows.append(Row(userId: s.userId, userName: state.userName(id: s.userId),
                                    taskName: label(task), turnIndex: i + 1,
                                    start: s.start, end: s.end, isLive: false))
                }
                if let r = state.running, r.taskId == task.id, r.turnId == turn.id {
                    rows.append(Row(userId: r.userId, userName: state.userName(id: r.userId),
                                    taskName: label(task), turnIndex: i + 1,
                                    start: r.startedAt, end: max(now, r.startedAt), isLive: true))
                }
            }
        }
        return rows
    }

    // MARK: - Formatting

    private static func pct(_ part: TimeInterval, _ whole: TimeInterval) -> Int {
        whole > 0 ? Int((part / whole * 100).rounded()) : 0
    }

    /// "3h 07m" / "12m" / "45s"
    static func hm(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEEE, MMM d, yyyy"; return f }()
    private static let timeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()
    private static let dateTimeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d, yyyy h:mm a"; return f }()

    private static func dayTitle(_ d: Date) -> String { dayFmt.string(from: d) }
    private static func time(_ d: Date) -> String { timeFmt.string(from: d) }
    private static func dateTime(_ d: Date) -> String { dateTimeFmt.string(from: d) }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// `TimeTracker --report` opens the HTML report without starting the menu-bar app.
/// `TimeTracker --report-html` prints the HTML to stdout.
enum ReportCLI {
    static func runIfRequested() {
        let args = CommandLine.arguments
        let wantsOpen = args.contains("--report")
        let wantsStdout = args.contains("--report-html")
        guard wantsOpen || wantsStdout else { return }

        let state = loadState() ?? .empty
        let html = ReportBuilder.html(state: state)
        if wantsStdout {
            print(html)
        } else {
            let url = TrackerPaths.reportURL
            try? html.data(using: .utf8)?.write(to: url, options: .atomic)
            NSWorkspace.shared.open(url)
            print("Report written to \(url.path)")
        }
        exit(0)
    }

    private static func loadState() -> AppState? {
        guard let data = try? Data(contentsOf: TrackerPaths.stateURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppState.self, from: data)
    }
}

enum TrackerPaths {
    /// Set TIMETRACKER_DIR to point the app/CLI at a different data folder (used for testing).
    static var directory: URL {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment["TIMETRACKER_DIR"], !override.isEmpty {
            let dir = URL(fileURLWithPath: override, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = (base ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent("TimeTracker", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var stateURL: URL { directory.appendingPathComponent("state.json") }
    static var reportURL: URL { directory.appendingPathComponent("report.html") }
    static var backupsDirectory: URL {
        let dir = directory.appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
