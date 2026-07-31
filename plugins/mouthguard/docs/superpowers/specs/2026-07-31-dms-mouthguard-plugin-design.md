# MouthGuard DMS Plugin — Design

**Date:** 2026-07-31
**Status:** Approved, ready for implementation planning

## Context

[MouthGuard](https://github.com/sitolam/mouthguard) is a single-file browser app (`index.html`,
~1600 lines) that tracks whether the user's mouth is open. It runs MediaPipe Face Mesh on webcam
frames, measures the gap between inner-lip landmarks 13 and 14, and alerts when the mouth stays
open past a configurable detection window. It is at v1.3.1 and works well, but it only exists as a
browser tab — it needs a tab open, and its alerts (tab-title blinking, browser notifications) are
weak signals on a Linux desktop.

DankMaterialShell (DMS) is a Quickshell/QML desktop shell with a plugin registry. A DMS plugin
would put mouth state in the bar as an always-visible pill, deliver real desktop notifications,
and survive without a browser tab.

This is a **port, not a translation**. DMS plugins are QML with no browser and no ML runtime, so
the detection engine has to be rebuilt as a helper process. The intended outcome is a standalone
plugin repo, eventually submitted to the DMS plugin registry.

## Goals

- Bar pill showing live mouth state, with popout and Control Center integration
- Feature parity with the web app: threshold, detection window, distance compensation, live lip
  gap chart, session stats, 30-session history, sound alerts
- Installs on NixOS without pip, venv, or FHS wrappers
- Camera is never open longer than it needs to be

## Non-goals

- Replacing or modifying the web app — `sitolam/mouthguard` stays as-is
- Numeric parity with MediaPipe's gap values (see Calibration)
- Multi-face tracking — largest detected face wins
- Registry submission in this milestone (the JSON is written last, after the plugin is proven)

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Detection backend | dlib 68-point | `dlib`, `opencv4`, `face-recognition-models` are all in nixpkgs and build for Python 3.14 from the binary cache. `mediapipe` is not in nixpkgs and caps at Python 3.13. |
| Repo | New `sitolam/dms-mouthguard` | Matches how every registry plugin is laid out; no web-app baggage in a `dms plugins install` clone. |
| Surfaces | Composite: daemon + widget | Detection keeps running regardless of bar layout. Same shape as `takeABreak` and `typingSounds`. |
| Camera lifecycle | Manual toggle, remembers state, auto-pauses | Privacy and battery, without a click every login. |
| Alerts | Pill + notification + sound | Direct analog of the web app. No full-screen overlay. |
| No face | Pause accounting, auto-stop after timeout | Keeps stats honest; releases the camera when the user walks off. |
| Portability | StartupCheck + docs + `flake.nix` | Guaranteed-correct interpreter for Nix users, clear install hints for everyone else. |

## Architecture

```
dms-mouthguard/
  plugin.json              composite manifest
  MouthGuardDaemon.qml     detector lifecycle, state machine, alerts, stats, persistence
  MouthGuardWidget.qml     bar pill + popout + CC tile
  MouthGuardSettings.qml   PluginSettings
  StartupCheck.qml         dependency probe
  detector.py              webcam -> landmarks -> JSON lines
  flake.nix                pinned python env
  sounds/*.wav             5 alert sounds
  tools/gen-sounds.py      regenerates sounds from index.html's Web Audio params
  README.md  LICENSE  CHANGELOG.md  screenshot.png
```

### Process boundary

`detector.py` is a **dumb sensor holding no policy**. It emits measurements; every threshold,
timer, and alert rule lives in QML. Consequence: changing sensitivity or alert delay in settings
applies live, without restarting the camera — something the web app cannot do.

**stdout** — one JSON object per line, ~10/sec:

```json
{"ready":true,"backend":"dlib","device":"/dev/video0","fps":10}
{"t":1712.4,"gap":4.21,"face":118.3}
{"t":1712.5,"face":0}
{"error":"camera_busy","detail":"/dev/video0: Device or resource busy"}
```

