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
        };
      });
    };
}
