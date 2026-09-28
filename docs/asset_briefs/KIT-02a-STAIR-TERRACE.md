# KIT-02a — Mistvale Stair / Terrace **Construction Language**

**Asset ID:** KIT-02a
**Type:** Modular environment kit (vertical circulation) — **a language, not a set**
**Priority:** P0
**Status:** SPEC READY (rev. 2 — construction language)
**Depends on:** ENV-01 (grid, materials, landing) — extends it, does not replace it
**Derived from:** `tools/audit_routes.gd` (stair-band report) and
`tools/dump_ascent_layout.gd` (resolved composition), both against the continuous
height field in `scripts/world/mistvale_heights.gd`

> **Revision note.** Rev. 1 described "13 stairs". That was wrong in kind, not in
> degree. Stones that carry a market plaza, a hillside alley, a thousand-year-old
> mountain road and a ruin cannot be the same object with different numbers. Rev. 2
> adds cultural semantics, edge/corner/broken variants and cause-driven detail, and
> restates the acceptance as an experience test rather than a tolerance test.

---

## 0. Production order — read this first

**ONE GOOD PIECE FIRST. THEN THE KIT.**

Do not generate twenty objects and then judge them. Build a **single
representative production stair** — the **S-A civic module, `R20`, 4 m waist** —
put it in Blender, look at it in a first-person framing at 1.5 m, and compare the
silhouette, stone structure, edge wear, material break-up and proportions against
the style target. If it still reads as a greybox asset, **stop** and send the
screenshot back for a quality pass. Only when one piece is genuinely production
grade does the rest of the kit get built — and it will then be built from a proven
code path rather than from a hopeful one.

Acceptance for the single piece (`§11`) is a separate, earlier gate than acceptance
for the kit (`§12`).

---

## 1. Why this is a language

The audit found **three** places where the walking surface lands in the 35–45° band.
Those are real routes, and a smooth 40° surface reads as a wall you slide up, so
they must become authored stairs.

But those three places are not the same kind of place:

| Site | What it is | Who walks it |
| --- | --- | --- |
| **S-A** Guild Stair | a **civic** monument | residents, on their way to the guild |
| **S-C** West Ledges | an **old path** | almost nobody, for a long time |
| **S-B** Cliff Ascent | an **ancient engineered** climb | you, on the way to the ruins |

A single repeating stair mesh in all three says the opposite of what the
masterplan says: that Mistvale is one culture with one building technique. So this
kit is a **construction language**: one modulus, one grid, one material set — and
several *dialects* that read differently in silhouette, edge treatment and detail
density while remaining physically interlockable.

**All variants share the same modulus.** A `Corner_L` from the ruin kit must accept
a flight from the town kit. That is the whole point; if a variant only works with
its own family it is a separate kit pretending to be a variant.

---

## 2. The modulus (unchanged from rev. 1 — it survived audit)

**Lock the tread, not the riser.**

```
tread = 2.00 / 7 = 0.285714 m        (seven steps per 2 m grid cell)
slope = atan(7 × riser / 2.00)
```

Locking the tread means one flight = **exactly one 2.00 m grid cell of run**, so
stairs stack on the same grid as terraces, walls and kerbs. The riser is then the
only free variable.

### 2a. Some risers do NOT exist for numeric reasons — they are cultural

This is the correction that matters most in rev. 2. Each riser is not an
interchangeable option; it is a statement about who built this and how much they
cared.

| Riser | Slope | Name | Means | Where it belongs |
| --- | --- | --- | --- | --- |
| **0.160** | 29.25° | **Civic** | comfortable public circulation — you do not notice the step | market, housing, everyday roads |
| **0.200** | 34.99° | **Town-steep** | the town ran out of room and chose steepness over distance | secondary town routes, **Guild Terrace** |
| **0.220** | 37.60° | **Old / built** | built deliberately, by hand, by people who had to carry the stone | mountain paths, older buildings, steep lanes |
| **0.240** | 40.03° | **Harsh** | **intentionally difficult.** Not a default — a decision | ruins, ancient engineering, the steepest cliff route |

