"""Generate placeholder SFX for the Iaido / 聚合斩 signature skill.

Suno was not reachable in this pass, so the audio timeline is built with
synthesised placeholders that carry the right *drama* at the right *time*.
Replace each file with a real Suno render later; the trigger points in
`iaido_audio_timeline.gd` do not change.

Run:  python godot/tools/generate_iaido_placeholders.py
"""

import math
import os
import random
import struct
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio", "sfx")


def write_wav(name, samples):
    path = os.path.join(OUT_DIR, name)
    peak = max(abs(s) for s in samples) or 1.0
    gain = 0.92 / peak
    frames = bytearray()
    for s in samples:
        v = max(-1.0, min(1.0, s * gain))
        frames += struct.pack("<h", int(v * 32000))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    print("wrote %s (%.2fs)" % (name, len(samples) / float(SR)))


def noise(n, seed=0):
    rng = random.Random(seed)
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def lowpass_sweep(x, f0, f1):
    y = 0.0
    out = []
    n = max(1, len(x) - 1)
    for i, v in enumerate(x):
        f = f0 + (f1 - f0) * (i / n)
        a = math.exp(-2.0 * math.pi * max(f, 20.0) / SR)
        y = (1.0 - a) * v + a * y
        out.append(y)
    return out


def bandpass_sweep(x, lo0, lo1, hi0, hi1):
    a = lowpass_sweep(x, hi0, hi1)
    b = lowpass_sweep(x, lo0, lo1)
    return [p - q for p, q in zip(a, b)]


def env(n, fn):
    return [fn(i / max(1, n - 1)) for i in range(n)]


def ramp_up(n, p=1.0):
    return env(n, lambda t: t ** p)


def bell(n, attack=0.02, p=2.0):
    def f(t):
        if t < attack:
            return t / attack
        k = (t - attack) / max(1e-5, 1.0 - attack)
        return math.exp(-p * k * 3.0)
    return env(n, f)


def sine(freq, n, phase=0.0):
    return [math.sin(2.0 * math.pi * freq * i / SR + phase) for i in range(n)]


def mix(*layers):
    n = max(len(l) for l in layers)
    out = [0.0] * n
    for l in layers:
        for i, v in enumerate(l):
            out[i] += v
    return out


def pad(x, n):
    return list(x) + [0.0] * max(0, n - len(x))


# ---------------------------------------------------------------------------
# Cues
# ---------------------------------------------------------------------------

def cue_air_suck():
    """0.20s · the world's air is pulled out."""
    n = int(0.90 * SR)
    src = noise(n, 11)
    body = bandpass_sweep(src, 200.0, 90.0, 7000.0, 380.0)
    body = [b * e for b, e in zip(body, env(n, lambda t: math.sin(min(1.0, t / 0.55) * math.pi * 0.5) * (1.0 - max(0.0, (t - 0.72) / 0.28))))]
    sub = [s * e for s, e in zip(sine(96.0, n), env(n, lambda t: math.exp(-2.2 * t) * 0.25))]
    return mix(body, sub)


def cue_sheath_move():
    """0.80s · controlled blade travel back to the hip."""
    n = int(0.75 * SR)
    src = noise(n, 22)
    fric = bandpass_sweep(src, 700.0, 1500.0, 4200.0, 5200.0)
    fric = [f * e for f, e in zip(fric, env(n, lambda t: math.sin(min(1.0, t / 0.8) * math.pi) ** 1.4))]
    metal = [s * e for s, e in zip(sine(520.0, n), env(n, lambda t: 0.06 * math.sin(min(1.0, t / 0.8) * math.pi)))]
    low = [s * e for s, e in zip(sine(78.0, n), env(n, lambda t: 0.18 * math.sin(min(1.0, t / 0.8) * math.pi)))]
    return mix(fric, metal, low)


def cue_reverse_wave():
    """1.20s · air refraction collapsing inward. Not an energy ring."""
    n = int(1.15 * SR)
    src = noise(n, 33)
    swell = bandpass_sweep(src, 260.0, 2400.0, 900.0, 6500.0)
    # Reverse-sounding: amplitude climbs steadily then cuts hard.
    swell = [s * e for s, e in zip(swell, env(n, lambda t: (0.06 + 0.94 * (t ** 1.5)) * (1.0 - max(0.0, (t - 0.90) / 0.10))))]
    shimmer = [s * e for s, e in zip(sine(1180.0, n), env(n, lambda t: 0.05 * t ** 2.0))]
    deep = [s * e for s, e in zip(sine(58.0, n), env(n, lambda t: 0.20 * t))]
    return mix(swell, shimmer, deep)


