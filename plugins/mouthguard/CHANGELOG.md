# Changelog

All notable changes to the MouthGuard DMS plugin are documented here.

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
