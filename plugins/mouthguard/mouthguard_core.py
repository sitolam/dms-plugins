"""Pure helpers for the MouthGuard detector. No I/O, no OpenVINO, no OpenCV.

Everything here is a function of its arguments, so it can be tested without a
camera, an inference runtime, or a model file on disk.

The measurement pipeline is MediaPipe Face Mesh, the same one the MouthGuard
web app runs (@mediapipe/face_mesh 0.4): a BlazeFace short-range detector
finds the face, its box becomes a rotated square region of interest, and the
468-point landmark model runs on that crop. The geometry below -- anchor
generation, box decoding, region-of-interest construction, landmark
projection -- reimplements the calculator graph MediaPipe wraps around those
two models, because we drive the models directly rather than through
MediaPipe's own runtime.
"""

import json
import math
import os

# MediaPipe Face Mesh 468-point landmark indices. These match the web app.
LIP_TOP = 13      # inner upper lip
LIP_BOTTOM = 14   # inner lower lip
NOSE_TIP = 1
CHIN = 152

# Eye-corner landmarks used to orient the region of interest when tracking
# from the previous frame's mesh (MediaPipe's face_landmarks_to_roi uses the
# same pair: left eye inner-to-outer corner reference points).
LEFT_EYE_CORNER = 33
RIGHT_EYE_CORNER = 263

# Below this many pixels the face measurement is noise, not a face.
MIN_FACE_HEIGHT = 10.0


def _dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def lip_gap(points):
    """Vertical distance between the inner lip landmarks, in pixels.

    Deliberately the raw Y delta, not hypot: this is what the web app
    measures, and DEFAULT_THRESHOLD is calibrated against that. Face Mesh
    tracks a rotated region of interest, so the mesh it returns is already
    upright with respect to the head -- a tilted head does not tilt the
    lip axis in the way it would for a detector that only ever sees an
    axis-aligned crop.
    """
    return abs(points[LIP_TOP][1] - points[LIP_BOTTOM][1])


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


# --- model files ----------------------------------------------------------
# The two MediaPipe TFLite bundles, byte-identical to the ones the web app's
# @mediapipe/face_mesh 0.4 loads from its CDN. OpenVINO reads TFLite directly
# through its tensorflow_lite frontend, so they need no conversion step.
DETECTOR_MODEL = "face_detection_short_range.tflite"
LANDMARK_MODEL = "face_landmark.tflite"


class ModelNotFound(Exception):
    """A MediaPipe model file could not be located."""


def default_model_dirs():
    return [
        "/usr/share/mouthguard",
        "/usr/share/mediapipe/models",
        os.path.expanduser("~/.cache/mouthguard"),
    ]


def resolve_model_dir(env=None, candidates=None):
    """Locate the directory holding both TFLite models.

    MOUTHGUARD_MODEL_DIR overrides the search outright: if it is set but does
    not hold the models, that is an error rather than a reason to fall back,
    so a typo in the override surfaces instead of silently loading some other
    copy.
    """
    env = os.environ if env is None else env
    override = env.get("MOUTHGUARD_MODEL_DIR")
    if override:
        missing = _missing_models(override)
        if missing:
            raise ModelNotFound(
                f"MOUTHGUARD_MODEL_DIR={override} is missing: {', '.join(missing)}")
        return override

    for path in default_model_dirs() if candidates is None else candidates:
        if not _missing_models(path):
            return path

    raise ModelNotFound(
        f"Could not find {DETECTOR_MODEL} and {LANDMARK_MODEL}. Build the "
        "plugin's flake (nix build .#detector), or set MOUTHGUARD_MODEL_DIR "
        "to a directory holding both MediaPipe model files.")


def _missing_models(directory):
    return [name for name in (DETECTOR_MODEL, LANDMARK_MODEL)
            if not os.path.isfile(os.path.join(directory, name))]


# --- inference device -----------------------------------------------------
# Preference order for OpenVINO. The NPU is tried first because it is the
# lowest-power option and the models are small enough to fit it comfortably;
# the iGPU runs the same graph in about a millisecond, so falling back costs
# nothing perceptible. CPU is the floor and is always present.
DEVICE_PREFERENCE = ("NPU", "GPU", "CPU")


