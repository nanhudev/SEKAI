"""Prepare one Suno render for the game.

Audio line (B) tool. Takes whatever Suno downloaded (mp3/wav, any length,
silence at the edges) and writes a dry, trimmed, peak-safe mono WAV into
`godot/audio/sfx/`.

Usage:
    python audio_source/tools/prepare_cue.py RAW CUE_ID [--dur 0.18]
        [--peak -1.0] [--mono] [--target-lufs -20] [--report-only]

FFMPEG path: set FFMPEG env var, default D:/oopz/ffmpeg.exe
"""

import argparse
import os
import re
import subprocess
import sys

FFMPEG = os.environ.get("FFMPEG", r"D:\oopz\ffmpeg.exe")
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "godot", "audio", "sfx")


def run(args):
    proc = subprocess.run(args, capture_output=True, text=True)
    return proc


def measure_peak(path):
    proc = run([FFMPEG, "-hide_banner", "-i", path,
                "-af", "astats=metadata=1:reset=0", "-f", "null", "-"])
    peaks = [float(m) for m in re.findall(r"Peak_level dB: ([-\d.]+)", proc.stderr)]
    return max(peaks) if peaks else None


def measure_lufs(path):
    proc = run([FFMPEG, "-hide_banner", "-i", path,
                "-af", "ebur128=framelog=quiet", "-f", "null", "-"])
    tail = proc.stderr.strip().splitlines()
    integrated = None
    for line in tail:
        if "I:" in line and "LUFS" in line:
            m = re.search(r"I:\s*([-\d.]+)\s*LUFS", line)
            if m:
                integrated = float(m.group(1))
    return integrated


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("raw")
    parser.add_argument("cue_id")
    parser.add_argument("--dur", type=float, default=0.0, help="target length in seconds, 0 = keep")
    parser.add_argument("--peak", type=float, default=-1.0, help="target peak dBFS")
    parser.add_argument("--target-lufs", type=float, default=None,
                        help="loudness target in LUFS (measured, then peak-limited)")
    parser.add_argument("--mono", action="store_true", default=True)
    parser.add_argument("--report-only", action="store_true")
    parser.add_argument("--out", default=OUT_DIR)
    args = parser.parse_args()

    raw = os.path.abspath(args.raw)
    if not os.path.exists(raw):
        sys.exit("raw file not found: %s" % raw)
    if not os.path.exists(FFMPEG):
        sys.exit("ffmpeg not found at %s (set FFMPEG env var)" % FFMPEG)

    peak = measure_peak(raw)
    lufs = measure_lufs(raw)
    print("%s  peak=%s dBFS  I=%s LUFS" % (os.path.basename(raw), peak, lufs))
    if args.report_only:
        return

    # 1. strip edge silence, 2. force length, 3. micro fades so no click,
    # 4. gain to target peak.
    chain = [
        "silenceremove=start_periods=1:start_duration=0.01:start_threshold=-50dB:detection=peak",
        "areverse",
        "silenceremove=start_periods=1:start_duration=0.01:start_threshold=-50dB:detection=peak",
        "areverse",
    ]
    if args.dur > 0.0:
        chain.append("apad")
        chain.append("atrim=0:%.4f" % args.dur)
        chain.append("afade=t=in:st=0:d=0.003")
        chain.append("afade=t=out:st=%.4f:d=0.008" % max(0.0, args.dur - 0.008))
    if args.mono:
        chain.append("aresample=44100")
        chain.append("pan=mono|c0=.5*c0+.5*c1")
    if args.target_lufs is not None and lufs is not None:
        chain.append("volume=%.2fdB" % (args.target_lufs - lufs))
    if peak is not None:
        # after loudness alignment re-measure and pull the peak down if needed
        chain.append("alimiter=limit=%.4f" % (10 ** (args.peak / 20.0)))
    else:
        chain.append("volume=0dB")

    os.makedirs(args.out, exist_ok=True)
    out_path = os.path.join(args.out, "%s.wav" % args.cue_id)
    proc = run([FFMPEG, "-hide_banner", "-y", "-i", raw,
                "-af", ",".join(chain),
                "-ar", "44100", "-ac", "1", "-c:a", "pcm_s16le", out_path])
    if proc.returncode != 0:
        sys.exit(proc.stderr[-2000:])
    new_peak = measure_peak(out_path)
    new_lufs = measure_lufs(out_path)
    print("wrote %s  peak=%s dBFS  I=%s LUFS" % (out_path, new_peak, new_lufs))


if __name__ == "__main__":
    main()
