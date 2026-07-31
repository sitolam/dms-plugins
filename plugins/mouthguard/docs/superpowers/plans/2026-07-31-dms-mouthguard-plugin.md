# MouthGuard DMS Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the MouthGuard webcam mouth-closure tracker from a browser app to a DankMaterialShell composite plugin (background daemon + bar widget + Control Center tile).

**Architecture:** A bundled Python helper (`detector.py`) owns the webcam, runs dlib's 68-point face landmark predictor, and streams one JSON measurement per line on stdout. It holds no policy. All thresholds, timers, alerting, and stats live in QML, so settings changes apply live without restarting the camera. The daemon surface owns the process and state machine; the widget surface renders the pill, popout, and CC tile and finds the daemon through `pluginService.pluginInstances`.

**Tech Stack:** QML (Quickshell / DankMaterialShell 1.5.3+), Python 3 with `opencv4` + `dlib` + `numpy` + `face-recognition-models`, Nix flake for the dev shell and runtime env, `pytest` for Python tests, `qmltestrunner` (Qt Quick Test) for the state machine.

**Spec:** `docs/superpowers/specs/2026-07-31-dms-mouthguard-plugin-design.md`

## Global Constraints

- Plugin `id` is exactly `mouthGuard` (camelCase, must match the future registry entry).
- Plugin directory when installed: `~/.config/DankMaterialShell/plugins/MouthGuard/`.
- `plugin.json` must declare `"permissions": ["settings_read", "settings_write", "process"]` — settings UI errors without `settings_write`.
- Both `horizontalBarPill` and `verticalBarPill` are required; omitting the vertical pill makes the widget vanish on side-mounted bars.
- Never hardcode colours or sizes — use `Theme.*` from `qs.Common` (`Theme.error`, `Theme.surfaceText`, `Theme.spacingM`, `Theme.cornerRadius`, `Theme.fontSizeMedium`, …).
- `Theme.fontSizeS` does not exist; it is `Theme.fontSizeSmall`.
- Browser JS APIs do not exist in QML. No `globalThis`, no `localStorage`, no `Notification`.
- `detector.py` must never import QML-side concepts or read settings. It emits measurements only.
- All QML files use `PascalCase.qml`; Python files use `snake_case.py`.
- License is MIT, matching the upstream web app.
- Every task ends with a commit. Use Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `chore:`).

## File Structure

| File | Responsibility |
|---|---|
| `plugin.json` | Composite manifest: daemon + widget + control-center |
| `detector.py` | Entrypoint: camera loop, stdin commands, process lifecycle |
| `mouthguard_core.py` | Pure functions: geometry, model resolution, protocol encoding |
| `StateMachine.js` | Pure detection-window state machine (`.pragma library`) |
| `MouthGuardDaemon.qml` | Process lifecycle, state machine driver, alerts, stats, persistence |
| `MouthGuardWidget.qml` | Bar pills, popout container, CC tile |
| `GapChart.qml` | Canvas lip-gap chart, isolated so the popout stays readable |
| `MouthGuardSettings.qml` | `PluginSettings` declarations |
| `StartupCheck.qml` | Dependency probe, blocks activation with install hints |
| `SoundEffectWrapper.qml` | QtMultimedia `SoundEffect` wrapper |
| `tools/gen_sounds.py` | Renders the 5 alert WAVs from the web app's oscillator params |
| `tests/test_*.py` | pytest suite for `mouthguard_core.py` and `detector.py` |
| `tests/tst_statemachine.qml` | Qt Quick Test suite for `StateMachine.js` |
| `flake.nix` | Dev shell + runtime python env |

---

### Task 1: Repo scaffolding and Nix dev shell

**Files:**
- Create: `flake.nix`, `.gitignore`, `LICENSE`, `CHANGELOG.md`

**Interfaces:**
- Consumes: nothing
- Produces: `nix develop` shell providing `python3` (with `dlib`, `opencv4`, `numpy`, `face-recognition-models`, `pytest`) and `qmltestrunner`. Every later task's test commands run inside it.

- [ ] **Step 1: Write `flake.nix`**

```nix
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
        detector = pkgs.writeShellScriptBin "mouthguard-detector" ''
          exec ${pythonEnv}/bin/python3 ${./detector.py} "$@"
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
```

- [ ] **Step 2: Write `.gitignore`**

```
__pycache__/
*.pyc
.pytest_cache/
result
result-*
calibration-*.csv
```

- [ ] **Step 3: Write `LICENSE`**

MIT License, `Copyright (c) 2026 sitolam`. Copy the body verbatim from `~/Documents/mouthguard/LICENSE`, changing only the copyright line.

- [ ] **Step 4: Write `CHANGELOG.md`**

```markdown
# Changelog

All notable changes to the MouthGuard DMS plugin are documented here.

## [Unreleased]

Initial development.
```

- [ ] **Step 5: Verify the shell resolves**

Run: `nix develop -c python3 -c "import cv2, dlib, numpy, face_recognition_models; print('ok')"`
Expected: `ok`

Run: `nix develop -c qmltestrunner -help 2>&1 | head -1`
Expected: usage line mentioning `qmltestrunner`

- [ ] **Step 6: Commit**

```bash
git add flake.nix flake.lock .gitignore LICENSE CHANGELOG.md
git commit -m "chore: scaffold repo with nix dev shell"
```

---

### Task 2: Landmark geometry

**Files:**
- Create: `mouthguard_core.py`
- Create: `tests/test_geometry.py`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `lip_gap(points) -> float` — `points` is a sequence of 68 `(x, y)` float pairs; returns the Euclidean distance between index 62 and 66.
  - `face_height(points) -> float` — Euclidean distance between index 30 (nose tip) and index 8 (chin).
  - `compensate(gap: float, face: float, ref: float) -> float` — returns `gap * (ref / face)` when `face > 10`, else returns `gap` unchanged.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_geometry.py
import math
import pytest
from mouthguard_core import lip_gap, face_height, compensate


def pts(**overrides):
    """68 landmarks all at origin, with named indices overridden."""
    p = [(0.0, 0.0)] * 68
    for idx, xy in overrides.items():
        p[int(idx[1:])] = xy
    return p


def test_lip_gap_is_vertical_distance():
    p = pts(i62=(100.0, 200.0), i66=(100.0, 209.0))
    assert lip_gap(p) == pytest.approx(9.0)


def test_lip_gap_uses_hypot_so_tilt_does_not_shrink_it():
    # Same 9px separation, rotated 45 degrees. A raw Y-delta would read 6.36.
    d = 9.0 / math.sqrt(2)
    p = pts(i62=(100.0, 200.0), i66=(100.0 + d, 200.0 + d))
    assert lip_gap(p) == pytest.approx(9.0)


def test_face_height_is_nose_to_chin():
    p = pts(i30=(50.0, 100.0), i8=(50.0, 220.0))
    assert face_height(p) == pytest.approx(120.0)


def test_compensate_scales_gap_to_reference():
    # Sitting twice as close: face reads 200 against a 100 reference,
    # so a 10px raw gap must normalise back down to 5.
    assert compensate(10.0, 200.0, 100.0) == pytest.approx(5.0)


def test_compensate_is_identity_at_reference_distance():
    assert compensate(7.0, 100.0, 100.0) == pytest.approx(7.0)


def test_compensate_ignores_implausible_face_height():
    # Guards against divide-by-near-zero when the predictor returns garbage.
    assert compensate(7.0, 4.0, 100.0) == pytest.approx(7.0)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `nix develop -c pytest tests/test_geometry.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'mouthguard_core'`

- [ ] **Step 3: Write the minimal implementation**