**Do not use `0.240` as a Mistvale default.** It is the ruin's dialect. If a
settlement stair uses it, the settlement is calling itself a ruin.

### 2b. The measured field independently produced these semantics

`tools/dump_ascent_layout.gd` solves the riser from the ground, not from a wish
list. Given the real terrain, it lands on:

| Route | Solved risers | Family it lands in | Cultural reading |
| --- | --- | --- | --- |
| **Guild Terrace** (civic) | 0.157 / 0.196 / 0.153 | **R16 – R20** | public circulation, exactly as §2a says |
| **S-B Cliff Ascent** | 0.241 / 0.238 / 0.151 | **R24** on the crux | harsh ancient engineering, exactly as §2a says |

The terrain and the culture agree without being forced to. That is a good sign for
the kit and it is the reason the riser table is allowed to be prescriptive.

---

## 3. The resolved composition (what actually gets built)

Solved numbers, not authored ones. Re-derive any time the field changes by running
`tools/dump_ascent_layout.gd` — **never hand-write a rise.**

### 3a. S-B Cliff Ascent — 63 steps, 3 flights, 12 beats

| Beat | D (m) | Run | Ground | Structure | Result |
| --- | --- | --- | --- | --- | --- |
| WALK | 216 | 16.0 | 115.61 → 119.11 | grade | mountain traverse |
| GATE | 232 | 3.0 | 119.11 → 120.27 | grade | old door frame |
| WALK | 235 | 3.0 | 120.27 → 121.88 | grade | 24° approach |
| **FLIGHT A** | 238 | 8.0 | 121.88 → 128.62 | +6.74 | **28 steps, riser 0.241, 40.1°** |
| ALCOVE | 246 | 2.0 | 128.62 → 130.46 | grade | reach bay cut into the hill |
| **FLIGHT B** | 248 | 6.0 | 130.46 → 135.45 | +5.00 | **21 steps, riser 0.238, 39.8°** |
| BALCONY | 254 | 2.0 | 135.45 → 136.82 | grade | cantilevered reach bay |
| **FLIGHT C** | 256 | 4.0 | 136.82 → 138.93 | +2.11 | **14 steps, riser 0.151, 27.8°** |
| SHELF | 260 | 2.0 | 138.93 → 139.65 | grade | natural rock shelf |
| WALK | 262 | 8.0 | 139.65 → 140.99 | grade | broken old wall |
| FRAGMENT | 270 | 8.0 | 140.99 → 142.07 | grade | ruin fragment field |
| ARRIVAL | 278 | 16.9 | 142.07 → 144.14 | grade | forecourt |

**Longest single flight: 28 steps.** Brief §4 fails any continuous run ≥ 40 steps;
this is 28, and it is broken by a cut bay, a cantilever and a shelf.

### 3b. The geometric fact that shaped the whole design

The crux is a **40° face with 19 m of run**. You cannot put generous landings in it
without cutting several metres off a mountain. So a "bay" here is delivered by two
devices that cost **zero run**:

- **ALCOVE** — cut back INTO the uphill rock. You stand inside the mountain.
- **BALCONY** — cantilever OUT over the drop. You stand above the valley.

Both are **width** features, not length features: the path keeps the ground's grade
along its length and the niche is cut sideways. An earlier version made them level
along the path and immediately pushed the next flight to **46°**. That is the single
most important thing to preserve when iterating on this kit.

### 3c. Guild Terrace — 56 steps, 3 flights (CIVIC)

