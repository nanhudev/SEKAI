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

Added this round (回风 is now fully playable, so these are gating):

| Cue ID | Layers to source or generate | Target duration | Gameplay trigger |
| --- | --- | --- | --- |
| `fw_zheliu_slip` | the incoming attack's transient **passing by** — cloth moving, not metal contacting | 0.22 s | 折柳 lets an attack graze past |
| `fw_zheliu_air` | a thin returning air cut, deliberately small | 0.16 s | the counter-cut after a slip |
| `fw_jinghong` | a rising air swirl with no contact transient | 0.24 s | 惊鸿 opens the style's exits |
| `fw_changfeng_a/b/c` | three directional cuts, **same timbre family**, panning with the cut side | 0.20 s each | the three 长风 cuts |

`fw_zheliu_slip` is the one that matters most: it must sound like the attack **missed**,
not like it was blocked. If it shares timbre with `guard_hold`, 折柳 loses its identity —
the whole point is that the player declined the exchange instead of winning it.

### 白蔷庭 · White Rose — the quiet style

Critical design note: **this style barely makes impact sounds, and that is the identity.**
A quiet style cannot be sold as "the same cuts, turned down" — it needs its own palette,
mostly air and thin steel, with the impacts placed *precisely* rather than loudly.

| Cue ID | Layers to source or generate | Target duration | Gameplay trigger |
| --- | --- | --- | --- |
| `wr_cut_short` | a very short, very dry steel line — no body, almost no tail | 0.12 s | 第一式 横 |
| `wr_thrust_point` | narrow air puncture + a single clean steel tick at the tip | 0.14 s | 第二式 刺 |
| `wr_cut_back` | reverse-direction short line, timbrally the mirror of `wr_cut_short` | 0.12 s | 第三式 反 |
| `wr_measure_ideal` | a barely-there air change on the *player's* side — like stepping into the right place | 0.10 s | a move commits at Ideal Measure |
| `wr_measure_crowd` | muffled, close, slightly unpleasant cloth/armour press | 0.12 s | a move commits Too Close |
| `wr_chuanting_drive` | one long steel exit that keeps travelling — the point does not stop | 0.30 s | 穿庭 |
| `wr_jiazhang_read` | identical first 200ms to `wr_chuanting_drive`, then a hard cancel: air cut off mid-travel | 0.20 s | 假章's feint wind-up |
| `wr_bind_lock` | two blades settling against each other: one metal-on-metal contact, then tension | 0.28 s | the bind begins (perfect guard on 白蔷) |
| `wr_bind_thrust` | the slide along the opponent's blade, then the point going in | 0.22 s | Light inside the bind |
| `wr_bind_disengage` | steel leaving contact + the player's own footstep backwards | 0.26 s | Heavy inside the bind |

Two hard rules for this style:

1. **`wr_jiazhang_read` must share its first 200 ms with `wr_chuanting_drive`.**
   A feint you can hear is not a feint. Record/extract them from the same source take.
2. **`wr_measure_ideal` must be non-localisable.** If the player can tell it is a UI beep,
   the style has become a readout. It should feel like a change in how the room sounds.

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

## Priority F: elements as behaviour (added 2026-09-27, combat director pass)

Requirement is behavioural: **watching the game with the audio on, the three elements must
be distinguishable without looking.** So each element needs a *state* layer that runs while
the state is on the target, not only a cast transient.

| Cue ID | Layers to source or generate | Target duration | Trigger |
| --- | --- | --- | --- |
| `mag_ember_cast` | short dry ignition, no whoosh | 0.18 s | 火种 |
| `mag_burn_loop` | low, close, irregular crackle. **Irregular is mandatory** — a steady loop reads as a machine | 1.0 s loop | target is Burning |
| `mag_burn_spread` | the crackle jumping sideways with a clear directional shift | 0.35 s | wind spreads a burning target / field |
| `mag_frost_cast` | tight cold air intake, reverse-envelope | 0.20 s | 寒流 / 凝霜 |
| `mag_frost_stage` | three escalating crystal ticks: chilled / frosted / frozen | 0.10 s each | frost climbs a rung |
| `mag_shatter` | brittle crack **then** a heavy break — two events, not one | 0.34 s | Shatter |
| `mag_brittle_break` | single dull shear, closer and drier than Shatter | 0.24 s | Brittle Break (Frosted + heavy) |
| `mag_wind_cast` | wide, low, moving air with an audible cone edge | 0.24 s | 风压 |
| `mag_wind_light` | the object/enemy being pushed: cloth and light debris | 0.22 s | a light target is thrown |
| `mag_wind_heavy` | the same gust meeting a heavy target: air only, **no displacement** | 0.20 s | a heavy target resists |
| `mag_wall_impact` | body/box hitting a hard surface, plus a small settle | 0.30 s | COMBO 2 — pushed into the wall |
| `mag_infuse_fire` / `mag_infuse_frost` | a short material change on the blade itself, no transient | 0.16 s | the blade passes through a field |

