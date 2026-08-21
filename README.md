# dms-plugins

DankMaterialShell plugins written for [sitolamix](https://github.com/sitolam/sitolamix).

| Plugin | What it does |
| --- | --- |
| [`mouthguard`](plugins/mouthguard) | Webcam mouth-closure tracker with alerts and session stats |
| [`dankmenu`](plugins/dankmenu) | Omarchy-style root menu: one key to every command, with its own search |

Each directory under `plugins/` is a complete DMS plugin and is symlinked whole
into `~/.config/DankMaterialShell/plugins/<id>`; nothing in a plugin references
a path above its own root.

## Install

Manually:

```bash
ln -s "$PWD/plugins/dankmenu" ~/.config/DankMaterialShell/plugins/dankMenu
```

On NixOS, via home-manager:

```nix
programs.dank-material-shell.plugins.dankMenu = {
  enable = true;
  src = inputs.dms-plugins.packages.${pkgs.system}.dankmenu;
};
```

## Development

```bash
nix develop
pytest plugins/mouthguard                                   # MouthGuard's Python suite
qmltestrunner -input plugins/dankmenu/tests/tst_menumodel.qml
```

`qmltestrunner` takes one `-input` file per run, and its exit code is the
failure count rather than a flat 1.

MouthGuard keeps its own `flake.nix` under `plugins/mouthguard/`: its README and
`StartupCheck.qml` both document `nix build .#detector` *inside the plugin
directory* as the supported path for non-flake installs, and that has to keep
working. The root flake is what NixOS consumers use.
