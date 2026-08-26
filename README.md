# Time Tracker

A macOS menu-bar time tracker for working on multiple tasks in a time-shared
(one-at-a-time) fashion. Each task has multiple turns; each turn accumulates
its own elapsed time and can be paused/resumed/stopped.

## Features

- Lives in the macOS status bar (no Dock icon).
- Click the menu-bar icon to open a popover with all tasks.
- Only one turn runs at a time — starting/resuming any turn auto-pauses the current one.
- Per turn: **Start/Resume**, **Pause** (keeps the turn open), **Stop** (closes the turn).
- Add / rename / delete tasks.
- Persistent state: saved to `~/Library/Application Support/TimeTracker/state.json`.
- Auto-pauses on system sleep and app quit; auto-resumes the same turn on wake / relaunch.
  The offline gap is **not** counted toward elapsed time.

## Build & run

Requires macOS 13+ and the Swift toolchain (Xcode command-line tools are enough).

```sh
cd /Users/c910451/Documents/PersonalGithubProjects/timeTracker
swift run -c release
```

The first time you run it, the icon appears in the menu bar. Click it to open the popover.
Use the ⏻ button in the popover header to quit.

## Notes on data model

- **Task**: `{ id, name, turns[], createdAt }`
- **Turn**: `{ id, accumulatedSeconds, isClosed, createdAt }`
- **Running**: at most one `{ taskId, turnId, startedAt }` at a time. Elapsed time for the
  live turn = `accumulatedSeconds + (now - startedAt)`.
- On pause: the live delta is folded into `accumulatedSeconds` and `running` is cleared.
- On stop: same as pause plus `isClosed = true` (turn cannot be resumed; a new turn must be started).
