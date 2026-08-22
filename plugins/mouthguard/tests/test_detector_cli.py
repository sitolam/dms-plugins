import json
import subprocess
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent


def run_self_test():
    return subprocess.run(
        [sys.executable, str(ROOT / "detector.py"), "--self-test"],
        capture_output=True, text=True, timeout=60, cwd=ROOT,
    )


def test_self_test_exits_cleanly():
    assert run_self_test().returncode == 0


def test_first_line_is_the_ready_handshake():
    lines = run_self_test().stdout.strip().splitlines()
    first = json.loads(lines[0])
    assert first["ready"] is True
    assert first["backend"] == "mediapipe"


def test_every_line_is_valid_standalone_json():
    # QML splits this stream on newlines, so a line that is not self-contained
    # JSON breaks the parser downstream.
    for line in run_self_test().stdout.strip().splitlines():
        json.loads(line)


def test_emits_measurements_after_the_handshake():
    lines = run_self_test().stdout.strip().splitlines()
    measurements = [json.loads(x) for x in lines[1:]]
    assert len(measurements) == 3
    assert all("t" in m and "face" in m for m in measurements)
