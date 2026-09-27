# SEKAI Combat SFX production brief

Status: production specification only. No SFX in this document has been generated, licensed, auditioned, or integrated.

Use short, dry, layered impacts that preserve player control and positional clarity. Avoid music-like notes, long cinematic tails, stock laser sounds, and a single generic hit sample reused for every action. The existing four BGM tracks stay unchanged.

## Priority A: sword and defense

| Cue ID | Layers to source or generate | Target duration | Gameplay trigger |
| --- | --- | --- | --- |
| `sword_light_01` | narrow steel air cut + faint cloth motion | 0.18 s | first light startup |
| `sword_light_02` | reverse-direction steel whoosh + grip movement | 0.22 s | second light startup |
| `sword_light_03` | forward thrust air snap + firm footstep | 0.28 s | third light step |
| `sword_heavy` | weighted blade movement + low body effort | 0.38 s | heavy startup |
| `guard` | compact steel contact + muted body impact | 0.20 s | ordinary blocked hit |
| `perfect_guard` | bright metal transient + body impact + very short low punch + spark tail | 0.35 s | short perfect guard window |

## Priority B: elements and combination

| Cue ID | Layers to source or generate | Target duration | Gameplay trigger |
| --- | --- | --- | --- |
| `fire_cast` | inhaling embers + ignition snap | 0.45 s | Fire formation/release |
| `fire_impact` | focused flame burst + small stone scorch | 0.45 s | Fire impact |
| `frost_loop` | close granular ice hiss + cold airy sustain, seamless | 1–2 s loop | Frost active stream |
| `freeze` | tiny crystal ticks tightening into a short hard lock | 0.5 s | Frozen threshold |
| `wind_burst` | broad air displacement + dust/leaf movement + low push | 0.55 s | Wind release/force |
| `shatter` | high ice crack + stone break + low punch + magic tail | 0.7 s | Frozen → Heavy Shatter |

## Priority C: iaido (7.2s signature ceremony, 2026-09-27 revision)

The audio timeline is live in `godot/scripts/combat/iaido_audio_timeline.gd`, keyed off `IaidoTuning`. All 14 cues currently use synthesised placeholders from `godot/tools/generate_iaido_placeholders.py`; replace the WAV files only — the trigger points must not move. The void must NOT sound like a sci-fi portal: no laser, no electricity, just deep airless resonance, subtle pressure and an impossible empty space.

| Cue ID | Trigger (timeline) | Direction |
| --- | --- | --- |
| `iaido_air_suck` | 0.20s · world air disappears | fast broadband inhale, hard cut |
| `iaido_sheath_move` | 0.80s · blade walks back to the hip | controlled metal friction |
| `iaido_reverse_wave` | 1.20s · three shells collapse inward | reverse swell, air refraction |
| `iaido_pressure` | 2.20s · compression hold | very low pressure tone, almost silence |
| `iaido_lock_click` | 2.85s · sheath lock | sharp dry click, small |
| `iaido_draw` | 2.97s · instant draw | fast bright swish, 130ms |
| `iaido_world_cut` | 3.10s · reality tears | descending tear + low sub |
| `iaido_void_open` | 3.40s · void exposed | deep airless resonance, slow |
| `iaido_glass_stress` | 4.25s · surface starts failing | high creak with flutter |
| `iaido_glass_break` | 4.58s · first shards let go | crystalline burst, not full collapse |
| `iaido_spin` | 4.60s · two wrist revolutions | two whooshes, fast then medium |
| `iaido_slow_sheathe` | 5.50s · blade friction slowing | friction decelerating to 0.3x |
| `iaido_final_click` | 6.20s · FINAL CLICK | lower and heavier than the lock |
| `iaido_reality_restore` | 6.80s · shards and void drawn back | reverse suck + tiny reconnect pulse |

Music pauses at 0.00 and resumes from the same timestamp after `restore_end`; the large glass collapse at 6.25s reuses `iaido_glass_break` pitched down.

## Source and audition log template

For every imported candidate record: cue ID, source/tool, creator or model, license/usage right, exact generation prompt or source URL, creation/download date, file hash, intended trigger, and audition notes. Keep rejected candidates out of the game directory. Never describe a cue as approved until it is heard in the Godot combat scene at normal gameplay volume.

Generated prompts should request isolated dry SFX with no music, speech, or ambient bed, and should specify each layer separately so transient, body and tail can be mixed in Godot. Set sample peaks below clipping and compare perceived loudness against the existing `first-encounter.mp3` combat music.
