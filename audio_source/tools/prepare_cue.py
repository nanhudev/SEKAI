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
    """Return (peak_dbfs, rms_dbfs, seconds) using astats.

    LUFS is useless on 0.2-1.0s one-shots, so level work uses RMS + peak.
    """
    proc = run([FFMPEG, "-hide_banner", "-i", path,
                "-af", "astats=metadata=1:reset=0", "-f", "null", "-"])
    err = proc.stderr
    peaks = [float(m) for m in re.findall(r"Peak level dB: ([-\d.eE+]+)", err)]
    rms = [float(m) for m in re.findall(r"RMS level dB: ([-\d.eE+]+)", err)]
    samples = [int(m) for m in re.findall(r"Number of samples: (\d+)", err)]
    rate = re.search(r"(\d+) Hz,", err)
    seconds = None
    if samples and rate:
        seconds = max(samples) / float(rate.group(1))
    return (max(peaks) if peaks else None,
            max(rms) if rms else None,
            seconds)


def measure_lufs(path):
    """Integrated LUFS, only meaningful above ~3 s. Returns None on failure."""
    proc = run([FFMPEG, "-hide_banner", "-i", path,
                "-af", "ebur128=framelog=quiet", "-f", "null", "-"])
    for line in proc.stderr.splitlines():
        m = re.search(r"^\s*I:\s*([-\d.]+)\s*LUFS", line)
        if m:
            value = float(m.group(1))
            return None if value == 0.0 else value
    return None


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

    peak, rms, seconds = measure_peak(raw)
    lufs = measure_lufs(raw) if (seconds is None or seconds >= 3.0) else None
    print("%s  dur=%s  peak=%s dBFS  rms=%s dBFS  I=%s LUFS" % (
        os.path.basename(raw),
        "%.2fs" % seconds if seconds else "?",
        "%.2f" % peak if peak is not None else "?",
        "%.2f" % rms if rms is not None else "?",
        "%.1f" % lufs if lufs is not None else "n/a",
    ))
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
    # NOTE: this ffmpeg build's alimiter does not cap as documented, so the
    # peak target is reached with a plain gain stage and clamped below 0 dBFS.

    os.makedirs(args.out, exist_ok=True)
    out_path = os.path.join(args.out, "%s.wav" % args.cue_id)
    tmp_path = out_path + ".tmp.wav"

    # Pass 1: shape (trim silence, force length, fades, mono).
    proc = run([FFMPEG, "-hide_banner", "-y", "-i", raw,
                "-af", ",".join(chain),
                "-ar", "44100", "-ac", "1", "-c:a", "pcm_s16le", tmp_path])
    if proc.returncode != 0:
        sys.exit(proc.stderr[-2000:])

    # Pass 2: normalise the shaped file to the target peak.
    tmp_peak, _rms, _dur = measure_peak(tmp_path)
    target = min(args.peak, -0.5)
    gain = 0.0
    if tmp_peak is not None:
        gain = target - tmp_peak
    proc = run([FFMPEG, "-hide_banner", "-y", "-i", tmp_path,
                "-af", "volume=%.2fdB" % gain,
                "-ar", "44100", "-ac", "1", "-c:a", "pcm_s16le", out_path])
    if proc.returncode != 0:
        sys.exit(proc.stderr[-2000:])
    if os.path.exists(tmp_path):
        os.remove(tmp_path)

    new_peak, new_rms, new_seconds = measure_peak(out_path)
    print("wrote %s  dur=%s  peak=%s dBFS  rms=%s dBFS" % (
        out_path,
        "%.2fs" % new_seconds if new_seconds else "?",
        "%.2f" % new_peak if new_peak is not None else "?",
        "%.2f" % new_rms if new_rms is not None else "?",
    ))


if __name__ == "__main__":
    main()
