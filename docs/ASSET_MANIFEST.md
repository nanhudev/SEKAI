# Asset manifest

**Status vocabulary — one word per real state. Do not invent intermediate ones.**

| Status | Means |
| --- | --- |
| `SOURCE READY` | the brief / prompt exists, nothing has been built |
| `BLENDER VERIFIED` | built and looked at in Blender; not exported |
| `GLB READY` | a `.glb` exists in `assets/models/` |
| `GODOT IMPORTED` | the `.glb` is under `godot/models/` **and** the importer has produced a `.import`; the engine can load it |
| `IN SCENE` | some `.tscn` instantiates it |
| `IN-GAME VERIFIED` | a character uses it in the runtime without breaking, and it has been looked at |

> **`GLB copied` is not `Integrated`.** That mistake is already recorded in this
> file's history: the twelve `assets/models/mistvale/*.glb` were listed as
> "Integrated" for a day while `godot/` contained zero references to them.
>
> Every measured number below comes from `tools/audit_art_import.gd`, which reads
> the values out of the engine's own importer. Re-run it rather than trusting
> this table:
>
> ```
> G:/Godot/Godot_v4.4.1-stable_win64_console.exe --headless --path F:/SEKAI/godot \
>   --script res://tools/audit_art_import.gd > F:/SEKAI/assets_source/review/art_import_audit.txt 2>&1
> ```

---

## ENV-01 — Mistvale ground / stair / terrace kit

Source: `assets_source/environment/mistvale/env01_ground_kit.blend` (145 KB)
GLB: `assets/models/environment/mistvale/ENV01_*.glb` × 12 → `godot/models/environment/mistvale/`
Status: **IN SCENE** — instanced by the Training Ground environment showcase
(zone F) and by the movement lane's stair bank.

Measured by the importer (AABB in metres):

| Piece | X | Y | Z | tris | mats |
| --- | ---: | ---: | ---: | ---: | ---: |
| `ENV01_Terrace_8x8` | 8.000 | 0.300 | 8.000 | 396 | 2 |
| `ENV01_Terrace_4x4` | 4.000 | 0.300 | 4.000 | 352 | 2 |
| `ENV01_Terrace_StepEdge_4` | 4.000 | 0.300 | 0.600 | 132 | 3 |
| `ENV01_Curb_4` | 4.000 | 0.160 | 0.300 | 44 | 1 |
| `ENV01_Ramp_4x2` | 4.000 | 0.900 | 2.000 | 90 | 2 |
| `ENV01_Stair_Straight_4` | 4.000 | 1.440 | 2.000 | 572 | 3 |
| `ENV01_Stair_Landing_2x2` | 2.000 | 0.300 | 2.000 | 132 | 1 |
| `ENV01_RetainingWall_4x1p5` | 4.000 | 1.500 | 0.450 | 1,012 | 3 |
| `ENV01_RetainingWall_Corner` | 4.000 | 1.500 | 4.000 | 2,068 | 3 |
| `ENV01_BridgeDeck_4` | 4.000 | 0.350 | 2.000 | 528 | 2 |
| `ENV01_BridgeRail_4` | 4.000 | 1.050 | 0.150 | 396 | 2 |
| `ENV01_CliffEdge_4` | 4.000 | 1.192 | 0.999 | 264 | 2 |

Total **5,986 tris**. Every dimension is an exact multiple of the 2.00 m grid,
which is the kit's whole contract, and the importer confirms it piece by piece.

---

## C2B-01 — First person sword

GLB: `assets/models/weapons/fp_sword.glb` → `godot/models/weapons/`
Scene: `godot/scenes/weapons/Sword_FP.tscn` (created 2026-09-27)
Status: **IN SCENE** (the drop-in scene exists). `INTEGRATED` pending: `Player.tscn`
still holds `TempSwordVisual`. See `docs/ART_INTEGRATION_REQUESTS.md` REQ-2.

Measured: **832 tris**, materials **`MAT_Sword_Steel`, `MAT_Sword_Fittings`,
`MAT_Sword_Grip`, `MAT_Sword_Inlay`**, AABB **0.131 × 0.044 × 1.047 m**.

> Axis correction: the long axis is **Z**, not +Y. The earlier note in
> `CHAT2BLENDER_LOG.md` is wrong on this point — see REQ-2.

---

## Mistvale modular building kit (pre-Chat2Blender)

GLB: `assets/models/mistvale/*.glb` × 12 (`beam, chimney, door, fence,
foundation, roof_slope, sign, stair, wall_door, wall_plain, wall_window, window`)
Status: **GLB READY → GODOT IMPORTED pending**