`mag_wind_light` vs `mag_wind_heavy` is the element's whole thesis in two cues: **the same
input, an audibly different outcome.** If they sound like the same sound at different volumes,
Wind is a damage number again.

## Priority G: 缚星链 · STAR-BIND CHAIN (added 2026-09-27, combat director pass)

**THE CHAIN'S IDENTITY IS THE LINKS. NOT THE HEAD.**
A single air whoosh over a thrown head makes this read as a whip, and a whip is just a long
sword with a worse grip. Every cue below therefore carries a **link layer**: many small metal
contacts, not one. If a listener cannot hear that the weapon is a rope of metal, the weapon
has failed at the level sound can fix.

Two cues carry the whole design, and both are structural rather than decorative:

- `ch_taut` — TENSION has no UI, so this cue *is* the readout. It must be unmistakable and it
  must be the same sound every time the chain reaches its limit, or the player never learns
  what "taut" means.
- `ch_tug` — the haul is delivered as five diminishing yanks (see `COMBAT_DESIGN.md` §19).
  **The rhythm has to be audible or 顿挫 only exists in the animation.** One sample triggered
  five times is a machine gun, which is the opposite of a rope losing power; the cue must
  degrade across the sequence.

| Cue ID | Layers to source or generate | Target duration | Gameplay trigger |
| --- | --- | --- | --- |
| `ch_hold` | loose links settling against each other, no whoosh, no wind | 0.7 s | idle sway of the head |
| `ch_sweep` | wide air cut **+ a dense link rattle that trails the air slightly** | 0.26 s | 横缚 (145° sweep) |
| `ch_return` | the same rattle played in reverse, tighter and shorter | 0.22 s | 返扫 (the carried second cut) |
| `ch_slam` | air accelerating downward, then a short link clatter on arrival | 0.30 s | 下砸 |
| `ch_orbit_loop` | continuous circling links, seamless. **The rate must track MOMENTUM, not a fixed BPM** | 1.0 s loop | 蓄势回旋 active |
| `ch_launch` | links paying out fast and unevenly, rising rattle, then air | 0.45 s | 甩星 release |
| `ch_taut` | one hard metal snap at full stretch, then a **low creak of something under load** | 0.50 s | chain reaches max radius |
| `ch_hook_throw` | head leaving the hand, air narrowing behind it | 0.34 s | 缠锁 throw |
| `ch_hook_soft` | head biting into a body: dull metal, cloth, no ring | 0.30 s | hook attaches to an enemy |
| `ch_hook_hard` | the same bite on stone: sharp metal ring + grit | 0.30 s | hook attaches to the anchor |
| `ch_tug` | **one heavy yank**: rope creak under load + a cluster of links being dragged. Three tiers, each shorter/duller/lower than the last, mapped to `pull_tug_curve` (0.28 / 0.20 / 0.12) | 0.20 / 0.16 / 0.12 s | each of the 5 tugs of 缚 / 曳 |
| `ch_tug_player` | the same yank **heard from the dragged end**: your own feet scraping + cloth, the chain far away | 0.24 s | a heavy target / the anchor hauls YOU |
| `ch_bound` | the chain going tight AROUND something: a short constricting creak, no impact | 0.35 s | 缚 opens its window |
| `ch_slip` | the chain letting go: links running slack, a small downward settle | 0.30 s | 缚 · 松脱 |
| `ch_pull_cut` | the pull and the cut as ONE event: chain strain handing over to a steel cut | 0.30 s | 拉近斩 |
| `ch_ground_slam` | upward chain strain, then a full body/ground impact with the links arriving after | 0.55 s | 地砸 |
| `ch_wall` | head into stone: hard stone impact, then links falling slack, **no rebound** | 0.45 s | 撞墙 · WALL |
| `ch_deflect` | metal sweeping metal aside — a glancing scrape, never a solid clang | 0.22 s | 拨链 |
| `ch_chain_cut` | 截链: the enemy's steel being knocked off its line, plus a bright link snap | 0.28 s | perfect deflect |
| `ch_wind_boost` | air joining an already-spinning chain — the loop getting denser, no gust transient | 0.40 s | 风 × 链 momentum boost |

