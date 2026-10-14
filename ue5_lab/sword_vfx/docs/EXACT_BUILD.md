# EXACT NIAGARA BUILD SHEET

**Generated** by `tools/gen_build_sheets.py` from `exports/p11_report.json`.
Do not edit by hand — regenerate it. Every input name below was read back
from the live module topology during the build, and every arrow points at a
binding that was re-read from the graph afterwards.

Built into `/Game/SEKAI/VFX/Sword/Systems/`.

## What this document certifies, and what it does not

Every table below is generated from `exports/p11_report.json`, i.e. from the
run that produced the assets. That means the module choices, the input names and
the linked `User.*` parameters are **observed**, not intended.

It does **not** certify that the graphs look right, and it does not certify that
they compile. Read the per-system status line, and treat anything not marked
`UpToDate` as unfinished. The vocabulary is the brief's:

| Term | Meaning |
|---|---|
| `SPEC READY` | design / build sheet only |
| `ASSET READY` | material / texture / mesh exists |
| `IMPLEMENTED` | the Niagara graph really exists and runs |
| `VISUALLY VERIFIED` | actually looked at in the editor, on a bright AND a dark wall |
| `GAMEPLAY VERIFIED` | running against the real Sword animation and combat |


## Headline

| System | Built | Saved | Compile | Links verified | Manual steps |
|---|---|---|---|---|---|
| `NS_SW_Core_EdgeTrail` | yes | yes | `UpToDate` **but stale** | 5 | 3 |
| `NS_SW_Core_Glint` | yes | yes | `UpToDate` **but stale** | 3 | 3 |
| `NS_SW_Core_AirSlice` | yes | yes | `UpToDate` **but stale** | 4 | 3 |
| `NS_SW_Core_Wave` | yes | yes | `UpToDate` **but stale** | 9 | 5 |
| `NS_SW_Core_SpatialScar` | yes | yes | `UpToDate` **but stale** | 8 | 4 |
| `NS_SW_Core_MajorArc` | yes | yes | `UpToDate` **but stale** | 8 | 4 |
| `NS_SW_Core_MistWake` | yes | yes | `UpToDate` **but stale** | 5 | 3 |
| `NS_SW_Core_PurpleMotes` | yes | yes | `UpToDate` **but stale** | 4 | 3 |
| `NS_SW_Core_Hit` | yes | yes | `UpToDate` | 3 | 3 |

Totals: **9** systems, **49** module pins re-read from the graph, **24** user parameters, **31** manual editor steps.

## User parameters (one set, 24 entries, on every system)

These are added individually, so a refusal names the parameter it refused.
Brief section 24, plus four additions that exist because a module input
would not take the scalar form.

| Parameter | Type | Purpose |
|---|---|---|
| `User.PrimaryColor` | LinearColor | stroke body colour |
| `User.CoreColor` | LinearColor | hot core colour |
| `User.MistColor` | LinearColor | void / mist colour |
| `User.DarkColor` | LinearColor | void core colour |
| `User.Intensity` | NiagaraFloat | global multiplier, drives Color.Scale Alpha |
| `User.Width` | NiagaraFloat | stroke width, metres |
| `User.Length` | NiagaraFloat | stroke length, authored value, metres |
| `User.Radius` | NiagaraFloat | arc / burst / sprite radius, metres |
| `User.ArcAngle` | NiagaraFloat | major arc sweep, degrees |
| `User.Lifetime` | NiagaraFloat | particle lifetime, seconds |
| `User.Speed` | NiagaraFloat | travel speed, authored value, m/s |
| `User.Distortion` | NiagaraFloat | refraction offset strength |
| `User.MistAmount` | NiagaraFloat | 0 = normal sword, 1 = magic sword |
| `User.SpawnRate` | NiagaraFloat | particles per second, primary emitters |
| `User.StartPosition` | NiagaraPosition | world start |
| `User.EndPosition` | NiagaraPosition | world end |
| `User.BladeBase` | NiagaraPosition | blade base, world |
| `User.BladeTip` | NiagaraPosition | blade tip, world |
| `User.ArcStart` | NiagaraFloat | arc begin angle, degrees |
| `User.ArcEnd` | NiagaraFloat | arc end angle, degrees |
| `User.ScaleVector` | Vector3f | ScaleMeshSize takes Vector3f, so Length/Radius have this vector twin |
| `User.Velocity` | Vector3f | SolveForcesAndVelocity takes Vector3f, so Speed has this vector twin |
| `User.MistCount` | NiagaraInt32 | burst count for mist emitters; 0 in the Normal profile keeps them free |
| `User.MistRate` | NiagaraFloat | spawn rate for mist emitters; 0 in the Normal profile keeps them free |

