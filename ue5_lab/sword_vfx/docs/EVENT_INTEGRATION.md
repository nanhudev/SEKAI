# SWORD VFX - EVENT INTEGRATION

> **GENERATED** by `tools/gen_event_integration.py` from `docs/sword_vfx_event_contract.json`, `source/sword_visual_profile.json` and `exports/p11_report.json`. Do not hand-edit.

Event names and times come from the Godot source of truth via the contract. The profile says what each moment looks like on each sword. This file says what each event DOES, which is the one thing neither of the others states.

## 1. The integration model

An event does exactly two things, in this order:

1. **write `User.*`** on the profile's system for that slot
2. **start** it (`Activate`) - or not, if this slot drives an already-running system

Niagara must never guess timing from its own delays. Everything it needs about WHEN arrives as one of these events; everything about WHAT is a `User.*` value. A system that appears to know about time is a bug.

Three consequences worth stating, because each has a specific failure:

| Rule | What goes wrong if broken |
|------|---------------------------|
| Write `User.*` **before** `Activate` | the first frame runs on the previous slot's values - a white glint flashes purple for one frame |
| `reset` at the end of every beat, not just at the start of the next one | a dropped event leaves the last effect alive forever |
| Contact events pass `material` and `intensity` in | a sword that cuts space flashes the same on stone as on flesh |

Two event sources exist and they are not interchangeable. The contract records both, and picking the wrong one has a specific consequence - which is why the contract states `not_safe_for` as well as `safe_for`:

| Source | What it is | Safe for | NOT safe for |
|--------|------------|----------|--------------|
| **clock** | SwordMove.events, fired by _tick_move_events() on the move's own clock | sound and presentation | geometry - a cut's mark must come from the instant the cut RESOLVED |
| **signal** | SwordReach.trace_resolved / arc_resolved, emitted when a cut actually resolved, carrying the tested window | marks and contact | - |

these have no t; they fire on a frame

In practice: presentation (glints, trails, the wave) rides the move's clock, because it must line up with the animation. Anything that leaves a MARK - a scar, a contact flash - rides the signal, because a mark must appear at the instant the cut actually resolved, not at the instant the move's timer said it should have.

## 2. Per-move event map

`t` is seconds from the start of the move, straight out of the contract - i.e. owned by the Sword line, not by VFX.

### `sb_a1`  (total 0.4 s, source: phases)

Gameplay fields that matter to VFX: `hitstop`=0.024, `reach_mode`=body, `trail_width_scale`=0.42.

| t (s) | Event | Slot | Action | What it does |
|-------|-------|------|--------|--------------|
| 0.0 | `EV_SWORD_A1_SHEATH_TOUCH` | `EquipGlint` | activate | the saya contact cue. Fired by BOTH sb_a1 and sb_equip at t=0, so it must be idempotent - a re-fire at the same instant is not a bug. |
| 0.13 | `EV_SWORD_A1_DRAW` | `BladeTrail` | activate | edge trail on; thin is the identity |
| 0.13 | `EV_SWORD_A1_ACTIVE` | `A1Slice` | activate | peak: the edge trail stops and the thin air slice is drawn on start -> end. 1.5-2.5 m. NOT a projectile - it must not travel. |
| 0.4 | `EV_SWORD_A1_FINISH` | - | reset | the little iaido cut is over. Trail and slice both go; nothing about A1 survives this event. |

### `sb_a2`  (total 0.415 s, source: phases)

Gameplay fields that matter to VFX: `hitstop`=0.032, `reach`=8.4, `reach_mode`=wave, `reach_speed`=26.0, `trail_width_scale`=1.15.

| t (s) | Event | Slot | Action | What it does |
|-------|-------|------|--------|--------------|
| 0.1 | `EV_SWORD_A2_RELEASE` | `BladeTrail` | activate | the release swing's edge |
| 0.14 | `EV_SWORD_A2_WAVE` | `A2Wave` | activate | a thin curved PRESSURE SHEET, 8.4 m at 26 m/s = 0.323 s of flight. NOT a thick crescent; bright edge, faint interior, distortion in the tail only. |
| 0.415 | `EV_SWORD_A2_FINISH` | - | reset | the sheet has flown its 8.4 m. Deactivate rather than let it die on its own lifetime, so the tail is bounded by the move and not by a number in the graph. |

