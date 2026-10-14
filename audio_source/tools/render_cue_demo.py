#!/usr/bin/env python
"""Render the cue table to wav so the mix can be auditioned without launching
the game.

The point is A/B: run it against the current atoms and against
processed/pre_tame/ (the pre-fix backups) and listen to the two chains back to
back. Turning a mix decision into "press play twice" is faster than arguing
about dB values.

NOTE: the cue mirror below must stay in sync with
godot/scripts/audio/combat_audio_cues.gd. If a cue changes there, change it
here or the demo lies.

Usage:
    python audio_source/tools/render_cue_demo.py [--atoms <dir>] [--out <dir>]
"""

import argparse
import os
import wave

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GODOT = os.path.abspath(os.path.join(ROOT, "..", "godot"))
CORE = os.path.join(GODOT, "audio", "sfx", "core")
DEFAULT_OUT = os.path.join(ROOT, "processed", "demo")

RATE = 44100
REFERENCE_PEAK_DB = -6.0

# atom file -> measured peak (dBFS). Mirrors SoundAtomRegistry.ATOM_TABLE.
ATOMS = {
    "air_fast_01.wav": -6.0,
    "air_fast_02.wav": -6.0,
    "pressure_low_01.wav": -8.0,
    "body_low_01.wav": -9.0,
    "cloth_fast_01.wav": -6.0,
    "metal_sharp_01.wav": -6.0,
    "metal_sharp_02.wav": -6.0,
    "metal_body_01.wav": -7.34,
    "glass_crack_01.wav": -6.0,
    "glass_body_01.wav": -6.01,
    "glass_low_tick_01.wav": -8.0,
    "wind_pressure_01.wav": -9.40,
}

# Cue mirror: name -> [(atom file, gain_db, delay, pitch)]
CUES = {
    "light_1": [("air_fast_01.wav", 0.0, 0.0, 1.0), ("cloth_fast_01.wav", -9.0, 0.005, 1.0)],
    "light_2": [("air_fast_02.wav", 0.0, 0.0, 1.035), ("cloth_fast_01.wav", -9.0, 0.005, 1.0)],
    "light_3": [("air_fast_01.wav", -0.5, 0.0, 0.94), ("cloth_fast_01.wav", -10.0, 0.005, 1.0),
                ("body_low_01.wav", -18.0, 0.010, 1.0)],
    "heavy_swing": [("air_fast_01.wav", -1.0, 0.0, 0.98),
                    ("pressure_low_01.wav", -6.0, 0.05, 1.0),
                    ("cloth_fast_01.wav", -8.0, 0.01, 0.96)],
    "hit_light": [("body_low_01.wav", 0.0, 0.0, 1.0)],
    "hit_heavy": [("body_low_01.wav", 0.0, 0.0, 0.98), ("pressure_low_01.wav", -12.0, 0.0, 1.0)],
    "dodge": [("air_fast_01.wav", -3.0, 0.0, 1.06), ("cloth_fast_01.wav", -7.5, 0.0, 1.0)],
    "guard": [("metal_body_01.wav", 0.0, 0.0, 1.0), ("metal_sharp_01.wav", -8.0, 0.005, 1.0)],
    "perfect_guard": [("metal_sharp_01.wav", 0.0, 0.0, 1.0),
                      ("metal_body_01.wav", -5.5, 0.008, 1.0),
                      ("body_low_01.wav", -10.0, 0.012, 1.0)],
    "wind_burst": [("wind_pressure_01.wav", 0.0, 0.0, 1.0),
                   ("air_fast_01.wav", -5.0, 0.02, 1.0),
                   ("pressure_low_01.wav", -7.0, 0.06, 1.0)],
}


def read(path: str) -> np.ndarray:
    with wave.open(path, "rb") as handle:
        rate = handle.getframerate()
        channels = handle.getnchannels()
        raw = handle.readframes(handle.getnframes())
    data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)
    if rate != RATE:
        old = np.arange(len(data), dtype=np.float64)
        new = np.linspace(0, len(data) - 1, int(len(data) * RATE / rate))
        data = np.interp(new, old, data)
    return data


def pitch_shift(data: np.ndarray, factor: float) -> np.ndarray:
    if abs(factor - 1.0) < 1e-4:
        return data
    old = np.arange(len(data), dtype=np.float64)
    new = np.linspace(0, len(data) - 1, max(1, int(len(data) / factor)))
    return np.interp(new, old, data)


def render(atoms_dir: str, sequence, out_path: str, tail: float = 0.6) -> None:
    events = []
    for cue_name, at in sequence:
        for atom_file, gain_db, delay, pitch in CUES[cue_name]:
            events.append((at + delay, atom_file, gain_db, pitch))
    length = 0.0
    for at, atom_file, _gain, pitch in events:
        path = os.path.join(atoms_dir, atom_file)
        if not os.path.exists(path):
            continue
        length = max(length, at + len(read(path)) / float(RATE) / pitch)
    buffer = np.zeros(int((length + tail) * RATE), dtype=np.float64)
    for at, atom_file, gain_db, pitch in events:
        path = os.path.join(atoms_dir, atom_file)
        if not os.path.exists(path):
            print("  skip missing %s" % atom_file)
            continue
        data = read(path)
        # Same trim the registry applies, so the demo matches the game mix.
        trim = REFERENCE_PEAK_DB - ATOMS.get(atom_file, -6.0)
        gain = 10.0 ** ((trim + gain_db) / 20.0)
        chunk = pitch_shift(data, pitch) * gain
        start = int(at * RATE)
        end = min(len(buffer), start + len(chunk))
        buffer[start:end] += chunk[:end - start]
    peak = float(np.abs(buffer).max())
    if peak > 1e-9:
        buffer *= (10.0 ** (-3.0 / 20.0)) / peak
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    pcm = np.clip(buffer * 32767.0, -32768.0, 32767.0).astype("<i2")
    with wave.open(out_path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(pcm.tobytes())
    print("  %s" % os.path.basename(out_path))


DEMOS = {
    "demo_light_chain.wav": [
        ("light_1", 0.00), ("light_2", 0.34), ("light_3", 0.68),
        # second pass: same three swings, but each one CONNECTS
        ("light_1", 1.20), ("hit_light", 1.38),
        ("light_2", 1.60), ("hit_light", 1.78),
        ("light_3", 2.00), ("hit_light", 2.18),
    ],
    "demo_heavy_dodge.wav": [
        ("heavy_swing", 0.00), ("hit_heavy", 0.26),
        ("dodge", 1.10), ("dodge", 1.45),
    ],
    "demo_guards.wav": [
        ("guard", 0.00), ("guard", 0.45),
        ("perfect_guard", 1.30), ("perfect_guard", 1.75),
    ],
    "demo_wind.wav": [
        ("wind_burst", 0.00), ("wind_burst", 0.90),
    ],
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--atoms", default=CORE)
    parser.add_argument("--out", default=DEFAULT_OUT)
    parser.add_argument("--suffix", default="")
    args = parser.parse_args()
    for name, sequence in DEMOS.items():
        stem, ext = os.path.splitext(name)
        out = os.path.join(args.out, "%s%s%s" % (stem, args.suffix, ext))
        render(args.atoms, sequence, out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
