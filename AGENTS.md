# Move Cursor Display

Omarchy shell plugin that moves the cursor to another display with a keyboard shortcut.
QML (Quickshell 0.3.1) + Lua (Hyprland 0.56.2; tests run on standalone Lua 5.5).

## Layout

- `manifest.json` - Plugin registration: a single `service` kind, kept loaded.
- `Service.qml` - Lifecycle. Reads the optional JSON keymap, checks key conflicts, and
  registers bindings through `hyprctl eval`. Re-registers after a Hyprland config reload
  and clears its bindings on teardown.
- `hypr/bind.lua` - Hyprland adapter. Owns the four action closures and the global
  `apply`/`clear` lifecycle. A keyboard listener refreshes the cursor after the shortcut
  is released, because `hide_on_key_press` hides it again on key release.
- `hypr/core.lua` - Pure geometry: logical rectangles, display ordering, relative and
  center destinations. Takes plain tables and has no Hyprland dependency.
- `test/core_test.lua` - Geometry tests: layouts, scaling, rotation, clamping, round trips.
- `test/bind_test.lua` - Adapter tests against a stubbed Hyprland API.
- `preview.png` - Marketplace preview image, also shown at the top of the README.

## Design notes

- Bindings are registered at runtime. User Hyprland config files are never modified.
- `bind.lua` loads `core.lua` once and captures it, so a key press reads no files and
  leftover bindings keep working if the plugin directory is removed.
- Each service instance carries an owner token, so an old instance tearing down late
  cannot clear the bindings of its replacement.
- Relative placement maps the addressable span (logical size minus one) and keeps
  fractional coordinates, so edges survive a round trip across displays of different sizes.
- Monitor geometry is read on every key press.

## Conventions

- English only, in code, comments, and docs.
- Keep each file under 800 lines.
- After changing `hypr/`, run `lua test/core_test.lua` and `lua test/bind_test.lua`
  from the repository root.
- Update this file when files are added, removed, or change responsibility.
