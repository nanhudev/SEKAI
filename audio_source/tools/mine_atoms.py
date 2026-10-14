#!/usr/bin/env python
"""Mine short, bright, dry transients out of the Suno raw captures.

The library is missing crystalline glass ticks and a wood scabbard tick. Those
are exactly the kind of event Suno renders as ONE isolated click inside a much
longer bed, so instead of spending new generation quota we scan the captures we
already have for events that are:

    short        20 - 250 ms
    bright       spectral centroid above ~3.5 kHz
    dry          energy collapses right after the onset (fast decay)
    isolated     quiet immediately before the onset

Everything it finds is written as a candidate wav for a human to audition.
Nothing is installed into the game library automatically.

Usage:
    python audio_source/tools/mine_atoms.py [--source glass] [--top 6]
"""

import argparse
import os
import struct
import wave

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RAW = os.path.join(ROOT, "suno", "raw")
OUT = os.path.join(ROOT, "processed", "candidates")

# Where the actual content starts (capture latency) and where the queue's
# next clip starts leaking in. See raw/CAPTURE_MANIFEST.md.
SKIP_HEAD = 1.40
SKIP_TAIL = 2.00

TARGET_PEAK_DB = -6.0
PRE_ROLL = 0.006
POST_ROLL = 0.120
MAX_LEN = 0.300


def read_wav(path: str):
    with wave.open(path, "rb") as handle:
        rate = handle.getframerate()
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        raw = handle.readframes(handle.getnframes())
    if width != 2:
        raise SystemExit("expected 16-bit pcm: %s" % path)
    data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)
    return rate, data


def analyse(rate: int, data: np.ndarray):
    hop = 256
    win = 512
    frames = 1 + (len(data) - win) // hop
    if frames <= 1:
        return None
    window = np.hanning(win)
    rms = np.zeros(frames)
    centroid = np.zeros(frames)
    freqs = np.fft.rfftfreq(win, 1.0 / rate)
    for i in range(frames):
        block = data[i * hop:i * hop + win] * window
        rms[i] = float(np.sqrt(np.mean(block * block)))
        spectrum = np.abs(np.fft.rfft(block))
        total = spectrum.sum()
        centroid[i] = float((freqs * spectrum).sum() / total) if total > 1e-9 else 0.0
    return {"hop": hop, "rate": rate, "rms": rms, "centroid": centroid}


def find_events(result: dict, start_sample: int, end_sample: int):
    hop = result["hop"]
    rate = result["rate"]
    rms = result["rms"]
    centroid = result["centroid"]
    frame_time = hop / float(rate)
    first = int(start_sample / hop)
    last = int(end_sample / hop)
    if last - first < 4:
        return []

    loud = rms.copy()
    loud[loud <= 0] = 1e-9
    # isolation: how much louder this frame is than the 300 ms before it
    pad = max(1, int(0.300 / frame_time))
    before = np.zeros_like(loud)
    before[pad:] = rms[:-pad]
    before[:pad] = rms[:pad].mean()
    isolation = loud / np.maximum(before, 1e-9)

    events = []
    index = first
    while index < last:
        bright = centroid[index] > 3500.0
        strong = rms[index] > 0.02
        isolated = isolation[index] > 2.2
        if bright and strong and isolated:
            begin = index
            while index < last and rms[index] > 0.012 and index - begin < int(0.25 / frame_time):
                index += 1
            end = index
            duration = (end - begin) * frame_time
            if duration < 0.012:
                index += 1
                continue
            peak = float(rms[begin:end].max())
            tail_start = min(last - 1, end + int(0.080 / frame_time))
            decay = float(rms[end:tail_start].max()) if tail_start > end else 0.0
            decay_ratio = 1.0 - min(1.0, decay / max(peak, 1e-9))
            # Isolation is capped: a frame after true silence scores millions
            # and would bury every other candidate. Decay is what makes an
            # event read as DRY, so it carries real weight.
            score = (centroid[begin:end].mean() / 1000.0) \
                * min(isolation[begin], 25.0) ** 0.5 * (0.3 + decay_ratio)
            events.append({
                "start": begin * frame_time,
                "end": end * frame_time,
                "duration": duration,
                "centroid": float(centroid[begin:end].mean()),
                "isolation": float(isolation[begin]),
                "decay": decay_ratio,
                "peak": peak,
                "score": float(score),
            })
        else:
            index += 1
    return events


