# UE5 VFX LAB — pipeline rule and current state

**Status of this document:** pipeline authority. Any line that works on VFX reads
this before it starts.

---

## 1. What UE5 is, and what it is not

**Godot remains the SEKAI runtime.** UE5 is not a new main engine and it is not a
migration target. It is a **VFX prototyping / simulation / baking tool**.

UE5 is responsible for:

```
Niagara · Chaos Fracture · Material VFX prototyping · Flipbook · Distortion
Noise / Mask · Particle motion · Mesh FX · VFX reference
```

Everything produced there has to come back to Godot to be implemented and
accepted. Nothing from the lab ships inside a UE runtime, and MAIN must not
introduce an Unreal runtime dependency.

---

## 2. Who owns what

| Line | Owns |
| --- | --- |
| **ART** | UE5 VFX Lab production, export, the Godot rebuild, the Training Ground VFX Stage |
| **COMBAT** | may raise `COMBAT-VFX REQUEST` (attack readability, magic behaviour, hit reaction, shatter, wind force, chain momentum) — but never changes combat logic for a VFX |
| **IAIDO / SKILL** | first-priority consumer: Reality Glass, Reality Cut support, Blue Void, fracture, shards, distortion, collapse |
| **AUDIO** | reads the final **Godot** timeline. Never write to UE preview timing |
| **NARRATIVE** | UE5 does not change the world. Accepted gameplay/VFX may become world expression; prototype VFX is not automatically canon |
| **MAIN** | final integration. Every UE output goes: export → Godot implementation → Training Ground test → runtime validation |

**Chat2Blender still owns models. UE5 owns effects. The two lines do not mix.**

---

## 3. Shared status vocabulary

```
UE PROTOTYPE · UE VISUALLY VERIFIED · EXPORTED · GODOT REBUILT · INTEGRATED · IN-GAME VERIFIED
```

"UE5 里效果做好了" is not SEKAI done. Only `IN-GAME VERIFIED` is.

---

## 4. Current priority

1. **Iaido Reality Glass** ← already past EXPORTED, see §5
2. Blue Void
3. Frost / Shatter
4. Wind
5. Fire
6. Chain VFX (after the chain prototype is approved)

---

## 5. The lab as it actually exists (measured, not assumed)

- **Engine:** `/f/UE_5.8/` (`UnrealEditor.exe`)
- **Project:** `F:/SEKAI/ue5_lab/RealityGlass_Lab/RealityGlass_Lab.uproject`
  — engine association `SEKAI_UE58`; plugins: GeometryScripting,
  PythonScriptPlugin, EditorScriptingUtilities, ChaosSolverPlugin, Fracture,
  ModelingToolsEditorMode, Niagara
- **Method:** headless commandlet, not hand-driving the editor —
  `UnrealEditor-Cmd.exe -run=pythonscript -script=<file>`; a run takes ~4.4 s and
  reports `Success - 0 error(s), 0 warning(s)`
- **Scripts:** `ue5_lab/scripts/build_reality_fracture.py` (30 KB, the producer)
  plus `probe_api*.py` (API discovery, kept as a record of what worked)
- **Exports:** `ue5_lab/exports/`

### Reality Glass — artefact list

| Artefact | Measured |
| --- | --- |
| `fracture.obj` / `.json` | **202 Voronoi cells**, 769 tris, 1,173 verts, 769 polygroups |
| `shards.obj` / `.json` | **18 shards**, 58 tris, 94 verts |
| cut plane | angle **−30°**, normal (0.5, 0.866), half-extent 1.15, aspect 16:9 |
| `mask_crack.png`, `mask_edge.png`, `mask_flow.png`, `mask_fracture.png`, `mask_shardid.png` | 1024 × 576 |
| `lab_reference_fracture.png`, `lab_reference_shards.png` | review renders |

`shards.json` carries, **per shard**, its polygon, area, centroid and
`dist_to_cut`. That last field is the useful one for Godot: it gives the shard
spawn/emission order for free, so the Godot rebuild does not have to re-derive
"which piece comes off first" from geometry.