| Beat | D (m) | Run | Rise | Result |
| --- | --- | --- | --- | --- |
| WALK | 6 | 29.0 | — | market frontage plaza, 9 m wide |
| FLIGHT 1 | 35 | 6.0 | +3.29 | 21 steps, riser 0.157, **28.7°** |
| LANDING | 41 | 2.0 | +1.08 | lower terrace, balustrade, look back at the market |
| FLIGHT 2 | 43 | 6.0 | +4.12 | 21 steps, riser 0.196, **34.5°** |
| LANDING | 49 | 2.0 | +1.08 | mid terrace, **C-05 combat space**, guild front rises |
| FLIGHT 3 | 51 | 4.0 | +2.14 | 14 steps, riser 0.153, **28.2°** |
| ARRIVAL | 55 | 14.0 | — | forecourt, axis terminates on the guild entrance |

Note the shape: **gentle → steeper → gentle**. A civic stair that just gets steeper
is a hill. This one tightens in the middle and releases at the top, which is what
makes it read as *built*.

The 29 m frontage is deliberate and is §13 evidence: a public space has to be wide
enough that residents would actually use it.

---

## 4. Collision contract — read before modelling

**`CharacterBody3D` has no automatic step-up.** A 0.16–0.24 m riser collided as
trimesh is a vertical face, `move_and_slide()` classifies it as a wall, and the
player stops dead at the first step. Auto-generated trimesh collision — which is
what ENV-01 relies on — is **wrong for this kit**.

Therefore every flight ships a **ramp collision proxy**:

| Requirement | Value |
| --- | --- |
| Object name | `<flight name>_RAMP` |
| Shape | plain box, width = flight width |
| Box length (along slope) | `sqrt(2.00² + rise²)` → 2.292 / 2.441 / 2.524 / 2.612 m for R16 / R20 / R22 / R24 |
| Box thickness | 0.10 m |
| Top face | tangent to the step nosings — from `(0, riser, 0)` to `(0, 7 × riser, 2.00)` in local space |
| Orientation | **object rotation stays 0 / scale 1.** The slope is baked into mesh data |
| Origin | same as the flight |
| Material | `MV_Stone_Base`. It sits inside the solid stair and never renders, but an unmaterialed object may be dropped by the export pipeline |

**The split is absolute.** Visual geometry may be as broken, overgrown and irregular
as the design wants. Collision stays simple, continuous and stable. Never simplify
the visual to make the collider easy; never hand the player a trimesh stair.

Variants that are *walks* rather than *flights* (ALCOVE, BALCONY, LANDING, EDGE,
BROKEN) get a **flat or gently-sloped proxy** on the same terms.

---

## 5. Piece list (20)

Grid **2.00 m**. Origin on the ground plane at the footprint centre, except flights,
ramps and landings where the origin is at the bottom of the run, centred across the
width.

### 5a. Flights — 6 (one parametric builder, six arguments)

| # | Object name | Dimensions | Notes |
| --- | --- | --- | --- |
| 1 | `KIT02A_Stair_R16_7W2` | 2.00 × 1.12 × 2.00 | 7 steps, riser 0.160, tread 0.285714, civic |
| 2 | `KIT02A_Stair_R20_7W2` | 2.00 × 1.40 × 2.00 | riser 0.200, town-steep |
| 3 | `KIT02A_Stair_R22_7W2` | 2.00 × 1.54 × 2.00 | riser 0.220, old/built |
| 4 | `KIT02A_Stair_R24_7W2` | 2.00 × 1.68 × 2.00 | riser 0.240, harsh — ruin dialect |
| 5 | `KIT02A_Stair_R20_7W4` | 2.00 × 1.40 × **4.00** | **the civic hero piece.** 4 m waist carries S-A and the C-05 combat space |
| 6 | `KIT02A_Stair_R16_7W4` | 2.00 × 1.12 × **4.00** | the gentle civic flight (Guild Flights 1 and 3) |

### 5b. Variants — 8 (this is what rev. 2 adds)

**A twelfth flight length makes a map longer. An END makes a map readable.** These
are the pieces that let the same modulus produce a town, a path and a ruin.

