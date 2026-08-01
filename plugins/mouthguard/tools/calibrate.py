#!/usr/bin/env python3
# tools/calibrate.py
"""Record lip gap statistics for a labelled pose, to derive plugin defaults.

Usage:  python3 tools/calibrate.py <label> <seconds> [device] [--device DEVICE]

Prints median/p05/p95 of gap and face height, and appends raw rows to
calibration-<label>.csv.

The camera device defaults to /dev/video0, matching detector.py's own
default. It can be overridden two ways — pick whichever reads better in a
given invocation:

    python3 tools/calibrate.py closed-near 20 /dev/video2
    python3 tools/calibrate.py closed-near 20 --device /dev/video2

If both are given, --device wins. This exists so a machine with more than
one camera can be pointed at the right one, and so this script's own error
handling can be exercised against a path that is guaranteed not to be a
camera (e.g. --device /dev/null or --device /nonexistent) without ever
touching real hardware.
"""

import argparse
import json
import pathlib
import statistics
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

DEFAULT_DEVICE = "/dev/video0"


def parse_args(argv=None):
    p = argparse.ArgumentParser(prog="calibrate.py")
    p.add_argument("label", help="pose label, e.g. closed-near")
    p.add_argument("seconds", type=float, help="how long to record, in seconds")
    p.add_argument(
        "device", nargs="?", default=None,
        help=f"camera device path (default {DEFAULT_DEVICE})",
    )
    p.add_argument(
        "--device", dest="device_flag", default=None,
        help="camera device path; overrides the positional form if both are given",
    )
    return p.parse_args(argv)


def resolve_device(args):
    return args.device_flag or args.device or DEFAULT_DEVICE


def main(argv=None):
    args = parse_args(argv)
    label, secs, device = args.label, args.seconds, resolve_device(args)

    proc = subprocess.Popen(
        [sys.executable, str(ROOT / "detector.py"), "--device", device],
        stdout=subprocess.PIPE, stdin=subprocess.PIPE, text=True, cwd=ROOT,
    )
    gaps, faces = [], []
    out = open(ROOT / f"calibration-{label}.csv", "w")
    out.write("t,gap,face\n")
    try:
        for line in proc.stdout:
            d = json.loads(line)
            if "error" in d:
                print("detector error:", d, file=sys.stderr)
                return 1
            if "ready" in d:
                print(f"recording '{label}' for {secs}s on {device} — hold the pose")
                continue
            if "gap" not in d:
                continue
            gaps.append(d["gap"])
            faces.append(d["face"])
            out.write(f"{d['t']},{d['gap']},{d['face']}\n")
            if d["t"] >= secs:
                break
    finally:
        # The detector may already have exited on its own (e.g. it hit
        # camera_busy and returned before ever reading a command), in which
        # case its stdin read end is gone and writing "quit" raises
        # BrokenPipeError. That is an expected shutdown race, not a bug in
        # this script, so it must not surface as an uncaught traceback.
        if proc.stdin is not None and not proc.stdin.closed:
            try:
                proc.stdin.write("quit\n")
                proc.stdin.flush()
            except (BrokenPipeError, OSError):
                pass
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
        out.close()

    if not gaps:
        print("no face measured", file=sys.stderr)
        return 1

    q = statistics.quantiles(gaps, n=20)
    print(f"{label}: n={len(gaps)} gap median={statistics.median(gaps):.2f} "
          f"p05={q[0]:.2f} p95={q[18]:.2f} face median={statistics.median(faces):.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
