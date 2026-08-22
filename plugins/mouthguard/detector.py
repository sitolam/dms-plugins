#!/usr/bin/env python3
"""MouthGuard detector: webcam frames in, lip-gap measurements out.

This process holds no policy. It does not know what a threshold is, how long a
detection window lasts, or when to alert. It measures and reports; QML decides.
That split is what lets settings changes apply without restarting the camera.
"""

import argparse
import sys
import time

from mouthguard_core import (
    ModelNotFound,
    encode_error,
    encode_measurement,
    encode_ready,
    face_height,
    lip_gap,
    resolve_model_dir,
)


def emit(line):
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def parse_args(argv=None):
    p = argparse.ArgumentParser(prog="detector.py")
    p.add_argument("--device", default="/dev/video0")
    p.add_argument("--fps", type=int, default=10)
    p.add_argument(
        "--inference-device", default=None,
        help="OpenVINO device to run the models on (NPU, GPU, CPU). Default "
             "picks the first available in that order.")
    p.add_argument(
        "--width", type=int, default=640,
        help="capture width in pixels; unlike the previous dlib pipeline "
             "this does not set a floor on usable seating distance -- the "
             "detector letterboxes every frame down to 128x128 regardless")
    p.add_argument("--height", type=int, default=480, help="capture height in pixels")
    p.add_argument("--self-test", action="store_true")
    return p.parse_args(argv)


def self_test(args):
    """Emit a valid stream without touching the camera or a model."""
    emit(encode_ready("mediapipe", args.device, args.fps))
    t0 = time.monotonic()
    for gap in (3.0, 9.5, None):
        emit(encode_measurement(time.monotonic() - t0, gap, 0.0 if gap is None else 118.0))
    return 0


def read_command():
    """Non-blocking read of one stdin line. Returns None when nothing waits."""
    import select

    if not select.select([sys.stdin], [], [], 0)[0]:
        return None
    line = sys.stdin.readline()
    if not line:
        return "quit"
    return line.strip().lower()


def main(argv=None):
    args = parse_args(argv)
    if args.self_test:
        return self_test(args)

    import cv2

    from mouthguard_mesh import FaceMesh

    try:
        model_dir = resolve_model_dir()
    except ModelNotFound as exc:
        emit(encode_error("model_missing", exc))
        return 2

    try:
        mesh = FaceMesh(model_dir, args.inference_device)
    except Exception as exc:  # noqa: BLE001 - any runtime failure is fatal here
        emit(encode_error("inference_failed", exc))
        return 4

    def open_capture():
        cap = cv2.VideoCapture(args.device, cv2.CAP_V4L2)
        if not cap.isOpened():
            return None
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
        return cap

    cap = open_capture()
    if cap is None:
        emit(encode_error("camera_busy", f"{args.device}: cannot open device"))
        return 3

    emit(encode_ready("mediapipe/" + mesh.device, args.device, args.fps))

    paused = False
    t0 = time.monotonic()
    period = 1.0 / max(1, args.fps)

    try:
        while True:
            cmd = read_command()
            if cmd == "quit":
                break
            if cmd == "pause" and not paused:
                paused = True
                if cap is not None:
                    cap.release()
                    cap = None
                mesh.reset()
            elif cmd == "resume" and paused:
                cap = open_capture()
                if cap is None:
                    emit(encode_error(
                        "camera_busy", f"{args.device}: cannot reopen, staying paused"))
                    # Stay paused and keep the process alive: exiting here
                    # would discard the compiled models over a momentary
                    # device-busy blip, which is exactly the cost pause/
                    # resume exists to avoid. A later "resume" can retry.
                else:
                    paused = False

            if paused:
                time.sleep(period)
                continue

            ok, frame = cap.read()
            if not ok:
                time.sleep(period)
                continue

            # Face Mesh runs its own two-stage pipeline internally: BlazeFace
            # only when tracking is lost, the 468-point landmark model every
            # frame. Both are roughly a millisecond, so unlike the dlib
            # pipeline this needs no frame-skipping of the detection stage.
            points = mesh(frame)
            if points is None:
                emit(encode_measurement(time.monotonic() - t0, None, 0.0))
            else:
                emit(encode_measurement(
                    time.monotonic() - t0, lip_gap(points), face_height(points)))

            time.sleep(period)
    except KeyboardInterrupt:
        pass
    finally:
        if cap is not None:
            cap.release()

    return 0


if __name__ == "__main__":
    sys.exit(main())