```python
# mouthguard_core.py
"""Pure helpers for the MouthGuard detector. No I/O, no dlib, no OpenCV."""

import math

# dlib 68-point landmark indices
LIP_TOP = 62      # inner upper lip
LIP_BOTTOM = 66   # inner lower lip
NOSE_TIP = 30
CHIN = 8

# Below this many pixels the face measurement is noise, not a face.
MIN_FACE_HEIGHT = 10.0


def _dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def lip_gap(points):
    """Distance between the inner lip landmarks, in pixels."""
    return _dist(points[LIP_TOP], points[LIP_BOTTOM])


def face_height(points):
    """Nose-tip to chin distance, in pixels.

    Nose-to-chin rather than forehead-to-chin: the forehead landmark nears the
    frame edge at close range, reading artificially small and under-compensating.
    """
    return _dist(points[NOSE_TIP], points[CHIN])


def compensate(gap, face, ref):
    """Normalise a raw lip gap to a reference face size."""
    if face <= MIN_FACE_HEIGHT:
        return gap
    return gap * (ref / face)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `nix develop -c pytest tests/test_geometry.py -v`
Expected: 6 passed

- [ ] **Step 5: Commit**

```bash
git add mouthguard_core.py tests/test_geometry.py
git commit -m "feat: add landmark geometry helpers"
```

---

### Task 3: Landmark model resolution

**Files:**
- Modify: `mouthguard_core.py`
- Create: `tests/test_model_resolution.py`

**Interfaces:**
- Consumes: nothing
- Produces: `resolve_model_path(env=None, candidates=None) -> str` — returns the first readable path to `shape_predictor_68_face_landmarks.dat`, raising `ModelNotFound` (a new exception class exported from `mouthguard_core`) when none exists. `env` defaults to `os.environ`; `candidates` allows tests to inject a search list.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_model_resolution.py
import pytest
from mouthguard_core import resolve_model_path, ModelNotFound

NAME = "shape_predictor_68_face_landmarks.dat"


def test_env_var_wins(tmp_path):
    m = tmp_path / NAME
    m.write_bytes(b"x")
    other = tmp_path / "other.dat"
    other.write_bytes(b"x")
    got = resolve_model_path(env={"MOUTHGUARD_MODEL": str(m)}, candidates=[str(other)])
    assert got == str(m)


def test_falls_through_to_candidates_when_env_unset(tmp_path):
    m = tmp_path / NAME
    m.write_bytes(b"x")
    got = resolve_model_path(env={}, candidates=[str(m)])
    assert got == str(m)


def test_skips_candidates_that_do_not_exist(tmp_path):
    m = tmp_path / NAME
    m.write_bytes(b"x")
    got = resolve_model_path(env={}, candidates=["/nonexistent/a.dat", str(m)])
    assert got == str(m)


def test_env_var_pointing_at_missing_file_is_an_error(tmp_path):
    # Explicit user intent that cannot be honoured must fail loudly rather than
    # silently falling back to some other model.
    with pytest.raises(ModelNotFound):
        resolve_model_path(env={"MOUTHGUARD_MODEL": "/nope/x.dat"}, candidates=[])


def test_raises_when_nothing_found():
    with pytest.raises(ModelNotFound):
        resolve_model_path(env={}, candidates=["/nonexistent/a.dat"])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `nix develop -c pytest tests/test_model_resolution.py -v`
Expected: FAIL — `ImportError: cannot import name 'resolve_model_path'`

- [ ] **Step 3: Write the implementation**

Append to `mouthguard_core.py`:

```python
import os

MODEL_NAME = "shape_predictor_68_face_landmarks.dat"


class ModelNotFound(Exception):
    """The 68-point landmark model could not be located."""


def _packaged_model_paths():
    """Path supplied by the face_recognition_models package, if installed."""
    try:
        import face_recognition_models
    except ImportError:
        return []
    return [face_recognition_models.pose_predictor_model_location()]


def default_model_candidates():
    return _packaged_model_paths() + [
        f"/usr/share/dlib/{MODEL_NAME}",
        f"/usr/share/dlib-models/{MODEL_NAME}",
        os.path.expanduser(f"~/.cache/mouthguard/{MODEL_NAME}"),
    ]


def resolve_model_path(env=None, candidates=None):
    """Locate the landmark model, preferring an explicit override."""
    env = os.environ if env is None else env
    override = env.get("MOUTHGUARD_MODEL")
    if override:
        if os.path.isfile(override):
            return override
        raise ModelNotFound(f"MOUTHGUARD_MODEL points at a missing file: {override}")

    for path in default_model_candidates() if candidates is None else candidates:
        if os.path.isfile(path):
            return path

    raise ModelNotFound(
        "Could not find " + MODEL_NAME + ". Install your distro's dlib data "
        "package, or set MOUTHGUARD_MODEL to its path."
    )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `nix develop -c pytest tests/test_model_resolution.py -v`
Expected: 5 passed

- [ ] **Step 5: Verify it finds the real model in the Nix env**

Run: `nix develop -c python3 -c "from mouthguard_core import resolve_model_path; print(resolve_model_path())"`
Expected: a path under `/nix/store/...face-recognition-models.../shape_predictor_68_face_landmarks.dat`

- [ ] **Step 6: Commit**

```bash
git add mouthguard_core.py tests/test_model_resolution.py
git commit -m "feat: resolve landmark model from env, package, or system paths"
```

---

### Task 4: Wire protocol encoding

**Files:**
- Modify: `mouthguard_core.py`
- Create: `tests/test_protocol.py`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `encode_ready(backend: str, device: str, fps: int) -> str`
  - `encode_measurement(t: float, gap: float | None, face: float) -> str`
  - `encode_error(code: str, detail: str) -> str`

  Each returns a single JSON line **without** a trailing newline. `encode_measurement` omits `gap` entirely when it is `None` (no face). Floats are rounded to 2 decimals so the stream stays compact at 10 lines/sec.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_protocol.py
import json
from mouthguard_core import encode_ready, encode_measurement, encode_error


def test_ready_handshake_carries_backend_and_device():
    d = json.loads(encode_ready("dlib", "/dev/video0", 10))
    assert d == {"ready": True, "backend": "dlib", "device": "/dev/video0", "fps": 10}


def test_measurement_includes_gap_and_face():
    d = json.loads(encode_measurement(1712.456, 4.211, 118.34))
    assert d == {"t": 1712.46, "gap": 4.21, "face": 118.34}


def test_no_face_omits_gap_entirely():
    # QML distinguishes "no face" from "gap of zero"; a zero gap would read as
    # a firmly closed mouth and wrongly accrue to closed time.
    d = json.loads(encode_measurement(1712.5, None, 0.0))
    assert d == {"t": 1712.5, "face": 0.0}
    assert "gap" not in d


def test_error_is_terminal_shape():
    d = json.loads(encode_error("camera_busy", "/dev/video0: busy"))
    assert d == {"error": "camera_busy", "detail": "/dev/video0: busy"}


def test_lines_are_single_line_and_newline_free():
    for line in [
        encode_ready("dlib", "/dev/video0", 10),
        encode_measurement(1.0, 2.0, 3.0),
        encode_error("x", "y\nz"),
    ]:
        assert "\n" not in line
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `nix develop -c pytest tests/test_protocol.py -v`
Expected: FAIL — `ImportError: cannot import name 'encode_ready'`

- [ ] **Step 3: Write the implementation**

Append to `mouthguard_core.py`:

```python
import json


def _line(obj):
    return json.dumps(obj, separators=(",", ":"))


def encode_ready(backend, device, fps):
    return _line({"ready": True, "backend": backend, "device": device, "fps": fps})


def encode_measurement(t, gap, face):
    obj = {"t": round(t, 2), "face": round(face, 2)}
    if gap is not None:
        obj["gap"] = round(gap, 2)
    return _line(obj)


def encode_error(code, detail):
    return _line({"error": code, "detail": " ".join(str(detail).split())})
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `nix develop -c pytest tests/test_protocol.py -v`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
git add mouthguard_core.py tests/test_protocol.py
git commit -m "feat: add JSON wire protocol encoders"
```

---

### Task 5: Face-rect caching policy

**Files:**
- Modify: `mouthguard_core.py`
- Create: `tests/test_rect_cache.py`

**Interfaces:**
- Consumes: nothing
- Produces: `should_redetect(frame_index: int, have_rect: bool, points=None, rect=None, interval: int = 5) -> bool` — decides whether the expensive HOG detector must run this frame. Returns `True` when there is no cached rect, when `frame_index % interval == 0`, or when any landmark in `points` has drifted outside `rect`. `rect` is `(left, top, right, bottom)`.

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_rect_cache.py
from mouthguard_core import should_redetect

RECT = (10, 10, 110, 110)
INSIDE = [(50.0, 50.0)] * 68


def test_must_detect_when_no_cached_rect():
    assert should_redetect(3, have_rect=False) is True


def test_must_detect_on_interval_boundary():
    assert should_redetect(10, have_rect=True, points=INSIDE, rect=RECT, interval=5) is True


def test_reuses_cached_rect_between_intervals():
    assert should_redetect(11, have_rect=True, points=INSIDE, rect=RECT, interval=5) is False


def test_redetects_when_landmarks_drift_outside_rect():
    # Face moved; the cached rect no longer contains it, so tracking has gone stale.
    drifted = [(50.0, 50.0)] * 67 + [(500.0, 50.0)]
    assert should_redetect(11, have_rect=True, points=drifted, rect=RECT, interval=5) is True


def test_missing_points_forces_detection():
    assert should_redetect(11, have_rect=True, points=None, rect=RECT, interval=5) is True
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `nix develop -c pytest tests/test_rect_cache.py -v`
Expected: FAIL — `ImportError: cannot import name 'should_redetect'`

- [ ] **Step 3: Write the implementation**

Append to `mouthguard_core.py`:

```python
def should_redetect(frame_index, have_rect, points=None, rect=None, interval=5):
    """Whether the HOG face detector must run for this frame.

    Running the detector every frame is the dominant cost; the 68-point
    predictor against a known rect is roughly a millisecond. Between detections
    the previous rect is reused, unless the landmarks have wandered out of it.
    """
    if not have_rect or rect is None:
        return True
    if interval > 0 and frame_index % interval == 0:
        return True
    if points is None:
        return True

    left, top, right, bottom = rect
    return any(
        x < left or x > right or y < top or y > bottom
        for x, y in points
    )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `nix develop -c pytest tests/test_rect_cache.py -v`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
git add mouthguard_core.py tests/test_rect_cache.py
git commit -m "feat: add face-rect caching policy"
```

---

