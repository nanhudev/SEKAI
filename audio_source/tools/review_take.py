#!/usr/bin/env python3
"""Read a sword/pass take against its own beat map, so "listen to the whole thing"
is a set of numbers instead of a memory of which second was which.

WHAT THIS IS FOR. A pass over the audio line produces a video and a recorded bus.
Reviewing it by ear is one take per listen and leaves nothing behind; reviewing it
by eye alone cannot hear a miss. This reads `beats.tsv` (written by
`godot/tools/sword_audio_pass.gd`) and reports, for each beat, the slice of the
RECORDED WAV that belongs to it - level, how much of the slice is actually audible,
spectral centre, band split, and (for stereo) whether the sound is off to one side.

The last two columns are the ones that answer questions a waveform cannot answer by
itself:

  `bal`  right-minus-left energy in dB. A CONTACT beat whose target stands 32
         degrees to the player's right has to be positive and LARGE; a beat whose
         target stands dead ahead has to be ~0. That is question F, measured.
  `live` the fraction of the slice above the take's own noise floor. A beat that
         fired its cue and is still 4% live is a cue with no tail; a beat at 90%
         live is a cue that has not finished when the next one starts.

READ `low%`/`edge%`/`cent` AS LEVEL, NOT AS TIMBRE. They window the WHOLE slice with
a Hann, and a Hann is 0 at both ends, so a cue that lives in the first third of a
1.5 s slice has its onset multiplied by ~0.01 and what survives is a step that leaks
as 1/f energy. Measured: `sword_contact_stone` reads a centroid of 743/2194/3480 Hz
across its three variants this way, which looks like a 2.2-octave variant lottery -
and on the ATTACK window (`attack_bands.py`, 0.12 s from the detected onset) the same
six plays sit inside 19.6-29.1% low and 24.6-35.1% edge, i.e. one stable material.
Use these columns for level, tail and stereo side; use `attack_bands.py` for colour.

Usage: review_take.py <take_dir> [--floor-db -60]
"""
from __future__ import annotations

import argparse
import sys
import wave
from pathlib import Path

import numpy as np


def read_wav(path: Path):
    with wave.open(str(path), "rb") as w:
        rate, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(w.getnframes())
    dt = {2: "<i2", 4: "<i4"}[sw]
    scale = {2: 32768.0, 4: 2147483648.0}[sw]
    a = np.frombuffer(raw, dtype=dt).astype(np.float64) / scale
    if ch > 1:
        a = a.reshape(-1, ch)
    else:
        a = a.reshape(-1, 1)
    return a, rate


def db(x: float) -> float:
    return 20.0 * np.log10(max(x, 1e-9))


def analyse(slice_: np.ndarray, rate: int, floor_db: float):
    if slice_.size == 0:
        return None
    mono = slice_.mean(axis=1)
    peak = float(np.abs(mono).max())
    rms = float(np.sqrt(np.mean(mono ** 2)))
    floor = 10 ** (floor_db / 20.0)
    live = float(np.mean(np.abs(mono) > floor))
    # Bands and centre come from the slice AS HEARD, so a beat that is mostly its
    # own tail reports the tail - which is the point of measuring the beat and not
    # the atom.
    spec = np.abs(np.fft.rfft(mono * np.hanning(len(mono))))
    freqs = np.fft.rfftfreq(len(mono), 1.0 / rate)
    e = spec ** 2
    tot = e.sum() + 1e-12
    cent = float((freqs * e).sum() / tot)

    def share(lo, hi):
        return 100.0 * e[(freqs >= lo) & (freqs < hi)].sum() / tot

    # TAIL is measured on a 20 ms RMS ENVELOPE against the beat's OWN peak, not on
    # raw samples against an absolute floor. The first version took the last sample
    # above -60 dBFS, so one stray sample 1.4 s later reported a 1.4 s tail on a
    # 0.25 s whoosh - which ruined the single column PART C ("尾音短") and PART D
    # ("CLANG -> SILENCE") are actually judged on.
    win = max(1, int(0.020 * rate))
    frames = len(mono) // win
    tail = 0.0
    if frames > 0:
        env = np.sqrt(np.mean(mono[:frames * win].reshape(frames, win) ** 2, axis=1))
        peak_env = float(env.max())
        if peak_env > 0.0:
            above = np.nonzero(env > peak_env * 0.01)[0]
            if above.size:
                tail = float((above[-1] + 1) * win / rate)
    atk = float(np.argmax(np.abs(mono)) / rate)

    out = {
        "peak": db(peak),
        "rms": db(rms),
        "live": 100.0 * live,
        "tail": tail,
        "atk": atk,
        "cent": cent,
        "low": share(0, 160),
        "mid": share(160, 2000),
        "edge": share(2000, 6500),
        "air": share(6500, rate),
        "bal": 0.0,
    }
    if slice_.shape[1] >= 2:
        left = float(np.sum(slice_[:, 0] ** 2))
        right = float(np.sum(slice_[:, 1] ** 2))
        out["bal"] = 10.0 * np.log10((right + 1e-12) / (left + 1e-12))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("take_dir")
    ap.add_argument("--floor-db", type=float, default=-60.0,
                    help="level above which a sample counts as audible")
    args = ap.parse_args()

    take = Path(args.take_dir)
    beats_path = take / "beats.tsv"
    wav_path = take / "sword_performance_pass01.wav"
    if not beats_path.exists():
        sys.exit("no beats.tsv in %s - the take was not shot with a beat map" % take)
    if not wav_path.exists():
        sys.exit("no %s" % wav_path)

    data, rate = read_wav(wav_path)
    total = len(data) / rate

    rows = [ln.split("\t") for ln in beats_path.read_text(encoding="utf-8").splitlines()[1:]]
    print("take: %s   %.2fs   %d channels @ %d Hz" % (wav_path.name, total, data.shape[1], rate))

    # One width vector, used by the header and by every row, with a length check.
    # The header used to be a hand-counted %-6s run that silently drifted out of
    # step with the row - it raised before a single beat was measured.
    HEAD = ("start", "end", "beat", "expect", "fired", "peak", "rms", "live%",
            "tail", "atk", "low%", "edge%", "air%", "cent", "R-L")
    WIDTH = (6, 6, 46, 6, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 6)
    print(" ".join("%-*s" % (w, h) for h, w in zip(HEAD, WIDTH)))

    for row in rows:
        if len(row) < 5:
            continue
        start, end = float(row[0]), float(row[1])
        caption, expect, fired = row[2], row[3], row[4]
        seg = data[int(start * rate):int(end * rate)]
        m = analyse(seg, rate, args.floor_db)
        if m is None:
            continue
        cells = [
            "%.2f" % start, "%.2f" % end, caption, expect.lstrip("&") or "-",
            fired + ("" if fired in ("-", "YES") else " !!"),
            "%.1f" % m["peak"], "%.1f" % m["rms"], "%.0f" % m["live"],
            "%.2f" % m["tail"], "%.2f" % m["atk"],
            "%.1f" % m["low"], "%.1f" % m["edge"], "%.1f" % m["air"],
            "%.0f" % m["cent"], "%+.1f" % m["bal"],
        ]
        assert len(cells) == len(WIDTH), "row/header width mismatch"
        print(" ".join("%-*s" % (w, c) for c, w in zip(cells, WIDTH)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
