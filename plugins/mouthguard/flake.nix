{
  description = "MouthGuard — mouth closure tracker for DankMaterialShell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in
    {
      packages = forAll (pkgs: rec {
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          dlib opencv4 numpy face-recognition-models
        ]);
        detectorSrc = pkgs.runCommand "mouthguard-detector-src" { } ''
          mkdir -p $out
          cp ${./detector.py} $out/detector.py
          cp ${./mouthguard_core.py} $out/mouthguard_core.py
        '';
        detector = pkgs.writeShellScriptBin "mouthguard-detector" ''
          exec ${pythonEnv}/bin/python3 ${detectorSrc}/detector.py "$@"
        '';
        default = detector;
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
          # shell (another tool, an editor, a parent shell) may legitimately
          # already have paths on it that we want to keep. QML2_IMPORT_PATH is
          # just Qt6's back-compat alias for it — nothing should be setting
          # QML2_IMPORT_PATH on its own account, so it is simply assigned the
          # final, already-merged QML_IMPORT_PATH value rather than merged
          # separately (merging it independently would risk the two variables
          # disagreeing, which defeats the point of one being an alias).
          shellHook = ''
            export QML_IMPORT_PATH="${pkgs.qt6.qtdeclarative}/lib/qt-6/qml''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
            export QML2_IMPORT_PATH="$QML_IMPORT_PATH"
          '';
        };
      });
    };
}
