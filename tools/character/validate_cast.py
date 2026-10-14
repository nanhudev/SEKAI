#!/usr/bin/env python3
"""Validate godot/resources/cast/demo_cast.json against what is actually on disk.

WHY
---
The cast manifest is the promise that a character's *story identity* will survive
a model swap.  A hand-written manifest that drifts from the bakes is worse than
no manifest: narrative code binds to it and fails later, somewhere else.

This checks the claims, not the syntax:
  * every model path resolves to a real GLB in BOTH source and Godot trees
  * every skeleton_profile's numbers (bones / height / clips / rig repairs) match
    that character's own *_retarget.json -- so the profile is a measured claim
  * every clip named under base_motions actually exists in the baked clips
  * character_id is unique, and no id is a model name (the exact failure the
    ROLE != MODEL rule exists to prevent)

    python tools/character/validate_cast.py [--json godot/resources/cast/demo_cast.json]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GODOT = os.path.join(ROOT, "godot")
PLACEHOLDERS = os.path.join(ROOT, "assets_source", "characters", "placeholders")

REQUIRED_FIELDS = ("character_id", "display_name", "placeholder_model",
                   "skeleton_profile", "animation_profile", "scene_role")
ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")
MODEL_NAME_RE = re.compile(r"^lpg_")


def res_to_disk(project_relative: str) -> str:
    """res://assets/x.glb -> <ROOT>/godot/assets/x.glb"""
    if project_relative.startswith("res://"):
        return os.path.join(GODOT, project_relative[len("res://"):].replace("/", os.sep))
    return project_relative


def stem_of(project_relative: str) -> str:
    return os.path.splitext(os.path.basename(project_relative))[0]


