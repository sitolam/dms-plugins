# Changelog

All notable changes to the MouthGuard DMS plugin are documented here.

## [Unreleased]

## [0.2.0] — 2026-08-23

The detection pipeline is now the one the browser app this was ported from actually uses. The
0.1.0 port swapped MediaPipe for dlib because dlib was the thing packaged for Python on a
desktop, and paid for it twice: a face had to be close enough to clear dlib's minimum detectable
size, and a turned head read as no face at all. Both are gone, and so is the calibration step
that existed largely to work around the first one.

### Changed

- Face tracking moved from dlib to MediaPipe Face Mesh — the same models the web app this plugin
  was ported from runs (`@mediapipe/face_mesh` 0.4), driven directly through OpenVINO, whose
  TFLite frontend reads them without a conversion step. This replaces dlib's HOG detector and
  68-point predictor with BlazeFace plus the 468-point mesh, and fixes the two accuracy problems
  the dlib port had: faces are found well beyond the roughly 80x80 px floor the HOG detector
  imposed, and a turned head no longer reads as "no face".
- Detection now runs on the **NPU** where one is available, falling back to the GPU and then the
  CPU — including when a device enumerates but fails to compile, which is what an Intel NPU with
  a driver but no graph compiler does. The chosen device is reported in the `ready` line as
  `mediapipe/<device>` and can be forced with `--inference-device`. Measured here: 0.6 ms per
  inference on the NPU, 1.0 ms on the iGPU, 1.5 ms on the CPU.
- **Calibration is gone, along with `CALIBRATION.md`, `tools/calibrate.py`, and their tests.**
  The threshold (5.0) and distance-compensation reference (100 px) are the web app's values,
  carried over with its model, and are meaningful without per-camera tuning: compensation
  normalises each gap against the user's own nose-to-chin distance in the same frame, so seating
  distance and camera geometry divide out.
- The threshold setting key is now `meshThreshold`. A value saved against the dlib pipeline was
  on a different scale and would be silently misread here, so old settings lapse to the new
  default instead.
- The flake fetches both model files, pinned by hash, and assembles the NPU runtime: Intel's NPU
  graph compiler is not packaged by nixpkgs, and without it OpenVINO enumerates the NPU and then
  fails every compile with `ZE_RESULT_ERROR_UNSUPPORTED_FEATURE`. It is fetched from the matching
  `linux-npu-driver` release and placed beside OpenVINO's own libraries, which is the only
  location OpenVINO will look in.
- `--detect-interval` is gone. MediaPipe re-runs its detector only when the mesh reports it has
  lost the face, so there is no interval left to tune.

### Fixed

- Desktop notifications never appeared on systems without `libnotify`. Alerts shelled out to
  `notify-send`, which is not part of a base install on NixOS and several minimal distros, and
  `Quickshell.execDetached` gives no indication when the binary is missing — the notification
  simply went nowhere, silently. Alerts now go through `dms notify` (the DMS CLI, which is
  necessarily present wherever this plugin runs, and reaches the same
  `org.freedesktop.Notifications` server), falling back to `notify-send` only where `dms` is not
  on `PATH`.
- Detection no longer switches itself off when the shell restarts. The active flag was saved with
  `savePluginData` rather than its look-alike `savePluginState`, and so landed in
  `~/.config/DankMaterialShell/plugin_settings.json` — a file that is read-only for anyone
  managing their dotfiles declaratively (home-manager, chezmoi, a `/nix/store` symlink), where
  DMS's own `FileView` suppresses the resulting error. It is now stored as plugin *state*
  alongside session history, in a file DMS creates and owns.

### Packaging and dependencies

- Dependencies are now `python3`, `python-opencv`, and `python-openvino`. `python-dlib` and the
  95 MB `shape_predictor_68_face_landmarks.dat` are gone; the two MediaPipe models replacing them
  total 1.4 MB and are fetched, hash-pinned, by the flake.