**`ch_tug` vs `ch_tug_player` is the weight table in sound.** A light enemy is heard as *the
thing being hauled*; a heavy enemy and a fixed pillar are heard as *your own body being
hauled*, and the difference between those two mixes is the entire §18 argument. If they sound
like the same cue at different volumes, weight is a number again.

**Do not add a tug sound to the chain's overhead/hold layers.** Five yanks at 0.24 s spacing sit
inside a sequence that is otherwise mostly quiet, and that quiet is what makes the rhythm read.

### G2 · the chain's emitted timing events (§49 interface — added 2026-09-28)

The chain does not play audio itself. It **emits** the moments it knows about, and the AUDIO layer
subscribes. This is the whole interface; nothing else needs to be invented per cue. If a cue below
has no emitter, the audio has no trigger and the cue is dead weight in the table.

| Emitted signal | When it fires | Payload | What AUDIO should do with it |
| --- | --- | --- | --- |
| `tug(step, total, amount)` | each diminishing yank of 缚 / 曳, 5 per haul | `step` 1-based, `total` = 5, `amount` = the tug's share (0.28 / 0.24 / 0.20 / 0.16 / 0.12) | pick the `ch_tug` tier from `step`, set volume from `amount`. **Never re-derive the count** — the curve lives in the moveset and the signal already carries it |
| `wall_impact(strength)` | the head lands on solid world with nothing to hook | `strength` 0..1 from the head's speed | `ch_wall`. One shot, no rebound layer, and no `ch_hook_hard` — the wall refuses |

**The tug count is asserted, not assumed.** `chain_integration` counts `tug` emissions per haul and
fails if it does not match the length of `pull_tug_curve`. That check exists so this interface cannot
rot silently when a later form re-authors the pull: if someone changes the curve to three tugs and
forgets the audio, the suite tells them, not the mixer.

### G3 · §43 impact weight: one cue, sized by what it hit (added 2026-09-28)

The landing now pays a cost scaled by **target weight × head speed** (`COMBAT_DESIGN.md` §19):
momentum is spent, the arc bends off the impact line, and a **hitstop** runs for
`impact_hitstop × 0.55 … 1.35`. Measured, a light body leaves the head at 0.282 momentum with a
−106° bend; a heavy one at 0.215 with −102°.

Audio consequence, and it is a rule rather than a nicety: **do not author separate light/medium/heavy
impact samples.** Author one landing cue whose tail can be stretched, because the difference the
player must hear is *the head losing its spin*, not a different material. A heavy landing is not a
new sound; it is the same sound arriving at a head that was already carrying more of it.

`ch_taut` additionally now rides a **camera** event — a 1.80° FOV squeeze and a trauma snap fired the
frame the chain reaches max radius. The sound must **lead** that frame, not follow it: if the squeeze
lands first, the player reads "the camera is excited" instead of "the chain just became a rigid bar".
One frame of anticipation is enough; more and the cue feels detached.

## Source and audition log template

For every imported candidate record: cue ID, source/tool, creator or model, license/usage right, exact generation prompt or source URL, creation/download date, file hash, intended trigger, and audition notes. Keep rejected candidates out of the game directory. Never describe a cue as approved until it is heard in the Godot combat scene at normal gameplay volume.

Generated prompts should request isolated dry SFX with no music, speech, or ambient bed, and should specify each layer separately so transient, body and tail can be mixed in Godot. Set sample peaks below clipping and compare perceived loudness against the existing `first-encounter.mp3` combat music.
