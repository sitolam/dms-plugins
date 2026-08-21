{
  description = "sitolam's DankMaterialShell plugins";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];

      # nixpkgs bumped dlib 20.0 -> 20.0.1 (2026-08-18) without refreshing
      # python3Packages.dlib: build-cores.patch no longer applies, and 20.0.1's
      # setup.py dropped the `--set` build flag the nix expression feeds it, so
      # the python binding fails to build on unstable. Pin the src back to 20.0 —
      # what stable ships, and what the binary cache already has. Only mouthguard
      # pulls dlib in. Drop once nixpkgs fixes python3Packages.dlib.
      #
      # This lives in the flake rather than in a frozen flake.lock so that
      # `nix flake update` stays safe: the old dms-mouthguard repo only built
      # because its lock predated the bump, which is a fix with a shelf life.
      dlibPin = _final: prev: {
        dlib = prev.dlib.overrideAttrs (_: rec {
          version = "20.0";
          src = prev.fetchFromGitHub {
            owner = "davisking";
            repo = "dlib";
            tag = "v${version}";
            sha256 = "sha256-VTX7s0p2AzlvPUsSMXwZiij+UY9g2y+a1YIge9bi0sw=";
          };
        });
      };

      forAll = f: nixpkgs.lib.genAttrs systems (s: f (import nixpkgs {
        system = s;
        overlays = [ dlibPin ];
      }));
    in
    {
      packages = forAll (pkgs: rec {
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          dlib opencv4 numpy face-recognition-models
        ]);

        detectorSrc = pkgs.runCommand "mouthguard-detector-src" { } ''
          mkdir -p $out
          cp ${./plugins/mouthguard/detector.py} $out/detector.py
          cp ${./plugins/mouthguard/mouthguard_core.py} $out/mouthguard_core.py
        '';

        mouthguard-detector = pkgs.writeShellScriptBin "mouthguard-detector" ''
          exec ${pythonEnv}/bin/python3 ${detectorSrc}/detector.py "$@"
        '';

        # Plugin source trees, so consumers can take a package rather than
        # interpolating a subpath of the flake input.
        mouthguard = pkgs.runCommand "dms-plugin-mouthguard-src" { } ''
          cp -r ${./plugins/mouthguard} $out
        '';
        dankmenu = pkgs.runCommand "dms-plugin-dankmenu-src" { } ''
          cp -r ${./plugins/dankmenu} $out
        '';

        default = mouthguard-detector;
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [
            (pkgs.python3.withPackages (ps: with ps; [
              dlib opencv4 numpy face-recognition-models pytest
            ]))
            pkgs.qt6.qtdeclarative
            pkgs.jq
          ];

          # qmltestrunner's bundled QtTest/TestCase.qml imports QtQuick.Window,
          # which lives in qtdeclarative's own qml tree. That tree isn't on the
          # import path by default in this shell (and an ambient system Qt
          # install can shadow it), so qmltestrunner fails to resolve TestCase
          # itself. Point both the Qt6 and legacy Qt5-named variables at it,
          # derived from the qtdeclarative package already in this shell's
          # inputs so it tracks nixpkgs bumps instead of a pinned store path.
          # QML_IMPORT_PATH is prepended-to rather than overwritten because it
          # is a real, still-consulted Qt6 variable: something outside this
          # shell may legitimately already have paths on it. QML2_IMPORT_PATH
          # is just Qt6's back-compat alias, so it is assigned the final merged
          # value rather than merged separately.
          shellHook = ''
            export QML_IMPORT_PATH="${pkgs.qt6.qtdeclarative}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
            export QML2_IMPORT_PATH="$QML_IMPORT_PATH"
          '';
        };
      });
    };
}
