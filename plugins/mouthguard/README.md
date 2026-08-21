# MouthGuard

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (DMS) plugin that watches
your webcam and alerts you when your mouth has been open too long — useful if you're trying to
train yourself into habitual nasal breathing / mouth closure. It is a native port of the
browser-based app at **[github.com/sitolam/mouthguard](https://github.com/sitolam/mouthguard)**:
same detection logic and alerting behaviour, reimplemented as a DMS daemon + bar pill instead of a
page you keep open in a tab. Face tracking runs locally via [dlib](http://dlib.net/); nothing
leaves your machine.

> **Screenshot:** not yet included. Capturing one requires enabling the plugin and opening the
> popout with a live session running, which this documentation pass deliberately did not do — it
> would mean touching a camera device and a live shell that belong to someone else. The project
> owner will add `screenshot.png` and a `![MouthGuard popout](screenshot.png)` line here once
> captured.

## Requirements

- **DMS** `>=1.5.0` (see `plugin.json`)
- A working detector command — either of:
  - the flake-built wrapper (`nix build .#detector`), **required on NixOS** — see below, or
  - **python3** with the **`cv2`** (OpenCV) and **`dlib`** modules installed system-wide
- The dlib 68-point face landmark model, `shape_predictor_68_face_landmarks.dat` (~95 MB /
  99.7 MB on disk)

**On NixOS, the system `python3` will not have `cv2`/`dlib`** — there is no "system install" for
them here — so `nix build .#detector` inside the plugin directory is the supported path, not an
alternative. `StartupCheck.qml` and `MouthGuardDaemon.qml` share one resolution rule: use
`<plugin dir>/result/bin/mouthguard-detector` if it exists and is executable, otherwise fall back
to `python3 <plugin dir>/detector.py`. The startup check runs whichever of those it picks with
`--self-test` and requires a real `"ready"` response — a stale `result` symlink (e.g. its nix
store path was garbage-collected) is treated as broken, not silently trusted — and reports an
inline hint covering both the Nix and per-distro cases if that fails. The model file is resolved
separately at detector start time (see [The landmark model](#the-landmark-model) below) and is
**not** covered by that startup check.

**`result` is gitignored.** A fresh clone has no detector command until you build one — see
below.

### Install the Python dependencies

**Nix (NixOS, or anyone who wants the pinned/self-contained build):** from the plugin directory —
```bash
nix build .#detector
```
This produces `result -> /nix/store/.../mouthguard-detector`, a self-contained wrapper bundling
the pinned interpreter, `dlib`, `opencv4`, `numpy`, and `face-recognition-models` (which supplies
the landmark model). `nix develop -c python3 detector.py --self-test` also works, for a quick
check without building the wrapper, but the daemon itself needs the `result` build to exist —
plain `python3` on NixOS's ambient interpreter has neither module.

**Arch:**
```bash
sudo pacman -S python-opencv python-dlib
```

**Fedora:**
```bash
sudo dnf install python3-opencv python3-dlib
```

**Debian / Ubuntu:**
```bash
sudo apt install python3-opencv python3-dlib
```

### The landmark model

`mouthguard_core.resolve_model_path()` looks for `shape_predictor_68_face_landmarks.dat`, in
order:

1. `face_recognition_models` package, if installed (this is what the bundled Nix flake provides)
2. `/usr/share/dlib/shape_predictor_68_face_landmarks.dat`
3. `/usr/share/dlib-models/shape_predictor_68_face_landmarks.dat`
4. `~/.cache/mouthguard/shape_predictor_68_face_landmarks.dat`
5. the path in the `MOUTHGUARD_MODEL` environment variable, if set (checked first if present, and
   raises immediately rather than falling through if it points at a missing file)

None of Arch, Fedora, or Debian's `python-dlib`/`python3-dlib` packages above bundle this model.
If your distro doesn't provide it in `/usr/share/dlib*`, download it separately (dlib's own
[dlib-models](https://github.com/davisking/dlib-models) repository is the canonical upstream
source) and place it at `~/.cache/mouthguard/shape_predictor_68_face_landmarks.dat`, or set
`MOUTHGUARD_MODEL` to wherever you put it.

### Install the plugin

Via DMS's plugin manager:
```bash
dms plugins install mouthGuard
```

Or manually:
```bash
git clone https://github.com/sitolam/dms-mouthguard ~/.config/DankMaterialShell/plugins/MouthGuard
```

Either way, **on NixOS run `nix build .#detector` inside that plugin directory before enabling
it** — `result` is gitignored, so neither a fresh clone nor a fresh install via the plugin manager
brings one along, and without it the startup check has only the ambient `python3` fallback to try
(see [Requirements](#requirements) above).

Then enable it from DMS's plugin settings. `plugin.json` declares `capabilities: ["daemon",
"dankbar-widget", "control-center"]`, `requires_dms: ">=1.5.0"`, and
`permissions: ["settings_read", "settings_write", "process"]` (the last is what lets it spawn
`detector.py`).

## Usage

Once enabled, MouthGuard adds an icon to the bar (or the vertical side-bar, depending on your
DMS layout) that changes with tracking state (`videocam_off` / `sentiment_satisfied` /
`warning` / `face_retouching_off` / `pause_circle` for inactive / closed / open / no-face /
paused respectively) and a color shift (red when open, dimmed when idle).

| Click | Action |
|---|---|
| Left click | Open the popout (chart, live stats, and the last 5 sessions) |
| Middle click | Start or stop a tracking session |
| Right click | Mute or unmute alerts (sound + notifications) without stopping the session |

The **popout** shows a live scrolling lip-gap chart with a threshold line, the distance
compensation readout (face size / adjusted gap, when compensation is on), running Open / Closed /
Away / Events counters for the current session, and the last 5 sessions from history with a
Start/Stop button.

MouthGuard also registers a **Control Center tile**: the tile itself shows state as primary/
secondary text ("Off" / "Tracking" / "Mouth open" / "No face" / "Paused"), is toggleable directly
from the tile, and — on a wide enough Control Center grid — expands into a detail panel with a
compact version of the same chart plus an Open time / Events summary.

## Settings

All settings are edited from DMS's plugin settings panel (`MouthGuardSettings.qml`). Two of them
are stored in integer-native units rather than their "natural" real-world units — see
[Why threshold and alertDelay use odd units](#why-threshold-and-alertdelay-use-odd-units) below
before comparing a stored value against `CALIBRATION.md`.

| Setting | Key | Control | Range | Default | Unit |
|---|---|---|---|---|---|
| Camera | `device` | selection | `/dev/video0`, `/dev/video1` | `/dev/video0` | — |
| Sensitivity threshold | `threshold` | slider | 10 – 100 | 35 | tenths of a gap-unit (px) |
| Detection window | `alertDelay` | slider | 0 – 10000 | 1000 | milliseconds |
| Distance compensation | `distanceCompensation` | toggle | — | on | — |
| Alert sound | `soundType` | selection | soft / chime / double / buzz / ping / none | soft | — |
| Volume | `volume` | slider | 0 – 100 | 85 | % |
| Desktop notifications | `notifications` | toggle | — | on | — |
| Detection rate | `fps` | slider | 5 – 15 | 10 | fps |
| Stop after no face | `noFaceTimeout` | slider | 0 – 15 (0 = disabled) | 5 | minutes |
| Pause when locked or idle | `autoPause` | toggle | — | on | — |
| Show gap value in the bar | `showGapInPill` | toggle | — | off | — |

Notes on a few of these:

- **Sensitivity threshold** — lower is more sensitive. The calibrated default of 35 corresponds
  to a real gap of **3.5 px** on this camera; see `CALIBRATION.md` for how that number was
  derived and `tools/calibrate.py` to re-derive it for your own camera.
- **Detection window** — the mouth must stay open continuously for this entire duration before
  it counts as an "open" event and an alert fires. Briefer openings are discarded — see
  [Statistics and detection semantics](#statistics-and-detection-semantics).
- **Detection rate** — measured throughput on the reference hardware is roughly 5–6 fps in
  practice; values near the top of the slider's range are unlikely to be reached even though the
  control allows them.
- **Show gap value in the bar** — shows the live gap number (the same value compared against the
  threshold — the distance-compensated value when compensation is on, the raw value otherwise)
  next to the pill's icon, once tracking has started. Only appears on the horizontal bar pill;
  the vertical pill is too narrow.

### Why threshold and alertDelay use odd units

DMS 1.5.3's `SliderSetting` (which wraps `DankSlider`) is integer-only end to end — both declare
plain `property int value`, `DankSlider` rounds every drag/wheel update with `Math.round()`, and
neither exposes `from`, `to`, or `stepSize` for fractional control. Rather than build a custom
slider control just for two settings, both were given integer-native units instead:

- **`threshold`** is stored in **tenths of a gap-unit**. The calibrated real value is 3.5 px
  (`mouthguard_core.DEFAULT_THRESHOLD`); the slider stores and displays `35`.
  `MouthGuardDaemon.qml` divides `pluginData.threshold` by 10 to recover 3.5.
- **`alertDelay`** is stored directly in **milliseconds** rather than the original web app's
  0–10 s / 0.1 s-step range. This is finer-grained than the original, not coarser — a plain
  integer millisecond range comfortably exceeds 0.1 s precision. `MouthGuardDaemon.qml` reads it
  as-is, with no `* 1000`.

If you're cross-checking a stored value (e.g. `35` in DMS's saved plugin state) against
`CALIBRATION.md`'s `3.5`, this is why they don't match at face value — divide by 10.

## How it works

`detector.py` is a **policy-free sensor**: it opens the camera, runs dlib's HOG face detector and
68-point landmark predictor, and streams one JSON line per frame to stdout — a face's lip gap and
face height, or a bare no-face measurement. It has no concept of a threshold, a detection window,
or an alert; it only measures and reports.

`MouthGuardDaemon.qml` (with the ported `StateMachine.js`) owns every policy decision: the
threshold comparison, distance compensation, the detection-window state machine, alert delivery
(sound + desktop notification), auto-pause on lock/idle/sleep, session stats, and history.

This split exists so that **settings changes apply live, without restarting the camera.**
Because thresholds, the detection window, distance compensation, and alert sound/volume/
notification behaviour are all read reactively from `pluginData` inside the QML daemon, changing
any of them from the settings panel takes effect on the very next measurement line — no detector
process restart, and no re-paying the ~1 s dlib model load or the camera's warm-up period (see
[Limitations](#limitations)).

The daemon also drives `detector.py` with two stdin commands, `pause` and `resume`, used for
auto-pause (screen lock, idle, suspend): `pause` releases the camera device (so the camera's LED
goes off) while keeping the dlib model resident in memory, and `resume` reopens the device. This
avoids paying the model-load cost on every lock/unlock cycle.

## Statistics and detection semantics

These are easy to misread, so stated explicitly:

- A session's **Open + Closed + Away (unmeasured)** time should account for the whole session.
- **"Away" / unmeasured** time accrues whenever no face is visible in frame, *and* across every
  auto-pause gap (screen lock, idle, suspend) — both are "no measurement was possible" and are
  reconciled the same way.
- The **history percentage** (shown per past session in the popout, e.g. "62% open (of
  measured)") is **percent of MEASURED time** (`open ÷ (open + closed)`) — Away time is
  deliberately excluded from that denominator, so a session with a long lock-screen gap doesn't
  read as mostly "closed."
- **Detection requires the mouth to stay open for the full detection window** (`alertDelay`)
  continuously. If it closes before the window elapses, nothing is recorded and no alert fires —
  this is deliberate, to keep brief/incidental openings from counting as events or triggering
  alerts.

## Limitations

These were each found the hard way during development (see `CALIBRATION.md` for the full detail
behind the calibration- and camera-related ones) and are worth knowing before you rely on this
plugin:

- **dlib's HOG face detector has a minimum detectable face size, roughly 80×80 px.** At the
  default 640×480 capture resolution, detection is reliable at normal seated distance from the
  camera, but degrades as you move farther back, and at arm's length it may not find a face at
  all. `detector.py --width` / `--height` lower this floor's real-world distance further — the
  detector runs at full capture resolution with no downscale, so shrinking the capture size
  shrinks the usable seating-distance range too.
- **Off-angle robustness is worse than the original browser version's MediaPipe.** A turned head
  reads as "no face" rather than firing a false alert, which is the safer failure mode, but it is
  a genuine accuracy regression compared to the web app this was ported from.
- **Camera warm-up costs roughly the first 7 seconds of every session.** A cold-started UVC
  camera takes about that long to auto-expose before it produces a usable measurement. This
  applies at the start of every session, and again after every auto-pause resume (lock/idle/sleep)
  — the initial silence after starting or resuming is expected, not a sign the tracker isn't
  working.
- **DMS's built-in camera privacy indicator will most likely NOT light up while MouthGuard is
  tracking.** `PrivacyService.cameraActive` is derived from PipeWire; this plugin opens the
  camera directly via V4L2 (`cv2.VideoCapture(..., cv2.CAP_V4L2)`), which PipeWire doesn't see.
  **The plugin's own bar pill is the honest signal of whether your camera is in use** — do not
  rely on DMS's shell-wide privacy indicator to tell you MouthGuard's camera is off.
- **The landmark model is large** — roughly 95 MB (99.7 MB decimal) on disk — and is not bundled
  in this repository; see [The landmark model](#the-landmark-model) above.
- **Thresholds are calibrated for one person, one camera, and one lighting setup** (Logitech UVC
  046d:0990, recorded 2026-08-02 — see `CALIBRATION.md`). They will not necessarily transfer to a
  different camera or face. Re-tune with `tools/calibrate.py` and the procedure documented in
  `CALIBRATION.md` if detection feels wrong on your setup.

## Testing

Three independent test suites cover this plugin — Python unit tests, and two separate QML test
files (they must be run separately; `qmltestrunner` only accepts one `-input` file at a time):

```bash
nix develop -c pytest -q
nix develop -c qmltestrunner -input tests/tst_statemachine.qml
nix develop -c qmltestrunner -input tests/tst_gapchart_math.qml
```

Expected: `pytest` reports `33 passed`; each `qmltestrunner` run reports `28 passed` and
`10 passed` respectively, both with `Totals: N passed, 0 failed, ...` and process exit code `0`.

**Note on `qmltestrunner`'s exit code:** it is the **failure count**, not a flat `1` on any
failure — `0` means all passed, and a nonzero exit code equals the number of failing test
functions, not just "something failed."

## License

MIT — see `LICENSE`.