### Task 6: Detector entrypoint

**Files:**
- Create: `detector.py`
- Create: `tests/test_detector_cli.py`

**Interfaces:**
- Consumes: everything from `mouthguard_core`.
- Produces: an executable emitting the wire protocol on stdout. CLI:
  `--device PATH` (default `/dev/video0`), `--fps N` (default 10), `--detect-interval N` (default 5), `--width N` (default 640), `--height N` (default 480), `--scale F` (default 0.5), `--self-test`.
  `--self-test` skips the camera entirely, emits the ready handshake plus three synthetic measurements, and exits 0 — this is what makes the entrypoint testable headlessly.
  Reads `pause`, `resume`, `quit` from stdin. `pause` releases the capture device; `resume` reopens it; the dlib model stays resident across both.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_detector_cli.py
import json
import subprocess
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent


def run_self_test():
    return subprocess.run(
        [sys.executable, str(ROOT / "detector.py"), "--self-test"],
        capture_output=True, text=True, timeout=60, cwd=ROOT,
    )


def test_self_test_exits_cleanly():
    assert run_self_test().returncode == 0


def test_first_line_is_the_ready_handshake():
    lines = run_self_test().stdout.strip().splitlines()
    first = json.loads(lines[0])
    assert first["ready"] is True
    assert first["backend"] == "dlib"


def test_every_line_is_valid_standalone_json():
    # QML splits this stream on newlines, so a line that is not self-contained
    # JSON breaks the parser downstream.
    for line in run_self_test().stdout.strip().splitlines():
        json.loads(line)


def test_emits_measurements_after_the_handshake():
    lines = run_self_test().stdout.strip().splitlines()
    measurements = [json.loads(x) for x in lines[1:]]
    assert len(measurements) == 3
    assert all("t" in m and "face" in m for m in measurements)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nix develop -c pytest tests/test_detector_cli.py -v`
Expected: FAIL — detector.py does not exist

- [ ] **Step 3: Write `detector.py`**

```python
#!/usr/bin/env python3
"""MouthGuard detector: webcam frames in, lip-gap measurements out.

This process holds no policy. It does not know what a threshold is, how long a
detection window lasts, or when to alert. It measures and reports; QML decides.
That split is what lets settings changes apply without restarting the camera.
"""

import argparse
import sys
import time

from mouthguard_core import (
    ModelNotFound,
    encode_error,
    encode_measurement,
    encode_ready,
    face_height,
    lip_gap,
    resolve_model_path,
    should_redetect,
)


def emit(line):
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def parse_args(argv=None):
    p = argparse.ArgumentParser(prog="detector.py")
    p.add_argument("--device", default="/dev/video0")
    p.add_argument("--fps", type=int, default=10)
    p.add_argument("--detect-interval", type=int, default=5)
    p.add_argument("--width", type=int, default=640)
    p.add_argument("--height", type=int, default=480)
    p.add_argument("--scale", type=float, default=0.5)
    p.add_argument("--self-test", action="store_true")
    return p.parse_args(argv)


def self_test(args):
    """Emit a valid stream without touching the camera."""
    emit(encode_ready("dlib", args.device, args.fps))
    t0 = time.monotonic()
    for gap in (3.0, 9.5, None):
        emit(encode_measurement(time.monotonic() - t0, gap, 0.0 if gap is None else 118.0))
    return 0


def read_command():
    """Non-blocking read of one stdin line. Returns None when nothing waits."""
    import select

    if not select.select([sys.stdin], [], [], 0)[0]:
        return None
    line = sys.stdin.readline()
    if not line:
        return "quit"
    return line.strip().lower()


def main(argv=None):
    args = parse_args(argv)
    if args.self_test:
        return self_test(args)

    import cv2
    import dlib

    try:
        model_path = resolve_model_path()
    except ModelNotFound as exc:
        emit(encode_error("model_missing", exc))
        return 2

    detector = dlib.get_frontal_face_detector()
    predictor = dlib.shape_predictor(model_path)

    def open_capture():
        cap = cv2.VideoCapture(args.device, cv2.CAP_V4L2)
        if not cap.isOpened():
            return None
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
        return cap

    cap = open_capture()
    if cap is None:
        emit(encode_error("camera_busy", f"{args.device}: cannot open device"))
        return 3

    emit(encode_ready("dlib", args.device, args.fps))

    paused = False
    frame_index = 0
    rect = None
    points = None
    t0 = time.monotonic()
    period = 1.0 / max(1, args.fps)
    inv_scale = 1.0 / args.scale

    try:
        while True:
            cmd = read_command()
            if cmd == "quit":
                break
            if cmd == "pause" and not paused:
                paused = True
                if cap is not None:
                    cap.release()
                    cap = None
                rect = None
            elif cmd == "resume" and paused:
                paused = False
                cap = open_capture()
                if cap is None:
                    emit(encode_error("camera_busy", f"{args.device}: cannot reopen"))
                    return 3

            if paused:
                time.sleep(period)
                continue

            ok, frame = cap.read()
            if not ok:
                time.sleep(period)
                continue

            small = cv2.resize(frame, None, fx=args.scale, fy=args.scale)
            gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)

            if should_redetect(frame_index, rect is not None, points, rect,
                               args.detect_interval):
                faces = detector(gray, 0)
                if faces:
                    # Largest face wins; multi-face tracking is out of scope.
                    face = max(faces, key=lambda f: f.width() * f.height())
                    rect = (face.left(), face.top(), face.right(), face.bottom())
                else:
                    rect = None
                    points = None

            if rect is None:
                emit(encode_measurement(time.monotonic() - t0, None, 0.0))
            else:
                shape = predictor(gray, dlib.rectangle(*rect))
                points = [(shape.part(i).x, shape.part(i).y) for i in range(68)]
                # Scale back to full-resolution pixels so gap and face height
                # stay comparable across --scale values.
                full = [(x * inv_scale, y * inv_scale) for x, y in points]
                emit(encode_measurement(
                    time.monotonic() - t0, lip_gap(full), face_height(full)))

            frame_index += 1
            time.sleep(period)
    except KeyboardInterrupt:
        pass
    finally:
        if cap is not None:
            cap.release()

    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `nix develop -c pytest tests/test_detector_cli.py -v`
Expected: 4 passed

- [ ] **Step 5: Run the whole suite**

Run: `nix develop -c pytest -v`
Expected: 25 passed

- [ ] **Step 6: Commit**

```bash
git add detector.py tests/test_detector_cli.py
git commit -m "feat: add detector entrypoint with camera loop and stdin control"
```

---

### Task 7: Calibrate against a real webcam

This is the task that makes the plugin usable. dlib's inner-lip landmarks produce a different
numeric scale than MediaPipe's, so the web app's threshold of `5` and reference of `100px` are
meaningless here and must be measured, not guessed.

**Files:**
- Create: `tools/calibrate.py`
- Create: `CALIBRATION.md`
- Modify: `mouthguard_core.py` (add the derived constants)

**Interfaces:**
- Consumes: `detector.py` on a real camera.
- Produces: `DEFAULT_THRESHOLD: float` and `DEFAULT_DISTANCE_REF: float` in `mouthguard_core.py`, consumed as defaults by `MouthGuardSettings.qml` (Task 12) and `MouthGuardDaemon.qml` (Task 11).

- [ ] **Step 1: Write the capture helper**