### `sb_a3`  (total 1.0 s, source: phases)

Gameplay fields that matter to VFX: `hitstop`=0.02, `reach`=18.0, `reach_mode`=trace, `trail_width_scale`=0.55.

| t (s) | Event | Slot | Action | What it does |
|-------|-------|------|--------|--------------|
| 0.1 | `EV_SWORD_A3_SHEATHE` | `SheatheVFX` | drive | the wind-up: the blade returns to the saya before the domain opens (A3_RETURN_HOME). For the magic sword this is where the mist starts going down, exactly as in the Iaido sheathe - it is the same idea at a smaller scale. |
| 0.12 | `EV_SWORD_A3_DOMAIN_BEGIN` | - | set | the domain opens. Three traces are about to be drawn; nothing is on screen yet, and nothing should be - A3's power is that the three marks appear one at a time. |
| 0.16 | `EV_SWORD_A3_CUT_1` | `A3Scar` | activate | scar 1 of 3, trace 1: +38 deg, 14 m. Draw start -> end in 20-60 ms, hold 120-250 ms, fade ~100 ms. World space. One scar per cut event - this system is activated three times with DIFFERENT geometry, not once with three particles. |
| 0.34 | `EV_SWORD_A3_CUT_2` | `A3Scar` | activate | scar 2 of 3, trace 2: -34 deg, 16 m. All three must briefly coexist and still read as 1/2/3. |
| 0.54 | `EV_SWORD_A3_CUT_3` | `A3Scar` | activate | scar 3 of 3, trace 3: +4 deg, 18 m, wider. For the magic sword this is the hero frame: if it reads as one mass of purple-black smoke, it has FAILED. |
| 0.68 | `EV_SWORD_A3_DOMAIN_END` | - | reset | the domain closes; all three scars go |

### `sb_a4`  (total 0.66 s, source: phases)

Gameplay fields that matter to VFX: `arc_slices`=6.0, `hitstop`=0.055, `reach_arc_from`=-140.0, `reach_arc_to`=130.0, `reach_mode`=arc, `reach_radius`=4.2, `trail_width_scale`=1.75.

| t (s) | Event | Slot | Action | What it does |
|-------|-------|------|--------|--------------|
| 0.12 | `EV_SWORD_A4_ARC_BEGIN` | `BladeTrail` | activate | the arc forms LIVE with the blade: the trail is what tells the player where the sweep has got to |
| 0.12 | `EV_SWORD_A4_ACTIVE` | `A4Arc` | activate | 270 degrees of arc - NOT a 360 ring. ArcStart/ArcEnd exist so it cannot silently close. Read from the Top camera: the START and the END must both be visible. |
| 0.32 | `EV_SWORD_A4_ARC_END` | - | reset | arc gone; everything to zero |

### `sb_equip`  (total 1.75 s, source: phases)

Gameplay fields that matter to VFX: `trail_width_scale`=0.42.

| t (s) | Event | Slot | Action | What it does |
|-------|-------|------|--------|--------------|
| 0.0 | `EV_SWORD_EQUIP_BEGIN` | - | reset | nothing on screen yet; clears anything left over |
| 0.35 | *(no UE5 name)* | - | *(no VFX by design)* | the Sword line fires it; the contract assigns it no VFX obligation |
| 0.75 | `EV_SWORD_EQUIP_PARTIAL_DRAW` | `SheatheVFX` | drive | Magic only: a thread of black mist leaks from the saya mouth and disperses. Drive User.MistAmount from how far the blade has moved, not from a timer. Normal has nothing here. |
| 0.95 | `EV_SWORD_EQUIP_GLINT` | `EquipGlint` | activate | the cold glint: 12-20 cm of exposed blade, one narrow highlight scanning along it, 80-160 ms. This is a slot, not a new effect. |
| 1.07 | `EV_SWORD_EQUIP_FULL_DRAW` | `BladeTrail` | set | blade is fully out; arm the trail but do not start it |
| 1.4 | `EV_SWORD_EQUIP_END` | - | reset | equip is over; nothing should still be alive |

