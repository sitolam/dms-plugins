# Calibration

> **STATUS: RECORDED.** `DEFAULT_THRESHOLD` and `DEFAULT_DISTANCE_REF` are
> defined in `mouthguard_core.py`, derived from the measurements below. The
> recording session was performed by the project owner at the webcam; this
> document only records the results and the reasoning, and was not itself
> allowed to open a camera device.

## Why this exists

dlib's inner-lip landmarks (`mouthguard_core.LIP_TOP` / `LIP_BOTTOM`) produce
raw pixel distances on a completely different numeric scale than MediaPipe's,
which the original web app was tuned against. The web app's threshold of `5`
and its distance-compensation reference of `100px` are meaningless here — they
had to be re-measured against a real dlib pipeline on real hardware.
`tools/calibrate.py` (built in Task 7a) is the tool that does the measuring.

## Recording conditions

| Field | Value |
|---|---|
| Date | 2026-08-02 |
| Camera device | `/dev/video0` |
| Camera model | Logitech UVC 046d:0990 |
| Capture resolution | 640x480 |
| Detector configuration | HOG face detector **and** 68-point predictor both run at full 640x480 resolution — no downscale anywhere in the pipeline (commit `5d561f9` removed the `--scale` knob entirely; see "Findings that cost real debugging effort" below) |
| Operator | Project owner, at the webcam |

## The three poses

Each pose was held at normal seating distance while `tools/calibrate.py
<label> <seconds>` recorded every `gap` and `face` measurement `detector.py`
emitted. Raw rows are committed as `calibration-closed-near.csv`,
`calibration-ajar-near.csv`, and `calibration-open-near.csv`.

| Label | Pose | What it establishes |
|---|---|---|
| `closed-near` | Mouth firmly closed, normal seating distance | The "definitely closed" gap distribution, and the face-height reference for distance compensation |
| `ajar-near` | Lips barely parted, normal seating distance | The lower edge of "definitely open" — the boundary the threshold must clear |
| `open-near` | Mouth clearly open, normal seating distance | A sanity check that "open" reads well above threshold |