```python
#!/usr/bin/env python3
# tools/calibrate.py
"""Record lip gap statistics for a labelled pose, to derive plugin defaults.

Usage:  python3 tools/calibrate.py <label> <seconds>
Prints median/p05/p95 of gap and face height, and appends raw rows to
calibration-<label>.csv.
"""

import statistics
import subprocess
import sys
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    label, secs = sys.argv[1], float(sys.argv[2])
    proc = subprocess.Popen(
        [sys.executable, str(ROOT / "detector.py")],
        stdout=subprocess.PIPE, stdin=subprocess.PIPE, text=True, cwd=ROOT,
    )
    gaps, faces = [], []
    out = open(ROOT / f"calibration-{label}.csv", "w")
    out.write("t,gap,face\n")
    try:
        for line in proc.stdout:
            d = json.loads(line)
            if "error" in d:
                print("detector error:", d, file=sys.stderr)
                return 1
            if "ready" in d:
                print(f"recording '{label}' for {secs}s — hold the pose")
                continue
            if "gap" not in d:
                continue
            gaps.append(d["gap"])
            faces.append(d["face"])
            out.write(f"{d['t']},{d['gap']},{d['face']}\n")
            if d["t"] >= secs:
                break
    finally:
        proc.stdin.write("quit\n")
        proc.stdin.flush()
        proc.terminate()
        out.close()

    if not gaps:
        print("no face measured", file=sys.stderr)
        return 1

    q = statistics.quantiles(gaps, n=20)
    print(f"{label}: n={len(gaps)} gap median={statistics.median(gaps):.2f} "
          f"p05={q[0]:.2f} p95={q[18]:.2f} face median={statistics.median(faces):.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Record the four poses**

Run each in turn, holding the stated pose at normal seating distance:

```bash
nix develop -c python3 tools/calibrate.py closed-near 20     # mouth firmly closed
nix develop -c python3 tools/calibrate.py ajar-near 20       # lips barely parted
nix develop -c python3 tools/calibrate.py open-near 20       # clearly open
nix develop -c python3 tools/calibrate.py closed-far 20      # closed, arm's length back
```

- [ ] **Step 3: Derive the constants**

- `DEFAULT_THRESHOLD` — pick a value cleanly above `closed-near` p95 and below `ajar-near` p05. If those two ranges overlap, the landmarks cannot separate the poses; fall back to the midpoint of the two medians and record that the separation is marginal.
- `DEFAULT_DISTANCE_REF` — the `face` median from `closed-near`.

Sanity-check the reference: `compensate(gap_far_median, face_far_median, DEFAULT_DISTANCE_REF)` should land close to `gap_near_median`. If it does not, the compensation is not doing its job and the pose recordings should be repeated with more consistent framing.

- [ ] **Step 4: Record the constants in `mouthguard_core.py`**

Append, replacing the bracketed values with the measured ones:

```python
# Derived empirically — see CALIBRATION.md. These are dlib-scale values and
# bear no relation to the web app's MediaPipe-scale threshold of 5.
DEFAULT_THRESHOLD = <measured>
DEFAULT_DISTANCE_REF = <measured>
```

- [ ] **Step 5: Write `CALIBRATION.md`**

Record, in a short table: the four pose medians and p05/p95, the two chosen constants, the date, the camera model (`v4l2-ctl --list-devices` or `/sys/class/video4linux/video0/name`), and the one-line reasoning for the threshold choice. Anyone re-tuning for a different camera needs this to know what "normal" looked like.

- [ ] **Step 6: Commit**

```bash
git add tools/calibrate.py CALIBRATION.md mouthguard_core.py
git commit -m "feat: calibrate detection defaults against real webcam"
```

---

### Task 8: Detection state machine

**Files:**
- Create: `StateMachine.js`
- Create: `tests/tst_statemachine.qml`

**Interfaces:**
- Consumes: nothing (pure JS, no QML types).
- Produces: `StateMachine.js` as a `.pragma library` exporting:
  - `createState() -> object` with fields `mouthOpen` (bool), `rawOpenSince` (ms|null), `currentOpenStart` (ms|null), `mouthOpenSince` (ms|null), `totalOpenMs`, `totalClosedMs`, `totalUnmeasuredMs`, `openEvents` (array of ms durations).
  - `tick(state, {now, dt, isOpen, hasFace, delay}) -> array of event strings` — mutates `state`, returns zero or more of `"alert"`, `"confirmed"`, `"closed"`.

  Faithful port of `index.html:1411-1462`. Time accounting runs **before** detection, using the *confirmed* state.

- [ ] **Step 1: Write the failing test**

```qml
// tests/tst_statemachine.qml
import QtQuick
import QtTest
import "../StateMachine.js" as SM

