# C2B-05 · Iaido First-Person Scabbard (鞘 / saya) production brief

Status: **asset specification only.** No Blender script or model has been generated.
Issued by: MAIN (combat runtime). Owner of the generated asset: ART.
Requests the amendment of: nothing. This brief supersedes the procedural stand-in
`C2B_IAIDO_SCABBARD_STANDIN` currently living in `godot/scenes/player/Player.tscn`
+ `godot/scripts/combat/iaido_scabbard_rig.gd`.

---

## 1. Why this asset exists

聚合斩 / Iaido is the signature skill of 藏锋流. Its whole second half is
**the blade going home**. At the moment the ceremony is the only thing on screen,
so the player is staring at the hip for four continuous seconds.

The current placeholder is a rectangular box. It has no mouth, no wall thickness,
no interior, and no end. Two consequences, both fatal:

* the blade cannot be seen to *enter* anything — it slides into a solid slab and
  is switched off with a `visible = false`, which reads as a bug;
* the object the entire anticipation phase converges on (the sheath mouth) does
  not exist as a thing, so there is nothing for the player to look at.

This asset is therefore not decoration. It is the **destination** of the skill.

## 2. Non-negotiable: this is a separate object from the sword

The sword (`C2B-01`) and the scabbard are two independent objects with their own
transforms. They must never be animated as a pair, never parented to each other,
and never be exported as one mesh. The runtime drives them separately and relies
on **real spatial relations + depth occlusion** for the insertion to read.

Specifically the runtime needs the scabbard to be a **closed, opaque tube** so
that the portion of the blade inside it is hidden by the scabbard's own walls.
Do not model an open-frame or wireframe saya. Do not model the saya as a
half-shell for "visibility".

## 3. Design

- Stylized next-gen fantasy, same weapon language as `C2B-01 First Person Sword`.
  The two will be on screen together for four seconds; if the fittings, metal
  tone, and formality do not match, the pair reads as two different games.
- **Body:** deep wood or deep lacquer, near-black with a restrained warm
  undertone. Satin, not gloss — a mirror saya under the arena lighting produces a
  long specular streak that pulls the eye away from the mouth.
- **Fittings (金具):** muted dark gold or blackened iron only. A `koiguchi`
  (mouth collar), a `kurikata` (cord knob) on the outward-facing side, and a
  `kojiri` (end cap). Restrained, small, functional.
- **Sageo** (cord): a simple flat braided cord through the kurikata. One short
  hanging loop is enough. No tassel, no knot sculpture.
- **Explicitly rejected:** bright decoration, printed patterns, inlaid gold
  dragons, mother-of-pearl, oversized tsuba-like collars, glossy black plastic,
  tourist-trinket saya. If it looks like a souvenir-shop katana, it is wrong.
- Edge-up wear (the katana convention). The cutting edge lies toward the
  `-X` side of the scabbard exactly as it does on the sword.

### The mouth is the hero detail

The `koiguchi` is where the player's eye will be parked for several seconds.
It must have **real wall thickness and a real recessed interior**:

* an outer rim with a visible thickness (roughly 3–6 mm at this scale);
* a recessed inner lip that steps down into the bore, so the mouth reads as a
  hole with depth rather than as a dark decal;
* the bore itself visible for at least the first 40–60 mm;
* a slight asymmetric wear/bevel where the blade has been drawn across it
  thousands of times. Subtle. One soft chamfer, not a chip.

## 4. Technical handoff — the mechanical interface

This section is a contract. The runtime aligns to these numbers; do not change
them without telling MAIN.

```
Origin        : the CENTRE of the koiguchi mouth plane.
                (NOT the middle of the whole object, NOT the kojiri.)
Local +Y      : points from the mouth DOWN THE BORE, toward the kojiri.
                i.e. +Y is the direction the blade travels when it enters.
Local -X      : the side the cutting edge faces when seated.
                (Same convention as C2B-01.)
Local +Z      : the outward-facing side of the body (where the kurikata sits).
Real metres   : 1 unit = 1 metre. Verify with an empty before export.
```

