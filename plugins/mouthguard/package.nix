# The MouthGuard detector, as a plain function of a nixpkgs instance.
#
# This is not a flake output on purpose. Two flakes need these derivations --
# this plugin's own flake.nix and the repository-root flake.nix, which is what
# consumers pin -- and a copy in each is a copy that drifts: the last one
# ended up with the two of them naming different Python environments for the
# same detector.py. Anything that consumes MouthGuard from outside Nix flakes
# entirely can import this file directly too.
{ pkgs }:

let
  inherit (pkgs) lib;

  # The webcam is already a shared PipeWire camera source on this desktop
  # (wireplumber's v4l2 monitor owns /dev/video0 and re-exposes it as a
  # Video/Source node) -- gaze reads the same node ("resolved through
  # PipeWire at runtime", modules/hardware/gaze.nix). opencv4's default
  # build has no GStreamer support, so detector.py's only option was
  # cv2.CAP_V4L2 straight against /dev/video0: a second exclusive open of
  # the device node PipeWire itself already holds, which starved every
  # other PipeWire camera client -- gaze's face auth and any browser/video
  # call -- for as long as MouthGuard was active. Building opencv4 with
  # GStreamer, and pulling in the plugin that speaks to PipeWire
  # (pipewiresrc, shipped by pipewire itself), lets detector.py
  # join that same shared node instead of fighting it for exclusive access.
  gstPluginPath = lib.makeSearchPath "lib/gstreamer-1.0" (
    (with pkgs.gst_all_1; [
      # .out: gst_all_1.gstreamer's default output is "bin" (gst-inspect
      # etc, no plugins) -- "${pkg}/..." string interpolation on the bare
      # attribute silently picked that one, so libgstcoreelements.so
      # (capsfilter, videoconvert's caps-negotiation glue) was never on
      # the path and every parse-launch link failed with
      # `no such element factory "capsfilter"`.
      gstreamer.out
      gst-plugins-base
    ])
    # pipewiresrc/pipewiresink ship as part of pipewire itself
    # (lib/gstreamer-1.0/libgstpipewire.so), not gst-plugins-good/-bad --
    # confirmed by build: pointing GST_PLUGIN_SYSTEM_PATH_1_0 at
    # gst-plugins-good alone left GStreamer reporting `no element
    # "pipewiresrc"`.
    ++ [ pkgs.pipewire ]
  );
