"""Build Iaido cues + core sound atoms from Suno raw captures.

SELECT -> TRIM -> CLEAN -> LEVEL pipeline. Every entry carries provenance
(source file, section, rationale) and a target peak. Fades are baked so a
hard stop in Godot never clicks. Relative hierarchy is applied in Godot
(iaido_audio_timeline.gd volume_db); here everything lands at its own
musical peak inside -8..-1.5 dBFS with headroom.

Usage:
    python build_iaido_cues.py            # build into ../processed/
    python build_iaido_cues.py --install  # also copy into godot/audio/sfx/
"""

import math
import os
import shutil
import struct
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.normpath(os.path.join(HERE, "..", "suno", "raw"))
OUT = os.path.normpath(os.path.join(HERE, "..", "processed"))

FADE_IN = 0.008

# (output, source, start, length, target_peak_db, fade_out)
# Sections chosen from SFX_SELECTION.md / CAPTURE_MANIFEST.md onsets.
CUES = [
    # --- Iaido signature timeline (godot/audio/sfx/iaido/) ---
    ("iaido/world_suck.wav",        "suno_cap_air_suck_A.wav",        1.35, 0.45, -6.0, 0.06),
    ("iaido/sheath_move.wav",       "suno_cap_sword_handling_A.wav",  4.30, 0.40, -8.0, 0.08),
    ("iaido/reverse_compression.wav","suno_cap_spatial_compress_A.wav",1.52, 0.78, -6.0, 0.10),
    ("iaido/pressure_thud.wav",     "suno_cap_space_tear_A.wav",      5.90, 0.24, -7.0, 0.07),
    ("iaido/sheath_lock.wav",       "suno_cap_sheath_click_A.wav",    2.64, 0.13, -5.0, 0.03),
    ("iaido/draw.wav",              "suno_cap_draw_slash_A.wav",      1.09, 0.30, -5.0, 0.05),
    ("iaido/reality_cut.wav",       "suno_cap_draw_slash_A.wav",      1.52, 0.34, -4.0, 0.05),
    ("iaido/void_open.wav",         "suno_cap_space_tear_A.wav",      2.55, 0.62, -6.0, 0.12),
    ("iaido/glass_stress.wav",      "suno_cap_glass_stress_A.wav",    1.10, 0.68, -7.0, 0.10),
    ("iaido/glass_detach.wav",      "suno_cap_glass_shatter_A.wav",   1.05, 0.38, -7.0, 0.06),
    ("iaido/spin.wav",              "suno_cap_sword_handling_A.wav",  1.05, 0.45, -7.0, 0.07),
    ("iaido/slow_sheathe.wav",      "suno_cap_sword_handling_A.wav",  4.30, 0.88, -7.5, 0.10),
    ("iaido/final_sheathe.wav",     "suno_cap_sheath_click_A.wav",    4.60, 0.22, -4.0, 0.04),
    ("iaido/reality_collapse.wav",  "suno_cap_glass_shatter_B.wav",  11.40, 0.82, -3.0, 0.14),
    ("iaido/reality_restore.wav",   "suno_cap_reality_restore_A.wav", 1.76, 0.32, -6.0, 0.08),
    # --- Core sound atoms (godot/audio/sfx/core/) ---
    ("core/metal_sharp_01.wav",  "suno_cap_sheath_click_A.wav",   2.66, 0.07, -6.0, 0.02),
    ("core/metal_sharp_02.wav",  "suno_cap_sheath_click_B.wav",   2.66, 0.07, -6.0, 0.02),
    ("core/metal_body_01.wav",   "suno_cap_sheath_click_A.wav",   4.62, 0.14, -6.0, 0.04),
    ("core/air_fast_01.wav",     "suno_cap_draw_slash_A.wav",     1.10, 0.35, -6.0, 0.06),
    ("core/air_fast_02.wav",     "suno_cap_draw_slash_B.wav",     1.08, 0.35, -6.0, 0.06),
    ("core/air_low_01.wav",      "suno_cap_space_tear_A.wav",     4.02, 0.55, -8.0, 0.10),
    ("core/body_low_01.wav",     "suno_cap_space_tear_A.wav",     5.20, 0.60, -9.0, 0.14),
    ("core/cloth_fast_01.wav",   "suno_cap_sword_handling_A.wav", 3.88, 0.28, -9.0, 0.06),
    ("core/glass_tick_01.wav",   "suno_cap_glass_stress_A.wav",   1.58, 0.08, -8.0, 0.02),
    ("core/glass_crack_01.wav",  "suno_cap_glass_shatter_A.wav",  1.05, 0.30, -6.0, 0.05),
    ("core/glass_crack_02.wav",  "suno_cap_glass_shatter_B.wav",  4.30, 0.30, -6.0, 0.05),
    ("core/wind_pressure_01.wav","suno_cap_spatial_compress_A.wav",1.55, 0.70, -8.0, 0.12),
]


def read_wav(path):
    with wave.open(path, "rb") as w:
        n, rate, ch, width = w.getnframes(), w.getframerate(), w.getnchannels(), w.getsampwidth()
        assert width == 2 and rate == 44100, "%s: expected 44.1k s16" % path
        raw = w.readframes(n)
    frames = struct.unpack("<%dh" % (n * ch), raw)
    return frames, rate, ch


def write_wav(path, frames, rate, ch):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack("<%dh" % len(frames), *frames))


def build_one(src_path, start, length, peak_db, fade_out):
    frames, rate, ch = read_wav(src_path)
    i0 = int(start * rate) * ch
    n = int(length * rate) * ch
    seg = list(frames[i0:i0 + n])
    if len(seg) < n:
        raise SystemExit("section beyond EOF in %s" % src_path)
    fi = int(FADE_IN * rate) * ch
    fo = int(fade_out * rate) * ch
    for i in range(min(fi, len(seg))):
        seg[i] = int(seg[i] * (i / fi))
    for i in range(min(fo, len(seg))):
        seg[-1 - i] = int(seg[-1 - i] * (i / fo))
    peak = max(1, max(abs(x) for x in seg))
    target = 10 ** (peak_db / 20.0) * 32767
    g = target / peak
    return [int(x * g) for x in seg], rate, ch


def main():
    install = "--install" in sys.argv
    godot = os.path.normpath(os.path.join(HERE, "..", "..", "godot", "audio", "sfx"))
    for out_rel, src, start, length, peak_db, fade_out in CUES:
        src_path = os.path.join(RAW, src)
        frames, rate, ch = build_one(src_path, start, length, peak_db, fade_out)
        out_path = os.path.join(OUT, out_rel)
        write_wav(out_path, frames, rate, ch)
        dur = len(frames) / (rate * ch)
        line = "%-34s %.2fs  peak %.1f dB  <- %s @%.2f" % (
            out_rel, dur, peak_db, src, start)
        print(line)
        if install:
            dst = os.path.join(godot, out_rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(out_path, dst)
    if install:
        print("installed into", godot)


if __name__ == "__main__":
    main()
