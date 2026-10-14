#!/usr/bin/env python
"""Tame the air atoms: shape a real decay envelope and stop the broadband hiss.

Why this exists:
    The light chain sounded NOISY, not "swordy". Two measured causes, both in
    the material rather than in the mix:

    1. `tail/head = 0.60` - a 350 ms block of noise that barely decays. Three
       light attacks in a row therefore overlap into one continuous wall.
    2. The spectrum is almost flat: 12 kHz sits only ~4 dB under the body of
       the sound. That reads as hiss, not as a blade. There is also a sub-200 Hz
       component loud enough to smear the transient into rumble.

    Turning the volume down would have made the swing quiet AND still hissy.
    So: give the whoosh an exponential decay, band-limit it to the "speed"
    region, and re-level it back to the library reference peak.

Originals are backed up to processed/pre_tame/ before anything is overwritten.

Usage:
    python audio_source/tools/tame_atoms.py [--dry-run]
"""

import argparse
import os
import shutil
import wave

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GODOT = os.path.abspath(os.path.join(ROOT, "..", "godot"))
CORE = os.path.join(GODOT, "audio", "sfx", "core")
BACKUP = os.path.join(ROOT, "processed", "pre_tame")

TARGET_PEAK_DB = -6.0

# Frequency -> dB. Interpolated on a log axis, so this is a tone curve, not a
# stack of peaking filters. The point: keep 0.8 - 3.5 kHz (where "speed" lives),
# throw away rumble and hiss.
AIR_CURVE = [
    (60.0, -14.0), (150.0, -8.0), (300.0, -3.0), (600.0, -1.0),
    (900.0, 0.0), (3500.0, 0.0), (5000.0, -5.0), (8000.0, -9.0),
    (12000.0, -14.0), (16000.0, -18.0), (22050.0, -22.0),
]

# Cloth is low-mid heavy and 280 ms long, which turns a subtle layer into
# rumble. High-pass it and shorten it so it reads as movement.
CLOTH_CURVE = [
    (60.0, -30.0), (150.0, -18.0), (300.0, -8.0), (500.0, -3.0),
    (900.0, 0.0), (3000.0, 0.0), (6000.0, -4.0), (10000.0, -9.0),
    (22050.0, -14.0),
]

JOBS = [
    # file, curve, decay tau (s), max length (s), attack hold (s)
    ("air_fast_01.wav", AIR_CURVE, 0.070, 0.24, 0.012),
    ("air_fast_02.wav", AIR_CURVE, 0.070, 0.24, 0.012),
    ("cloth_fast_01.wav", CLOTH_CURVE, 0.085, 0.20, 0.010),
]


def read_wav(path: str):
    with wave.open(path, "rb") as handle:
        rate = handle.getframerate()
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        raw = handle.readframes(handle.getnframes())
    if width != 2:
        raise SystemExit("expected 16-bit pcm: %s" % path)
    data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if channels > 1:
        data = data.reshape(-1, channels)
    return rate, channels, data


def write_wav(path: str, rate: int, data: np.ndarray) -> None:
    pcm = np.clip(data * 32767.0, -32768.0, 32767.0).astype("<i2")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1 if data.ndim == 1 else data.shape[1])
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(pcm.tobytes())


def tone_curve(rate: int, n: int, points) -> np.ndarray:
    freqs = np.fft.rfftfreq(n, 1.0 / rate)
    freqs = np.maximum(freqs, 1.0)
    xs = np.array([p[0] for p in points], dtype=np.float64)
    ys = np.array([p[1] for p in points], dtype=np.float64)
    gains_db = np.interp(np.log(freqs), np.log(xs), ys)
    return 10.0 ** (gains_db / 20.0)


def envelope(n: int, rate: int, tau: float, hold: float) -> np.ndarray:
    times = np.arange(n, dtype=np.float64) / float(rate)
    env = np.exp(-np.maximum(times - hold, 0.0) / tau)
    # A click at t=0 is worse than a slightly soft attack.
    attack = max(1, int(0.002 * rate))
    env[:attack] *= np.linspace(0.0, 1.0, attack)
    return env


def process(path: str, curve_points, tau: float, max_len: float, hold: float,
            dry_run: bool):
    rate, channels, data = read_wav(path)
    n = data.shape[0]
    keep = min(n, int(max_len * rate))
    data = data[:keep]
    n = keep

    spectrum = np.fft.rfft(data, axis=0)
    spectrum *= tone_curve(rate, n, curve_points)[:, None] if data.ndim > 1 \
        else tone_curve(rate, n, curve_points)
    shaped = np.fft.irfft(spectrum, n=n, axis=0)

    shaped *= (envelope(n, rate, tau, hold)[:, None] if shaped.ndim > 1
               else envelope(n, rate, tau, hold))
    peak = float(np.abs(shaped).max())
    if peak > 1e-9:
        shaped *= (10.0 ** (TARGET_PEAK_DB / 20.0)) / peak
    # Same length and framing as the original, so the .import cache stays valid.
    out = np.zeros((int(max_len * rate), channels), dtype=np.float64)
    out[:n] = shaped if shaped.ndim > 1 else shaped[:, None]
    if channels == 1:
        out = out[:, 0]

    if dry_run:
        return rate, out
    backup = os.path.join(BACKUP, os.path.basename(path))
    os.makedirs(BACKUP, exist_ok=True)
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
    write_wav(path, rate, out)
    return rate, out


def report(name: str, rate: int, data: np.ndarray) -> None:
    mono = data.mean(axis=1) if data.ndim > 1 else data
    bands = [(0, 200), (200, 800), (800, 2000), (2000, 4000), (4000, 7000),
             (7000, 12000), (12000, 22050)]
    n = len(mono)
    spec = np.abs(np.fft.rfft(mono * np.hanning(n)))
    freqs = np.fft.rfftfreq(n, 1.0 / rate)
    total = float((spec ** 2).sum())
    parts = []
    for lo, hi in bands:
        mask = (freqs >= lo) & (freqs < hi)
        parts.append(10 * np.log10((spec[mask] ** 2).sum() / total + 1e-12))
    seg = max(1, n // 40)
    env = [float(np.sqrt(np.mean(mono[i * seg:(i + 1) * seg] ** 2))) for i in range(40)]
    tail = sum(env[-8:]) / max(sum(env[:8]), 1e-9)
    print("  %-20s len %.3f s  hiss(7k+) %5.1f dB  tail/head %.2f" % (
        name, n / float(rate), parts[5] + parts[6], tail))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    for name, curve, tau, max_len, hold in JOBS:
        path = os.path.join(CORE, name)
        if not os.path.exists(path):
            print("  missing %s" % name)
            continue
        rate, out = process(path, curve, tau, max_len, hold, args.dry_run)
        report(name, rate, out)
    print("backups in %s" % BACKUP)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
