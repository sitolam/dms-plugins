"""Unit tests for tools/calibrate.py's stream-parsing logic.

These feed canned JSON lines straight into collect_measurements()/summarize()
rather than spawning detector.py or calibrate.py as subprocesses — the
classification and truncation-detection logic is pure and does not need a
process (or a camera) to exercise it.
"""

from mouthguard_core import encode_error, encode_measurement, encode_ready
from tools.calibrate import collect_measurements, summarize


def test_ready_handshake_is_ignored_but_reported_via_callback():
    seen = []
    lines = [
        encode_ready("dlib", "/dev/video0", 10),
        encode_measurement(5.0, 3.0, 118.0),
    ]
    result = collect_measurements(lines, secs=5.0, on_ready=seen.append)

    assert len(seen) == 1
    assert seen[0]["ready"] is True
    # The handshake line itself never becomes a sample.
    assert result["gaps"] == [3.0]
    assert result["rows"] == [(5.0, 3.0, 118.0)]


def test_measurement_with_gap_is_collected():
    lines = [encode_measurement(1.0, 4.5, 120.0)]
    result = collect_measurements(lines, secs=100.0)

    assert result["gaps"] == [4.5]
    assert result["faces"] == [120.0]
    assert result["rows"] == [(1.0, 4.5, 120.0)]


def test_no_face_line_is_not_counted_as_a_zero_gap():
    # encode_measurement(..., gap=None, ...) omits "gap" entirely, matching
    # what detector.py emits when should_redetect finds no face. A gap of
    # zero would misread as a firmly closed mouth, so this must never be
    # added to gaps/faces/rows.
    lines = [
        encode_measurement(1.0, None, 0.0),
        encode_measurement(2.0, 3.5, 118.0),
    ]
    result = collect_measurements(lines, secs=2.0)

    assert result["gaps"] == [3.5]
    assert result["faces"] == [118.0]
    assert result["rows"] == [(2.0, 3.5, 118.0)]
    assert result["reached_duration"] is True


def test_error_object_is_surfaced_and_stops_collection():
    lines = [encode_error("camera_busy", "/dev/video0: busy")]
    result = collect_measurements(lines, secs=20.0)

    assert result["error"] == {"error": "camera_busy", "detail": "/dev/video0: busy"}
    assert result["gaps"] == []
    assert result["reached_duration"] is False

    exit_code, out_lines, err_lines, rows = summarize("closed-near", 20.0, result)
    assert exit_code == 1
    assert rows is None
    assert out_lines == []
    assert any("camera_busy" in line for line in err_lines)


def test_stream_ending_early_is_a_truncation_not_a_valid_short_sample():
    # Regression test for the silent-truncation bug: the detector stream
    # ends (process died, EOF on stdout) after two seconds of a requested
    # twenty, having emitted three genuine samples along the way. A silent
    # "success" here is exactly how bad numbers reach CALIBRATION.md and
    # then the QML daemon while looking like a normal calibration run.
    lines = [
        encode_measurement(0.5, 3.0, 118.0),
        encode_measurement(1.0, 3.1, 118.5),
        encode_measurement(1.5, 3.2, 118.2),
    ]
    result = collect_measurements(lines, secs=20.0)

    assert result["reached_duration"] is False
    assert result["last_t"] == 1.5
    assert result["gaps"] == [3.0, 3.1, 3.2]

    exit_code, out_lines, err_lines, rows = summarize("closed-near", 20.0, result)

    # The samples were real, but summarize() must still refuse to present
    # them as a valid, complete recording.
    assert exit_code != 0
    assert rows is None
    assert out_lines == []
    combined_stderr = " ".join(err_lines).upper()
    assert "TRUNCAT" in combined_stderr
    assert "20.00" in " ".join(err_lines)
    assert "1.50" in " ".join(err_lines)


def test_reaching_the_requested_duration_produces_valid_output():
    lines = [
        encode_measurement(5.0, 3.0, 118.0),
        encode_measurement(10.0, 3.2, 118.5),
    ]
    result = collect_measurements(lines, secs=10.0)
    assert result["reached_duration"] is True

    exit_code, out_lines, err_lines, rows = summarize("closed-near", 10.0, result)

    assert exit_code == 0
    assert err_lines == []
    assert rows == [(5.0, 3.0, 118.0), (10.0, 3.2, 118.5)]
    assert len(out_lines) == 1
    assert "closed-near" in out_lines[0]
    assert "n=2" in out_lines[0]


def test_full_duration_with_zero_faces_is_reported_distinctly_from_truncation():
    # The stream runs the whole requested window but never sees a face —
    # a different failure mode from truncation, and should say so.
    lines = [
        encode_measurement(5.0, None, 0.0),
        encode_measurement(10.0, None, 0.0),
    ]
    result = collect_measurements(lines, secs=10.0)
    assert result["reached_duration"] is True
    assert result["gaps"] == []

    exit_code, out_lines, err_lines, rows = summarize("closed-near", 10.0, result)
    assert exit_code == 1
    assert rows is None
    assert err_lines == ["no face measured"]