def write_candidate(path: str, rate: int, data: np.ndarray, start: float, end: float) -> None:
    a = max(0, int((start - PRE_ROLL) * rate))
    b = min(len(data), int((end + POST_ROLL) * rate))
    if (b - a) / float(rate) > MAX_LEN:
        b = a + int(MAX_LEN * rate)
    chunk = data[a:b].astype(np.float32).copy()
    length = len(chunk)
    if length < 32:
        return
    # Dry means dry: a 2 ms fade in kills the click artefact, the tail fade is
    # longer because the natural decay is part of the sound.
    fade_in = min(int(0.002 * rate), length // 8)
    fade_out = min(int(0.035 * rate), length // 3)
    chunk[:fade_in] *= np.linspace(0.0, 1.0, fade_in)
    chunk[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)
    peak = float(np.abs(chunk).max())
    if peak > 1e-6:
        chunk *= (10.0 ** (TARGET_PEAK_DB / 20.0)) / peak
    pcm = np.clip(chunk * 32767.0, -32768.0, 32767.0).astype("<i2")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(pcm.tobytes())


SOURCES = {
    "glass": ["suno_cap_glass_stress_A.wav", "suno_cap_glass_stress_B.wav",
              "suno_cap_glass_shatter_A.wav", "suno_cap_glass_shatter_B.wav"],
    "wood": ["suno_cap_sword_handling_A.wav", "suno_cap_sword_handling_B.wav",
             "suno_cap_sheath_click_A.wav", "suno_cap_sheath_click_B.wav"],
    "air": ["suno_cap_draw_slash_A.wav", "suno_cap_draw_slash_B.wav",
            "suno_cap_air_suck_A.wav", "suno_cap_air_suck_B.wav"],
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default="glass", choices=sorted(SOURCES.keys()))
    parser.add_argument("--top", type=int, default=6)
    # A tick is not a crack. Anything longer than this is a sustained event and
    # is useless as an atom, no matter how bright it is.
    parser.add_argument("--max-dur", type=float, default=0.090)
    parser.add_argument("--post-roll", type=float, default=0.050)
    parser.add_argument("--max-len", type=float, default=0.130)
    args = parser.parse_args()
    globals()["POST_ROLL"] = args.post_roll
    globals()["MAX_LEN"] = args.max_len

    found = []
    for name in SOURCES[args.source]:
        path = os.path.join(RAW, name)
        if not os.path.exists(path):
            print("  missing %s" % name)
            continue
        rate, data = read_wav(path)
        start_sample = int(SKIP_HEAD * rate)
        end_sample = max(start_sample + rate, len(data) - int(SKIP_TAIL * rate))
        result = analyse(rate, data)
        if result is None:
            continue
        for event in find_events(result, start_sample, end_sample):
            event["file"] = name
            found.append(event)
    found = [item for item in found if item["duration"] <= args.max_dur]
    if not found:
        print("no candidates found in %s sources (try --max-dur)" % args.source)
        return 1

    found.sort(key=lambda item: item["score"], reverse=True)
    print("%-28s %6s %6s %7s %7s %6s" % ("candidate", "start", "len", "centrd", "isol", "decay"))
    for rank, event in enumerate(found[:args.top]):
        out = os.path.join(OUT, "%s_cand_%02d.wav" % (args.source, rank + 1))
        rate, data = read_wav(os.path.join(RAW, event["file"]))
        write_candidate(out, rate, data, event["start"], event["end"])
        print("%-28s %6.2f %6.3f %7.0f %7.2f %6.2f" % (
            os.path.basename(out), event["start"], event["duration"],
            event["centroid"], event["isolation"], event["decay"]))
    print("wrote %d candidate(s) to %s" % (min(args.top, len(found)), OUT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
