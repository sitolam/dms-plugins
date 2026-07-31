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
