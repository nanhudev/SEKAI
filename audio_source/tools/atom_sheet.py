#!/usr/bin/env python3
"""One dry wav containing every sword atom in the library, family by family.

WHY. Reviewing a rebuilt sound language by opening 40 files is reviewing nothing: the
only comparison that matters is BETWEEN atoms, and a player cannot hold two files in
their head. This lays the whole set out in one take, in the order the language groups
them, with a fixed gap - so "is this family one sound or three" becomes a single listen
instead of a folder tour.

Dry on purpose (brief PART K): these are the raw atoms, before any cue gain, pitch or
spatialisation. Anything that needs reverb to work is a bug in the atom.

The gap is 0.35 s rather than a musical value: long enough that a tail does not leak into
the next atom's attack, short enough that the file stays listenable end to end.

Usage: atom_sheet.py [--out <wav>] [--gap 0.35] [--group sword_contact_* wood_crack ...]
       with no --group: every group that has an atom under godot/audio/sfx/atoms/
"""
from __future__ import annotations
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import argparse
import re
import sys
import wave
from pathlib import Path

import numpy as np

# res:// is the GODOT PROJECT root, not the repo root - the wrong one yields perfectly
# legal silence.
ATOMS = Path(str(_SEKAI_ROOT / 'godot/audio/sfx/atoms'))
DEMO = Path(str(_SEKAI_ROOT / 'audio_source/processed/demo'))
# The AUTHORITATIVE group of a file lives in the two Godot tables. Deriving it from the
# filename instead was the first version of this tool and it was wrong on any family whose
# name contains `_s` - `blade_ring_short` and `sword_contact_stone` both came out as their
# first two words, which quietly merged three families into two and lost two others.
TABLE_PATHS = (
    Path(str(_SEKAI_ROOT / 'godot/scripts/audio/chain_atom_table.gd')),
    Path(str(_SEKAI_ROOT / 'godot/scripts/audio/sound_atom_registry.gd')),
)
ROW = re.compile(
    r'"id":\s*&"([^"]+)".*?"file":\s*"([^"]+)".*?"group":\s*&"([^"]+)"', re.S)


def read(path: Path):
    with wave.open(str(path), "rb") as w:
        rate, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(w.getnframes())
    dt = {2: "<i2", 4: "<i4"}[sw]
    scale = {2: 32768.0, 4: 2147483648.0}[sw]
    a = np.frombuffer(raw, dtype=dt).astype(np.float64) / scale
    return (a if ch == 1 else a.reshape(-1, ch).mean(axis=1)), rate


def file_to_group() -> dict[str, str]:
    out: dict[str, str] = {}
    for path in TABLE_PATHS:
        if not path.exists():
            print("missing table %s" % path, file=sys.stderr)
            continue
        for _id, file, group in ROW.findall(path.read_text(encoding="utf-8")):
            out[file] = group
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(DEMO / "sword_atoms_dry.wav"))
    ap.add_argument("--gap", type=float, default=0.35)
    ap.add_argument("--group", nargs="*", default=None)
    args = ap.parse_args()

    files = sorted(ATOMS.rglob("*.wav"))
    if not files:
        print("no atom wavs under %s" % ATOMS, file=sys.stderr)
        return 2

    known = file_to_group()
    families: dict[str, list[Path]] = {}
    unlisted: list[str] = []
    for path in files:
        family = known.get(path.name)
        if family is None:
            # A wav on disk that no table claims is not "an atom with a guessed family":
            # it is either a leftover render or a file the generator forgot to list. Both
            # want to be visible, so it gets its own bucket instead of a silent guess.
            family = "(unlisted) " + path.parent.name
            unlisted.append(path.name)
        if args.group and not any(
                family == g or (g.endswith("*") and family.startswith(g[:-1]))
                for g in args.group):
            continue
        families.setdefault(family, []).append(path)

    if not families:
        print("no families matched %r" % (args.group,), file=sys.stderr)
        return 1

    pieces: list[np.ndarray] = []
    index: list[str] = ["index\tfamily\tfile\tstart\tduration\tpeak_db\trms_db"]
    rate = 44100
    clock = 0.0
    order = sorted(families)
    for family in order:
        for path in sorted(families[family]):
            audio, rate = read(path)
            pieces.append(audio)
            pieces.append(np.zeros(int(args.gap * rate)))
            dur = len(audio) / rate
            peak = 20.0 * np.log10(max(float(np.abs(audio).max()), 1e-9))
            rms = 20.0 * np.log10(max(float(np.sqrt(np.mean(audio ** 2))), 1e-9))
            index.append("%d\t%s\t%s\t%.3f\t%.3f\t%.1f\t%.1f" % (
                len(index) - 1, family, path.name, clock, dur, peak, rms))
            clock += dur + args.gap

    mono = np.concatenate(pieces)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(out), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(np.clip(mono * 32767.0, -32768, 32767).astype("<i2").tobytes())

    tsv = out.with_suffix(".tsv")
    tsv.write_text("\n".join(index) + "\n", encoding="utf-8")
    print("families %d | atoms %d | %.2fs -> %s" % (
        len(order), len(index) - 1, len(mono) / rate, out))
    print("index -> %s" % tsv)
    for family in order:
        print("  %-34s %d" % (family, len(families[family])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
