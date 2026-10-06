# Window Controls

Corner buttons for Omarchy windows. Drag a window from the grip, resize it from the bottom-right handle, and snap it by dropping it on a corner or a side. The status bar lists open windows alongside the workspace buttons and clock, including minimized windows and windows on other workspaces.

## Behavior

- Controls and resize handles use logical window coordinates, including on monitors with fractional scaling.
- Dragging to a corner fills a quarter of the destination monitor's work area. The left and right edges fill a half; the top fills the work area. The bottom edge alone does not snap.
- A drag or resize starts after the pointer moves at least four logical pixels. Clicking the resize handle alone does not change the window's layout.
- Minimized windows use `special:li-window-controls`. Other special workspaces remain independent.
- Original workspaces are saved outside the plugin directory and restored after plugin reloads or shell restarts. Saved records are checked against live window identities.
- Controls have no fixed window-count limit. Open windows appear on their monitor's status bar by application name. Names shrink to fit more windows together, and pages appear when the list still exceeds the available space. Click a name to focus that window or restore it to its original workspace. The focused window is highlighted. The widget uses the bar's theme and leaves space for the clock and other widgets. Hover a name to read the window's full title.
- Button presses retain their original window target. Controls that would obstruct a foreground window are suppressed using the compositor's focus and window-state information.
- Full-title and action tooltips describe the controls. Compact controls fit smaller windows.

The overlay does not take keyboard focus. Omarchy's existing window-management shortcuts remain available.

## Requirements

This version targets Omarchy 4, Hyprland's Lua dispatcher API, and Quickshell 0.3.1 or newer. Runtime commands use the existing `bash` and `hyprctl` programs.

## Install

```bash
omarchy plugin add https://github.com/andersonmorillo/window-controls.git --enable
```

For an existing Git installation, update with `omarchy plugin update li.window-controls`. If it was enabled as a panel-only plugin, move its existing configuration entry into the bar layout:

```bash
omarchy plugin disable li.window-controls
omarchy plugin enable li.window-controls --after omarchy.workspaces
```

Restore metadata survives this change. Local source edits trigger a plugin refresh. If status still reports the previous version, run `omarchy restart shell` to clear cached QML.

Place the open-window widget after the workspace buttons:

```bash
omarchy bar put li.window-controls --after omarchy.workspaces
```

You can move it through the bar's normal layout controls or change its maximum width:

```bash
omarchy bar set li.window-controls maxWidth 640 --json
```

Window entries prefer 96 logical pixels and can shrink to 72 pixels when needed. The maximum width is also limited by the display and available space before the center widgets. You can adjust the entry widths with `chipWidth` and `minChipWidth` through the same bar settings command.

## Development and checks

Run the helper and state regressions from the repository:

```bash
node check.js
node state-check.js
node bar-check.js
bash tests/run-qml-smoke.sh
bash tests/run-persistence.sh
omarchy plugin validate .
```

The QML smoke test needs a running Wayland session. It uses an isolated shell with invisible overlays, disables compositor actions and persistence, and checks the actual QML component. Node is required only for development checks.

The persistence check runs two separate offscreen shell processes with temporary settings to verify restore metadata survives a restart.

For desktop verification, use disposable test windows and capture the whole desktop so layer-shell controls are included:

```bash
omarchy capture screenshot fullscreen save
hyprctl clients -j
hyprctl monitors -j
omarchy-shell shell call li.window-controls status ''
```

Cover fractional scaling, mixed-monitor drag and snapping, 13 or more windows, shelf overflow, overlapping windows, canceled gestures, inactive workspace selection, bar maximization, and minimize → reload → restore. Store captures outside the live plugin folder, since its file watcher reloads code on changes.

The status call reports polling failures and snapshot age as well as control positions. Invalid snapshots never replace the last valid state, and stale controls stop taking input if updates cannot recover.

## Remove

```bash
omarchy plugin remove li.window-controls
```

## License

MIT. The plugin runs inside the existing Omarchy shell and saves its own restore metadata when enabled.
