# MELO — TOP CANDIDATES

17 of 84. Everything else is either a duplicate export, a plain chamfered slab, or
greybox. Ratings follow the brief: **A** = directly reusable (scale / material /
naming / minor cleanup), **B** = kitbash source (shape good, needs拆件 + rebuild),
**C** = reference only (do not use the mesh), **REJECT** = no value.

## The headline finding

The brief assumed MELO is industrial sci-fi mecha and warned against "怎么突然有
高达零件". MELO's own `docs/STYLE.md` says the opposite:

> 只用 Cone、Triangle、Hexagon、Circle、**Floating Ring**、Crystal、Plane。大形体、
> 留白、对称、能量核心与可读轮廓。
> 禁止复杂雕花、**现代机械**、真实皮肤、真实布料、随机细节、**线缆**与写实磨损。
> 主色象牙白、次色金、能量青蓝、结构蓝黑。

No cables. No modern machinery. No random detail. Ivory + ancient gold + cyan
energy core + blue-black structure, in large symmetrical faceted forms.

**MELO is already an ancient-construct language.** Its `arc_ancient_sanctuary_kit`
is literally named "Ancient Sanctuary". The de-sci-fi risk is far lower than the
brief anticipated, and the real risk is the opposite one: adopting assets so close
to SEKAI's Ancient Ruin direction that they stop reading as SEKAI specifically.

## Target 01 — Lesser Ruin Sentinel / 遗迹哨兵

| | |
| --- | --- |
| asset | `msh_cre_ancient_sentinel_lod0_v001` |
| source | `asset_library/creatures/cre_ancient_sentinel/meshes/` |
| measured | **0.92 × 0.29 × 1.06 m**, 18,188 tris |
| what it is | a floating ivory-ceramic construct. Faceted triangular plates, gold joint trim, a glowing pale-blue core in the chest, a gold hover ring beneath it, a second ring above the head, no legs |
| reuse | **REUSE-A** |
| why useful | it is a functioning Lesser Sentinel: hovering, ring-based, readable from a distance, 1 m tall - the exact silhouette class SEKAI needs and does not have |
| target use | `遗迹哨兵` lesser variant, and the base for the Training Ground's mechanical target |
| required changes | drop the baked 80-tri collision icosphere (`棱角球.006`, 1.9 × 2.0 × 2.0 m); re-author materials into SEKAI's stone/metal set; decide whether the blue core stays cyan or moves to SEKAI's element colour; ~18 k tris is over budget for a lesser enemy and needs a decimate pass |

## Target 02 — World Beacon / 信标

| | |
| --- | --- |
| asset | `msh_arc_ring_device_large_v001` |
| source | `asset_library/architecture/arc_ancient_sanctuary_kit/meshes/` |
| measured | **3.78 × 2.40 × 3.78 m**, 1,478 tris |
| what it is | a large double-hooped gold torus standing upright on a dark plinth, holding a glowing cyan core |
| reuse | **REUSE-A** |
| why useful | this is a device that *watches*. Ring + core + plinth is the whole 信标 idea already built, at 1.5 k tris |
| target use | 信标 / World Beacon, and the `region_gate` centrepiece |
| required changes | de-gold the ring or age it (SEKAI metal is aged, not polished gold); replace the polished cyan core with SEKAI's restrained core material; add the "观察者" read - the core should face the player |

| | |
| --- | --- |
| asset | `msh_arc_shrine_device_v001` |
| measured | **3.00 × 2.40 × 3.15 m**, 900 tris |
| what it is | an ivory arch on a dark base enclosing a gold ring and a glowing core - a smaller, more altar-like sibling of the ring device |
| reuse | **REUSE-A** |
| why useful | better proportion for a settlement-scale beacon than the 3.78 m one, and cheaper |
| target use | 信标 shrine inside 雾谷, or the Mistvale region gate |

