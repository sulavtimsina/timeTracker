import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: TrackerStore
    @State private var newTaskName: String = ""
    @State private var editingTaskId: UUID? = nil
    @State private var editingName: String = ""
    @State private var userEditor: UserEditor? = nil
    @State private var userEditorName: String = ""

    private enum UserEditor: Equatable {
        case add
        case rename(UUID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            userBar
            if let editor = userEditor { userEditorRow(editor) }
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
                store.openReport()
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Open HTML time report")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit Time Tracker")
        }
    }

    // MARK: - User bar

    private var userBar: some View {
        HStack(spacing: 6) {
            Image(systemName: store.canTrack ? "person.crop.circle.fill" : "person.crop.circle.badge.questionmark")
                .foregroundStyle(store.canTrack ? Color.accentColor : Color.orange)
            Menu {
                ForEach(store.state.activeUsers) { user in
                    Button {
                        store.setActiveUser(user.id)
                    } label: {
                        if user.id == store.activeUser?.id {
                            Label(user.name, systemImage: "checkmark")
                        } else {
                            Text(user.name)
                        }
                    }
                }
                if !store.state.activeUsers.isEmpty { Divider() }
                Button("Add User…") {
                    userEditorName = ""
                    userEditor = .add
                }
                if let active = store.activeUser {
                    Button("Rename \(active.name)…") {
                        userEditorName = active.name
                        userEditor = .rename(active.id)
                    }
                    Button("Sign Out \(active.name)") { store.setActiveUser(nil) }
                    Divider()
                    Button("Remove \(active.name)", role: .destructive) { store.removeUser(userId: active.id) }
                }
            } label: {
                Text(store.activeUser?.name ?? "Select user")
                    .font(.subheadline)
                    .foregroundStyle(store.canTrack ? Color.primary : Color.orange)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            if !store.canTrack {
                Text("Select a user to track time")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func userEditorRow(_ editor: UserEditor) -> some View {
        HStack {
            TextField(editor == .add ? "New user name" : "User name", text: $userEditorName, onCommit: commitUserEditor)
                .textFieldStyle(.roundedBorder)
            Button(editor == .add ? "Add" : "Save", action: commitUserEditor)
                .keyboardShortcut(.defaultAction)
            Button("Cancel") { userEditor = nil }
        }
    }

    private func commitUserEditor() {
        switch userEditor {
        case .add: store.addUser(name: userEditorName)
        case .rename(let id): store.renameUser(userId: id, to: userEditorName)
        case nil: break
        }
        userEditor = nil
        userEditorName = ""
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
                            .disabled(!store.canTrack)
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
                .disabled(!store.canTrack)
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
                .disabled(!store.canTrack)
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
            if running, let r = store.state.running {
                Text(store.state.userName(id: r.userId))
                    .font(.caption2).foregroundStyle(.secondary)
            }
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
            } else {
                Button {
                    store.startOrResume(taskId: task.id, turnId: turn.id)
                } label: { Image(systemName: "play.fill") }
                .help(store.canTrack ? "Resume" : "Select a user first")
                .disabled(!store.canTrack)
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
