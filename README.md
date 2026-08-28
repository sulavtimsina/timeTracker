# Time Tracker

A macOS menu-bar time tracker for a small team (or a shared computer) where people take
turns working on a set of tasks. It records **who** worked on **which task**, **when**, and for
**how long**, and produces a clean HTML report on demand.

- Lives in the menu bar — no Dock icon, no window to manage.
- Multiple **users**, but only one is active at a time; time is always attributed to the
  person who was signed in.
- Multiple **tasks**, each with any number of **turns** (a turn is one work stint on a task
  that can be paused and resumed).
- **HTML report** with totals per user, per task, per day, plus arrival/departure times.

---

## Requirements

- macOS 13 or newer
- Swift toolchain (Xcode Command Line Tools are enough: `xcode-select --install`)

## Build and run

```sh
cd /Users/sulavtimsina/timeTracker/timeTracker
swift build -c release
.build/release/TimeTracker
```

Or simply `swift run -c release`, which builds and runs in one step (Ctrl-C quits).

### Install as an app in /Applications

```sh
scripts/build-app.sh            # builds dist/TimeTracker.app
scripts/build-app.sh --install  # also installs to /Applications and launches it
```

This wraps the release binary in a proper `.app` bundle with an icon
(`packaging/AppIcon.icns`) and `packaging/Info.plist`, ad-hoc code-signs it, and — with
`--install` — replaces `/Applications/TimeTracker.app` so you can launch it from Launchpad
or Spotlight. The bundle sets `LSUIElement`, so there is no Dock icon; look for the clock
in the menu bar.

To regenerate the icon from its source drawing:

```sh
swift packaging/makeicon.swift icon1024.png
mkdir -p AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s icon1024.png --out AppIcon.iconset/icon_${s}x${s}.png
  sips -z $((s*2)) $((s*2)) icon1024.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns AppIcon.iconset -o packaging/AppIcon.icns
```

The app appears as a **clock icon** in the menu bar. While a turn is running it becomes a
**record icon** followed by the task name and elapsed time, e.g. `⏺ Task 1 12:34`.

> **Notched MacBooks:** macOS hides menu-bar items that don't fit beside the notch, with no
> warning. If you don't see the icon, quit a couple of other menu-bar apps or check an external
> display. `pgrep -fl TimeTracker` confirms the app is running.

Only run **one copy** at a time — two instances would fight over the same data file.

---

## Using the app

Click the menu-bar icon to open the popover.

### Header

| Control | What it does |
|---|---|
| Green text `Task • 00:00` | The currently running task and its live time |
| 🔍 (`doc.text.magnifyingglass`) | Generate the HTML report and open it in your browser |
| ⏻ | Quit (the running turn is paused and saved first) |

### User row

Directly under the header. Shows the active user, or **Select user** in orange if nobody is
signed in.

Click it for the user menu:

- **A user's name** — sign that person in. If someone else's turn is running it is paused
  first; the new person presses ▶ themselves.
- **Add User…** — type a name, press Add. The first user you add is signed in automatically.
- **Rename …** — rename the active user.
- **Sign Out …** — nobody active; running turn is paused.
- **Remove …** — removes the active user from the menu. Their past time stays in the report
  under their name.

**Nothing can be started or resumed until a user is selected.** The ▶ and *New Turn*
buttons are disabled and the row shows *Select a user to track time*.

### Tasks and turns

Each task shows a **chevron** (click the name to collapse or expand its turns — remembered
across relaunches), its total time, and a `…` menu (Rename, New Turn, Delete Task — which
asks for confirmation and keeps the recorded time). Under it, one row per turn; if a task
has more than 10 turns the list scrolls and opens on the running or newest turn.

| Turn state | Dot | Buttons |
|---|---|---|
| Running | 🟢 | ⏸ Pause |
| Paused | 🟠 | ▶ Resume |

- **▶ / Start Turn 1 / New Turn** — start tracking. Whatever was running (for anyone) is
  paused automatically; only one turn runs at a time.
- **⏸** — pause, keeping the turn open so it can be resumed later.
- There is deliberately **no Stop button**, so a turn can't be closed by accident. Start a
  *New Turn* when you want a fresh one.
- The running turn row also shows the name of the user doing the work.

Add a task with the text field at the bottom (**Add** or Return).

### A typical two-person day

