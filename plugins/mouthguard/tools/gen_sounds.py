#!/usr/bin/env python3
# tools/gen_sounds.py
"""Render MouthGuard's five alert sounds to WAV.

The web app synthesises these with the Web Audio API, which has no QML
equivalent, so they ship as assets. Parameters mirror index.html:1056-1130
exactly; regenerate rather than hand-editing the WAVs.
"""

import math
import pathlib
import struct
import wave

RATE = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / "sounds"

# name -> list of (wave_type, freq_start, freq_end, amp, start_s, dur_s)
VOICES = {
    "soft":   [("sine", 660, 660, 1.00, 0.00, 0.45)],
    "chime":  [("sine", 880, 880, 0.60, 0.00, 1.20),
               ("sine", 1320, 1320, 0.30, 0.00, 1.20),
               ("sine", 1760, 1760, 0.15, 0.00, 1.20)],
    "double": [("sine", 800, 800, 1.00, 0.00, 0.15),
               ("sine", 800, 800, 1.00, 0.18, 0.15)],
    "buzz":   [("saw", 180, 180, 0.40, 0.00, 0.25)],
    "ping":   [("sine", 1400, 900, 0.80, 0.00, 0.20)],
}


def osc(wave_type, phase):
    if wave_type == "sine":
        return math.sin(phase)
    # Sawtooth over a 2*pi phase, matching Web Audio's 'sawtooth'.
    return 2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0


def render(voices):
    total = max(s + d for _, _, _, _, s, d in voices)
    n = int(RATE * (total + 0.02))
    buf = [0.0] * n

    for wave_type, f0, f1, amp, start, dur in voices:
        phase = 0.0
        i0 = int(start * RATE)
        for i in range(int(dur * RATE)):
            if i0 + i >= n:
                break
            frac = i / (dur * RATE)
            freq = f0 * ((f1 / f0) ** frac) if f1 != f0 else f0
            # exponentialRampToValueAtTime(0.001, t + dur)
            env = amp * ((0.001 / amp) ** frac)
            # 10ms attack, matching the linearRamp the double beep uses. Applied
            # to every voice: it removes the click a hard start would otherwise
            # produce, and is inaudible on the rest.
            env *= min(1.0, i / (0.01 * RATE))
            buf[i0 + i] += env * osc(wave_type, phase)
            phase += 2 * math.pi * freq / RATE

    peak = max(abs(v) for v in buf) or 1.0
    return [int(max(-1.0, min(1.0, v / peak)) * 32767) for v in buf]


def main():
    OUT.mkdir(exist_ok=True)
    for name, voices in VOICES.items():
        samples = render(voices)
        path = OUT / f"{name}.wav"
        with wave.open(str(path), "w") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", s) for s in samples))
        print(f"wrote {path} ({len(samples) / RATE:.2f}s)")


if __name__ == "__main__":
    main()
