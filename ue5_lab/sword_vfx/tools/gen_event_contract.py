"""SEKAI Sword VFX - generate the machine-readable event contract from Godot.

WHY THIS PARSES THE GODOT SOURCE INSTEAD OF RESTATING IT

    The brief (section 3) wants one event contract that the UE5 side consumes so
    a Niagara graph never guesses a time. The numbers in that contract already
    exist, in `sword_basic.gd` and `IaidoTuning.tres`. Re-typing them into a
    second document creates a second place for them to be wrong, and the failure
    mode is silent: a stale `t` does not throw, it just fires the wrong effect at
    the wrong moment.

    So this reads them out of the shipping source and emits JSON. The document
    `docs/SWORD_VFX_EVENT_CONTRACT.md` is the explanation; this file is the
    data. When the draw is retuned in Godot, re-run this and the contract moves
    with it.

    Anything this cannot resolve is emitted as null WITH A REASON, never
    defaulted - a guessed timing is worse than a missing one.

Usage:
    python gen_event_contract.py            # write the JSON
    python gen_event_contract.py --table    # also print the resolved table
"""
import argparse
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SEKAI = os.path.abspath(os.path.join(ROOT, "..", ".."))
BASIC = os.path.join(SEKAI, "godot", "scripts", "combat", "sword_basic.gd")
VFX = os.path.join(SEKAI, "godot", "scripts", "combat", "sword_combat_vfx.gd")
TUNING = os.path.join(SEKAI, "godot", "resources", "tuning", "IaidoTuning.tres")
COMBAT_TUNING = os.path.join(SEKAI, "godot", "resources", "tuning", "IaidoCombatTuning.tres")
CONFIG_SCRIPT = os.path.join(SEKAI, "godot", "scripts", "weapons", "sword_config.gd")
CONFIG_RESOURCE = os.path.join(SEKAI, "godot", "resources", "tuning", "SwordConfig.tres")
DIRECTOR = os.path.join(SEKAI, "godot", "scripts", "combat", "iaido_director.gd")
OUT = os.path.join(ROOT, "docs", "sword_vfx_event_contract.json")

# Godot's raw event id -> the brief's UE5 name. The brief's names are the
# interface; Godot's ids are what the source actually fires.
UE5_NAME = {
    # A1
    "A1_SHEATH_TOUCH": "EV_SWORD_A1_SHEATH_TOUCH",
    "A1_DRAW": "EV_SWORD_A1_DRAW",
    "A1_ACTIVE": "EV_SWORD_A1_ACTIVE",
    "A1_FINISH": "EV_SWORD_A1_FINISH",
    # A2
    "A2_RELEASE": "EV_SWORD_A2_RELEASE",
    "A2_WAVE": "EV_SWORD_A2_WAVE",
    "A2_FINISH": "EV_SWORD_A2_FINISH",
    # A3
    "A3_SHEATHE": "EV_SWORD_A3_SHEATHE",
    "A3_DOMAIN_START": "EV_SWORD_A3_DOMAIN_BEGIN",
    "A3_CUT_1": "EV_SWORD_A3_CUT_1",
    "A3_CUT_2": "EV_SWORD_A3_CUT_2",
    "A3_CUT_3": "EV_SWORD_A3_CUT_3",
    "A3_DOMAIN_END": "EV_SWORD_A3_DOMAIN_END",
    # A4
    "A4_ARC_START": "EV_SWORD_A4_ARC_BEGIN",
    "A4_ACTIVE": "EV_SWORD_A4_ACTIVE",
    "A4_ARC_END": "EV_SWORD_A4_ARC_END",
    # the draw, five beats (PRESENTATION V3)
    "EQUIP_CARRY": None,                      # no VFX obligation
    "EQUIP_GLINT": "EV_SWORD_EQUIP_GLINT",
    "EQUIP_SEAT": "EV_SWORD_EQUIP_END",
    "SAYA_PUSH": "EV_SWORD_EQUIP_FULL_DRAW",
    "DRAW": "EV_SWORD_EQUIP_PARTIAL_DRAW",
}

# The five-beat draw reuses SHEATH_TOUCH / DRAW, so the equip move needs its own
# overlay: the same raw id means different things in sb_a1 and sb_equip. The key
# is the raw id AS THE SOURCE DEFINES IT - `EV_DRAW` is `&"A1_DRAW"`, so the raw
# value really is "A1_DRAW" even inside the equip move.
UE5_NAME_BY_MOVE = {
    "sb_equip": {
        "A1_SHEATH_TOUCH": "EV_SWORD_EQUIP_BEGIN",
        "A1_DRAW": "EV_SWORD_EQUIP_PARTIAL_DRAW",
    },
    "sb_a1": {"A1_SHEATH_TOUCH": "EV_SWORD_A1_SHEATH_TOUCH"},
}

