# SWORD CURRENT STATUS REPORT

2026-10-12 · F:/SEKAI · existing work preserved. This report precedes the full-upgrade edits.

| Feature | Current Implementation | Quality Problem | Upgrade Plan |
|---|---|---|---|
| Sword / Saya | Sword_FP.tscn, fp_sword.glb v9, fp_saya.glb, sword_classes.gd measured anchors | Finished blade/saya exist; no visible gripping hands | Preserve meshes; add visible glove/forearm presentation at existing sockets |
| Transform contract | +Y blade/bore, -X edge; registry guard setback and extraction; SwordSayaRig / SayaHandDriver | Several older tuning values still describe the placeholder; independent owners must not show two sayas | Document actual registry contract; drive hands from the owning live sword/saya transforms |
| Weapon manager | Existing draw/sheath transitions, reversal fix and safe attack interruption | No editable animation library on the sword presentation | Keep state owner; add synchronized AnimationPlayer presentation clips |
| A1 / A2 | Small draw-cut to right, body-led left return with physical travelling wave | A1 24ms contact stop, thin motion feedback; blade appeared detached | 30–50ms light stop, distinct per-move trails and visible grip |
| A3 | Three timed space cuts, 46 total damage / 26 posture, curved partial sheath returns | Pasted brief asks for an uppercut; existing triple-cut grammar differs | Keep the established three-cut mechanic; make the final cut rise and give contacted bodies a bounded upward/backward reaction |
| A4 | 270-degree six-sector major arc, continuous envelope after polish pass 02 | 55ms finish contact stop; little impact distinction | Raise the finisher's contact emphasis and preserve the rear gap |
| Heavy | uni_heavy with charge, posture and separate pose | 58ms contact stop below new 80–120ms target | Tune to 90ms with restrained directional impulse |
| Hit / damage / state | CombatController, Area3D hitbox, SwordReach, CombatHurtbox | Earlier fixes already prevent A2 double damage and restore A3 per-cut hits | Preserve and re-run receipt tests |
| Iaido | IaidoDirector / world pause / screen split / glass / audio / real bore motion | Current timeline lasts 9.9s; user now wants a 1.5–3s combat cast | Keep long Demo; author a 2.75s combat resource and reuse the same physical sequence |
| Recovery | Existing controlled 0.933-turn recovery, bore repoint then edge alignment | Brief's two-turn criticism refers to an older demo | Preserve the current single-turn solution; shorten its combat profile |
| Parry | 120ms perfect window, attacker stagger, metal cue, white flash, counter window | No blade-local sparks; generic trauma is high | Add small local sparks and retain existing enemy/counter logic |
| VFX | Per-move events, wave, space-cut planes, major arc, historical ribbon | No unified external event contract for hit/parry/Iaido | Expose typed event payloads from existing runtime signals; keep Godot effects and provide a Niagara mapping |
| Audio | Layered atom registry, swing identities, body/wood/stone/metal contacts; 14 Iaido cues | Long-form cue durations can overlap inside a short cast | Retime existing cue events and trim combat-only tails; preserve dry core transients |
| Skills / ultimate | SwordSkill ATTACK/MOBILITY etc.; universal sword already has the named pressure skill, plus style/ultimate interfaces | Universal sword has no sword-step entry | Preserve existing pressure; add step through current move/skill resources; reserve universal ultimate |
| Camera | CameraFeedbackController, FOV impulses, held Iaido clock | Must remain comfortable; no human acceptance yet | Restrained camera, smooth restoration; no extra random shaking |
| Tuning | SwordMove, SwordMoveset, SwordGuardProfile, CombatTuning, IaidoTuning resources | A second config could duplicate existing sources of truth | Add one presentation config for new parameters, retaining existing combat data owners |
| Training / evidence | Current TrainingGround, sword_core_lab, material fixtures, sentinel; pass-02 movie | Pass-02 movie omits draw/parry/dodge/full Iaido | Record a continuous input-driven Sword_Final_Test.mp4 in TrainingGround with event receipts |

## Identity and implementation sequence

First Person Iaido Fantasy Sword: precision, speed, space cutting, deliberate sheath closure. Preserve current first-person controllers and physical bore paths. Build the short combat profile first, then visible hand/AnimationPlayer presentation, reaction/parry/event integration, named skills and config. Finish with repeatable gameplay checks and a real rendered training take.

This is polish + upgrade + integration. No new input map, enemy AI, equipment system, skill tree or combat framework. The existing A3 three-cut structure is explicitly retained as its space-control identity; the final rising cut supplies the requested uppercut finish. Stylized procedural gloves are a first-person presentation asset, not a claim of finished anatomical or motion-capture animation.
