#!/usr/bin/env python3
"""Per-VARIANT band split for a named set of atoms, so a cue that measures low can
be traced to the layer that made it low instead of being fixed by ear.

`review_take.py` measures the RECORDED BUS, i.e. the cue. When a cue reads 72% below
160 Hz there are two very different repairs: the identity atom is itself dark, or a
support layer is dark and too loud. This answers which, per seed variant, because a
cue picks variants round-robin and one bad seed is a bug in only one third of plays.

Usage: atom_bands.py <stem> [<stem> ...]
       atom_bands.py --dir-root <path> <stem> ...
"""
from __future__ import annotations
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import sys
import wave
from pathlib import Path

import numpy as np

# res:// is relative to the Godot project root, NOT the repo root. Getting this
# wrong yields perfectly legal silence.
SFX = Path(str(_SEKAI_ROOT / 'godot/audio/sfx'))


def read(path: Path):
    with wave.open(str(path), "rb") as w:
        sr, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(w.getnframes())
    dt = {2: "<i2", 4: "<i4"}[sw]
    scale = {2: 32768.0, 4: 2147483648.0}[sw]
    a = np.frombuffer(raw, dtype=dt).astype(np.float64) / scale
    if ch > 1:
        a = a.reshape(-1, ch).mean(axis=1)
    return a, sr


def bands(a: np.ndarray, sr: int):
    spec = np.abs(np.fft.rfft(a * np.hanning(len(a))))
    freqs = np.fft.rfftfreq(len(a), 1.0 / sr)
    e = spec ** 2
    tot = e.sum() + 1e-12

    def share(lo, hi):
        return 100.0 * e[(freqs >= lo) & (freqs < hi)].sum() / tot

    cent = float((freqs * e).sum() / tot)
    peak = float(np.max(np.abs(a)))
    pk_db = 20.0 * np.log10(peak) if peak > 0 else -180.0
    return cent, share(0, 160), share(160, 2000), share(2000, 6500), share(6500, sr), len(a) / sr, pk_db


def main(argv):
    stems = [s for s in argv if not s.startswith("--")]
    if not stems:
        sys.exit(__doc__)
    print("%-34s %-6s %7s %6s %5s %5s %5s %5s %6s" % (
        "atom", "seed", "len", "peak", "low%", "mid%", "edge%", "air%", "cent"))
    missing = 0
    for stem in stems:
        hits = sorted(SFX.rglob(stem + "*.wav"))
        if not hits:
            print("%-34s  --    MISSING" % stem)
            missing += 1
            continue
        for f in hits:
            a, sr = read(f)
            cent, lo, mid, edge, air, ln, pk = bands(a, sr)
            seed = f.stem.split("_")[-1]
            print("%-34s %-6s %6.2fs %6.1f %5.1f %5.1f %5.1f %5.1f %6.0f" % (
                stem, seed, ln, pk, lo, mid, edge, air, cent))
    if missing:
        print("MISSING atoms: %d" % missing)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
