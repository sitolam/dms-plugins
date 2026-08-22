# dms-plugins

[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) plugins,
written for [sitolamix](https://github.com/sitolam/sitolamix) but not tied to it.

| Plugin | What it does |
| --- | --- |
| [`dankmenu`](plugins/dankmenu) | One key to every command — a hierarchical, searchable root menu in the shape of [Omarchy](https://github.com/basecamp/omarchy)'s `Super+Space` |
| [`mouthguard`](plugins/mouthguard) | Webcam mouth-closure tracker with alerts and session stats |

![dankMenu](plugins/dankmenu/screenshots/root.png)

## Install

Each directory under `plugins/` is a complete DMS plugin, symlinked whole into
`~/.config/DankMaterialShell/plugins/<id>`. Nothing inside a plugin references a
path above its own root, so a single directory is all you need to copy.

```bash
git clone https://github.com/sitolam/dms-plugins
ln -s "$PWD/dms-plugins/plugins/dankmenu" ~/.config/DankMaterialShell/plugins/dankMenu
```

Then enable it in DMS under `Mod+,` → Plugins.

On NixOS, via home-manager:

```nix
programs.dank-material-shell.plugins = {
  dankMenu.src = inputs.dms-plugins.packages.${pkgs.system}.dankmenu;
  mouthGuard.src = inputs.dms-plugins.packages.${pkgs.system}.mouthguard;
};
```

Per-plugin setup, configuration and keybinds live in each plugin's own README.

## Development

```bash
nix develop
pytest plugins/mouthguard                                     # MouthGuard's Python suite
qmltestrunner -input plugins/dankmenu/tests/tst_menumodel.qml # one file per run
nix flake check                                               # everything, headless
```

`qmltestrunner` takes one `-input` file per run, and its exit code is the
failure count rather than a flat 1.

MouthGuard keeps its own `flake.nix` under `plugins/mouthguard/`: its README and
`StartupCheck.qml` both document `nix build .#detector` *inside* the plugin
directory as the supported path for non-flake installs, and that has to keep
working. The root flake is what NixOS consumers use, and it carries a dlib 20.0
pin — nixpkgs bumped dlib to 20.0.1 without refreshing `python3Packages.dlib`,
which breaks the build on unstable.

## Publishing a plugin to the DMS registry

Plugins here are installable directly from this repo, but listing one in the
[DMS plugin registry](https://github.com/AvengeMedia/dms-plugin-registry) makes
it discoverable from `dms plugins install` and the in-shell plugin browser.
The [official guide](https://danklinux.com/docs/contributing-registry) is the
authority; the short version:

1. Fork [`AvengeMedia/dms-plugin-registry`](https://github.com/AvengeMedia/dms-plugin-registry).
2. Add `plugins/{github-username}-{plugin-name}.json`, lowercase and hyphenated
   — e.g. `sitolam-dankmenu.json`.
3. Fill in the entry:

   ```json
   {
     "id": "dankMenu",
     "name": "Dank Menu",
     "capabilities": ["daemon", "ipc"],
     "category": "utilities",
     "repo": "https://github.com/sitolam/dms-plugins",
     "path": "plugins/dankmenu",
     "author": "sitolam",
     "description": "Omarchy-style root menu: one key to every command, with built-in search",
     "dependencies": [],
     "compositors": ["any"],
     "distro": ["any"],
     "screenshot": "https://raw.githubusercontent.com/sitolam/dms-plugins/main/plugins/dankmenu/screenshots/root.png"
   }
   ```

   **`path` is what makes a monorepo work** — it points the registry at the
   subdirectory rather than the repo root, so one repo can list several plugins.

4. `id` and `name` **must match the plugin's own `plugin.json` exactly**, or the
   entry is rejected.
5. Run the repo's validation scripts, then open a PR. The registry opens a
   tracking issue for feedback, and listings are ranked by community upvotes.

Keep the description short, point `screenshot` at a real image, and make sure
the `compositors` and `distro` values are ones you have actually tested.

## License

MIT.
