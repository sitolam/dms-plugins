# Virtual Keyboard Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `plugins/virtualkeyboard/`, a DMS composite plugin (`id: virtualKeyboard`) that shows an on-screen keyboard overlay, toggled by IPC (bindable to any compositor keybind) or an optional DankBar pill — install it locally, verify it end to end, document it, then open the registry PR.

**Architecture:** A daemon surface (`VirtualKeyboardDaemon.qml`) owns an `Ydotool.qml` key-injection helper and a lazily-built `KeyboardWindow.qml` (bottom-docked `PanelWindow`), and exposes `IpcHandler { target: "virtualKeyboard" }` (`toggle`/`open`/`close`). An optional bar-pill widget surface (`VirtualKeyboardWidget.qml`) reads/writes the same `PluginService` global var (`"open"`) so bar, IPC, and window state always agree, without the widget ever being required. Key sizing/label logic and the US QWERTY layout are pure `.pragma library` JS modules (`KeyShape.js`, `layout-us.js`), unit-tested with `qmltestrunner` the same way `dankmenu`'s `MenuModel.js`/`Search.js` are.

**Tech Stack:** QML (Quickshell/DMS plugin API), `.pragma library` JS modules, `qmltestrunner`, `ydotool`/`ydotoold` for key injection.

**Spec:** `docs/superpowers/specs/2026-08-25-virtual-keyboard-design.md`

## Global Constraints