- The `ready` handshake is emitted once, before any measurement. QML uses it to distinguish a
  healthy start from a camera that is busy or missing.
- `face: 0` means no face this frame. `gap` is absent in that case.
- `error` objects are terminal; the process exits non-zero after emitting one.

**stdin** — line-delimited commands: `pause`, `resume`, `quit`.

`pause` calls `cap.release()` (camera LED off) but keeps the dlib model resident, so `resume` is
instant rather than paying the ~1 s cost of reloading a 96 MB predictor. The process is only killed
on a full session stop.

**stderr** — human-readable diagnostics only, never parsed.

QML consumes stdout with `Process` + `SplitParser { splitMarker: "\n" }`, the pattern
`typingSounds/TypingSoundsDaemon.qml:319` uses for `libinput debug-events`.

### Landmark mapping

| Quantity | MediaPipe (web app) | dlib 68-point (plugin) |
|---|---|---|
| Inner lip gap | `abs(lm[13].y - lm[14].y) * H` | `hypot(lm[62], lm[66])` |
| Face height | `hypot(lm[1], lm[152])` nose→chin | `hypot(lm[30], lm[8])` nose-tip→chin |

The web app measures the gap as a raw Y delta and uses `hypot` only for face height. The port uses
`hypot` for both — a deliberate improvement, not a faithful copy: dlib returns pixel coordinates
directly, so there is no normalisation step to undo, and `hypot` stops mild head tilt from
shrinking the apparent gap. This is the same reasoning behind v1.3.1's switch to nose→chin, where
that landmark stays fully in frame at close distances while a forehead landmark drifts toward the
frame edge and under-compensates.

Distance compensation keeps the web app's formula: `adj = gap * (REF / face)`, with `adj` compared
against the threshold when compensation is enabled and raw `gap` when it is not.

### Calibration

**MouthGuard's tuned defaults do not transfer.** dlib's inner-lip landmarks produce a different
numeric scale than MediaPipe's, so both the default threshold (`5`) and the distance-compensation
reference (`100 px`) are meaningless here and must be re-derived empirically against a real webcam
before the plugin is usable. This is a required implementation step, not a polish item.

Method: run `detector.py` standalone, record gap distributions for closed mouth, slightly open, and
clearly open, at near and far seating distances. Pick the threshold to separate closed from
slightly-open, and pick `REF` as the median `face` value at normal seating distance. Document both
numbers and how they were obtained in the README.

### Performance

- Capture at 640×480, run detection on a 320×240 downscale
- Run the HOG face detector only every Nth frame (default 5); between detections reuse the last
  face rect and run only the 68-point predictor, which is ~1 ms
- Re-detect immediately if the predictor's output drifts outside the cached rect
- Target 10 fps, configurable

## Behaviour

### State machine

Ported from `index.html`. Lives in `MouthGuardDaemon.qml`, driven by measurement lines.

States: `inactive` → `closed` | `opening` | `open` | `noface` | `paused`

- `gap`/`adj` over threshold starts `opening` and a detection-window timer
- Staying over threshold for the **full** window confirms `open`: the window's elapsed time is
  retroactively added to time-open, and the alert fires
- Dropping below threshold during `opening` discards the event entirely — no alert, nothing
  recorded. This is v1.2.2's false-positive fix and must be preserved
- While `open`, the alert re-arms every detection window
- Dropping below threshold → `closed` immediately; sound and pill state stop at once
- No face for >1 s → `noface`: alerts suppressed, elapsed time accrues to `unmeasured` rather than
  open or closed
- No face for > `noFaceTimeout` (default 5 min, 0 disables) → session stops, history written,
  toast shown, detector process exits

### Auto-pause

Detector is paused (not killed) whenever:

```qml
SessionService.locked || SessionService.idleHint
  || SessionService.preparingForSleep || IdleService.monitorsOff
```

