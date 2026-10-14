# CURRENT STATE AUDIT + IMPLEMENTATION PLAN

2026-10-12 · F:\SEKAI · branch godot-combat-mvp. Working tree was already dirty; no existing changes reverted. Audit completed before combat edits.

## Evidence and limits

- Opened the real TrainingGround with Godot 4.4.1 / Compatibility / RX 6650 XT.
- Reviewed decoded sequences from existing sword_basic_v2.mp4, saya_body_mechanics_pass02.mp4, sword_sfx_rebuild_pass01.mp4 and iaido_final_pass4.mp4. These are September recordings, not proof of today's build.
- Current native Movie Maker capture: E:\SEKAI-CombatCore-20261012\combat_baseline_before.mp4, 42.1 seconds, 1280×720, 30 fps, real engine audio. Continuous **scripted input replay in TrainingGround**, not ten minutes of human play. One marked fixture reposition; no montage. InputEventAction enters the actual input handler.
- Event log confirms A1, A1-A2, A1-A2-A3, A1-A2-A3-A4, reset to A1, weapon round trip, movement attack, dodge, ordinary guard, one perfect guard and uni_riposte. Inspect action has no implementation. Iaido input reaches the existing director; its full visual endpoint needs a longer capture.
- Desktop keyboard capture had focus loss and was rejected. Earlier PNG recorder was stale: it reverses a 1.75s sheathe after 0.9/1.0s and triggers the current reversal bug. F: ran out of space; this run's intermediate folders were preserved on E:.
- Existing sword_basic_v2 scenarios print PASS, but process exits 1 with leaked resources at cleanup. This is not a clean passing check.
- Native recording FPS is a recording setting, **not** measured gameplay FPS or end-to-end input latency. Audio track exists; perceptual listening assessment remains unverified.

## CURRENT COMBAT MAP

| Responsibility | Real implementation |
|---|---|
| Main / training / test | scenes/main/Main.tscn → systems/main_flow.gd; scenes/training/TrainingGround.tscn; scenes/combat/CombatSandbox.tscn |
| Player / first person | scenes/player/Player.tscn → player/player_movement.gd; CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D |
| InputMap | Registered at runtime by PlayerMovement, CombatController and WeaponManager; not stored in project.godot |
| Weapon ownership | combat/weapon_slot.gd; combat/weapon_manager.gd is transition owner |
| Sword logic / move data | combat/combat_controller.gd; moveset_library.gd; sword_basic.gd; SwordMove resource |
| Animation | sword_pose_sampler.gd → temp_sword_visual.gd; procedural key poses, not AnimationTree-driven sword attacks |
| Sword model | TempSwordVisual reads weapons/sword_classes.gd and imported first-person meshes; fp_sword.glb exists |
| Saya / left hand | combat/sword_saya_rig.gd + player/saya_hand_driver.gd; separate hand socket, curved axial seating data |
| Melee hit | CombatController._process_move → SwordHitbox Area3D → hitbox.gd._on_area_entered |
| Wave / traces / arc | combat/sword_reach.gd; actual A2 travelling Area3D, A3 angular queries, A4 six sector queries |
| Damage / reaction | hurtbox.gd.receive_hit → enemies/technical_dummy.gd._on_hit; training/drill_dummy.gd inherits enemy and suppresses death |
| Camera / hitstop | camera/camera_feedback_controller.gd; combat/time_effect_manager.gd sets Engine.time_scale |
| VFX / shaders | sword_combat_vfx.gd listens to move/reach events; iaido_screen_fx, iaido_glass_layer, iaido_tear_3d, resources/shaders |
| Audio | audio/combat_audio_director.gd + combat_audio_cues.gd + sword_basic_cues.gd + sound_atom_registry; four material groups exist |
| Iaido | iaido_director.gd → target collector / world pause / foreground weapon / cut plane / execution / audio timeline |
| Guard / parry / dodge | CombatController with SwordGuardProfile; player hurtbox response opens riposte and interrupts enemy |
| HUD / debug | CombatHUD; DeveloperPanel F8; ParryDebugOverlay; WeaponIndicator F7; TrainingUI F1/F2 lighting |

Actual attack flow:

InputEvent → CombatController.request → cancel/buffer gate → _start_light → _begin_move
→ _process_move + SwordPoseSampler → TempSwordVisual / SayaHandSocket
→ body Area3D OR SwordReach wave/trace/sector
→ CombatHurtbox.receive_hit → enemy damage/poise/state
→ CombatController._on_hitbox_landed → camera/hitstop/audio/VFX.

Important defect: Area3D emits hit_landed **before** damage delivery and always delivers damage afterward. A controller early return currently suppresses feedback, not damage. The ranged _deliver path repeats the same feedback-before-damage ordering.

## Baseline critique (provisional / 10)

