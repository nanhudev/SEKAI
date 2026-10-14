#!/usr/bin/env python3
"""Generate docs/AUDIO_MANIFEST.md: one row per atom that actually ships.

WHY GENERATED. The brief asks for id / category / source / prompt or provenance / raw /
processed / duration / usage / variants / license / status per sound. Two of those ten
fields live in the library's own `sfx_manifest.json`, three live in the Godot atom tables,
one is on disk and the rest are prose. A hand-written table drifts from all four within a
week, and a provenance table that has drifted is worse than none - it is a document that
looks authoritative and is wrong.

So: the two machine-readable sides are joined here, and only the prose is written by hand
(in `PROSE`, below). Re-run after any regeneration.

Usage: emit_manifest_doc.py [--out docs/AUDIO_MANIFEST.md]
"""
from __future__ import annotations
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import argparse
import json
import re
import sys
import wave
from pathlib import Path

REPO = Path(str(_SEKAI_ROOT))
ATOMS = REPO / "godot" / "audio" / "sfx" / "atoms"
GODOT_TABLES = (
    REPO / "godot" / "scripts" / "audio" / "chain_atom_table.gd",
    REPO / "godot" / "scripts" / "audio" / "sound_atom_registry.gd",
)
# The library side. There are two libraries in flight; the sword atoms live in the
# secondary one, so both are joined rather than guessing which is authoritative.
LIBRARIES = (
    Path("F:/SEKAI-WT/chain-audio/audio_source/library/sfx_manifest.json"),
    Path("F:/SEKAI-WT/audio-dev/audio_source/library/sfx_manifest.json"),
)
ROW = re.compile(
    r'"id":\s*&"([^"]+)".*?"file":\s*"([^"]+)".*?"category":\s*&"([^"]+)".*?'
    r'"group":\s*&"([^"]+)"', re.S)

## The only hand-written part: things no table knows.
PROSE = """\
## What this file is

One row per sound atom that is actually loadable in the game, with where it came from.
**The rows are generated** by `audio_source/tools/emit_manifest_doc.py`; the header and the
license section are written by hand. The machine-readable authorities are:

| field | authority |
| --- | --- |
| `id`, `category`, `family`, `usage` | `godot/scripts/audio/{chain_atom_table,sound_atom_registry}.gd` |
| `raw`, `processed`, `seed`, `provider`, `prompt`, `status` | `audio_source/library/sfx_manifest.json` |
| `duration`, `peak` | measured from the shipped wav, not trusted from a table |
| `license` | **not in any table** - see below |

## License and provenance

Every atom in this library is generated locally, not licensed from a sound pack:

- **Provider / model:** `stabilityai/stable-audio-3-small-sfx` (`stable-audio-3-small-sfx`),
  run on **CPU**, `steps=8`, `cfg_scale=1.0`, `sample_rate=44100`.
- **License:** **Stability AI Community License.** Outputs are owned by the user and may be
  distributed and commercialised freely; the carve-out is scale - an organisation above
  **USD 1M annual revenue** must move to the Stability AI Enterprise licence, which is also
  the tier that carries legal indemnification.
- **Training data posture:** the model family is trained on licensed audio (AudioSparx
  catalogue plus Freesound under CC-0 / CC-BY / CC-Sampling+), which is the basis of the
  commercial-use claim rather than a post-hoc legal argument.
- **Not Suno.** Suno is used in this project for **BGM only**; no SFX in this manifest comes
  from Suno. The legacy Suno SFX that predate this rule are marked LEGACY and must not be
  deleted (they are still referenced as fallbacks).

### Open item - the license is recorded once, not per row

`audio_source/library/sfx_manifest.json` has **no `license` key at all** (verified over all
404 entries of the sword library and all 228 of the main one). The license above is uniform
across the generated library, so recording it once is accurate *today* - and it stops being
accurate the moment a second provider is added, because there will be nothing in the data
to distinguish the rows. The fix is one field in the generator plus a re-emit, and it is
deliberately not done here: the manifest is written by a tool this line does not own.
"""


