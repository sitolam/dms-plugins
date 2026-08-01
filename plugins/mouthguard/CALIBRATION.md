# Calibration

> **STATUS: NOT YET RECORDED.** Every numeric cell in this document is a
> `TBD (pending 7b recording)` placeholder. No pose has been captured, no
> webcam has been opened, and neither `DEFAULT_THRESHOLD` nor
> `DEFAULT_DISTANCE_REF` has been added to `mouthguard_core.py`. This file
> exists only to define the shape of the record that Task 7b (the live
> recording session) will fill in.

## Why this exists

dlib's inner-lip landmarks (`mouthguard_core.LIP_TOP` / `LIP_BOTTOM`) produce
raw pixel distances on a completely different numeric scale than MediaPipe's,
which the original web app was tuned against. The web app's threshold of `5`
and its distance-compensation reference of `100px` are meaningless here —
they must be re-measured against a real dlib pipeline on real hardware.
`tools/calibrate.py` (built in Task 7a) is the tool that does the measuring;
Task 7b is the session where a person sits in front of the camera and holds
four poses while it runs.

## The four poses

Each pose is held for ~20 seconds at normal seating distance (except where
noted), while `tools/calibrate.py <label> <seconds>` records every `gap` and
`face` measurement `detector.py` emits.

| Label | Pose | What it establishes |
|---|---|---|
| `closed-near` | Mouth firmly closed, normal seating distance | The "definitely closed" gap distribution, and the face-height reference for distance compensation |
| `ajar-near` | Lips barely parted, normal seating distance | The lower edge of "definitely open" — the boundary the threshold must clear |
| `open-near` | Mouth clearly open, normal seating distance | A sanity check that "open" reads well above threshold, not used in the derivation itself |
| `closed-far` | Mouth firmly closed, arm's length back from the screen | Tests that distance compensation correctly rescales a closed mouth recorded farther away back to the `closed-near` gap range |

## Results table

Fill in from each `tools/calibrate.py` run's printed summary line
(`label: n=... gap median=... p05=... p95=... face median=...`).

| Pose | n | gap median | gap p05 | gap p95 | face median |
|---|---|---|---|---|---|
| `closed-near` | TBD (pending 7b recording) | TBD (pending 7b recording) | TBD (pending 7b recording) | TBD (pending 7b recording) | TBD (pending 7b recording) |
| `ajar-near` | TBD (pending 7b recording) | TBD (pending 7b recording) | TBD (pending 7b recording) | TBD (pending 7b recording) | TBD (pending 7b recording) |
| `open-near` | TBD (pending 7b recording) | TBD (pending 7b recording) | TBD (pending 7b recording) | TBD (pending 7b recording) | TBD (pending 7b recording) |
| `closed-far` | TBD (pending 7b recording) | TBD (pending 7b recording) | TBD (pending 7b recording) | TBD (pending 7b recording) | TBD (pending 7b recording) |

## Derived constants

Both constants are derived from the table above, not chosen independently.

### `DEFAULT_THRESHOLD`

The gap value above which a mouth counts as open. It must sit cleanly above
`closed-near` p95 and below `ajar-near` p05 — that gap is the separation
margin between "definitely closed" and "definitely open" the whole plugin
depends on.

- If the two ranges **do not overlap**: pick any value in the gap between
  `closed-near` p95 and `ajar-near` p05 (their midpoint is a reasonable
  default).
- If the two ranges **overlap**: the landmarks cannot cleanly separate the
  poses on this camera/lighting setup. Fall back to the midpoint of the two
  *medians* (not the p95/p05 values) and say so explicitly in the reasoning
  line below — do not silently pick a number as if separation were clean.

`DEFAULT_THRESHOLD` = TBD (pending 7b recording)

Reasoning: TBD (pending 7b recording)

### `DEFAULT_DISTANCE_REF`

The `face` (nose-to-chin) median from `closed-near` — the face height, in
dlib pixel units, that all other measurements get rescaled to via
`compensate(gap, face, ref)`.

`DEFAULT_DISTANCE_REF` = TBD (pending 7b recording)

### Sanity check

`compensate(gap_far_median, face_far_median, DEFAULT_DISTANCE_REF)`, using
the `closed-far` row above, should land close to the `closed-near` gap
median. If it does not, distance compensation is not doing its job — the
recordings should be repeated with more consistent framing between the near
and far poses.

- `compensate(closed-far gap median, closed-far face median, DEFAULT_DISTANCE_REF)` = TBD (pending 7b recording)
- `closed-near` gap median (for comparison) = TBD (pending 7b recording)

## Recording conditions

| Field | Value |
|---|---|
| Date | TBD (pending 7b recording) |
| Camera device | TBD (pending 7b recording) |
| Camera model | TBD (pending 7b recording) — from `v4l2-ctl --list-devices` or `/sys/class/video4linux/video0/name` |
| Lighting | TBD (pending 7b recording) |
| Operator | TBD (pending 7b recording) |

## After recording (7b checklist)

Task 7b, once the table above is filled in, still owes:

1. Replace every `TBD (pending 7b recording)` cell in this file with the
   measured value.
2. Append the derived constants to `mouthguard_core.py`:

   ```python
   # Derived empirically — see CALIBRATION.md. These are dlib-scale values and
   # bear no relation to the web app's MediaPipe-scale threshold of 5.
   DEFAULT_THRESHOLD = <measured>
   DEFAULT_DISTANCE_REF = <measured>
   ```

3. Commit `tools/calibrate.py` (already done in 7a), the completed
   `CALIBRATION.md`, and the updated `mouthguard_core.py` together.

Until all three of those are done, `DEFAULT_THRESHOLD` and
`DEFAULT_DISTANCE_REF` do not exist anywhere in this repository. Any code
that references them before then is reading a name that has not been
defined.
