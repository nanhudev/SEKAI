# MELO — PROVENANCE

Everything under `assets_source/reuse/melo/` came from a pre-existing project on
this machine. This file exists so that, later, it is always possible to tell
whether a SEKAI asset was **generated** or **recovered from MELO**.

## Source project

| field | value |
| --- | --- |
| project name | `Melo: Light Rhythm Prototype` |
| path | `C:/Users/Administrator/Desktop/项目_开发与研究/Melo-Godot-Prototype` |
| engine config | Godot `4.7`, `Forward Plus` |
| main scene | `res://scenes/vertical_slice/scn_melo_showcase_vertical_slice.tscn` |
| revision marker | `G5_SYNC_REV.txt` = `fa018898b68707a445c8af34b1c7d90a342f33e5` |
| owner | the user (own work, not third-party) |
| Godot project files | 84 GLB, 21 `.blend`, 101 PNG |

## Access policy during this audit

MELO is a **read-only source**. Round 1 did not modify, move, rename or delete a
single file inside the MELO project. The only writes were:

* reads of GLB / `.tres` / `.gdshader` / `.json` / `.tscn` / `.md` content;
* writes under `F:/SEKAI/...` (review images, audit JSON, these documents);
* copies of 19 specifically approved GLBs into `source/` (see `manifest.json`).

## Why provenance is recorded even though MELO is the user's own work

Because the two lines must never be confused later. A recovered asset carries
constraints a generated one does not: a different engine version, a different
material system, a different art brief, and a silhouette that was designed to be
read as a flying hero at 5.6 m camera distance. When someone in three months asks
"why does this pillar have this proportion", the answer has to be findable.

## Engine version note

MELO targets **Godot 4.7**. SEKAI targets **Godot 4.4.1**. Nothing in this audit
was imported into the SEKAI project, so no version conflict exists yet. It is
recorded because a `.tscn` or `.tres` copied verbatim from MELO carries
`format=3` and may use properties that do not exist in 4.4.1. The 19 staged files
are **GLB only** — GLB is engine-version-neutral, which is why it is the only
format staged.

## Staging convention

```
assets_source/reuse/melo/
  PROVENANCE.md                  this file
  MELO_ASSET_INVENTORY.md        all 84 GLB measured
  MELO_TOP_CANDIDATES.md         the 17 worth continuing with
  MELO_CONVERSION_PROPOSALS.md   five SEKAification proposals
  manifest.json                  machine-readable record of the staged copies
  source/                        the 19 approved GLBs, original names kept
```

`source/` is **not** a Godot resource directory. It sits under `assets_source/`,
which is the ART line's source tree, and is not referenced by any `.tscn`. Nothing
here is `IN GODOT`; see the status vocabulary in `docs/ASSET_MANIFEST.md`.