| # | Object name | Dimensions | What it is for |
| --- | --- | --- | --- |
| 7 | `KIT02A_Stair_End_2` | 2.00 × 0.30 × 2.60 | **terminal.** The flight's last step widens into a threshold stone overhanging 0.30. Absorbs the run residual and hides the terrain plane cutting the top step |
| 8 | `KIT02A_Stair_Corner_L_2` / 9 `_R_2` | 2.00 × rise × 2.00 | **90° turn.** A square half-landing with a flight stub on the perpendicular face. Mirror pair, not a rotated copy. This is the piece that lets a stair follow a route that bends |
| 10 | `KIT02A_Stair_Broken_2` | 2.00 × 1.54 × 2.00 | **collapsed module.** Two treads missing, rubble in the gap, one cheek sheared off. Crossed on the ramp proxy; the step you cannot see is the step you do not stumble on |
| 11 | `KIT02A_Stair_Edge_Open_2` | 2.00 × rise × 2.20 | **open outer edge.** Kerb only, no wall. For the exposed side of a hillside stair |
| 12 | `KIT02A_Stair_Edge_Wall_2` | 2.00 × rise × 2.20 | **wall-side.** Outer edge cut hard against a rock face; used where the path is a notch |
| 13 | `KIT02A_Terrace_Landing_2x2` | 2.00 × 0.24 × 2.00 | level landing slab with a retaining lip on the downhill edge |
| 14 | `KIT02A_Alcove_2` | 2.00 run × 3.40 tall × **2.80 deep** | **reach bay, cut into the hill.** Floor level ACROSS the width, follows grade ALONG the path. A 0.90 m bench at the back. Costs zero run |
| 15 | `KIT02A_Cantilever_Deck_2` | 2.00 run × 0.60 deck × **3.40 projection** | **reach bay, projecting into air.** Three corbels under, low parapet. Costs zero run |

### 5c. Structural and rails — 5

| # | Object name | Dimensions | Notes |
| --- | --- | --- | --- |
| 16 | `KIT02A_Stair_Cheek_L_2` / `_R_2` | 2.00 run × 1.96 tall × 0.40 | stepped flank wall whose top follows the nosing line + 0.28, so the flight never floats on a hillside |
| 17 | `KIT02A_Retain_Wall_Step_2` | 2.00 × 0.45 × steps 0.60 → 1.50 | stepped retaining wall; the slope-following companion to ENV-01's flat wall |
| 18 | `KIT02A_Retain_Cap_2` | 2.00 × 0.14 × 0.50 | cap stone, overhanging 0.05 |
| 19 | `KIT02A_Stair_Rail_2` | 2.00 × 1.05 × 0.16 | 3 posts + 2 rails. Carries the 13 m drop on S-B: "someone built this so you would not fall" |
| 20 | `KIT02A_Rock_Stair_Half_2` | 2.00 run × 1.54 tall × 2.00 | **the old-path hero piece (D3).** A standard `R22` flight whose cheeks are overgrown by rock and soil: the stones are the *substrate*, not the object |

---

## 6. Detail rule — every detail must have a CAUSE

**Random noise is not detail.** Any surface variation in this kit must be
attributable to a physical process, and the reason has to be visible in the shape,
not just in the texture.

| Cause | Where it shows |
| --- | --- |
| inner side of the path is wetter | moss concentrates on the uphill cheek and in the nosing joints on that side |
| water crosses here | a drainage channel is cut through the nosing, and the stones downstream of it are scoured pale |
| outer edge takes the traffic and the weather | outer nosings are chipped and rounded; the inner nosing stays crisp |
| people walk the centre | the middle third of each tread is polished and slightly dished; both edges stay rough |
| this is a mountain path | loose stone accumulates along the outer edge, trapped by the kerb |
| this is ancient | joints are wider, and the wide joints are filled with moss rather than mortar |

If a detail cannot be given a cause, it should not be generated.

### 6a. Three tiers, all present in every flight

| Tier | Content |
| --- | --- |
| **PRIMARY** | the flight's silhouette: the slope, the width, the flank walls' top line |
| **SECONDARY** | retaining cheeks, cap stones, landings, edge treatment, the rail, the terrace mass below |
| **TERTIARY** | nosing chips, missing corners, moss-bearing pockets, drainage cuts, small loose stones, joint width |