### Iaido (the new motion)

| t (s) | Event | Slot | Action | What it does |
|-------|-------|------|--------|--------------|
| 0.52 | `EV_IAIDO_SAYA_TOUCH` | `SheatheVFX` | drive | the blade spine meets the saya. From here User.MistAmount only goes DOWN. Drive it from the blade's remaining distance, not a timer. |
| 4.68 | `EV_IAIDO_DRAW` | `IaidoDraw` | activate | 100 ms axial draw, t=4.68. Normal: cold glint. Magic: purple glint. |
| 5.02 | `EV_IAIDO_CUT` | `IaidoScar` | activate | t=5.02, the cut. Magic: the void scar, mist leaking gently along the scar normal - never a burst. |
| 6.3 | `EV_IAIDO_ROTATE` | - | set | the one orientation reset. Deliberately has no VFX: the beat that must read here is the BLADE's position, and adding an effect to it would cover the thing being judged. |
| 7.3 | `EV_IAIDO_SHEATHE_BEGIN` | `SheatheVFX` | drive | the blade is truly inside: the mist is suctioned back in. Nothing may spawn after this point. |
| 7.9 | `EV_IAIDO_MOUTH_FIND` | `SheatheVFX` | drive | the tip finds the mouth. Mist continues to reduce; nothing new starts. |
| 8.4 | `EV_IAIDO_CLICK` | `SheatheVFX` | drive | t=8.40, the final click. ONE point at the saya mouth for 20-50 ms, then ALL VFX return to zero. This is the last thing the player sees in the whole sequence and it must be clean. For the magic sword this single beat is what the whole 'darkness leaks through the cut' idea resolves on: the click pulls the mist back in. |

### Contact events - signal-driven, no `t`

These come from `SwordReach.trace_resolved` / `arc_resolved` rather than from the move's clock, and they carry no time because they fire on the frame the cut actually resolved. Anything that leaves a MARK must be driven from here: using the move clock would place the mark at the instant the cut was SCHEDULED, which is a different instant whenever the animation and the trace disagree - and the brief is explicit that a scar's geometry comes from the resolved reach, not from the clock.

| Event | Slot | Action | What it does |
|-------|------|--------|--------------|
| `EV_SWORD_A1_HIT` | `HitBody` | drive | contact family, fired by the SIGNAL not the clock - it has no `t`, because a hit happens on the frame the trace resolves, not at a scheduled time. Which of HitBody/HitStone/HitMetal/HitWood depends on the surface the trace found and is passed in, never hard-coded. |
| `EV_SWORD_A2_HIT` | `HitBody` | drive | same contact family as A1 |
| `EV_SWORD_A3_HIT` | `HitBody` | drive | A3's marks resolve per trace (14 m, 16 m, 18 m), so this fires whenever a trace finds something - up to three times in one A3. |
| `EV_SWORD_A4_HIT` | `HitBody` | drive | the sweep's contact. Same family; the arc is 270 degrees so this can legitimately fire several times in one pass. |
| `EV_SWORD_HIT_BODY` | `HitBody` | drive | surface: flesh. The blade's own colour - a sword that cuts space must not flash purple on a body. |
| `EV_SWORD_HIT_STONE` | `HitStone` | drive | surface: stone. The substrate test - a sword that cuts space should read differently on stone. |
| `EV_SWORD_HIT_METAL` | `HitMetal` | drive | surface: metal. The overdraw risk of the four; keep it the lowest particle count, not the brightest. |
| `EV_SWORD_HIT_WOOD` | `HitWood` | drive | surface: wood. The softest of the four, and the only one where a little material breakup is allowed. |

## 3. Inspect is BLOCKED, and this is what that means

