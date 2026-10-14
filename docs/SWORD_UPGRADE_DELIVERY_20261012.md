# SWORD UPGRADE DELIVERY

Implementation delivered for this pass. Commercial visual quality and human play/comfort acceptance remain open.

## MODEL

- Preserved the existing sword v9 and real saya, registry dimensions and first-person integration.
- Added visible stylized gripping gloves, wrists, tapered sleeves and shoulder/elbow contribution. Both hands follow the actual owners during draw, cuts, parry, sheath and Iaido.
- Transform ownership and measured anchors are documented in `SWORD_SAYA_TRANSFORM_CONTRACT.md`.

## COMBAT

- A1–A4 remains the existing playable chain. A3 preserves three spatial cuts and now finishes upward, with a small visual body lift/backward tilt; this deliberately differs from a single-hit uppercut.
- Contact stops: A1 32ms, A2 38ms, A3 30ms, A4 80ms; universal heavy 90ms. A2/A3 damage delivery fixes remain intact.
- Perfect guard retains actual enemy stagger/counter behavior; random trauma is capped and blade-local sparks were added.
- Existing sword pressure skill remains; sword step reuses the mobility cut with a cooldown. Universal ultimate remains reserved.

## ANIMATION

- Native `SwordAnimationPlayer` with ten editable clips: Idle, Draw Sword, Sheath Sword, Attack A1–A4, Parry, Iaido, Skill.
- Library: `godot/resources/animations/SwordPresentation.tres`. Presentation tracks animate grip tension and elbow/shoulder contribution, synchronized to actual move/equip clocks.
- The blade's working procedural quaternion/curved-bore solver is preserved. This is not a completed skeleton/AnimationTree replacement.

## IAIDO

- Combat: authored 2.75-second profile, 100ms draw, delayed space cut, controlled single turn (0.933 turns), mouth alignment, 0.70-second return/sheath and final closure.
- Long 9.9-second Demo remains available through the director's default `start_iaido()`; live player combat selects `start_iaido(true)`.
- Prepare / Draw / Strike / Sheath / End phases are exposed. End is emitted at completion, not the start of restoration.
- Completion, abort and death restore time scale, pause ownership, FOV, audio, sword/saya ownership and the Demo tuning resource.

## VFX

- Historical blade ribbon; distinct lifetimes 55 / 90 / 50 / 140ms for A1–A4.
- Continuous major-arc sector envelope, three directional spatial marks, small material-aware contact effects and warm parry sparks.
- Eight versioned runtime events: SWORD_DRAW / SWING / HIT / PARRY and IAIDO_START / DRAW / SLASH / SHEATH. Existing generated UE contract was extended and regenerated, rather than hand-edited.
- Godot signal is implemented. Niagara mapping is an interface; no UE transport/deployment was performed.

## AUDIO

- Reused current actual layered atom/cue assets and body/wood/stone/metal routing.
- Short Iaido retimes the cue timeline without increasing pitch. Tails are bounded and fade over the final 40ms before stopping; the long Demo keeps its original playback.
- Final movie records native game audio; no replacement offline mix. Sound registry gate reports 156 atoms, 68 groups, 28 cues. Three existing requested atoms remain pending: glass_high_tick, glass_tinkle, wood_sheath_tick.
- Human listening acceptance remains unperformed.

## DATA / CAMERA

- `godot/resources/tuning/SwordConfig.tres` controls damage, combo window, per-cut hitstop, heavy hitstop, camera strength, draw and sheath duration; it links the presentation and combat-Iaido resources for trail lifetime and Iaido duration.
- Existing contact feedback gains a bounded 6–10mm positional recoil and smooth decay. Trace cuts retain their stable camera; parry keeps the white flash/FOV response without strong random shake.

## FILES CHANGED (this upgrade)

- `godot/scripts/weapons/sword_config.gd`, `sword_presentation_config.gd`, `sword_hand_presentation.gd`
- `godot/resources/tuning/SwordConfig.tres`, `SwordPresentationConfig.tres`, `IaidoCombatTuning.tres`
- `godot/resources/animations/SwordPresentation.tres`
- `godot/scripts/player/temp_sword_visual.gd`
- `godot/scripts/camera/camera_feedback_controller.gd`
- `godot/scripts/combat/sword_basic.gd`, `sword_reach.gd`, `sword_hit_reaction.gd`, `sword_combat_vfx.gd`, `moveset_library.gd`, `combat_controller.gd`, `weapon_manager.gd`, `iaido_director.gd`, `iaido_audio_timeline.gd`
- `godot/tests/sword_upgrade_integration.gd`, `iaido_integration.gd` (long Demo explicitly selected by its existing gate)
- `godot/tools/sword_final_test.gd`
- `ue5_lab/sword_vfx/tools/gen_event_contract.py`, generated `ue5_lab/sword_vfx/docs/sword_vfx_event_contract.json`
- This delivery report, current-state audit and transform contract.

## VERIFIED / KNOWN ISSUES

- Real Compatibility renderer: upgrade integration PASS and clean exit 0, including hand foreground copies, native clips, short cast, immediate follow-up, death/abort and parry event/sparks.
- Existing core damage, guard, sound-language and long-Demo assertions PASS. Blade clearance and ribbon/sector timing regression PASS. Generated contract resolves 22 move events and seven long-Demo events, without missing timing.
- Existing sandbox zero-vector messages and some resource teardown warnings remain. The first headless upgrade run passed its assertions then hit Godot 4.4.1 signal 11 during shutdown; rendered runs passed with exit 0. It is not a clean headless gate.
- Glove/arm assets are stylized procedural prototypes. Formal anatomy/rigging, close finger/cloth intersection review and commercial material detail remain open.
- A3 is the existing triple spatial sequence with an upward finish, not a wholesale replacement by a single uppercut. No input map, enemy AI, equipment system, skill tree or combat framework was rebuilt.
- Recorded test is continuous scripted input with marked fixture resets, not a human session. Native 60fps capture is not a gameplay performance benchmark.

## DELIVERABLES / NEXT

- `E:/SEKAI-SwordUpgrade-20261012/Sword_Final_Test.mp4`: draw, three full chains, dodge into attack, actual perfect guard/counter, sword pressure, sword step, complete combat Iaido, follow-up combat, four material contacts and sheathing.
- Event log: `Sword_Final_Test_receipt.json`; assertions: `Sword_Final_Test_acceptance.json`; visual sheet: `Sword_Final_Test_sheet.jpg`.
- Final recording: 2,477 native frames / 60fps = 41.283 seconds. Receipt verifies three complete A1–A4 chains, actual DODGE state, one perfect guard/counter, pressure, step, four contact materials, Iaido completion at 2.7667 recorded seconds and subsequent attack. Native audio is present (mono review RMS 0.05099, peak 0.88834); these measurements do not replace listening acceptance.
- Skill entries use the existing style-skill inputs (pressure F3 / step F4); the existing E/X/C/V bindings were preserved rather than reassigned to the pasted skill numbering.
- Next: artist anatomy/AnimationPlayer polish, close-range VFX clipping review and human listening/interactive comfort acceptance.
