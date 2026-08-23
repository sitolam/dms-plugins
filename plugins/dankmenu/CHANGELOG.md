# Changelog

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