- **Status:** `BLOCKED_NO_GODOT_MOVE`
- **Requested by the brief:** `EV_SWORD_INSPECT_BEGIN`, `EV_SWORD_INSPECT_GLINT`, `EV_SWORD_INSPECT_ALIGN_SAYA`, `EV_SWORD_INSPECT_END`

Per brief section 1 the Godot line owns timing, so this line does not invent a duration. NS_SW_Core_Glint is the reusable component section 8 asks for and is built; the events are reserved.

The loop below is on the map for completeness but **cannot be wired yet**: there is no timing to fire it against, so an implementation would be guessing at when the glint happens. The four Inspect events need the Sword line to publish their `t` values. The glint itself is not blocked - it is the same core the equip glint uses.

## 4. Coverage check (derived)

| | Count |
|---|---|
| events with a VFX obligation | 36 |
| ...of those, mapped | 36 |
| ...of those, unmapped | 0 |
| ...of those, reserved (brief-required, not yet emitted) | 4 |
| events the contract marks as no-VFX by design | 1 |
| mappings for events that no longer exist | 0 |

**Reserved** - mapped in this file and waiting for the Sword line to emit them. Not a defect; the mapping is written so that wiring them is a one-line change when the source starts firing them:

- `EV_SWORD_INSPECT_ALIGN_SAYA` -> `SheatheVFX`
- `EV_SWORD_INSPECT_BEGIN` -> *(cleanup)*
- `EV_SWORD_INSPECT_END` -> *(cleanup)*
- `EV_SWORD_INSPECT_GLINT` -> `InspectGlint`

**No VFX by design** - the Sword line fires these and the contract states they carry no VFX obligation. Listed so that "no mapping" and "deliberately unmapped" cannot be confused later:

- `EQUIP_CARRY` (t=0.35)

Every event carrying a VFX obligation has exactly one mapping, and no mapping refers to an event that no longer exists. The 4 reserved mappings are waiting on the Sword line.

## 5. Slot coverage

Slots the event map drives: **14 of 15**.

Slots that no event drives directly - each of these is reached by another slot's system or is driven by distance rather than by an event, so it is worth confirming rather than assuming:

- `IdleVFX` - realised by `NS_SW_Core_PurpleMotes`, `NS_SW_Core_MistWake`

## 6. What is NOT automatable here

The calls in section 1 are gameplay code. This project is Blueprint-only and neither a Blueprint class nor its member variables can be authored from Python, so the node that performs `set-then-activate` is a `MANUAL EDITOR STEP`.

What is not manual is everything above it: which event fires, at what time, which slot it drives, which core system that slot maps to on each sword, and which `User.*` names exist to be written. Those are all generated from the sources and cannot drift.

## 7. Status

| Item | State |
|------|-------|
| Event names + times | `SPEC READY` - generated from Godot |
| Event -> slot -> system map | `SPEC READY` - this file |
| `User.*` names to write | `ASSET READY` - on the built systems |
| Ordering rule (set before activate) | `SPEC READY` |
| Blueprint/gameplay binding | *not built* - needs the editor |
| Firing against a real animation | *not verified* - needs the Sword line |

Per the brief's completion vocabulary, nothing here is `IMPLEMENTED`: no Niagara graph is being driven by a real event yet. Reporting otherwise would be exactly the confusion section 35 forbids.

### Parameters a profile may write

These are the 24 names the built systems really expose - checked against `exports/p11_report.json`, so a name here is one a graph actually has.

- `User.ArcAngle`
- `User.ArcEnd`
- `User.ArcStart`
- `User.BladeBase`
- `User.BladeTip`
- `User.CoreColor`
- `User.DarkColor`
- `User.Distortion`
- `User.EndPosition`
- `User.Intensity`
- `User.Length`
- `User.Lifetime`
- `User.MistAmount`
- `User.MistColor`
- `User.MistCount`
- `User.MistRate`
- `User.PrimaryColor`
- `User.Radius`
- `User.ScaleVector`
- `User.SpawnRate`
- `User.Speed`
- `User.StartPosition`
- `User.Velocity`
- `User.Width`

