#!/usr/bin/env python3
"""Rebuild each cue offline from the RESOLVED layer list, and diff it against the take.

WHY THIS EXISTS. `review_take.py` measures what came out. `layers.tsv` records what the
mixer decided to put in - group, atom, final gain, pitch, delay, per layer. Between
those two there is a whole playback path, and when a cue measures nothing like its own
table there are two very different explanations:

  * the table is wrong (a layer is too loud, the identity atom is the wrong colour), or
  * the PLAYBACK is wrong (a pitch that is not applied, a delay that is smeared, two
    layers landing on one voice).

Guessing between them from the summed recording is how an afternoon disappears. This
reconstructs the mix from the same numbers the engine used and reports whether it
reproduces the take. If it does, every future question about a cue can be answered
offline, per layer, without rendering anything.

Also prints, for each cue, each layer's share of the total ENERGY and of the low band -
which is the actual answer to "which layer is the identity", as opposed to which one
was written at 0 dB.

Usage: cue_mix.py <take_dir> [--only <cue_id>]
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
TABLES = [
    GODOT / "scripts" / "audio" / "sound_atom_registry.gd",
    GODOT / "scripts" / "audio" / "chain_atom_table.gd",
]


def atom_files():
    """atom id -> absolute wav path, from the two atom tables."""
    out = {}
    for src in TABLES:
        text = src.read_text(encoding="utf-8")
        for m in re.finditer(r'\{"id": &"([^"]+)"(.*?)\}', text, re.S):
            blob = m.group(0)
            f = re.search(r'"file": "([^"]+)"', blob)
            if not f:
                continue
            d = re.search(r'"dir": "([^"]+)"', blob)
            rel = (d.group(1).replace("res://", "") if d else "audio/sfx/core/") + f.group(1)
            out.setdefault(m.group(1), GODOT / rel)
    return out


def read_wav(path: Path):
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
    if a.size == 0:
        return 0.0, 0.0, 0.0, 0.0, 0.0
    spec = np.abs(np.fft.rfft(a * np.hanning(len(a))))
    fr = np.fft.rfftfreq(len(a), 1.0 / sr)
    e = spec ** 2
    tot = e.sum() + 1e-12

    def sh(lo, hi):
        return 100.0 * e[(fr >= lo) & (fr < hi)].sum() / tot

    return float((fr * e).sum() / tot), sh(0, 160), sh(160, 2000), sh(2000, 6500), sh(6500, sr)


def db(x: float) -> float:
    return 20.0 * np.log10(max(x, 1e-9))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("take_dir")
    ap.add_argument("--only", default="")
    args = ap.parse_args()

    take = Path(args.take_dir)
    layers_path = take / "layers.tsv"
    beats_path = take / "beats.tsv"
    if not layers_path.exists():
        sys.exit("no layers.tsv in %s - the take was not shot with the resolved mix" % take)

    files = atom_files()
    rate = 44100

    # cue label -> [ (group, atom, gain_db, pitch, delay) ]
    plan = {}
    order = []
    for ln in layers_path.read_text(encoding="utf-8").splitlines()[1:]:
        parts = ln.split("\t")
        if len(parts) < 6:
            continue
        label = parts[0]
        if label not in plan:
            plan[label] = []
            order.append(label)
        plan[label].append((parts[1], parts[2], float(parts[3]), float(parts[4]), float(parts[5])))

    # recorded slices
    recorded = {}
    for ln in beats_path.read_text(encoding="utf-8").splitlines()[1:]:
        p = ln.split("\t")
        if len(p) >= 3:
            recorded.setdefault(p[2], []).append((float(p[0]), float(p[1])))

    wav_path = take / "sword_performance_pass01.wav"
    if not wav_path.exists():
        sys.exit("no %s" % wav_path)
    bus, bus_rate = read_wav(wav_path)
    rate = bus_rate

    print("%-38s %8s %8s %8s %8s %8s" % (
        "cue", "peak", "cmp peak", "cent", "cmp cent", "match"))
    print("%-38s %8s %8s %8s %8s %8s" % ("", "(offline)", "(take)", "(offline)", "(take)", ""))
    worst = []
    for label in order:
        if args.only and args.only not in label:
            continue
        layers = plan[label]
        length = 0.0
        for _, _, _, _, delay in layers:
            pass
        # Offline mix at the same nominal length as the longest recorded slice.
        spans = recorded.get(label, [])
        total = max((b - a) for a, b in spans) if spans else 1.5
        n = int(total * rate) + 1
        mix = np.zeros(n)
        contrib = []
        layer_end = 0.0
        for group, atom, gain, pitch, delay in layers:
            path = files.get(atom)
            if path is None or not path.exists():
                contrib.append((group, atom, 0.0, 0.0, 0.0))
                continue
            a, sr = read_wav(path)
            # The engine sets AudioStreamPlayer.pitch_scale, which resamples: the
            # whole file gets longer by 1/pitch and every frequency by pitch.
            m = max(2, int(round(len(a) / max(pitch, 1e-3))))
            src_idx = np.linspace(0.0, len(a) - 1.0, m)
            r = np.interp(src_idx, np.arange(len(a)), a) * (10.0 ** (gain / 20.0))
            off = int(delay * rate)
            end = min(n, off + len(r))
            if off < n:
                mix[off:end] += r[:end - off]
            layer_end = max(layer_end, off / rate + len(r) / rate)
            contrib.append((group, atom, float(np.sum(r ** 2)), delay, pitch))
        tot_e = sum(c[2] for c in contrib) + 1e-12
        # MEASURE THE CUE, NOT THE SLICE. Both sides go through `bands()`, which windows
        # with a Hann over the whole buffer, and a Hann is 0 at both ends. A cue that
        # occupies the first third of a 1.5 s slice therefore has its onset multiplied by
        # ~0.01 and the surviving step leaks as 1/f energy, so part of the reading
        # describes the window rather than the sound. Measured on
        # `sword_contact_stone @ahead pass 1`, reconstruction and take alike: over the
        # 1.48 s slice, 2256 Hz and 39.8% below 160 Hz; over the cue's own 0.67 s span,
        # 2418 Hz and 20.1%. Half the low band was buffer occupancy. Trimming BOTH sides
        # to the cue's own span makes the artifact cancel instead of being divided out by
        # luck. It does NOT close the residual gap to the take - that one is real and
        # lives in the playback path, in `layered_sfx.gd`'s air-absorption filter.
        cut = n if layer_end <= 0.02 else min(n, int(layer_end * rate) + 1)
        cent, lo, mid, edge, air = bands(mix[:cut], rate)
        peak = db(float(np.abs(mix).max()))
        rec_peak = rec_cent = float("nan")
        if spans:
            a0, a1 = spans[0]
            seg = bus[int(a0 * rate):int(a0 * rate) + cut]
            if seg.size:
                rec_peak = db(float(np.abs(seg).max()))
                rec_cent, *_ = bands(seg, rate)
        flag = ""
        if np.isfinite(rec_peak):
            d = peak - rec_peak
            if abs(d) > 3.0:
                flag = "PEAK %+.1f" % d
            dc = cent - rec_cent
            if abs(dc) > 0.35 * max(cent, 1.0):
                flag += " CENT %+.0f" % dc
        print("%-38s %8.1f %8.1f %8.0f %8.0f  %s" % (
            label, peak, rec_peak, cent, rec_cent, flag if flag else "ok"))
        worst.append((label, [c for c in contrib]))
        if args.only:
            print("    %-26s %-30s %6s %6s %7s" % ("group", "atom", "share%", "delay", "pitch"))
            for group, atom, e, delay, pitch in contrib:
                print("    %-26s %-30s %6.1f %6.3f %7.3f" % (
                    group, atom, 100.0 * e / tot_e, delay, pitch))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