| Dimension | Score | Observed reason |
|---|---:|---|
| Input feel | 6 | Immediate prep and 150ms buffer exist; reversing sheathe can strand equip_blend and reject attacks permanently |
| Motion | 6 | Directional, authored curved poses and separate saya control exist; procedural sword without readable hands still looks detached |
| Hit | 3 | Dummy scarcely flinches; body hitbox and blade travel disagree; A3 dedup collapses repeated contacts |
| Camera | 5 | Directional swing impulses exist, but every contact adds generic trauma; several targets accumulate feedback |
| VFX / audio | VFX 4; audio unscored | Trails/scars have real events, but pale surfaces and overlapping fixtures obscure the cuts; audio was not perceptually listened to |
| Combat decision | 6 | Close/mid/long/surround grammar is real; existing perfect guard opens a counter; same-target A3 and visual reactions do not deliver their promised rhythm |

## CURRENT PROBLEMS — TOP 10

1. **P0 / input:** WeaponManager reversing a pending sheathe sets drawing_in but never restores _draw_left. After one tick it stops drawing below equip_blend=1; attack/iaido remain rejected. Reproduced by current recorder's 2→1 sequence; source agrees.
2. **P0 / hit:** A2 shared dedup cannot prevent the losing Area3D from delivering damage. Gates must run before damage, not only in a feedback signal handler.
3. **P0 / A3:** _seen is per move, so a body intersecting all three cuts receives only its first weighted hit; near melee also opens for the entire 0.52s multi-cut span. Need per-cut dedup and no unrelated melee window.
4. **P1 / reaction:** Ordinary hits change health/poise without directional body flinch. The same inert silhouette receives a whole sentence.
5. **P1 / camera:** Every contact adds random trauma, including the otherwise stable A3. Multi-target contact repeats the camera/stop impulse in one frame.
6. **P1 / hit geometry:** Melee box is a fixed 1.4×1.2×1.6 volume, not a blade sweep; wave uses overlap-only tracking. Fast thin contacts / initial overlaps / cover occlusion are unproven.
7. **P1 / equip:** Attacks are rejected for the complete 1.75s presentation. Need a physically safe interrupt into A1 once the blade clears the bore, preserving pose continuity.
8. **P1 / A2:** Gameplay wave spawns at startup=.10 while named wave event is .14; launch starts at the eye rather than actual blade release. One release instant and origin must serve hit, audio and VFX.
9. **P2 / review lab:** TrainingGround is an art hub, not a sword drill. Collinear near bodies obscure mid/long targets; repeated lunge enters nonblocking dummy geometry; no dedicated material/parry arrangement.
10. **P2 / presentation:** U / mouse-forward inspect and magic sword visual profile are absent on the live input path. Old Iaido movie is an obsolete placeholder sword; new one-rotation recovery is already in source and must be preserved, not rebuilt from that movie.

## CURRENT TIMINGS (actual move data, seconds)

| Move | windup | active span | follow | recovery | hitstop |
|---|---:|---:|---:|---:|---:|
| A1 | .130 | .070 | .055 | .145 | .024 |
| A2 | .100 | .090 | .070 | .155 | .034 |
| A3 | .160 | .520 (three event instants) | .100 | .220 | .022 |
| A4 | .120 | .200 | .110 | .230 | .055 |

A3 cut instants: .160 / .340 / .540; reach 14 / 16 / 18m. A2: 8.4m at 26m/s. A4: -140°→130°, radius 4.2m, six slices. Input buffer .150s. Universal combo memory .900s **after a cut ends**, separate from buffer. Perfect guard .120s; dodge total .360s, invulnerability [0,.200). Hit/miss recovery and styles scale raw timing; these data are not OS input latency measurements.

## IMPLEMENTATION PLAN — PRESERVE → REFACTOR → EXTEND

KEPT: existing move resource/sampler; A1–A4 distance grammar; saya hand socket and curved bore; one controlled Iaido rotation; actual audio/material registry; guard/riposte/dodge; current map.

Pass 01 (no VFX): fix three player-facing groups only: (1) equip reversal and safe attack entry, (2) hit delivery ordering/per-cut dedup/release timing, (3) directional enemy reaction and restrained contact camera. Leave working state machine; no replacement architecture. Add one focused runtime regression that reads damage receipts, not just feedback counters. Record the same continuous engine replay without VFX.

Pass 02 (audio): keep existing event/cue registry. Make named cuts audible even with VFX disabled; verify four material hits and separate guard/counter/sheath cues. Capture actual native engine audio; no offline substitute mix.

Pass 03 (VFX): restore existing effects using the corrected gameplay events. Reduce obscuring layers; distinguish wave/scars/arc. Magic only as optional visual profile, shared moves.

Pass 04: add a small sword lab host using existing TrainingGround and TechnicalDummy, no new world content. Near/mid/far, surrounding targets, parry sentinel, material row and clear Iaido lane. Continuous 60–120s interaction capture and timing receipts.

Acceptance remains open until ten minutes of actual interactive combat, audio listening, clipping review and final A–J self-review are performed. Scripted replay cannot prove fun, comfort or willingness to play again.
