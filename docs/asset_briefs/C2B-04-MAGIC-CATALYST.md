# C2B-04 · Magic Catalyst

Status: SPEC READY · Priority: P1

## Use

First-person spellcasting focus for Fire / Frost / Wind. Replaces the empty space where the magic circle currently appears with no object.
Shown during cast startup, active channel, and release.

## Design — important constraint

**NOT a traditional large staff.** No tall wand, no orb on a stick, no fantasy scepter.

The catalyst is a compact hand-worn or forearm-mounted focus. Prefer one of:
- a bracer-mounted ring construct that unfolds slightly when channeling
- a compact grip-held focus, smaller than a dagger
- a wrist-mounted shard array that separates when active

It must not block the magic circle, which appears in front of the camera at roughly 0.7 m.
The catalyst frames the circle; it does not replace it.

Stylized next-generation fantasy, same ancient-civilization motif language as C2B-01 and C2B-03.

## Dimensions

| Part | Metric |
| --- | --- |
| Maximum extent (closed) | 0.16 m |
| Maximum extent (channeling) | 0.24 m |
| Worn diameter (bracer form) | 0.09 m |

Must stay inside the lower-center of the first-person frame. Nothing may cross screen center where the magic circle sits.

## Viewing distance

0.25 m to 0.7 m.

## First-person / third-person

First-person only.

## Poly budget

Under 7,000 triangles. This is a supporting prop; C2B-01 and C2B-02 carry more visual weight.

## Materials

Maximum 3 slots:
1. Warm metal frame
2. Stone or ceramic element
3. Emissive channel surface — must brighten per element (Fire / Frost / Wind)

Procedural PBR only. No image textures, no external plugins.

## Animation needs

No rig, no armature. Rigid mesh.
Provide **two named pose variants as separate objects** in the same file:
- `Catalyst_Closed` — resting state
- `Catalyst_Open` — channeling state, parts separated

Godot toggles visibility and drives a short transform. The emissive channel surface must be a separate named mesh (`Catalyst_Core`) so Godot can drive emission color per element.

## Element color language

Godot already uses these circle colors; the catalyst core must harmonize, not fight them:
- Fire `Color(1.0, 0.55, 0.20)`
- Wind `Color(0.75, 0.80, 0.80)`
- Frost `Color(0.55, 0.85, 1.00)`

## Modularity

Named objects: `Frame`, `Core`, and each separable element if the chosen design has them.

## Collision needs

None.

## Transforms and origin — critical

- Origin at the **wrist / grip point**, aligned to the same coordinate space as C2B-02 `FPHand_Cast`
- Channeling direction faces local -Z
- Apply all transforms before export

## Godot usage

Godot 4.4.1. Parented under `WeaponRoot` alongside C2B-02, in the foreground viewport.
Must not occlude `MagicCircle3D`, which is positioned fully inside the first-person view.

## Export

- GLB: `F:\SEKAI\assets\models\weapons\magic_catalyst.glb`
- Blend: `F:\SEKAI\assets_source\weapons\magic_catalyst.blend`
- Script: `F:\SEKAI\assets\chat2blender\magic_catalyst_<chunk>.py`

## Mandatory production route

ChatGPT Web → GPT-5.6 Sol → Blender Python → visible Blender → GLB → Godot first-person review.
The SEKAI agent must not author the Blender modeling script.

## Acceptance views

1. Closed pose at 0.3 m during idle movement: does not obstruct the view.
2. Open pose during cast: reads as activated, not just scaled up.
3. With magic circle active: catalyst frames it, never overlaps its center.
4. Core emission readable in all three element colors.
5. GLB in Godot: aligned to the hand, no clipping through camera near plane.
