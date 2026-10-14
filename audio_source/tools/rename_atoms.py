#!/usr/bin/env python
"""CORE ATOM ROLE CLEANUP - rename atoms to match their real acoustic role.

Godot 4 stores imported assets as:

    res://.godot/imported/<basename>-<md5(res://source/path)>.sample

so a rename has to move three things together, or the editor silently
re-imports (and, worse, the old uid keeps pointing at a missing file):

    audio/sfx/core/<old>.wav
    audio/sfx/core/<old>.wav.import      (source_file / path / dest_files)
    .godot/imported/<old>.wav-<hash>.sample + .md5

The file NAME must never constrain the sound design, so renames are cheap
and expected. See docs/AUDIO_SOUND_LANGUAGE.md for the role of each atom.
"""

import hashlib
import os
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GODOT = os.path.join(ROOT, "godot")
CORE = os.path.join(GODOT, "audio", "sfx", "core")
IMPORTED = os.path.join(GODOT, ".godot", "imported")

# old name -> new name. Pair each with the reason so the log reads as a
# design decision, not a file shuffle.
RENAMES = [
    ("air_low_01", "pressure_low_01",
     "not a low sword whoosh - it is a pressure sub / low swell"),
    ("glass_crack_02", "glass_body_01",
     "darker and duller than 01 - it is a fracture body, not a second main crack"),
    ("glass_tick_01", "glass_low_tick_01",
     "not bright/brittle enough to carry the main glass tick - demoted"),
]


def res_hash(res_path: str) -> str:
    return hashlib.md5(res_path.encode("utf-8")).hexdigest()


def rename(old: str, new: str, reason: str) -> bool:
    old_res = "res://audio/sfx/core/%s.wav" % old
    new_res = "res://audio/sfx/core/%s.wav" % new
    old_hash = res_hash(old_res)
    new_hash = res_hash(new_res)

    wav_old = os.path.join(CORE, old + ".wav")
    wav_new = os.path.join(CORE, new + ".wav")
    if not os.path.exists(wav_old):
        if os.path.exists(wav_new):
            print("  = %s already renamed" % new)
            return False
        print("  ! missing source: %s" % old)
        return False

    os.rename(wav_old, wav_new)

    # Imported artefacts keep their content, only their name changes.
    for ext in (".sample", ".md5"):
        src = os.path.join(IMPORTED, "%s.wav-%s%s" % (old, old_hash, ext))
        dst = os.path.join(IMPORTED, "%s.wav-%s%s" % (new, new_hash, ext))
        if os.path.exists(src):
            os.rename(src, dst)

    imp_old = os.path.join(CORE, old + ".wav.import")
    imp_new = os.path.join(CORE, new + ".wav.import")
    if os.path.exists(imp_old):
        with open(imp_old, "r", encoding="utf-8") as handle:
            text = handle.read()
        text = text.replace(old_res, new_res)
        text = text.replace("%s.wav-%s.sample" % (old, old_hash),
                            "%s.wav-%s.sample" % (new, new_hash))
        with open(imp_new, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        os.remove(imp_old)

    print("  %-22s -> %-22s (%s)" % (old + ".wav", new + ".wav", reason))
    return True


def main() -> int:
    print("CORE ATOM ROLE CLEANUP")
    moved = 0
    for old, new, reason in RENAMES:
        if rename(old, new, reason):
            moved += 1
    print("renamed %d atom(s)" % moved)
    return 0


if __name__ == "__main__":
    sys.exit(main())
