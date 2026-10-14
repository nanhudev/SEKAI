#!/usr/bin/env python3
"""Measure every atom's LOUDNESS and emit `godot/scripts/audio/atom_loudness_table.gd`.

WHY A LOUDNESS TABLE AND NOT A PEAK. `SoundAtom.base_gain_db` used to be
`-6.0 - peak`, and its own doc comment promised that "every atom reads at the same
loudness and layer gains are true RELATIVE values". A peak trim does not do that.
Measured over this library the crest factor (peak minus RMS) runs from 6.7 dB to
30.6 dB, so at the same table gain a DENSE atom (`metal_body`, 0.14 s, centroid
330 Hz, crest 10 dB) is about 8 dB louder than a SPIKY one (`air_fast`, 0.24 s,
centroid 2294 Hz, crest 18 dB). Consequence, measured in the cue sheet: in
`sword_light_3`, written with `air_fast` at 0 dB and `metal_body` at -13 dB, the
recording was dominated by `metal_body` - centroid 346 Hz instead of 1835 Hz. The
design language said "0 dB is the identity" and the audio disagreed.

WHAT IS MEASURED. The maximum RMS over a sliding window, not the whole-file RMS:
a 1.8 s chain bed with a long quiet tail would otherwise be judged by its tail and
boosted until its attack clipped. The window is long enough to contain one impact
and short enough that a bed is judged by its loudest moment.

Reference: `--reference-db` is the loudness an atom at 0 dB should land on. It is
chosen so the MEDIAN atom keeps the peak it has under the old basis, which keeps the
blast radius on the already-tuned chain cues small while still correcting the
outliers - which is where the bug actually was.

Usage: emit_atom_loudness.py [--reference-db -22.0] [--check] [--apply]
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

REPO = Path(str(_SEKAI_ROOT))
GODOT = REPO / "godot"
OUT = GODOT / "scripts" / "audio" / "atom_loudness_table.gd"
SOURCES = [
    GODOT / "scripts" / "audio" / "sound_atom_registry.gd",
    GODOT / "scripts" / "audio" / "chain_atom_table.gd",
]
WINDOW = 0.30
HOP = 0.15


def measure(path: Path):
    if not path.exists():
        return None
    with wave.open(str(path), "rb") as w:
        sr, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(w.getnframes())
    if sw not in (2, 4):
        return None
    dt = {2: "<i2", 4: "<i4"}[sw]
    scale = {2: 32768.0, 4: 2147483648.0}[sw]
    a = np.frombuffer(raw, dtype=dt).astype(np.float64) / scale
    if ch > 1:
        a = a.reshape(-1, ch).mean(axis=1)
    if a.size == 0:
        return None
    peak = 20.0 * np.log10(max(float(np.abs(a).max()), 1e-9))
    win = max(1, int(WINDOW * sr))
    hop = max(1, int(HOP * sr))
    if len(a) <= win:
        windows = a.reshape(1, -1)
    else:
        count = 1 + (len(a) - win) // hop
        windows = np.lib.stride_tricks.as_strided(
            a, shape=(count, win), strides=(a.strides[0] * hop, a.strides[0]))
    power = (windows ** 2).mean(axis=1)
    loud = 20.0 * np.log10(max(float(np.sqrt(power.max())), 1e-9))
    return peak, loud, len(a) / sr


def rows_from_sources():
    """(atom id, absolute wav path) for every atom either table declares."""
    out = []
    for src in SOURCES:
        text = src.read_text(encoding="utf-8")
        for m in re.finditer(
                r'\{"id": &"([^"]+)"(.*?)\}', text, re.S):
            atom_id, rest = m.group(1), m.group(2)
            blob = m.group(0)
            f = re.search(r'"file": "([^"]+)"', blob)
            if not f:
                continue
            d = re.search(r'"dir": "([^"]+)"', blob)
            if d:
                rel = d.group(1).replace("res://", "") + f.group(1)
            else:
                rel = "audio/sfx/core/" + f.group(1)
            out.append((atom_id, GODOT / rel))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--reference-db", type=float, default=None,
                    help="loudness an atom at 0 dB lands on; defaults to "
                         "-6.0 - median(crest), i.e. the median atom keeps the peak "
                         "it had under the old basis, which keeps the blast radius on "
                         "the already-tuned chain cues at about zero")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    seen = {}
    misses = []
    for atom_id, path in rows_from_sources():
        if atom_id in seen:
            continue
        m = measure(path)
        if m is None:
            misses.append((atom_id, str(path)))
            continue
        seen[atom_id] = m
    if not seen:
        sys.exit("no atoms measured - table regexes did not match")

    peaks = np.array([v[0] for v in seen.values()])
    louds = np.array([v[1] for v in seen.values()])
    crest = peaks - louds
    if args.reference_db is None:
        args.reference_db = -6.0 - float(np.median(crest))
    old = -6.0 - peaks
    new = args.reference_db - louds
    print("atoms=%d  missing=%d" % (len(seen), len(misses)))
    print("short-term crest: min %.1f  median %.1f  max %.1f  spread %.1f dB" % (
        crest.min(), float(np.median(crest)), crest.max(), crest.max() - crest.min()))
    print("basis shift:     min %+.1f  median %+.1f  max %+.1f  mean %+.1f dB" % (
        (new - old).min(), float(np.median(new - old)),
        (new - old).max(), (new - old).mean()))
    worst = sorted(seen.items(), key=lambda kv: -abs(
        (args.reference_db - kv[1][1]) - (-6.0 - kv[1][0])))[:12]
    print("largest corrections (atom / crest / old trim / new trim):")
    for atom_id, (peak, loud, _) in worst:
        print("  %-32s crest %5.1f   %+6.1f -> %+6.1f dB" % (
            atom_id, peak - loud, -6.0 - peak, args.reference_db - loud))
    for atom_id, path in misses:
        print("  MISSING FILE: %s  (%s)" % (atom_id, path))

    crest_note = (
        "## Because a PEAK trim does not make atoms equally loud. Crest factors here run\n"
        "## from %.1f to %.1f dB, so a dense low body written at -13 dB could still be the\n"
        "## loudest thing in its cue - measured, in `sword_light_3`. A peak trim also\n"
        "## cannot notice when a peak it recorded goes stale, and two of the core atoms\n"
        "## were already 1.8 and 2.2 dB stale." % (crest.min(), crest.max())
    )
    lines = [
        "extends RefCounted",
        "## GENERATED - do not edit by hand.",
        "##",
        "## Written by `audio_source/tools/emit_atom_loudness.py`, which also writes the",
        "## command in its own docstring. One row per atom id: the measured short-term",
        "## loudness and the trim derived from it.",
        "##",
        "## WHY THIS FILE EXISTS AT ALL, given the atom tables already carry a `peak`.",
        crest_note,
        "## It is a SIDE table keyed by atom id rather than a new field in the two atom",
        "## tables on purpose: `chain_atom_table.gd` is generated by a tool that a",
        "## parallel session runs from its own worktree, and adding a column there would",
        "## mean two writers disagreeing about the same file. The registry merges this in",
        "## and falls back to the old peak formula for any id that is absent, so a",
        "## missing row degrades to the previous behaviour instead of to silence.",
        "",
        "const REFERENCE_LOUDNESS_DB := %.1f" % args.reference_db,
        "",
        "## atom id -> [measured short-term loudness dBFS, measured peak dBFS]",
        "const LOUDNESS := {",
    ]
    for atom_id in sorted(seen):
        peak, loud, _ = seen[atom_id]
        lines.append('\t&"%s": [%.2f, %.2f],' % (atom_id, loud, peak))
    lines.append("}")
    lines.append("")
    text = "\n".join(lines)

    if args.check:
        old_text = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        print("\n%s" % ("IN SYNC" if old_text == text else "DRIFT - re-run with --apply"))
        return 0
    if args.apply:
        OUT.write_text(text, encoding="utf-8")
        print("\nwrote %s (%d rows)" % (OUT, len(seen)))
        return 0
    print("\n(dry run; pass --apply to write %s)" % OUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
