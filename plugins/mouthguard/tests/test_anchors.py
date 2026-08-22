import math

import pytest

from mouthguard_core import DETECTOR_INPUT_SIZE, decode_detection, sigmoid, ssd_anchors


def test_anchor_count_matches_the_model_output():
    # face_detection_short_range.tflite emits 896 rows; a mismatch here means
    # every detection would be decoded against the wrong anchor.
    assert len(ssd_anchors()) == 896


def test_anchors_split_between_the_two_grids():
    anchors = ssd_anchors()
    assert len(set(anchors[:512])) == 16 * 16   # stride 8, 2 per cell
    assert len(set(anchors[512:])) == 8 * 8     # stride 16, 6 per cell


def test_anchors_are_cell_centres_in_relative_coordinates():
    first = ssd_anchors()[0]
    assert first == pytest.approx((0.5 / 16, 0.5 / 16))
    assert all(0.0 < c < 1.0 for a in ssd_anchors() for c in a)


def test_sigmoid_clips_instead_of_overflowing():
    # MediaPipe caps score logits at +/-100 for exactly this reason; without
    # it a confident negative row raises OverflowError from math.exp.
    assert sigmoid(-1e9) == pytest.approx(0.0)
    assert sigmoid(1e9) == pytest.approx(1.0)
    assert sigmoid(0.0) == pytest.approx(0.5)


def test_decode_places_the_box_relative_to_its_anchor():
    anchor = (0.5, 0.5)
    regressor = [0.0] * 16
    regressor[2] = DETECTOR_INPUT_SIZE * 0.4   # width, in input pixels
    regressor[3] = DETECTOR_INPUT_SIZE * 0.2   # height
    (xmin, ymin, w, h), _ = decode_detection(regressor, anchor)
    assert (w, h) == pytest.approx((0.4, 0.2))
    assert (xmin, ymin) == pytest.approx((0.3, 0.4))  # centred on the anchor


def test_decode_offsets_are_in_input_pixels():
    anchor = (0.5, 0.5)
    regressor = [0.0] * 16
    regressor[0] = DETECTOR_INPUT_SIZE * 0.25  # centre shifted a quarter right
    (xmin, _, w, _), _ = decode_detection(regressor, anchor)
    assert xmin + w / 2 == pytest.approx(0.75)


def test_decode_returns_all_six_keypoints_anchored_the_same_way():
    anchor = (0.25, 0.75)
    regressor = [0.0] * 16
    _, keypoints = decode_detection(regressor, anchor)
    assert len(keypoints) == 6
    assert all(kp == pytest.approx(anchor) for kp in keypoints)