# Float constants are the *subject* of the contract, but they live in a wall of
# unrelated constants, so only what the contract needs is read back and reported.
WANTED_FIELDS = [
    "startup", "strike", "follow_time", "recovery",
    "reach_mode", "reach", "reach_speed", "reach_radius",
    "reach_arc_from", "reach_arc_to", "arc_slices",
    "trace_half_len_tan", "trace_half_thick_tan",
    "trail_width_scale", "hitstop", "fov_kick",
    "domain_from", "domain_to",
]

IAIDO_EVENTS = [
    ("EV_IAIDO_SAYA_TOUCH", "sheath_move_cue",
     "the blade touches the saya and walks it home"),
    ("EV_IAIDO_DRAW", "draw_start",
     "100 ms instant draw (draw_end = draw_start + 0.10)"),
    ("EV_IAIDO_CUT", "cut_start",
     "the cut; cut_start == damage_time"),
    ("EV_IAIDO_ROTATE", "spin_start",
     "phase K: two wrist arcs, one turn total, 6.30 -> 6.78 -> 7.30"),
    ("EV_IAIDO_SHEATHE_BEGIN", "slow_sheathe_start",
     "phase L: the return begins"),
    ("EV_IAIDO_MOUTH_FIND", "final_insert_start",
     "the tip finds the koiguchi; the last 7 cm crawl"),
    ("EV_IAIDO_CLICK", "final_click",
     "final click; devour begins at the same instant"),
]

# Brief section 8. There is no inspect move in the Godot source - verified by
# grep for "inspect" and by sword_basic.moves() returning [a1..a4]. Emitted as
# blocked rather than given invented durations.
INSPECT_BLOCKED = {
    "status": "BLOCKED_NO_GODOT_MOVE",
    "requested_events": ["EV_SWORD_INSPECT_BEGIN", "EV_SWORD_INSPECT_GLINT",
                         "EV_SWORD_INSPECT_ALIGN_SAYA", "EV_SWORD_INSPECT_END"],
    "evidence": [
        "grep -rn 'inspect|INSPECT' godot/scripts/ --include=*.gd -> no move, "
        "no EV_INSPECT_*, no timing",
        "sword_basic.gd moves() returns [a1(), a2(), a3(), a4()]; the only "
        "other move is sb_equip",
    ],
    "note": "Per brief section 1 the Godot line owns timing, so this line does "
            "not invent a duration. NS_SW_Core_Glint is the reusable component "
            "section 8 asks for and is built; the events are reserved.",
}

NUM = r"(-?\d+(?:\.\d+)?)"
# An optional trailing comment must be allowed: `const EV_EQUIP_CARRY :=
# &"EQUIP_CARRY"   # the assembly is up and still` is a real line in the source,
# and a `\s*$` anchor misses it. That silently left four equip events unmapped.
_TAIL = r"\s*(?:#.*)?$"
RE_CONST_NUM = re.compile(r"^const\s+([A-Z0-9_]+)\s*:=\s*" + NUM + _TAIL, re.M)
RE_CONST_STR = re.compile(r'^const\s+([A-Z0-9_]+)\s*:=\s*&"([^"]+)"' + _TAIL, re.M)
RE_EVENT_CONST = re.compile(r'^const\s+(EV_[A-Z0-9_]+)\s*:=\s*&"([^"]+)"' + _TAIL,
                            re.M)


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


# --------------------------------------------------------------------------
# constants, including the ones that are expressions
# --------------------------------------------------------------------------
#
# Not every duration is a literal. The source writes
#
#     const NE_TOTAL := NE_DRAW_FULL + NE_SETTLE
#     move.strike    = A3_RESOLVE - A3_HOLD_END   # 0.52 - all three cuts
#
# and a numeric-only regex silently drops both, which then reads downstream as
# "this beat has no duration" - a missing number that looks like an absent one.
# So every const is captured as text and resolved by repeated substitution over
# the const namespace, with only arithmetic permitted.

RE_CONST_ANY = re.compile(r"^const\s+([A-Z0-9_]+)\s*:=\s*(.+?)\s*(?:#.*)?$", re.M)
_SAFE = re.compile(r"^[0-9+\-*/%.() \tA-Za-z_]+$")