### ⛔ P0 GAP — the crack mask has no topology (2026-09-28)

`reality_crack_mask.png` was inspected directly at 1024 × 576. It is a
**uniform 202-cell Voronoi net**: even density corner to corner, no primary
line, no branch hierarchy, no long cracks and no short ones. `fracture_build.log`
confirms the generator agrees — `sites: 202`, `coarse sites: 18`, no cut-weighted
pass and no branch pass in the log.

The Godot side has been made as robust as it can be against this (the reveal is
now staggered by a region threshold, and the front genuinely travels — see
`godot/vfx/iaido_fracture_field.gdshaderinc`), so the net reads as damage
growing out of the wound rather than as a texture switched on. **But a uniform
net cannot be revealed into a hierarchy it does not contain.** §12–14 of the
Reality Crack brief ask for a primary cut with 4–8 main branches, uneven
lengths and angles, some stopping abruptly, some re-branching — and that has to
be baked, because it is geometry, not shading.

**The bake has to become layered.** In priority order:

| Layer | What it is | Where it goes |
| --- | --- | --- |
| **P0 primary** | The blade's own diagonal (angle −30°, through `cut_center`) drawn as a continuous, slightly wandering line across the whole plane. This is the one line that is allowed to be continuous. | `crack_mask.r` at high value; also its own `mask_primary.png` |
| **P0 branches** | **4–8 main branches** leaving the primary at real angles. Uneven lengths. Some terminate abruptly, some fork once. | `crack_mask.r` |
| **P0 secondaries** | Shorter cracks that appear near the branches only. Localised spidering, never full-frame. | `crack_mask.r` |
| **P0 density** | Site density must follow distance from the primary: fine within ~120 px, decaying outward so the corners are **sparse**, not merely coarse. The current bake has cut weighting but it is far too weak to read. | the Voronoi site seeding |
| **P0 edge breakup** | The lip must not be a ruled edge — a ragged perimeter mask for `edge_mask.png`. | `edge_mask.png` |
| **P1 shards** | **10–18 hero shards**, cut along the primary and the main branches so their boundaries coincide with real cracks instead of crossing them. | `shards.json` |
| **P1 debris** | Micro debris / dust / sparkle. **After** the above; the brief explicitly files this at P1. | separate export, not in `crack_mask` |

**Acceptance:** a still of `reality_crack_mask.png` must be readable as
"a thing was cut" with the primary line and its branches evident **without**
knowing which side the blade entered. If it reads as a tile of a Voronoi
pattern, it has failed regardless of how it animates.

The generator to change is `ue5_lab/scripts/build_reality_fracture.py`; the
run is the usual headless commandlet (**re-bake the *layers*, not the whole
scene**). Status of this item: `REQUESTED`, blocking §12–14 of the Reality
Crack pass. Godot must keep working with the current mask until the new one
lands — do not block the runtime on it.

### Where this sits in the vocabulary

**`EXPORTED`.** The pipeline works end to end — content was authored in UE, baked
headless, exported and consumed by both Godot shaders. What has **not** passed is
`UE VISUALLY VERIFIED` for the crack mask, for the reason in the P0 section
above: the artefact renders, and it is the wrong artefact. `GODOT REBUILT` has
not started.

### The Godot rebuild (next, ART)

The gap is well-defined because the exports are plain `obj` + `json` + `png`:
the shard polygons and `dist_to_cut` port directly, and the masks are the same
masks the existing `godot/vfx/iaido_glass_shard.gdshader` and
`iaido_world_split.gdshader` want. The rebuild lands on the Training Ground's
**VFX Stage (zone E)**, which exists precisely so this can be looked at on a
neutral floor with a reference grid.

---

## 6. Why the VFX Stage is part of the Training Ground

A screen-space effect cannot be accepted from a still frame — refraction only
changes what is already there, so a static image cannot show whether it is
working. And an effect on an empty floor cannot be judged either, because there
is no silhouette for a cut to separate. The VFX Stage therefore provides a
neutral deck, a mid-grey backdrop, a ground grid for motion reference, and a
fixed `CaptureAnchor_VFX` so two shots of the same effect are comparable.
