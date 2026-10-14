"""Generate docs/EVENT_INTEGRATION.md - how a sword event becomes VFX.

    python tools/gen_event_integration.py

Three sources, and each one is authoritative for a different thing:

    docs/sword_vfx_event_contract.json   the EVENT NAMES and their times
                                         (itself generated from the Godot source)
    source/sword_visual_profile.json     which slot each moment uses, per sword
    exports/p11_report.json              the User.* names that really exist

The one authored thing here is EVENT_MAP below: the contract knows what the
events are called and when they fire, but nothing in either file says what a
given event should DO. That mapping is a design decision and is written down
once, here, rather than being scattered across a Blueprint.

The generator also reports events the contract lists that EVENT_MAP does not
cover. An unmapped event is not a warning to be smoothed over: it means the
Sword line will fire something that no VFX will answer, which is invisible
until someone watches the animation and notices a beat with nothing on it.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CONTRACT = os.path.join(ROOT, "docs", "sword_vfx_event_contract.json")
PROFILE = os.path.join(ROOT, "source", "sword_visual_profile.json")
REPORT = os.path.join(ROOT, "exports", "p11_report.json")
OUT = os.path.join(ROOT, "docs", "EVENT_INTEGRATION.md")

# ---------------------------------------------------------------------------
# THE AUTHORED MAPPING
#
# event -> (slot or None, action, note)
#
# action vocabulary, kept deliberately small so it can be implemented directly:
#   set       write User.* on a system; do not start it
#   activate  write User.*, then start the system
#   stop      stop the system
#   reset     return every slot to zero (the end of a presentation beat)
#   drive     the value is not fixed - it comes from the animation/geometry
# ---------------------------------------------------------------------------
EVENT_MAP = {
    # ---- equip: five beats, times from NE_* in the Godot source
    "EV_SWORD_EQUIP_BEGIN":
        (None, "reset", "nothing on screen yet; clears anything left over"),
    "EV_SWORD_EQUIP_PARTIAL_DRAW":
        ("SheatheVFX", "drive",
         "Magic only: a thread of black mist leaks from the saya mouth and "
         "disperses. Drive User.MistAmount from how far the blade has moved, "
         "not from a timer. Normal has nothing here."),
    "EV_SWORD_EQUIP_GLINT":
        ("EquipGlint", "activate",
         "the cold glint: 12-20 cm of exposed blade, one narrow highlight "
         "scanning along it, 80-160 ms. This is a slot, not a new effect."),
    "EV_SWORD_EQUIP_FULL_DRAW":
        ("BladeTrail", "set",
         "blade is fully out; arm the trail but do not start it"),
    "EV_SWORD_EQUIP_END":
        (None, "reset", "equip is over; nothing should still be alive"),

    # ---- inspect: timing is BLOCKED (see section 5), names are stable
    "EV_SWORD_INSPECT_BEGIN":
        (None, "reset", "clean slate before the inspect beat"),
    "EV_SWORD_INSPECT_GLINT":
        ("InspectGlint", "activate",
         "the SAME glint core as equip, retuned: slower, base -> tip. This is "
         "why the glint is one parameterised component and not two effects."),
    "EV_SWORD_INSPECT_ALIGN_SAYA":
        ("SheatheVFX", "set",
         "Magic only: black mist rises slightly on ONE side behind the sword. "
         "It must not cross the blade - the blade material stays readable."),
    "EV_SWORD_INSPECT_END":
        (None, "reset", "all slots to zero"),

    # ---- A1
    "EV_SWORD_A1_SHEATH_TOUCH":
        ("EquipGlint", "activate",
         "the saya contact cue. Fired by BOTH sb_a1 and sb_equip at t=0, so it "
         "must be idempotent - a re-fire at the same instant is not a bug."),
    "EV_SWORD_A1_DRAW":
        ("BladeTrail", "activate", "edge trail on; thin is the identity"),
    "EV_SWORD_A1_ACTIVE":
        ("A1Slice", "activate",
         "peak: the edge trail stops and the thin air slice is drawn on "
         "start -> end. 1.5-2.5 m. NOT a projectile - it must not travel."),
    "EV_SWORD_A1_HIT":
        ("HitBody", "drive",
         "contact family, fired by the SIGNAL not the clock - it has no `t`, "
         "because a hit happens on the frame the trace resolves, not at a "
         "scheduled time. Which of HitBody/HitStone/HitMetal/HitWood depends on "
         "the surface the trace found and is passed in, never hard-coded."),
    "EV_SWORD_A1_FINISH":
        (None, "reset",
         "the little iaido cut is over. Trail and slice both go; nothing about "
         "A1 survives this event."),

    # ---- A2
    "EV_SWORD_A2_RELEASE":
        ("BladeTrail", "activate", "the release swing's edge"),
    "EV_SWORD_A2_WAVE":
        ("A2Wave", "activate",
         "a thin curved PRESSURE SHEET, 8.4 m at 26 m/s = 0.323 s of flight. "
         "NOT a thick crescent; bright edge, faint interior, distortion in the "
         "tail only."),
    "EV_SWORD_A2_HIT":
        ("HitBody", "drive", "same contact family as A1"),
    "EV_SWORD_A2_FINISH":
        (None, "reset",
         "the sheet has flown its 8.4 m. Deactivate rather than let it die on "
         "its own lifetime, so the tail is bounded by the move and not by a "
         "number in the graph."),

    # ---- A3
    "EV_SWORD_A3_SHEATHE":
        ("SheatheVFX", "drive",
         "the wind-up: the blade returns to the saya before the domain opens "
         "(A3_RETURN_HOME). For the magic sword this is where the mist starts "
         "going down, exactly as in the Iaido sheathe - it is the same idea at "
         "a smaller scale."),
    "EV_SWORD_A3_DOMAIN_BEGIN":
        (None, "set",
         "the domain opens. Three traces are about to be drawn; nothing is on "
         "screen yet, and nothing should be - A3's power is that the three "
         "marks appear one at a time."),
    "EV_SWORD_A3_CUT_1":
        ("A3Scar", "activate",
         "scar 1 of 3, trace 1: +38 deg, 14 m. Draw start -> end in 20-60 ms, "
         "hold 120-250 ms, fade ~100 ms. World space. One scar per cut event - "
         "this system is activated three times with DIFFERENT geometry, not "
         "once with three particles."),
    "EV_SWORD_A3_CUT_2":
        ("A3Scar", "activate",
         "scar 2 of 3, trace 2: -34 deg, 16 m. All three must briefly coexist "
         "and still read as 1/2/3."),
    "EV_SWORD_A3_CUT_3":
        ("A3Scar", "activate",
         "scar 3 of 3, trace 3: +4 deg, 18 m, wider. For the magic sword this "
         "is the hero frame: if it reads as one mass of purple-black smoke, it "
         "has FAILED."),
    "EV_SWORD_A3_DOMAIN_END":
        (None, "reset", "the domain closes; all three scars go"),

    # ---- A4
    "EV_SWORD_A4_ARC_BEGIN":
        ("BladeTrail", "activate",
         "the arc forms LIVE with the blade: the trail is what tells the player "
         "where the sweep has got to"),
    "EV_SWORD_A4_ACTIVE":
        ("A4Arc", "activate",
         "270 degrees of arc - NOT a 360 ring. ArcStart/ArcEnd exist so it "
         "cannot silently close. Read from the Top camera: the START and the "
         "END must both be visible."),
    "EV_SWORD_A4_ARC_END":
        (None, "reset", "arc gone; everything to zero"),

    # ---- contact family: SIGNAL-driven, no t, fires on the resolved frame
    "EV_SWORD_A3_HIT":
        ("HitBody", "drive",
         "A3's marks resolve per trace (14 m, 16 m, 18 m), so this fires "
         "whenever a trace finds something - up to three times in one A3."),
    "EV_SWORD_A4_HIT":
        ("HitBody", "drive",
         "the sweep's contact. Same family; the arc is 270 degrees so this can "
         "legitimately fire several times in one pass."),
    "EV_SWORD_HIT_BODY":
        ("HitBody", "drive", "surface: flesh. The blade's own colour - a sword "
         "that cuts space must not flash purple on a body."),
    "EV_SWORD_HIT_STONE":
        ("HitStone", "drive", "surface: stone. The substrate test - a sword "
         "that cuts space should read differently on stone."),
    "EV_SWORD_HIT_METAL":
        ("HitMetal", "drive", "surface: metal. The overdraw risk of the four; "
         "keep it the lowest particle count, not the brightest."),
    "EV_SWORD_HIT_WOOD":
        ("HitWood", "drive", "surface: wood. The softest of the four, and the "
         "only one where a little material breakup is allowed."),

    # ---- Iaido: the new motion, one orientation reset, then CLICK
    "EV_IAIDO_DRAW":
        ("IaidoDraw", "activate",
         "100 ms axial draw, t=4.68. Normal: cold glint. Magic: purple glint."),
    "EV_IAIDO_CUT":
        ("IaidoScar", "activate",
         "t=5.02, the cut. Magic: the void scar, mist leaking gently along the "
         "scar normal - never a burst."),
    "EV_IAIDO_ROTATE":
        (None, "set",
         "the one orientation reset. Deliberately has no VFX: the beat that "
         "must read here is the BLADE's position, and adding an effect to it "
         "would cover the thing being judged."),
    "EV_IAIDO_SAYA_TOUCH":
        ("SheatheVFX", "drive",
         "the blade spine meets the saya. From here User.MistAmount only goes "
         "DOWN. Drive it from the blade's remaining distance, not a timer."),
    "EV_IAIDO_MOUTH_FIND":
        ("SheatheVFX", "drive",
         "the tip finds the mouth. Mist continues to reduce; nothing new "
         "starts."),
    "EV_IAIDO_SHEATHE_BEGIN":
        ("SheatheVFX", "drive",
         "the blade is truly inside: the mist is suctioned back in. Nothing "
         "may spawn after this point."),
    "EV_IAIDO_CLICK":
        ("SheatheVFX", "drive",
         "t=8.40, the final click. ONE point at the saya mouth for 20-50 ms, "
         "then ALL VFX return to zero. This is the last thing the player sees "
         "in the whole sequence and it must be clean. For the magic sword this "
         "single beat is what the whole 'darkness leaks through the cut' idea "
         "resolves on: the click pulls the mist back in."),
}


# ---------------------------------------------------------------------------
# RESERVED: named by the brief, not yet emitted by the Sword line.
#
# These are mapped above because the brief's section 3 requires them to exist in
# the contract, but the Godot source does not fire them yet - the hit events come
# out of the trace/contact system rather than out of the move, and the Inspect
# move does not exist at all. Separating them from "stale" matters: stale means
# someone renamed an event and this file was not updated, which is a defect.
# Reserved means the mapping is written and waiting, which is a plan.
# ---------------------------------------------------------------------------
RESERVED = {
    "EV_SWORD_INSPECT_BEGIN",
    "EV_SWORD_INSPECT_GLINT",
    "EV_SWORD_INSPECT_ALIGN_SAYA",
    "EV_SWORD_INSPECT_END",
}


def load(p):
    with open(p, encoding="utf-8") as fh:
        return json.load(fh)


def main():
    contract = load(CONTRACT)
    profile = load(PROFILE)
    report = load(REPORT)

    params = {p["name"] for p in report.get("user_params", [])}
    slots = [k for k in profile["slot_map"] if not k.startswith("_")]

    def ev_name(e):
        """The UE5 event name, or "" when the contract has none.

        Coerced to a string rather than left as None so the coverage check can
        sort and diff without mixing types. An event with no UE5 name cannot be
        wired at all, so it is deliberately NOT hidden - it shows up as an
        unmapped entry named "(no UE5 name)".
        """
        return e.get("ue5") or ""

    def show(name):
        return "`%s`" % name if name else "*(no UE5 name)*"

    def has_vfx(e):
        """False only when the contract says so explicitly.

        The contract writes `has_vfx_obligation: false` for a beat the Sword
        line fires that VFX is meant to ignore (EQUIP_CARRY, the assembly being
        brought up before the glint). Absent means "assume there is one", so a
        missing key can never silently excuse an event from being answered.
        """
        return e.get("has_vfx_obligation") is not False

    L = []
    A = L.append
    A("# SWORD VFX - EVENT INTEGRATION")
    A("")
    A("> **GENERATED** by `tools/gen_event_integration.py` from "
      "`docs/sword_vfx_event_contract.json`, `source/sword_visual_profile.json` "
      "and `exports/p11_report.json`. Do not hand-edit.")
    A("")
    A("Event names and times come from the Godot source of truth via the "
      "contract. The profile says what each moment looks like on each sword. "
      "This file says what each event DOES, which is the one thing neither of "
      "the others states.")
    A("")

    # ---------------------------------------------------------------- model
    A("## 1. The integration model")
    A("")
    A("An event does exactly two things, in this order:")
    A("")
    A("1. **write `User.*`** on the profile's system for that slot")
    A("2. **start** it (`Activate`) - or not, if this slot drives an "
      "already-running system")
    A("")
    A("Niagara must never guess timing from its own delays. Everything it needs "
      "about WHEN arrives as one of these events; everything about WHAT is a "
      "`User.*` value. A system that appears to know about time is a bug.")
    A("")
    A("Three consequences worth stating, because each has a specific failure:")
    A("")
    A("| Rule | What goes wrong if broken |")
    A("|------|---------------------------|")
    A("| Write `User.*` **before** `Activate` | the first frame runs on the "
      "previous slot's values - a white glint flashes purple for one frame |")
    A("| `reset` at the end of every beat, not just at the start of the next "
      "one | a dropped event leaves the last effect alive forever |")
    A("| Contact events pass `material` and `intensity` in | a sword that cuts "
      "space flashes the same on stone as on flesh |")
    A("")
    A("Two event sources exist and they are not interchangeable. The contract "
      "records both, and picking the wrong one has a specific consequence - "
      "which is why the contract states `not_safe_for` as well as `safe_for`:")
    A("")
    clock = contract["two_event_sources"]["clock"]
    signal = contract["two_event_sources"]["signal"]
    A("| Source | What it is | Safe for | NOT safe for |")
    A("|--------|------------|----------|--------------|")
    A("| **clock** | %s | %s | %s |"
      % (clock.get("what"), clock.get("safe_for"),
         clock.get("not_safe_for")))
    A("| **signal** | %s | %s | - |"
      % (signal.get("what"), signal.get("safe_for")))
    A("")
    A("%s" % signal.get("note", ""))
    A("")
    A("In practice: presentation (glints, trails, the wave) rides the move's "
      "clock, because it must line up with the animation. Anything that leaves "
      "a MARK - a scar, a contact flash - rides the signal, because a mark must "
      "appear at the instant the cut actually resolved, not at the instant the "
      "move's timer said it should have.")
    A("")

    # --------------------------------------------------------------- table
    A("## 2. Per-move event map")
    A("")
    A("`t` is seconds from the start of the move, straight out of the "
      "contract - i.e. owned by the Sword line, not by VFX.")
    A("")

    seen = set()
    no_vfx = []
    for move_id, mv in contract["moves"].items():
        A("### `%s`  (total %s s, source: %s)"
          % (move_id, mv.get("total_s"), mv.get("total_source")))
        A("")
        fields = mv.get("fields") or {}
        if fields:
            A("Gameplay fields that matter to VFX: "
              + ", ".join("`%s`=%s" % (k, v) for k, v in sorted(fields.items())
                          if k in ("reach_mode", "reach", "reach_speed",
                                   "trail_width_scale", "reach_radius",
                                   "reach_arc_from", "reach_arc_to",
                                   "arc_slices", "hitstop"))
              + ".")
            A("")
        A("| t (s) | Event | Slot | Action | What it does |")
        A("|-------|-------|------|--------|--------------|")
        for e in sorted(mv["events"], key=lambda e: (e.get("t") is None,
                                                     e.get("t") or 0)):
            name = ev_name(e)
            tcol = "?" if e.get("t") is None else e["t"]
            if not has_vfx(e):
                no_vfx.append((name or e.get("godot_id"), e.get("t")))
                A("| %s | %s | - | *(no VFX by design)* | the Sword line fires "
                  "it; the contract assigns it no VFX obligation |"
                  % (tcol, show(name)))
                continue
            seen.add(name)
            slot, action, note = EVENT_MAP.get(name, (None, "**UNMAPPED**", ""))
            A("| %s | %s | %s | %s | %s |"
              % (tcol, show(name), "`%s`" % slot if slot else "-", action, note))
        A("")

    A("### Iaido (the new motion)")
    A("")
    A("| t (s) | Event | Slot | Action | What it does |")
    A("|-------|-------|------|--------|--------------|")
    for e in sorted(contract["iaido"]["events"], key=lambda e: e.get("t") or 0):
        name = ev_name(e)
        seen.add(name)
        slot, action, note = EVENT_MAP.get(name, (None, "**UNMAPPED**", ""))
        A("| %s | %s | %s | %s | %s |"
          % (e.get("t"), show(name), "`%s`" % slot if slot else "-",
             action, note))
    A("")

    # --------------------------------------------- frame-based (the signal)
    A("### Contact events - signal-driven, no `t`")
    A("")
    A("These come from `SwordReach.trace_resolved` / `arc_resolved` rather than "
      "from the move's clock, and they carry no time because they fire on the "
      "frame the cut actually resolved. Anything that leaves a MARK must be "
      "driven from here: using the move clock would place the mark at the "
      "instant the cut was SCHEDULED, which is a different instant whenever the "
      "animation and the trace disagree - and the brief is explicit that a "
      "scar's geometry comes from the resolved reach, not from the clock.")
    A("")
    signal_events = contract["two_event_sources"]["signal"].get("ue5_events") or []
    A("| Event | Slot | Action | What it does |")
    A("|-------|------|--------|--------------|")
    for name in signal_events:
        seen.add(name)
        slot, action, note = EVENT_MAP.get(name, (None, "**UNMAPPED**", ""))
        A("| %s | %s | %s | %s |"
          % (show(name), "`%s`" % slot if slot else "-", action, note))
    A("")

    # -------------------------------------------------------------- inspect
    A("## 3. Inspect is BLOCKED, and this is what that means")
    A("")
    insp = contract["inspect"]
    A("- **Status:** `%s`" % insp.get("status"))
    A("- **Requested by the brief:** %s"
      % ", ".join("`%s`" % x for x in insp.get("requested_events", [])))
    A("")
    A("%s" % insp.get("note", ""))
    A("")
    A("The loop below is on the map for completeness but **cannot be wired "
      "yet**: there is no timing to fire it against, so an implementation would "
      "be guessing at when the glint happens. The four Inspect events need the "
      "Sword line to publish their `t` values. The glint itself is not blocked - "
      "it is the same core the equip glint uses.")
    A("")

    # ---------------------------------------------------------------- check
    A("## 4. Coverage check (derived)")
    A("")
    unmapped = sorted(seen - set(EVENT_MAP))
    # Reserved is MAPPED BUT NOT EMITTED, so it comes from the mapping, not from
    # the contract - the whole point is that the contract does not have these
    # yet. Intersecting with `seen` (the first version of this line) yielded an
    # empty set by construction and would have reported 0 reserved forever.
    reserved = sorted(set(EVENT_MAP) & RESERVED)
    stale = sorted((set(EVENT_MAP) - seen) - RESERVED)
    A("| | Count |")
    A("|---|---|")
    A("| events with a VFX obligation | %d |" % len(seen))
    A("| ...of those, mapped | %d |" % (len(seen) - len(unmapped)))
    A("| ...of those, unmapped | %d |" % len(unmapped))
    A("| ...of those, reserved (brief-required, not yet emitted) | %d |"
      % len(reserved))
    A("| events the contract marks as no-VFX by design | %d |" % len(no_vfx))
    A("| mappings for events that no longer exist | %d |" % len(stale))
    A("")
    if unmapped:
        A("**Unmapped events** - these will fire and nothing will answer them:")
        A("")
        for u in unmapped:
            A("- %s" % show(u))
        A("")
    if reserved:
        A("**Reserved** - mapped in this file and waiting for the Sword line to "
          "emit them. Not a defect; the mapping is written so that wiring them "
          "is a one-line change when the source starts firing them:")
        A("")
        for r in reserved:
            slot = EVENT_MAP[r][0]
            A("- %s -> %s" % (show(r), "`%s`" % slot if slot else "*(cleanup)*"))
        A("")
    if no_vfx:
        A("**No VFX by design** - the Sword line fires these and the contract "
          "states they carry no VFX obligation. Listed so that \"no mapping\" "
          "and \"deliberately unmapped\" cannot be confused later:")
        A("")
        for n, t in no_vfx:
            A("- `%s` (t=%s)" % (n, t))
        A("")
    if stale:
        A("**Stale mappings** - the contract no longer lists these, so the "
          "event was renamed or removed and this file was not updated. This is "
          "a defect, unlike the reserved list above:")
        A("")
        for s in stale:
            A("- `%s`" % s)
        A("")
    if not unmapped and not stale:
        A("Every event carrying a VFX obligation has exactly one mapping, and "
          "no mapping refers to an event that no longer exists."
          + (" The %d reserved mappings are waiting on the Sword line."
             % len(reserved) if reserved else ""))
        A("")

    # ---------------------------------------------------------------- slots
    used = {EVENT_MAP[e][0] for e in EVENT_MAP if EVENT_MAP[e][0]}
    unused = [s for s in slots if s not in used]
    A("## 5. Slot coverage")
    A("")
    A("Slots the event map drives: **%d of %d**."
      % (len(used), len(slots)))
    A("")
    if unused:
        A("Slots that no event drives directly - each of these is reached by "
          "another slot's system or is driven by distance rather than by an "
          "event, so it is worth confirming rather than assuming:")
        A("")
        for s in unused:
            A("- `%s` - realised by %s"
              % (s, ", ".join("`%s`" % x
                             for x in profile["slot_map"][s])))
        A("")

    # -------------------------------------------------------------- manual
    A("## 6. What is NOT automatable here")
    A("")
    A("The calls in section 1 are gameplay code. This project is Blueprint-only "
      "and neither a Blueprint class nor its member variables can be authored "
      "from Python, so the node that performs `set-then-activate` is a "
      "`MANUAL EDITOR STEP`.")
    A("")
    A("What is not manual is everything above it: which event fires, at what "
      "time, which slot it drives, which core system that slot maps to on each "
      "sword, and which `User.*` names exist to be written. Those are all "
      "generated from the sources and cannot drift.")
    A("")

    # -------------------------------------------------------------- status
    A("## 7. Status")
    A("")
    A("| Item | State |")
    A("|------|-------|")
    A("| Event names + times | `SPEC READY` - generated from Godot |")
    A("| Event -> slot -> system map | `SPEC READY` - this file |")
    A("| `User.*` names to write | `ASSET READY` - on the built systems |")
    A("| Ordering rule (set before activate) | `SPEC READY` |")
    A("| Blueprint/gameplay binding | *not built* - needs the editor |")
    A("| Firing against a real animation | *not verified* - needs the Sword line |")
    A("")
    A("Per the brief's completion vocabulary, nothing here is `IMPLEMENTED`: no "
      "Niagara graph is being driven by a real event yet. Reporting otherwise "
      "would be exactly the confusion section 35 forbids.")
    A("")
    A("### Parameters a profile may write")
    A("")
    A("These are the %d names the built systems really expose - checked "
      "against `exports/p11_report.json`, so a name here is one a graph "
      "actually has." % len(params))
    A("")
    for p in sorted(params):
        A("- `%s`" % p)
    A("")

    text = "\n".join(L) + "\n"
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)

    print("wrote %s" % OUT)
    print("  contract events   : %d" % len(seen))
    print("  mapped            : %d" % (len(seen) - len(unmapped)))
    print("  unmapped          : %d %s" % (len(unmapped), unmapped or ""))
    print("  reserved          : %d %s" % (len(reserved), reserved or ""))
    print("  no-vfx by design  : %d" % len(no_vfx))
    print("  stale mappings    : %d %s" % (len(stale), stale or ""))
    print("  slots driven      : %d / %d" % (len(used), len(slots)))


if __name__ == "__main__":
    main()
