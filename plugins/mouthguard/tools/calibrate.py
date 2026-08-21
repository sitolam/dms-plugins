#!/usr/bin/env python3
# tools/calibrate.py
"""Record lip gap statistics for a labelled pose, to derive plugin defaults.

Usage:  python3 tools/calibrate.py <label> <seconds> [device] [--device DEVICE]

Prints median/p05/p95 of gap and face height, and — only for a complete,
untruncated recording — writes the raw rows to calibration-<label>.csv.

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


def collect_measurements(lines, secs, on_ready=None):
    """Consume detector.py's JSON-lines stream and classify each line.

    Pure: `lines` is any iterable of raw JSON-line strings — a live
    subprocess's stdout, or a canned list in tests. No I/O happens here,
    which is what makes the classification and truncation-detection logic
    testable without ever spawning a process.

    Recognises the three line shapes mouthguard_core.encode_* produces:
      - {"error": ..., "detail": ...}        terminal; stops immediately.
      - {"ready": True, ...}                 the handshake; ignored except
                                              for the optional on_ready
                                              callback.
      - {"t": ..., "face": ..., ["gap": ...]}  a measurement. Only counted
        into gaps/faces/rows when "gap" is present — a no-face frame omits
        "gap" entirely (see encode_measurement) and must never be treated
        as a gap of zero, which would misread as a firmly closed mouth.

    Stops as soon as a measurement's "t" reaches `secs`
    (reached_duration=True), or when `lines` is exhausted first
    (reached_duration=False — the detector stream ended before the
    requested recording time elapsed, e.g. because the process died
    mid-recording). The caller must treat a reached_duration=False result
    as unusable, not as a shorter-but-valid sample: silently accepting it
    is how a two-second capture of a requested twenty ends up silently
    written into CALIBRATION.md as if it were the real thing.
    """
    gaps, faces, rows = [], [], []
    last_t = None
    for line in lines:
        d = json.loads(line)
        if "error" in d:
            return {
                "gaps": gaps, "faces": faces, "rows": rows,
                "last_t": last_t, "reached_duration": False, "error": d,
            }
        if "ready" in d:
            if on_ready is not None:
                on_ready(d)
            continue
        if "t" not in d:
            continue
        last_t = d["t"]
        if "gap" in d:
            gaps.append(d["gap"])
            faces.append(d["face"])
            rows.append((d["t"], d["gap"], d["face"]))
        if last_t >= secs:
            return {
                "gaps": gaps, "faces": faces, "rows": rows,
                "last_t": last_t, "reached_duration": True, "error": None,
            }
    return {
        "gaps": gaps, "faces": faces, "rows": rows,
        "last_t": last_t, "reached_duration": False, "error": None,
    }


def summarize(label, secs, result):
    """Turn a collect_measurements() result into a script outcome.

    Pure, like collect_measurements() — returns (exit_code, stdout_lines,
    stderr_lines, csv_rows). csv_rows is None whenever the run must not be
    trusted (detector error, truncated recording, or zero usable samples);
    main() only writes calibration-<label>.csv when csv_rows is not None,
    so a failed or incomplete run never leaves a CSV on disk that could
    later be mistaken for a complete one.

    Order of checks matters: an explicit detector error is reported first,
    then truncation (did the stream even run for the requested duration —
    a structural problem, checked before we ask what was in it), then
    "no face measured" (the stream ran the full duration but never saw a
    face). A truncated-with-zero-samples run is reported as truncated, not
    as "no face measured", since the missing duration is the actionable
    fact.
    """
    if result["error"] is not None:
        return 1, [], [f"detector error: {result['error']}"], None

    if not result["reached_duration"]:
        actual = result["last_t"] if result["last_t"] is not None else 0.0
        n = len(result["gaps"])
        return (
            1,
            [],
            [
                f"TRUNCATED RECORDING for '{label}': requested {secs:.2f}s, "
                f"the detector stream ended after {actual:.2f}s (n={n} "
                "sample(s) collected). These statistics would NOT be valid "
                "for a complete recording, so they are not being printed. "
                "Re-run this pose.",
            ],
            None,
        )

    if not result["gaps"]:
        return 1, [], ["no face measured"], None

    gaps, faces = result["gaps"], result["faces"]
    q = statistics.quantiles(gaps, n=20)
    line = (
        f"{label}: n={len(gaps)} gap median={statistics.median(gaps):.2f} "
        f"p05={q[0]:.2f} p95={q[18]:.2f} "
        f"face median={statistics.median(faces):.2f}"
    )
    return 0, [line], [], result["rows"]


def _shutdown(proc):
    """Ask the detector to quit, then reap it.

    Runs unconditionally after the stream is done being read, whether that
    ended cleanly, on an error, or on truncation. If the detector already
    exited on its own (e.g. camera_busy fired before it ever got to read a
    command), its stdin read end is gone: write()/flush() raise
    BrokenPipeError, which is caught below.

    Catching it around flush() is not sufficient on its own, though: the
    "quit\\n" bytes stay buffered in the TextIOWrapper, and CPython retries
    the flush during interpreter-shutdown finalization, outside any
    try/except, printing an uncatchable "Exception ignored while
    finalizing file ...: BrokenPipeError" to stderr. That retry is
    deterministic once the child has already exited, not merely a timing
    fluke. Explicitly closing stdin here (also guarded) discards the
    buffered write instead of leaving it for GC to retry.
    """
    if proc.stdin is not None and not proc.stdin.closed:
        try:
            proc.stdin.write("quit\n")
            proc.stdin.flush()
        except (BrokenPipeError, OSError):
            pass
        finally:
            try:
                proc.stdin.close()
            except (BrokenPipeError, OSError):
                pass
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


def main(argv=None):
    args = parse_args(argv)
    label, secs, device = args.label, args.seconds, resolve_device(args)

    proc = subprocess.Popen(
        [sys.executable, str(ROOT / "detector.py"), "--device", device],
        stdout=subprocess.PIPE, stdin=subprocess.PIPE, text=True, cwd=ROOT,
    )

    def announce_ready(_d):
        print(f"recording '{label}' for {secs}s on {device} — hold the pose")

    try:
        result = collect_measurements(proc.stdout, secs, on_ready=announce_ready)
    finally:
        _shutdown(proc)

    exit_code, out_lines, err_lines, rows = summarize(label, secs, result)
    for line in out_lines:
        print(line)
    for line in err_lines:
        print(line, file=sys.stderr)

    if rows is not None:
        with open(ROOT / f"calibration-{label}.csv", "w") as out:
            out.write("t,gap,face\n")
            for t, gap, face in rows:
                out.write(f"{t},{gap},{face}\n")

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
