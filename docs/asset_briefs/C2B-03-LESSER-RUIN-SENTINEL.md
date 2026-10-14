# C2B-03 · Lesser Ruin Sentinel

Status: SPEC READY · Priority: P0

## Use

The first real enemy. Replaces `technical_dummy`, the primitive test target currently in the combat sandbox.
This is the enemy the player learns Perfect Guard and Iaido against, so its telegraph must be readable at a glance.

## Design

- Stylized next-generation fantasy. Ancient civilization construct, not a zombie, not a golem made of rocks.
- Silhouette priority: **the player must distinguish idle / anticipation / active from shape alone**, before any color or VFX cue.
- Floating separated parts are acceptable and encouraged. The body does not need to be a single continuous mesh.
- Restrained ornament. Ancient motif language consistent with the sword guard (C2B-01) and World Beacon (C2B-05).
- NOT generic low-poly. NOT mobile-game toy style.

## Dimensions

| Part | Metric |
| --- | --- |
| Total height | 2.20 m |
| Shoulder width | 0.95 m |
| Eye / core height | 1.80 m |
| Arm reach (sweep) | 1.60 m |
| Hurtbox center height | 1.10 m |

Hurtbox in Godot is an Area3D; the mesh must sit inside a plausible body volume around 1.10 m center height.

## Viewing distance

1.5 m to 12 m. Readable at mid-combat distance, does not need extreme close-up detail.
It WILL be seen during the iaido world cut, where the screen splits — the silhouette must survive being cut in half.

## First-person / third-person

Seen from first-person. Player never sees it from a cinematic third-person camera during Combat MVP.

## Poly budget

Under 18,000 triangles. Floating parts can be individually low-poly.

## Materials

Maximum 4 slots:
1. Aged stone / ceramic body
2. Warm metal fittings
3. Emissive core (the telegraph surface — must be able to brighten)
4. Optional cloth remnant

Procedural PBR only. No image textures, no external plugins.

## Animation needs

**No rig. No armature. No skinning.**
Godot drives Node animation on separated parts. This is deliberate — rig must not block the Combat MVP.

Required named parts, each a separate object so Godot can animate them independently:

- `Torso`
- `Head`
- `Core` (the emissive telegraph surface)
- `ArmL` / `ArmR`
- `WeaponArm` (the arm that swings)
- `Base` (ground contact / hover element)

## Telegraph requirement — critical

The enemy has three attack patterns: **sweep**, **charged heavy**, **physical lunge**.
Each needs a distinct readable pose built from the parts above:

- Sweep: weapon arm winds to one side, core dim
- Charged heavy: parts pull inward and compress, core brightens steadily
- Lunge: parts spread and lean forward, core flares once

The `Core` object must be a separate named mesh so Godot can drive its emission independently of the body material.

## Modularity

Separate floating parts as listed. Godot will parent and animate them as nodes.

## Collision needs

None in Blender. Godot Area3D handles hitbox and hurtbox.

## Transforms and origin — critical

- Origin at the **feet / ground contact point**, centered horizontally
- Character faces local -Z
- Apply all transforms before export

## Godot usage

Godot 4.4.1. Replaces the primitive technical dummy in `CombatSandbox`.
Requires `Hurtbox` Area3D child added in Godot (not in Blender).

## Export

- GLB: `F:\SEKAI\assets\models\enemies\lesser_ruin_sentinel.glb`
- Blend: `F:\SEKAI\assets_source\enemies\lesser_ruin_sentinel.blend`
- Script: `F:\SEKAI\assets\chat2blender\ruin_sentinel_<chunk>.py`

## Mandatory production route

ChatGPT Web → GPT-5.6 Sol → Blender Python → visible Blender → GLB → Godot first-person review.
The SEKAI agent must not author the Blender modeling script.

## Acceptance views

1. Idle silhouette at 4 m: reads as a construct, not a pile of boxes.
2. Three telegraph poses at 3 m: distinguishable without color.
3. Core visible during charged heavy from first-person.
4. During iaido world cut: silhouette still reads when split.
5. GLB in Godot: correct 2.20 m height, no clipping into ground, hurtbox alignment.
