#!/usr/bin/env python3
"""
library -> Godot. The missing bridge.

`audio_source/library/<category>/processed/` is where a sound becomes usable;
`godot/audio/sfx/` is where the game can load it. Until now that hop was done by
hand, which is how a library ends up with 200 files and a registry that knows
about 12 of them.

Two outputs, both mechanical:

  1. the chosen processed wavs are copied into the Godot tree, under the layout
     the audio brief asks for (atoms/<material>, weapons/<weapon>);
  2. `godot/scripts/audio/chain_atom_table.gd` is REGENERATED from the manifest,
     so the registry never has to be hand-edited when a sound is added or a seed
     is swapped. Generated, not transcribed - the same rule the Iaido tuning and
     the UI tokens already follow.

Usage:
    python audio_source/tools/emit_godot_atoms.py --check
    python audio_source/tools/emit_godot_atoms.py --apply
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent                      # audio_source/
REPO = ROOT.parent                      # repo root
LIBRARY = ROOT / "library"
MANIFEST = LIBRARY / "sfx_manifest.json"
# The two sides live in different worktrees while a line is in progress: the
# library belongs to the audio branch, the game tree is wherever the weapon being
# given a voice actually runs. Rather than copying the library around, the output
# side is a parameter.
DEFAULT_GODOT_ROOT = REPO
GODOT_SFX_SUBDIR = Path("godot") / "audio" / "sfx"
TABLE_SUBPATH = Path("godot") / "scripts" / "audio" / "chain_atom_table.gd"

# Which seeds are kept. Two is the brief's floor for a high-frequency sound and
# is enough to break the machine-gun repeat without pretending four takes were
# auditioned - nothing here has been listened to yet.
KEEP_SEEDS = 2
# The sword is the weapon the player fires most often, so it gets three: A/B/C is
# the difference between "that is a variation" and "that is the same sample".
SWORD_KEEP_SEEDS = 3

# id -> (godot subdir, variation group, role, pitch range, note)
#
# The group is the thing cues reference; the id is provenance. A group with more
# than one member alternates A/B/A/B instead of repeating, which is the whole
# reason variations exist.
CHAIN: dict[str, tuple[str, str, str, tuple[float, float], str]] = {
    # --- library exports that already existed (audited, not regenerated) ------
    "metal_chain_fast_move_01": ("weapons/chain", "chain_move", "CHAIN MOVE (FAST)", (0.96, 1.05),
                                 "links travelling at speed; the sweep's own noise floor"),
    "metal_chain_whoosh_01": ("weapons/chain", "chain_whoosh", "CHAIN WHOOSH", (0.97, 1.04),
                              "the thrown head's air; never the identity of a swing on its own"),
    "metal_chain_rattle_01": ("weapons/chain", "chain_rattle", "CHAIN RATTLE", (0.96, 1.05),
                              "TEXTURE, not a layer - sits far below the whoosh"),
    "metal_chain_tension_01": ("weapons/chain", "chain_tension", "CHAIN TENSION (RISE)", (0.97, 1.04),
                               "links aligning under load; the rope coming up"),
    "metal_chain_tighten_01": ("weapons/chain", "chain_tighten", "CHAIN TIGHTEN (LOCK)", (0.97, 1.04),
                               "the load arriving on an already-straight rope"),
    "metal_chain_snap_release_01": ("weapons/chain", "chain_snap", "CHAIN SNAP RELEASE", (0.98, 1.03),
                                    "sudden slack; the pressure being spent"),
    "metal_chain_impact_light_01": ("weapons/chain", "chain_impact_light", "CHAIN IMPACT LIGHT", (0.98, 1.03),
                                    "a graze; the head touching something without committing"),
    "metal_chain_impact_heavy_01": ("weapons/chain", "chain_impact_heavy", "CHAIN IMPACT HEAVY", (0.97, 1.03),
                                    "mass arriving; the body layer under a contact"),
    "metal_chain_slow_drag_01": ("weapons/chain", "chain_drag", "CHAIN DRAG", (0.96, 1.04),
                                 "links dragged over a surface under their own weight"),
    "metal_chain_slide_01": ("weapons/chain", "chain_slide", "CHAIN SLIDE", (0.96, 1.04),
                             "scrape; use when the chain is pulled across, not lifted"),
    "metal_chain_wrap_01": ("weapons/chain", "chain_wrap", "CHAIN WRAP", (0.97, 1.03),
                            "coil closing on a target; 缚's own sound"),
    "metal_chain_ground_hit_01": ("weapons/chain", "chain_ground", "CHAIN GROUND HIT", (0.97, 1.03),
                                  "dropped, not thrown; aftermath and loot"),
    "metal_chain_break_01": ("weapons/chain", "chain_break", "CHAIN BREAK", (0.97, 1.03),
                             "link failure; held for a future ultimate, not for combat"),
    "metal_link_clink_01": ("weapons/chain", "chain_link_tick", "LINK TICK", (0.98, 1.03),
                            "single link contact; detail and UI accent"),

    # --- STEP 5: the gaps the audit actually found ---------------------------
    "chain_idle_settle_01": ("weapons/chain", "chain_idle", "CHAIN IDLE SETTLE", (0.96, 1.05),
                             "the idle noise floor - quiet by design, not an event"),
    "chain_retract_fast_01": ("weapons/chain", "chain_retract_light", "CHAIN RETRACT (LIGHT)", (0.97, 1.04),
                              "A3 whiff reel; reeling has to sound as good as throwing"),
    "chain_retract_heavy_01": ("weapons/chain", "chain_retract_heavy", "CHAIN RETRACT (HEAVY)", (0.96, 1.03),
                               "hauling something with weight back to the hand"),
    "chain_yank_short_01": ("weapons/chain", "chain_yank_light", "CHAIN YANK (LIGHT)", (0.98, 1.04),
                            "ONE tug. The impact of what was pulled is a different sound"),
    "chain_yank_heavy_01": ("weapons/chain", "chain_yank_heavy", "CHAIN YANK (HEAVY)", (0.96, 1.03),
                            "a heavy body on the other end; the player is what moves"),
    "chain_orbit_fast_01": ("weapons/chain", "chain_orbit", "CHAIN ORBIT", (0.97, 1.04),
                            "回旋; repeated while spinning, never restarted straight"),
    "chain_tension_rise_01": ("weapons/chain", "chain_tension_rise", "CHAIN TENSION RISE", (0.98, 1.03),
                              "100-350 ms and stackable; this is the atom TENSION is built from"),
    "chain_tension_lock_01": ("weapons/chain", "chain_tension_lock", "CHAIN TENSION LOCK", (0.97, 1.03),
                              "at the limit, holding; the beat before the snap"),
    "chain_payout_01": ("weapons/chain", "chain_payout", "CHAIN PAY-OUT", (0.97, 1.03),
                        "the head travelling away; what makes A3 read as a THROW"),
    "metal_link_heavy_01": ("atoms/metal", "chain_link_heavy", "LINK HEAVY", (0.97, 1.03),
                            "the loud end of the rattle range"),

    # --- contact: the head meeting the world (§9-§11) ------------------------
    "hook_stone_01": ("atoms/stone", "hook_stone", "HOOK / BITE - STONE", (0.97, 1.03),
                      "trident into stone; CONTACT layer for any stone surface, not chain-only"),
    "hook_metal_01": ("atoms/metal", "hook_metal", "HOOK / BITE - METAL", (0.98, 1.03),
                      "iron door, weapon rack, an armoured surface"),
    "hook_wood_01": ("atoms/wood", "hook_wood", "HOOK / BITE - WOOD", (0.97, 1.03),
                     "bridge, dock, door, crate; the surface picks the layer, gameplay does not"),
    "body_impact_soft_01": ("atoms/body", "body_impact", "BODY IMPACT (STYLIZED)", (0.96, 1.04),
                            "a blow landing on a body. No gore, no voice - shared, not chain-only"),
    "air_heavy_01": ("atoms/air", "air_heavy", "AIR HEAVY", (0.97, 1.04),
                     "the wide low whoosh under A1; this also fills core's PENDING air_heavy"),
}

# ---------------------------------------------------------------------------
# SWORD. The weapon the game is actually about, and the one that had no language
# of its own: its whole vocabulary used to be `air_fast` + `cloth_fast`, so A1 and
# A3 were the same file at two pitches and the blade itself was never audible.
#
# RULE FOR THIS TABLE, learned from the chain: an atom carries ONE material, and
# the material decides what it is allowed to do. Air never contains metal, cloth
# never contains impact, and the things that TOUCH the sword are separate groups
# (`sword_contact_*`) so that a contact is chosen by what was hit rather than by
# which attack hit it. That is what makes §PART F possible at all.
#
# Nothing here is a finished skill sound. A3 is not a file; it is
# `air_cut_medium` + `blade_move_light` + `low_impact_short`, and it is a DIFFERENT
# combination from A1 - never A1's file played again.
# ---------------------------------------------------------------------------
SWORD: dict[str, tuple[str, str, str, tuple[float, float], str]] = {
    # --- AIR: the identity of a whiff. Light / medium / heavy / stab are four
    # different shapes of air, not four volumes of one.
    "air_cut_light_01": ("atoms/air", "air_cut_light", "AIR CUT (LIGHT)", (0.97, 1.04),
                         "A1/A2 identity; short, fast, bright. Metal does NOT belong here"),
    "air_cut_medium_01": ("atoms/air", "air_cut_medium", "AIR CUT (MEDIUM)", (0.97, 1.03),
                          "A3 finisher; wider air than light, still not a low boom"),
    "air_cut_heavy_01": ("atoms/air", "air_cut_heavy", "AIR CUT (HEAVY)", (0.96, 1.02),
                         "heavy release; broad displaced air with real momentum behind it"),
    "air_stab_01": ("atoms/air", "air_stab", "AIR STAB", (0.98, 1.04),
                    "narrow focused FORWARD air; thrust and riposte, not an arc"),

    # --- BLADE: the sword's own steel in motion, and its own voice answering.
    "blade_move_light_01": ("atoms/metal", "blade_move_light", "BLADE MOVE (LIGHT)", (0.98, 1.03),
                            "the blade itself travelling under a light cut; sits under the air"),
    "blade_move_heavy_01": ("atoms/metal", "blade_move_heavy", "BLADE MOVE (HEAVY)", (0.97, 1.02),
                            "steel body resonance under a heavy swing; the mass in the metal"),
    "blade_ring_short_01": ("atoms/metal", "blade_ring_short", "BLADE RING (SHORT)", (0.98, 1.03),
                            "the steel answering; SHORT, and never a bell"),

    # --- CONTACT with metal (a surface), as opposed to the BLOCK family below.
    "metal_contact_light_01": ("atoms/metal", "metal_contact_light", "METAL CONTACT (LIGHT)", (0.98, 1.03),
                               "graze / deflect on an armoured surface; the edge skated"),
    "metal_contact_heavy_01": ("atoms/metal", "metal_contact_heavy", "METAL CONTACT (HEAVY)", (0.97, 1.03),
                               "committed clash; the body of the meeting, ring second"),

    # --- DEFENSE: block, perfect guard, bind, riposte. Four different MOMENTS.
    "guard_metal_01": ("atoms/metal", "guard_metal", "GUARD METAL (BLOCK)", (0.97, 1.03),
                       "an ORDINARY block: solid, dull, the edge did not bite, tail short"),
    "perfect_guard_sharp_01": ("atoms/metal", "perfect_guard_sharp", "PERFECT GUARD SHARP", (0.99, 1.02),
                               "the sharpest, cleanest transient in the game; this IS the timing-success tell"),
    "blade_slide_short_01": ("atoms/metal", "blade_slide_short", "BLADE SLIDE (SHORT)", (0.97, 1.03),
                             "edge along edge; the bind, and the beat before a riposte"),
    "riposte_release_01": ("atoms/metal", "riposte_release", "RIPOSTE RELEASE", (0.98, 1.03),
                           "the advantage being spent; a focused decisive cut, not a new skill"),

    # --- WEAPON BODY: the sword's OWN mass. Not the target's body - that is
    # `sword_contact_body` and the shared `body_impact`.
    "weapon_body_light_01": ("atoms/body", "weapon_body_light", "WEAPON BODY (LIGHT)", (0.97, 1.03),
                             "hilt / guard / pommel on a light move; barely there"),
    "weapon_body_heavy_01": ("atoms/body", "weapon_body_heavy", "WEAPON BODY (HEAVY)", (0.96, 1.02),
                             "the mass that swings it; heavy release and shatter"),
    "low_impact_short_01": ("atoms/body", "low_impact_short", "LOW IMPACT (SHORT)", (0.97, 1.03),
                            "the finisher's weight: short and tight, NEVER a cinematic boom"),

    # --- CLOTH / HAND: the layer that says a PERSON is holding it.
    "cloth_light_01": ("atoms/cloth", "cloth_light", "CLOTH (LIGHT)", (0.96, 1.05),
                       "sleeve and fabric on a quick cut; keep it low, it is not the point"),
    "cloth_heavy_01": ("atoms/cloth", "cloth_heavy", "CLOTH (HEAVY)", (0.95, 1.04),
                       "coat shifting under a big wind-up"),
    "grip_shift_01": ("atoms/cloth", "grip_shift", "GRIP SHIFT", (0.97, 1.03),
                      "the hand re-taking the grip; the beat of intent before a release"),
    "weapon_sway_01": ("atoms/cloth", "weapon_sway", "WEAPON SWAY", (0.97, 1.04),
                       "dodge / sprint sway. EVENT BASED and very quiet - the sword is not a loop"),

    # --- CONTACT: chosen by WHAT WAS HIT. Gameplay sends a material, not a file.
    "sword_contact_body_01": ("atoms/body", "sword_contact_body", "SWORD CONTACT - BODY", (0.97, 1.03),
                              "stylized: dull hit plus a small blade slice. No gore, no voice"),
    "sword_contact_wood_01": ("atoms/wood", "sword_contact_wood", "SWORD CONTACT - WOOD", (0.97, 1.03),
                              "dry cut plus a wood crack"),
    "wood_crack_01": ("atoms/wood", "wood_crack", "WOOD CRACK", (0.97, 1.03),
                      "timber giving way; the second half of a wooden contact"),
    "sword_contact_stone_01": ("atoms/stone", "sword_contact_stone", "SWORD CONTACT - STONE", (0.97, 1.03),
                               "stone chip plus metal edge contact; NOT a hammer on rock"),
    "stone_chip_01": ("atoms/stone", "stone_chip", "STONE CHIP", (0.97, 1.04),
                      "small debris answering the blade"),
    "ice_impact_01": ("atoms/ice", "ice_impact", "ICE IMPACT", (0.97, 1.03),
                      "the blade arriving on frozen matter"),
    "ice_crack_01": ("atoms/ice", "ice_crack", "ICE CRACK", (0.97, 1.03),
                     "frozen flesh under stress; the beat before a shatter"),
    "crystal_break_01": ("atoms/ice", "crystal_break", "CRYSTAL BREAK", (0.96, 1.02),
                         "a frozen OBJECT coming apart - a sword broke it, not a window"),
    "ice_shard_settle_01": ("atoms/ice", "ice_shard_settle", "ICE SHARD SETTLE", (0.97, 1.03),
                            "aftermath; shards settling, dry and short"),
}

TABLE: dict[str, tuple[str, str, str, tuple[float, float], str]] = {**CHAIN, **SWORD}

CATEGORY_OF_DIR = {
    "weapons/chain": "chain",
    "atoms/air": "air",
    "atoms/body": "body",
    "atoms/cloth": "cloth",
    "atoms/ice": "ice",
    "atoms/metal": "metal",
    "atoms/stone": "stone",
    "atoms/wood": "wood",
}

GROUP_LABEL = {}


def safe(s: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]", "_", s)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--godot-root", default=str(DEFAULT_GODOT_ROOT),
                    help="game tree to emit into (default: this repo)")
    ap.add_argument("--library-root",
                    help="audio_source/ to read (default: the one beside this script)")
    args = ap.parse_args()
    if not args.apply and not args.check:
        ap.error("need --check or --apply")

    library = Path(args.library_root) if args.library_root else ROOT
    manifest_path = library / "library" / "sfx_manifest.json"
    godot_root = Path(args.godot_root)
    godot_sfx = godot_root / GODOT_SFX_SUBDIR
    table_path = godot_root / TABLE_SUBPATH
    if not manifest_path.exists():
        sys.exit("no manifest at %s" % manifest_path)

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    by_id: dict[str, list[dict]] = {}
    for entry in manifest:
        by_id.setdefault(str(entry.get("sfx_id", "")), []).append(entry)

    rows: list[str] = []
    copies: list[tuple[Path, Path]] = []
    problems: list[str] = []

    for sfx_id, (subdir, group, role, (pmin, pmax), note) in TABLE.items():
        entries = [e for e in by_id.get(sfx_id, []) if e.get("processed_path")]
        if not entries:
            problems.append("%s: no processed file (run process_atoms.py first)" % sfx_id)
            continue
        entries.sort(key=lambda e: int(e.get("seed", 0)))
        chosen = entries[:SWORD_KEEP_SEEDS if sfx_id in SWORD else KEEP_SEEDS]
        letter = ord("A")
        for entry in chosen:
            src = Path(entry["processed_path"])
            if not src.is_absolute():
                src = REPO / src
            if not src.exists():
                problems.append("%s: missing %s" % (sfx_id, src))
                continue
            # Godot cannot import a name it cannot trust, and the seed has to
            # survive into the filename: swapping variant 2 later must not mean
            # re-reading a table to find out which take it was.
            stem = "%s_s%s" % (safe(sfx_id), safe(str(entry.get("seed", "0"))))
            dst = godot_sfx / subdir / (stem + ".wav")
            copies.append((src, dst))
            rows.append(
                '\t{"id": &"%s_%s", "dir": "res://audio/sfx/%s/", "file": "%s.wav",\n'
                '\t\t"category": &"%s", "role": "%s %s", "group": &"%s",\n'
                '\t\t"peak": %s, "pitch_min": %s, "pitch_max": %s,\n'
                '\t\t"note": "%s"}'
                % (safe(sfx_id), chr(letter), subdir, stem,
                   CATEGORY_OF_DIR[subdir], role, chr(letter), group,
                   float(entry.get("processed_peak_db", -6.0)), pmin, pmax,
                   note.replace('"', "'"))
            )
            letter += 1
        if letter == ord("A"):
            problems.append("%s: nothing copied" % sfx_id)

    header = '''extends RefCounted
## GENERATED - do not edit by hand.
##
## Written by `audio_source/tools/emit_godot_atoms.py` from
## `audio_source/library/sfx_manifest.json`. The registry reads this table; a new
## sound is added by generating it, processing it and re-running that tool, never
## by transcribing a filename here.
##
## Three families live here now, and they are grouped by MATERIAL because that is
## what decides what a sound is allowed to do:
##   * SWORD  - air / blade / weapon-body / cloth-hand / the four guard moments
##   * CONTACT- body / stone / metal / wood / ice, chosen by WHAT WAS HIT
##   * CHAIN  - the second weapon's own vocabulary (weapons/chain)
## The sword's original twelve atoms still live in SoundAtomRegistry's own table
## under `core/`, because moving them would change what the approved sword audio
## loads.
##
## The FILE is still called chain_atom_table.gd. That name is history: it was the
## extension table before the sword had one. It is not renamed because a parallel
## session runs this same tool from its own worktree, and two writers disagreeing
## about the output path is a worse bug than a stale filename.

'''

    body = "const ROWS: Array[Dictionary] = [\n" + ",\n".join(rows) + ",\n]\n"

    print("atoms   : %d rows from %d ids (%d sword, %d chain)"
          % (len(rows), len(TABLE), len(SWORD), len(CHAIN)))
    for src, dst in copies:
        print("  %-46s -> %s" % (src.name, dst))

    if problems:
        print("\nproblems:")
        for problem in problems:
            print("  ! " + problem)

    if args.check:
        print("\n(check only - nothing written)")
        return 1 if problems else 0

    for src, dst in copies:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    table_path.parent.mkdir(parents=True, exist_ok=True)
    table_path.write_text(header + body, encoding="utf-8")
    print("\nwrote %s (%d rows)" % (table_path, len(rows)))
    print("copied %d wavs into %s" % (len(copies), godot_sfx))
    return 0


if __name__ == "__main__":
    sys.exit(main())
