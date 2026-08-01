"""Pure helpers for the MouthGuard detector. No I/O, no dlib, no OpenCV."""

import json
import math
import os

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


def _line(obj):
    return json.dumps(obj, separators=(",", ":"), allow_nan=False)


def encode_ready(backend, device, fps):
    return _line({"ready": True, "backend": backend, "device": device, "fps": fps})


def encode_measurement(t, gap, face):
    obj = {"t": round(t, 2), "face": round(face, 2)}
    if gap is not None:
        obj["gap"] = round(gap, 2)
    return _line(obj)


def encode_error(code, detail):
    return _line({"error": code, "detail": " ".join(str(detail).split())})


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


# Derived empirically — see CALIBRATION.md. These are dlib-scale values,
# measured against the full-resolution HOG detector and 68-point predictor,
# and bear no relation to the web app's MediaPipe-scale threshold of 5 and
# distance-compensation reference of 100px. Do not "round trip" a value
# between the two apps; they are different measurement pipelines on
# different coordinate scales.
DEFAULT_THRESHOLD = 3.5
DEFAULT_DISTANCE_REF = 71
