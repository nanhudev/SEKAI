#!/usr/bin/env python3
"""
The captured chain timeline -> two listenable stems.

Input is the JSON `godot/tools/capture_chain_audio.gd` writes: the cue ids the
real ChainAudioDirector decided to fire, on the clock the real ChainDirector ran
at, plus the cue table and the atom groups read out of the engine.

Nothing about the mix is re-authored here. The cue table says what a cue is made
of, the capture says when it happened, and this file only does arithmetic:

    for every layer:  gain = atom trim + layer gain + cue gain
                      pitch = layer pitch x atom pitch (Godot's pitch_scale
                              changes speed AND pitch, so this resamples)
                      at    = event time + layer delay

Outputs
    chain_atoms_dry.wav        every cue solo, in table order - the DRY ATOM SHEET
    chain_sequence_pass01.wav  the captured performance, in real time

Usage
    python audio_source/tools/mix_chain_demo.py --capture capture.json \
        --out-dir F:/SEKAI/audio_source/processed/demo

`--godot-root` is the GODOT PROJECT dir (the one holding project.godot), i.e.
`F:/SEKAI/godot` - NOT the repo root. `res://` is relative to the project dir, so
pointing it at the repo root silently resolves every single atom to a missing
file and renders a stem of pure silence.
"""
from __future__ import annotations
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import argparse
import json
import random
import re
import wave
from pathlib import Path

import numpy as np

RATE = 48000
SHEET_GAP = 0.55
SHEET_LEAD = 0.35
PEAK_DB = -1.5
# Fixed, so the demo is reproducible. Godot randomises pitch inside each atom's
# own small range and alternates variants; this mirrors the alternation exactly
# and freezes the jitter, because a stem that changes every time it is rendered
# cannot be A/B'd against anything.
SEED = 20260928


def read_wav(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as handle:
        channels = handle.getnchannels()
        frames = handle.readframes(handle.getnframes())
    data = np.frombuffer(frames, dtype="<i2").astype(np.float64) / 32768.0
    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)
    return data