`SessionService` also exposes `sessionLocked` / `sessionUnlocked` / `sessionResumed` signals for
edge-triggered handling. Paused time accrues to `unmeasured`.

### Alerts

On confirmed open: pill switches to `Theme.error` with a `warning` icon, a desktop notification
fires, and the configured sound plays via QtMultimedia `SoundEffect`. All three stop the moment
the mouth closes. Re-arms every detection window while open. Right-clicking the pill mutes alerts
for the current session without stopping tracking.

The web app's tab-title blinking has no desktop analog and is dropped.

## Surfaces

### Daemon — `MouthGuardDaemon.qml`

Owns the `Process`, the state machine, stats accumulation, and persistence. Registers itself in
`pluginService.pluginInstances[pluginId]` on completion and removes itself on destruction — the
pattern `typingSounds/TypingSoundsDaemon.qml:58-81` uses. This is what keeps a multi-monitor setup
from spawning one detector per bar instance.

### Widget — `MouthGuardWidget.qml`

Looks up the daemon via `pluginService.pluginInstances[pluginId]` to read live state and call
`toggle()`.

**Pill states:**

| State | Icon | Colour |
|---|---|---|
| inactive | `videocam_off` | muted |
| closed | `sentiment_satisfied` | `Theme.surfaceText` |
| open | `warning` | `Theme.error`, subtle pulse |
| noface | `face_retouching_off` | muted |
| paused | `pause_circle` | muted |

Optional live gap readout next to the icon (setting, off by default). Both `horizontalBarPill` and
`verticalBarPill` are required — omitting the vertical one makes the widget vanish on side-mounted
bars.

Click opens the popout, middle-click toggles the session, right-click mutes alerts.

**Popout (~420×380):**

- Header: session state and elapsed time
- `Canvas` chart: 60 s rolling lip gap with a dashed threshold line in `Theme.error`, plotting
  `adj` when compensation is on and `gap` when off, so the threshold line stays meaningful.
  `systemMonitorPlus/SystemMonitorPlusPill.qml:86` confirms `Canvas` works in DMS plugins
- Readouts when compensation is on: face size, adjusted gap
- Stats row: time open / closed / unmeasured, event count, average open duration
- History list, last 30 sessions, with `% open` bars and the web app's
  `bar & % = time mouth was open` subtitle
- Start/Stop button

### Control Center

`ccWidgetIcon`, `ccWidgetPrimaryText: "MouthGuard"`, `ccWidgetSecondaryText` reflecting state,
`ccWidgetIsActive` bound to the session, `onCcWidgetToggled` starting/stopping. `ccDetailContent`
provides a compact chart plus stats, which promotes the tile to a CompoundPill at 50% width.

## Settings

`PluginSettings` with `pluginId: "mouthGuard"`. Requires `settings_write` in the manifest or the
settings UI errors.

| Key | Component | Default |
|---|---|---|
| `device` | SelectionSetting, enumerated from `/dev/video*` | first found |
| `threshold` | SliderSetting | **TBD — from calibration** |
| `alertDelay` | SliderSetting, 0–10 s, 0.1 step | 1.0 |
| `distanceCompensation` | ToggleSetting | true |
| `soundType` | SelectionSetting, 5 sounds + none | soft beep |
| `volume` | SliderSetting | 85 |
| `notifications` | ToggleSetting | true |
| `fps` | SliderSetting, 5–15 | 10 |
| `noFaceTimeout` | SliderSetting, 0–15 min | 5 |
| `autoPause` | ToggleSetting | true |
| `showGapInPill` | ToggleSetting | false |

`threshold`'s default is filled during the calibration step, not left for the user to discover.

`distanceRef` is deliberately **not** a setting. v1.3.1 removed the web app's Calibrate button
after finding that a fixed reference works without per-session calibration and that stale persisted
values silently overrode it. The plugin keeps that lesson: `REF` is a constant in
`MouthGuardDaemon.qml`, set once from calibration.

## Persistence

- `pluginService.savePluginData(pluginId, key, value)` — all settings plus `active`, so the session
  resumes at login
