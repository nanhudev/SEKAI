# MELO — SEKAI CONVERSION PROPOSALS

Five proposals, one per TARGET in the brief. Each one states MELO's current state,
SEKAI's target context, the specific changes, and whether the work is **local
cleanup** (Blender, ART line) or a **Chat2Blender redesign** (new geometry).

Per §15: if a MELO asset is only 30–60% right, it does not get hand-edited. It
goes to Chat2Blender with the mesh, screenshots, dimensions and target, and comes
back as a SEKAI asset. That is the line between "cleanup" and "redesign" below.

Per §16 and §19, none of these may land in Mistvale residential. All five serve
Ruin / Construct / Beacon / Training Ground / Weapon Mechanics only.

---

## P-01 · World Beacon / 信标

**From** `msh_arc_ring_device_large_v001` (3.78 × 2.40 × 3.78 m, 1,478 tris)
plus `msh_arc_arch_frame_v001` as an optional outer frame.

**MELO now** — a polished gold double torus, upright, on a dark plinth, enclosing a
bright cyan core. Clean, symmetrical, ceremonial. It reads as a *device that
works*, which is the opposite of what a 信标 in 雾谷 should read as.

**SEKAI target** — the 信标 is the thing the 观察者 sees the world through. It
should read as *still functioning and doing so under protest*: an ancient
structure that was not built by anyone currently alive, holding a core that is
restrained rather than bright.

| change | detail |
| --- | --- |
| material | gold → aged dark metal. MELO ships `M_Creature_AncientGold` at metallic 0.86 / roughness 0.34; SEKAI wants metal that has been outside for centuries |
| core | cyan emission 4.0 with a 2 Hz pulse is a game HUD, not a relic. Reduce to a low steady emission with a slow irregular breath |
| surface | MELO's forms are perfect. SEKAI's Ancient Ruin language is "imperfect geometry / ancient construction". Add a chamfer break on the ring's outer edge and a chip on one quadrant of the plinth |
| symmetry | break it once. One hoop slightly out of plane. Perfect symmetry reads as manufactured |
| grounding | the plinth must look *set into* the fog-valley floor, not placed on it |

**Verdict — local cleanup + one redesign pass.** Geometry is 85% right; the work is
material, core restraint and one deliberate imperfection. The ring itself does not
need Chat2Blender. The *core* does: the current core is an icosphere, and SEKAI's
信标 core needs a designed form, not a sphere.

---

## P-02 · Lesser Ruin Sentinel / 遗迹哨兵

**From** `msh_cre_ancient_sentinel_lod0_v001` (0.92 × 0.29 × 1.06 m, 18,188 tris).

**MELO now** — a floating ivory-ceramic construct with faceted triangular plates,
gold joint trim, a glowing blue chest core, a gold hover ring below, a second ring
above the head, and no legs. Its parts are already named the way a construct
should be: `Chest_Main`, `Head_Fin_L/R`, `Back_Shards_L/R`, `Hover_Shards_L/R`,
`Hand_*_Shards`, `Shoulder_*`, `Core_Outer`, `Core_Ring`, `Waist_Ring`,
`Neck_Ring_Upper`, `Hover_Ring`.

**SEKAI target** — 遗迹哨兵, the enemy family in 雾谷. Not a sci-fi drone: an
ancient guardian that has been standing in wet air for a long time.

| change | detail |
| --- | --- |
| strip | remove `棱角球.006`, the 80-tri collision icosphere at 1.9 × 2.0 × 2.0 m. It is a proxy, not geometry |
| budget | 18,188 tris is a hero budget for a lesser enemy. Target 5–6 k with the silhouette intact: the shard limbs and rings carry the read, the plates do not |
| material | `M_Creature_IvoryCeramic` is already close to stone. Push toward `M_Env_IvoryStone` and let a wet-dark film sit in the recesses. Gold trim → aged bronze, only where it is a joint |
| core | keep it as the one bright element, but it must be the *only* one |
| damage | MELO's style rule bans realistic wear. So damage is structural, not texture: a missing shard, a ring with one segment gone, a cracked plate. Broken, not weathered |
| silhouette | keep the hover ring. Floating without legs is the single most valuable thing this asset offers |

**Verdict — local cleanup, no redesign needed for the read.** This is the closest
match in the entire audit: a 1 m floating ring-based construct with a chest core is
already 遗迹哨兵. The work is decimation, material transfer and structural damage.
A Chat2Blender pass is worth it **only for the core piece**, which should be
designed to match SEKAI's 信标 core so the family reads as one civilisation.

---

## P-03 · 缚星链 / Chain Weapon — connector design

**From** the hero body's ring and joint nodes: `Melo_BackHalo_0/1/2`,
`Melo_NeckHalo`, `Melo_CoreRearRing`, `Melo_JointA/B/C_L`.

**MELO now** — no chain exists. But the hero is built from stacked concentric rings
(`BackHalo_0/1/2` are three rings in a row) and named joints.

**SEKAI target** — a chain whose links read as *ancient*, not as hardware.

