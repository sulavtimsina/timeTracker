import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: TrackerStore
    @State private var newTaskName: String = ""
    @State private var editingTaskId: UUID? = nil
    @State private var editingName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            if store.state.tasks.isEmpty {
                Text("No tasks yet. Add one below.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.state.tasks) { task in
                        taskRow(task)
                        Divider()
                    }
                }
            }
            addTaskBar
        }
        .padding(12)
        .frame(minWidth: 260, idealWidth: 280)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "clock.fill")
            Text("Time Tracker").font(.headline)
            Spacer()
            if let running = store.runningTask,
               let r = store.state.running,
               let turn = running.turns.first(where: { $0.id == r.turnId }) {
                Text("\(running.name) • \(TimeFormat.hms(store.liveElapsed(for: turn, in: running)))")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit Time Tracker")
        }
    }

    // MARK: - Task row

    @ViewBuilder
    private func taskRow(_ task: TrackedTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if editingTaskId == task.id {
                    TextField("Task name", text: $editingName, onCommit: {
                        store.renameTask(taskId: task.id, to: editingName)
                        editingTaskId = nil
                    })
                    .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        store.renameTask(taskId: task.id, to: editingName)
                        editingTaskId = nil
                    }
                    Button("Cancel") { editingTaskId = nil }
                } else {
                    Text(task.name).font(.subheadline).bold()
                    Spacer()
                    Text(TimeFormat.hms(store.liveTotal(for: task)))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                    Menu {
                        Button("Rename") {
                            editingName = task.name
                            editingTaskId = task.id
                        }
                        Button("New Turn") { store.startNewTurn(taskId: task.id) }
                        Divider()
                        Button("Delete Task", role: .destructive) { store.deleteTask(taskId: task.id) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            if task.turns.isEmpty {
                Button {
                    store.startNewTurn(taskId: task.id)
                } label: {
                    Label("Start Turn 1", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                ForEach(Array(task.turns.enumerated()), id: \.element.id) { idx, turn in
                    turnRow(task: task, turn: turn, index: idx + 1)
                }
                Button {
                    store.startNewTurn(taskId: task.id)
                } label: {
                    Label("New Turn", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Turn row

    @ViewBuilder
    private func turnRow(task: TrackedTask, turn: Turn, index: Int) -> some View {
        let running = store.isRunning(taskId: task.id, turnId: turn.id)
        HStack(spacing: 8) {
            Circle()
                .fill(running ? Color.green : (turn.isClosed ? Color.gray : Color.orange))
                .frame(width: 8, height: 8)
            Text("Turn \(index)").font(.caption)
            Spacer()
            Text(TimeFormat.hms(store.liveElapsed(for: turn, in: task)))
                .font(.caption).monospacedDigit()

            if turn.isClosed {
                Text("stopped").font(.caption2).foregroundStyle(.secondary)
            } else if running {
                Button {
                    store.pauseRunning()
                } label: { Image(systemName: "pause.fill") }
                .help("Pause")
                Button {
                    store.stopTurn(taskId: task.id, turnId: turn.id)
                } label: { Image(systemName: "stop.fill") }
                .help("Stop (close turn)")
            } else {
                Button {
                    store.startOrResume(taskId: task.id, turnId: turn.id)
                } label: { Image(systemName: "play.fill") }
                .help("Resume")
                Button {
                    store.stopTurn(taskId: task.id, turnId: turn.id)
                } label: { Image(systemName: "stop.fill") }
                .help("Stop (close turn)")
            }
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Add task bar

    private var addTaskBar: some View {
        HStack {
            TextField("New task name", text: $newTaskName, onCommit: submitNew)
                .textFieldStyle(.roundedBorder)
            Button("Add", action: submitNew)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func submitNew() {
        store.addTask(name: newTaskName)
        newTaskName = ""
    }
}
