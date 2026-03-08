# DeskPad Displays Contract -- Checklist

| ID | Requirement | Acceptance Criteria |
|---|---|---|
| REQ1 | DeskPad writes a display snapshot to `~/.DeskPad/displays.json`. | Running DeskPad creates `~/.DeskPad/displays.json` and `~/.DeskPad/` if absent. |
| REQ2 | The file is written atomically as valid UTF-8 JSON with a trailing newline. | Code writes to a temp path and replaces the final file with `rename`, and serialized output ends with `\n`. |
| REQ3 | DeskPad writes the snapshot on application startup. | Launch path calls the snapshot publisher before app becomes idle; a fresh file timestamp appears after launch. |
| REQ4 | DeskPad updates the snapshot after screen configuration changes via `NSApplication.didChangeScreenParametersNotification`. | Notification observer exists and triggers a rewrite only when display state changes. |
| REQ5 | Root JSON contains `version`, `generatedAt`, `host`, `activeDisplayID`, `mainDisplayID`, `arrangement`, and `displays`. | Serialized JSON shape matches the spec and compiles without placeholder fields. |
| REQ6 | `arrangement.orderedDisplayIDs` uses strategy `frame-origin-left-to-right`, sorting by `frame.x` then `frame.y`. | Code sorts screens by `frame.x` then `frame.y`, and each display receives the corresponding `arrangementIndex`. |
| REQ7 | Each display entry includes `displayID`, `arrangementIndex`, `isMain`, `isBuiltin`, `lastSeenAt`, `frame`, `visibleFrame`, `backingScaleFactor`, and `localizedName`. | Display mapping code populates every required field from AppKit/CoreGraphics data. |
| REQ8 | `activeDisplayID` is populated with a soft hint and may fall back to `mainDisplayID`. | JSON always contains `activeDisplayID`, using `mainDisplayID` when no stronger activity signal exists. |
| REQ9 | DeskPad writes a final snapshot on termination only when screen state changed since the previous write. | Termination path calls a conditional writer that skips unchanged snapshots. |

## Known Traps

| TRA-ID | REQ-ID | Trap | Category | Mitigation |
|---|---|---|---|---|
| TRA1 | REQ2 | `FileManager.moveItem` is not an overwrite-safe atomic replace when the destination already exists. | Boundary/Mismatch | Use a temp file and POSIX `rename()` on the same filesystem. |
| TRA2 | REQ3, REQ4 | The virtual display may appear after app launch, so a single launch-time snapshot can miss the final screen list. | Hidden Prerequisite | Write once on startup and also observe `didChangeScreenParameters` so the snapshot converges after display registration. |
| TRA3 | REQ6, REQ7 | `NSScreen.main` is not the same as the system main display, and screen ordering must not depend on AppKit's array order. | Boundary/Mismatch | Use `CGMainDisplayID()` for the main display and perform explicit deterministic sorting. |
| TRA4 | REQ9 | Comparing full JSON would make `generatedAt` and `lastSeenAt` force unnecessary rewrites. | Implementation Depth | Track a stable configuration signature separate from serialized timestamps. |
