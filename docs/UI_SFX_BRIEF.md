# SEKAI UI SFX brief — UI PASS 03 (FINALIZATION)

**From:** UI line · **To:** AUDIO line (B)
**Status:** production specification only. No cue in this document has been generated, licensed, auditioned, or integrated.
**Supersedes:** the PASS 02 version of this file (that one had 8 assets; §I of the pass brief cut it to 6).

---

## 0. What changed in PASS 03

PASS 02 fixed the *visual* direction. PASS 03 cut the asset list down.

The old brief had eight cues and a per-beat boot score. That is a trailer, not a
game menu. §I of the pass brief, verbatim in intent:

> This round we only need `UI_FOCUS / UI_CONFIRM / UI_BACK / UI_OPEN / UI_CLOSE /
> UI_BOOT`. Keep it clean. Short. Close.
> No epic magic, no long reverb, no glass ping on everything.
> **Boot may have at most ONE signature cue.**

So: **six assets.** Events stay finer-grained than assets — 10 events map onto 6
assets — because the *event* tells you what happened and the *asset* is what you
hear. Two events sharing one asset is fine (same material, different filter).
Two assets for one event is not.

---

## 1. Hard rules

1. **No musical pitch on focus/hover.** If a cue has a discernible note, it will
   fight the BGM. Contact noise only.
2. **No reverb tail on anything except `UI_BOOT`.** Tail = event. Events that fire
   5–20 times a minute must not announce themselves.
3. **Nothing UI may be louder than the thing it responds to.** `hitstop` and sword
   impacts own the top of the mix; UI lives under them permanently.
4. **One recognizable cue per boot.** The startup is ~2.8 s and has exactly one
   moment allowed to be *memorable*. Not three.
5. **The cue is the response, not the animation.** §13: input must feel instant.
   A UI cue must be triggered by the **input event**, never by an animation
   reaching a keyframe. If the player presses a key and the sound waits 120 ms for
   a line to finish drawing, the interface feels broken regardless of the sound.
6. **Short and close.** Every asset except `UI_BOOT` must read as *near* — as if
   the player's hand is on it. Nothing in this set is a room sound.

---

## 2. The six assets

| Asset | Layers to source or generate | Duration | Mix level | Wired? |
| --- | --- | --- | --- | --- |
| `UI_FOCUS` | faint air displacement + one whisper of cloth; a thin wood tick under it | 0.05–0.11 s | quietest cue in the game | yes |
| `UI_CONFIRM` | firmer contact: wood or thin metal against cloth, single hit, **no ring** | 0.12–0.16 s | low, but clearly the loudest of the interaction set | yes |
| `UI_BACK` | duller and shorter than confirm: muted cloth brush, **no metal** | 0.08–0.12 s | lower than `UI_CONFIRM` | yes |
| `UI_OPEN` | a light unlatching / cloth being drawn aside — "something is becoming available" | 0.18–0.28 s | low | yes |
| `UI_CLOSE` | the inverse of `UI_OPEN`, shorter, damped — "it went back where it was" | 0.12–0.20 s | lower than `UI_OPEN` | yes |
| `UI_BOOT` | **the one signature cue.** Very light "world-writing": graphite/paper, or a breath across a still surface. Long, low, spacious | 0.6–1.0 s | mid | yes |

### Notes per asset

- **`UI_FOCUS` covers both hover and focus, but they must be distinguishable at
  low volume,** because a mouse player hears both within the same second. That
  means different *material* or different filtering — **not** different gain.
  Recommended: one source, two filterings (hover = highs rolled off further).
- **`UI_CONFIRM` must not ring.** A ringing confirm is the single most common way
  a menu becomes tiring. Keep the metallic component to one thin transient with no
  sustain.
- **`UI_OPEN` / `UI_CLOSE` must be an obvious pair** — same material, inverse
  gesture. They are the only two cues in the set that describe *space* rather than
  *contact*, so they are the ones most likely to drift into "whoosh". Resist it:
  a whoosh is air moving fast; a panel opening is air moving *once*.
- **`UI_BOOT` is the only asset allowed to be memorable,** and it must be
  *quiet-memorable*, not *trailer-memorable*. Think "something is being written
  down somewhere far away", not "the game is starting".

