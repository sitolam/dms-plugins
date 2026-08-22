import pytest

from mouthguard_core import DEVICE_PREFERENCE, order_devices, pick_device, should_redetect


# --- when the face detector has to run ------------------------------------
def test_must_detect_before_there_is_a_mesh():
    assert should_redetect(have_mesh=False) is True


def test_tracks_on_from_a_confident_mesh():
    # The whole speed argument for this pipeline: with a face in frame the
    # detector effectively runs once per session.
    assert should_redetect(have_mesh=True, presence=0.9) is False


def test_redetects_when_the_mesh_loses_confidence():
    assert should_redetect(have_mesh=True, presence=0.1) is True


def test_missing_presence_forces_detection():
    assert should_redetect(have_mesh=True, presence=None) is True


# --- inference device choice ----------------------------------------------
def test_prefers_the_npu_then_the_gpu():
    assert pick_device(["CPU", "GPU", "NPU"]) == "NPU"
    assert pick_device(["CPU", "GPU"]) == "GPU"
    assert pick_device(["CPU"]) == "CPU"


def test_matches_enumerated_sub_devices_by_family():
    assert pick_device(["CPU", "GPU.0", "GPU.1"]) == "GPU.0"


def test_cpu_is_the_answer_when_nothing_is_available():
    # OpenVINO always has a CPU plugin, so naming it beats refusing to run.
    assert pick_device([]) == "CPU"


def test_order_keeps_unknown_devices_as_a_last_resort():
    ordered = order_devices(["MYRIAD", "CPU", "NPU"])
    assert ordered == ["NPU", "CPU", "MYRIAD"]


def test_preference_order_is_npu_gpu_cpu():
    assert DEVICE_PREFERENCE == ("NPU", "GPU", "CPU")
