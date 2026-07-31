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