| | |
| --- | --- |
| asset | `msh_arc_arch_frame_v001` / `msh_arc_gate_frame_large_v001` |
| measured | 5.20 × 1.08 × 5.48 m and 7.00 × 1.08 × 7.30 m, both **1,252 tris** |
| reuse | **REUSE-A** (but note they are the *same mesh* at two scales) |
| why useful | a free-standing arch that suspends a ring in its opening - a portal read with no animation needed |
| target use | World Beacon outer frame; Mistvale Access gate |
| required changes | pick one scale and delete the other - shipping both is 89 KB of duplicate |

## Target 03 — Chain Weapon / 缚星链

Nothing in MELO is a chain. **No direct reuse.** But it does contain the
connector vocabulary the chain needs, as named nodes inside the hero body:

| node | what it is | reuse |
| --- | --- | --- |
| `Melo_BackHalo_0/1/2` | three concentric gold rings, stacked | **REUSE-C** - link silhouette |
| `Melo_NeckHalo` | smaller ring | **REUSE-C** |
| `Melo_CoreRearRing` | ring with a raised lip | **REUSE-C** - the link's load-bearing face |
| `Melo_JointA/B/C_L` | three mechanical joint pieces forming an arm | **REUSE-C** - hinge logic |

The value is **mechanism reference, not mesh**: a ring-with-lip that stacks into a
taut line is exactly how a 缚星链 link should read, and it is a better starting
point than inventing one. Per §15 this goes through Chat2Blender as a redesign,
not through a copy.

## Target 04 — Training Ground

The Training Ground may be more neutral than Mistvale, so these drop in fastest.

| asset | measured | tris | reuse | use |
| --- | --- | --- | --- | --- |
| `msh_arc_energy_core_large_v001` | 3.23 × 3.23 × 3.68 m | 2,050 | **REUSE-A** | VFX stage centrepiece; a real thing to throw effects at instead of a cube |
| `msh_arc_energy_core_medium_v001` | 1.85 × 1.85 × 2.17 m | 2,050 | **REUSE-A** | same mesh at 57% - keep one |
| `msh_arc_ancient_terminal_v001` | 1.60 × 1.42 × 1.41 m | 764 | **REUSE-A** | developer panel / rack housing; pairs with `training_weapon_rack.gd` |
| `msh_arc_pillar_broken_v001` | 2.40 × 1.55 × 4.49 m | 1,256 | **REUSE-A** | a target with actual vertical presence next to the flat dummies |
| `msh_arc_ruin_fragment_c_v001` | 1.93 × 1.50 × 2.04 m | **244** | **REUSE-A** | the cheapest useful piece in the whole audit - debris, blockers, cover |
| `msh_drone_cannon_a_v001` | 0.35 × 0.48 × 0.50 m | 1,604 | **REUSE-B** | small floating training target |

## Target 05 — Ruin Environment

| asset | measured | tris | reuse | note |
| --- | --- | --- | --- | --- |
| `msh_arc_pillar_large_v001` | 1.45 × 1.45 × **7.42 m** | 928 | **REUSE-A** | a 7.4 m column with a dark pyramidal cap. Best single ruin piece in the kit |
| `msh_arc_energy_door_frame_v001` | 4.40 × 1.08 × 4.75 m | 1,468 | **REUSE-A** | door mechanism with a suspended ring |
| `msh_arc_door_frame_v001` | 3.20 × 1.08 × 3.60 m | 1,036 | **REUSE-B** | same idea, plainer |
| `msh_arc_stairs_v001` | 4.00 × **8.00** × 2.20 m | 972 | **REUSE-B** | an 8 m run. Directly comparable to KIT-02a and worth studying, but it is one monolithic mesh, not a modular kit |
| `msh_arc_ramp_v001` | 4.00 × 7.97 × 1.99 m | **188** | **REUSE-B** | a ramp for 188 tris |
| `msh_arc_crystal_cluster_a_v001` | 0.87 × 0.88 × 1.13 m | 900 | **REUSE-A** | crystal cluster; good for the ruins and the VFX stage |
| `msh_arc_tree_a_v001` | 2.69 × 2.49 × **5.35 m** | 1,644 | **REUSE-B** | a fully stylised tetrahedral conifer. Not Mistvale's language, but a valid ruins/exterior silhouette |
| `msh_arc_altar_main_v001` | 4.03 × 3.76 × 1.42 m | 1,280 | **REUSE-A** | ring platform on radial shards. Strong ritual-site piece |