def write_wav(path: Path, data: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(data * 32767.0, -32768.0, 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(pcm.tobytes())


def resample(data: np.ndarray, factor: float) -> np.ndarray:
    """`factor` > 1 = shorter and higher, like AudioStreamPlayer.pitch_scale."""
    if abs(factor - 1.0) < 1e-6:
        return data
    n = max(2, int(round(len(data) / factor)))
    src = np.arange(len(data), dtype=np.float64)
    dst = np.linspace(0.0, len(data) - 1.0, n)
    return np.interp(dst, src, data)


def db(value: float) -> float:
    return 10.0 ** (value / 20.0)


def res_to_path(godot_root: Path, res: str) -> Path:
    # `res://` is the GODOT PROJECT root, not the repo root. `Path` already treats
    # "/" as a separator on Windows, so the old `.replace("/", str(Path("/")))`
    # only added a way to be wrong.
    return godot_root / re.sub(r"^res://", "", res)


class ChainMix:
    def __init__(self, doc: dict, godot_root: Path):
        self.groups = doc["table"]["groups"]
        self.cues = {cue["id"]: cue for cue in doc["table"]["cues"]}
        self.missing = doc["table"].get("missing", [])
        self.godot_root = godot_root
        self.rng = random.Random(SEED)
        self._cursor: dict[str, int] = {}
        self._sample_cache: dict[str, np.ndarray] = {}
        self.unresolved: list[str] = []

    def pick(self, group: str):
        atoms = self.groups.get(group) or []
        if not atoms:
            if group not in self.unresolved:
                self.unresolved.append(group)
            return None
        index = self._cursor.get(group, -1) + 1
        if index >= len(atoms):
            index = 0
        self._cursor[group] = index
        return atoms[index]

    def sample(self, res: str) -> np.ndarray | None:
        if res not in self._sample_cache:
            path = res_to_path(self.godot_root, res)
            if not path.exists():
                return None
            self._sample_cache[res] = read_wav(path)
        return self._sample_cache[res]

    def render_cue(self, cue_id: str) -> np.ndarray:
        cue = self.cues.get(cue_id)
        if cue is None:
            self.unresolved.append("cue:" + cue_id)
            return np.zeros(1)
        total = 0
        pieces: list[tuple[int, np.ndarray]] = []
        for layer in cue["layers"]:
            atom = self.pick(layer["group"])
            if atom is None:
                if not layer["optional"]:
                    self.unresolved.append("required:" + layer["group"])
                continue
            data = self.sample(atom["path"])
            if data is None:
                self.unresolved.append("file:" + atom["path"])
                continue
            pitch = layer["pitch"] * self.rng.uniform(atom["pitch_min"], atom["pitch_max"])
            data = resample(data, pitch)
            gain = db(atom["base_gain_db"] + layer["gain_db"] + cue["gain_db"])
            offset = int(round(layer["delay"] * RATE))
            pieces.append((offset, data * gain))
            total = max(total, offset + len(data))
        if total == 0:
            return np.zeros(1)
        out = np.zeros(total)
        for offset, piece in pieces:
            out[offset:offset + len(piece)] += piece
        return out

    def mix_events(self, events: list[dict], lead: float = 0.05) -> np.ndarray:
        rendered: list[tuple[int, np.ndarray]] = []
        end = 0
        for event in events:
            data = self.render_cue(event["cue"])
            start = int(round((lead + float(event["t"])) * RATE))
            rendered.append((start, data))
            end = max(end, start + len(data))
        out = np.zeros(max(1, end + int(0.4 * RATE)))
        for start, data in rendered:
            out[start:start + len(data)] += data
        return out


def cue_order(doc: dict) -> list[str]:
    """Table order, which is the order the cue table reads like."""
    return [cue["id"] for cue in doc["table"]["cues"]]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--capture", required=True, help="JSON from capture_chain_audio.gd")
    ap.add_argument("--godot-root", default=str(_SEKAI_ROOT / 'godot'),
                    help="Godot PROJECT dir (contains project.godot)")
    ap.add_argument("--out-dir", default=str(_SEKAI_ROOT / 'audio_source/processed/demo'))
    args = ap.parse_args()

    raw = Path(args.capture).read_text(encoding="utf-8")
    start = raw.find("SEKAI_CHAIN_CAPTURE_BEGIN")
    end = raw.find("SEKAI_CHAIN_CAPTURE_END")
    if start >= 0 and end > start:
        raw = raw[start + len("SEKAI_CHAIN_CAPTURE_BEGIN"):end]
    doc = json.loads(raw.strip())
    if doc.get("error"):
        print("capture failed: %s" % doc["error"])
        return 1

    godot_root = Path(args.godot_root)
    # Fail loudly rather than render silence: every atom is `res://`-relative, so a
    # wrong root turns the whole stem into a valid-looking, completely empty file.
    if not (godot_root / "project.godot").exists():
        print("--godot-root must be the Godot PROJECT dir (contains project.godot).")
        print("  got: %s" % godot_root)
        return 1
    out_dir = Path(args.out_dir)
    mix = ChainMix(doc, godot_root)

    # ---------------------------------------------------------- the dry sheet
    names = cue_order(doc)
    sheet_parts: list[np.ndarray] = [np.zeros(int(SHEET_LEAD * RATE))]
    cursor = 0
    marks: list[tuple[float, str]] = []
    for name in names:
        cue = mix.cues.get(name)
        data = mix.render_cue(name)
        marks.append((cursor / RATE, "%s  (%s)" % (name, (cue or {}).get("intent", ""))))
        sheet_parts.append(data)
        gap = np.zeros(int(SHEET_GAP * RATE))
        sheet_parts.append(gap)
        cursor += len(data) + len(gap)
    sheet = np.concatenate(sheet_parts)

    # ------------------------------------------------------ the performance
    sequence = mix.mix_events(doc["events"])

    for data, name, headroom in (
        (sheet, "chain_atoms_dry.wav", PEAK_DB),
        (sequence, "chain_sequence_pass01.wav", PEAK_DB),
    ):
        peak = float(np.abs(data).max()) or 1.0
        data = data * (10.0 ** (headroom / 20.0)) / peak
        write_wav(out_dir / name, data)
        print("%-30s %.2fs  peak %.1f dBFS" % (
            name, len(data) / RATE, headroom))

    print("\n--- DRY ATOM SHEET (%d cues, %.1fs)" % (len(names), cursor / RATE))
    for t, label in marks:
        print("  %6.2fs  %s" % (t, label))

    print("\n--- PERFORMANCE (%d cues)" % len(doc["events"]))
    for event in doc["events"]:
        print("  %6.2fs  %s" % (float(event["t"]), event["cue"]))
    for note in doc.get("notes", []):
        print("  note: %s" % note)
    if mix.unresolved:
        print("\nSILENT LAYERS (no atom / no file):")
        for item in dict.fromkeys(mix.unresolved):
            print("  ! %s" % item)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
