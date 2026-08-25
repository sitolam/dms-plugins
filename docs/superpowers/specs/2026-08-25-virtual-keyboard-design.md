# Virtual keyboard plugin — design

Status: approved for implementation
Date: 2026-08-25

## Summary

Port [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)'s on-screen
keyboard (`dots/.config/quickshell/ii/modules/ii/onScreenKeyboard/`) into a
DMS plugin, restyled to DMS's own design language (Theme colors, `StyledRect`/
`StyledText`, dankMenu's card+blur convention) rather than upstream's flat
`illogical-impulse` look. Plugin id: `virtualKeyboard`.

Primary entry points, in priority order:
1. **IPC** — `dms ipc call virtualKeyboard toggle|open|close`, bindable to any
   compositor keybind (niri, Hyprland, anything). This is the point of the
   feature; nothing about it requires the bar.
2. **DankBar pill** — optional, off by default (composite plugins are not
   auto-added to the bar). A keyboard icon that toggles the same state.

## Why ydotool, not wtype

Upstream uses `ydotool` with raw Linux input-event keycodes (`OskKey.qml`,
`layouts.js`) instead of `wtype`, because the shift/ctrl/alt keys must be
*held down* while a following key is pressed — that's a press/release pair
spanning two separate taps on the on-screen keyboard, not a single atomic
"type this codepoint" call. `wtype` has no equivalent of holding a modifier
across two separate emit calls; `ydotool key <code>:1` / `<code>:0` does,
because it drives `/dev/uinput` directly and is compositor-agnostic (works on
niri, Hyprland, anything — matching this repo's `compositors: any` badge).
Same reasoning, same tool, ported here.

Dependency: the `ydotool` binary plus a running `ydotoold` (needs the user in
the `input` group or the socket world-writable, depending on distro
packaging). Gated behind a `startupCheck` component (same pattern as
mouthGuard's Python dependency gate) — if `ydotool` is missing or `ydotoold`
isn't reachable, the plugin refuses to enable and shows an actionable error
instead of silently eating keypresses.

## Scope: US QWERTY only

Upstream ships US/German/Russian. This plugin ships **US QWERTY only** for
v1, full layout including the function row (Esc/F1-F12/PrtSc/Del), matching
the existing two plugins' scope discipline (dankMenu ships one menu schema,
mouthGuard one detector backend). Additional layouts are a follow-up, not
blocking this PR.

## Plugin manifest

```json
{
    "id": "virtualKeyboard",
    "name": "Virtual Keyboard",
    "description": "On-screen keyboard overlay, toggled by IPC or an optional DankBar pill",
    "version": "0.1.0",
    "license": "MIT",
    "author": "sitolam",
    "icon": "keyboard",
    "type": "composite",
    "capabilities": ["daemon", "ipc", "dankbar-widget"],
    "components": {
        "daemon": "./VirtualKeyboardDaemon.qml",
        "widget": "./VirtualKeyboardWidget.qml"
    },
    "settings": "./VirtualKeyboardSettings.qml",
    "startupCheck": "./StartupCheck.qml",
    "requires_dms": ">=1.5.0",
    "dependencies": ["ydotool", "ydotoold"],
    "compositors": ["any"],
    "permissions": ["settings_read", "settings_write", "process"]
}
```

## File layout

```
plugins/virtualkeyboard/
├── plugin.json
├── StartupCheck.qml          # ydotool binary + ydotoold socket reachability
├── Ydotool.js                 # key press/release/shiftMode state (ported from Ydotool.qml service)
├── VirtualKeyboardDaemon.qml   # IpcHandler(toggle/open/close) + owns the PanelWindow via LazyLoader
├── KeyboardWindow.qml          # PanelWindow, bottom-docked, pin/hide controls, blur+card
├── KeyboardLayout.qml          # ColumnLayout of key rows, ported from OskContent.qml
├── Key.qml                     # one key: sizing multipliers, shift/caps label swap, press/release → Ydotool
├── layout-us.js                # ported from layouts.js, US entry only
├── VirtualKeyboardWidget.qml    # DankBar pill (PluginComponent), optional
├── VirtualKeyboardSettings.qml  # pinnedOnStartup toggle
├── README.md
├── screenshots/
│   ├── keyboard.png
│   └── pill.png
└── tests/
    └── tst_layout.qml          # sizing-multiplier / shift-label lookup, same spirit as dankmenu's tests
```

## Daemon (`VirtualKeyboardDaemon.qml`)

Same shape as `DankMenuDaemon.qml`: a `PluginComponent`-free `Item` (daemon
surfaces don't wrap in `PluginComponent`, per the composite-plugin contract)
owning:
- A `LazyLoader` wrapping `KeyboardWindow` — built on first open, not at
  shell startup, same reasoning as dankMenu's menu window.
- `IpcHandler { target: "virtualKeyboard" }` with `toggle()`, `open()`,
  `close()`, all returning short status strings like dankMenu's.
- The pinned setting, read via `pluginService.loadPluginData`.
- Global var `virtualKeyboard.open` (bool) so the optional bar widget can
  reflect state without its own IPC round-trip.

## Window (`KeyboardWindow.qml`)

`PanelWindow`, `anchors { bottom; left; right }`, `WlrLayershell.layer:
WlrLayer.Overlay`. `exclusiveZone` is the card height when pinned, `0`
otherwise (reserves screen space only when pinned, same as upstream).
`mask` set to the visible card region so clicks pass through the transparent
letterboxing on either side — this overlay doesn't need a click-to-dismiss
backdrop the way dankMenu's centered modal does, since it doesn't obscure the
rest of the screen.

Card: `StyledRect`, `Theme.readableSurface` background, `Theme.outlineVariant`
border, `Theme.cornerRadius`, with `WindowBlur` behind it tracking its rect —
same treatment as dankMenu's card. Two control buttons top-left (pin,
hide) using the same `DankActionButton`/toggle-state pattern DMS uses
elsewhere, replacing upstream's bespoke `GroupButton`.

Esc closes when the card has focus, matching upstream.

## Keys (`Key.qml`, `layout-us.js`)

Direct port of `OskKey.qml`'s sizing table (width/height multiplier per
`shape`: normal/fn/tab/caps/shift/control/space/expand) and `layouts.js`'s US
entry (label/labelShift/keycode/shape per key, fn row included). Visual
swap only:
- `StyledRect` + `StyledText` instead of `RippleButton`/upstream's
  `contentItem`.