class Report:
    def __init__(self):
        self.errors: list[str] = []
        self.warns: list[str] = []
        self.rows: list[tuple] = []

    def err(self, msg):
        self.errors.append(msg)

    def warn(self, msg):
        self.warns.append(msg)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", default=os.path.join(GODOT, "resources", "cast", "demo_cast.json"))
    a = ap.parse_args()

    if not os.path.isfile(a.json):
        print("FATAL: no manifest at %s" % a.json)
        return 2
    with open(a.json, encoding="utf-8") as f:
        man = json.load(f)

    r = Report()
    profiles = man.get("skeleton_profiles", {})
    anim_profiles = man.get("animation_profiles", {})
    base = man.get("base_motions", {})

    # ---- the clip names RUNTIME code will use.
    # Godot renames clips on import (it strips a trailing _loop / -loop and sets
    # loop mode), so the bake metadata and the runtime names do NOT match.  Rather
    # than re-deriving that rule and hoping it stays true, prefer a real Godot
    # --report dump as the authority and say which source was used.
    LOOP_RE = re.compile(r"[-_]loop$", re.I)
    lib_clips: set[str] = set()
    clip_src = ""
    review = os.path.join(PLACEHOLDERS, "_review")
    if os.path.isdir(review):
        for fn in sorted(os.listdir(review)):
            if not fn.endswith("_report.json"):
                continue
            with open(os.path.join(review, fn), encoding="utf-8") as f:
                d = json.load(f)
            names = {c["name"] for c in d.get("clips", [])}
            if names:
                lib_clips, clip_src = names, "godot report %s (authoritative)" % fn
                break
    if not lib_clips:
        for fn in sorted(os.listdir(PLACEHOLDERS)):
            if fn.endswith("_retarget.json"):
                with open(os.path.join(PLACEHOLDERS, fn), encoding="utf-8") as f:
                    raw = [c["name"] for c in json.load(f).get("clips", [])]
                lib_clips = {LOOP_RE.sub("", n) for n in raw}
                clip_src = "inferred by stripping _loop from a bake (NOT authoritative)"
                break
    if not lib_clips:
        r.err("no clip source found: no Godot --report and no *_retarget.json")

    # ---- base motions: every named clip must exist
    for motion, spec in base.items():
        if motion.startswith("_"):
            continue
        for clip in spec.get("clips", []):
            if lib_clips and clip not in lib_clips:
                r.err("base_motions.%s names clip '%s' which is not in the baked clips"
                      % (motion, clip))

    # ---- animation profiles referenced must exist; action ids look sane
    seen_actions: dict[str, str] = {}
    for prof_name, prof in anim_profiles.items():
        if prof_name.startswith("_"):
            continue
        for act in prof.get("actions", []):
            if not ID_RE.match(act):
                r.err("animation_profiles.%s action id '%s' is not snake_case"
                      % (prof_name, act))
            if act in seen_actions and seen_actions[act] != prof_name:
                r.warn("action id '%s' is shared by %s and %s -- intentional? "
                       "shared actions should live in base_motions instead"
                       % (act, seen_actions[act], prof_name))
            seen_actions.setdefault(act, prof_name)

    # ---- characters
    used_models: dict[str, str] = {}
    ids: set[str] = set()
    for ch in man.get("characters", []):
        cid = ch.get("character_id", "<missing>")
        for field in REQUIRED_FIELDS:
            if field not in ch:
                r.err("%s: missing required field '%s'" % (cid, field))
        if not ID_RE.match(cid):
            r.err("%s: character_id must be snake_case" % cid)
        if MODEL_NAME_RE.match(cid):
            r.err("%s: character_id looks like a MODEL name. Story code must never "
                  "bind to a model -- this is the exact failure ROLE != MODEL prevents." % cid)
        if cid in ids:
            r.err("duplicate character_id '%s'" % cid)
        ids.add(cid)

        model = ch.get("placeholder_model", "")
        sname = ch.get("skeleton_profile", "")
        apname = ch.get("animation_profile", "")

        if sname and sname not in profiles:
            r.err("%s: unknown skeleton_profile '%s'" % (cid, sname))
        if apname and apname not in anim_profiles:
            r.err("%s: unknown animation_profile '%s'" % (cid, apname))

        # every model path must exist in both trees
        candidates = [model] + ([ch["placeholder_model_alt"]] if ch.get("placeholder_model_alt") else [])
        for m in candidates:
            if not m:
                continue
            disk = res_to_disk(m)
            if not os.path.isfile(disk):
                r.err("%s: model missing in Godot tree: %s" % (cid, m))
            src = os.path.join(PLACEHOLDERS, stem_of(m) + ".glb")
            if not os.path.isfile(src):
                r.err("%s: model missing in source tree: %s" % (cid, src))

        # the profile's numbers must match THIS character's own bake
        meta_path = os.path.join(PLACEHOLDERS, stem_of(model) + "_retarget.json")
        bones = height = clips = "-"
        repairs = []
        if os.path.isfile(meta_path):
            with open(meta_path, encoding="utf-8") as f:
                meta = json.load(f)
            bones = meta.get("target_bones")
            height = meta.get("target_height_m")
            clips = len(meta.get("clips", []))
            repairs = meta.get("rig_repairs", [])
            prof = profiles.get(sname, {})
            if prof:
                if prof.get("bones") != bones:
                    r.err("%s: profile %s claims bones=%s, bake says %s"
                          % (cid, sname, prof.get("bones"), bones))
                if prof.get("clips") != clips:
                    r.err("%s: profile %s claims clips=%s, bake says %s"
                          % (cid, sname, prof.get("clips"), clips))
                if abs(float(prof.get("height_m", 0)) - float(height or 0)) > 1e-4:
                    r.err("%s: profile %s claims height=%s, bake says %s"
                          % (cid, sname, prof.get("height_m"), height))
                claimed = bool(prof.get("rig_repairs"))
                actual = bool(repairs)
                if claimed != actual:
                    r.err("%s: profile %s claims rig_repairs=%s but the bake recorded %s "
                          "(a model swap changed the skeleton behaviour)"
                          % (cid, sname, prof.get("rig_repairs"), repairs))
        else:
            r.err("%s: no bake metadata at %s" % (cid, meta_path))

        if model in used_models and used_models[model] != sname:
            r.err("model %s is used by %s and %s with DIFFERENT skeleton profiles"
                  % (stem_of(model), used_models[model], cid))
        used_models[model] = sname

        r.rows.append((cid, ch.get("scene_role", ""), stem_of(model), sname,
                       bones, height, clips, ch.get("priority", "")))

    # ---- pools
    for pool_name, pool in man.get("pools", {}).items():
        if not isinstance(pool, dict):
            continue
        for m in pool.get("models", []):
            if not os.path.isfile(res_to_disk(m)):
                r.err("pool %s: model missing: %s" % (pool_name, m))

    # ---- the same model must not be BOTH a named character and a crowd villager
    crowd = set()
    for pool_name in ("town_crowd", "guard"):
        for m in man.get("pools", {}).get(pool_name, {}).get("models", []):
            crowd.add(stem_of(m))
    for ch in man.get("characters", []):
        s = stem_of(ch.get("placeholder_model", ""))
        if s in crowd:
            r.warn("%s uses %s, which is also in a crowd pool -- the player may read "
                   "a villager as this character" % (ch.get("character_id"), s))

    # ---- print
    print("== demo_cast.json ==")
    print("   %-18s %-20s %-16s %-14s %5s %7s %5s %s"
          % ("character_id", "scene_role", "model", "skeleton", "bones", "height", "clips", "prio"))
    for row in r.rows:
        print("   %-18s %-20s %-16s %-14s %5s %7s %5s %s" % row)
    print("   characters=%d  skeleton_profiles=%d  animation_profiles=%d  clips_known=%d"
          % (len(r.rows), len(profiles), len(anim_profiles), len(lib_clips)))
    print("   clip-name source: %s" % clip_src)

    for w in r.warns:
        print("   WARN  %s" % w)
    for e in r.errors:
        print("   FAIL  %s" % e)

    if r.errors:
        print("   ==> %d error(s)" % len(r.errors))
        return 1
    print("   ==> OK (%d warning(s))" % len(r.warns))
    return 0


if __name__ == "__main__":
    sys.exit(main())