## Module input reference

Read from the module assets with `GetModuleSchemaFromAsset`, with no system
context. This is the list of inputs that actually exist — three input names
in an earlier draft of the builder were wrong and failed silently, so this
table is the authority.

### `/Niagara/Modules/Ribbons/RibbonWidth`

| Input | Type |
|---|---|
| `Ribbon Width` | NiagaraFloat |
| `Beam Twist Amount` | NiagaraFloat |

### `/Niagara/Modules/Solvers/SolveForcesAndVelocity`

| Input | Type |
|---|---|
| `DeltaTime` | NiagaraFloat |
| `Force` | Vector3f |
| `Velocity` | Vector3f |
| `Mass` | NiagaraFloat |
| `Position` | NiagaraPosition |
| `Speed Limit` | NiagaraFloat |
| `PreviousVelocity` | Vector3f |
| `Acceleration Limit` | NiagaraFloat |
| `Write to Intrinsic Properties` | NiagaraBool |
| `Manually Enable Rotational Solver` | NiagaraBool |

### `/Niagara/Modules/Update/Color/Color`

| Input | Type |
|---|---|
| `Color` | LinearColor |
| `Scale Color` | Vector3f |
| `Scale Alpha` | NiagaraFloat |

### `/Niagara/Modules/Update/Color/ScaleColor`

| Input | Type |
|---|---|
| `Color Value To Scale` | LinearColor |
| `Scale RGB` | Vector3f |
| `Scale Alpha` | NiagaraFloat |

### `/Niagara/Modules/Update/Size/ScaleMeshSize`

| Input | Type |
|---|---|
| `Initial Mesh Scale` | Vector3f |
| `Scale Factor` | Vector3f |

### `/Niagara/Modules/Update/Size/ScaleSpriteSize`

| Input | Type |
|---|---|
| `Initial Sprite Size` | Vector2f |
| `Uniform Scale Factor` | NiagaraFloat |

## Systems

### `NS_SW_Core_EdgeTrail`

> A1 / A4 blade edge trail. A ribbon that follows the blade, driven entirely from User.* so Normal and Magic are the same graph.

**Asset:** `/Game/SEKAI/VFX/Sword/Systems/NS_SW_Core_EdgeTrail`

**Status:** built · saved · compile `UpToDate` **but stale**

- `E_Trail` / `ENiagaraScriptUsage::ParticleSpawnScriptInterpolated` — **Unknown** 
- `E_Trail` / `ENiagaraScriptUsage::ParticleUpdateScript` — **Unknown** 

#### Emitter `E_Trail`

| # | Renderer | Material | Mesh |
|---|---|---|---|
| 0 | ribbon | `MI_SW_Trail_Normal` | — |

| Phase | Module | Asset | Input | Bound to |
|---|---|---|---|---|
| EmitterUpdateScript | `SpawnRate` | `SpawnRate` | `Spawn Rate` | `User.SpawnRate` |
| ParticleSpawnScript | `Init` | `InitializeParticle` | `Lifetime` | `User.Lifetime` |
| ParticleUpdateScript | `Color` | `Color` | `Color` | `User.PrimaryColor` |
|  |  | `` | `Scale Alpha` | `User.Intensity` |
| ParticleUpdateScript | `RibbonWidth` | `RibbonWidth` | `Ribbon Width` | `User.Width` |

##### Renderer settings — MANUAL EDITOR STEP

- **ribbon:** Tessellation Mode = **Custom** (not `Automatic`). Automatic tessellation re-tessellates per frame and a ribbon that follows a blade visibly changes width as it swings.
- **ribbon:** Segments per Tessellation = 8. Below that a fast arc goes polygonal; above it, it is invisible on a 0.05 m ribbon.
- **ribbon:** UV0 Tiling Distance / Tile U = 4, so the Edge mask scrolls four times along the ribbon instead of stretching once.
- **ribbon:** Set `Material Parameter Binding` on the ribbon so the mask scroll speed comes from Speed, not from a hard-coded number.

##### MANUAL EDITOR STEP

