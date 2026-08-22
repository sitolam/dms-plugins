import pytest

from mouthguard_core import DETECTOR_MODEL, LANDMARK_MODEL, ModelNotFound, resolve_model_dir


def models_in(directory, *names):
    directory.mkdir(parents=True, exist_ok=True)
    for name in names or (DETECTOR_MODEL, LANDMARK_MODEL):
        (directory / name).write_bytes(b"x")
    return str(directory)


def test_env_var_wins(tmp_path):
    wanted = models_in(tmp_path / "wanted")
    other = models_in(tmp_path / "other")
    got = resolve_model_dir(env={"MOUTHGUARD_MODEL_DIR": wanted}, candidates=[other])
    assert got == wanted


def test_falls_through_to_candidates_when_env_unset(tmp_path):
    found = models_in(tmp_path / "found")
    assert resolve_model_dir(env={}, candidates=[found]) == found


def test_skips_candidates_that_do_not_exist(tmp_path):
    found = models_in(tmp_path / "found")
    assert resolve_model_dir(env={}, candidates=["/nonexistent", found]) == found


def test_skips_a_candidate_holding_only_one_of_the_two_models(tmp_path):
    # A half-populated directory is the more dangerous failure: it would let
    # startup get as far as loading one model and fail on the other.
    half = models_in(tmp_path / "half", LANDMARK_MODEL)
    whole = models_in(tmp_path / "whole")
    assert resolve_model_dir(env={}, candidates=[half, whole]) == whole


def test_env_var_pointing_at_a_directory_without_models_is_an_error(tmp_path):
    # Explicit user intent that cannot be honoured must fail loudly rather
    # than silently falling back to some other copy of the models.
    fallback = models_in(tmp_path / "fallback")
    with pytest.raises(ModelNotFound):
        resolve_model_dir(env={"MOUTHGUARD_MODEL_DIR": str(tmp_path / "empty")},
                          candidates=[fallback])


def test_raises_when_nothing_found():
    with pytest.raises(ModelNotFound):
        resolve_model_dir(env={}, candidates=["/nonexistent"])
