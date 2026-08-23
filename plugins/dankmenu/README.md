# dankMenu

One key to every command on the machine — a hierarchical, searchable root menu
for [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell), in
the shape of [Omarchy](https://github.com/basecamp/omarchy)'s `Super+Space`
menu.

![dankMenu root](screenshots/root.png)

Type instead of navigating, and it searches every command below the level
you're on — with a breadcrumb telling you where each result lives:

![searching from the root](screenshots/search.png)

## Credits

The design is [Omarchy](https://github.com/basecamp/omarchy)'s, by
[Basecamp](https://basecamp.com) and its contributors (MIT). Omarchy binds
`SUPER+SPACE` to `omarchy-menu`, a hierarchical menu covering apps, settings,
toggles and power actions — the single entry point to the whole desktop.

This plugin reimplements that idea for DMS. It shares no code with Omarchy, but
it deliberately keeps **their menu file schema field-for-field**, so subtrees of
[`omarchy-menu.jsonc`](https://github.com/basecamp/omarchy/blob/master/default/omarchy/omarchy-menu.jsonc)
paste in and parse unchanged, and their `when` / `checked` / `disabled`
semantics behave the same way. The IPC verbs mirror `omarchy-menu`'s too, so
routes and muscle memory carry over.

Go try the real thing if you're on Arch — it's very good.

## Why a window instead of a spotlight plugin

DMS already supports `type: launcher` plugins that add rows to its spotlight, so
that looks like the obvious way to build this. It cannot work: DMS's launcher
controller emits `itemExecuted` after every selection and the spotlight modal
hides itself on that signal unconditionally, with no hook for a plugin to
prevent it. "Enter descends into a submenu" is therefore impossible there —
selecting a row always closes the launcher.

So dankMenu is a `daemon` plugin owning its own wlr-layershell window, and its
search, ranking and app list are its own code. The only thing borrowed from the
shell is `SessionService.launchDesktopEntry`, so apps started from the menu land
in the right systemd scope rather than being reparented to the shell process.

## Install

Requires DMS ≥ 1.5.0.

**Manually:**

```bash
git clone https://github.com/sitolam/dms-plugins
ln -s "$PWD/dms-plugins/plugins/dankmenu" ~/.config/DankMaterialShell/plugins/dankMenu
```

Then enable it in DMS: `Mod+,` → Plugins → enable **Dank Menu**.

**On NixOS, via home-manager:**

```nix
programs.dank-material-shell.plugins.dankMenu = {
  enable = true;
  src = inputs.dms-plugins.packages.${pkgs.system}.dankmenu;
};
```

Note that with `managePluginSettings = true`, `plugin_settings.json` becomes a
read-only store symlink — the plugin must be enabled declaratively as above,
because the DMS settings GUI cannot write to it.

Finally, bind it. For niri:

```kdl
binds {
    Mod+Space { spawn "dms" "ipc" "call" "dankMenu" "toggle" "root"; }
}
```

For Hyprland:

```conf
bind = SUPER, SPACE, exec, dms ipc call dankMenu toggle root
```

## Usage

```bash
dms ipc call dankMenu toggle          # open at the root, or close if open
dms ipc call dankMenu open system     # open straight into a submenu
dms ipc call dankMenu open power-menu # aliases work too
dms ipc call dankMenu close
dms ipc call dankMenu refresh         # re-read the menu file
```

Because `open` takes a route, any submenu can have its own keybind — a power
menu on `Mod+Escape` is just `dms ipc call dankMenu open system`.

| key | effect |
| --- | --- |
| `Enter` | enter a submenu, or run a row and close |
| `Right` | enter a submenu, when the cursor is at the end of the query |
| `Escape` | up one level; at the root, close |
| `Left` / `Backspace` | up one level, when the query is empty |
| `Up` / `Down` | move the selection |
| any text | search this level's whole subtree |

### vim bindings

Every one is `Ctrl`-prefixed. Bare `hjkl` cannot navigate here: the search field
is always focused and always accepting a query, so plain letters have to reach
it as text.

| key | effect |
| --- | --- |
| `Ctrl+J` / `Ctrl+K` | down / up (`Ctrl+N` / `Ctrl+P` also work) |
| `Ctrl+L` / `Ctrl+H` | in / out — enter a submenu, or go up a level |
| `Ctrl+D` / `Ctrl+U` | half a page down / up |
| `Ctrl+G` | close the menu outright, from any depth |

Going back out of a submenu returns the highlight to the row you entered
through, not to the top of the list.

## Configuring the menu

The whole menu is one JSONC file. The plugin ships
[`menu.jsonc`](menu.jsonc) as a starting point; point the **`menuPath`** setting
at your own file to replace it entirely. Whichever file is live is watched, so
saving it updates the menu immediately — no shell restart, no `refresh` call.

Set `menuPath` in DMS under `Mod+,` → Plugins → Dank Menu, or declaratively:

```nix
programs.dank-material-shell.plugins.dankMenu.settings.menuPath = "/home/you/.config/dankmenu.jsonc";
```

### The file format

JSONC — JSON with `//` comments and trailing commas, the same dialect Omarchy
uses. Object keys are **dotted ids**, and the dots *are* the hierarchy:
`setup.network.dns` is a child of `setup.network`, which is a child of `setup`.
Declaration order is display order.

```jsonc
{
  // A submenu: no action, no target, no provider.
  "system": {"icon":"power_settings_new","label":"System","aliases":["power-menu"]},

  // An action: runs a shell command, then closes the menu.
  "system.lock": {"icon":"lock","label":"Lock","action":"loginctl lock-session"},

  // A link: opens in your browser.
  "learn.niri": {"icon":"grid_view","label":"Niri","target":"https://github.com/YaLTeR/niri/wiki"},

  // A provider: contents generated at open time. "apps" is the only one so far.
  "apps": {"icon":"apps","label":"Apps","provider":"apps"},
}
```

The **kind of a row is inferred**, never declared: `action` makes it an action,
`target` a link, `provider` a provider-backed submenu, and anything else a plain
submenu.

### Fields

| field | meaning |
| --- | --- |
| `label` | the row's text. Defaults to its id. |
| `icon` | a [Material Symbols](https://fonts.google.com/icons) name (`wifi`, `school`). App rows use the icon theme instead. |
| `iconFont` | font family for the glyph, when it isn't the menu font |
| `title` | header text when the submenu is open. Defaults to `label`. |
| `aliases` | extra names for `open <route>`, and extra search terms |
| `action` | shell command, run through `bash -lc` |
| `target` | URL, opened externally |
| `provider` | generated contents — currently only `apps` |
| `when` | hide the row unless this succeeds |
| `checked` | append a ✓ when this succeeds |
| `disabled` | dim the row and block selection when this succeeds |
| `labelCmd` | replace the row's label with this snippet's output |

Actions go through `bash -lc`, so pipes, `$(…)`, `&&` and quoting all work —
menu actions are shell text, not argv.

### Conditions

`when`, `checked` and `disabled` are shell snippets, judged by **exit status**.
They make the menu reflect the machine rather than just describe it:

```jsonc
// Ticked while night mode is actually on.
"trigger.toggle.night": {
  "icon":"nightlight","label":"Night Mode",
  "checked":"dms ipc call night status | grep -q enabled",
  "action":"dms ipc call night toggle"
},

// Absent entirely on a desktop.
"trigger.toggle.battery": {
  "icon":"battery_std","label":"Battery Percentage",
  "when":"test -d /sys/class/power_supply/BAT0",
  "action":"dms ipc call bar toggle"
},
```

![conditions in action](screenshots/conditions.png)

Every snippet for one menu level runs in a **single** shell, not one process per
row, so a level with a dozen conditions costs one spawn. Rows stay visible while
results are pending, so a slow condition delays a tick rather than making rows
flicker in and out of the list.

### Live labels

`labelCmd` is the odd one out: it is judged by its **output**, not its exit
status. Its first line of stdout becomes the row's label, which is the only way
to put a live value in front of someone — the menu tree is a static file, so
`label` alone can never show a number that changes.

```jsonc
// Reads "Memory  2.1GiB / 4GiB" rather than "Memory".
"windows.memory": {
  "icon":"memory",
  "label":"Memory",
  "labelCmd":"docker stats --no-stream --format '{{.MemUsage}}' windows | sed 's/^/Memory  /'",
  "disabled":"true"
},
```

Details worth knowing:

- Output is clamped to **one line** and stripped of tabs, because it travels as
  one field of a tab-separated record.
- **stderr is discarded.** A warning from the snippet would otherwise be
  rendered as the label.
- Empty output falls back to the static `label`, so a snippet that fails leaves
  a sensible row rather than a blank one. Give every `labelCmd` row a `label`
  worth falling back to.
- It is a **snapshot**, taken when the level opens — like the other three
  conditions. It is not a running meter; reopen the level to refresh.
- Keep it fast. Every snippet for a level runs in one shell, and the level waits
  on all of them.

Conditions are re-evaluated every time you enter a level, so a tick is never
stale. While a search is active they cover the whole subtree being searched.

### Apps

The `apps` provider lists your desktop entries, ranked by the plugin's own
fuzzy scorer plus a frecency boost. At the **root**, a search covers apps too —
so one keystroke sequence finds either a command or a program.

![the apps provider](screenshots/apps.png)

### Generating the tree

Because `menuPath` is just a path, the file can be generated. On NixOS that
means menu rows can reference store paths and your own flake:

```nix
{ id = "update.rebuild"; icon = "build"; label = "Rebuild";
  action = "ghostty --working-directory=${flakeDir} -e just rebuild"; }
```

Emit it as ordered JSONC text rather than via `pkgs.formats.json` — Nix
serialises attrsets alphabetically, and menu rows have a meaningful order. A
power menu reading "lock, logout, reboot, shutdown, suspend" is not the one
anybody wants. See
[sitolamix's `plugins.nix`](https://github.com/sitolam/sitolamix/blob/main/modules/desktop/dms/plugins.nix)
for a full worked example.

## Development

```bash
nix develop ../..
qmltestrunner -input tests/tst_menumodel.qml
qmltestrunner -input tests/tst_search.qml
qmltestrunner -input tests/tst_conditions.qml
```

`qmltestrunner` takes one `-input` per run and exits with the failure count.
`nix flake check` runs all three headless.

`MenuModel.js` (JSONC parsing, tree building, route resolution), `Search.js`
(scoring and ranking) and `Conditions.js` (script generation and output
parsing) import no QML types at all, so the tests exercise the exact files the
plugin loads rather than copies of them. The QML files are thin shells over
those three.

| file | responsibility |
| --- | --- |
| `DankMenuDaemon.qml` | IPC handler, menu file loading, window lifecycle |
| `MenuWindow.qml` | the layershell window, keys, row building |
| `MenuList.qml` | list and row delegate |
| `Conditions.qml` | runs the generated condition script |
| `AppSource.qml` | desktop entries in, menu rows out |

## License

MIT.