1. Ribbon width over life: 1.0 -> 0.55 ease-out. A trail must thin as the swing decelerates
2. Colour alpha over life: hold, then fade over the last 40% so the tail dies first
3. Ribbon renderer: tessellation Custom, 8 segments, UV0 tiled 4x along the ribbon

#### Why this system is built this way

- This is the ONE system both A1 and A4 use. A1 wants a thin trail (0.42 of width) and A4 wants a wide one (1.75), so the caller sets `User.Width`; do not add a second trail system for A4.
- Draw-on for A4 comes from the mask scrolling along U, NOT from a ribbon lifetime curve. A ribbon whose endpoints are animated to reveal it reads as a growing object, not a cut being drawn.

### `NS_SW_Core_Glint`

> Equip / inspect cold glint. One particle, very short life, plus an optional point light. Not a firework, and no lens flare anywhere near it.

**Asset:** `/Game/SEKAI/VFX/Sword/Systems/NS_SW_Core_Glint`

**Status:** built · saved · compile `UpToDate` **but stale**

- `E_Glint` / `ENiagaraScriptUsage::ParticleSpawnScriptInterpolated` — **Unknown** 
- `E_Glint` / `ENiagaraScriptUsage::ParticleUpdateScript` — **Unknown** 

#### Emitter `E_Glint`

| # | Renderer | Material | Mesh |
|---|---|---|---|
| 0 | sprite | `MI_SW_Glint_Normal` | — |
| 1 | light | — | — |

| Phase | Module | Asset | Input | Bound to |
|---|---|---|---|---|
| EmitterUpdateScript | `SpawnBurst` | `SpawnBurst_Instantaneous` | `Spawn Count` | `1` |
| ParticleSpawnScript | `Init` | `InitializeParticle` | `Lifetime` | `User.Lifetime` |
| ParticleUpdateScript | `ScaleSpriteSize` | `ScaleSpriteSize` | `Uniform Scale Factor` | `User.Radius` |
| ParticleUpdateScript | `Color` | `Color` | `Color` | `User.CoreColor` |
|  |  | `` | `Scale Alpha` | `User.Intensity` |

##### Renderer settings — MANUAL EDITOR STEP

- **light:** Radius Scale is set to 40.0. A point light on a sword draw that is too wide lights the whole hand and stops reading as an edge highlight.
- **light:** Keep it to one particle. The exporter cost is per-light.
- **sprite:** Alignment = `Velocity Aligned` is NOT wanted here; the glint and motes are camera-independent points of light, so leave it `Unaligned`.
- **sprite:** Sub Image / sprite size index stays 0 - sizing is done on the particle.

##### MANUAL EDITOR STEP

1. The scan along the blade is the Streak map scrolling on U, so the draw-on is a material UV wipe, not a sprite size curve
2. Sprite size over life: 0.35 -> 1.0 in the first 25%, then 1.0 -> 0.15. 80-160 ms total
3. Light renderer: one particle, low radius. Colour over life: CoreColor, alpha down to 0

#### Why this system is built this way

- The glint is only legible because Beat 2 exposes 160 mm of blade (`NE_PARTIAL_DRAW`). If the draw timing changes, the glint duration must be re-derived from the event pair at 0.95 s and 1.07 s, never from a Lifetime value.
- Inspect (brief section 8) reuses THIS system with slower values. There is no separate inspect graph to build.

### `NS_SW_Core_AirSlice`

> A1 thin air slice: a 1.5-2.5 m sliver drawn on from one end, not a projectile. Same graph for both swords.

**Asset:** `/Game/SEKAI/VFX/Sword/Systems/NS_SW_Core_AirSlice`

**Status:** built · saved · compile `UpToDate` **but stale**

- `E_Slice` / `ENiagaraScriptUsage::ParticleSpawnScriptInterpolated` — **Unknown** 
- `E_Slice` / `ENiagaraScriptUsage::ParticleUpdateScript` — **Unknown** 

#### Emitter `E_Slice`

| # | Renderer | Material | Mesh |
|---|---|---|---|
| 0 | mesh | `MI_SW_SpatialScar_Normal` | `SM_SW_ScarStrip` |

| Phase | Module | Asset | Input | Bound to |
|---|---|---|---|---|
| EmitterUpdateScript | `SpawnBurst` | `SpawnBurst_Instantaneous` | `Spawn Count` | `1` |
| ParticleSpawnScript | `Init` | `InitializeParticle` | `Lifetime` | `User.Lifetime` |
| ParticleUpdateScript | `ScaleMeshSize` | `ScaleMeshSize` | `Scale Factor` | `User.ScaleVector` |
| ParticleUpdateScript | `Color` | `Color` | `Color` | `User.PrimaryColor` |
|  |  | `` | `Scale Alpha` | `User.Intensity` |