in
rec {
  # The two MediaPipe TFLite bundles the web app's @mediapipe/face_mesh 0.4
  # loads, fetched from Google's asset bucket and pinned by hash so the plugin
  # measures against exactly the model it was tuned on. OpenVINO's TFLite
  # frontend reads them as-is; there is no conversion step to keep in sync.
  models = pkgs.runCommand "mouthguard-models" { } ''
    mkdir -p $out
    cp ${pkgs.fetchurl {
      url = "https://storage.googleapis.com/mediapipe-assets/face_detection_short_range.tflite";
      hash = "sha256-O8GC658zkl2eWLXI1ZMIp2D0reqPKCNw5CjFEhLCZjM=";
    }} $out/face_detection_short_range.tflite
    cp ${pkgs.fetchurl {
      url = "https://storage.googleapis.com/mediapipe-assets/face_landmark.tflite";
      hash = "sha256-EFXLnUqcqLjGiJAqOlGUMRE4uiVrzJTjNtg3Ol8wyBQ=";
    }} $out/face_landmark.tflite
  '';

  pythonEnv = pkgs.python3.withPackages (
    ps: with ps; [
      openvino
      (opencv4.override { enableGStreamer = true; })
      numpy
    ]
  );

  # --- NPU support ---------------------------------------------------------
  # OpenVINO can only build a graph for Intel's NPU through a compiler that
  # Intel ships as a binary alongside the Level Zero driver, and that nixpkgs
  # does not package: without it the NPU enumerates and then fails every
  # compile with ZE_RESULT_ERROR_UNSUPPORTED_FEATURE. It is fetched from the
  # same driver release the kernel side comes from, because the compiler and
  # the driver version must match.
  npuCompiler = pkgs.stdenvNoCC.mkDerivation {
    pname = "intel-npu-driver-compiler";
    version = "1.35.0";
    src = pkgs.fetchurl {
      url = "https://github.com/intel/linux-npu-driver/releases/download/v1.35.0/linux-npu-driver-v1.35.0.20260722-29947505341-ubuntu2404.tar.gz";
      hash = "sha256-OYND5T/axgI60IVu+Iu2ARseEkR6ESvlXoXifvf5bGY=";
    };
    sourceRoot = ".";
    nativeBuildInputs = with pkgs; [
      dpkg
      autoPatchelfHook
    ];
    buildInputs = with pkgs; [
      stdenv.cc.cc.lib
      tbb_2022
      zlib
      zstd
    ];
    installPhase = ''
      runHook preInstall
      dpkg-deb -x intel-driver-compiler-npu_*.deb unpacked
      install -Dm444 -t $out/lib unpacked/usr/lib/x86_64-linux-gnu/*.so
      runHook postInstall
    '';
    meta.platforms = [ "x86_64-linux" ];
  };

  # OpenVINO looks for that compiler next to its own plugin libraries, by the
  # path libopenvino.so itself was loaded from -- so the copy has to be a real
  # one, not a tree of symlinks back into the openvino store path, and the
  # detector has to load libopenvino.so from here (LD_LIBRARY_PATH, which the
  # loader consults before the RUNPATH baked into the Python module).
  # Registering the NPU plugin from a private directory does not work: the
  # compiler path is derived from libopenvino.so's location, not the plugin's.
  openvinoWithNpu = pkgs.runCommand "openvino-with-npu-compiler" { } ''
    mkdir -p $out/lib
    cp -rL ${pkgs.openvino.lib}/lib/. $out/lib/
    chmod -R u+w $out/lib
    cp ${npuCompiler}/lib/*.so $out/lib/openvino/
  '';

  detectorSrc = pkgs.runCommand "mouthguard-detector-src" { } ''
    mkdir -p $out
    cp ${./detector.py} $out/detector.py
    cp ${./mouthguard_core.py} $out/mouthguard_core.py
    cp ${./mouthguard_mesh.py} $out/mouthguard_mesh.py
  '';

  detector = pkgs.writeShellScriptBin "mouthguard-detector" ''
    export MOUTHGUARD_MODEL_DIR=''${MOUTHGUARD_MODEL_DIR:-${models}}
    # pipewire's own pipewiresrc plugin, found by GStreamer's own plugin
    # scanner rather than linked -- opencv4's GStreamer support loads
    # plugins as .so files at runtime, not build time.
    export GST_PLUGIN_SYSTEM_PATH_1_0=''${GST_PLUGIN_SYSTEM_PATH_1_0:-${gstPluginPath}}
    # pw-dump: detector.py's pipewire_target_for() shells out to it to
    # resolve --device's /dev/videoN into the PipeWire node name
    # pipewiresrc needs (see that function's docstring for why -- there is
    # no "default camera" wireplumber will pick without one).
    export PATH="${pkgs.pipewire}/bin''${PATH:+:$PATH}"
    ${lib.optionalString pkgs.stdenv.hostPlatform.isx86_64 ''
      # Everything below is what it takes to reach the NPU; all of it is
      # harmless on a machine that has none, where mouthguard_mesh falls
      # through to GPU and then CPU.
      #
      #   openvinoWithNpu  the OpenVINO libraries plus Intel's NPU graph
      #                    compiler, which has to sit beside them
      #   level-zero       the loader the NPU plugin talks to; OpenVINO
      #                    enumerates no NPU at all without it on the path
      #   /run/opengl-driver/lib  where NixOS puts the Level Zero and OpenCL
      #                    userspace drivers (hardware.graphics.extraPackages),
      #                    needed for both the NPU and the GPU
      export LD_LIBRARY_PATH="${openvinoWithNpu}/lib:${pkgs.level-zero}/lib:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      # Fallback for systems that did not install the NPU driver into the
      # system driver path: the Level Zero loader will also take a driver
      # named outright, and ignores one matching no hardware.
      export ZE_ENABLE_ALT_DRIVERS=''${ZE_ENABLE_ALT_DRIVERS:-${pkgs.intel-npu-driver}/lib/libze_intel_npu.so.1}
    ''}
    exec ${pythonEnv}/bin/python3 ${detectorSrc}/detector.py "$@"
  '';

  # Everything the test suites need on top of the runtime dependencies.
  devPackages = [
    (pkgs.python3.withPackages (
      ps: with ps; [
        openvino
        (opencv4.override { enableGStreamer = true; })
        numpy
        pytest
      ]
    ))
    pkgs.qt6.qtdeclarative
    pkgs.jq
  ];
}
