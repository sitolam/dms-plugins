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
    resolve_model_path,
    should_redetect,
)


def emit(line):
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def positive_scale(raw):
    """argparse type= validator: --scale must be > 0.

    A zero scale divides by zero when converting the detector's rectangle
    back to full-resolution pixels; a negative scale silently produces
    garbage coordinates instead of failing. Reject both here, before the
    camera is ever opened, rather than discovering it mid-loop with the
    device held.
    """
    value = float(raw)
    if value <= 0:
        raise argparse.ArgumentTypeError(
            f"--scale must be > 0, got {raw!r}")
    return value


def parse_args(argv=None):
    p = argparse.ArgumentParser(prog="detector.py")
    p.add_argument("--device", default="/dev/video0")
    p.add_argument("--fps", type=int, default=10)
    p.add_argument("--detect-interval", type=int, default=5)
    p.add_argument("--width", type=int, default=640)
    p.add_argument("--height", type=int, default=480)
    p.add_argument(
        "--scale", type=positive_scale, default=0.5,
        help="downscale factor for the HOG face detector only, in (0, 1]; "
             "the 68-point predictor always runs at full resolution, so "
             "this does not affect measurement precision")
    p.add_argument("--self-test", action="store_true")
    return p.parse_args(argv)


def self_test(args):
    """Emit a valid stream without touching the camera."""
    emit(encode_ready("dlib", args.device, args.fps))
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
    import dlib

    try:
        model_path = resolve_model_path()
    except ModelNotFound as exc:
        emit(encode_error("model_missing", exc))
        return 2

    detector = dlib.get_frontal_face_detector()
    predictor = dlib.shape_predictor(model_path)

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

    emit(encode_ready("dlib", args.device, args.fps))

    paused = False
    frame_index = 0
    rect = None
    points = None
    t0 = time.monotonic()
    period = 1.0 / max(1, args.fps)

    try:
        # inv_scale maps the HOG detector's rectangle, found on the
        # downscaled frame, up to full-resolution pixel coordinates. It is
        # no longer used to scale landmarks: the predictor now runs
        # directly on the full-resolution frame, so its output is already
        # in the canonical space. Computed inside the try block, not
        # before it, so a degenerate --scale can never leave the camera
        # handle open on the way out; parse_args already rejects
        # --scale <= 0, so this is defence in depth rather than the
        # primary guard.
        inv_scale = 1.0 / args.scale

        while True:
            cmd = read_command()
            if cmd == "quit":
                break
            if cmd == "pause" and not paused:
                paused = True
                if cap is not None:
                    cap.release()
                    cap = None
                rect = None
                points = None
            elif cmd == "resume" and paused:
                cap = open_capture()
                if cap is None:
                    emit(encode_error(
                        "camera_busy", f"{args.device}: cannot reopen, staying paused"))
                    # Stay paused and keep the process alive: exiting here
                    # would discard the resident dlib model over a momentary
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

            # Grayscale the full frame once. The HOG detector still runs on
            # a downscaled copy of it -- detection cost scales with area,
            # and that is the expensive step -- but the 68-point predictor
            # runs against the full-resolution grayscale image below, so
            # landmarks are never quantised by a downscale-then-upscale
            # round trip. That round trip used to halve measurement
            # precision at the default --scale 0.5: the predictor returns
            # integer pixel coordinates, and a barely-parted mouth a few
            # pixels wide cannot afford to lose half its resolution.
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            small_gray = cv2.resize(gray, None, fx=args.scale, fy=args.scale)

            if should_redetect(frame_index, rect is not None, points, rect,
                               args.detect_interval):
                faces = detector(small_gray, 0)
                if faces:
                    # Largest face wins; multi-face tracking is out of scope.
                    face = max(faces, key=lambda f: f.width() * f.height())
                    # Scale the detector's rect up to full-resolution
                    # coordinates immediately on detection. Full resolution
                    # is the one canonical space for the cached rect from
                    # here on -- should_redetect compares it against
                    # `points` below, which are also full-resolution, and
                    # the two must never drift into different spaces.
                    rect = (
                        round(face.left() * inv_scale),
                        round(face.top() * inv_scale),
                        round(face.right() * inv_scale),
                        round(face.bottom() * inv_scale),
                    )
                else:
                    rect = None
                    points = None

            if rect is None:
                emit(encode_measurement(time.monotonic() - t0, None, 0.0))
            else:
                shape = predictor(gray, dlib.rectangle(*rect))
                points = [(shape.part(i).x, shape.part(i).y) for i in range(68)]
                # Landmarks come back in full-resolution pixels already --
                # the predictor ran against the full-resolution image, not
                # the downscaled one -- so no further scaling is applied.
                emit(encode_measurement(
                    time.monotonic() - t0, lip_gap(points), face_height(points)))

            frame_index += 1
            time.sleep(period)
    except KeyboardInterrupt:
        pass
    finally:
        if cap is not None:
            cap.release()

    return 0


if __name__ == "__main__":
    sys.exit(main())
