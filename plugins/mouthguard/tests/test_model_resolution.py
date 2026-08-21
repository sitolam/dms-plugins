import pytest
from mouthguard_core import resolve_model_path, ModelNotFound

NAME = "shape_predictor_68_face_landmarks.dat"


def test_env_var_wins(tmp_path):
    m = tmp_path / NAME
    m.write_bytes(b"x")
    other = tmp_path / "other.dat"
    other.write_bytes(b"x")
    got = resolve_model_path(env={"MOUTHGUARD_MODEL": str(m)}, candidates=[str(other)])
    assert got == str(m)


def test_falls_through_to_candidates_when_env_unset(tmp_path):
    m = tmp_path / NAME
    m.write_bytes(b"x")
    got = resolve_model_path(env={}, candidates=[str(m)])
    assert got == str(m)


def test_skips_candidates_that_do_not_exist(tmp_path):
    m = tmp_path / NAME
    m.write_bytes(b"x")
    got = resolve_model_path(env={}, candidates=["/nonexistent/a.dat", str(m)])
    assert got == str(m)


def test_env_var_pointing_at_missing_file_is_an_error(tmp_path):
    # Explicit user intent that cannot be honoured must fail loudly rather than
    # silently falling back to some other model.
    with pytest.raises(ModelNotFound):
        resolve_model_path(env={"MOUTHGUARD_MODEL": "/nope/x.dat"}, candidates=[])


def test_raises_when_nothing_found():
    with pytest.raises(ModelNotFound):
        resolve_model_path(env={}, candidates=["/nonexistent/a.dat"])
