{
  description = "sitolam's DankMaterialShell plugins";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});

      # MouthGuard's derivations are defined once, in the plugin's own
      # directory, and imported by both this flake and plugins/mouthguard's --
      # see plugins/mouthguard/package.nix. They are not trivial (pinned model
      # files, and an NPU runtime assembled around Intel's unpackaged graph
      # compiler), and two hand-kept copies of them drifted apart last time.
      mouthguardPkgs = pkgs: import ./plugins/mouthguard/package.nix { inherit pkgs; };
    in
    {
      packages = forAll (pkgs: rec {
        # The detector binary MouthGuard's StartupCheck.qml and
        # MouthGuardDaemon.qml expect to find at <pluginDir>/result/bin. A
        # consumer installing the plugin from a read-only store path cannot run
        # `nix build` inside the plugin directory, so it symlinks this in as
        # that `result` instead.
        mouthguard-detector = (mouthguardPkgs pkgs).detector;

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

      checks = forAll (pkgs: {
        # dankMenu's core is plain JavaScript with no QML type imports, so the
        # suites run headless here rather than only in a dev shell.
        dankmenu-qml = pkgs.runCommand "dankmenu-qml-tests"
          {
            nativeBuildInputs = [ pkgs.qt6.qtdeclarative ];
          }
          ''
            export QML_IMPORT_PATH="${pkgs.qt6.qtdeclarative}/lib/qt-6/qml"
            export QML2_IMPORT_PATH="$QML_IMPORT_PATH"
            # The sandbox has no display, and qmltestrunner wants a platform
            # plugin even for tests that never instantiate a window.
            export QT_QPA_PLATFORM=offscreen
            # Without a writable cache dir fontconfig floods stderr and buries
            # the actual test output.
            export XDG_CACHE_HOME="$PWD/.cache"
            mkdir -p "$XDG_CACHE_HOME"
            cp -r ${./plugins/dankmenu} dankmenu
            for t in dankmenu/tests/tst_*.qml; do
              echo "== $t"
              qmltestrunner -input "$t"
            done
            touch $out
          '';
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = (mouthguardPkgs pkgs).devPackages;

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
            export MOUTHGUARD_MODEL_DIR="''${MOUTHGUARD_MODEL_DIR:-${(mouthguardPkgs pkgs).models}}"
            export QML_IMPORT_PATH="${pkgs.qt6.qtdeclarative}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
            export QML2_IMPORT_PATH="$QML_IMPORT_PATH"
          '';
        };
      });
    };
}