---

## 3. Event → asset map

The interface dispatches `CustomEvent("sekai:ui")` on `window` with
`detail = { cue, id, ... }`. The authoritative list is `UI_CUES` in
`ui_web/components/ui_cue.js`. **Do not add an event without updating that file** —
the Web prototype, the Godot UI layer, and the future WebView bridge all listen on
the same name, and an unknown ID is silently dropped.

| Event | → Asset | Fires when | Notes |
| --- | --- | --- | --- |
| `hover` | `UI_FOCUS` | pointer enters an interactive item | lighter filtering |
| `focus` | `UI_FOCUS` | focus genuinely lands (keyboard / W/S / arrows) | firmer filtering |
| `confirm` | `UI_CONFIRM` | activate an item | also fires on the Launcher's 进入世界 |
| `back` | `UI_BACK` | Escape / leaving a sub-screen | |
| `open` | `UI_OPEN` | settings overlay opens | |
| `close` | `UI_CLOSE` | settings overlay closes | |
| `startup` | `UI_BOOT` | Launcher boot starts | **once per session.** `detail.fast` is true on the return path — AUDIO should shorten or skip |
| `deny` | `UI_BACK` | an unavailable item is triggered | damped further; **reserved — V2 has no disabled items** (§6: no save ⇒ 继续旅程 is absent, not greyed). Do not spend time on it. |
| `ready` | *(silent)* | world revealed, menu landed | §I20: this window stays quiet. Deliberately no asset. |
| `start` | *(silent)* | player enters the world | the world ambience bed takes over; UI stops speaking here |

The two silent rows are deliberate, not omissions. Scoring `ready` turns "the
world is being revealed" into "UI system boot complete" — the exact failure PASS
02 §9 was written to prevent. And `start` is where the UI should stop having a
voice at all.

### Boot: exactly one cue

- `UI_BOOT` fires once, at the moment the mark is being written.
- Between that and the menu landing: **nothing**.

Returning players hear it shortened or not at all — `UI_BOOT` belongs to the
session, not to the menu, and must not replay every time the title screen is
shown (§30).

---

## 4. Timings — read them, do not retype them

The boot beats live in `ui_web/v2/v2.config.js` (`LAUNCHER`,
`MENU_BOOT.first`, `MENU_BOOT.again`) and are the single source of truth. This
document deliberately does **not** reproduce the millisecond table — a
hand-copied timing table is how the iaido cue list once drifted by 0.36 s.

```
ui_web/v2/v2.config.js   LAUNCHER.beats · MENU_BOOT.first.beats · MENU_BOOT.again.beats
```

---

## 5. How to audition against the real interface

The interface can be driven deterministically, without a human and without a game
build:

```
node ui_web/tools/render.mjs video --root F:/SEKAI \
     --path ui_web/v2/main_menu/index.html --page main_menu_v2 \
     --query "boot=first" --fps 30 --duration 4200
```

Everything the UI emits is a `sekai:ui` CustomEvent on `window`. A listener that
logs `performance.now() + ' ' + detail.cue` gives the authoritative cue timeline
for that run — build the SFX against that log, not against prose.

Reference previews: `ui_web/previews/main_menu_final.mp4`,
`menu_to_game_final.mp4`, `settings_preview.mp4`, `launcher_final.mp4`.

---

## 6. Open questions for AUDIO (not blockers)

1. Can `UI_FOCUS` (hover) and `UI_FOCUS` (focus) come from **one** source with two
   filterings, rather than two separately generated assets? Strong preference: it
   guarantees they read as the same material, which is what makes them feel like
   one interface rather than two unrelated blips.
2. Should `UI_BOOT` be a UI asset at all, or is it better owned by the world
   ambience bed the player hears on the title screen? Leaning toward the latter;
   it would remove the last place where the UI has a "voice".
3. `UI_OPEN`/`UI_CLOSE` are currently only used by the settings overlay. If AUDIO
   writes them as a generic "panel" pair, note that the settings overlay is
   **typography over the world** — not a glass panel — and a "panel opening" sound
   would be scoring something that isn't there.