A flight with only PRIMARY is a blockout. A flight with PRIMARY + SECONDARY is a
game asset. TERTIARY is what makes it this game's asset.

---

## 7. Materials

**No new materials. Reuse ENV-01's four, with the same values**, so KIT-02a is
visually continuous with the ground kit:

| Name | Base colour | Metallic | Roughness |
| --- | --- | --- | --- |
| `MV_Stone_Base` | 0.42, 0.44, 0.47 | 0.0 | 0.85 |
| `MV_Stone_Pale` | 0.68, 0.64, 0.55 | 0.0 | 0.80 |
| `MV_Timber_Dark` | 0.20, 0.15, 0.12 | 0.0 | 0.70 |
| `MV_Moss_Accent` | 0.32, 0.38, 0.30 | 0.0 | 0.90 |

Break-up rules:

- each tread alternates `MV_Stone_Base` / `MV_Stone_Pale`, but **not in a strict
  alternation** — a strict A/B/A/B reads as a tiled texture from ten paces
- `MV_Moss_Accent` on 2–3 treads per flight, weighted to the uphill side (§6)
- every nosing gets a 0.03 m chamfer, worn asymmetrically (§6: outer edges take more)
- `MV_Timber_Dark` is only for the rail top bar and ramp paving

**This is the difference between "a stair" and "an extruded staircase primitive"**,
and it is most of the point of the kit.

---

## 8. Poly budget

**Under 26,000 triangles for the whole kit**, target 19,000–23,000.

| Group | Budget |
| --- | --- |
| each 2 m flight | 1,400 – 2,600 |
| the two 4 m wide civic flights | 2,600 – 4,000 each |
| `Alcove_2`, `Cantilever_Deck_2` | 1,200 – 2,200 each |
| cheeks, walls, caps, rails | under 800 each |
| `Rock_Stair_Half_2` | 2,600 – 4,000 |

Sharp edges are flat shaded — correct for this style. **Bevels are baked**, not left
as live modifiers. No subdivision surfaces left live.

---

## 9. `assembly_demo` — mandatory, three instances

Three assemblies in one export `KIT02A_AssemblyDemo.glb`. **These are compositions,
not layout proofs.** Showing that modules tile is not the requirement; the
requirement is that each one produces a *feeling*. A demo that only shows "the
modules fit" is FAIL.

### D1 — GUILD TERRACE (civic / proud / functional)

Not a mountain path. Must show: **width**, public space, the guild building as the
terminating sight line, and evidence that residents would really walk this way.

Build at least: the market-edge plaza → `Stair_R16_7W4` → `Terrace_Landing_2x2` with
balustrade → `Stair_R20_7W4` → upper terrace → forecourt, with the guild frontage as
the axis terminator. Use `Alcove_2` as the mid-landing seat.

**Acceptance:** photographed from the plaza, it must read as *"I am climbing the
steps of an important public building"* — not *"I am climbing a hill path"*.

### D2 — S-B CLIFF ASCENT (the highest-spec demo of this revision)

Not "8 identical modules in a line". That is explicitly forbidden. This demo must
contain **at least three distinct height stages**, and between them:

a landing · a retaining wall · rock interaction · a rail where there is a real drop ·
**one ancient fragment** · **a vista opening**

Suggested build, following §3a: `End_2` → `Stair_R24_7W2` × 4 → `Alcove_2` →
`Stair_R24_7W2` × 3 → `Cantilever_Deck_2` → `Stair_R16_7W2` × 2 → `Stair_Broken_2` →
`Terrace_Landing_2x2`. Wrap the flank in `Cheek_R_2` and `Retain_Wall_Step_2`, and put
the fragment where the stair changes direction.

**Acceptance — the two shots that decide it:**
- **from the bottom:** the image must produce *"I need to climb that"*
- **from the top, looking back:** the image must produce *"I came up from there"*

