# C2B-02 · First Person Hand / Forearm

Status: SPEC READY · Priority: P0

## Use

First-person male hand and forearm. Replaces the empty space where the sword currently floats.
Must be readable in four states: **Sword** (grip), **Block** (raised guard), **Cast** (open palm toward magic circle), **Iaido** (sheath grip and draw).

This asset is what makes the first-person view read as a real game rather than a floating weapon.

## Design

- Stylized next-generation fantasy. Same visual language as C2B-01 sword and the Mistvale kit.
- Young adult male hand, weathered but not old. Adventurer, not noble.
- Simple bracer or wrapped forearm band at the wrist; bare fingers.
- Skin and cloth must read at 0.3 m. No generic mannequin, no low-poly blob fingers.

## Dimensions

| Part | Metric |
| --- | --- |
| Hand length (wrist crease to fingertip) | 0.19 m |
| Palm width | 0.085 m |
| Forearm visible length | 0.30 m |
| Forearm radius at wrist | 0.048 m |

## Viewing distance

0.25 m to 0.9 m. Fingers are individually visible during the iaido hold.

## First-person / third-person

First-person only. Lives in the same foreground viewport as the sword.

## Poly budget

Under 9,000 triangles for hand + forearm. Spend triangles on knuckles and finger silhouette, not on the upper arm which is off-screen.

## Materials

Maximum 3 slots: skin, bracer/wrap (cloth or leather), optional metal buckle.
Procedural PBR only. No image textures, no external plugins.

## Animation needs

No rig, no armature. Rigid mesh; Godot drives transform.
Provide **four named pose variants as separate objects** in the same file (not four files):

- `FPHand_Sword` — closed grip, thumb over index, wrapped around a 0.03 m cylinder
- `FPHand_Block` — grip with forearm rotated to present the guard
- `FPHand_Cast` — open palm, fingers spread, facing forward
- `FPHand_Iaido` — sheath grip, thumb along the blade spine

Only one is visible at a time; Godot toggles visibility. This avoids rig work entirely and keeps the Combat MVP unblocked.

## Modularity

Separate named objects: `Forearm`, `Palm`, `Thumb`, `Index`, `Middle`, `Ring`, `Little`, `Bracer`.
Godot may later drive finger curl per-finger; name them so that is possible.

## Collision needs

None. Godot Area3D only.

## Transforms and origin — critical

- Origin at the **grip center**, the same point C2B-01 uses as its origin
- Open palm faces local -Z
- Forearm extends along local +Y (away from the grip, toward the elbow)
- Apply all transforms before export

## Godot usage

Godot 4.4.1. Parented under `WeaponRoot` next to the sword, in the foreground viewport.
The sword origin and hand origin must coincide so C2B-01 can be dropped in without re-alignment.

## Export

- GLB: `F:\SEKAI\assets\models\character\fp_hand.glb`
- Blend: `F:\SEKAI\assets_source\character\fp_hand.blend`
- Script: `F:\SEKAI\assets\chat2blender\fp_hand_<chunk>.py`

## Mandatory production route

ChatGPT Web → GPT-5.6 Sol → Blender Python → visible Blender → GLB → Godot first-person review.
The SEKAI agent must not author the Blender modeling script.

## Acceptance views

1. Grip pose with C2B-01 sword present: no interpenetration, knuckles visible.
2. Cast pose with magic circle active: palm faces the circle, not away.
3. Block pose: forearm and guard read as one defensive shape.
4. Iaido sheath grip: thumb position along the blade is unambiguous.
5. GLB in Godot at 0.3 m: skin does not look plastic, silhouette is not a mitten.