##### Renderer settings — MANUAL EDITOR STEP

- **mesh:** Facing Mode = `Custom` with `Custom Facing Vector` bound to the cut normal. The sheets are authored +Z-normal, so the default `Face Camera` would turn a spatial scar into a billboard and it would stop living in the world.
- **mesh:** Mesh Alignment = `World` for A3/A4 (they stay where they were cut); `Velocity` is wrong for both.
- **mesh:** Pivot Offset stays (0,0,0) for every generated mesh: each one is authored about the point it should scale and rotate about.

##### MANUAL EDITOR STEP

1. Draw-on is a material U wipe on the Scar mask: 0 -> 1 across the first 35% of life, 50-100 ms total
2. Set User.ScaleVector so the strip reaches 1.5-2.5 m along X; Y stays thin
3. The strip is authored 6 cm wide. Only widen it if the blade is unusually heavy

#### Why this system is built this way

- Not a projectile. Godot's A1 is `reach_mode = body`, so nothing travels. Give it no Velocity module.
- Draw-on is the U wipe: 0 -> 1 across the first 35 percent of life, 50-100 ms total.

### `NS_SW_Core_Wave`

> A2 mid-range blade wave: a thin curved pressure sheet, 6-10 m, bright leading edge and faint interior. Not a thick blue crescent.

**Asset:** `/Game/SEKAI/VFX/Sword/Systems/NS_SW_Core_Wave`

**Status:** built · saved · compile `UpToDate` **but stale**

- `E_Wave` / `ENiagaraScriptUsage::ParticleSpawnScriptInterpolated` — **Unknown** 
- `E_Wave` / `ENiagaraScriptUsage::ParticleUpdateScript` — **Unknown** 
- `E_MistWake` / `ENiagaraScriptUsage::ParticleSpawnScriptInterpolated` — **Unknown** 
- `E_MistWake` / `ENiagaraScriptUsage::ParticleUpdateScript` — **Unknown** 

#### Emitter `E_Wave`

| # | Renderer | Material | Mesh |
|---|---|---|---|
| 0 | mesh | `MI_SW_Wave_Normal` | `SM_SW_WaveSheet` |

| Phase | Module | Asset | Input | Bound to |
|---|---|---|---|---|
| EmitterUpdateScript | `SpawnBurst` | `SpawnBurst_Instantaneous` | `Spawn Count` | `1` |
| ParticleSpawnScript | `Init` | `InitializeParticle` | `Lifetime` | `User.Lifetime` |
| ParticleUpdateScript | `ScaleMeshSize` | `ScaleMeshSize` | `Scale Factor` | `User.ScaleVector` |
| ParticleUpdateScript | `Solve` | `SolveForcesAndVelocity` | `Velocity` | `User.Velocity` |
| ParticleUpdateScript | `Color` | `Color` | `Color` | `User.PrimaryColor` |
|  |  | `` | `Scale Alpha` | `User.Intensity` |

##### Renderer settings — MANUAL EDITOR STEP

- **mesh:** Facing Mode = `Custom` with `Custom Facing Vector` bound to the cut normal. The sheets are authored +Z-normal, so the default `Face Camera` would turn a spatial scar into a billboard and it would stop living in the world.
- **mesh:** Mesh Alignment = `World` for A3/A4 (they stay where they were cut); `Velocity` is wrong for both.
- **mesh:** Pivot Offset stays (0,0,0) for every generated mesh: each one is authored about the point it should scale and rotate about.

##### MANUAL EDITOR STEP

1. User.ScaleVector: 8.0 uniform for a 6-10 m wave; the sheet is 1.0 m x 0.68 m before scaling
2. Travel 0.18-0.35 s across the range: set User.Velocity.X so length/speed lands in that window
3. Colour alpha over life: leading edge holds, whole sheet to 0 over the last 30%

#### Emitter `E_MistWake`

| # | Renderer | Material | Mesh |
|---|---|---|---|
| 0 | mesh | `MI_SW_Mist_Normal` | `SM_SW_GlintQuad` |

