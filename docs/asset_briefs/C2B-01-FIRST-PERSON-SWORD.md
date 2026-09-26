# C2B-01 · First Person Sword production brief

Status: asset specification only. No Blender script or model has been generated.

## Use

First-person sword for SEKAI Combat MVP. It must read clearly during a fast diagonal cut, reverse cut, forward finishing strike, block, and iaido draw. The current Godot primitive Hitbox is temporary and may stay during integration.

## Design

- Stylized next-generation fantasy; clean and sharp, with an original silhouette and restrained ornament.
- Human one-handed sword, total length about 1.05 m: blade about 0.78 m, grip about 0.22 m, compact guard.
- No oversized fantasy proportions, large jewels, broad glowing strips, or decorative shapes that obscure the blade direction.
- The blade should have a readable cutting edge and spine in first-person close view. Small ancient-civilization motifs may sit at the guard and fuller.
- Material groups: steel blade, dark wrapped grip, muted warm-metal fittings, optional subtle emissive inlay. Prefer no more than four materials.

## Technical handoff

- Real-world meter scale; origin at grip center, blade extends along local +Y, cutting edge faces local -X.
- Separate named objects for blade, guard, grip, pommel, and optional sheath. A sheath is helpful for iaido but can be a separate later asset.
- Apply transforms, preserve consistent normals, UVs, PBR materials, and clean object names.
- Keep triangle count appropriate for first-person real-time display; target under 12k triangles for sword alone.
- Export GLB with stable object transforms. Provide blade tip, hilt, and cutting-edge attachment references for trails and collision alignment.
- Collision uses Godot Area3D active frames; Blender mesh should not contain gameplay collision logic.

## Mandatory production route

Workspace ChatGPT web → GPT-5.6 Sol produces Blender Python → visible Blender execution and visual review → GLB export → visible Godot review. The SEKAI agent must not author the Blender modeling script.

## Acceptance views

1. Neutral grip against a mid-tone background, first-person distance.
2. Blade viewed edge-on and broadside; cutting direction unambiguous.
3. Guard and hand clearance during block and iaido pose.
4. GLB in Godot with plausible size, material response, and no clipping through camera.