- `pluginService.savePluginState(pluginId, "history", [...])` — last 30 sessions, the analog of the
  web app's `localStorage` history

## Sounds

The web app synthesizes its five alerts (soft beep, chime, double beep, buzz, high ping) with the
Web Audio API, which has no QML equivalent. They are rendered once to `.wav` files and played with
QtMultimedia `SoundEffect`, wrapped as in `typingSounds/SoundEffectWrapper.qml`.

`tools/gen-sounds.py` regenerates them from the same oscillator/envelope parameters used in
`index.html`, so the assets stay reproducible rather than being opaque binaries.

## Portability

`StartupCheck.qml` probes in order and calls `done(null)` on first success:

1. The flake env, if `flake.nix` and `nix` are both present
2. `python3 -c "import cv2, dlib"` plus model resolution

On failure it returns `{ title, details }` with per-distro install hints (Arch `python-dlib`,
Fedora `python3-dlib`, Debian `python3-dlib`, Nix: use the bundled flake). Failures surface as a
toast and land in `pluginService.pluginLoadErrors`.

`detector.py` resolves the landmark model in order:

1. `$MOUTHGUARD_MODEL`
2. `import face_recognition_models` → `pose_predictor_model_location()`
3. `/usr/share/dlib/`, `~/.cache/mouthguard/`

Manifest declares `"dependencies": ["python3", "python-opencv", "python-dlib"]`.

## Known limitations

To be stated plainly in the README, not discovered by users:

- **Reduced off-angle accuracy.** dlib's HOG detector loses the face past roughly 30° of head turn,
  where MediaPipe still tracked. Auto-pause absorbs this as `noface` rather than firing false
  alerts, but it is a genuine regression against the web app.
- **No DMS privacy indicator.** `PrivacyService.cameraActive` is derived from PipeWire nodes;
  OpenCV opens V4L2 directly, so the shell's built-in camera indicator will most likely not light
  up. The plugin's own pill is the honest signal.
- **96 MB model.** Ships via `face-recognition-models` on Nix; elsewhere it comes from the distro's
  dlib data package.

## Verification

1. **Detector standalone** — `python3 detector.py --device /dev/video0`, confirm the `ready`
   handshake, a steady ~10 lines/sec, plausible `gap`/`face` values, and that `gap` rises clearly
   when the mouth opens. Confirm `pause` on stdin turns the camera LED off and `resume` restores
   the stream.
2. **Calibration** — capture the distributions described above, set `threshold` and `distanceRef`.
3. **Plugin load** — copy to `~/.config/DankMaterialShell/plugins/MouthGuard/`, then
   `dms ipc plugin-scan scan` and `dms ipc plugin-scan status mouthGuard`. Run the shell with
   `qs -v` to see QML errors.
4. **End-to-end** — enable the plugin, add the pill to a bar section, start a session, hold the
   mouth open past the window, and confirm pill colour, notification, and sound all fire and all
   stop on close. Confirm a brief opening below the window fires nothing.
5. **Auto-pause** — lock the session, confirm the camera LED goes off and the process survives;
   unlock and confirm tracking resumes without a reload stall.
6. **No-face auto-stop** — set `noFaceTimeout` to 1 min, walk away, confirm the session stops, the
   toast appears, and the session lands in history.
7. **Persistence** — restart the shell, confirm settings and history survive and that `active`
   resumes.
8. **Vertical bar** — move the DankBar to a side edge and confirm the pill still renders.

## Build order

1. `detector.py` + calibration
2. Manifest + daemon + minimal pill — end-to-end alerting
3. Settings + persistence
4. Popout: chart, stats, history
5. Sounds, CC tile, StartupCheck, `flake.nix`
6. README, screenshot, CHANGELOG

Registry submission (`plugins/sitolam-mouthguard.json`, `"id": "mouthGuard"` matching
`plugin.json`, category `monitoring`) is deliberately out of scope until the plugin is proven in
daily use.
