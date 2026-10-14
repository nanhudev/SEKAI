# MISTVALE GAMEPLAY MAP

The manifest the integration brief (§40) asks for: which map is the game's map,
where it is, what a player starts on, and which anchors gameplay can ask for by
name.

**Status: PLAYABLE — needs User Gameplay Verified.** Every claim below is
measured, not asserted; the tool that measures each one is named next to it. No
claim here has been confirmed by a human playing it.

---

## 0. Integration report (brief §62)

```
PROJECT          F:/SEKAI/ue5_lab/Mistvale_Rebuild/Mistvale_Rebuild.uproject
MAP              /Game/Maps/L_Mistvale_Rebuild        (UMAP 395,888 B)
UE VERSION       5.8.3, CL 58210709  (F:/UE_5.8)
RUNTIME          Godot 4.4.1, gl_compatibility  ->  res://scenes/world/MistvalePlayable.tscn
PLAYER START     (5.93, 1.52, -310.03)  facing +Z, on the road, ground y = 0.57
PLAYABLE         YES -- PARTIAL. Walkable and reachable end to end; no interiors,
                 no NPCs, no story, no second region.
GOLDEN ROUTE     PASS. 667.2 m, 0 holes, 0 steps > 0.35 m, 0 blockers.
POIs             8 POI_ (SouthEntry, Riverside, MainBridge, Market, Guild,
                 GuildTraining, Church, NorthGate)
WORLD EXITS      3 TRG_ (SouthWorldExit, NorthGateExit, RiverRoute)
SAFE POINTS      6 SAFE_ (South, Bridge, Market, Guild, Church, NorthGate)
ANCHORS          5 ANCHOR_ (Lia_River, Oren_Workshop, Mira_TownEdge,
                 Veil_Guild, Taim_SouthRoad)
KNOWN ISSUES     5, listed in §7. The first two are the ones a person notices.
```

## 1. Where the map is

| | |
|---|---|
| UE project | `F:/SEKAI/ue5_lab/Mistvale_Rebuild/Mistvale_Rebuild.uproject` |
| Map | `/Game/Maps/L_Mistvale_Rebuild` |
| UMAP on disk | `Mistvale_Rebuild/Content/Maps/L_Mistvale_Rebuild.umap` (395,888 B) |
| UE version | 5.8.3, CL 58210709 (`F:/UE_5.8`) |
| Runtime engine | **Godot 4.4.1**, `gl_compatibility` — UE5 is the authoring/level-art environment only |
| Scene | `res://scenes/world/MistvalePlayable.tscn` |
| Entry | Main menu → **探索雾谷（城镇）** (`main_flow.start_region()`); `res://scenes/main/Main.tscn` boots it |
| Predecessor | `MistvaleRegion.tscn` (LD-01 blockout) — kept, still reachable via `main_flow.region_blockout_scene`. Not deleted, not the door. |

The UE project is content-only: **0 Blueprints, 0 C++, 0 GameMode, 0 Pawn.** The
`.uproject` description says "Godot playable project remains separate", which is
exactly the split this manifest records: UE builds the place, Godot runs it.

## 2. How the geometry gets in

`L_Mistvale_Rebuild` → FBX → glTF → Godot, with a check at every hop:

| Step | Tool | Verified against |
|---|---|---|
| Level → FBX | `tools/ue5_import/export_level_fbx.py` | `_handoff/export_audit.json` |
| FBX → GLB + palette | `tools/ue5_import/export_glb.py` | `_handoff/glb_expected.json` |
| GLB in Godot | `godot/tools/probe_mistvale_ue.gd` | `_handoff/glb_actual.json` — max per-node delta **0.0001 m** |
| Collision bake | `godot/tools/bake_mistvale_collision.gd` | its own 12-point assertion |

226 actors, 281,342 triangles, metric, unmirrored. Frame convention is
`godot = (ue.x, ue.z, -ue.y)`.

**Asset:** `godot/models/mistvale_ue/mistvale_rebuild.glb` (2.7 MB) +
`mistvale_collision.res` (10 MB, one world-space `ConcavePolygonShape3D`).

The FBX export carries **no material colours** (`bake_material_inputs=DISABLED`),
so all 24 materials arrive grey. The 21 real colours are recovered from the
scripts that already own them (`model_guild.py`, `model_stone_bridge.py`,
`render_saved_scene.py`) by `export_glb.py`'s `PALETTE`.

## 3. Player start

```
POI_SouthEntry     (  5.93,   0.53, -314.03)
spawn (capsule)    (  5.93,   1.52, -310.03)   facing +Z, i.e. north up the route
```

The x is read from the road ribbon's own southern 12 m, not typed: the road's
whole-actor AABB centres on x = −0.50, but that AABB spans the road's 205 m
swing, so spawning on it would put the player on the verge 6.5 m west of the
road. Measured by `godot/tools/walk_mistvale_route.gd`.

The handoff's own `PlayerStart_MistvaleSouth` (UE 600, −31000, 157.62 cm) is
**unusable**: it is in the opposite half of the map from the golden route's south
end and 24 m below the ground, because its height was probed with the Y axis
already flipped while its coordinate was not.

## 4. Golden Route

**PASS — continuous end to end.** `godot/tools/walk_mistvale_route.gd` walks the
centreline the level's own road surfaces define, with a head-height ray of finite
length, plus a forward chest-height probe:

```
route            667.2 m, 1302 samples, z -320.5 → +330.0
holes            0
steps > 0.35 m   0        (0.35 m = the player capsule's radius)
blocked          0
climb            26.79 m
anchors          22 checked, 0 off the walkable surface, 0 on a roof
```

Order, south to north: **South Entry → riverside → main bridge → lower town →
market → guild → church → north gate.** Surface chain:

```
ART_Surface_SM_Route_GoldenRoute_South   z -320.0 .. -114.6
SM_Handoff_BridgeSouth                   z -119.0 .. -102.0   (ramp, y 5.88 → 6.39)
MainStoneBridge_DECK                     z -104.3 ..  -65.5   (deck flat at 6.374)
SM_Handoff_BridgeNorth                   z  -68.0 ..  -52.0   (ramp, y 6.39 → 7.88)
ART_Surface_SM_Route_GoldenRoute_Town    z  -55.6 .. +330.0
```

## 5. Anchors

All 22 are `Node3D` markers under `Anchors/`, derived at run time from the named
actor's world AABB and then grounded by raycast. Nothing is hand-placed.

| POI | x | y | z | derives from |
|---|---|---|---|---|
| `POI_SouthEntry` | 5.93 | 0.53 | −314.03 | GoldenRoute_South (south end) |
| `POI_Riverside` | −9.59 | 5.34 | −126.99 | RiversideStreet |
| `POI_MainBridge` | 0.00 | 6.37 | −84.93 | MainStoneBridge_DECK |
| `POI_Market` | −7.50 | 14.78 | 92.00 | Plaza_MarketSquare |
| `POI_Guild` | −30.00 | 16.99 | 163.00 | Plaza_GuildForecourt |
| `POI_GuildTraining` | −82.00 | 16.91 | 162.00 | HERO_Guild_TrainingYard |
| `POI_Church` | 104.00 | 20.61 | 211.00 | Plaza_ChurchForecourt |
| `POI_NorthGate` | −0.96 | 24.51 | 283.18 | HERO_NorthGate_Lintel |

| World exit | x | y | z |
|---|---|---|---|
| `TRG_SouthWorldExit` | 5.93 | 0.31 | −326.03 |
| `TRG_NorthGateExit` | −0.96 | 24.80 | 290.45 |
| `TRG_RiverRoute` | −9.59 | 5.34 | −126.99 |

| Safe point | x | y | z |
|---|---|---|---|
| `SAFE_South` | 5.93 | 0.53 | −314.03 |
| `SAFE_Bridge` | 0.00 | 6.37 | −84.93 |
| `SAFE_Market` | −7.50 | 14.78 | 92.00 |
| `SAFE_Guild` | −82.00 | 16.91 | 162.00 |
| `SAFE_Church` | 104.00 | 20.61 | 211.00 |
| `SAFE_NorthGate` | −0.96 | 24.51 | 283.18 |

| Narrative anchor | x | y | z |
|---|---|---|---|
| `ANCHOR_Lia_River` | −9.59 | 5.34 | −126.99 |
| `ANCHOR_Oren_Workshop` | −62.82 | 12.90 | 64.36 |
| `ANCHOR_Mira_TownEdge` | −1.47 | 8.10 | −49.65 |
| `ANCHOR_Veil_Guild` | −25.00 | 16.48 | 154.50 |
| `ANCHOR_Taim_SouthRoad` | 5.93 | 0.53 | −314.03 |

No NPCs, no story, no quest markers — positions only (brief §24).

## 6. Gameplay systems present

- **River is not walkable.** `ART_Surface_SM_River_Continuous` is excluded from
  the collision bake, so the player goes in rather than walking on the water like
  ice, and is recovered by the fall volume below.
- **Fall recovery.** `mistvale_playable.gd::_physics_process` puts the player at
  the nearest `SAFE_*` once below `FALL_FLOOR` (−12 m). No UI, no checkpoint
  (brief §30-31).
- **Training Yard is combat-usable.** The scene carries the same director stack
  as `TrainingGround.tscn` (Iaido, Moment of No Moon, screen FX, audio, HUD), so
  the sword behaves here as it does everywhere else. `DeveloperPanel` and
  `ParryDebugOverlay` are deliberately absent (brief §52).
- **Settings apply.** `start_region()` calls `_apply_settings()`, which used to be
  inert in this door because the blockout walker has no camera controller.

## 7. Known issues

1. **The south approach is 200 m of flat, straight, untextured road.** The
   graded terrain proxy is a single green plane with no ground detail, and the
   road runs dead straight to the town. Frozen art (brief §3), not a blocker.
2. **The first 250 m reads as empty** at eye level. Fog was pulled from 0.0014 to
   0.00055 to stop the town washing out, but the approach itself is still empty.
3. **`SM_Handoff_BridgeSouth` is wound backwards.** Visible, and (now) solid,
   only because the bake sets `backface_collision = true`. With Godot's default
   the ramp is invisible to collision and the bridge becomes a 1.17 m wall. The
   UE mesh should be fixed at source.
4. **The market square's centre is the well.** `MarketSquare_Well` sits at exactly
   (0.00, 100.00) and is 3 m across, so `POI_Market`/`SAFE_Market` use an inset
   quadrant point instead of the plaza centre.
5. **The map is 1 m of terrain with no interior.** No building is enterable; the
   226 actors are shells. Nothing in the brief asks for interiors.

## 8. Reproducing the verdict

```
godot --headless --path godot --script res://tools/bake_mistvale_collision.gd
godot --headless --path godot --script res://tools/walk_mistvale_route.gd
godot --headless --path godot --script res://tests/mistvale_door_integration.gd

godot --path godot --resolution 1280x720 --audio-driver Dummy \
      --script res://tools/mistvale_walk_renderer.gd -- <out_dir> 4 500
godot --path godot --resolution 1600x900 --audio-driver Dummy \
      --script res://tools/mistvale_map_shot.gd -- <out_dir>
```

The renderers must **not** be headless: they await `RenderingServer.frame_post_draw`
and never fire it without a window. The tests must be headless.
