#!/usr/bin/env python3
"""Why the atom trim is wrong, measured.

`sound_atom_registry.gd` and `chain_atom_table.gd` store each atom's measured PEAK and
the registry turns it into `base_gain_db = -6.0 - peak`. That makes every atom's
PEAK equal, which is not the same as making them equally loud, because the atoms in
this library have crest factors from about 10 dB to about 18 dB:

  * a dense low body (`metal_body`, 0.14 s, centroid 330 Hz) has crest ~10 dB
  * a spiky air whoosh (`air_fast`, 0.24 s, centroid 2294 Hz) has crest ~18 dB

At the same table gain the dense one is ~8 dB LOUDER, so a layer written as "-13 dB
under the identity" can be the loudest thing in the cue. This tool prints per-atom
peak, RMS, crest and the trim each basis would give, so the size of the correction is
a number instead of an argument.

Usage: atom_loudness.py [--reference-db -24.0]
"""
from __future__ import annotations
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import argparse
import sys
import wave
from pathlib import Path

import numpy as np

SFX = Path(str(_SEKAI_ROOT / 'godot/audio/sfx'))
REFERENCE_PEAK_DB = -6.0


def measure(path: Path):
    with wave.open(str(path), "rb") as w:
        sr, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(w.getnframes())
    dt = {2: "<i2", 4: "<i4"}[sw]
    scale = {2: 32768.0, 4: 2147483648.0}[sw]
    a = np.frombuffer(raw, dtype=dt).astype(np.float64) / scale
    if ch > 1:
        a = a.reshape(-1, ch).mean(axis=1)
    if a.size == 0:
        return None
    peak = 20.0 * np.log10(max(float(np.abs(a).max()), 1e-9))
    rms = 20.0 * np.log10(max(float(np.sqrt((a ** 2).mean())), 1e-9))
    return peak, rms, len(a) / sr


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reference-db", type=float, default=-24.0,
                    help="RMS the identity layer should land on")
    args = ap.parse_args()

    rows = []
    for f in sorted(SFX.rglob("*.wav")):
        m = measure(f)
        if m is None:
            continue
        peak, rms, ln = m
        rows.append((f, peak, rms, peak - rms, ln))
    if not rows:
        sys.exit("no wavs under %s" % SFX)

    crests = np.array([r[3] for r in rows])
    print("atoms=%d   crest: min %.1f  median %.1f  max %.1f  spread %.1f dB" % (
        len(rows), crests.min(), float(np.median(crests)), crests.max(),
        crests.max() - crests.min()))
    print()

    peaks = np.array([REFERENCE_PEAK_DB - r[1] for r in rows])
    louds = np.array([args.reference_db - r[2] for r in rows])
    shift = louds - peaks
    print("implied correction (loudness basis minus peak basis):")
    print("  min %+.1f  median %+.1f  max %+.1f  mean %+.1f dB" % (
        shift.min(), float(np.median(shift)), shift.max(), shift.mean()))
    print()
    print("%-34s %6s %6s %6s %8s %8s %8s" % (
        "atom", "len", "peak", "rms", "crest", "peak→", "loud→"))
    order = np.argsort(-np.abs(shift))
    for i in order:
        f, peak, rms, crest, ln = rows[i]
        print("%-34s %5.2fs %6.1f %6.1f %6.1f %+8.1f %+8.1f" % (
            f.stem, ln, peak, rms, crest, peaks[i], louds[i]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