## Reference only (REUSE-C) — do not use the mesh

| asset | measured | tris | why reference |
| --- | --- | --- | --- |
| `msh_chr_melo_body_lod0` (+14 duplicate exports) | 1.60 × 0.55 × 2.18 m | 7,056 | the hero body. Ivory/gold humanoid with a gold cape, crescent head, dark halo. Its *proportion system* and its 7 named modules are the reference; the mesh is a flight hero for a different camera distance |
| `msh_cin_brutalist_megagate_v001` | **112.46 × 142.04 × 44.00 m** | 10,976 | a 112 m megastructure. Landscape-scale landmark proportion reference |
| `msh_cin_tianji_cannon_v001` | 22.04 × 14.40 × 22.04 m | 15,764 | concentric gold rings + radial fins around a glowing core - a giant device proportion reference |
| `msh_bos_city_core_devourer_v001` | **75.00 × 75.00 × 48.00 m** | 45,784 | boss reference for an Ancient Colossus, per §17 |
| `msh_arc_bush/grass/dead_tree/rock_*` | 0.8–2.0 m | 520–1,300 | shape language for ruins vegetation |
| `msh_arc_bridge_broken_v001` | 2.08 × 1.98 × 0.41 m | 764 | broken slab proportion |

## REJECT — and why

| group | count | reason |
| --- | --- | --- |
| `msh_arc_floor_*`, `msh_arc_platform_*`, `msh_arc_floating_floor_*` | 9 | chamfered boxes with a dark rim. SEKAI's ENV-01 already does this better, with a tread modulus and a collision-ramp contract MELO has no equivalent of |
| `msh_arc_wall_*` (4x4, 8x4, corner, broken a/b) | 5 | plain dark slabs |
| `msh_arc_brick_a/b`, `broken_block_a/b` | 4 | unnamed blocks, no ruin read |
| `msh_arc_bridge_long_v001` | 1 | renders as two bare rails |
| `msh_cin_tianji_ambush_set_v001` | 1 | 16,364 tris spread over a 47 × 36 × 124 m flat set |
| 14 of 15 `msh_chr_melo_*` exports | 14 | byte-different but geometry-identical re-exports for animation tests. Same 7,056 tris, same 1.60 × 0.55 × 2.18 m box |
| `ancient_ruins_kit.gd` | - | its own header: "greybox modules (CSG/Mesh). No hi-poly." Reference for the placement API only |

## Two traps worth recording

**1. Collision proxies masquerade as the model.** 21 of 84 GLBs ship a helper mesh
that can be larger than the asset. The Ancient Sentinel carries `棱角球.006`, an
80-triangle icosphere at **1.9 × 2.0 × 2.0 m** wrapping a 0.92 × 0.29 × 1.06 m
body. Measured naively it reports as a 2 m asset and a 5×-too-small render. Any
importer must strip these first.

**2. Several "different" pieces are one mesh at two scales.**

| large | small | tris (identical) |
| --- | --- | --- |
| `ring_device_large` 3.78 m | `ring_device_small` 1.70 m | 1,478 / 1,478 |
| `energy_core_large` 3.23 m | `energy_core_medium` 1.85 m | 2,050 / 2,050 |
| `arch_frame` 5.20 m | `gate_frame_large` 7.00 m | 1,252 / 1,252 |

Ship one and scale it.
