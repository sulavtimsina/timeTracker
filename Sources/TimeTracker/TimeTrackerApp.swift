import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var termSource: DispatchSourceSignal?
    private var intSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — pure menu bar app.
        NSApp.setActivationPolicy(.accessory)
        installSignalHandlers()
    }

    /// `kill`, `pkill`, and Ctrl-C would otherwise end the process without running
    /// `applicationWillTerminate`, losing the live turn's elapsed time. Route them through
    /// a normal terminate so the store can pause and save first.
    private func installSignalHandlers() {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        for source in [termSource, intSource] {
            source?.setEventHandler { NSApp.terminate(nil) }
            source?.resume()
        }
    }
}

@main
struct TimeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TrackerStore()

    init() {
        // `TimeTracker --report` / `--report-html` run headlessly and exit.
        ReportCLI.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(store)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @EnvironmentObject var store: TrackerStore

    var body: some View {
        // `store.tick` drives per-second updates.
        let _ = store.tick
        HStack(spacing: 4) {
            Image(systemName: store.state.running == nil ? "clock" : "record.circle")
            if let task = store.runningTask,
               let r = store.state.running,
               let turn = task.turns.first(where: { $0.id == r.turnId }) {
                Text("\(shortName(task.name)) \(TimeFormat.hms(store.liveElapsed(for: turn, in: task)))")
                    .monospacedDigit()
            }
        }
    }

    private func shortName(_ n: String) -> String {
        n.count > 12 ? String(n.prefix(12)) + "…" : n
    }
}
