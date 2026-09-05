#!/usr/bin/env python3
"""MouthGuard detector: webcam frames in, lip-gap measurements out.

This process holds no policy. It does not know what a threshold is, how long a
detection window lasts, or when to alert. It measures and reports; QML decides.
That split is what lets settings changes apply without restarting the camera.
"""

import argparse
import json
import subprocess
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
    p.add_argument(
        "--device", default="/dev/video0",
        help="camera. A /dev/videoN path (the default) is resolved to its "
             "PipeWire Video/Source node; anything else is taken as a "
             "PipeWire node name (pw-cli ls Node) directly -- see "
             "--capture-backend v4l2 for the raw path")
    p.add_argument(
        "--capture-backend", choices=("pipewire", "v4l2"), default="pipewire",
        help="pipewire (default) opens the camera through the same "
             "PipeWire Video/Source node gaze and browsers already read, "
             "via GStreamer's pipewiresrc, instead of a second exclusive "
             "V4L2 open competing with PipeWire's own -- see the yield/"
             "retry loop in main() for how MouthGuard steps aside for "
             "another PipeWire client instead of just winning the race. "
             "v4l2 is the old cv2.CAP_V4L2 path against --device directly, "
             "kept as a fallback for a cv2 build with no GStreamer "
             "support (falls back to it automatically) or for debugging "
             "a PipeWire-side problem.")
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

    def open_v4l2():
        cap = cv2.VideoCapture(args.device, cv2.CAP_V4L2)
        if not cap.isOpened():
            return None
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
        return cap

    def pipewire_target_for(device):
        """PipeWire node.name of the Video/Source node backing `device`.

        Unlike default *audio* sink/source, wireplumber sets no "default
        camera" metadata -- pipewiresrc left without a target (or path
        "unconnected") fails to negotiate at all ("stream error: target not
        found"), it does not fall back to picking one. So the V4L2 device
        node this was always configured with has to be resolved to its
        PipeWire node by hand. `pw-dump`'s object.path on a camera node is
        literally "v4l2:<device>" (confirmed against this machine's `pw-cli
        ls Node` output), which is the same identity gaze's own
        PipeWire-resolved "primary" camera is found by -- so this is
        matching against the same shared node gaze already reads, not a
        second guess at it.
        """
        try:
            out = subprocess.run(
                ["pw-dump"], capture_output=True, text=True, timeout=2, check=True)
            nodes = json.loads(out.stdout)
        except (OSError, subprocess.SubprocessError, json.JSONDecodeError) as exc:
            print(f"[pipewire] pw-dump failed, falling back to raw V4L2: {exc!r}",
                  file=sys.stderr, flush=True)
            return None
        want = f"v4l2:{device}"
        for obj in nodes:
            props = (obj.get("info") or {}).get("props") or {}
            if props.get("object.path") == want:
                return props.get("node.name")
        print(f"[pipewire] no node with object.path={want!r} among "
              f"{len(nodes)} objects, falling back to raw V4L2",
              file=sys.stderr, flush=True)
        return None

    def open_pipewire():
        """Open the camera's PipeWire Video/Source node.

        This UVC webcam's PipeWire node does NOT fan one device out to
        several simultaneous clients -- verified directly (a second
        pipewiresrc opened against the same target-object while this one
        was streaming got "error set output format: -16 (Device or
        resource busy)"), so this is not a fix for exclusivity on its own.
        What it would change, when it opens, is *whose* exclusivity fight
        MouthGuard is in: a second raw V4L2 open competes underneath
        PipeWire's own hold of the device, which can starve or wedge every
        PipeWire camera client -- gaze, a browser's video call -- at once,
        not just whichever one raced MouthGuard next; pipewiresrc instead
        makes MouthGuard one more PipeWire client in the same arbitration
        PipeWire already runs for gaze and everyone else.

        In practice, on this machine, this consistently fails to open (no
        stderr from cv2/GStreamer, cap.isOpened() just comes back false)
        when run as MouthGuard's actual detector process, despite an
        identical pipeline working fine run by hand in a login shell with
        matching XDG_RUNTIME_DIR/WAYLAND_DISPLAY/DBUS_SESSION_BUS_ADDRESS --
        cause not yet found. open_capture() falls back to open_v4l2() when
        this returns None, which is why the fix that actually matters here
        is the yield/hold loop in main() below: it works the same way
        (release, then genuinely stay off the device for YIELD_HOLD_S)
        whichever backend ends up capturing, so gaze/a video call still get
        a real window even while stuck on the V4L2 fallback. Revisit this
        docstring once the pipewiresrc failure is actually diagnosed --
        the pw-dump/pipeline failure prints below are what to go looking
        for in `journalctl --user -u dms.service | grep pipewire`.
        A "/dev/videoN" --device value is resolved to its PipeWire node
        first (see pipewire_target_for); anything else is assumed to
        already be a PipeWire node name and used as-is. drop=true/
        max-buffers=1 keeps the sink from queuing stale frames when a tick
        takes longer than the pipeline's own rate.
        """
        target = args.device
        if target.startswith("/dev/video"):
            target = pipewire_target_for(target)
            if target is None:
                return None
        pipeline = (
            f'pipewiresrc target-object="{target}" ! '
            f"video/x-raw,width={args.width},height={args.height} ! "
            "videoconvert ! video/x-raw,format=BGR ! "
            "appsink drop=true max-buffers=1 sync=false"
        )
        cap = cv2.VideoCapture(pipeline, cv2.CAP_GSTREAMER)
        if not cap.isOpened():
            print(f"[pipewire] pipewiresrc failed to open (target={target!r}), "
                  "falling back to raw V4L2", file=sys.stderr, flush=True)
            return None
        return cap

    def open_capture():
        if args.capture_backend == "pipewire":
            cap = open_pipewire()
            if cap is not None:
                return cap
            # No pipewiresrc plugin, or this cv2 build has no GStreamer
            # support at all (the python3 portable fallback path, on a
            # distro that packages a plain opencv4) -- fall through to the
            # old exclusive path rather than refusing to run.
        return open_v4l2()

    cap = open_capture()
    if cap is None:
        emit(encode_error("camera_busy", f"{args.device}: cannot open device"))
        return 3

    emit(encode_ready("mediapipe/" + mesh.device, args.device, args.fps))

    paused = False
    t0 = time.monotonic()
    period = 1.0 / max(1, args.fps)

    # Lowest-priority camera use: MouthGuard periodically drops its own
    # stream so a client that only tries once (gaze's face auth, most
    # video-call apps) gets a window to grab the slot the two of them
    # would otherwise just race for -- see open_pipewire()'s docstring for
    # why this loop, not PipeWire's own arbitration, is what actually
    # yields the camera on this hardware. YIELD_INTERVAL_S bounds how
    # long another app can be locked out behind an already-running
    # MouthGuard session; RETRY_INTERVAL_S bounds how long MouthGuard
    # waits, once it has lost the camera, before quietly checking whether
    # it is free again. "camera_yielded" (not "camera_busy") is the wire
    # signal for both cases below, so QML can tell "MouthGuard stepped
    # aside, still measuring when it gets a turn" apart from a fatal
    # camera_busy it should end the session over -- see
    # MouthGuardDaemon.qml's stdout handler.
    #
    # YIELD_HOLD_S matters more than it looks: the first cut of this loop
    # released and immediately tried to reopen, so the "window" for another
    # client was however long cap.release()/open_capture() itself took --
    # tens of milliseconds. gaze's face auth makes exactly one attempt, no
    # retry of its own (gazed's journal: one "Attempting to open... camera"
    # line per sudo prompt, then give up), so that was a lottery it lost
    # most of the time -- confirmed against gazed's own log going 3-for-6
    # across a session with MouthGuard continuously active. Sleeping the
    # whole hold instead of racing a reopen makes the window a real,
    # deterministic ~YIELD_HOLD_S rather than a coin flip on scheduling.
    YIELD_INTERVAL_S = 8.0
    YIELD_HOLD_S = 2.0
    RETRY_INTERVAL_S = 1.0
    last_yield = time.monotonic()
    lost = False

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
                    last_yield = time.monotonic()

            if paused:
                time.sleep(period)
                continue

            now = time.monotonic()
            if cap is None:
                # Lost the camera (see below) -- keep checking whether it
                # freed up, at the slower retry cadence rather than the
                # measurement fps, so a client that is still using it
                # is not hammered with open attempts.
                cap = open_capture()
                if cap is None:
                    time.sleep(RETRY_INTERVAL_S)
                    continue
                lost = False
                last_yield = now
            elif now - last_yield >= YIELD_INTERVAL_S:
                cap.release()
                cap = None
                mesh.reset()
                last_yield = now
                lost = True
                emit(encode_error(
                    "camera_yielded",
                    f"{args.device}: yielding for {YIELD_HOLD_S:.0f}s"))
                time.sleep(YIELD_HOLD_S)
                continue

            ok, frame = cap.read()
            if not ok:
                # The other common shape of losing the camera: a client
                # that grabbed it mid-stream rather than during this
                # loop's own yield window above. Release cleanly instead
                # of spinning read() against a capture object that is
                # never going to succeed again on its own, and fall into
                # the same lost-camera retry path the yield branch above uses.
                cap.release()
                cap = None
                mesh.reset()
                if not lost:
                    emit(encode_error(
                        "camera_yielded", f"{args.device}: lost, retrying"))
                    lost = True
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