def collect_consts(src):
    """Return (resolved: dict[str,float], unresolved: dict[str,str])."""
    raw = {}
    for m in RE_CONST_ANY.finditer(src):
        val = m.group(2).strip()
        if val.startswith('&"') or val.startswith("Vector") or val.startswith("preload"):
            continue
        raw[m.group(1)] = val

    resolved = {}
    for _ in range(8):
        progress = False
        for name, expr in list(raw.items()):
            if name in resolved:
                continue
            if not _SAFE.match(expr):
                continue
            try:
                v = eval(expr, {"__builtins__": {}}, dict(resolved))
            except Exception:
                continue
            if isinstance(v, (int, float)):
                resolved[name] = float(v)
                progress = True
        if not progress:
            break
    unresolved = {k: v for k, v in raw.items() if k not in resolved}
    return resolved, unresolved


def resolve(token, consts):
    """Resolve a value token, including expressions, to a float."""
    token = str(token).split("#")[0].strip()
    if not token:
        return None, "empty expression"
    if not _SAFE.match(token):
        return None, "not arithmetic: %r" % token
    try:
        v = eval(token, {"__builtins__": {}}, dict(consts))
    except Exception as exc:
        return None, "unresolved (%s) in %r" % (type(exc).__name__, token)
    if isinstance(v, (int, float)):
        return float(v), None
    return None, "not a number: %r" % token


def parse_moves(src, consts, ev_ids):
    """Split the source on `static func <name>() -> SwordMove:` and read each."""
    marks = [(m.start(), m.group(1)) for m in
             re.finditer(r"static func ([a-z0-9_]+)\(\)\s*->\s*SwordMove:", src)]
    out = {}
    for i, (pos, fn) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(src)
        body = src[pos:end]
        move_id = None
        m = re.search(r"move\.id\s*=\s*([A-Z0-9_]+)", body)
        if m:
            move_id = consts.get("__strid__" + m.group(1)) or m.group(1)
        entry = {"godot_func": fn, "move_id": move_id, "fields": {}, "events": []}

        for field in WANTED_FIELDS:
            m = re.search(r"move\.%s\s*=\s*([^\n]+)" % re.escape(field), body)
            if not m:
                continue
            raw = m.group(1).strip()
            if raw.startswith('&"'):
                entry["fields"][field] = raw[2:-1]
                continue
            v, why = resolve(raw, consts)
            entry["fields"][field] = v if v is not None else {"unresolved": raw}

        # events block
        m = re.search(r"move\.events\s*=\s*\[(.*?)\]\s*\n", body, re.S)
        if m:
            for em in re.finditer(
                    r'\{\s*"t"\s*:\s*([^,]+),\s*"id"\s*:\s*([A-Z0-9_]+)\s*\}', m.group(1)):
                traw, evconst = em.group(1), em.group(2)
                t, why = resolve(traw, consts)
                raw_id = ev_ids.get(evconst, evconst)
                # An explicit None in UE5_NAME is NOT a missing name. It is the
                # statement that this beat carries NO vfx obligation - e.g.
                # EQUIP_CARRY, the assembly being brought up before the glint
                # beat. Emitting a bare null for it made it indistinguishable
                # from a mapping someone had simply forgotten, which is why the
                # distinction is now written into the contract as
                # `has_vfx_obligation` instead of being left to context.
                moved = UE5_NAME_BY_MOVE.get(move_id) or {}
                if raw_id in moved:
                    ue5, obligation = moved[raw_id], True
                elif raw_id in UE5_NAME:
                    ue5 = UE5_NAME[raw_id]
                    obligation = ue5 is not None
                else:
                    ue5, obligation = "UNMAPPED", None
                entry["events"].append({
                    "godot_const": evconst, "godot_id": raw_id,
                    "t_source": traw.strip(), "t": t,
                    "t_error": why, "ue5": ue5,
                    "has_vfx_obligation": obligation})

        # A3's three marks carry the angle/reach/offset that make them countable
        m = re.search(r"move\.traces\s*=\s*\[(.*?)\]\s*\n", body, re.S)
        if m:
            traces = []
            for tm in re.finditer(
                    r'\{\s*"t"\s*:\s*([^,]+),\s*"angle"\s*:\s*' + NUM +
                    r',\s*"reach"\s*:\s*' + NUM + r',\s*"weight"\s*:\s*' + NUM +
                    r',\s*"offset"\s*:\s*Vector2\(\s*' + NUM + r'\s*,\s*' + NUM + r'\s*\)',
                    m.group(1)):
                t, why = resolve(tm.group(1), consts)
                traces.append({"t": t, "t_source": tm.group(1).strip(),
                               "t_error": why,
                               "angle_deg": float(tm.group(2)),
                               "reach_m": float(tm.group(3)),
                               "damage_weight": float(tm.group(4)),
                               "lens_offset": [float(tm.group(5)), float(tm.group(6))]})
            if traces:
                entry["traces"] = traces

        # total, from the four phase durations the Sword line authored
        parts, missing = 0.0, []
        for k in ("startup", "strike", "follow_time", "recovery"):
            v = entry["fields"].get(k)
            if isinstance(v, float):
                parts += v
            else:
                missing.append(k)
        entry["total_from_phases"] = round(parts, 4) if not missing else None
        entry["total_missing_phases"] = missing

        # Two beats (A3, the draw) do not express their length as four phases.
        # They name it instead, as <PREFIX>_TOTAL, so it is read from the
        # constants the beat's own events refer to rather than guessed. The draw
        # references BOTH the live NE_* family and the superseded EQUIP_* one,
        # so every candidate is emitted with the prefix it came from and the
        # best-supported one is picked - silently taking EQUIP_TOTAL (0.62) for
        # the five-beat draw would put the whole contract out by a second.
        prefixes = {}
        for e in entry["events"]:
            for tok in [e["t_source"]] + ([e["godot_const"]] if e["godot_const"] else []):
                pre = str(tok).split("_")[0]
                if pre and pre.isalpha() and pre.upper() == pre:
                    prefixes[pre] = prefixes.get(pre, 0) + 1
        cands = []
        for pre, hits in prefixes.items():
            key = pre + "_TOTAL"
            if key in consts:
                cands.append({"prefix": pre, "const": key, "value": consts[key],
                              "referenced": hits})
        cands.sort(key=lambda c: -c["referenced"])
        entry["total_candidates"] = cands
        entry["total_s"] = (entry["total_from_phases"] if not missing
                            else (cands[0]["value"] if cands else None))
        entry["total_source"] = ("phases" if not missing
                                 else (cands[0]["const"] if cands else None))
        out[move_id or fn] = entry
    return out


