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

## Priority A2: the guard loop (added 2026-09-27, combat director pass)

Priority A covers the sword and the two guard states, but the perfect-guard loop now has
more beats than that table describes, and the riposte is a distinct action with its own
sound. Without these the loop reads as "defend, defend, defend" with no punctuation.

| Cue ID | Layers to source or generate | Target duration | Gameplay trigger |
| --- | --- | --- | --- |
| `guard_hold` | leather-wrapped grip creak + tight arm tension, loopable | 0.8–1.5 s loop | holding guard, no contact |
| `guard_break` | weapon wrenched aside + breath knocked out + metal scrape | 0.5 s | stamina broke, guard failed |
| `riposte` | very short steel entry + light body turn | 0.22 s | released from a perfect guard |
| `blade_glint` | single high metallic ping, tiny, dry, no reverb tail | 0.12 s | edge glint appears after 截锋 |

`perfect_guard` is the single most important cue in the game's combat layer. It is the
player's reward for reading an attack instead of memorising a timer, so its transient must
be the sharpest, brightest metal sound in the whole set. A dull perfect guard destroys the
entire design intent.

## Priority D: style identity cues (added 2026-09-27, combat director pass)

Design rule: **the player must feel that the style changed without reading the UI.**
Sound carries a large share of that. These cues exist so 藏锋流 and 回风式 are recognisable
with the screen turned off.

### 藏锋流 · Hidden Edge — the staccato style

| Cue ID | Layers to source or generate | Target duration | Gameplay trigger |
| --- | --- | --- | --- |
| `he_sheathe` | long controlled steel friction into a wooden scabbard mouth + soft click | 0.6 s | blade returns to the hip |
| `he_draw_burst` | extremely fast steel exit + cloth whip, no wind-up | 0.15 s | 一文字 starting from sheathed |
| `he_dansui_still` | near-silence: a single settling cloth breath, then nothing | 0.3 s | 断水 holding absolutely still |
| `he_dansui_cut` | very fast wide steel line + hard air displacement | 0.3 s | 断水 release |

Note the pairing in 断水: **the sound of the stillness is not the sound of the cut.**
The 0.3 s of near-silence is what makes the following cut land. Do not fill it with a hum.

### 回风式 · Flowing Wind — the continuous style

| Cue ID | Layers to source or generate | Target duration | Gameplay trigger |
| --- | --- | --- | --- |
| `fw_cut_a` … `fw_cut_d` | four whooshes with shared timbre, rising body rotation each time | 0.20–0.26 s | the four chain hits |
| `fw_flow_keep` | short soft air re-grip, no transient | 0.12 s | connected hit shortens the next recovery |
| `fw_flow_break` | abrupt air stall + cloth snap | 0.18 s | whiffed cut breaks the rhythm |

`fw_cut_a`…`d` should feel like **one continuous gesture sampled four times**, not four
unrelated samples. `fw_flow_break` must be audibly worse than `fw_flow_keep` — that
contrast is the entire style.

## Priority E: 无明一刻 (Moment of No-Moon) ultimate

Distinct from Priority C. This ceremony's whole point is the silence and the single click.
Do **not** reuse 聚合斩's void or glass cues.

| Cue ID | Trigger (timeline) | Direction |
| --- | --- | --- |
| `mom_activation` | 0.00 s | a soft outward breath, then the world goes quiet |
| `mom_mono` | 0.35 s | no tone at all; a just-audible air pressure drop, seamless with surrounding silence |
| `mom_mark` | 0.95 s | five thin, dry ticks, slightly staggered, almost subliminal |
| `mom_draw` | 2.00 s | a single very short swish, barely present — the draw is meant to be missed |
| `mom_sheathe` | 3.10 s | slow friction, deliberately dragging, no click at the end |
| `mom_click` | 3.92 s | **the click.** Single, dry, hard, low, with the shortest possible tail |
| `mom_resolve` | 3.99 s | simultaneous mark release: layered cuts stacked into one impact, then air returns |
| `mom_restore` | 4.35 s | room tone re-entering; music resumes from the same timestamp |

**The entire ceremony is built around silencing everything, then one click.**
If `mom_click` is not the loudest, loneliest sound in the sequence, the ultimate fails
regardless of how good the rest of the mix is. Music must duck out at 0.00 and resume
from the same timestamp after `mom_restore`.

## Source and audition log template

For every imported candidate record: cue ID, source/tool, creator or model, license/usage right, exact generation prompt or source URL, creation/download date, file hash, intended trigger, and audition notes. Keep rejected candidates out of the game directory. Never describe a cue as approved until it is heard in the Godot combat scene at normal gameplay volume.

Generated prompts should request isolated dry SFX with no music, speech, or ambient bed, and should specify each layer separately so transient, body and tail can be mixed in Godot. Set sample peaks below clipping and compare perceived loudness against the existing `first-encounter.mp3` combat music.