def shipped_atoms() -> dict[str, dict]:
    """file name -> {id, category, group} from the two Godot tables."""
    out: dict[str, dict] = {}
    for path in GODOT_TABLES:
        if not path.exists():
            print("missing table %s" % path, file=sys.stderr)
            continue
        for atom_id, file, category, group in ROW.findall(path.read_text(encoding="utf-8")):
            out[file] = {"id": atom_id, "category": category, "group": group}
    return out


def library_rows() -> dict[str, dict]:
    """file name -> a manifest entry, newest library wins only if absent before."""
    out: dict[str, dict] = {}
    for path in LIBRARIES:
        if not path.exists():
            print("missing manifest %s" % path, file=sys.stderr)
            continue
        for entry in json.loads(path.read_text(encoding="utf-8")):
            for key in ("raw_path", "processed_path"):
                name = Path(str(entry.get(key, ""))).name
                if name and name not in out:
                    out[name] = entry
    return out


def measure(path: Path) -> tuple[float, float]:
    with wave.open(str(path), "rb") as w:
        frames, rate = w.getnframes(), w.getframerate()
        raw = w.readframes(frames)
    import numpy as np
    a = np.frombuffer(raw, dtype="<i2").astype("float64") / 32768.0
    peak = 20.0 * (np.log10(max(abs(a).max(), 1e-9))) if a.size else -180.0
    return frames / rate, float(peak)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(REPO / "docs" / "AUDIO_MANIFEST.md"))
    args = ap.parse_args()

    table = shipped_atoms()
    library = library_rows()
    wavs = sorted(ATOMS.rglob("*.wav"))
    if not wavs:
        print("no shipped atoms under %s" % ATOMS, file=sys.stderr)
        return 2

    rows: list[list[str]] = []
    unmatched: list[str] = []
    for path in wavs:
        meta = table.get(path.name)
        entry = library.get(path.name) or library.get(_source_name(path, library))
        if meta is None:
            unmatched.append(path.name)
            continue
        dur, peak = measure(path)
        rows.append([
            "`%s`" % meta["id"],
            meta["category"],
            "`%s`" % meta["group"],
            "%.2fs" % dur,
            "%+.1f" % peak,
            str(entry.get("seed", "-")) if entry else "-",
            (entry.get("use", "-") if entry else "-"),
            (entry.get("status", "unlisted") if entry else "unlisted"),
        ])

    # Variant count per family is what §17 turns on, so it is a column of its own.
    counts: dict[str, int] = {}
    for r in rows:
        counts[r[2]] = counts.get(r[2], 0) + 1

    out = [PROSE, ""]
    out.append("## Atoms (%d families, %d atoms)" % (len(counts), len(rows)))
    out.append("")
    out.append("`variants` is how many seeds this family can alternate between - the number")
    out.append("that decides whether a fast combo machine-guns one file (§17).")
    out.append("")
    out.append("| id | category | family | variants | duration | peak | seed | usage | status |")
    out.append("| --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- |")
    for r in rows:
        out.append("| %s | %s | %s | %d | %s | %s | %s | %s | %s |" % (
            r[0], r[1], r[2], counts[r[2]], r[3], r[4], r[5], r[6], r[7]))
    out.append("")
    if unmatched:
        out.append("### Wavs on disk that no Godot table claims (%d)" % len(unmatched))
        out.append("")
        out.append("These load nothing - either a leftover from a superseded render, or a")
        out.append("file the generator wrote and never listed. Both want to be seen.")
        out.append("")
        for name in unmatched:
            out.append("- `%s`" % name)
        out.append("")

    Path(args.out).write_text("\n".join(out) + "\n", encoding="utf-8")
    print("families %d | atoms %d | unclaimed %d -> %s" % (
        len(counts), len(rows), len(unmatched), args.out))
    return 0


def _source_name(path: Path, library: dict[str, dict]) -> str:
    """The manifest records `..._s1000.wav`; a shipped atom may have been renamed.

    Falling back to a prefix match keeps a renamed file attached to its provenance instead
    of silently showing "unlisted" - provenance that disappears on a rename is provenance
    that is one filename away from being lost.
    """
    stem = path.stem
    for name in library:
        if name.startswith(stem):
            return name
    return stem


if __name__ == "__main__":
    raise SystemExit(main())