| Phase | Module | Asset | Input | Bound to |
|---|---|---|---|---|
| EmitterUpdateScript | `SpawnBurst` | `SpawnBurst_Instantaneous` | `Spawn Count` | `User.MistCount` |
| ParticleSpawnScript | `Init` | `InitializeParticle` | `Lifetime` | `User.Lifetime` |
| ParticleUpdateScript | `Color` | `Color` | `Color` | `User.MistColor` |
|  |  | `` | `Scale Alpha` | `User.Intensity` |

##### Renderer settings — MANUAL EDITOR STEP

- **mesh:** Facing Mode = `Custom` with `Custom Facing Vector` bound to the cut normal. The sheets are authored +Z-normal, so the default `Face Camera` would turn a spatial scar into a billboard and it would stop living in the world.
- **mesh:** Mesh Alignment = `World` for A3/A4 (they stay where they were cut); `Velocity` is wrong for both.
- **mesh:** Pivot Offset stays (0,0,0) for every generated mesh: each one is authored about the point it should scale and rotate about.

##### MANUAL EDITOR STEP

1. Costs nothing in the Normal profile: User.MistCount is 0 there
2. Keep the count low - the wave must still read as a thin sheet, not a purple fog bank

#### Why this system is built this way

- 0.18-0.35 s is the contract window for the flight. Godot's own numbers are 8.4 m at 26.0 m/s = 0.323 s, so `User.Velocity.X = 26` and `User.Lifetime = 0.323` reproduce the shipping feel exactly.
- The sheet must NOT be given a roll or a spin. It is a pressure sheet with a leading edge, and rolling it destroys the edge.

### `NS_SW_Core_SpatialScar`

> A3 world-space spatial scar. Three instances are spawned by the contract, each reading 1/2/3 by draw order and position, held long enough that all three coexist without merging.

**Asset:** `/Game/SEKAI/VFX/Sword/Systems/NS_SW_Core_SpatialScar`

**Status:** built · saved · compile `UpToDate` **but stale**

- `E_Scar` / `ENiagaraScriptUsage::ParticleSpawnScriptInterpolated` — **Unknown** 
- `E_Scar` / `ENiagaraScriptUsage::ParticleUpdateScript` — **Unknown** 
- `E_ScarMist` / `ENiagaraScriptUsage::ParticleSpawnScriptInterpolated` — **Unknown** 
- `E_ScarMist` / `ENiagaraScriptUsage::ParticleUpdateScript` — **Unknown** 

#### Emitter `E_Scar`

| # | Renderer | Material | Mesh |
|---|---|---|---|
| 0 | mesh | `MI_SW_SpatialScar_Normal` | `SM_SW_ScarStrip` |

| Phase | Module | Asset | Input | Bound to |
|---|---|---|---|---|
| EmitterUpdateScript | `SpawnBurst` | `SpawnBurst_Instantaneous` | `Spawn Count` | `1` |
| ParticleSpawnScript | `Init` | `InitializeParticle` | `Lifetime` | `User.Lifetime` |
| ParticleUpdateScript | `ScaleMeshSize` | `ScaleMeshSize` | `Scale Factor` | `User.ScaleVector` |
| ParticleUpdateScript | `Color` | `Color` | `Color` | `User.PrimaryColor` |
|  |  | `` | `Scale Alpha` | `User.Intensity` |

##### Renderer settings — MANUAL EDITOR STEP

- **mesh:** Facing Mode = `Custom` with `Custom Facing Vector` bound to the cut normal. The sheets are authored +Z-normal, so the default `Face Camera` would turn a spatial scar into a billboard and it would stop living in the world.
- **mesh:** Mesh Alignment = `World` for A3/A4 (they stay where they were cut); `Velocity` is wrong for both.
- **mesh:** Pivot Offset stays (0,0,0) for every generated mesh: each one is authored about the point it should scale and rotate about.

##### MANUAL EDITOR STEP

1. Draw-on 20-60 ms, hold 120-250 ms, fade ~100 ms. Three copies must read 1 / 2 / 3 - stagger the draw-on, never the hold
2. The three scars are slash / backslash / shallow horizontal. Geometry is one system; orientation is the caller's job

#### Emitter `E_ScarMist`

| # | Renderer | Material | Mesh |
|---|---|---|---|
| 0 | mesh | `MI_SW_Mist_Normal` | `SM_SW_GlintQuad` |

