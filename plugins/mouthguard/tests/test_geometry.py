import math

import pytest

from mouthguard_core import (
    CHIN,
    LEFT_EYE_CORNER,
    LIP_BOTTOM,
    LIP_TOP,
    NOSE_TIP,
    NUM_LANDMARKS,
    RIGHT_EYE_CORNER,
    ROI_SCALE,
    compensate,
    face_height,
    lip_gap,
    project_landmarks,
    rect_from_detection,
    rect_from_landmarks,
)


def mesh(**overrides):
    """468 landmarks all at origin, with named indices overridden."""
    p = [(0.0, 0.0)] * NUM_LANDMARKS
    for idx, xy in overrides.items():
        p[int(idx[1:])] = xy
    return p


def test_lip_gap_is_the_vertical_lip_separation():
    p = mesh(**{f"i{LIP_TOP}": (100.0, 200.0), f"i{LIP_BOTTOM}": (100.0, 209.0)})
    assert lip_gap(p) == pytest.approx(9.0)


def test_lip_gap_ignores_horizontal_offset():
    # The web app measures the raw Y delta, and the threshold is set against
    # that. Face Mesh returns an upright mesh, so lip separation is vertical
    # by construction and a sideways component is noise, not signal.
    p = mesh(**{f"i{LIP_TOP}": (100.0, 200.0), f"i{LIP_BOTTOM}": (140.0, 209.0)})
    assert lip_gap(p) == pytest.approx(9.0)


def test_face_height_is_nose_to_chin():
    p = mesh(**{f"i{NOSE_TIP}": (50.0, 100.0), f"i{CHIN}": (50.0, 220.0)})
    assert face_height(p) == pytest.approx(120.0)


def test_face_height_uses_hypot_so_a_tilted_head_still_measures_full_length():
    d = 120.0 / math.sqrt(2)
    p = mesh(**{f"i{NOSE_TIP}": (50.0, 100.0), f"i{CHIN}": (50.0 + d, 100.0 + d)})
    assert face_height(p) == pytest.approx(120.0)


def test_compensate_normalises_to_the_reference_face():
    # Half the reference face size means twice the distance, so the same
    # measured gap counts double.
    assert compensate(3.0, 50.0, 100) == pytest.approx(6.0)


def test_compensate_passes_the_gap_through_when_no_face_was_measured():
    # Guards against dividing by a face height of zero on a frame with no face.
    assert compensate(3.0, 0.0, 100) == pytest.approx(3.0)


# --- region of interest ---------------------------------------------------
def test_detection_rect_is_square_and_scaled():
    box = (0.25, 0.25, 0.5, 0.25)  # 320x120 px in a 640x480 frame
    eyes = [(0.4, 0.3), (0.6, 0.3)]
    cx, cy, w, h, angle = rect_from_detection(box, eyes, 640, 480)
    assert (cx, cy) == pytest.approx((320.0, 180.0))
    assert w == h == pytest.approx(320.0 * ROI_SCALE)
    assert angle == pytest.approx(0.0)


def test_detection_rect_rotates_with_the_eye_line():
    # Eyes 45 degrees apart in a square frame: the crop must follow, or the
    # landmark model sees a tilted face it was not trained on.
    box = (0.25, 0.25, 0.5, 0.5)
    eyes = [(0.4, 0.4), (0.6, 0.6)]
    *_, angle = rect_from_detection(box, eyes, 480, 480)
    assert math.degrees(angle) == pytest.approx(45.0)


def test_landmark_rect_covers_the_mesh_and_follows_its_rotation():
    p = mesh(**{
        "i0": (100.0, 100.0), "i1": (300.0, 200.0),
        f"i{LEFT_EYE_CORNER}": (150.0, 150.0),
        f"i{RIGHT_EYE_CORNER}": (250.0, 150.0),
    })
    # Every other landmark sits at the origin, so the bounding box runs from
    # (0, 0) to (300, 200).
    cx, cy, w, h, angle = rect_from_landmarks(p, 640, 480)
    assert (cx, cy) == pytest.approx((150.0, 100.0))
    assert w == h == pytest.approx(300.0 * ROI_SCALE)
    assert angle == pytest.approx(0.0)


def test_project_landmarks_inverts_an_unrotated_crop():
    raw = [0.0] * (NUM_LANDMARKS * 3)
    raw[0], raw[1] = 96.0, 96.0        # centre of a 192px crop
    raw[3], raw[4] = 192.0, 0.0        # top-right corner
    rect = (300.0, 200.0, 100.0, 100.0, 0.0)
    points = project_landmarks(raw, rect)
    assert points[0] == pytest.approx((300.0, 200.0))
    assert points[1] == pytest.approx((350.0, 150.0))


def test_project_landmarks_undoes_the_crop_rotation():
    raw = [0.0] * (NUM_LANDMARKS * 3)
    raw[0], raw[1] = 192.0, 96.0       # right edge, vertically centred
    rect = (300.0, 200.0, 100.0, 100.0, math.pi / 2)
    x, y = project_landmarks(raw, rect)[0]
    # A quarter turn sends the crop's +x axis to the frame's +y axis.
    assert (x, y) == pytest.approx((300.0, 250.0))
