#!/usr/bin/env python
"""Register class_name scripts in .godot/global_script_class_cache.cfg.

Adding a new `class_name` script normally requires opening the editor once so
Godot can rebuild the cache. `--editor --quit` rewrites the whole cache and
kicks off a re-import, which is hostile to the other sessions working in this
same tree. This patches just the entries we added, keeping the file sorted the
way Godot writes it.

Usage:
    python audio_source/tools/register_classes.py <project_dir>
"""

import os
import re
import sys

# class -> (base, script path). Keep in sync with the class_name declarations.
CLASSES = [
    ("CombatAudioCues", "RefCounted", "res://scripts/audio/combat_audio_cues.gd"),
    ("CombatAudioDirector", "Node", "res://scripts/audio/combat_audio_director.gd"),
    ("LayeredSFX", "Node", "res://scripts/audio/layered_sfx.gd"),
    ("SfxCue", "Resource", "res://scripts/audio/sfx_cue.gd"),
    ("SfxLayer", "Resource", "res://scripts/audio/sfx_layer.gd"),
    ("SoundAtom", "Resource", "res://scripts/audio/sound_atom.gd"),
    ("SoundAtomRegistry", "Node", "res://scripts/audio/sound_atom_registry.gd"),
]

ENTRY = """{{
"base": &"{base}",
"class": &"{cls}",
"icon": "",
"is_abstract": false,
"is_tool": false,
"language": &"GDScript",
"path": "{path}"
}}"""


def parse(text: str):
    """Return (prefix, [entry strings], suffix)."""
    match = re.match(r"list=\[(.*)\]\s*$", text, re.S)
    if not match:
        raise SystemExit("unexpected cache format")
    body = match.group(1).strip()
    if not body:
        return "list=[", [], "]\n"
    entries = re.split(r"\}\s*,\s*\{", body)
    # Splitting eats both braces at every boundary: only the first piece keeps
    # its leading "{" and only the last keeps its trailing "}".
    entries = ["{" + e if not e.startswith("{") else e for e in entries]
    entries = [e if e.endswith("}") else e + "}" for e in entries]
    return "list=[", entries, "]\n"


def name_of(entry: str) -> str:
    match = re.search(r'"class":\s*&"([^"]+)"', entry)
    return match.group(1) if match else ""


def main() -> int:
    project = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "..", "..", "godot")
    cache_path = os.path.join(project, ".godot", "global_script_class_cache.cfg")
    with open(cache_path, "r", encoding="utf-8") as handle:
        text = handle.read()
    prefix, entries, suffix = parse(text)
    existing = {name_of(e): i for i, e in enumerate(entries)}
    for cls, base, path in CLASSES:
        entry = ENTRY.format(base=base, cls=cls, path=path)
        if cls in existing:
            entries[existing[cls]] = entry
            print("  updated %s" % cls)
        else:
            entries.append(entry)
            print("  added   %s" % cls)
    entries.sort(key=name_of)
    with open(cache_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(prefix + ",\n".join(entries) + "\n" + suffix)
    print("cache now holds %d classes" % len(entries))
    return 0


if __name__ == "__main__":
    sys.exit(main())