- `Theme.surfaceContainerHigh` idle, `Theme.primaryContainer` /
  `Theme.primary`-tinted text when a modifier key is latched (shift down,
  caps-lock via double-tap-shift within 300ms — same timer logic as
  `capsLockTimer` in `OskKey.qml`).
- Backspace/Enter keys render `DankIcon` (`backspace` / `keyboard_return`)
  instead of upstream's icon-font text trick.
- Press/release wired to `Ydotool.press(keycode)` / `Ydotool.release(keycode)`
  exactly as upstream; modifier chording (shift held while another key taps)
  works the same way because release only fires when the finger/pointer
  actually lifts off the modifier key.

## Widget (`VirtualKeyboardWidget.qml`)

Optional DankBar pill via `PluginComponent`, `horizontalBarPill` +
`verticalBarPill`, `keyboard` icon, toggling `virtualKeyboard.open` global
var on click (`pillClickAction`, not a popout — clicking should open/close
the keyboard itself, not a menu). Not added to any bar section by default;
users who don't want it in the bar simply never add it — the daemon and IPC
work identically either way.

## Settings (`VirtualKeyboardSettings.qml`)

One `ToggleSetting`: `pinnedOnStartup` (default `false`). That's the entire
v1 settings surface — matches the "US only" scope decision.

## Testing

- `tests/tst_layout.qml`: verify sizing-multiplier lookup for each `shape`,
  and shift/caps label resolution (`labelShift` fallback to `label`), same
  style as dankmenu's `tst_menumodel.qml`.
- Manual: install into `~/.config/DankMaterialShell/plugins/virtualKeyboard`
  symlinked from this repo (per the README's "from a clone" flow), enable in
  DMS Settings → Plugins, verify:
  - `ydotool` missing → startupCheck blocks enable with actionable error.
  - IPC toggle opens/closes the panel.
  - A compositor keybind (documented for niri and Hyprland in the plugin's
    README) opens/closes it.
  - Typing into a text field actually inputs characters, including a
    shift-chorded capital letter and a held-Ctrl combo.
  - Pin reserves screen space; unpin does not.
  - Optional bar pill, once manually added to `dankBarLeftWidgets`, toggles
    the same window.

## Rollout

1. Implement plugin, install via symlink into `~/.config/DankMaterialShell/plugins/virtualKeyboard`
   (this repo cloned already at `~/src` per README convention — or, per this
   task, the working copy is *at* `../../sitolamix`'s sibling, so symlink
   from this working tree directly).
2. Manually verify per the Testing section above on this machine.
3. Screenshot the keyboard (open, docked) and the bar pill for
   `plugins/virtualkeyboard/screenshots/` and the root README's plugin table.
4. Write `plugins/virtualkeyboard/README.md` (component/type/needs, keybind
   snippets for niri + Hyprland, ydotool/ydotoold setup note) following
   dankmenu's and mouthguard's README shape.
5. Update root `README.md`: add to the plugin table, the install list
   (`dms plugins install virtualKeyboard`), and the two-column screenshot
   grid.
6. Commit.
7. Only after manual verification passes: open the PR against
   `AvengeMedia/dms-plugin-registry` adding this plugin, per the existing two
   plugins' registry entries as a template.