| Phase | Module | Asset | Input | Bound to |
|---|---|---|---|---|
| EmitterUpdateScript | `SpawnBurst` | `SpawnBurst_Instantaneous` | `Spawn Count` | `User.MistCount` |
| ParticleSpawnScript | `Init` | `InitializeParticle` | `Lifetime` | `User.Lifetime` |
| ParticleUpdateScript | `Color` | `Color` | `Color` | `User.MistColor` |
|  |  | `` | `Scale Alpha` | `User.Intensity` |

##### Renderer settings — MANUAL EDITOR STEP

- **mesh:** Facing Mode = `Custom` with `Custom Facing Vector` bound to the cut normal. The sheets are authored +Z-normal, so the default `Face Camera` would turn a spatial scar into a billboard and it would stop living in the world.
- **mesh:** Mesh Alignment = `World` for A3/A4 (they stay where they were cut); `Velocity` is wrong for both.
- **mesh:** Pivot Offset stays (0,0,0) for every generated mesh: each one is authored about the point it should scale and rotate about.

##### MANUAL EDITOR STEP

1. Mist leaks along the scar normal, slowly. It must not close into a ring and must not smother the three scar lines
2. If the hero frame shows one purple-black cloud, User.MistCount is too high

#### Why this system is built this way

- Three instances, three positions, three angles - the caller's job. The graph must not try to branch on which cut it is.
- The offsets in Godot's `move.traces` are what stop the three marks reading as a starburst. If all three arrive at the same screen point, the beat has failed no matter how good one scar looks.
- SCAR_EDGE_WIDTH is 0.034 m because 0.020 m was sub-pixel at 720p at 16 m. Re-check the edge width against the ACTUAL camera distance in the lab; a world width that read fine at 8 m will vanish at 18 m.

### `NS_SW_Core_MajorArc`

> A4 major arc, 240-300 deg. SM_SW_ArcSheet has the sweep on U, so the arc can be drawn on along its own length and keeps a readable start and an end. Not a 360 ring.

**Asset:** `/Game/SEKAI/VFX/Sword/Systems/NS_SW_Core_MajorArc`

**Status:** built · saved · compile `UpToDate` **but stale**

- `E_Arc` / `ENiagaraScriptUsage::ParticleSpawnScriptInterpolated` — **Unknown** 
- `E_Arc` / `ENiagaraScriptUsage::ParticleUpdateScript` — **Unknown** 
- `E_ArcMist` / `ENiagaraScriptUsage::ParticleSpawnScriptInterpolated` — **Unknown** 
- `E_ArcMist` / `ENiagaraScriptUsage::ParticleUpdateScript` — **Unknown** 

#### Emitter `E_Arc`

| # | Renderer | Material | Mesh |
|---|---|---|---|
| 0 | mesh | `MI_SW_Trail_Normal` | `SM_SW_ArcSheet` |

| Phase | Module | Asset | Input | Bound to |
|---|---|---|---|---|
| EmitterUpdateScript | `SpawnBurst` | `SpawnBurst_Instantaneous` | `Spawn Count` | `1` |
| ParticleSpawnScript | `Init` | `InitializeParticle` | `Lifetime` | `User.Lifetime` |
| ParticleUpdateScript | `ScaleMeshSize` | `ScaleMeshSize` | `Scale Factor` | `User.ScaleVector` |
| ParticleUpdateScript | `Color` | `Color` | `Color` | `User.PrimaryColor` |
|  |  | `` | `Scale Alpha` | `User.Intensity` |

##### Renderer settings — MANUAL EDITOR STEP

- **mesh:** Facing Mode = `Custom` with `Custom Facing Vector` bound to the cut normal. The sheets are authored +Z-normal, so the default `Face Camera` would turn a spatial scar into a billboard and it would stop living in the world.
- **mesh:** Mesh Alignment = `World` for A3/A4 (they stay where they were cut); `Velocity` is wrong for both.
- **mesh:** Pivot Offset stays (0,0,0) for every generated mesh: each one is authored about the point it should scale and rotate about.

##### MANUAL EDITOR STEP

1. The arc is formed live by the blade: the draw-on is the Edge mask wiping along U, driven by the A4 arc timing, not by a scale curve
2. Arc mesh is 2 m outer diameter at scale 1.0, swept about its own origin, so User.ScaleVector stays uniform here
3. Colour alpha over life: fade over the last 35%. Start and end must stay distinguishable in a still frame

#### Emitter `E_ArcMist`