1. Person A opens the popover, picks **A** in the user menu, presses ▶ on a task.
2. A pauses, switches tasks, starts new turns — all logged under A.
3. A leaves: **Sign Out** (or B simply picks **B** — A's running turn pauses automatically).
4. B picks a task and presses ▶; everything from here is logged under B.
5. Anyone clicks 🔍 to see hours per person, per task, and per day.

### Sleep, wake, quit, relaunch

- Closing the lid / sleeping pauses the running turn; waking resumes the same turn. The time
  asleep is **not** counted.
- Quitting (⏻, `kill`, `pkill`, or Ctrl-C in the terminal) saves the running turn; relaunching
  resumes it. The time the app was closed is not counted.
- The signed-in user is remembered across relaunches.

---

## The report

Click 🔍 in the popover, or from a terminal:

```sh
.build/release/TimeTracker --report        # write report.html and open it in the browser
.build/release/TimeTracker --report-html   # print the HTML to stdout instead
```

Neither command starts the menu-bar app; they read the saved data and exit.

**Saved to:** `~/Library/Application Support/TimeTracker/report.html`
(overwritten on every generation — copy it elsewhere if you want to keep a snapshot).

The report is a single self-contained HTML file (no external assets, prints well, light and
dark mode) containing:

1. **Grand total** across everyone.
2. **By user** — total time, share bar, number of sessions, tasks worked, first and last
   activity.
3. **By task** — total, share bar, number of turns, and a column per user showing how much
   each person contributed.
4. **Daily log** — newest day first. For each day: a card per user with **arrived**, **left**
   (or *still working*), **present** (wall-clock span) and **hours worked**, followed by every
   session that day (user, task, turn, start, end, duration). A session that is running right
   now is highlighted with a green **running** pill.

Time recorded before users existed appears as **Unassigned**.

---

## Where data is saved

| File | Purpose |
|---|---|
| `~/Library/Application Support/TimeTracker/state.json` | All tasks, turns, sessions, users — the single source of truth. Written on every change. |
| `~/Library/Application Support/TimeTracker/report.html` | The most recently generated report. |
| `~/Library/Application Support/TimeTracker/backups/state-YYYY-MM-DD.json` | Automatic daily backup, taken on the first launch of each day. The newest 30 are kept. |

`state.json` is human-readable JSON. Set the environment variable
`TIMETRACKER_DIR=/some/folder` to make the app and the CLI use a different folder (handy for
testing or keeping separate books).

### Data safety

Recorded time is treated as irreplaceable. Rules the app follows:

- **Nothing in the app removes recorded time.** *Delete Task* and *Remove User* only
  archive: the item disappears from the popover, but every session stays in `state.json`
  and in the report (tasks show as `Name (deleted)`). Deleting a task asks for
  confirmation first.
- **Every change is saved immediately** with an atomic write, so a crash mid-write can't
  leave a half-written file.
- **Quitting saves the live turn** — the ⏻ button, `kill`, `pkill`, and Ctrl-C all pause
  the running turn and write it out before exiting. Sleep does the same. On relaunch / wake
  the turn resumes; the time away is not counted.
- **An unreadable `state.json` is never overwritten.** If the file can't be parsed, it is
  moved to `state.unreadable-<timestamp>.json` and the app starts empty; the original is
  there to recover from.
- **Daily backups** are taken automatically into `backups/`.

To restore from a backup: quit the app, copy the chosen `backups/state-….json` over
`state.json`, and relaunch.

### Data model

- **User**: `{ id, name, isArchived, createdAt }` — *Remove* archives rather than deletes so
  old sessions keep their name.
- **Task**: `{ id, name, turns[], isArchived, createdAt }` — *Delete Task* archives.
- **Turn**: `{ id, sessions[], isClosed, createdAt }`; `accumulatedSeconds` is derived (sum of
  sessions) and written only for readability.
- **Session**: `{ id, userId, start, end }` — one uninterrupted stretch of work by one user.
  `userId` is `null` for pre-users data.
- **running**: at most one `{ taskId, turnId, startedAt, userId }` at a time. Live time for
  that turn = `accumulatedSeconds + (now − startedAt)`.
- **pendingResume**: set on sleep/quit so the same turn resumes on wake/relaunch.

On pause, user switch, sleep or quit, a session `[startedAt, now]` is appended to the turn
and `running` is cleared. Files from before sessions existed are migrated on first load: the
old `accumulatedSeconds` becomes one unassigned session starting at the turn's `createdAt`.

---

## Project layout

```
Package.swift
Sources/TimeTracker/
  TimeTrackerApp.swift   # app entry, menu-bar label, signal handling, --report CLI hook
  ContentView.swift      # the popover UI
  TrackerStore.swift     # state, persistence, timers, sleep/quit handling
  Models.swift           # User, Task, Turn, Session, AppState (+ legacy migration)
  Report.swift           # HTML report builder, CLI, data paths
```