Required critical measurements (metres):

| Part | Value | Note |
| --- | --- | --- |
| **Inner bore depth** (origin → inner end) | **≥ 1.00** | the blade seats to local y = 0.995 |
| **Bore cross-section at the mouth** | **0.092 × 0.055** (X × Z) | must clear the 0.075 × 0.038 blade |
| **Outer cross-section at the mouth** | **0.115 × 0.078** | gives the wall its thickness |
| **Overall external length** (origin → kojiri) | **≈ 1.02** | |
| Taper | ≈ 0.88 of mouth size at the kojiri | a real saya tapers; a parallel tube reads as a pipe |
| Wall thickness at the mouth | 0.010–0.014 | below this the mouth has no thickness on screen |

Tolerances: the bore must **never** be narrower than 0.085 × 0.048 anywhere along
its length, or the blade will visibly intersect the wall during the insert.

Named objects required (separate, not merged):

```
Koiguchi_Mouth      the collar + the visible mouth ring
Saya_Body           the lacquered tube
Kojiri              the end cap
Kurikata            the cord knob
Sageo               the cord
```

Materials: **maximum 4.** Suggest `Saya_Lacquer`, `Fitting_Metal`,
`Sageo_Cord`, and optionally `Bore_Interior` (a separate darker, non-reflective
material for the inside of the tube). The bore interior matters: if it shares the
body material it will catch the same specular highlight at the mouth and the hole
will look filled.

Normals: outward on the outside, **inward on the bore**. Do not flip the bore to
face outward "for visibility" — the runtime renders the scabbard double-sided
precisely so the mouth reads as a hole, and outward bore normals will break it.

## 5. Constraints

- Triangle budget: **under 6,000 triangles** for the whole scabbard. Almost all of
  it should be in the mouth and the kurikata; the tube itself can be very low.
- No gameplay collision geometry in the mesh. The runtime uses its own Area3D.
- No animation. No shape keys. Static mesh only.
- Keep the object's bounding box honest — the runtime uses it for the foreground
  weapon viewport's near-plane check.
- Export GLB with applied transforms and stable object names.

## 6. Mandatory production route

Workspace ChatGPT web → GPT-5.6 Sol produces Blender Python → **visible** Blender
execution and visual review → GLB export → visible Godot review.
The SEKAI agent must not author the Blender modelling script.

Complex geometry must be emitted as incremental runnable chunks:

```
# C2B:CHUNK saya_blockout
...
# C2B:END
```

Each chunk must run standalone. Budget 2–3 major iterations.

## 7. Acceptance views

1. **Mouth macro**, straight down the bore from just outside, first-person
   distance. Wall thickness and the recessed lip must be unambiguous.
2. **Side-on**, whole scabbard, showing the taper and the fitting placement.
3. **Edge-on**, confirming the kurikata sits on +Z and the edge side is `-X`.
4. **Empty-verify**: an empty scaled to the bore's cross-section passes through
   the tube end to end without intersecting a wall.
5. **In Godot, first-person, left-hip anchor**: the blade inserts and is hidden by
   the body; at the seated pose only guard + grip are outside the mouth.
6. **Pair check**: sword and scabbard side by side against a mid-tone background.
   If they do not read as the same weapon family, reject and redo.

## 8. Drop-in point

When the GLB lands, MAIN replaces the stand-in:

- scene node: `CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/SheathAnchor`
  → child node `CeremonyScabbard`, which must keep **identity transform** and its
  origin at the koiguchi mouth;
- GLB goes to `godot/models/weapons/iaido_scabbard.glb`;
- `.blend` source to `assets_source/weapons/iaido_scabbard.blend`;
- record in `docs/ASSET_MANIFEST.md` and `docs/CHAT2BLENDER_LOG.md`.

The stand-in is built to these exact numbers, so the swap is geometry-only and
requires no runtime change.