The whole ascent must read as **PROGRESSION**, not as a stamina test.

### D3 — HALF-BURIED OLD PATH

This demo is about **visual integration**, not geometry. The stairs must not stand
next to a rock — they must **grow out of the hill**: rock overlapping the cheeks,
soil covering the outer nosings, vegetation slots between the flights, corners
broken and rounded.

Build from `Rock_Stair_Half_2` × 4 with `End_2` and a `Broken_2` in the middle.

**Acceptance:** the primary read must be *"an old path that has been in this
mountain for a long time"* — the stones are the substrate, not the subject.

---

## 10. Chunk plan

The scene may already contain ENV-01's `kit_common`. **Do not redefine its helpers
or materials.**

| Chunk | Contents |
| --- | --- |
| `stair_common` | parametric flight builder `(riser, width, steps)`, nosing/wear helper, **ramp-proxy builder**, the 4 material lookups |
| `wear` | the cause-driven detail helpers from §6: `worn_nosing(side)`, `moss_pocket(side)`, `drainage_cut()`, `chipped_corner()`, `loose_stones(edge)` |
| `flights_core` | pieces 1–4 |
| `flights_civic` | pieces 5–6 |
| `variants` | pieces 7–15 (end, corner, broken, edges, landing, alcove, cantilever) |
| `structure` | pieces 16–19 |
| `old_path` | piece 20 |
| `assembly_demo` | D1, D2, D3 — separate file |

Each chunk must sit inside a fenced Python code block and be **independently
executable** — one chunk failing must not take the rest with it.

---

## 11. Acceptance — the single piece (gate 1, before any kit work)

- [ ] it reads as built stone, not as a scaled cube, at a **first-person distance of 1.5 m**
- [ ] PRIMARY / SECONDARY / TERTIARY are all present and all legible in a single
      screenshot (§6a)
- [ ] every detail visible in that screenshot has a stated cause (§6)
- [ ] bench/terrace rhythm reads: the flight is not one monotonous ramp of steps
- [ ] tread measured on the mesh = **0.285714 m**
- [ ] `<name>_RAMP` box present, top face tangent to the nosings, slope baked into mesh data
- [ ] rotation 0 / scale 1
- [ ] exactly the four ENV-01 materials, no fifth

**If any box is unticked, the correct action is a quality pass, not more pieces.**

---

## 12. Acceptance — the kit (gate 2)

- [ ] tread is **0.285714 m** on every flight — measured on the mesh, not assumed from the argument
- [ ] every flight is exactly 2.00 m of run (the civic variants are 4.00 m wide, same run)
- [ ] every piece: rotation 0 / scale 1, origin on the stated footprint
- [ ] every flight carries a `<name>_RAMP` proxy
- [ ] 20 pieces, whole kit under 26,000 tris
- [ ] material count is exactly 4, and no fifth material appears anywhere
- [ ] `KIT02A_AssemblyDemo.glb` contains exactly three assemblies, and they differ in
      width, step count, riser and side treatment — **not just in length**
- [ ] D1 / D2 / D3 each pass their own §9 acceptance shot
- [ ] a character walks up D1, D2 and D3 in Godot **without stopping at a step**, and
      the alcove and the cantilever are reachable by stepping sideways off the flight

**The last one is the only acceptance that actually matters.** Everything else in
this document is a means.

---

## 13. Paths

- Blender source: `assets_source/environment/mistvale/kit02a_stair_terrace.blend`
- GLB, one per piece: `assets/models/environment/mistvale/`
- Assembly demo GLB: `assets/models/environment/mistvale/KIT02A_AssemblyDemo.glb`
- Godot: `godot/models/environment/mistvale/`
- Blockout this kit replaces, and the composition it must match:
  `scripts/world/mistvale_ascent.gd` + `scenes/world/MistvaleRegion.tscn`
- Review renders: `assets_source/review/compose/`