def order_devices(available, preference=DEVICE_PREFERENCE):
    """Available devices sorted best-first, unknown ones last.

    Matching is by prefix so multi-device names ("GPU.0", "GPU.1") count as
    their family. Devices outside the preference list keep their reported
    order behind the known ones rather than being dropped: an accelerator we
    have not heard of is still worth trying before giving up.
    """
    def rank(dev):
        for i, want in enumerate(preference):
            if dev == want or dev.startswith(want + "."):
                return i
        return len(preference)

    return sorted(available, key=rank)


def pick_device(available, preference=DEVICE_PREFERENCE):
    """The single best available device, or CPU when none is known."""
    ordered = order_devices(available, preference)
    return ordered[0] if ordered else "CPU"


# --- BlazeFace: anchors and box decoding ----------------------------------
# Parameters from MediaPipe's face_detection_short_range.tflite SSD anchor
# options: 4 layers, strides 8/16/16/16 over a 128x128 input, fixed anchor
# size, one aspect ratio plus one interpolated scale. That yields 2 anchors
# per cell of a 16x16 grid and 6 per cell of an 8x8 grid: 896 total, which is
# exactly the model's output row count.
DETECTOR_INPUT_SIZE = 128
DETECTOR_STRIDES = (8, 16, 16, 16)
DETECTOR_MIN_SCORE = 0.5
LANDMARK_INPUT_SIZE = 192
LANDMARK_MIN_PRESENCE = 0.5
NUM_LANDMARKS = 468


def ssd_anchors(input_size=DETECTOR_INPUT_SIZE, strides=DETECTOR_STRIDES):
    """Anchor centres, in [0,1] input-relative coordinates.

    Only the centres are produced: this configuration sets fixed_anchor_size,
    so every anchor's width and height are 1.0 and the decoder below can treat
    them as constants rather than carrying two useless columns per row.
    """
    anchors = []
    layer = 0
    while layer < len(strides):
        # Consecutive layers sharing a stride are merged into one grid pass,
        # each contributing its own anchor per cell -- that is what turns the
        # three stride-16 layers into 6 anchors per stride-16 cell.
        last = layer
        while last < len(strides) and strides[last] == strides[layer]:
            last += 1
        repeats = 2 * (last - layer)  # x2 for the interpolated aspect ratio

        stride = strides[layer]
        rows = math.ceil(input_size / stride)
        cols = math.ceil(input_size / stride)
        for y in range(rows):
            for x in range(cols):
                cx = (x + 0.5) / cols
                cy = (y + 0.5) / rows
                anchors.extend([(cx, cy)] * repeats)
        layer = last
    return anchors


def sigmoid(x):
    """Logistic function, clipped the way MediaPipe clips its scores.

    Without the clip a strongly negative logit overflows math.exp; MediaPipe
    caps at +/-100 for the same reason.
    """
    x = max(-100.0, min(100.0, x))
    return 1.0 / (1.0 + math.exp(-x))


def decode_detection(regressor, anchor, input_size=DETECTOR_INPUT_SIZE):
    """One BlazeFace regressor row to a box in [0,1] coordinates.

    Returns (xmin, ymin, width, height) plus the two eye keypoints, which are
    what orients the region of interest. Offsets arrive in input-pixel units
    and are divided by the input size to land back in relative coordinates.
    """
    cx = regressor[0] / input_size + anchor[0]
    cy = regressor[1] / input_size + anchor[1]
    w = regressor[2] / input_size
    h = regressor[3] / input_size
    keypoints = [
        (regressor[4 + i * 2] / input_size + anchor[0],
         regressor[5 + i * 2] / input_size + anchor[1])
        for i in range(6)
    ]
    return (cx - w / 2, cy - h / 2, w, h), keypoints


# --- region of interest ---------------------------------------------------
# MediaPipe expands the detection box by 1.5x and squares it off before
# cropping for the landmark model. Both numbers come from the face_landmark
# graph's rect transformation options; the landmark model was trained on that
# framing, so changing them degrades the mesh.
ROI_SCALE = 1.5