A fourth pose (`closed-far`, testing distance compensation at arm's length)
was attempted but is not part of this record: dlib's HOG detector found no
face at that distance under the lighting available during recording (see
"Camera warm-up" below for a related, but distinct, cause of missing early
samples). Distance compensation is instead validated below by applying it to
the three near-distance recordings themselves and confirming it moves the
medians only slightly, as expected when face height already sits close to the
reference.

## Results table (raw, per-frame)

| Pose | n | gap median | gap p05 | gap p95 | face median |
|---|---|---|---|---|---|
| `closed-near` | 154 | 2.00 | 0.00 | 4.12 | 71.06 |
| `ajar-near` | 155 | 4.00 | 3.00 | 5.00 | 72.34 |
| `open-near` | 150 | 6.00 | 5.00 | 7.00 | 77.41 |

Note how close the raw `closed-near` p95 (4.12) sits to the raw `ajar-near`
p05 (3.00) — per-frame, a single closed-mouth frame and a single ajar-mouth
frame can be nearly indistinguishable. This overlap is expected and is
addressed by the detection window, not by per-frame separation; see
"The single most important thing to understand" below.

## Distance-compensated table

`compensate(gap, face, ref)` applied per-frame with `ref = 71`
(`DEFAULT_DISTANCE_REF`):

| Pose | adj median | adj p05 | adj p95 |
|---|---|---|---|
| `closed-near` | 2.19 | 0.00 | 4.11 |
| `ajar-near` | 3.93 | 2.87 | 4.98 |
| `open-near` | 5.51 | 4.53 | 6.43 |

Because `REF` was chosen to equal the `closed-near` face median (71.06,
rounded down to 71), and all three poses were recorded at the same seating
distance, compensation barely moves these numbers — that is the expected,
correct outcome for same-distance recordings, not a sign the compensation
step did nothing. Its purpose is to normalise a session where the user's
distance from the camera drifts over time, not to change same-distance
numbers.

## Detection-window simulation — the real basis for the threshold

Per-frame medians and percentiles are not what actually gates an alert: the
state machine (`StateMachine.js`, ported from the web app's `index.html`)
only confirms "mouth open" after the raw signal has stayed above threshold
continuously for a full detection window (the `delay` parameter to `tick()`,
1.0s by default). The recorded time series for each pose was replayed
through that real windowing logic — not just summarised statistically — to
find a threshold that survives it.

| Window | Threshold | Result |
|---|---|---|
| 1.0s (default) | 3.0 | closed 0.0 false alarms/min; ajar DETECTED; open DETECTED |
| 1.0s (default) | 3.5 | closed 0.0 false alarms/min; ajar DETECTED; open DETECTED |
| 1.0s (default) | 4.0 | closed 0.0 false alarms/min; ajar MISSED; open DETECTED |
| 0.5s | 3.0 | 5.8 false alarms/min |
| 0.5s | 3.5 | 2.9 false alarms/min |
| 2.0s | 3.0 | ajar MISSED |
| 2.0s | 3.5 | ajar MISSED |
| 2.0s | 2.5 | ajar detected |

## The two chosen constants

```python
DEFAULT_THRESHOLD = 3.5
DEFAULT_DISTANCE_REF = 71
```

### `DEFAULT_THRESHOLD` = 3.5

At the default 1.0s detection window, both 3.0 and 3.5 detect both ajar and
open poses with zero false alarms on the closed-mouth recording. **3.5 was
chosen over 3.0 for headroom**: at a shortened 0.5s window (a plausible
future setting, e.g. for users who want a faster-reacting alert) threshold
3.5 produces roughly half the false-alarm rate of 3.0 (2.9/min vs 5.8/min).
3.5 is also the highest threshold that still detects `ajar-near` at the
default window — 4.0 misses it. So 3.5 sits at the boundary that maximises
false-alarm headroom without losing sensitivity to the hardest real case
(a barely-parted mouth).

4.0 was rejected outright: it fails to detect `ajar-near`, the central case
this plugin exists to catch.

### `DEFAULT_DISTANCE_REF` = 71

The `face` (nose-to-chin) median from `closed-near`: 71.06, recorded as 71.
This is the face height, in dlib pixel units, that all other measurements
get rescaled to via `compensate(gap, face, ref)`.

### The single most important thing to understand

**The per-frame distributions overlap substantially.** `closed-near` p95
(4.11, compensated) and `ajar-near` p05 (2.87, compensated) overlap by more
than a full unit — there is no gap value that cleanly separates a single
closed-mouth frame from a single ajar-mouth frame. If you look only at the
compensated table above and try to pick a threshold that sits between the
two ranges the way the original 4-pose plan assumed, you will conclude no
such threshold exists, and you would be right — for a single frame.

What actually makes this work is **the detection window**, not per-frame
separation: `ajar-near`'s signal, while noisy, sits above 3.5 *on average and
often enough* that a full 1.0s of continuous frames above threshold is
reached, while `closed-near`'s occasional excursions above 3.5 never sustain
for a full window. The threshold and the window are a matched pair — neither
one works alone. Re-deriving either constant without re-running the
detection-window simulation (not just re-computing percentiles) will very
likely produce a value that looks reasonable on paper and fails in practice.

## Findings that cost real debugging effort

These were each expensive to discover and are recorded here so they are not
re-learned the hard way on a future camera, machine, or contributor.

### 1. Downscaling the predictor made a barely-parted mouth invisible

An earlier calibration attempt ran the 68-point landmark predictor on a
frame downscaled by `--scale 0.5`, with coordinates doubled back up
afterward. That pass produced landmark measurements quantised to ~2px steps
(observed raw gap values: 0, 2.00, 2.83, 4.00, 4.47, 6.00, 6.32, 8.00 — see
`calibration-*-near.OLD.csv`, kept for the record). At that quantisation,
`closed-near` and `ajar-near` had **identical medians (4.00 for both)**, and
`ajar-near`'s max (6.00) was actually *lower* than `closed-near`'s max
(8.00) — a barely-parted mouth was statistically indistinguishable from a
closed one. This was not a tuning problem; it was a resolution problem:
half of the already-small few-pixel signal this plugin depends on was
discarded before it was ever measured. Commit `80deea1` moved the predictor
to run on the full-resolution frame, which is what produced the clean,
continuous-valued measurements in the tables above.

### 2. The HOG detector has a minimum face size, and downscaling silently crossed it

Separately from the predictor's precision loss, dlib's HOG frontal face
detector has a minimum detectable face size around 80x80px. At `--scale
0.5`, a normally-seated user's face — approximately 104x103px at full
640x480 resolution — shrank to roughly 52x52px on the downscaled frame the
detector actually ran on, below that floor. Detection then failed
**silently**: no error, no face, just an empty stream, exactly as if no one
were in frame. This is the worst failure mode for a mouth-breathing tracker,
because it looks identical to "working correctly, nobody there" rather than
"broken." It also explains why an earlier calibration pass could appear to
succeed (the operator had leaned in closer than normal, keeping the
downscaled face above the floor) while live testing at a normal seated
distance failed with no diagnostic at all. Commit `5d561f9` removed
`--scale` entirely, rather than tuning its default, because a downscale knob
whose plausible-looking values silently disable detection is not a safe
knob to leave in place. Both the HOG detector and the predictor now run
against the same full-resolution frame, which is also why `--width` /
`--height` directly determine the usable seating-distance range (documented
in `detector.py --help`).

### 3. Camera warm-up dominates short recordings

The first usable (face-detected) sample from a cold-started UVC camera
arrives roughly 7 seconds after the detector process starts, while the
camera auto-exposes. A calibration recording shorter than about 15 seconds
is therefore dominated by warm-up noise rather than steady-state
measurement — this is part of why `tools/calibrate.py` pose recordings run
for 20 seconds. This also means a real detection *session* (not just
calibration) has a multi-second blind period immediately after the daemon
starts or after the camera is reopened (e.g. after a pause/resume cycle) —
worth surfacing in the plugin's README as a known limitation, since a user
could otherwise interpret the initial silence as the tracker not working.

## How to re-calibrate for a different camera or person

The constants above are specific to one camera, one face, and one lighting
setup. Re-run this procedure whenever any of those changes meaningfully
(new hardware, a different primary user, a room with very different
lighting):

1. **Do not skip the warm-up.** Record each pose for at least 20 seconds
   with `tools/calibrate.py <label> <seconds>` — the first ~7s will be
   discarded warm-up noise, not signal.

2. **Record at minimum:**

   ```bash
   nix develop -c python3 tools/calibrate.py closed-near 20   # mouth firmly closed
   nix develop -c python3 tools/calibrate.py ajar-near 20     # lips barely parted
   nix develop -c python3 tools/calibrate.py open-near 20     # clearly open
   ```

   Each invocation prints a summary line (`label: n=... gap median=...
   p05=... p95=... face median=...`) and, on a complete (non-truncated)
   recording, writes `calibration-<label>.csv` with every raw sample.

3. **Set `DEFAULT_DISTANCE_REF`** to the `face` median from `closed-near`.

4. **Do not set `DEFAULT_THRESHOLD` from percentiles alone.** As shown
   above, per-frame percentiles for `closed-near` and `ajar-near` can and do
   overlap even when the whole system works correctly. Instead:
   - Write or reuse a small script that replays each recorded CSV through
     `StateMachine.tick()` at the detection window(s) you care about (at
     minimum the default 1.0s), sweeping candidate thresholds, and reports
     false alarms per minute on `closed-near` and whether `ajar-near` and
     `open-near` are detected.
   - Pick the highest threshold that still detects `ajar-near` at the
     default window — that maximises false-alarm headroom for users who
     shorten the window, without losing the hardest real case.
   - If no threshold detects `ajar-near` at any reasonable window, the
     landmarks are not separating the poses on this camera/lighting setup;
     do not force a number, investigate the recording (face size, lighting,
     `--scale`-style shortcuts) instead.

5. **If a face is not detected at all**, check face size against dlib's
   ~80x80px HOG floor before suspecting anything else — see finding 2
   above. `--width` / `--height` (not a resurrected `--scale`) are the
   supported way to trade detection distance for framerate.

6. Update `DEFAULT_THRESHOLD` and `DEFAULT_DISTANCE_REF` in
   `mouthguard_core.py`, and replace the tables and dated recording
   conditions in this file with the new measurements — keep the structure,
   since the reasoning about the detection window applies to any camera.
