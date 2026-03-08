# DeskPad

You're sharing your screen during a call, but your 5K display makes everything tiny for the audience. Or you need a clean workspace to present from without rearranging your actual desktop. DeskPad gives you a virtual monitor -- a real macOS display that lives inside an app window you can share.

## Getting Started

Build and install:

```
make install
```

This compiles a Release build and copies DeskPad.app to /Applications. You need Xcode installed.

On first launch, macOS will ask for Screen Recording permission. Grant it in System Settings -> Privacy & Security -> Screen Recording, then restart the app.

## How It Works

Launching DeskPad is like plugging in a second monitor. macOS treats it as a real display -- you can drag windows to it, set its resolution in System Settings -> Displays, and share it in any video call app.

The app window mirrors everything on the virtual display in real time. When your mouse cursor moves to the virtual display, the title bar turns blue so you know where you are.

The virtual display defaults to your main screen's resolution, so content appears at a familiar size from the start. You can change it anytime through System Settings.

## Status Bar

DeskPad runs from the menu bar and does not appear in the Dock. Click the display icon in the menu bar to:

- **Hide Window** -- the virtual display stays active (apps remain on it, screen sharing keeps working), but the mirror window disappears from your desktop
- **Show Window** -- brings the mirror back
- **Quit DeskPad** -- removes the virtual display and exits

Hiding the window is useful when you only need the virtual display for screen sharing and don't want the mirror taking up space.

## Display Snapshot

DeskPad writes your current display configuration to `~/.DeskPad/displays.json` whenever screens change -- monitors connected/disconnected, resolution changed, arrangement updated. The file contains display IDs, positions, resolutions, and scale factors for all active displays. Useful for scripts or tools that need to react to display changes.

## Troubleshooting

**Black or empty window:** Screen Recording permission is missing or stale. Go to System Settings -> Privacy & Security -> Screen Recording, toggle DeskPad off then on, and restart the app.

**Window not matching resolution:** Change the virtual display's resolution in System Settings -> Displays. Select "DeskPad Display" and pick a resolution. The window adjusts automatically.

## Building from Source

```
make build      # Debug build
make release    # Release build
make clean      # Remove build artifacts
make uninstall  # Remove from /Applications
```

Requires Xcode. The project uses SwiftFormat via a build phase -- it runs automatically during compilation.

## License

MIT -- see LICENSE.md.