def parse_tuning(src):
    vals = {}
    for m in re.finditer(r"^(\w+)\s*=\s*(-?\d+(?:\.\d+)?)\s*$", src, re.M):
        vals[m.group(1)] = float(m.group(2))
    return vals


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--table", action="store_true")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()

    for p in (BASIC, VFX, TUNING):
        if not os.path.exists(p):
            raise SystemExit("missing %s" % p)

    src = read(BASIC)
    consts, const_unresolved = collect_consts(src)
    id_of_const = {}
    for m in RE_CONST_STR.finditer(src):
        id_of_const[m.group(1)] = m.group(2)
        consts["__strid__" + m.group(1)] = m.group(2)
    ev_ids = {k: v for k, v in id_of_const.items() if k.startswith("EV_")}
    print("constants resolved: %d   unresolved: %d %s"
          % (len(consts), len(const_unresolved),
             sorted(const_unresolved) if const_unresolved else ""))

    moves = parse_moves(src, consts, ev_ids)
    # The four base moves now read editable config arrays. Read the exported
    # defaults, then resource overrides; never invent a failed expression value.
    for config_source in (CONFIG_SCRIPT, CONFIG_RESOURCE):
        text = read(config_source)
        for field, target in (("hit_stop", "hitstop"), ("attack_damage", "damage")):
            match = re.search(r"(?:@export\s+var\s+)?" + field + r"\s*(?::=|=)\s*PackedFloat32Array\(\[?([^\])]+)", text)
            if match:
                values = [float(value.strip()) for value in match.group(1).split(",")]
                if len(values) != 4:
                    raise ValueError("sword config must have four " + field + " values")
                for i, value in enumerate(values):
                    moves["sb_a%d" % (i + 1)]["fields"][target] = value
    tuning = parse_tuning(read(TUNING))

    iaido = []
    for ue5, key, why in IAIDO_EVENTS:
        iaido.append({"ue5": ue5, "tuning_field": key, "t": tuning.get(key),
                      "note": why,
                      "t_error": None if key in tuning
                      else "field %r absent from IaidoTuning.tres" % key})

    doc = {
        "generated_by": "ue5_lab/sword_vfx/tools/gen_event_contract.py",
        "warning": "GENERATED from the Godot source. Do not hand-edit.",
        "authority": {
            "timing": "godot/scripts/combat/sword_basic.gd + "
                      "iaido_director.gd + resources/tuning/IaidoTuning.tres",
            "appearance_in_godot": "godot/scripts/combat/sword_combat_vfx.gd",
            "sources_read": {"sword_basic.gd": BASIC, "IaidoTuning.tres": TUNING,
                             "IaidoCombatTuning.tres": COMBAT_TUNING,
                             "SwordConfig.tres": CONFIG_RESOURCE, "sword_config.gd": CONFIG_SCRIPT},
        },
        "two_event_sources": {
            "clock": {
                "what": "SwordMove.events, fired by _tick_move_events() on the "
                        "move's own clock",
                "safe_for": "sound and presentation",
                "not_safe_for": "geometry - a cut's mark must come from the "
                                "instant the cut RESOLVED",
            },
            "signal": {
                "what": "SwordReach.trace_resolved / arc_resolved, emitted when "
                        "a cut actually resolved, carrying the tested window",
                "safe_for": "marks and contact",
                "ue5_events": ["EV_SWORD_A1_HIT", "EV_SWORD_A2_HIT",
                               "EV_SWORD_A3_HIT", "EV_SWORD_A4_HIT",
                               "EV_SWORD_HIT_BODY", "EV_SWORD_HIT_STONE",
                               "EV_SWORD_HIT_METAL", "EV_SWORD_HIT_WOOD"],
                "note": "these have no t; they fire on a frame",
            },
        },
        "moves": moves,
        "iaido": {"events": iaido, "tuning": tuning,
                  "phase_map_comment": "see iaido_director.gd header: "
                                       "0.00 A silence .. 9.15 N restore"},
        "inspect": INSPECT_BLOCKED,
        "combat_iaido": {"tuning": parse_tuning(read(COMBAT_TUNING)),
                         "note": "live combat profile; iaido above retains the long Demo"},
        "runtime_weapon_events": {
            "signal": "SwordCombatVFX.weapon_event(event: StringName, payload: Dictionary)",
            "version": 1,
            "names": sorted(set(re.findall(r'&"((?:SWORD|IAIDO)_[A-Z_]+)"', read(VFX) + read(DIRECTOR)))),
            "niagara_mapping": "EV_ + event name; dispatch existing move-specific effects with payload.move",
            "payload": {"version": "int", "combat_time": "float",
                        "move": "optional SwordMove id", "position": "optional world-space Vector3",
                        "direction": "optional world-space Vector3", "surface": "body/wood/stone/metal",
                        "duration": "optional seconds", "timeline_time": "optional Iaido seconds"},
            "status": "Godot signal implemented; UE Niagara transport is an interface only",
        },
        "unmapped_godot_events": sorted(
            {e["godot_id"] for mv in moves.values() for e in mv["events"]
             if e["ue5"] == "UNMAPPED"}),
    }

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=1)
    print("wrote %s" % args.out)

    unresolved = [(mid, e["godot_id"], e["t_source"], e["t_error"])
                  for mid, mv in moves.items() for e in mv["events"]
                  if e["t"] is None]
    print("moves: %d   events: %d   unresolved t: %d"
          % (len(moves), sum(len(m["events"]) for m in moves.values()),
             len(unresolved)))
    if unresolved:
        for u in unresolved:
            print("  UNRESOLVED %s %s (%s) - %s" % u)
    print("iaido events resolved: %d / %d"
          % (sum(1 for i in iaido if i["t"] is not None), len(iaido)))
    if doc["unmapped_godot_events"]:
        print("UNMAPPED godot ids: %s" % doc["unmapped_godot_events"])

    if args.table:
        print()
        for mid, mv in moves.items():
            print("== %s  total=%s s" % (mid, mv["total_s"]))
            for e in mv["events"]:
                print("   %7s  %-16s -> %-32s %s"
                      % (e["t"] if e["t"] is not None else "?", e["godot_id"],
                         e["ue5"], e["t_source"]))
            for tr in mv.get("traces") or []:
                print("   trace t=%s angle=%s reach=%s w=%s off=%s"
                      % (tr["t"], tr["angle_deg"], tr["reach_m"],
                         tr["damage_weight"], tr["lens_offset"]))
        print()
        for i in iaido:
            print("   %7s  %-26s (%s)" % (i["t"], i["ue5"], i["tuning_field"]))


if __name__ == "__main__":
    main()