def rect_from_detection(box, keypoints, frame_w, frame_h):
    """Rotated square crop region, in frame pixels, from a BlazeFace hit.

    Rotation comes from the line between the two eye keypoints, so the crop
    handed to the landmark model is upright with respect to the head.
    """
    xmin, ymin, w, h = box
    cx = (xmin + w / 2) * frame_w
    cy = (ymin + h / 2) * frame_h
    # MediaPipe's detections_to_rects: rotation = target_angle - atan2(
    # -(y_end - y_start), x_end - x_start), with a target angle of 0 and the
    # two eye keypoints as start and end. The double negation collapses to a
    # plain atan2 of end-minus-start; writing it the other way round (start
    # minus end) is the same line 180 degrees out, which hands the landmark
    # model an upside-down face and loses tracking every other frame.
    start, end = keypoints[0], keypoints[1]
    angle = math.atan2((end[1] - start[1]) * frame_h,
                       (end[0] - start[0]) * frame_w)
    return _square_rect(cx, cy, w * frame_w, h * frame_h, angle)


def rect_from_landmarks(points, frame_w, frame_h):
    """Crop region for the next frame, derived from this frame's mesh.

    This is the tracking path: while the mesh stays confident the detector
    never runs again, which is where most of the pipeline's speed comes from.
    Rotation uses the outer eye corners, the landmark equivalent of the two
    BlazeFace eye keypoints.
    """
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2
    start = points[LEFT_EYE_CORNER]
    end = points[RIGHT_EYE_CORNER]
    angle = math.atan2(end[1] - start[1], end[0] - start[0])
    return _square_rect(cx, cy, max(xs) - min(xs), max(ys) - min(ys), angle)


def _square_rect(cx, cy, w, h, angle):
    """Scale by ROI_SCALE and square off on the long side."""
    side = max(w, h) * ROI_SCALE
    return (cx, cy, side, side, angle)


def project_landmarks(raw, rect, input_size=LANDMARK_INPUT_SIZE):
    """Landmark model output to frame pixels.

    `raw` is the flat 1404-value tensor: 468 points of (x, y, z) in crop
    pixels. The crop was a rotated square, so undoing it means normalising to
    the crop, centring, rotating by the crop's angle, and translating to the
    crop's centre in the frame. Z is dropped -- nothing downstream uses depth.
    """
    cx, cy, w, h, angle = rect
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    points = []
    for i in range(NUM_LANDMARKS):
        # float() rather than leaving these as whatever the runtime handed
        # back: OpenVINO returns numpy float32, which json.dumps refuses, and
        # the failure would land in encode_measurement several layers away
        # from its cause.
        x = float(raw[i * 3]) / input_size - 0.5
        y = float(raw[i * 3 + 1]) / input_size - 0.5
        px, py = x * w, y * h
        points.append((cx + px * cos_a - py * sin_a,
                       cy + px * sin_a + py * cos_a))
    return points


# --- wire protocol --------------------------------------------------------
def _line(obj):
    return json.dumps(obj, separators=(",", ":"), allow_nan=False)


def encode_ready(backend, device, fps):
    return _line({"ready": True, "backend": backend, "device": device, "fps": fps})


def encode_measurement(t, gap, face):
    obj = {"t": round(float(t), 2), "face": round(float(face), 2)}
    if gap is not None:
        obj["gap"] = round(float(gap), 2)
    return _line(obj)


def encode_error(code, detail):
    return _line({"error": code, "detail": " ".join(str(detail).split())})


def should_redetect(have_mesh, presence=None, threshold=LANDMARK_MIN_PRESENCE):
    """Whether BlazeFace must run before the landmark model this frame.

    MediaPipe re-runs detection only when tracking is lost, and the landmark
    model reports that itself through its presence score -- there is no frame
    counter to tune. Detection is the expensive half, so on a face that stays
    in frame it effectively runs once per session.
    """
    if not have_mesh:
        return True
    return presence is None or presence < threshold


# Defaults carried over from the web app, unchanged. They are meaningful
# without calibration because the distance compensation below normalises
# every measurement to a fixed reference face size: a gap is reported
# relative to the user's own nose-to-chin distance in the same frame, so
# seating distance, camera resolution and field of view all divide out.
# That is why this pipeline has no calibration step and the dlib one did.
DEFAULT_THRESHOLD = 5.0
DEFAULT_DISTANCE_REF = 100