| change | detail |
| --- | --- |
| do not copy | per §5, a mecha ring is not a chain link. This is a **language** transfer |
| take | the mechanism logic: a ring with a raised lip that stacks into a taut line. `Melo_CoreRearRing` is the shape that shows how a link's load-bearing face works |
| take | the joint logic from `Melo_JointA/B/C_L` — three pieces forming one articulation, which is how a chain link should fold |
| redesign via Chat2Blender | a link that is a *closed ring with an inward lip*, sized so it reads at 3 m and stacks under tension. Reference the halo rings for silhouette, not for mesh |
| budget | a 20 m chain in the Training Ground Chain Lab needs the link cheap. ~60–120 tris per link |

**Verdict — Chat2Blender redesign. REUSE-C.** Nothing here is copied. What is
recovered is a mechanism language that is already visually consistent with SEKAI's
rings-and-cores Ancient Ruin vocabulary, which is worth more than a mesh.

---

## P-04 · Training Ground

**From** `msh_arc_energy_core_large_v001` (3.23 m, 2,050 tris),
`msh_arc_ancient_terminal_v001` (1.60 m, 764 tris),
`msh_arc_pillar_broken_v001` (4.49 m, 1,256 tris),
`msh_arc_ruin_fragment_c_v001` (2.04 m, **244 tris**).

**MELO now** — the energy core is a cone hovering inside a gold ring on a dark
cylindrical pedestal. The terminal is a ceramic monolith on a dark base with a blue
panel. Both are genuine objects, not placeholders.

**SEKAI target** — §18 says the Training Ground may be more neutral than Mistvale,
and §22–24 already asked for a stylised-but-neutral look. These give the VFX stage
and combat court *real geometry to be thrown at* instead of the current
`_dummy_station` cones and slab placeholders.

| change | detail |
| --- | --- |
| import as-is first | these are the cheapest wins in the audit. Put them in the scene and look, before changing anything |
| VFX stage | the energy core becomes the effect target. It is already ring + core, so an effect that wraps or shatters it reads immediately |
| weapon rack | the terminal becomes the rack housing, pairing with the existing `training_weapon_rack.gd`. Its ceramic monolith already reads as a stand |
| combat court targets | `pillar_broken` at 4.49 m and `ruin_fragment_c` at 244 tris replace the flat white cones. A 244-tri piece is free |
| material | keep MELO's ivory/dark for Training Ground only, and document that this is a *review-space* material, never Mistvale's |
| do not | do not let any of it into `MistvaleRegion.tscn` |

**Verdict — direct import (REUSE-A).** This is where §18's "Training Ground 优先吃
旧资源" pays off immediately. It raises the review space's asset quality without a
single new asset being modelled.

---

## P-05 · Ruin Environment

**From** `msh_arc_pillar_large_v001` (1.45 × 1.45 × 7.42 m, 928 tris),
`msh_arc_pillar_broken_v001` (2.40 × 1.55 × 4.49 m, 1,256 tris),
`msh_arc_energy_door_frame_v001` (4.40 m, 1,468 tris),
`msh_arc_crystal_cluster_a_v001` (1.13 m, 900 tris),
plus `msh_arc_stairs_v001` and `msh_arc_ramp_v001` as comparison.

**MELO now** — tapered ivory columns with dark pyramidal caps; a door frame
suspending a ring; blue crystal clusters. Structurally clean, deliberately plain.
The stair is a single monolithic 8 m run.

**SEKAI target** — 雾谷's ruins: 遗迹哨兵 territory, wet air, ancient construction.

| change | detail |
| --- | --- |
| material — the main job | every piece is currently clean ivory + dark stone + gold. SEKAI's ruins need the wet-valley treatment: moss in the joints, dark water staining on the lower third, stone that has moved |
| **no polish** | MELO's forms are machine-perfect. Ancient construction needs the opposite. This is the largest single gap in the whole audit |
| the stair is a lesson, not an asset | `msh_arc_stairs_v001` is one 972-tri mesh for an 8 m run. KIT-02a is modular at a locked 2/7 m tread with a separate collision ramp. MELO's stair is what KIT-02a exists to avoid. Do not import it - read its proportions and keep KIT-02a |
| pillar | the 7.42 m column is the best single piece here. It gives the ruins vertical scale that ENV-01 has no equivalent for |
| crystal | keep the cluster, but decide whether the ruins glow. If the 信标 is the only light source, the crystals must be dark |
| door frame | the suspended ring makes this a *mechanism*, not decoration. It pairs with the 信标 family |

**Verdict — local cleanup for pillars and fragments; the wet-valley material pass is
the actual work, and it is a material problem, not a geometry problem.** The stair
and ramp are REUSE-B at best and are explicitly *not* recommended for import while
KIT-02a's modulus contract is in force.

---

## What this audit concludes

MELO is not a source of "mecha parts". It is a source of a **complete, internally
consistent ancient-construct art language** — ivory ceramic, aged gold, dark
structure, glowing cores, floating rings, large symmetrical facets — built by the
same user, at 275 k triangles for the entire library.

The single most valuable recovery is not any mesh. It is that SEKAI's 信标, 遗迹哨兵
and 缚星链 should look like they were made by **the same civilisation**, and MELO
already demonstrates what that civilisation looks like. Round 2 should convert
P-01, P-02 and P-04 first, because those three make the Training Ground review the
whole Ancient Ruin direction in one walk.