Copied to `godot/models/mistvale/` on 2026-09-27. The importer had **not** run at
the time of the audit (`FAILED TO LOAD` × 12, and zero `.import` files), which is
exactly the difference between "the file is there" and "the engine can use it".
Needs one editor/import pass. It also still needs a scale and material audit
before it can sit beside ENV-01, since it predates the 2 m grid.

---

## KIT-02a — stair / terrace construction language

Brief: `docs/asset_briefs/KIT-02a-STAIR-TERRACE.md` (rev. 2)
Status: **BLENDER VERIFIED (single piece only)** — gate 1 passed on numbers,
failed on wear, now in a quality pass.

`KIT02A_Stair_R20_7W4` — the S-A civic hero piece, built via Chat2Blender:

| Measured | Value | Contract |
| --- | --- | --- |
| dimensions | 4.0000 × 2.0000 × 1.4000 m | 4.00 wide × 2.00 run × 1.40 tall |
| measured tread | 0.285714285714 m | exactly 2.00/7 |
| step count | 7 | 7 |
| riser | 0.200000 m | 0.200, town-steep civic |
| visual tris | 3,424 | 2,600 – 4,000 |
| `_RAMP` tris | 12 | exactly 12 |
| rotation / scale | 0,0,0 / 1,1,1 | clean |
| materials | `MV_Stone_Base`, `MV_Stone_Pale`, `MV_Timber_Dark`, `MV_Moss_Accent` | exactly four, no fifth |

**Gate 1 result:** PASS on every measured contract. FAIL on §11's qualitative
clause — at first-person distance the treads read as flat clean planes with crisp
edges, so TERTIARY (cause-driven wear: dished centre, chipped outer nosings,
drainage cut, moss in the joints) is not legible. A QUALITY PASS was requested
rather than expanding the kit, which is the §19 rule.

The other 19 pieces are **SOURCE READY** (spec written, not built).

---

## C2B-02 / 03 / 04 — FP hand · Lesser Ruin Sentinel · Magic Catalyst

Status: **SOURCE READY** (briefs only). Unchanged.

---

## UI Kit V1

Source: `assets_source/ui/kit_v1/*.svg` (5 files) → `godot/ui/kit_v1/`
Status: **IN GODOT (files placed)**. No `.tscn` instantiates them yet.

---

## UE5 VFX LAB assets

Different pipeline, different vocabulary. See `docs/UE5_VFX_LAB.md`.

| Asset | UE stage | Godot stage |
| --- | --- | --- |
| Reality Glass — fracture (202 cells, 769 tris) | `EXPORTED` | not started |
| Reality Glass — shards (18, 58 tris, with `dist_to_cut`) | `EXPORTED` | not started |
| Reality Glass — 5 masks @ 1024×576 | `EXPORTED` | not started |

---

## MELO legacy assets (recovered)

Source: `C:/Users/Administrator/Desktop/项目_开发与研究/Melo-Godot-Prototype`
(`Melo: Light Rhythm Prototype`, Godot 4.7, rev `fa018898`). **Read-only source.**
Audit: `assets_source/reuse/melo/` — see `PROVENANCE.md` there.

Measured by instantiating every GLB in Blender, not from file names:

| | |
| --- | ---: |
| GLB files | 84 |
| triangles (visual, helper meshes excluded) | 274,950 |
| binary size | 17.4 MB |
| assets shipping a collision proxy that must be stripped | 21 |

| Asset | Godot stage | Art stage |
| --- | --- | --- |
| 19 approved GLBs in `assets_source/reuse/melo/source/` | **not imported** | staged, provenance recorded |
| `ring_device` / `shrine_device` / `altar_main` / `arch_frame` | not imported | **REUSE-A** (P-01) |
| `cre_ancient_sentinel` | not imported | **REUSE-A** (P-02) |
| `energy_core` / `ancient_terminal` / `pillar_broken` / `ruin_fragment_c` | not imported | **REUSE-A** (P-04) |
| `pillar_large` / `energy_door_frame` / `crystal_cluster_a` | not imported | **REUSE-A** (P-05) |

Ranking and per-asset reasons: `assets_source/reuse/melo/MELO_TOP_CANDIDATES.md`.
Five conversion proposals: `MELO_CONVERSION_PROPOSALS.md`.
Contact sheets: `assets_source/review/melo/SHEET_*.png` (6 sheets, 84 tiles).

> Nothing from MELO is `IN SCENE`. `assets_source/` is the ART source tree and no
> `.tscn` references it. Round 1 was an audit; conversion is round 2.
