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

## Priority C: iaido

| Cue ID | Layers to source or generate | Target duration | Gameplay trigger |
| --- | --- | --- | --- |
| `iaido_draw` | sheath friction + restrained breath | 0.35 s | anticipation |
| `iaido_slash` | extremely fast blade cut + thin spatial tear | 0.25 s | active-frame strike |
| `iaido_tear` | brief silence leading to widening brittle crack + low impact | 0.55 s | delayed hit |
| `iaido_sheathe` | distinct hard sheath click, short room tail | 0.25 s | recovery |

## Source and audition log template

For every imported candidate record: cue ID, source/tool, creator or model, license/usage right, exact generation prompt or source URL, creation/download date, file hash, intended trigger, and audition notes. Keep rejected candidates out of the game directory. Never describe a cue as approved until it is heard in the Godot combat scene at normal gameplay volume.

Generated prompts should request isolated dry SFX with no music, speech, or ambient bed, and should specify each layer separately so transient, body and tail can be mixed in Godot. Set sample peaks below clipping and compare perceived loudness against the existing `first-encounter.mp3` combat music.
