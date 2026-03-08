# DeskPad Displays Contract -- Implementation Plan

## REQ1, REQ2, REQ5, REQ7, REQ8

- Add snapshot models in DeskPad for the root document, host, arrangement, display entries, and frame payloads.
- Build the snapshot from `NSScreen.screens`, `CGMainDisplayID()`, `CGDisplayIsBuiltin`, `visibleFrame`, and `localizedName`.
- Serialize using `JSONEncoder` with sorted keys and pretty printing, then append a trailing newline.
- Write to `~/.DeskPad/displays.json.tmp` and atomically replace `~/.DeskPad/displays.json` via `rename()`.

Verification:

- `make build`
- `test -f ~/.DeskPad/displays.json`
- `python3 -m json.tool ~/.DeskPad/displays.json >/dev/null`

Trap mitigations:

- TRA1: keep temp file in the same directory as the final file.
- TRA3: do not rely on `NSScreen.main` or original screen order.

## REQ3, REQ4, REQ9

- Add a publisher object owned by `AppDelegate`.
- Force one snapshot write during app startup after the main window and controller are created.
- Register `NSApplication.didChangeScreenParametersNotification` and rewrite only when the stable configuration signature changes.
- On termination, perform one final conditional write if the signature diverged since the previous save.

Verification:

- `make build`
- Manual runtime check: launch DeskPad, inspect `~/.DeskPad/displays.json`, then connect/disconnect or reconfigure a display and confirm file timestamp changes.

Trap mitigations:

- TRA2: startup write is not the only source of truth; screen-parameter notifications reconcile later changes.
- TRA4: compare stable geometry/main-display data instead of the final JSON bytes.