def cue_pressure():
    """2.20s · very low pressure tone under the compression hold."""
    n = int(1.05 * SR)
    a = sine(41.0, n)
    b = [s * 0.6 for s in sine(61.5, n, 0.7)]
    c = [s * 0.35 for s in sine(82.0, n, 1.4)]
    bed = lowpass_sweep(noise(n, 44), 160.0, 90.0)
    bed = [x * 0.5 for x in bed]
    tone = mix(a, b, c, bed)
    return [t * e for t, e in zip(tone, env(n, lambda t: math.sin(min(1.0, t / 0.95) * math.pi) ** 0.8))]


def cue_lock_click():
    """2.85s · the sheath lock. Sharp, dry, small."""
    n = int(0.14 * SR)
    src = noise(n, 55)
    tick = bandpass_sweep(src, 1600.0, 1200.0, 9000.0, 7000.0)
    tick = [t * e for t, e in zip(tick, env(n, lambda t: math.exp(-34.0 * t)))]
    ping = [s * e for s, e in zip(sine(2150.0, n), env(n, lambda t: math.exp(-46.0 * t) * 0.55))]
    body = [s * e for s, e in zip(sine(240.0, n), env(n, lambda t: math.exp(-40.0 * t) * 0.35))]
    return mix(tick, ping, body)


def cue_draw():
    """2.97s · the instant draw. Fast bright swish."""
    n = int(0.24 * SR)
    src = noise(n, 66)
    swish = bandpass_sweep(src, 900.0, 5200.0, 3200.0, 11000.0)
    swish = [s * e for s, e in zip(swish, env(n, lambda t: math.exp(-11.0 * t) * min(1.0, t / 0.012)))]
    edge = [s * e for s, e in zip(sine(2600.0, n), env(n, lambda t: math.exp(-26.0 * t) * 0.30))]
    return mix(swish, edge)


def cue_world_cut():
    """3.10s · reality tears open."""
    n = int(0.60 * SR)
    src = noise(n, 77)
    tear = bandpass_sweep(src, 5200.0, 700.0, 12000.0, 3000.0)
    tear = [t * e for t, e in zip(tear, env(n, lambda t: math.exp(-6.5 * t) * min(1.0, t / 0.006)))]
    sub = [s * e for s, e in zip(sine(47.0, n), env(n, lambda t: math.exp(-4.5 * t) * 0.55))]
    shhk = [s * e for s, e in zip(bandpass_sweep(noise(n, 78), 2600.0, 1800.0, 8000.0, 5200.0), env(n, lambda t: math.exp(-14.0 * t) * 0.5))]
    return mix(tear, sub, shhk)


def cue_void_open():
    """3.40s · deep airless resonance behind the cut. NOT a sci-fi portal."""
    n = int(1.60 * SR)
    layers = []
    for freq, weight, phase in ((36.0, 1.0, 0.0), (54.0, 0.55, 0.9), (81.0, 0.30, 1.7), (108.0, 0.16, 2.4)):
        # Slow detune so it breathes instead of humming.
        tone = [math.sin(2.0 * math.pi * freq * (1.0 + 0.006 * math.sin(2.0 * math.pi * 0.22 * i / SR)) * i / SR + phase) * weight
                for i in range(n)]
        layers.append(tone)
    bed = lowpass_sweep(noise(n, 88), 240.0, 120.0)
    layers.append([b * 0.35 for b in bed])
    tone = mix(*layers)
    return [t * e for t, e in zip(tone, env(n, lambda t: (1.0 - math.exp(-7.0 * t)) * math.exp(-1.1 * t)))]


def cue_glass_stress():
    """4.25s · the world surface starts creaking."""
    n = int(0.65 * SR)
    src = noise(n, 99)
    creak = bandpass_sweep(src, 2200.0, 3400.0, 4800.0, 6200.0)
    flutter = [0.55 + 0.45 * math.sin(2.0 * math.pi * 17.0 * i / SR) for i in range(n)]
    creak = [c * f * e for c, f, e in zip(creak, flutter, env(n, lambda t: t ** 0.7))]
    grain = [s * e for s, e in zip(bandpass_sweep(noise(n, 100), 5200.0, 6000.0, 11000.0, 12000.0), env(n, lambda t: 0.18 * t))]
    return mix(creak, grain)


def cue_glass_break():
    """4.55s + 6.25s · glass fails and shards let go."""
    n = int(1.25 * SR)
    rng = random.Random(1234)
    out = [0.0] * n
    onset = bandpass_sweep(noise(n, 111), 3000.0, 900.0, 14000.0, 5000.0)
    for i, v in enumerate(onset):
        out[i] += v * math.exp(-16.0 * i / SR) * 0.9
    for _ in range(70):
        start = int(rng.uniform(0.02, 0.75) * SR)
        freq = rng.uniform(1400.0, 7200.0)
        length = int(rng.uniform(0.03, 0.14) * SR)
        decay = rng.uniform(18.0, 60.0)
        amp = rng.uniform(0.05, 0.28)
        for j in range(length):
            idx = start + j
            if idx >= n:
                break
            out[idx] += math.sin(2.0 * math.pi * freq * j / SR) * math.exp(-decay * j / SR) * amp
    tail = lowpass_sweep(noise(n, 112), 2200.0, 600.0)
    for i, v in enumerate(tail):
        out[i] += v * math.exp(-3.0 * i / SR) * 0.30
    return out