TestCase {
    name: "StateMachine"

    function make() { return SM.createState() }

    function feed(s, opts) {
        return SM.tick(s, {
            now: opts.now, dt: opts.dt === undefined ? 100 : opts.dt,
            isOpen: opts.isOpen, hasFace: opts.hasFace === undefined ? true : opts.hasFace,
            delay: opts.delay === undefined ? 1000 : opts.delay
        })
    }

    function test_closed_mouth_accrues_closed_time() {
        var s = make()
        feed(s, { now: 100, dt: 100, isOpen: false })
        compare(s.totalClosedMs, 100)
        compare(s.totalOpenMs, 0)
    }

    function test_brief_opening_below_window_is_discarded() {
        // The v1.2.2 false-positive fix: a blip shorter than the detection
        // window must leave no trace at all — no alert, no open time, no event.
        var s = make()
        feed(s, { now: 100, isOpen: true })
        feed(s, { now: 500, isOpen: true })
        var ev = feed(s, { now: 600, isOpen: false })
        compare(s.mouthOpen, false)
        compare(s.totalOpenMs, 0)
        compare(s.openEvents.length, 0)
        compare(ev.indexOf("alert"), -1)
    }

    function test_holding_past_window_confirms_and_alerts() {
        var s = make()
        feed(s, { now: 100, isOpen: true })
        var ev = feed(s, { now: 1100, isOpen: true })
        compare(s.mouthOpen, true)
        verify(ev.indexOf("alert") >= 0)
        verify(ev.indexOf("confirmed") >= 0)
    }

    function test_detection_window_is_retroactively_counted_as_open() {
        // The window itself was time spent with the mouth open, so it must move
        // from the closed total to the open total on confirmation.
        var s = make()
        feed(s, { now: 100, dt: 100, isOpen: true })
        compare(s.totalClosedMs, 100)
        feed(s, { now: 1100, dt: 1000, isOpen: true })
        compare(s.totalOpenMs, 1000)
        compare(s.totalClosedMs, 100)
    }

    function test_alert_rearms_once_per_window_not_every_tick() {
        var s = make()
        feed(s, { now: 100, isOpen: true })
        feed(s, { now: 1100, isOpen: true })          // confirmed, alert 1
        var quiet = feed(s, { now: 1600, isOpen: true })
        compare(quiet.indexOf("alert"), -1)
        var again = feed(s, { now: 2200, isOpen: true })
        verify(again.indexOf("alert") >= 0)
    }

    function test_closing_records_the_event_duration() {
        var s = make()
        feed(s, { now: 100, isOpen: true })
        feed(s, { now: 1100, isOpen: true })
        var ev = feed(s, { now: 3100, isOpen: false })
        verify(ev.indexOf("closed") >= 0)
        compare(s.openEvents.length, 1)
        compare(s.openEvents[0], 3000)
        compare(s.mouthOpen, false)
    }

    function test_sub_200ms_events_are_not_recorded() {
        var s = make()
        feed(s, { now: 100, isOpen: true, delay: 0 })
        feed(s, { now: 250, isOpen: false, delay: 0 })
        compare(s.openEvents.length, 0)
    }

    function test_no_face_accrues_unmeasured_and_suppresses_alerts() {
        var s = make()
        var ev = feed(s, { now: 100, dt: 100, isOpen: false, hasFace: false })
        compare(s.totalUnmeasuredMs, 100)
        compare(s.totalClosedMs, 0)
        compare(s.totalOpenMs, 0)
        compare(ev.length, 0)
    }

    function test_no_face_while_open_does_not_fire_alerts() {
        var s = make()
        feed(s, { now: 100, isOpen: true })
        feed(s, { now: 1100, isOpen: true })
        var ev = feed(s, { now: 2200, isOpen: false, hasFace: false })
        compare(ev.indexOf("alert"), -1)
        compare(s.totalUnmeasuredMs, 100)
    }

    function test_zero_delay_confirms_immediately() {
        var s = make()
        var ev = feed(s, { now: 100, isOpen: true, delay: 0 })
        compare(s.mouthOpen, true)
        verify(ev.indexOf("alert") >= 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nix develop -c qmltestrunner -input tests/tst_statemachine.qml`
Expected: FAIL — cannot resolve `../StateMachine.js`

- [ ] **Step 3: Write `StateMachine.js`**

```javascript
.pragma library

// Faithful port of the detection window logic in the MouthGuard web app
// (index.html:1411-1462). Kept as pure functions with no QML dependencies so
// it can be unit-tested with qmltestrunner.

function createState() {
    return {
        mouthOpen: false,
        rawOpenSince: null,
        currentOpenStart: null,
        mouthOpenSince: null,
        totalOpenMs: 0,
        totalClosedMs: 0,
        totalUnmeasuredMs: 0,
        openEvents: []
    }
}

// Events shorter than this are camera blips, not real mouth openings.
var MIN_EVENT_MS = 200

function tick(state, input) {
    var now = input.now
    var dt = input.dt
    var delay = input.delay
    var events = []

    // No face: accounting pauses entirely. Time counts toward neither open nor
    // closed, and alerts are suppressed — we genuinely do not know the state.
    if (!input.hasFace) {
        state.totalUnmeasuredMs += dt
        return events
    }

    // Time accounting uses the CONFIRMED state, and runs before detection.
    if (state.mouthOpen) {
        state.totalOpenMs += dt
    } else {
        state.totalClosedMs += dt
    }

    if (input.isOpen) {
        if (state.rawOpenSince === null) {
            state.rawOpenSince = now
        }

        if (!state.mouthOpen) {
            var openDur = now - state.rawOpenSince
            if (openDur >= delay) {
                // The window itself was open time; move it across.
                var retro = openDur
                state.totalClosedMs = Math.max(0, state.totalClosedMs - retro)
                state.totalOpenMs += retro
                state.mouthOpen = true
                state.currentOpenStart = state.rawOpenSince
                state.mouthOpenSince = now
                events.push("confirmed")
                events.push("alert")
            }
        } else if (now - state.mouthOpenSince >= delay) {
            // Re-arm: reset the clock so the next alert waits a full window.
            state.mouthOpenSince = now
            events.push("alert")
        }
    } else {
        if (state.mouthOpen) {
            var dur = now - (state.currentOpenStart === null ? now : state.currentOpenStart)
            if (dur > MIN_EVENT_MS) {
                state.openEvents.push(dur)
            }
            state.mouthOpen = false
            state.currentOpenStart = null
            events.push("closed")
        }
        state.rawOpenSince = null
    }

    return events
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `nix develop -c qmltestrunner -input tests/tst_statemachine.qml`
Expected: 10 passed, 0 failed

- [ ] **Step 5: Commit**

```bash
git add StateMachine.js tests/tst_statemachine.qml
git commit -m "feat: port detection window state machine with tests"
```

---

### Task 9: Manifest and startup check

**Files:**
- Create: `plugin.json`, `StartupCheck.qml`
- Create: `MouthGuardDaemon.qml` (stub), `MouthGuardWidget.qml` (stub)

**Interfaces:**
- Consumes: `detector.py`.
- Produces: a plugin that loads in DMS and shows a pill. `MouthGuardDaemon.qml` exposes `property bool active`, `property string mouthState` (one of `"inactive" | "closed" | "open" | "noface" | "paused"`), and `function toggle()`. The widget reads these; Task 11 gives them real behaviour.

- [ ] **Step 1: Write `plugin.json`**

```json
{
    "id": "mouthGuard",
    "name": "MouthGuard",
    "description": "Webcam mouth-closure tracker with alerts and session stats",
    "version": "0.1.0",
    "license": "MIT",
    "author": "sitolam",
    "icon": "sentiment_satisfied",
    "type": "composite",
    "capabilities": ["daemon", "dankbar-widget", "control-center"],
    "components": {
        "daemon": "./MouthGuardDaemon.qml",
        "widget": "./MouthGuardWidget.qml"
    },
    "settings": "./MouthGuardSettings.qml",
    "startupCheck": "./StartupCheck.qml",
    "requires_dms": ">=1.5.0",
    "dependencies": ["python3", "python-opencv", "python-dlib"],
    "permissions": ["settings_read", "settings_write", "process"]
}
```

- [ ] **Step 2: Write `StartupCheck.qml`**

```qml
import QtQuick
import qs.Common

QtObject {
    function check(done) {
        // Probe the interpreter the daemon will actually use, so a green check
        // here guarantees the detector can start.
        Proc.runCommand("mouthGuard.depCheck",
            ["sh", "-c", "python3 -c 'import cv2, dlib' 2>&1"],
            (stdout, exitCode) => {
                if (exitCode === 0) {
                    done(null)
                    return
                }
                done({
                    "title": I18n.tr("Python, OpenCV and dlib are required"),
                    "details": I18n.tr(
                        "MouthGuard needs python3 with the cv2 and dlib modules.\n\n" +
                        "Arch:    sudo pacman -S python-opencv python-dlib\n" +
                        "Fedora:  sudo dnf install python3-opencv python3-dlib\n" +
                        "Debian:  sudo apt install python3-opencv python3-dlib\n" +
                        "Nix:     use the flake.nix bundled with this plugin\n\n" +
                        "Detail: ") + stdout
                })
            })
    }
}
```

- [ ] **Step 3: Write the daemon stub**

```qml
import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null
    property bool active: false
    property string mouthState: "inactive"

    function toggle() {
        active = !active
        mouthState = active ? "closed" : "inactive"
    }

    // Register this instance so the widget surface — which is created once per
    // bar, per monitor — can find the single daemon rather than each spawning
    // its own detector.
    Component.onCompleted: {
        if (!pluginService) return
        const next = Object.assign({}, pluginService.pluginInstances)
        next[pluginId] = root
        pluginService.pluginInstances = next
    }

    Component.onDestruction: {
        if (!pluginService) return
        if (pluginService.pluginInstances[pluginId] !== root) return
        const next = Object.assign({}, pluginService.pluginInstances)
        delete next[pluginId]
        pluginService.pluginInstances = next
    }
}
```

- [ ] **Step 4: Write the widget stub with both pill orientations**

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null
    readonly property var daemon: pluginService
        ? pluginService.pluginInstances[pluginId] : null
    readonly property string mouthState: daemon ? daemon.mouthState : "inactive"

    readonly property var iconFor: ({
        "inactive": "videocam_off",
        "closed": "sentiment_satisfied",
        "open": "warning",
        "noface": "face_retouching_off",
        "paused": "pause_circle"
    })

    readonly property color stateColor: mouthState === "open"
        ? Theme.error
        : (mouthState === "closed" ? Theme.surfaceText : Theme.surfaceVariantText)

    horizontalBarPill: Component {
        StyledRect {
            width: icon.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            DankIcon {
                id: icon
                anchors.centerIn: parent
                name: root.iconFor[root.mouthState]
                size: Theme.iconSizeSmall
                color: root.stateColor
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.daemon?.toggle()
            }
        }
    }

    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: vicon.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            DankIcon {
                id: vicon
                anchors.centerIn: parent
                name: root.iconFor[root.mouthState]
                size: Theme.iconSizeSmall
                color: root.stateColor
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.daemon?.toggle()
            }
        }
    }
}
```

- [ ] **Step 5: Write a placeholder `MouthGuardSettings.qml`**

The manifest references it, so it must exist or the plugin fails to load. Task 12 fills it in.

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "mouthGuard"
}
```

- [ ] **Step 6: Install and verify the plugin loads**

```bash
ln -sfn "$PWD" ~/.config/DankMaterialShell/plugins/MouthGuard
dms ipc plugin-scan scan
dms ipc plugin-scan status mouthGuard
```

Expected: status reports loaded with no error. Validate the manifest first with `jq . plugin.json` if it does not appear.

- [ ] **Step 7: Verify the pill renders in both orientations**

Enable the plugin in Settings > Plugins, add it to a DankBar section, and confirm the icon appears. Move the bar to a left or right edge and confirm it is still visible. Clicking should flip the icon between `videocam_off` and `sentiment_satisfied`.

- [ ] **Step 8: Commit**

```bash
git add plugin.json StartupCheck.qml MouthGuardDaemon.qml MouthGuardWidget.qml MouthGuardSettings.qml
git commit -m "feat: add manifest, startup check, and plugin skeleton"
```

---

### Task 10: Alert sounds

**Files:**
- Create: `tools/gen_sounds.py`, `SoundEffectWrapper.qml`
- Create: `sounds/soft.wav`, `sounds/chime.wav`, `sounds/double.wav`, `sounds/buzz.wav`, `sounds/ping.wav`

**Interfaces:**
- Consumes: nothing.
- Produces: `SoundEffectWrapper.qml` exposing `property alias source`, `property alias volume`, and `function play()`. Sound files are 44.1 kHz 16-bit mono WAV, normalised to full scale so the QML volume slider is the only gain control.

- [ ] **Step 1: Write the generator**

Parameters are transcribed from `index.html:1056-1130`. Web Audio's `exponentialRampToValueAtTime` is reproduced as an exponential decay from the start gain to 0.001 over the ramp duration.

```python
#!/usr/bin/env python3
# tools/gen_sounds.py
"""Render MouthGuard's five alert sounds to WAV.

The web app synthesises these with the Web Audio API, which has no QML
equivalent, so they ship as assets. Parameters mirror index.html:1056-1130
exactly; regenerate rather than hand-editing the WAVs.
"""

import math
import pathlib
import struct
import wave

RATE = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / "sounds"

# name -> list of (wave_type, freq_start, freq_end, amp, start_s, dur_s)
VOICES = {
    "soft":   [("sine", 660, 660, 1.00, 0.00, 0.45)],
    "chime":  [("sine", 880, 880, 0.60, 0.00, 1.20),
               ("sine", 1320, 1320, 0.30, 0.00, 1.20),
               ("sine", 1760, 1760, 0.15, 0.00, 1.20)],
    "double": [("sine", 800, 800, 1.00, 0.00, 0.15),
               ("sine", 800, 800, 1.00, 0.18, 0.15)],
    "buzz":   [("saw", 180, 180, 0.40, 0.00, 0.25)],
    "ping":   [("sine", 1400, 900, 0.80, 0.00, 0.20)],
}


def osc(wave_type, phase):
    if wave_type == "sine":
        return math.sin(phase)
    # Sawtooth over a 2*pi phase, matching Web Audio's 'sawtooth'.
    return 2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0


def render(voices):
    total = max(s + d for _, _, _, _, s, d in voices)
    n = int(RATE * (total + 0.02))
    buf = [0.0] * n

    for wave_type, f0, f1, amp, start, dur in voices:
        phase = 0.0
        i0 = int(start * RATE)
        for i in range(int(dur * RATE)):
            if i0 + i >= n:
                break
            frac = i / (dur * RATE)
            freq = f0 * ((f1 / f0) ** frac) if f1 != f0 else f0
            # exponentialRampToValueAtTime(0.001, t + dur)
            env = amp * ((0.001 / amp) ** frac)
            # 10ms attack, matching the linearRamp the double beep uses. Applied
            # to every voice: it removes the click a hard start would otherwise
            # produce, and is inaudible on the rest.
            env *= min(1.0, i / (0.01 * RATE))
            buf[i0 + i] += env * osc(wave_type, phase)
            phase += 2 * math.pi * freq / RATE

    peak = max(abs(v) for v in buf) or 1.0
    return [int(max(-1.0, min(1.0, v / peak)) * 32767) for v in buf]


def main():
    OUT.mkdir(exist_ok=True)
    for name, voices in VOICES.items():
        samples = render(voices)
        path = OUT / f"{name}.wav"
        with wave.open(str(path), "w") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", s) for s in samples))
        print(f"wrote {path} ({len(samples) / RATE:.2f}s)")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Generate and verify the files**

Run: `nix develop -c python3 tools/gen_sounds.py`
Expected: five lines, durations approximately soft 0.47s, chime 1.22s, double 0.35s, buzz 0.27s, ping 0.22s

Run: `nix develop -c python3 -c "import wave; w=wave.open('sounds/chime.wav'); print(w.getnchannels(), w.getframerate(), w.getsampwidth())"`
Expected: `1 44100 2`

- [ ] **Step 3: Listen to each one**

Run: `for f in sounds/*.wav; do echo $f; ffplay -nodisp -autoexit -loglevel quiet $f; done`
Expected: five distinct, non-clipping alert sounds. If any is silent or distorted, the envelope maths is wrong — fix before continuing.

- [ ] **Step 4: Write the wrapper**

```qml
import QtQuick
import QtMultimedia

Item {
    id: root

    property alias source: player.source
    property alias volume: player.volume

    SoundEffect {
        id: player
    }

    function play() {
        player.play()
    }

    Component.onDestruction: player.stop()
}
```

- [ ] **Step 5: Commit**

```bash
git add tools/gen_sounds.py sounds SoundEffectWrapper.qml
git commit -m "feat: add alert sounds rendered from web audio params"
```

---

### Task 11: Daemon wiring — process, state machine, alerts

**Files:**
- Modify: `MouthGuardDaemon.qml`

**Interfaces:**
- Consumes: `detector.py`, `StateMachine.js`, `SoundEffectWrapper.qml`, `mouthguard_core.DEFAULT_THRESHOLD` / `DEFAULT_DISTANCE_REF` (transcribed as QML property defaults).
- Produces: on the daemon — `active`, `mouthState`, `lastGap`, `lastFace`, `lastAdjGap`, `sessionStats` (object with `openMs`, `closedMs`, `unmeasuredMs`, `events`, `avgOpenMs`), `gapHistory` (array of `{t, gap}` capped at 60s), `alertsMuted`, `toggle()`, `resetSession()`. Task 13 and 14 read all of these.

- [ ] **Step 1: Replace `MouthGuardDaemon.qml`**

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "StateMachine.js" as SM

PluginComponent {
    id: root

    property var popoutService: null

    // --- settings, mirrored from pluginData -------------------------------
    readonly property string device: pluginData?.device ?? "/dev/video0"
    readonly property real threshold: pluginData?.threshold ?? DEFAULT_THRESHOLD
    readonly property real alertDelayMs: (pluginData?.alertDelay ?? 1.0) * 1000
    readonly property bool distComp: pluginData?.distanceCompensation ?? true
    readonly property string soundType: pluginData?.soundType ?? "soft"
    readonly property real volume: (pluginData?.volume ?? 85) / 100
    readonly property bool notifications: pluginData?.notifications ?? true
    readonly property int fps: pluginData?.fps ?? 10
    readonly property int noFaceTimeoutMs: (pluginData?.noFaceTimeout ?? 5) * 60000

    // Replace both with the values measured in Task 7.
    readonly property real DEFAULT_THRESHOLD: <measured>
    readonly property real DISTANCE_REF: <measured>

    // --- live state -------------------------------------------------------
    property bool active: false
    property bool alertsMuted: false
    property string mouthState: "inactive"
    property real lastGap: 0
    property real lastFace: 0
    property real lastAdjGap: 0
    property var gapHistory: []
    property var sessionStats: ({
        openMs: 0, closedMs: 0, unmeasuredMs: 0, events: 0, avgOpenMs: 0
    })

    property var _sm: SM.createState()
    property real _lastTickAt: 0
    property real _noFaceSince: 0
    property real _sessionStart: 0

    function toggle() {
        active = !active
        if (active) resetSession()
        else mouthState = "inactive"
    }

    function resetSession() {
        _sm = SM.createState()
        _lastTickAt = 0
        _noFaceSince = 0
        _sessionStart = Date.now()
        gapHistory = []
        mouthState = "closed"
        _publishStats()
    }

    function _publishStats() {
        const evs = _sm.openEvents
        const total = evs.reduce((a, b) => a + b, 0)
        sessionStats = {
            openMs: _sm.totalOpenMs,
            closedMs: _sm.totalClosedMs,
            unmeasuredMs: _sm.totalUnmeasuredMs,
            events: evs.length,
            avgOpenMs: evs.length ? total / evs.length : 0
        }
    }

    function _alert() {
        if (alertsMuted) return
        if (notifications) {
            Quickshell.execDetached([
                "notify-send", "-a", "MouthGuard", "-i", "sentiment_dissatisfied",
                "MouthGuard", "Close your mouth!"
            ])
        }
        if (soundType !== "none") {
            sound.source = Qt.resolvedUrl("sounds/" + soundType + ".wav")
            sound.volume = volume
            sound.play()
        }
    }

    function _onMeasurement(msg) {
        const now = Date.now()
        const dt = _lastTickAt ? now - _lastTickAt : 100
        _lastTickAt = now

        const hasFace = msg.gap !== undefined
        if (hasFace) {
            _noFaceSince = 0
            lastGap = msg.gap
            lastFace = msg.face
            lastAdjGap = (distComp && msg.face > 10)
                ? msg.gap * (DISTANCE_REF / msg.face) : msg.gap
        } else {
            if (!_noFaceSince) _noFaceSince = now
            lastAdjGap = 0
        }

        const effective = distComp ? lastAdjGap : lastGap
        const events = SM.tick(_sm, {
            now: now, dt: dt, isOpen: hasFace && effective > threshold,
            hasFace: hasFace, delay: alertDelayMs
        })

        if (events.indexOf("alert") >= 0) _alert()

        // Chart plots the same number the threshold is compared against, so the
        // threshold line stays meaningful whichever mode is active.
        const cutoff = now - 60000
        const next = gapHistory.concat([{ t: now, gap: hasFace ? effective : 0 }])
        gapHistory = next.filter(p => p.t >= cutoff)

        mouthState = !hasFace ? "noface" : (_sm.mouthOpen ? "open" : "closed")
        _publishStats()

        if (_noFaceSince && noFaceTimeoutMs > 0
                && now - _noFaceSince > noFaceTimeoutMs) {
            ToastService?.showInfo(
                "MouthGuard stopped — no face detected for "
                + Math.round(noFaceTimeoutMs / 60000) + " minutes")
            active = false
            mouthState = "inactive"
        }
    }

    SoundEffectWrapper { id: sound }

    Process {
        id: detector
        running: root.active
        command: [
            "python3", pluginService.getPluginPath(root.pluginId) + "/detector.py",
            "--device", root.device, "--fps", String(root.fps)
        ]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!data) return
                let msg
                try { msg = JSON.parse(data) } catch (e) { return }
                if (msg.error) {
                    ToastService?.showError("MouthGuard: " + msg.error + " — " + msg.detail)
                    root.active = false
                    return
                }
                if (msg.ready) return
                root._onMeasurement(msg)
            }
        }

        stderr: StdioCollector {
            onTextReceived: text => console.warn("[MouthGuard]", text)
        }

        onExited: exitCode => {
            if (exitCode !== 0 && root.active) {
                ToastService?.showError("MouthGuard detector exited: " + exitCode)
                root.active = false
                root.mouthState = "inactive"
            }
        }
    }

    Component.onCompleted: {
        if (!pluginService) return
        const next = Object.assign({}, pluginService.pluginInstances)
        next[pluginId] = root
        pluginService.pluginInstances = next
        // Resume whatever the last session state was.
        active = pluginService.loadPluginData(pluginId, "active", false)
        if (active) resetSession()
    }

    Component.onDestruction: {
        if (!pluginService) return
        if (pluginService.pluginInstances[pluginId] !== root) return
        const next = Object.assign({}, pluginService.pluginInstances)
        delete next[pluginId]
        pluginService.pluginInstances = next
    }

    onActiveChanged: pluginService?.savePluginData(pluginId, "active", active)
}
```

- [ ] **Step 2: Substitute the calibrated constants**

Replace both `<measured>` placeholders with the values recorded in `CALIBRATION.md` from Task 7. The plugin will not behave sensibly until this is done.

- [ ] **Step 3: Reload and verify end-to-end alerting**

```bash
dms ipc plugin-scan reload mouthGuard
```

Click the pill to start. Confirm:
- the icon changes to `sentiment_satisfied` and the camera LED comes on
- holding the mouth open for more than the alert delay turns the pill `Theme.error`, fires a notification, and plays the sound
- closing the mouth returns the pill to normal immediately
- a brief opening well under the delay fires nothing at all

- [ ] **Step 4: Verify no duplicate detectors on multi-monitor**

Run: `pgrep -fa detector.py | wc -l`
Expected: `1`, even with the pill present on more than one bar.

- [ ] **Step 5: Commit**

```bash
git add MouthGuardDaemon.qml
git commit -m "feat: wire detector process, state machine, and alerts"
```

---

### Task 12: Auto-pause on lock, idle, and sleep

**Files:**
- Modify: `MouthGuardDaemon.qml`, `detector.py`

**Interfaces:**
- Consumes: `SessionService` (`locked`, `idleHint`, `preparingForSleep`) and `IdleService` (`monitorsOff`) from `qs.Services`.
- Produces: `property bool paused` on the daemon, and `pause`/`resume` written to the detector's stdin. The process keeps running while paused so the 96 MB model stays resident.

- [ ] **Step 1: Add stdin writing to the Process block**

Add to the `Process` element in `MouthGuardDaemon.qml`:

```qml
        stdinEnabled: true
```

- [ ] **Step 2: Add the pause binding and command dispatch**

Add to `MouthGuardDaemon.qml`:

```qml
    readonly property bool autoPause: pluginData?.autoPause ?? true

    readonly property bool shouldPause: active && autoPause && (
        (SessionService?.locked ?? false)
        || (SessionService?.idleHint ?? false)
        || (SessionService?.preparingForSleep ?? false)
        || (IdleService?.monitorsOff ?? false)
    )

    property bool paused: false

    onShouldPauseChanged: {
        if (!active) return
        paused = shouldPause
        // Releasing the capture device turns the camera LED off, but the
        // process stays alive so resuming does not pay the model reload.
        detector.write(shouldPause ? "pause\n" : "resume\n")
        mouthState = shouldPause ? "paused" : "closed"
        // Reset the tick clock so the paused span is not billed as one huge dt.
        _lastTickAt = 0
    }
```

- [ ] **Step 3: Suppress accounting while paused**

In `_onMeasurement`, immediately after `const now = Date.now()`, add:

```qml
        if (paused) return
```

- [ ] **Step 4: Verify pause releases the camera**

Lock the session (`loginctl lock-session`). Confirm within a second or two:

```bash
pgrep -fa detector.py          # still running
fuser /dev/video0 2>&1         # no longer held
```

Expected: process alive, device free, camera LED off.

- [ ] **Step 5: Verify resume is instant**

Unlock. Confirm the pill returns to `sentiment_satisfied` and gap values start updating again with no visible stall. Confirm `pgrep -fa detector.py` still reports the same PID as before the lock.

- [ ] **Step 6: Commit**

```bash
git add MouthGuardDaemon.qml
git commit -m "feat: auto-pause detector on lock, idle, and sleep"
```

---

### Task 13: Settings and persistence

**Files:**
- Modify: `MouthGuardSettings.qml`
- Modify: `MouthGuardDaemon.qml` (history persistence)

**Interfaces:**
- Consumes: the daemon's `sessionStats`.
- Produces: all setting keys named in the spec, plus `pluginService.savePluginState(pluginId, "history", [...])` holding at most 30 entries of `{start, durationMs, openMs, closedMs, events}`.

- [ ] **Step 1: Write the real settings component**

```qml
import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "mouthGuard"

    SelectionSetting {
        settingKey: "device"
        label: "Camera"
        description: "Which video device to read"
        options: [
            { label: "/dev/video0", value: "/dev/video0" },
            { label: "/dev/video1", value: "/dev/video1" }
        ]
        defaultValue: "/dev/video0"
    }

    SliderSetting {
        settingKey: "threshold"
        label: "Sensitivity threshold"
        description: "Lip gap that counts as open. Lower is more sensitive."
        from: 1; to: 30; stepSize: 0.5
        defaultValue: <measured>
    }

    SliderSetting {
        settingKey: "alertDelay"
        label: "Detection window"
        description: "Mouth must stay open this long to be detected and trigger an alert"
        from: 0; to: 10; stepSize: 0.1
        defaultValue: 1.0
    }

    ToggleSetting {
        settingKey: "distanceCompensation"
        label: "Distance compensation"
        description: "Keep sensitivity consistent regardless of how far you sit from the camera"
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "soundType"
        label: "Alert sound"
        options: [
            { label: "Soft beep", value: "soft" },
            { label: "Chime", value: "chime" },
            { label: "Double beep", value: "double" },
            { label: "Buzz", value: "buzz" },
            { label: "High ping", value: "ping" },
            { label: "None", value: "none" }
        ]
        defaultValue: "soft"
    }

    SliderSetting {
        settingKey: "volume"
        label: "Volume"
        from: 0; to: 100; stepSize: 5
        defaultValue: 85
    }

    ToggleSetting {
        settingKey: "notifications"
        label: "Desktop notifications"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "fps"
        label: "Detection rate"
        description: "Frames per second. Lower uses less CPU."
        from: 5; to: 15; stepSize: 1
        defaultValue: 10
    }

    SliderSetting {
        settingKey: "noFaceTimeout"
        label: "Stop after no face"
        description: "Minutes without a detected face before the session ends. 0 disables."
        from: 0; to: 15; stepSize: 1
        defaultValue: 5
    }

    ToggleSetting {
        settingKey: "autoPause"
        label: "Pause when locked or idle"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showGapInPill"
        label: "Show gap value in the bar"
        defaultValue: false
    }
}
```

- [ ] **Step 2: Substitute the calibrated threshold default**

Replace `<measured>` with `DEFAULT_THRESHOLD` from `CALIBRATION.md`. It must match the daemon's default exactly, or the pill and the settings page will disagree on day one.

- [ ] **Step 3: Add history persistence to the daemon**

Add to `MouthGuardDaemon.qml`:

```qml
    property var history: []

    function _saveSession() {
        if (!_sessionStart) return
        const measured = _sm.totalOpenMs + _sm.totalClosedMs
        // A session with nothing measured is noise, not history.
        if (measured < 1000) return

        const entry = {
            start: _sessionStart,
            durationMs: Date.now() - _sessionStart,
            openMs: _sm.totalOpenMs,
            closedMs: _sm.totalClosedMs,
            events: _sm.openEvents.length
        }
        history = [entry].concat(history).slice(0, 30)
        pluginService?.savePluginState(pluginId, "history", history)
    }
```

Call `_saveSession()` at the top of `toggle()` when `active` is about to become false, and in the no-face auto-stop branch before clearing `active`. Load it in `Component.onCompleted`:

```qml
        history = pluginService.loadPluginState(pluginId, "history", [])
```

- [ ] **Step 4: Verify settings round-trip**

Reload the plugin, open Settings > Plugins > MouthGuard, change the threshold and alert delay, and confirm the pill's behaviour changes **without** the camera restarting (`pgrep -fa detector.py` keeps the same PID). This is the payoff of keeping policy in QML.

- [ ] **Step 5: Verify history survives a restart**

Run a short session, stop it, then `dms ipc plugin-scan reload mouthGuard`. Confirm the entry persists:

```bash
jq '.mouthGuard.history | length' ~/.config/DankMaterialShell/plugin-state.json
```

Expected: at least `1`. If the file path differs on this DMS version, locate it with `grep -rl mouthGuard ~/.config/DankMaterialShell/`.

- [ ] **Step 6: Commit**

```bash
git add MouthGuardSettings.qml MouthGuardDaemon.qml
git commit -m "feat: add settings and session history persistence"
```

---

### Task 14: Lip gap chart

**Files:**
- Create: `GapChart.qml`

**Interfaces:**
- Consumes: `gapHistory` and `threshold` from the daemon.
- Produces: `GapChart` with `property var points` (array of `{t, gap}`), `property real threshold`, `property int windowMs` (default 60000). Repaints when `points` changes.

- [ ] **Step 1: Write the chart**

```qml
import QtQuick
import qs.Common

Canvas {
    id: root

    property var points: []
    property real threshold: 0
    property int windowMs: 60000

    onPointsChanged: requestPaint()
    onThresholdChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)

        if (!points || points.length < 2) return

        const now = points[points.length - 1].t
        const t0 = now - windowMs
        // Scale to the taller of the data and the threshold, so the threshold
        // line is always on screen even when the mouth never opens.
        let maxGap = threshold * 1.4
        for (let i = 0; i < points.length; i++) {
            if (points[i].gap > maxGap) maxGap = points[i].gap
        }
        if (maxGap <= 0) return

        const xOf = t => (t - t0) / windowMs * width
        const yOf = g => height - (g / maxGap) * height

        // Threshold reference line
        ctx.save()
        ctx.setLineDash([4, 4])
        ctx.strokeStyle = Theme.error
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(0, yOf(threshold))
        ctx.lineTo(width, yOf(threshold))
        ctx.stroke()
        ctx.restore()

        // Gap trace
        ctx.strokeStyle = Theme.primary
        ctx.lineWidth = 2
        ctx.beginPath()
        let started = false
        for (let i = 0; i < points.length; i++) {
            const p = points[i]
            if (p.t < t0) continue
            const x = xOf(p.t)
            const y = yOf(p.gap)
            if (!started) { ctx.moveTo(x, y); started = true }
            else ctx.lineTo(x, y)
        }
        ctx.stroke()
    }
}
```

- [ ] **Step 2: Verify it renders**

Temporarily add the chart to the widget's popout (Task 15 makes it permanent) and confirm a live trace appears with a dashed red threshold line, that it scrolls, and that opening the mouth pushes the trace above the line.

- [ ] **Step 3: Commit**

```bash
git add GapChart.qml
git commit -m "feat: add live lip gap chart"
```

---

### Task 15: Popout with stats and history

**Files:**
- Modify: `MouthGuardWidget.qml`

**Interfaces:**
- Consumes: the daemon's `mouthState`, `gapHistory`, `sessionStats`, `history`, `lastFace`, `lastAdjGap`, `threshold`, `distComp`, `toggle()`.
- Produces: the finished popout. No new outward interface.

- [ ] **Step 1: Add popout sizing and content to `MouthGuardWidget.qml`**

```qml
    popoutWidth: 420
    popoutHeight: 380

    function _fmt(ms) {
        if (!ms) return "—"
        const s = Math.floor(ms / 1000)
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
    }

    popoutContent: Component {
        PopoutComponent {
            headerText: "MouthGuard"
            detailsText: root.mouthState === "inactive"
                ? "Not tracking"
                : "Tracking — " + root.mouthState
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                GapChart {
                    width: parent.width
                    height: 120
                    points: root.daemon?.gapHistory ?? []
                    threshold: root.daemon?.threshold ?? 0
                }

                Row {
                    spacing: Theme.spacingL
                    visible: root.daemon?.distComp ?? false

                    StyledText {
                        text: "Face " + Math.round(root.daemon?.lastFace ?? 0) + "px"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    StyledText {
                        text: "Adj. gap " + (root.daemon?.lastAdjGap ?? 0).toFixed(1) + "px"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                Row {
                    spacing: Theme.spacingL

                    StyledText {
                        text: "Open " + root._fmt(root.daemon?.sessionStats.openMs)
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    StyledText {
                        text: "Closed " + root._fmt(root.daemon?.sessionStats.closedMs)
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    StyledText {
                        text: "Events " + (root.daemon?.sessionStats.events ?? 0)
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                StyledText {
                    text: "History — bar & % = time mouth was open"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                Repeater {
                    model: (root.daemon?.history ?? []).slice(0, 5)

                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        StyledText {
                            text: new Date(modelData.start).toLocaleTimeString(
                                Qt.locale(), Locale.ShortFormat)
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            width: 60
                        }
                        StyledText {
                            text: {
                                const tot = modelData.openMs + modelData.closedMs
                                return tot > 0
                                    ? Math.round(modelData.openMs / tot * 100) + "% open"
                                    : "—"
                            }
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }

                DankButton {
                    text: root.daemon?.active ? "Stop" : "Start"
                    onClicked: root.daemon?.toggle()
                }
            }
        }
    }
```

- [ ] **Step 2: Add the optional gap readout and click actions to the horizontal pill**

This implements the `showGapInPill` setting declared in Task 13. Replace the whole
`horizontalBarPill` component from Task 9 with:

```qml
    readonly property bool showGap: (pluginData?.showGapInPill ?? false)
        && root.mouthState !== "inactive"

    horizontalBarPill: Component {
        StyledRect {
            width: content.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            Row {
                id: content
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.iconFor[root.mouthState]
                    size: Theme.iconSizeSmall
                    color: root.stateColor
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.showGap
                    text: (root.daemon?.distComp
                        ? (root.daemon?.lastAdjGap ?? 0)
                        : (root.daemon?.lastGap ?? 0)).toFixed(1)
                    color: root.stateColor
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton) root.daemon?.toggle()
                    else if (mouse.button === Qt.RightButton) {
                        if (root.daemon) root.daemon.alertsMuted = !root.daemon.alertsMuted
                    } else root.popoutService?.togglePopout(root.pluginId)
                }
            }
        }
    }
```

- [ ] **Step 3: Add the same click actions to the vertical pill**

The vertical pill deliberately omits the gap readout — a side-mounted bar is too narrow for a
number beside the icon. Replace only its `MouseArea` with:

```qml
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton) root.daemon?.toggle()
                    else if (mouse.button === Qt.RightButton) {
                        if (root.daemon) root.daemon.alertsMuted = !root.daemon.alertsMuted
                    } else root.popoutService?.togglePopout(root.pluginId)
                }
            }
```

- [ ] **Step 4: Verify the popout**

Reload, click the pill, and confirm: the chart animates, stats tick up, the distance readouts appear only with compensation on, history lists past sessions, and Start/Stop works. Middle-click toggles tracking; right-click mutes alerts. Turn on "Show gap value in the bar" and confirm a live number appears beside the pill icon.

- [ ] **Step 5: Commit**

```bash
git add MouthGuardWidget.qml
git commit -m "feat: add popout with chart, stats, and history"
```

---

### Task 16: Control Center tile

**Files:**
- Modify: `MouthGuardWidget.qml`

**Interfaces:**
- Consumes: the daemon's `active`, `mouthState`, `toggle()`.
- Produces: no new outward interface.

- [ ] **Step 1: Add the CC properties**

```qml
    ccWidgetIcon: root.iconFor[root.mouthState]
    ccWidgetPrimaryText: "MouthGuard"
    ccWidgetSecondaryText: {
        if (!root.daemon?.active) return "Off"
        if (root.mouthState === "paused") return "Paused"
        if (root.mouthState === "noface") return "No face"
        return root.mouthState === "open" ? "Mouth open" : "Tracking"
    }
    ccWidgetIsActive: root.daemon?.active ?? false

    onCcWidgetToggled: root.daemon?.toggle()

    ccDetailContent: Component {
        Rectangle {
            implicitHeight: 160
            color: Theme.surfaceContainerHigh
            radius: Theme.cornerRadius

            Column {
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                GapChart {
                    width: parent.width
                    height: 90
                    points: root.daemon?.gapHistory ?? []
                    threshold: root.daemon?.threshold ?? 0
                }

                StyledText {
                    text: "Open " + root._fmt(root.daemon?.sessionStats.openMs)
                        + "   Events " + (root.daemon?.sessionStats.events ?? 0)
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }
```

- [ ] **Step 2: Verify in Control Center**

Open Control Center. Confirm the tile appears, renders as a CompoundPill at 50% width (because `ccDetailContent` is defined), toggles tracking, and that the expanded detail shows a live chart.

- [ ] **Step 3: Commit**

```bash
git add MouthGuardWidget.qml
git commit -m "feat: add Control Center tile"
```

---

### Task 17: Documentation and release prep

**Files:**
- Create: `README.md`, `screenshot.png`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: everything.
- Produces: a repo ready to publish.

- [ ] **Step 1: Write `README.md`**

Cover, in this order: what it does; a screenshot; requirements (`python3`, `cv2`, `dlib`, the 68-point model) with per-distro install commands and the `nix develop` route; install via `dms plugins install` and via manual `git clone` into `~/.config/DankMaterialShell/plugins/MouthGuard`; the click/middle-click/right-click table; a settings table matching `MouthGuardSettings.qml`; how it works (the detector/QML split, and why); and a **Limitations** section stating plainly:

- dlib's HOG detector loses the face past roughly 30° of head turn, where the browser version using MediaPipe still tracked. This shows as `noface` rather than false alerts, but it is a real accuracy regression.
- `PrivacyService.cameraActive` is PipeWire-derived, so DMS's built-in camera indicator will most likely not light up for this plugin's direct V4L2 access. The pill is the honest signal.
- The landmark model is 96 MB and comes from `face-recognition-models` (Nix) or the distro dlib data package.
- Thresholds are calibrated for the author's camera; see `CALIBRATION.md` to re-tune.

Link back to the web app at `https://github.com/sitolam/mouthguard`.

- [ ] **Step 2: Capture the screenshot**

With a session running and the popout open on the default dank purple theme, showing real data in the chart:

```bash
dms ipc screenshot region      # or the compositor's own tool
```

Save as `screenshot.png` in the repo root.

- [ ] **Step 3: Update `CHANGELOG.md`**

Replace the `Unreleased` block with a `## [0.1.0]` entry dated on release, listing: dlib-based detection, bar pill with five states, popout with live chart and stats, 30-session history, five alert sounds, distance compensation, auto-pause on lock/idle/sleep, no-face auto-stop, and Control Center integration.

- [ ] **Step 4: Run the full test suite one last time**

Run: `nix develop -c pytest -v`
Expected: all passed

Run: `nix develop -c qmltestrunner -input tests/tst_statemachine.qml`
Expected: 10 passed

- [ ] **Step 5: Commit and tag**

```bash
git add README.md screenshot.png CHANGELOG.md
git commit -m "docs: add README, screenshot, and 0.1.0 changelog"
git tag v0.1.0
```

---

## Out of scope

Registry submission (`plugins/sitolam-mouthguard.json` in `AvengeMedia/dms-plugin-registry`, with
`"id": "mouthGuard"` matching `plugin.json` and category `monitoring`) is deliberately deferred
until the plugin has been used daily and the calibration has held up on more than one camera.
