# ENV-01 — Mistvale Ground / Stair / Terrace Kit V1

**Asset ID:** ENV-01
**Type:** Modular environment kit (terrain + structure transition)
**Priority:** P0
**Status:** SPEC READY

## Use case

Buildable ground system for the Mistvale starting region, and the wholesale replacement
of `godot/scripts/systems/arena_dressing.gd` placeholder geometry in the combat sandbox.

`arena_dressing.gd` states in its own header comment that it is deterministic placeholder
geometry "meant to be replaced wholesale by the ART line". This kit is that replacement.

## Why a kit and not a map

The problem is not "there is no village". The problem is that three different needs —
combat arena silhouette, town exploration, and future region expansion — all currently
have nothing to stand on. One kit serves all three:

- combat sandbox: terrace slabs, pillars, cliff edge give the Iaido cut something real to act on
- town: terraces + stairs + retaining walls create the vertical structure Mistvale needs
- regions: the same pieces recombine

## Style

Stylized next-gen fantasy. Anime-readable, clean, consciously designed masonry.
NOT generic low-poly, NOT mobile-toy, NOT photoreal noise. Blocky stone courses with
subtle chamfered edges so silhouettes read without texture detail.

## Modular grid

**2.00 m base grid.** Every piece's footprint is an exact multiple. Origins sit on the
ground plane at the footprint centre, except stairs/ramps where the origin is at the
bottom of the run, centred across the width.

## Piece list (12)

| # | Object name | Dimensions (m, X × Y × Z) | Notes |
| --- | --- | --- | --- |
| 1 | `ENV01_Terrace_4x4` | 4.0 × 4.0 × 0.30 | raised slab, stone courses on the side, 0.10 edge trim |
| 2 | `ENV01_Terrace_8x8` | 8.0 × 8.0 × 0.30 | plaza slab, inset paving lines dividing it into 4×4 cells |
| 3 | `ENV01_Terrace_StepEdge_4` | 4.0 × 0.60 × 0.30 | low lip / bench edge, sits on top of a terrace |
| 4 | `ENV01_Stair_Straight_4` | 4.0 run × 2.0 wide × 1.44 tall | 8 risers of 0.18 rise / 0.50 tread |
| 5 | `ENV01_Stair_Landing_2x2` | 2.0 × 2.0 × 0.30 | flat landing, top face height matches terrace top |
| 6 | `ENV01_Ramp_4x2` | 4.0 × 2.0, rises 0.90 | ~12.7°, solid cheeks either side, paved top |
| 7 | `ENV01_RetainingWall_4x1p5` | 4.0 × 0.45 × 1.50 | stone courses, cap stone overhanging 0.04 |
| 8 | `ENV01_RetainingWall_Corner` | 4.0 × 4.0 L-plan × 1.50 | inner corner variant of #7 |
| 9 | `ENV01_Curb_4` | 4.0 × 0.30 × 0.16 | kerb strip, chamfered top |
| 10 | `ENV01_CliffEdge_4` | 4.0 × 1.0 × 1.20 | broken rock edge, irregular top profile, 5–7 chunks |
| 11 | `ENV01_BridgeDeck_4` | 4.0 × 2.0 × 0.35 | timber plank deck over stone stringers |
| 12 | `ENV01_BridgeRail_4` | 4.0 × 0.15 × 1.05 | posts every 1.0 m, two horizontal rails |

## Materials (4)

| Name | Base colour (linear-ish) | Metallic | Roughness | Used by |
| --- | --- | --- | --- | --- |
| `MV_Stone_Base` | 0.42, 0.44, 0.47 | 0.0 | 0.85 | terraces, stairs, walls, curb |
| `MV_Stone_Pale` | 0.68, 0.64, 0.55 | 0.0 | 0.80 | cap stones, edge trim, paving |
| `MV_Timber_Dark` | 0.20, 0.15, 0.12 | 0.0 | 0.70 | bridge deck, bridge rails, ramps cheeks |
| `MV_Moss_Accent` | 0.32, 0.38, 0.30 | 0.0 | 0.90 | occasional stone block variation, cliff edge |

## Poly budget

**< 30,000 tris for the whole kit**, target 20,000–25,000. Stairs and cliff edge are the
heaviest; terraces must stay under 1,200 tris each.

## Chunk plan requested from ChatGPT

| Chunk | Contents |
| --- | --- |
| `kit_common` | helpers: localisation-safe material factory, box/mesh builder, origin helper, transform apply, collection setup |
| `terraces` | pieces 1, 2, 3, 5, 9 |
| `stairs_ramps` | pieces 4, 6 |
| `walls_edges` | pieces 7, 8, 10 |
| `bridge` | pieces 11, 12 |

## Paths

- Blender source: `assets_source/environment/mistvale/env01_ground_kit.blend`
- GLB export: `assets/models/environment/mistvale/*.glb` — one GLB per piece, named after the object
- Godot usage: `godot/models/environment/mistvale/`

## Acceptance

- [ ] every piece is an exact multiple of the 2 m grid
- [ ] every piece has rotation 0 / scale 1 and an origin on the grid footprint
- [ ] material count is exactly 4, and all 4 render with correct base colour
- [ ] whole kit under 30k tris
- [ ] each piece renders a readable silhouette in the QA render
- [ ] placed in Godot and visible in the combat sandbox

## Godot usage note

One GLB per piece is deliberate: each piece then drops into a scene as a single Mesh
resource, which makes kitbashing a scene fast and keeps instancing cheap.
