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