- Plugin id: `virtualKeyboard` (camelCase, per `plugin-schema.json`'s `^[a-zA-Z][a-zA-Z0-9]*$`).
- `requires_dms: ">=1.5.0"` (matches the other two plugins in this repo).
- `license: "MIT"`, `author: "sitolam"` (matches the other two plugins).
- US QWERTY only for v1 — no other layouts, no layout-selection setting.
- Key injection via `ydotool` (raw keycode press/release), never `wtype` — see spec's "Why ydotool, not wtype".
- No plugin file references anything outside `plugins/virtualkeyboard/` (matches the root README's "neither references a path above its own directory").
- Bar pill is opt-in: composite plugins are not auto-added to any bar section, and nothing in this plugin may add itself to one.
- Tests run via `qmltestrunner -input tests/tst_<name>.qml`, one file per run, matching `dankmenu`'s existing tests.

---

## Reference material (already fetched, re-derive nothing)

- DMS plugin API + Theme docs live in the installed shell at
  `/nix/store/sfbgl5f54y4nvyj87r45a4msf7m5myzj-dms-shell-1.5.3/share/quickshell/dms/PLUGINS/README.md`
  and `.../PLUGINS/THEME_REFERENCE.md`. `Common/Theme.qml` in that same tree
  is the authoritative property list if something below is wrong.
- `plugins/dankmenu/` in this repo is the closest sibling plugin (daemon
  surface, `PanelWindow` overlay, `IpcHandler`, `qmltestrunner` tests) —
  when in doubt about a convention not nailed down below, match dankmenu.
- Upstream reference (end-4/dots-hyprland, `dots/.config/quickshell/ii/modules/ii/onScreenKeyboard/`):
  `OnScreenKeyboard.qml`, `OskContent.qml`, `OskKey.qml`, `layouts.js` — the
  behavior this plugin ports (sizing multipliers, shift/caps-lock state
  machine, keycodes). Already downloaded to the scratchpad this session;
  the exact keycode/shape/label data needed is inlined in Task 3 below.

---

### Task 1: Plugin scaffold + manifest

**Files:**
- Create: `plugins/virtualkeyboard/plugin.json`
- Create: `plugins/virtualkeyboard/.keep`

**Interfaces:**
- Produces: the manifest every later task's component files must match by filename (`VirtualKeyboardDaemon.qml`, `VirtualKeyboardWidget.qml`, `VirtualKeyboardSettings.qml`, `StartupCheck.qml`).

- [ ] **Step 1: Create the directory and an empty `.keep`**

```bash
mkdir -p plugins/virtualkeyboard/tests plugins/virtualkeyboard/screenshots
touch plugins/virtualkeyboard/.keep
```

- [ ] **Step 2: Write `plugin.json`**

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
    "dependencies": ["ydotool"],
    "compositors": ["any"],
    "permissions": ["settings_read", "settings_write", "process"]
}
```

- [ ] **Step 3: Validate the manifest against the schema**

```bash
DMS=/nix/store/sfbgl5f54y4nvyj87r45a4msf7m5myzj-dms-shell-1.5.3/share/quickshell/dms
python3 -c "
import json, jsonschema
schema = json.load(open('$DMS/PLUGINS/plugin-schema.json'))
manifest = json.load(open('plugins/virtualkeyboard/plugin.json'))
jsonschema.validate(manifest, schema)
print('OK')
"
```

Expected: `OK`. If `jsonschema` isn't installed, `nix-shell -p python3Packages.jsonschema --run '...'` the same command instead of skipping validation.

- [ ] **Step 4: Commit**

```bash
git add plugins/virtualkeyboard/plugin.json plugins/virtualkeyboard/.keep
git commit -m "feat(virtualkeyboard): add plugin manifest"
```

---

### Task 2: `KeyShape.js` — sizing and label logic (TDD)

**Files:**
- Create: `plugins/virtualkeyboard/KeyShape.js`
- Test: `plugins/virtualkeyboard/tests/tst_keyshape.qml`

**Interfaces:**
- Produces: `KeyShape.widthMultiplier(shape: string): number`, `KeyShape.heightMultiplier(shape: string): number`, `KeyShape.labelFor(keyData: {label, labelShift?, labelCaps?}, shiftMode: 0|1|2): string` — consumed by Task 5 (`Key.qml`).

- [ ] **Step 1: Write the failing test**

```qml
// plugins/virtualkeyboard/tests/tst_keyshape.qml
import QtQuick
import QtTest
import "../KeyShape.js" as KeyShape

TestCase {
    name: "KeyShape"

    function test_width_multiplier_known_shapes() {
        compare(KeyShape.widthMultiplier("tab"), 1.6);
        compare(KeyShape.widthMultiplier("caps"), 1.9);
        compare(KeyShape.widthMultiplier("shift"), 2.5);
        compare(KeyShape.widthMultiplier("control"), 1.3);
        compare(KeyShape.widthMultiplier("normal"), 1);
    }

    function test_width_multiplier_unknown_shape_defaults_to_one() {
        compare(KeyShape.widthMultiplier("bogus"), 1);
    }

    function test_height_multiplier_fn_is_shorter() {
        compare(KeyShape.heightMultiplier("fn"), 0.7);
        compare(KeyShape.heightMultiplier("normal"), 1);
    }

    function test_label_for_plain_mode_uses_base_label() {
        var key = {label: "a", labelShift: "A"};
        compare(KeyShape.labelFor(key, 0), "a");
    }

    function test_label_for_shift_mode_uses_shift_label() {
        var key = {label: "a", labelShift: "A"};
        compare(KeyShape.labelFor(key, 1), "A");
    }

    function test_label_for_shift_mode_falls_back_without_shift_label() {
        var key = {label: "Esc"};
        compare(KeyShape.labelFor(key, 1), "Esc");
    }

    function test_label_for_caps_mode_prefers_caps_label() {
        var key = {label: "Shift", labelShift: "Shift", labelCaps: "Caps"};
        compare(KeyShape.labelFor(key, 2), "Caps");
    }

    function test_label_for_caps_mode_falls_back_to_shift_label() {
        var key = {label: "a", labelShift: "A"};
        compare(KeyShape.labelFor(key, 2), "A");
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
qmltestrunner -input plugins/virtualkeyboard/tests/tst_keyshape.qml
```

Expected: FAIL — `../KeyShape.js` does not exist.

- [ ] **Step 3: Write `KeyShape.js`**

```js
.pragma library

// Per-shape size multipliers and shift/caps label resolution, ported from
// end-4/dots-hyprland's OskKey.qml widthMultiplier/heightMultiplier tables
// and its `Ydotool.shiftMode` label-selection ternary.

var WIDTH_MULTIPLIER = {
    normal: 1,
    fn: 1,
    tab: 1.6,
    caps: 1.9,
    shift: 2.5,
    control: 1.3,
    space: 1,
    expand: 1
};

var HEIGHT_MULTIPLIER = {
    normal: 1,
    fn: 0.7,
    tab: 1,
    caps: 1,
    shift: 1,
    control: 1,
    space: 1,
    expand: 1
};

function widthMultiplier(shape) {
    return WIDTH_MULTIPLIER.hasOwnProperty(shape) ? WIDTH_MULTIPLIER[shape] : 1;
}

function heightMultiplier(shape) {
    return HEIGHT_MULTIPLIER.hasOwnProperty(shape) ? HEIGHT_MULTIPLIER[shape] : 1;
}

// shiftMode: 0 = plain, 1 = shift held, 2 = caps-lock latched.
function labelFor(keyData, shiftMode) {
    if (shiftMode === 2)
        return keyData.labelCaps || keyData.labelShift || keyData.label;
    if (shiftMode === 1)
        return keyData.labelShift || keyData.label;
    return keyData.label;
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
qmltestrunner -input plugins/virtualkeyboard/tests/tst_keyshape.qml
```

Expected: PASS, 8 passed.

- [ ] **Step 5: Commit**

```bash
git add plugins/virtualkeyboard/KeyShape.js plugins/virtualkeyboard/tests/tst_keyshape.qml
git commit -m "feat(virtualkeyboard): add key sizing/label logic"
```

---

### Task 3: `layout-us.js` — US QWERTY layout data (TDD)

**Files:**
- Create: `plugins/virtualkeyboard/layout-us.js`
- Test: `plugins/virtualkeyboard/tests/tst_layout_us.qml`

**Interfaces:**
- Produces: `LayoutUs.rows: Array<Array<{keytype: "normal"|"modkey"|"spacer", label: string, labelShift?: string, labelCaps?: string, shape: string, keycode?: number}>>` — consumed by Task 6 (`KeyboardLayout.qml`).

- [ ] **Step 1: Write the failing test**

```qml
// plugins/virtualkeyboard/tests/tst_layout_us.qml
import QtQuick
import QtTest
import "../layout-us.js" as LayoutUs

TestCase {
    name: "LayoutUs"

    function test_has_six_rows() {
        compare(LayoutUs.rows.length, 6);
    }

    function test_function_row_starts_with_esc() {
        compare(LayoutUs.rows[0][0].label, "Esc");
        compare(LayoutUs.rows[0][0].shape, "fn");
        compare(LayoutUs.rows[0].length, 15);
    }

    function findByLabel(row, label) {
        for (var i = 0; i < row.length; i++)
            if (row[i].label === label)
                return row[i];
        return null;
    }

    function test_letter_a_keycode_and_shift_label() {
        var a = findByLabel(LayoutUs.rows[3], "a");
        compare(a.keycode, 30);
        compare(a.labelShift, "A");
        compare(a.shape, "normal");
    }

    function test_space_key_shape_and_keycode() {
        var row = LayoutUs.rows[5];
        var space = findByLabel(row, "Space");
        compare(space.keycode, 57);
        compare(space.shape, "space");
    }

    function test_shift_key_is_modkey_type() {
        var row = LayoutUs.rows[4];
        compare(row[0].keytype, "modkey");
        compare(row[0].shape, "shift");
        compare(row[0].keycode, 42);
        compare(row[0].labelCaps, "Caps");
    }

    function test_right_shift_shares_shift_keycode_family() {
        var row = LayoutUs.rows[4];
        var rightShift = row[row.length - 1];
        compare(rightShift.keytype, "modkey");
        compare(rightShift.keycode, 54);
    }

    function test_backspace_and_enter_expand_the_row() {
        var backspace = findByLabel(LayoutUs.rows[1], "Backspace");
        compare(backspace.shape, "expand");
        compare(backspace.keycode, 14);
        var enter = findByLabel(LayoutUs.rows[3], "Enter");
        compare(enter.shape, "expand");
        compare(enter.keycode, 28);
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
qmltestrunner -input plugins/virtualkeyboard/tests/tst_layout_us.qml
```

Expected: FAIL — `../layout-us.js` does not exist.

- [ ] **Step 3: Write `layout-us.js`**

Ported verbatim (keycodes, shapes, labels) from upstream's `layouts.js`
`"English (US)"` entry — the values below are the same Linux
`input-event-codes.h` keycodes upstream uses, so ydotool driving them
produces the same keypress upstream's OSK does.

```js
.pragma library

// US QWERTY, full layout including the function row. Keycodes are Linux
// input-event-codes (see /usr/include/linux/input-event-codes.h), the same
// ones ydotool expects. Ported from end-4/dots-hyprland's layouts.js
// "English (US)" entry.

var rows = [
    [
        {keytype: "normal", label: "Esc", shape: "fn", keycode: 1},
        {keytype: "normal", label: "F1", shape: "fn", keycode: 59},
        {keytype: "normal", label: "F2", shape: "fn", keycode: 60},
        {keytype: "normal", label: "F3", shape: "fn", keycode: 61},
        {keytype: "normal", label: "F4", shape: "fn", keycode: 62},
        {keytype: "normal", label: "F5", shape: "fn", keycode: 63},
        {keytype: "normal", label: "F6", shape: "fn", keycode: 64},
        {keytype: "normal", label: "F7", shape: "fn", keycode: 65},
        {keytype: "normal", label: "F8", shape: "fn", keycode: 66},
        {keytype: "normal", label: "F9", shape: "fn", keycode: 67},
        {keytype: "normal", label: "F10", shape: "fn", keycode: 68},
        {keytype: "normal", label: "F11", shape: "fn", keycode: 87},
        {keytype: "normal", label: "F12", shape: "fn", keycode: 88},
        {keytype: "normal", label: "PrtSc", shape: "fn", keycode: 99},
        {keytype: "normal", label: "Del", shape: "fn", keycode: 111}
    ],
    [
        {keytype: "normal", label: "`", labelShift: "~", shape: "normal", keycode: 41},
        {keytype: "normal", label: "1", labelShift: "!", shape: "normal", keycode: 2},
        {keytype: "normal", label: "2", labelShift: "@", shape: "normal", keycode: 3},
        {keytype: "normal", label: "3", labelShift: "#", shape: "normal", keycode: 4},
        {keytype: "normal", label: "4", labelShift: "$", shape: "normal", keycode: 5},
        {keytype: "normal", label: "5", labelShift: "%", shape: "normal", keycode: 6},
        {keytype: "normal", label: "6", labelShift: "^", shape: "normal", keycode: 7},
        {keytype: "normal", label: "7", labelShift: "&", shape: "normal", keycode: 8},
        {keytype: "normal", label: "8", labelShift: "*", shape: "normal", keycode: 9},
        {keytype: "normal", label: "9", labelShift: "(", shape: "normal", keycode: 10},
        {keytype: "normal", label: "0", labelShift: ")", shape: "normal", keycode: 11},
        {keytype: "normal", label: "-", labelShift: "_", shape: "normal", keycode: 12},
        {keytype: "normal", label: "=", labelShift: "+", shape: "normal", keycode: 13},
        {keytype: "normal", label: "Backspace", shape: "expand", keycode: 14}
    ],
    [
        {keytype: "normal", label: "Tab", shape: "tab", keycode: 15},
        {keytype: "normal", label: "q", labelShift: "Q", shape: "normal", keycode: 16},
        {keytype: "normal", label: "w", labelShift: "W", shape: "normal", keycode: 17},
        {keytype: "normal", label: "e", labelShift: "E", shape: "normal", keycode: 18},
        {keytype: "normal", label: "r", labelShift: "R", shape: "normal", keycode: 19},
        {keytype: "normal", label: "t", labelShift: "T", shape: "normal", keycode: 20},
        {keytype: "normal", label: "y", labelShift: "Y", shape: "normal", keycode: 21},
        {keytype: "normal", label: "u", labelShift: "U", shape: "normal", keycode: 22},
        {keytype: "normal", label: "i", labelShift: "I", shape: "normal", keycode: 23},
        {keytype: "normal", label: "o", labelShift: "O", shape: "normal", keycode: 24},
        {keytype: "normal", label: "p", labelShift: "P", shape: "normal", keycode: 25},
        {keytype: "normal", label: "[", labelShift: "{", shape: "normal", keycode: 26},
        {keytype: "normal", label: "]", labelShift: "}", shape: "normal", keycode: 27},
        {keytype: "normal", label: "\\", labelShift: "|", shape: "expand", keycode: 43}
    ],
    [
        {keytype: "spacer", label: "", shape: "empty"},
        {keytype: "spacer", label: "", shape: "empty"},
        {keytype: "normal", label: "a", labelShift: "A", shape: "normal", keycode: 30},
        {keytype: "normal", label: "s", labelShift: "S", shape: "normal", keycode: 31},
        {keytype: "normal", label: "d", labelShift: "D", shape: "normal", keycode: 32},
        {keytype: "normal", label: "f", labelShift: "F", shape: "normal", keycode: 33},
        {keytype: "normal", label: "g", labelShift: "G", shape: "normal", keycode: 34},
        {keytype: "normal", label: "h", labelShift: "H", shape: "normal", keycode: 35},
        {keytype: "normal", label: "j", labelShift: "J", shape: "normal", keycode: 36},
        {keytype: "normal", label: "k", labelShift: "K", shape: "normal", keycode: 37},
        {keytype: "normal", label: "l", labelShift: "L", shape: "normal", keycode: 38},
        {keytype: "normal", label: ";", labelShift: ":", shape: "normal", keycode: 39},
        {keytype: "normal", label: "'", labelShift: "\"", shape: "normal", keycode: 40},
        {keytype: "normal", label: "Enter", shape: "expand", keycode: 28}
    ],
    [
        {keytype: "modkey", label: "Shift", labelShift: "Shift", labelCaps: "Caps", shape: "shift", keycode: 42},
        {keytype: "normal", label: "z", labelShift: "Z", shape: "normal", keycode: 44},
        {keytype: "normal", label: "x", labelShift: "X", shape: "normal", keycode: 45},
        {keytype: "normal", label: "c", labelShift: "C", shape: "normal", keycode: 46},
        {keytype: "normal", label: "v", labelShift: "V", shape: "normal", keycode: 47},
        {keytype: "normal", label: "b", labelShift: "B", shape: "normal", keycode: 48},
        {keytype: "normal", label: "n", labelShift: "N", shape: "normal", keycode: 49},
        {keytype: "normal", label: "m", labelShift: "M", shape: "normal", keycode: 50},
        {keytype: "normal", label: ",", labelShift: "<", shape: "normal", keycode: 51},
        {keytype: "normal", label: ".", labelShift: ">", shape: "normal", keycode: 52},
        {keytype: "normal", label: "/", labelShift: "?", shape: "normal", keycode: 53},
        {keytype: "modkey", label: "Shift", labelShift: "Shift", labelCaps: "Caps", shape: "expand", keycode: 54}
    ],
    [
        {keytype: "modkey", label: "Ctrl", shape: "control", keycode: 29},
        {keytype: "modkey", label: "Alt", shape: "normal", keycode: 56},
        {keytype: "normal", label: "Space", shape: "space", keycode: 57},
        {keytype: "modkey", label: "Alt", shape: "normal", keycode: 100},
        {keytype: "normal", label: "Menu", shape: "normal", keycode: 139},
        {keytype: "modkey", label: "Ctrl", shape: "control", keycode: 97}
    ]
];
```

- [ ] **Step 4: Run it to verify it passes**

```bash
qmltestrunner -input plugins/virtualkeyboard/tests/tst_layout_us.qml
```

Expected: PASS, 7 passed.

- [ ] **Step 5: Commit**

```bash
git add plugins/virtualkeyboard/layout-us.js plugins/virtualkeyboard/tests/tst_layout_us.qml
git commit -m "feat(virtualkeyboard): add US QWERTY layout data"
```

---

### Task 4: `Ydotool.qml` — key injection + modifier state

**Files:**
- Create: `plugins/virtualkeyboard/Ydotool.qml`

**Interfaces:**
- Consumes: nothing beyond `Quickshell.Io.Process`.
- Produces: `press(keycode: int)`, `release(keycode: int)`, `releaseShiftKeys()`, `releaseAllKeys()`, `property int shiftMode` (0/1/2, auto-emits `shiftModeChanged`), `readonly property var shiftKeycodes: [42, 54]` — consumed by Task 5 (`Key.qml`) and Task 9 (`VirtualKeyboardDaemon.qml`, which calls `releaseAllKeys()` on close).

Not unit-tested: this component's entire job is spawning real `ydotool`
processes, which `qmltestrunner` can't meaningfully assert on without a real
`ydotoold` session (and would leave stray keypresses if it ran on a
developer's actual desktop). It's exercised by the manual end-to-end
checklist in Task 12, the same way dankmenu's `actionProcess` (`bash -lc`
spawner in `MenuWindow.qml`) has no unit test either.

- [ ] **Step 1: Write `Ydotool.qml`**

```qml
import QtQuick
import Quickshell.Io

Item {
    id: root

    // 0 = plain, 1 = shift held (single tap, released after the next normal
    // key or a second shift tap outside the caps-lock window), 2 = caps-lock
    // latched (second shift tap within the window).
    property int shiftMode: 0
    readonly property var shiftKeycodes: [42, 54]

    function press(keycode) {
        spawn(keycode + ":1")
    }

    function release(keycode) {
        spawn(keycode + ":0")
    }

    function releaseShiftKeys() {
        root.shiftMode = 0
        for (var i = 0; i < shiftKeycodes.length; i++)
            release(shiftKeycodes[i])
    }

    function releaseAllKeys() {
        releaseShiftKeys()
    }

    function spawn(arg) {
        var proc = ydotoolProcess.createObject(root, {keyArg: arg})
        proc.running = true
    }

    Component {
        id: ydotoolProcess

        Process {
            property string keyArg: ""
            command: ["ydotool", "key", keyArg]
            onExited: exitCode => {
                if (exitCode !== 0)
                    console.warn("virtualKeyboard: ydotool exited", exitCode, "-", keyArg)
                destroy()
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/virtualkeyboard/Ydotool.qml
git commit -m "feat(virtualkeyboard): add ydotool key-injection helper"
```

---

### Task 5: `Key.qml` — single key, sizing, press/release/caps-lock state machine

**Files:**
- Create: `plugins/virtualkeyboard/Key.qml`

**Interfaces:**
- Consumes: `KeyShape.widthMultiplier`/`heightMultiplier`/`labelFor` (Task 2); `ydotool.press/release/releaseShiftKeys/shiftMode/shiftKeycodes` (Task 4).
- Produces: `Key { required property var keyData; required property var ydotool }` — one row entry — consumed by Task 6 (`KeyboardLayout.qml`).

Not unit-tested for the same reason as Task 4 (real press/release side
effects); verified manually in Task 12.

- [ ] **Step 1: Write `Key.qml`**

```qml
import QtQuick
import qs.Common
import qs.Widgets
import "KeyShape.js" as KeyShape

StyledRect {
    id: root

    required property var keyData
    required property var ydotool

    readonly property string keytype: keyData.keytype
    readonly property string shape: keyData.shape
    readonly property int keycode: keyData.keycode || 0
    readonly property bool isEmpty: shape === "empty"
    readonly property bool isShiftKey: ydotool.shiftKeycodes.indexOf(keycode) !== -1
    readonly property bool isBackspace: keyData.label === "Backspace"
    readonly property bool isEnter: keyData.label === "Enter"
    readonly property bool latched: (isShiftKey && ydotool.shiftMode > 0) || (keytype === "modkey" && !isShiftKey && modToggled)

    // Sticky modkeys (Ctrl/Alt) latch on the first tap and release on the
    // second, same as upstream's OskKey "modkey" branch.
    property bool modToggled: false
    property bool isPressed: false

    readonly property real baseWidth: 45
    readonly property real baseHeight: 45

    width: baseWidth * KeyShape.widthMultiplier(shape)
    height: baseHeight * KeyShape.heightMultiplier(shape)
    visible: !isEmpty
    enabled: !isEmpty
    radius: Theme.cornerRadius
    color: isPressed ? Theme.primaryPressed : latched ? Theme.primaryContainer : Theme.surfaceContainerHigh

    DankIcon {
        anchors.centerIn: parent
        visible: root.isBackspace || root.isEnter
        name: root.isBackspace ? "backspace" : "keyboard_return"
        size: Theme.iconSize
        color: root.latched ? Theme.primary : Theme.surfaceText
    }

    StyledText {
        anchors.centerIn: parent
        visible: !root.isBackspace && !root.isEnter
        text: KeyShape.labelFor(root.keyData, root.isShiftKey ? root.ydotool.shiftMode : 0)
        font.pixelSize: root.shape === "fn" ? Theme.fontSizeSmall : Theme.fontSizeMedium
        color: root.latched ? Theme.primary : Theme.surfaceText
    }

    Timer {
        id: capsLockTimer
        interval: 300
        property bool hasStarted: false
        property bool canCaps: false
        onTriggered: canCaps = false
        function startWaiting() {
            hasStarted = true
            canCaps = true
            restart()
        }
    }

    Connections {
        target: root.ydotool
        function onShiftModeChanged() {
            if (root.ydotool.shiftMode === 0)
                capsLockTimer.hasStarted = false
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.isEmpty
        onPressed: {
            root.isPressed = true
            root.ydotool.press(root.keycode)
            if (root.isShiftKey && root.ydotool.shiftMode === 0)
                root.ydotool.shiftMode = 1
        }
        onReleased: {
            root.isPressed = false
            if (root.keytype === "normal") {
                root.ydotool.release(root.keycode)
                if (root.ydotool.shiftMode === 1)
                    root.ydotool.releaseShiftKeys()
            } else if (root.isShiftKey) {
                if (root.ydotool.shiftMode === 1) {
                    if (!capsLockTimer.hasStarted)
                        capsLockTimer.startWaiting()
                    else if (capsLockTimer.canCaps)
                        root.ydotool.shiftMode = 2
                    else
                        root.ydotool.releaseShiftKeys()
                } else if (root.ydotool.shiftMode === 2) {
                    root.ydotool.releaseShiftKeys()
                }
            } else if (root.keytype === "modkey") {
                root.modToggled = !root.modToggled
                if (!root.modToggled)
                    root.ydotool.release(root.keycode)
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/virtualkeyboard/Key.qml
git commit -m "feat(virtualkeyboard): add single-key component"
```

---

### Task 6: `KeyboardLayout.qml` — row layout over `layout-us.js`

**Files:**
- Create: `plugins/virtualkeyboard/KeyboardLayout.qml`

**Interfaces:**
- Consumes: `LayoutUs.rows` (Task 3), `Key` (Task 5, resolved by implicit sibling-file import — same pattern as `MenuWindow.qml` using `MenuList` with no explicit import).
- Produces: `KeyboardLayout { required property var ydotool }` — consumed by Task 7 (`KeyboardWindow.qml`).

- [ ] **Step 1: Write `KeyboardLayout.qml`**

```qml
import QtQuick
import QtQuick.Layouts
import "layout-us.js" as LayoutUs

ColumnLayout {
    id: root

    required property var ydotool

    spacing: 6

    Repeater {
        model: LayoutUs.rows

        delegate: RowLayout {
            id: keyRow
            required property var modelData
            spacing: 6

            Repeater {
                model: keyRow.modelData

                delegate: Key {
                    id: keyDelegate
                    required property var modelData
                    keyData: modelData
                    ydotool: root.ydotool
                    Layout.fillWidth: modelData.shape === "space" || modelData.shape === "expand"
                }
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/virtualkeyboard/KeyboardLayout.qml
git commit -m "feat(virtualkeyboard): add keyboard row layout"
```

---

### Task 7: `KeyboardWindow.qml` — bottom-docked overlay panel

**Files:**
- Create: `plugins/virtualkeyboard/KeyboardWindow.qml`

**Interfaces:**
- Consumes: `KeyboardLayout` (Task 6).
- Produces: `KeyboardWindow { required property var ydotool; property bool keyboardVisible; property bool pinned; signal keyboardClosed; function show(); function hide() }` — consumed by Task 9 (`VirtualKeyboardDaemon.qml`).

- [ ] **Step 1: Write `KeyboardWindow.qml`**

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets

PanelWindow {
    id: root

    required property var ydotool
    property bool keyboardVisible: false
    property bool pinned: false

    signal keyboardClosed

    function show() {
        keyboardVisible = true
    }

    function hide() {
        keyboardVisible = false
        keyboardClosed()
    }

    visible: keyboardVisible
    color: "transparent"

    anchors {
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: root.pinned ? implicitHeight - Theme.spacingL : 0
    implicitWidth: card.width
    implicitHeight: card.height + Theme.spacingL * 2

    WlrLayershell.namespace: "dms:plugins:virtualKeyboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.keyboardVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        item: card
    }

    WindowBlur {
        targetWindow: root
        blurX: card.x
        blurY: card.y
        blurWidth: root.keyboardVisible ? card.width : 0
        blurHeight: root.keyboardVisible ? card.height : 0
        blurRadius: Theme.cornerRadius
    }

    FocusScope {
        anchors.fill: parent
        focus: root.keyboardVisible

        Keys.onEscapePressed: root.hide()

        StyledRect {
            id: card

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spacingL
            width: content.implicitWidth + Theme.spacingL * 2
            height: content.implicitHeight + Theme.spacingL * 2
            radius: Theme.cornerRadius
            color: Theme.readableSurface
            border.width: 1
            border.color: Theme.outlineVariant

            RowLayout {
                id: content
                anchors.centerIn: parent
                spacing: Theme.spacingM

                ColumnLayout {
                    spacing: Theme.spacingXS

                    DankActionButton {
                        iconName: "keep"
                        iconColor: root.pinned ? Theme.primary : Theme.surfaceText
                        tooltipText: root.pinned ? "Unpin" : "Pin"
                        onClicked: root.pinned = !root.pinned
                    }

                    DankActionButton {
                        iconName: "keyboard_hide"
                        tooltipText: "Hide"
                        onClicked: root.hide()
                    }
                }

                Rectangle {
                    Layout.fillHeight: true
                    Layout.topMargin: Theme.spacingM
                    Layout.bottomMargin: Theme.spacingM
                    implicitWidth: 1
                    color: Theme.outlineVariant
                }

                KeyboardLayout {
                    ydotool: root.ydotool
                }
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/virtualkeyboard/KeyboardWindow.qml
git commit -m "feat(virtualkeyboard): add bottom-docked keyboard window"
```

---

### Task 8: `StartupCheck.qml` — ydotool dependency gate

**Files:**
- Create: `plugins/virtualkeyboard/StartupCheck.qml`

**Interfaces:**
- Consumes: `Proc.runCommand` (`qs.Common`, documented in `PLUGINS/README.md`'s "Running External Commands" section).
- Produces: the `check(done)` contract the plugin manifest's `startupCheck` field points at.

- [ ] **Step 1: Write `StartupCheck.qml`**

```qml
import QtQuick
import qs.Common

QtObject {
    function check(done) {
        Proc.runCommand("virtualKeyboard.depCheck", ["sh", "-c", "command -v ydotool"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null)
                return
            }
            done({
                title: "ydotool is required",
                details: "virtualKeyboard types by driving ydotool, which is not on your PATH.\n\nInstall ydotool, then make sure its ydotoold service is enabled and running (e.g. `systemctl --user enable --now ydotool` or your distro's equivalent — some distros run ydotoold as a system service instead), then re-enable this plugin."
            })
        })
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/virtualkeyboard/StartupCheck.qml
git commit -m "feat(virtualkeyboard): add ydotool startup dependency check"
```

---

### Task 9: `VirtualKeyboardDaemon.qml` — daemon surface, IPC, global-var sync

**Files:**
- Create: `plugins/virtualkeyboard/VirtualKeyboardDaemon.qml`

**Interfaces:**
- Consumes: `Ydotool` (Task 4), `KeyboardWindow` (Task 7), `PluginService.getGlobalVar/setGlobalVar` and `pluginService.loadPluginData` (injected by `PluginComponent`).
- Produces: `IpcHandler { target: "virtualKeyboard" }` with `toggle()/open()/close()`; global var `<pluginId>.open` (bool) — consumed by Task 10 (`VirtualKeyboardWidget.qml`).

- [ ] **Step 1: Write `VirtualKeyboardDaemon.qml`**

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property bool pinnedOnStartup: pluginService ? pluginService.loadPluginData(pluginId, "pinnedOnStartup", false) : false
    readonly property bool keyboardOpen: windowLoader.item ? windowLoader.item.keyboardVisible : false

    Ydotool {
        id: ydotool
    }

    LazyLoader {
        id: windowLoader
        loading: false

        KeyboardWindow {
            ydotool: ydotool
            pinned: root.pinnedOnStartup
            onKeyboardClosed: {
                windowLoader.loading = false
                PluginService.setGlobalVar(root.pluginId, "open", false)
                ydotool.releaseAllKeys()
            }
        }
    }

    function openKeyboard() {
        windowLoader.loading = true
        windowLoader.item.show()
        PluginService.setGlobalVar(root.pluginId, "open", true)
    }

    function closeKeyboard() {
        if (windowLoader.item)
            windowLoader.item.hide()
    }

    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId !== root.pluginId || varName !== "open")
                return
            const wantOpen = PluginService.getGlobalVar(root.pluginId, "open", false)
            if (wantOpen && !root.keyboardOpen)
                root.openKeyboard()
            else if (!wantOpen && root.keyboardOpen)
                root.closeKeyboard()
        }
    }

    IpcHandler {
        target: "virtualKeyboard"

        function toggle(): string {
            if (root.keyboardOpen) {
                root.closeKeyboard()
                return "VIRTUALKEYBOARD_CLOSED"
            }
            root.openKeyboard()
            return "VIRTUALKEYBOARD_OPENED"
        }

        function open(): string {
            root.openKeyboard()
            return "VIRTUALKEYBOARD_OPENED"
        }

        function close(): string {
            root.closeKeyboard()
            return "VIRTUALKEYBOARD_CLOSED"
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/virtualkeyboard/VirtualKeyboardDaemon.qml
git commit -m "feat(virtualkeyboard): add daemon surface with IPC toggle"
```

---

### Task 10: `VirtualKeyboardWidget.qml` — optional DankBar pill

**Files:**
- Create: `plugins/virtualkeyboard/VirtualKeyboardWidget.qml`

**Interfaces:**
- Consumes: `PluginService.getGlobalVar/setGlobalVar` (same `"open"` var Task 9 writes).
- Produces: the `widget` surface referenced by `plugin.json`'s `components.widget`.

- [ ] **Step 1: Write `VirtualKeyboardWidget.qml`**

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

PluginComponent {
    id: root

    property bool keyboardOpen: PluginService.getGlobalVar(root.pluginId, "open", false)

    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId === root.pluginId && varName === "open")
                root.keyboardOpen = PluginService.getGlobalVar(root.pluginId, "open", false)
        }
    }

    pillClickAction: () => {
        PluginService.setGlobalVar(root.pluginId, "open", !root.keyboardOpen)
    }

    horizontalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: root.keyboardOpen ? Theme.primaryContainer : Theme.surfaceContainerHigh

            DankIcon {
                anchors.centerIn: parent
                name: "keyboard"
                size: root.iconSize
                color: root.keyboardOpen ? Theme.primary : Theme.surfaceText
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: root.keyboardOpen ? Theme.primaryContainer : Theme.surfaceContainerHigh

            DankIcon {
                anchors.centerIn: parent
                name: "keyboard"
                size: root.iconSize
                color: root.keyboardOpen ? Theme.primary : Theme.surfaceText
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/virtualkeyboard/VirtualKeyboardWidget.qml
git commit -m "feat(virtualkeyboard): add optional DankBar pill widget"
```

---

### Task 11: `VirtualKeyboardSettings.qml` — pin-on-startup toggle

**Files:**
- Create: `plugins/virtualkeyboard/VirtualKeyboardSettings.qml`

**Interfaces:**
- Consumes: `PluginSettings`/`ToggleSetting` (`qs.Modules.Plugins`, `settingKey: "pinnedOnStartup"` — must match the key `VirtualKeyboardDaemon.qml`'s `loadPluginData` reads in Task 9).
- Produces: the `settings` surface referenced by `plugin.json`.

- [ ] **Step 1: Write `VirtualKeyboardSettings.qml`**

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "virtualKeyboard"

    StyledText {
        width: parent.width
        text: "Toggle the keyboard with `dms ipc call virtualKeyboard toggle` (bindable to a compositor keybind), or add the optional bar pill to DankBar."
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "pinnedOnStartup"
        label: "Pin on startup"
        description: "Reserve screen space for the keyboard immediately, instead of only once pinned by hand"
        defaultValue: false
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/virtualkeyboard/VirtualKeyboardSettings.qml
git commit -m "feat(virtualkeyboard): add settings UI"
```

---

### Task 12: Install locally and run the manual end-to-end checklist

**Files:** none created; this task exercises Tasks 1–11 together.

- [ ] **Step 1: Symlink the plugin into DMS**

```bash
mkdir -p ~/.config/DankMaterialShell/plugins
ln -s "$(pwd)/plugins/virtualkeyboard" ~/.config/DankMaterialShell/plugins/virtualKeyboard
```

- [ ] **Step 2: Confirm `ydotool`/`ydotoold` are actually available**

```bash
command -v ydotool && systemctl --user status ydotool 2>&1 | head -5
```

If `ydotool` is missing, install it first (this is a real dependency, not
something the plugin can work around) — on NixOS: `nix-shell -p ydotool`, or
add it to the system's package list permanently if this is meant to stick.
Ensure `ydotoold` is running (systemd user/system unit, or launch it
manually: `ydotoold &` — needs write access to `/dev/uinput`, typically via
the `input` group or root).

- [ ] **Step 3: Launch DMS and scan for the plugin**

```bash
qs -p /nix/store/sfbgl5f54y4nvyj87r45a4msf7m5myzj-dms-shell-1.5.3/share/quickshell/dms/shell.qml
```

(Or however DMS is normally started on this machine — check for an existing
running instance first with `pgrep -af quickshell` before launching a
second one.) In DMS Settings (`Mod+,`) → Plugins, click "Scan for Plugins",
find "Virtual Keyboard", and enable it.

Expected: if `ydotool` was missing in Step 2, the enable toggle reverts and
a toast shows the `StartupCheck` error with expandable details. Fix the
dependency and retry before continuing.

- [ ] **Step 4: Verify IPC toggle**

```bash
dms ipc call virtualKeyboard open
dms ipc call virtualKeyboard toggle   # should close it
dms ipc call virtualKeyboard toggle   # should reopen it
```

Expected: the bottom-docked keyboard card appears/disappears, blurred
background behind the card only, docked to the bottom edge, styled with the
active DMS color scheme (not a flat unthemed rectangle).

- [ ] **Step 5: Verify typing, including shift-chording and caps-lock**

Open a text field somewhere on screen (a terminal, a text editor, the DMS
search bar — anything that accepts keyboard input) and, using the on-screen
keyboard's mouse clicks:
- Tap a few letter keys → they should appear as typed lowercase letters.
- Tap-and-hold Shift is not needed: tap Shift once, then tap a letter key →
  that one letter should appear uppercase, and shift should visually
  un-latch (color returns to idle) after that one letter.
- Double-tap Shift quickly (within ~300ms) → the key should visually latch
  (stay tinted); every subsequent letter should type uppercase until Shift
  is tapped once more to release it.
- Tap Ctrl, then tap C, then release Ctrl (tap again) → confirm no crash;
  full Ctrl+C semantics depend on the focused app, so just confirm the
  latch/release visual state and that no stray characters appear.
- Tap Backspace and Enter → confirm they delete a character / submit,
  rendered as icons (not the literal words "Backspace"/"Enter").

- [ ] **Step 6: Verify pin behavior**

Click the pin button → the keyboard should reserve screen space (windows
behind it should resize/reflow, same as e.g. a real docked panel). Unclick
→ space should be released. Click the hide button (or press Esc while the
card has focus) → keyboard closes; running `dms ipc call virtualKeyboard
open` again should reopen it cleanly (no leftover stuck modifier — if a
modifier was left latched before closing, confirm it visually resets, since
`onKeyboardClosed` calls `ydotool.releaseAllKeys()`).

- [ ] **Step 7: Verify a compositor keybind**

Add a keybind calling the IPC toggle. For niri (`~/.config/niri/config.kdl`):

```kdl
binds {
    Mod+K { spawn "dms" "ipc" "call" "virtualKeyboard" "toggle"; }
}
```

For Hyprland (`~/.config/hypr/hyprland.conf`):

```
bind = SUPER, K, exec, dms ipc call virtualKeyboard toggle
```

Reload the compositor config and confirm the bound key opens/closes the
keyboard. (Use whichever compositor this machine actually runs; adjust the
modifier if `Mod+K`/`SUPER+K` collides with an existing bind.)

- [ ] **Step 8: Verify the optional bar pill, then confirm it's optional**

Add the widget to the bar to confirm it works: Settings → Appearance →
DankBar Layout → add a widget with id `virtualKeyboard` to a section (or
edit `~/.config/DankMaterialShell/config.json`'s `dankBarLeftWidgets` /
equivalent array directly, adding `{"widgetId": "virtualKeyboard", "enabled": true}`).
Confirm clicking the pill toggles the same keyboard the IPC/keybind control,
and that its icon tints when open. Then remove it from the bar again and
confirm IPC/keybind toggling still works identically — the pill must never
be required.

- [ ] **Step 9: Note results**

If every check above passes, proceed to Task 13. If anything fails, fix the
relevant task's file, re-run the failing step, and only proceed once this
entire checklist passes clean — this is the actual proof the plugin works,
not the unit tests, which only cover the pure data/logic modules.

---

### Task 13: Plugin README + screenshots

**Files:**
- Create: `plugins/virtualkeyboard/README.md`
- Create: `plugins/virtualkeyboard/screenshots/keyboard.png`
- Create: `plugins/virtualkeyboard/screenshots/pill.png`

**Interfaces:** none — documentation only, but must be written after Task 12
so the keybind snippets and dependency notes are things that were actually
verified, not guessed.

- [ ] **Step 1: Capture screenshots**

With the plugin open per Task 12 Step 4 (docked keyboard visible over a
representative desktop background) and again with the bar pill added per
Task 12 Step 8, take two screenshots using whatever this machine's normal
screenshot tool is (e.g. `grim`, or DMS's own screenshot plugin if
installed). Save them to `plugins/virtualkeyboard/screenshots/keyboard.png`
(full keyboard card, docked) and `plugins/virtualkeyboard/screenshots/pill.png`
(close crop on the bar pill, matching the crop style of
`plugins/mouthguard/screenshots/popout.png`).

- [ ] **Step 2: Write `README.md`**

Follow `plugins/dankmenu/README.md`'s structure (title, one-line pitch,
screenshot, "What it does", "Install", "IPC", "Settings", "Development").
At minimum it must include:

```markdown
# Virtual Keyboard

On-screen keyboard overlay for DMS — click keys with the mouse/touch, or
drive it entirely by IPC from a compositor keybind. Ported from
[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)'s on-screen
keyboard, restyled to DMS's own theme.

![Virtual Keyboard](screenshots/keyboard.png)

## What it does

A bottom-docked overlay with a full US QWERTY layout (including the
function row), shift/caps-lock, and sticky Ctrl/Alt. Key injection goes
through [`ydotool`](https://github.com/ouya/ydotool), so it works
compositor-agnostically — niri, Hyprland, anything wlroots-based.

## Needs

- `ydotool` installed and its `ydotoold` service running (needs `/dev/uinput`
  access — usually the `input` group). The plugin refuses to enable itself
  with an actionable error if `ydotool` isn't on `PATH`.

## Install

```bash
dms plugins install virtualKeyboard
```

Enable it in DMS under `Mod+,` → **Plugins**. No bar widget is added
automatically — see "Bar pill" below if you want one.

## IPC

```bash
dms ipc call virtualKeyboard toggle
dms ipc call virtualKeyboard open
dms ipc call virtualKeyboard close
```

Bind this to a compositor key. niri (`~/.config/niri/config.kdl`):

```kdl
binds {
    Mod+K { spawn "dms" "ipc" "call" "virtualKeyboard" "toggle"; }
}
```

Hyprland (`~/.config/hypr/hyprland.conf`):

```
bind = SUPER, K, exec, dms ipc call virtualKeyboard toggle
```

## Bar pill (optional)

![Bar pill](screenshots/pill.png)

Add `virtualKeyboard` to a DankBar section (Settings → Appearance → DankBar
Layout) for a click-to-toggle icon. It's entirely optional — IPC and
keybinds work identically with or without it.

## Settings

- **Pin on startup** — reserve screen space for the keyboard immediately
  rather than only once pinned by hand.

## Development

```bash
qmltestrunner -input tests/tst_keyshape.qml
qmltestrunner -input tests/tst_layout_us.qml
```

Only `KeyShape.js` (sizing/label logic) and `layout-us.js` (layout data) are
pure JS and unit-tested this way; everything else spawns real `ydotool`
processes or opens a real layershell window, and is verified manually.
```

- [ ] **Step 3: Commit**

```bash
git add plugins/virtualkeyboard/README.md plugins/virtualkeyboard/screenshots
git commit -m "docs(virtualkeyboard): add plugin README and screenshots"
```

---

### Task 14: Update root README

**Files:**
- Modify: `README.md`

**Interfaces:** none — documentation only.

- [ ] **Step 1: Add a third card to the plugin table**

Match the existing two-column `<table>` block's pattern (see the "The
plugins" section) — extend it to a three-item grid (or a new row) adding:

```html
<td width="50%" valign="top">

### [virtualKeyboard](plugins/virtualkeyboard)

On-screen keyboard overlay, ported from
[dots-hyprland](https://github.com/end-4/dots-hyprland) — toggle by IPC,
compositor keybind, or an optional DankBar pill.

<a href="plugins/virtualkeyboard"><img src="plugins/virtualkeyboard/screenshots/keyboard.png" alt="Virtual Keyboard"></a>

</td>
```

- [ ] **Step 2: Add a row to the plugin summary table**

```markdown
| [`virtualkeyboard`](plugins/virtualkeyboard) | `composite` | `ydotool` + `ydotoold` running | [README](plugins/virtualkeyboard/README.md) |
```

- [ ] **Step 3: Add to the install list**

In the `## Install` section's `dms plugins install ...` block, add:

```bash
dms plugins install virtualKeyboard
```

And in the "From a clone instead" `<details>` block's symlink example, add:

```bash
ln -s ~/src/dms-plugins/plugins/virtualkeyboard ~/.config/DankMaterialShell/plugins/virtualKeyboard
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add virtualKeyboard to the plugin table and install instructions"
```

---

### Task 15: Registry PR (gated on user confirmation)

**Files:** none in this repo; this task touches
`AvengeMedia/dms-plugin-registry`, a repository this project doesn't own.

**Interfaces:** none.

- [ ] **Step 1: Confirm every Task 12 checklist item actually passed**

Do not proceed if any manual verification step was skipped or failed.

- [ ] **Step 2: Look at the existing registry entries for the other two plugins as a template**

```bash
gh api repos/AvengeMedia/dms-plugin-registry/contents --jq '.[].name'
```

Find and read the dankMenu/mouthGuard entries (however the registry
represents them — likely a JSON/YAML file per plugin, or one manifest file
listing all plugins) to match the exact shape expected.

- [ ] **Step 3: Show the user the exact diff/new-file this would add to the registry, and get explicit go-ahead before opening the PR**

This is a publish action against a community repository this project
doesn't control — confirm with the user even though they pre-approved "the
PR" in this session, since the actual content (repo URL, description,
version) should be reviewed once real, not hypothetical.

- [ ] **Step 4: Fork, branch, commit the registry entry, push, open the PR**

```bash
gh repo fork AvengeMedia/dms-plugin-registry --clone=false
gh repo clone <your-fork>/dms-plugin-registry /tmp/dms-plugin-registry
cd /tmp/dms-plugin-registry
git checkout -b add-virtual-keyboard
# add the entry, following the template found in Step 2
git add -A
git commit -m "Add virtualKeyboard plugin"
git push -u origin add-virtual-keyboard
gh pr create --repo AvengeMedia/dms-plugin-registry \
  --title "Add virtualKeyboard plugin" \
  --body "On-screen keyboard overlay for DMS, ported from end-4/dots-hyprland. Repo: https://github.com/sitolam/dms-plugins/tree/main/plugins/virtualkeyboard"
```

- [ ] **Step 5: Report the PR URL back to the user**

---

## Self-review notes

- **Spec coverage:** composite daemon+widget split (Task 1/9/10), ydotool
  backend (Task 4/8), US-only scope (Task 3), bottom-docked themed window
  (Task 7), pin setting (Task 9/11), IPC (Task 9), bar pill optional (Task
  10, verified optional in Task 12 Step 8), README/screenshots/root-README/
  registry PR (Tasks 13–15) — all spec sections have a task.
- **Placeholder scan:** no TBD/TODO; every step has literal code or literal
  commands.
- **Type consistency:** `pluginId`/`pinnedOnStartup` setting key matches
  between Task 9's `loadPluginData(pluginId, "pinnedOnStartup", ...)` and
  Task 11's `settingKey: "pinnedOnStartup"`; the `"open"` global-var name
  matches between Task 9 and Task 10; `Key`/`KeyboardLayout`/`KeyboardWindow`
  property names (`keyData`, `ydotool`, `keyboardVisible`, `pinned`,
  `keyboardClosed`, `show()`, `hide()`) are used identically wherever
  referenced downstream.
