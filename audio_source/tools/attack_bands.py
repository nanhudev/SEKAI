#!/usr/bin/env python3
"""Band split of a beat's ATTACK, not of its whole slice.

WHY THIS EXISTS. `review_take.py` measures each beat over the full recorded slice,
which is right for level, tail and stereo side - and wrong for timbre. A cue with a
0.07 s transient on top of a 1 s decay has almost all of its ENERGY in the decay, so
the slice's band split describes the decay. A cue measured that way can read "0.0%
above 2 kHz" while its attack is the brightest thing in the take.

That distinction decides repairs. The first pass at `sword_hit_weight` was culled,
then defended, on whole-slice numbers, and the window that matters said something
different in both directions: a layer can be accused of having no edge when the edge
is there and merely short, or be let off when its attack is what is wrong.

So: this reads the same `beats.tsv` and the same recorded wav as `review_take.py` and
reports the band split over a short window taken from the beat's own detected onset.
Use it together with `review_take.py`, never instead of it.

Usage: attack_bands.py <take_dir> [--window 0.12] [--only <substring>]
"""
from __future__ import annotations

import argparse
import sys
import wave
from pathlib import Path

import numpy as np

BANDS = ((0, 160), (160, 2000), (2000, 6500), (6500, None))


def read_wav(path: Path):
    with wave.open(str(path), "rb") as w:
        rate, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(w.getnframes())
    dt = {2: "<i2", 4: "<i4"}[sw]
    scale = {2: 32768.0, 4: 2147483648.0}[sw]
    a = np.frombuffer(raw, dtype=dt).astype(np.float64) / scale
    return (a if ch == 1 else a.reshape(-1, ch).mean(axis=1)), rate


def bands(x: np.ndarray, rate: int):
    if x.size < 64:
        return (0.0, 0.0, 0.0, 0.0)
    # Power, not magnitude: a magnitude-weighted centroid is dominated by broadband
    # noise and reads a spiky transient as far brighter than it sounds.
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    freq = np.fft.rfftfreq(len(x), 1.0 / rate)
    total = spec.sum() + 1e-30
    out = []
    for lo, hi in BANDS:
        sel = freq >= lo if hi is None else (freq >= lo) & (freq < hi)
        out.append(100.0 * spec[sel].sum() / total)
    return tuple(out)


def db(x: float) -> float:
    return 20.0 * np.log10(max(x, 1e-9))


def onset_of(seg: np.ndarray, rate: int) -> int:
    """First sample of the TRANSIENT inside a slice.

    The first version of this tool read an `atk` column out of `beats.tsv`. That column
    does not exist - `review_take.py` COMPUTES it for its own table and never writes it -
    so `dict.get("atk", 0.0)` silently returned 0 and the tool measured the first 0.12 s of
    every slice instead of the attack. Which is how perfect guard came back reading
    64.7% below 160 Hz: the clang is 0.13 s into the slice and the window had already
    closed.

    Derive it here instead: a 5 ms RMS envelope, and the onset is the first frame at a
    fifth of the envelope's own maximum. Robust to a quiet lead-in and to a loud tail.
    """
    win = max(1, int(0.005 * rate))
    if seg.size < win * 2:
        return 0
    frames = seg.size // win
    env = np.sqrt(np.mean(seg[:frames * win].reshape(frames, win) ** 2, axis=1))
    if env.size == 0 or env.max() <= 0:
        return 0
    above = np.flatnonzero(env >= 0.2 * env.max())
    return int(above[0] * win) if above.size else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("take_dir")
    ap.add_argument("--window", type=float, default=0.12,
                    help="seconds of attack to measure (default 0.12)")
    ap.add_argument("--only", default="", help="substring filter on the beat label")
    ap.add_argument("--from-slice-start", action="store_true",
                    help="ignore onset detection; measure from the slice start instead")
    args = ap.parse_args()

    take = Path(args.take_dir)
    beats = take / "beats.tsv"
    wav = take / "sword_performance_pass01.wav"
    if not beats.exists() or not wav.exists():
        print("no beats.tsv / take wav under %s" % take, file=sys.stderr)
        return 2

    audio, rate = read_wav(wav)
    rows = [r.split("\t") for r in beats.read_text().splitlines() if r.strip()]
    head = rows[0]
    print("take: %s   attack window %.3fs   mono %.0f Hz%s"
          % (wav.name, args.window, rate,
             "   FROM SLICE START" if args.from_slice_start else "   from detected onset"))
    print("%-38s %8s %7s %6s %6s %6s %6s" %
          ("beat", "atk_rms", "peak", "low%", "mid%", "edge%", "air%"))

    shown = 0
    for row in rows[1:]:
        d = dict(zip(head, row))
        label = d["beat"]
        if args.only and args.only not in label:
            continue
        start = float(d["start"])
        slice_end = float(d["end"])
        whole = audio[int(start * rate):int(slice_end * rate)]
        offset = 0.0 if args.from_slice_start else onset_of(whole, rate) / rate
        onset = start + offset
        seg = audio[int(onset * rate):int((onset + args.window) * rate)]
        if seg.size == 0:
            print("%-38s %8s %7s %6s %6s %6s %6s" % (label, "-", "-", "-", "-", "-", "-"))
            shown += 1
            continue
        low, mid, edge, air = bands(seg, rate)
        print("%-38s %8.1f %7.1f %6.1f %6.1f %6.1f %6.1f"
              % (label, db(float(np.sqrt(np.mean(seg ** 2)) + 1e-12)),
                 db(float(np.abs(seg).max())), low, mid, edge, air))
        shown += 1
    if shown == 0:
        print("(nothing matched --only %r)" % args.only, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