| # | Renderer | Material | Mesh |
|---|---|---|---|
| 0 | mesh | `MI_SW_Mist_Normal` | `SM_SW_GlintQuad` |

| Phase | Module | Asset | Input | Bound to |
|---|---|---|---|---|
| EmitterUpdateScript | `SpawnBurst` | `SpawnBurst_Instantaneous` | `Spawn Count` | `User.MistCount` |
| ParticleSpawnScript | `Init` | `InitializeParticle` | `Lifetime` | `User.Lifetime` |
| ParticleUpdateScript | `Color` | `Color` | `Color` | `User.MistColor` |
|  |  | `` | `Scale Alpha` | `User.Intensity` |

##### Renderer settings — MANUAL EDITOR STEP

- **mesh:** Facing Mode = `Custom` with `Custom Facing Vector` bound to the cut normal. The sheets are authored +Z-normal, so the default `Face Camera` would turn a spatial scar into a billboard and it would stop living in the world.
- **mesh:** Mesh Alignment = `World` for A3/A4 (they stay where they were cut); `Velocity` is wrong for both.
- **mesh:** Pivot Offset stays (0,0,0) for every generated mesh: each one is authored about the point it should scale and rotate about.

##### MANUAL EDITOR STEP

1. Incomplete wake behind the arc only. It must never close into a 360 ring, even at maximum MistCount

#### Why this system is built this way

- 270 degrees. Godot's `reach_arc_from = -140`, `reach_arc_to = 130`. A 360 degree ring is explicitly forbidden and this number is the reason.
- ARC_BAND 0.13 m, not a wall: 0.32 m subtended ~100 px at 720p and read as a standing sheet of water rather than a blade going past.
- The draw-on is a U wipe along the sweep. Uniform scale = expanding ring = shockwave, which is what the beat must not be.

### `NS_SW_Core_MistWake`

> Black mist / void leakage. Low-count cards plus a mesh wake, never a single standard smoke sprite, and never dense enough to close into a ring or to smother the scar it leaks from.

**Asset:** `/Game/SEKAI/VFX/Sword/Systems/NS_SW_Core_MistWake`

**Status:** built · saved · compile `UpToDate` **but stale**

- `E_Wisp` / `ENiagaraScriptUsage::ParticleSpawnScriptInterpolated` — **Unknown** 
- `E_Wisp` / `ENiagaraScriptUsage::ParticleUpdateScript` — **Unknown** 

#### Emitter `E_Wisp`

| # | Renderer | Material | Mesh |
|---|---|---|---|
| 0 | mesh | `MI_SW_Mist_Normal` | `SM_SW_GlintQuad` |

| Phase | Module | Asset | Input | Bound to |
|---|---|---|---|---|
| EmitterUpdateScript | `SpawnRate` | `SpawnRate` | `Spawn Rate` | `User.MistRate` |
| ParticleSpawnScript | `Init` | `InitializeParticle` | `Lifetime` | `User.Lifetime` |
| ParticleUpdateScript | `ScaleMeshSize` | `ScaleMeshSize` | `Scale Factor` | `User.ScaleVector` |
| ParticleUpdateScript | `Color` | `Color` | `Color` | `User.MistColor` |
|  |  | `` | `Scale Alpha` | `User.Intensity` |

##### Renderer settings — MANUAL EDITOR STEP

- **mesh:** Facing Mode = `Custom` with `Custom Facing Vector` bound to the cut normal. The sheets are authored +Z-normal, so the default `Face Camera` would turn a spatial scar into a billboard and it would stop living in the world.
- **mesh:** Mesh Alignment = `World` for A3/A4 (they stay where they were cut); `Velocity` is wrong for both.
- **mesh:** Pivot Offset stays (0,0,0) for every generated mesh: each one is authored about the point it should scale and rotate about.

##### MANUAL EDITOR STEP

1. Mesh scale 0.5 -> 1.0 over life, slowly. Mist that grows fast reads as an explosion
2. Alpha over life: 0 -> peak at 25% -> 0
3. Zero cost in the Normal profile: User.MistRate is 0 there

#### Why this system is built this way

- Zero cost in the Normal profile because `User.MistRate` is 0. Do not 'optimise' it by removing the emitter: the Magic profile needs it and the whole point of section 23 is that both swords are one graph.
- Growth must be slow. Fast-growing mist reads as an explosion, which is the opposite of 'darkness that does not belong to this world leaking out'.

### `NS_SW_Core_PurpleMotes`