def cue_spin():
    """4.60s · two wrist-controlled blade revolutions: fast, then medium."""
    n = int(1.00 * SR)
    out = [0.0] * n
    for start_s, dur_s, lo, hi, amp in ((0.02, 0.36, 700.0, 4200.0, 0.9), (0.52, 0.46, 550.0, 3300.0, 0.75)):
        start = int(start_s * SR)
        length = int(dur_s * SR)
        seg = bandpass_sweep(noise(length, 121), lo, hi, lo * 3.4, hi * 2.1)
        for j, v in enumerate(seg):
            idx = start + j
            if idx >= n:
                break
            t = j / float(length)
            out[idx] += v * math.sin(min(1.0, t) * math.pi) ** 1.2 * amp
    return out


def cue_slow_sheathe():
    """5.50s · blade friction, slowing as it nears the mouth."""
    n = int(0.90 * SR)
    src = noise(n, 131)
    fric = bandpass_sweep(src, 800.0, 1900.0, 3800.0, 6200.0)
    # Speed curve: normal, then clearly slower.
    speed = lambda t: 1.0 if t < 0.5 else (0.6 if t < 0.8 else 0.3)
    fric = [f * e * speed(t) for f, e, t in
            ((f, e, i / float(n - 1)) for i, (f, e) in enumerate(zip(fric, env(n, lambda t: math.sin(min(1.0, t / 0.95) * math.pi) ** 1.1))))]
    metal = [s * e for s, e in zip(sine(690.0, n), env(n, lambda t: 0.05 * math.sin(min(1.0, t / 0.95) * math.pi)))]
    return mix(fric, metal)


def cue_final_click():
    """6.20s · the final sheathing click. Lower and heavier than the lock."""
    n = int(0.30 * SR)
    src = noise(n, 141)
    tick = bandpass_sweep(src, 900.0, 500.0, 6000.0, 3200.0)
    tick = [t * e for t, e in zip(tick, env(n, lambda t: math.exp(-22.0 * t)))]
    body = [s * e for s, e in zip(sine(148.0, n), env(n, lambda t: math.exp(-18.0 * t) * 0.75))]
    mid = [s * e for s, e in zip(sine(410.0, n), env(n, lambda t: math.exp(-30.0 * t) * 0.45))]
    ring = [s * e for s, e in zip(sine(1240.0, n), env(n, lambda t: math.exp(-26.0 * t) * 0.25))]
    return mix(tick, body, mid, ring)


def cue_reality_restore():
    """6.80s · the void and the shards are drawn back; reality reconnects."""
    n = int(1.05 * SR)
    src = noise(n, 151)
    # Reverse-suck: rises then settles, opposite of the break.
    suck = bandpass_sweep(src, 2400.0, 300.0, 6500.0, 900.0)
    suck = [s * e for s, e in zip(suck, env(n, lambda t: math.sin(min(1.0, t / 0.85) * math.pi) ** 1.3))]
    tone = [s * e for s, e in zip(sine(62.0, n), env(n, lambda t: math.exp(-1.6 * t) * 0.35))]
    out = mix(suck, tone)
    # Reality reconnect pulse at the very end: tiny, never a big shake.
    pulse_start = int(0.80 * SR)
    for j in range(int(0.06 * SR)):
        idx = pulse_start + j
        if idx < n:
            out[idx] += math.sin(2.0 * math.pi * 320.0 * j / SR) * math.exp(-38.0 * j / SR) * 0.30
    return out


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    cues = [
        ("iaido_air_suck.wav", cue_air_suck),
        ("iaido_sheath_move.wav", cue_sheath_move),
        ("iaido_reverse_wave.wav", cue_reverse_wave),
        ("iaido_pressure.wav", cue_pressure),
        ("iaido_lock_click.wav", cue_lock_click),
        ("iaido_draw.wav", cue_draw),
        ("iaido_world_cut.wav", cue_world_cut),
        ("iaido_void_open.wav", cue_void_open),
        ("iaido_glass_stress.wav", cue_glass_stress),
        ("iaido_glass_break.wav", cue_glass_break),
        ("iaido_spin.wav", cue_spin),
        ("iaido_slow_sheathe.wav", cue_slow_sheathe),
        ("iaido_final_click.wav", cue_final_click),
        ("iaido_reality_restore.wav", cue_reality_restore),
    ]
    for name, fn in cues:
        write_wav(name, fn())


if __name__ == "__main__":
    main()
