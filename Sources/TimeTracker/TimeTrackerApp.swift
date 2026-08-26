import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — pure menu bar app.
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct TimeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TrackerStore()

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
