# MouthGuard

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (DMS) plugin that watches
your webcam and alerts you when your mouth has been open too long — useful if you're trying to
train yourself into habitual nasal breathing / mouth closure. It is a native port of the
browser-based app at **[github.com/sitolam/mouthguard](https://github.com/sitolam/mouthguard)**:
same detection logic and alerting behaviour, reimplemented as a DMS daemon + bar pill instead of a
page you keep open in a tab. Face tracking runs locally, on the same
[MediaPipe Face Mesh](https://ai.google.dev/edge/mediapipe/solutions/vision/face_landmarker) model
the web app uses, through [OpenVINO](https://docs.openvino.ai/) — on an Intel NPU where one is
available, otherwise the iGPU or the CPU. Nothing leaves your machine.

> **Screenshot:** not yet included. Capturing one requires enabling the plugin and opening the
> popout with a live session running, which this documentation pass deliberately did not do — it
> would mean touching a camera device and a live shell that belong to someone else. The project
> owner will add `screenshot.png` and a `![MouthGuard popout](screenshot.png)` line here once
> captured.

## Requirements

- **DMS** `>=1.5.0` (see `plugin.json`)
- A working detector command — either of:
  - the flake-built wrapper (`nix build .#detector`), **required on NixOS** — see below, or
  - **python3** with the **`cv2`** (OpenCV) and **`openvino`** modules installed system-wide
- The two MediaPipe model files, `face_detection_short_range.tflite` (229 KB) and
  `face_landmark.tflite` (1.2 MB). The flake fetches both; see
  [The models](#the-models) below for doing it by hand.

**On NixOS, the system `python3` will not have `cv2`/`openvino`** — there is no "system install" for
them here — so `nix build .#detector` inside the plugin directory is the supported path, not an
alternative. `StartupCheck.qml` and `MouthGuardDaemon.qml` share one resolution rule: use
`<plugin dir>/result/bin/mouthguard-detector` if it exists and is executable, otherwise fall back
to `python3 <plugin dir>/detector.py`. The startup check runs whichever of those it picks with
`--self-test` and requires a real `"ready"` response — a stale `result` symlink (e.g. its nix
store path was garbage-collected) is treated as broken, not silently trusted — and reports an
inline hint covering both the Nix and per-distro cases if that fails. On the `python3` branch it
additionally probes the imports and the model directory, because `--self-test` deliberately
returns before either is touched.

**`result` is gitignored.** A fresh clone has no detector command until you build one — see
below.

### Install the Python dependencies

**Nix (NixOS, or anyone who wants the pinned/self-contained build):** from the plugin directory —
```bash
nix build .#detector
```
This produces `result -> /nix/store/.../mouthguard-detector`, a self-contained wrapper bundling
the pinned interpreter, `openvino`, `opencv4`, `numpy`, both MediaPipe model files, and the NPU
runtime (see [Using the NPU](#using-the-npu)). `nix develop -c python3 detector.py --self-test`
also works, for a quick check without building the wrapper, but the daemon itself needs the
`result` build to exist — plain `python3` on NixOS's ambient interpreter has neither module.

**Arch:**
```bash
sudo pacman -S python-opencv python-openvino
```

**Fedora:**
```bash
sudo dnf install python3-opencv python3-openvino
```

**Debian / Ubuntu:**
```bash
sudo apt install python3-opencv python3-openvino
```

### The models

Both files come from MediaPipe's asset bucket, and are the same ones the web app's
`@mediapipe/face_mesh` 0.4 loads:

- `face_detection_short_range.tflite` — BlazeFace, finds the face
- `face_landmark.tflite` — the 468-point mesh, measures the lips

OpenVINO reads TFLite directly, so neither needs converting.
`mouthguard_core.resolve_model_dir()` looks for a directory holding **both**, in order:

1. `MOUTHGUARD_MODEL_DIR`, if set (checked first, and raises immediately rather than falling
   through if that directory is missing either file)
2. `/usr/share/mouthguard`
3. `/usr/share/mediapipe/models`
4. `~/.cache/mouthguard`

The Nix wrapper sets `MOUTHGUARD_MODEL_DIR` to a pinned store path, so nothing else is needed
there. Otherwise, fetch them by hand:

```bash
mkdir -p ~/.cache/mouthguard && cd ~/.cache/mouthguard
curl -LO https://storage.googleapis.com/mediapipe-assets/face_detection_short_range.tflite
curl -LO https://storage.googleapis.com/mediapipe-assets/face_landmark.tflite
```

### Using the NPU

The detector asks OpenVINO for an **NPU** first, then a **GPU**, then the **CPU**, and falls
through to the next one if a device is present but fails to compile the models. Whichever it lands
on is reported in the `ready` line as `mediapipe/<device>`, and can be forced with
`--inference-device`. On this machine the three measure at roughly 0.6 ms, 1.0 ms and 1.5 ms per
inference, against a 100 ms budget at the default 10 fps — so the NPU is a power win, not a
latency requirement, and there is nothing to fix if you land on GPU or CPU.

Reaching an Intel NPU takes three pieces, all of which the flake wires up for you:

- the kernel driver (`intel_vpu`, giving you `/dev/accel/accel0`) — from your kernel
- the Level Zero loader and Intel's NPU userspace driver — on NixOS, `level-zero` and
  `intel-npu-driver` in `hardware.graphics.extraPackages`
- Intel's NPU graph compiler, which nixpkgs does not package. Without it OpenVINO enumerates the
  NPU and then fails every compile with `ZE_RESULT_ERROR_UNSUPPORTED_FEATURE`. The flake fetches
  it from the matching `linux-npu-driver` release and places it beside OpenVINO's own libraries,
  which is the only place OpenVINO will look for it.

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
before comparing a stored value against anything in the source.

| Setting | Key | Control | Range | Default | Unit |
|---|---|---|---|---|---|
| Camera | `device` | selection | `/dev/video0`, `/dev/video1` | `/dev/video0` | — |
| Sensitivity threshold | `meshThreshold` | slider | 10 – 100 | 50 | tenths of a gap-unit (px) |
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

- **Sensitivity threshold** — lower is more sensitive. The default of 50 is a real gap of
  **5.0 px**, the web app's value, and needs no per-camera calibration: distance compensation
  normalises every gap against your own nose-to-chin distance in the same frame, so seating
  distance and camera geometry divide out. The key is `meshThreshold`, not `threshold` — a value
  saved against the old dlib pipeline meant something else on a different scale, and lapses to
  this default rather than being reinterpreted.
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

- **`meshThreshold`** is stored in **tenths of a gap-unit**. The real value is 5.0 px
  (`mouthguard_core.DEFAULT_THRESHOLD`); the slider stores and displays `50`.
  `MouthGuardDaemon.qml` divides `pluginData.meshThreshold` by 10 to recover 5.0.
- **`alertDelay`** is stored directly in **milliseconds** rather than the original web app's
  0–10 s / 0.1 s-step range. This is finer-grained than the original, not coarser — a plain
  integer millisecond range comfortably exceeds 0.1 s precision. `MouthGuardDaemon.qml` reads it
  as-is, with no `* 1000`.

If you're cross-checking a stored value (e.g. `50` in DMS's saved plugin state) against
`DEFAULT_THRESHOLD`'s `5.0`, this is why they don't match at face value — divide by 10.

## How it works

`detector.py` is a **policy-free sensor**: it opens the camera, runs MediaPipe's BlazeFace
detector and 468-point Face Mesh model through OpenVINO, and streams one JSON line per frame to
stdout — a face's lip gap and
face height, or a bare no-face measurement. It has no concept of a threshold, a detection window,
or an alert; it only measures and reports.

`MouthGuardDaemon.qml` (with the ported `StateMachine.js`) owns every policy decision: the
threshold comparison, distance compensation, the detection-window state machine, alert delivery
(sound + desktop notification), auto-pause on lock/idle/sleep, session stats, and history.

This split exists so that **settings changes apply live, without restarting the camera.**
Because thresholds, the detection window, distance compensation, and alert sound/volume/
notification behaviour are all read reactively from `pluginData` inside the QML daemon, changing
any of them from the settings panel takes effect on the very next measurement line — no detector
process restart, and no re-paying the model compile or the camera's warm-up period (see
[Limitations](#limitations)).

The daemon also drives `detector.py` with two stdin commands, `pause` and `resume`, used for
auto-pause (screen lock, idle, suspend): `pause` releases the camera device (so the camera's LED
goes off) while keeping the compiled models resident, and `resume` reopens the device. This avoids
recompiling for the inference device on every lock/unlock cycle.

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

These were each found the hard way during development, and are worth knowing before you rely on
this plugin:

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
- **Only one face is tracked** — the highest-scoring detection wins, and MediaPipe's tracking
  then follows that face until it is lost. A second person entering frame does not confuse the
  measurement, but neither are they measured.
- **The NPU needs a graph compiler that no distribution packages.** The flake fetches Intel's,
  pinned to the driver release it matches; outside Nix you are on the GPU or the CPU unless you
  install it yourself. See [Using the NPU](#using-the-npu).

## Testing

Three independent test suites cover this plugin — Python unit tests, and two separate QML test
files (they must be run separately; `qmltestrunner` only accepts one `-input` file at a time):

```bash
nix develop -c pytest -q
nix develop -c qmltestrunner -input tests/tst_statemachine.qml
nix develop -c qmltestrunner -input tests/tst_gapchart_math.qml
```

Expected: `pytest` reports `43 passed`; each `qmltestrunner` run reports `28 passed` and
`10 passed` respectively, both with `Totals: N passed, 0 failed, ...` and process exit code `0`.

**Note on `qmltestrunner`'s exit code:** it is the **failure count**, not a flat `1` on any
failure — `0` means all passed, and a nonzero exit code equals the number of failing test
functions, not just "something failed."

## License

MIT — see `LICENSE`.
