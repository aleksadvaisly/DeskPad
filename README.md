# DeskPad

DeskPad creates a real virtual display on macOS and mirrors it inside a lightweight app window. The goal is simple: give you a separate screen you can move windows onto, then share that cleaner workspace in a call, stream, or recording without rearranging your main desktop.

macOS sees `DeskPad Display` as a normal monitor. You can move apps to it, change its resolution in Displays settings, and share it like any other screen.

## Requirements

- macOS
- Xcode command line tools / Xcode for building
- Screen Recording permission for the live mirror

## Install

```sh
make install
```

This builds a Release app and installs it to `/Applications/DeskPad.app`.

For a local Debug build:

```sh
make build
open build/Build/Products/Debug/DeskPad.app
```

## First Launch

When DeskPad starts mirroring the virtual display, macOS should request `Screen Recording` permission. Grant it in:

`System Settings -> Privacy & Security -> Screen Recording`

If you grant permission after launch, restart DeskPad.

If macOS does not show the prompt again because it already cached a previous decision, reset it with:

```sh
tccutil reset ScreenCapture com.stengo.DeskPad
```

## What DeskPad Does

- Creates a virtual monitor named `DeskPad Display`
- Mirrors that monitor in a resizable app window
- Lets you change the virtual display resolution through macOS Displays settings
- Keeps the virtual display alive even when the mirror window is hidden
- Publishes the current monitor layout to `~/.DeskPad/displays.json`
- Persists DeskPad UI preferences in `~/.DeskPad/settings.json`

## Menu Bar Controls

DeskPad runs as a menu bar app and does not stay in the Dock.

The status menu currently includes:

- `Hide Window` / `Show Window`
- `Bring Back`
- `Always On Top`
- `Refresh Rate > 30 Hz / 60 Hz`
- `In Use Indicator > info / warning / error`
- `Quit DeskPad`

### Refresh Rate

The virtual display can be exposed as either `30 Hz` or `60 Hz`. The selected value is remembered between launches.

### In Use Indicator

When the mouse is on the virtual display, the compact title bar can highlight in one of three styles:

- `info` - solid blue
- `warning` - diagonal yellow/anthracite stripes
- `error` - pulsing record-style red against dark anthracite

The selected style is remembered between launches.

## Saved State

DeskPad stores its own preferences in `~/.DeskPad/settings.json`.

Current persisted state includes:

- refresh rate
- in-use indicator style
- preferred virtual display mode
- window position and size
- window visibility
- always-on-top state

On startup, DeskPad restores these values when possible.

## Display Snapshot

DeskPad writes `~/.DeskPad/displays.json` and refreshes it when screen configuration changes.

The snapshot contains:

- host metadata
- active and main display IDs
- display ordering
- per-display frame and visible frame
- scale factor
- localized display names

This is useful if you want external scripts or tools to react to the current display layout.

## Troubleshooting

### Black or empty mirror window

Most often this means Screen Recording permission is missing, stale, or denied. Re-check it in System Settings and restart the app.

### Prompt does not appear

macOS may already have a stored TCC decision. Reset with:

```sh
tccutil reset ScreenCapture com.stengo.DeskPad
```

Then launch DeskPad again.

### Wrong mirrored size

Change the resolution for `DeskPad Display` in macOS Displays settings. DeskPad updates the mirror window to match and also remembers the last selected display mode.

### Hidden window but display still exists

That is intentional. `Hide Window` only removes the local mirror window from your desktop. The virtual display itself stays active until you quit DeskPad.

## Build Commands

```sh
make build
make release
make install
make uninstall
make clean
```

The project runs SwiftFormat from an Xcode build phase during compilation.

## License

MIT. See `LICENSE.md`.
