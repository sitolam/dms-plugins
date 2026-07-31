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