- Every derivation moved to `package.nix`, a plain function of a nixpkgs instance, imported by
  both this plugin's flake and the repository-root one. The root flake — the one consumers
  actually pin — had carried its own parallel copy of the detector's Python environment, which
  after this change would have meant a dlib environment for a `detector.py` that imports
  OpenVINO. Nothing about the new detector survives being retyped by hand in a second place: two
  hash-pinned model files, and an NPU runtime assembled around a compiler nixpkgs does not
  package. The root flake's dlib overlay pin went with it.
- `StartupCheck.qml` now verifies `import cv2, openvino` and that a model directory resolves,
  because `--self-test` deliberately returns before either is touched.

## [0.1.0] — 2026-08-02

Initial release. A native DankMaterialShell port of the browser-based MouthGuard
(https://github.com/sitolam/mouthguard), reimplemented as a DMS daemon + bar pill using dlib for
local face tracking instead of MediaPipe in the browser.

### Detection

- `detector.py`: policy-free sensor process — opens the camera via OpenCV/V4L2, runs dlib's HOG
  face detector and 68-point landmark predictor, and streams one JSON measurement line per frame
  over stdout. Holds no thresholds, timing, or alert policy; all of that lives in QML, which is
  what lets settings changes apply live without restarting the camera.
- Cached face-rect tracking between full re-detections (`--detect-interval`), amortising the HOG
  detector's cost across frames.
- `--self-test` mode emits a valid measurement stream without touching a camera device.
- Calibrated detection threshold (3.5, tenths-of-a-pixel scale) and distance-compensation
  reference (71 px), derived empirically against the real dlib pipeline — see `CALIBRATION.md`.
- `tools/calibrate.py` for recording and re-deriving these constants against a different camera.

### Tracking behaviour

- Detection window: the mouth must stay open continuously for the full configured delay before
  it is confirmed as an "open" event and an alert fires — brief openings are discarded.
- Distance compensation: normalises the raw lip gap by face height so sensitivity stays
  consistent as seating distance changes.
- Auto-pause on screen lock, idle, or sleep preparation: releases the camera device without
  killing the detector process, preserving the resident dlib model and avoiding its reload cost.
- No-face auto-stop: ends a session automatically after a configurable timeout with no face
  detected (0 disables).
- Session stats track Open / Closed / Away (unmeasured) time, event count, and average open
  duration; Away time covers both no-face spans and auto-pause gaps.

### UI

- Bar pill with five visual states (inactive, closed, open, no-face, paused), each with its own
  icon and colour, on both the horizontal and vertical bar layouts.
- Pill click actions: left-click opens the popout, middle-click starts/stops a session,
  right-click mutes/unmutes alerts without stopping tracking.
- Popout: live scrolling lip-gap chart with a threshold reference line, distance-compensation
  readout, running session stats, and the last 5 sessions from history with a Start/Stop button.
- Control Center tile: toggleable state summary (Off / Tracking / Mouth open / No face / Paused)
  that expands into a detail panel with a compact chart and an Open time / Events summary on
  wide-enough grids.
- 30-session history, persisted across restarts.
- Five synthesized alert sounds (soft beep, chime, double beep, buzz, high ping) plus a "none"
  option, with an adjustable volume and per-sound relative gain to preserve their original
  relative loudness.
- Optional live gap readout in the bar pill itself (`showGapInPill`).
- Desktop notifications on alert, rate-limited independently of the detection window to avoid a
  notification storm at very short window settings.

### Packaging and dependencies

- `plugin.json`: composite plugin (`daemon`, `dankbar-widget`, `control-center` capabilities),
  requires DMS `>=1.5.0`, depends on `python3`, `python-opencv`, `python-dlib`.
- `StartupCheck.qml`: verifies `python3 -c 'import cv2, dlib'` on load and surfaces per-distro
  install hints inline if it fails.
- Bundled Nix flake (`flake.nix`) providing a dev shell and a packaged detector with dlib,
  OpenCV, and the landmark model pinned together.