> Magic idle motes, plus the single point glint at the saya mouth on the final click. Very few, very slow, additive.

**Asset:** `/Game/SEKAI/VFX/Sword/Systems/NS_SW_Core_PurpleMotes`

**Status:** built · saved · compile `UpToDate` **but stale**

- `E_Motes` / `ENiagaraScriptUsage::ParticleSpawnScriptInterpolated` — **Unknown** 
- `E_Motes` / `ENiagaraScriptUsage::ParticleUpdateScript` — **Unknown** 

#### Emitter `E_Motes`

| # | Renderer | Material | Mesh |
|---|---|---|---|
| 0 | sprite | `MI_SW_Mote_Normal` | — |

| Phase | Module | Asset | Input | Bound to |
|---|---|---|---|---|
| EmitterUpdateScript | `SpawnRate` | `SpawnRate` | `Spawn Rate` | `User.SpawnRate` |
| ParticleSpawnScript | `Init` | `InitializeParticle` | `Lifetime` | `User.Lifetime` |
| ParticleUpdateScript | `ScaleSpriteSize` | `ScaleSpriteSize` | `Uniform Scale Factor` | `User.Radius` |
| ParticleUpdateScript | `Color` | `Color` | `Color` | `User.PrimaryColor` |
|  |  | `` | `Scale Alpha` | `User.Intensity` |

##### Renderer settings — MANUAL EDITOR STEP

- **sprite:** Alignment = `Velocity Aligned` is NOT wanted here; the glint and motes are camera-independent points of light, so leave it `Unaligned`.
- **sprite:** Sub Image / sprite size index stays 0 - sizing is done on the particle.

##### MANUAL EDITOR STEP

1. Spawn rate in single digits per second, and 0 while stowed. This is a few motes, not a candle
2. Sprite size over life: 0.5 -> 1.0 -> 0.2
3. Additive, so Scale Alpha does not attenuate it: brightness is set on MI_SW_Mote_* instead

#### Why this system is built this way

- `User.SpawnRate` must be single digits and 0 while stowed. A continuous stream is the 'smoke machine' the brief names as a failure.
- This system also carries the single point glint at the saya mouth on the final click (20-50 ms). That is a separate, timed one-shot - do not raise the idle rate to make it appear.

### `NS_SW_Core_Hit`

> Contact burst for the surface families. One system, several material instances - the caller picks the instance and the graph never branches on surface type.

**Asset:** `/Game/SEKAI/VFX/Sword/Systems/NS_SW_Core_Hit`

**Status:** built · saved · compile `UpToDate`

#### Emitter `E_Hit`

| # | Renderer | Material | Mesh |
|---|---|---|---|
| 0 | sprite | `MI_SW_Glint_Normal` | — |

| Phase | Module | Asset | Input | Bound to |
|---|---|---|---|---|
| EmitterUpdateScript | `SpawnBurst` | `SpawnBurst_Instantaneous` | `Spawn Count` | `14` |
| ParticleSpawnScript | `Init` | `InitializeParticle` | `Lifetime` | `User.Lifetime` |
| ParticleUpdateScript | `ScaleSpriteSize` | `ScaleSpriteSize` | `Uniform Scale Factor` | `User.Radius` |
| ParticleUpdateScript | `Color` | `Color` | `Color` | `User.PrimaryColor` |
|  |  | `` | `Scale Alpha` | `User.Intensity` |

##### Renderer settings — MANUAL EDITOR STEP

- **sprite:** Alignment = `Velocity Aligned` is NOT wanted here; the glint and motes are camera-independent points of light, so leave it `Unaligned`.
- **sprite:** Sub Image / sprite size index stays 0 - sizing is done on the particle.

##### MANUAL EDITOR STEP

1. Sprite size over life: 0.4 -> 1.0 quickly, then 1.0 -> 0.6
2. Hit timing is owned by the animation event, never by the system
3. Rename MI_SW_Glint_* to per-surface instances for body / stone / metal / wood

#### Why this system is built this way

- One system, one material instance per surface. The graph must never branch on surface type; the caller chooses the instance.
- The contact timing belongs to the animation event. A Delay module in here would desync the moment the move is retuned.

## Writes the toolset refused

Listed rather than hidden. An input the builder could not set is either a
mistake in the builder or a genuine editor-only step, and the difference
matters.

None. Every input the builder asked for was found, editable, and re-read
back from the graph with the expected binding.
