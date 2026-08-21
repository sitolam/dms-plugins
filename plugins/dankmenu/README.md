# dankMenu

An [Omarchy](https://github.com/basecamp/omarchy)-style root menu for
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell): one key
to every command on the machine, with drill-in navigation and its own search.

## What it is

Omarchy binds `SUPER+SPACE` to a hierarchical, fuzzy-searchable menu covering
apps, settings, toggles and power actions. This is that menu, as a DMS plugin.

It is a `daemon` plugin owning its own layershell window rather than a launcher
plugin living inside DMS's spotlight. That is not a stylistic choice: the
spotlight modal hides itself on every item execution
(`SpotlightLauncherContent.qml` reacts to `Controller`'s `itemExecuted`) with no
hook for a plugin to prevent it, which makes drill-in navigation impossible
there.

The search, the ranking and the app list are the plugin's own code. The only
thing borrowed from the shell is `SessionService.launchDesktopEntry`, so that
apps started from the menu land in the right systemd scope.

## Usage

```bash
dms ipc call dankMenu toggle          # open at the root, or close if open
dms ipc call dankMenu open system     # open straight into a submenu
dms ipc call dankMenu open power-menu # aliases work too
dms ipc call dankMenu close
dms ipc call dankMenu refresh         # re-read the menu file
```

Bind the first one to `Super+Space` in your compositor. For niri:

```kdl
binds {
    Mod+Space { spawn "dms" "ipc" "call" "dankMenu" "toggle" "root"; }
}
```

| key | effect |
| --- | --- |
| `Enter` | enter a submenu, or run a row and close |
| `Right` | enter a submenu, when the cursor is at the end of the query |
| `Escape` | up one level; at the root, close |
| `Left` / `Backspace` | up one level, when the query is empty |
| `Up` / `Down`, `Ctrl+P` / `Ctrl+N` | move the selection |
| any text | search this level's whole subtree |

At the root, a search also covers installed applications, so one keystroke
sequence finds either a command or a program.

## The menu file

`menu.jsonc` uses Omarchy's schema exactly — object keys are dotted ids,
hierarchy is implied by the dots, and the kind of a row is inferred from its
fields (`action` → action, `target` → link, `provider` → provider, otherwise
submenu). Subtrees of Omarchy's own menu file can be pasted in unchanged.

```jsonc
{
  "system": {"icon":"power_settings_new","label":"System","aliases":["power-menu"]},
  "system.lock": {"icon":"lock","label":"Lock","action":"loginctl lock-session"},
  "trigger.toggle.night": {
    "icon":"nightlight","label":"Night Mode",
    "checked":"dms ipc call night status | grep -q enabled",
    "action":"dms ipc call night toggle"
  }
}
```

Rows may carry `when`, `checked` and `disabled` shell snippets: `when` hides the
row unless the snippet succeeds, `checked` appends a tick when it does, and
`disabled` dims the row and blocks selection. Every snippet for one level runs
in a **single** shell, not one process per row, and rows stay visible while the
results are still pending.

`action` runs through `bash -lc`, so pipes, `$(…)` and `&&` all work. Icons on
ordinary rows are [Material Symbols](https://fonts.google.com/icons) names; app
rows use the icon theme.

Point the `menuPath` setting at another file to replace the tree entirely —
that is how a Nix-managed install supplies a generated one. Whichever file is
live is watched, so edits apply without restarting the shell.

## Development

```bash
nix develop ../..
qmltestrunner -input tests/tst_menumodel.qml
qmltestrunner -input tests/tst_search.qml
qmltestrunner -input tests/tst_conditions.qml
```

`qmltestrunner` takes one `-input` per run and exits with the failure count.
`MenuModel.js`, `Search.js` and `Conditions.js` import no QML types, so the
tests exercise the exact files the plugin loads rather than copies of them.
