# Changelog

## 0.3.0

### Added

- **DMS launcher plugins.** `type: launcher` plugins — calculator, emoji and the
  rest — now answer in this menu under the same triggers they use in spotlight,
  at any level. A plugin left with no trigger ("always active") answers every
  root search. Their rows come back in the plugin's own order, unranked: this
  menu's scorer would drop a calculator result whose label shares no letters
  with the query that produced it.

  Nothing about them is configured here. The plugin list, the triggers and the
  settings stay DMS's, and running a row goes through DMS too — which is what
  puts a calculator result on the clipboard.

  The plugins are reached through `PluginService` and `AppSearchService`, which
  is *not* the launcher coupling the plugin avoids: spotlight's controller,
  scorer and modal are still untouched, and the menu still owns its own window,
  search and app list.

### Changed

- **Typing no longer re-runs a level's conditions.** They were re-evaluated on
  every keystroke, and a search from the root covers the whole tree — so one
  condition costing a second (a `docker stats`, an `ssh`) was paid once per
  character. Identical condition sets now collapse to a single run, a burst of
  typing is debounced to one, and results stay on screen until the new ones
  land instead of blinking off between keystrokes. Entering a level still
  re-runs its conditions, which is what makes them a snapshot.

## 0.2.0

### Added

- **`labelCmd`** — a fourth condition kind, whose *output* becomes the row's
  label rather than being judged by its exit status. The menu tree is a static
  file, so `label` alone could never show a value that changes; this is how a
  row shows a temperature, a container's memory use, or a queue depth.

  It rides the same single-shell-per-level machinery as the other conditions, so
  a level with a live label still costs one spawn. Output is clamped to one line
  and stripped of tabs (it travels as a field of a tab-separated record), stderr
  is discarded so a warning cannot end up rendered as the label, and empty output
  falls back to the static `label`.

  Like the other conditions it is a snapshot taken when the level opens, not a
  running meter.

  This is an extension beyond Omarchy's schema. Omarchy menu files still paste in
  unchanged, but a menu using `labelCmd` will not work in Omarchy.

## 0.1.0

Initial release: hierarchical searchable menu, Omarchy's `menu.jsonc` schema
field-for-field, `when` / `checked` / `disabled` conditions, app provider, and
IPC verbs mirroring `omarchy-menu`.
