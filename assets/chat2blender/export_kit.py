"""Producer export step for ENV-01 Mistvale Ground / Stair / Terrace Kit.

Not modelling code: it saves the .blend source and writes ONE GLB PER PIECE,
named after the object. One GLB per piece is deliberate -- each piece then drops
into Godot as a single Mesh resource, which makes kitbashing a scene fast and
keeps instancing cheap.

Blend -> F:/SEKAI/assets_source/environment/mistvale/env01_ground_kit.blend
GLB   -> F:/SEKAI/assets/models/environment/mistvale/<ObjectName>.glb
"""

import bpy
import os

COLLECTION = "SEKAI_ENV01_KIT"
BLEND_PATH = "F:/SEKAI/assets_source/environment/mistvale/env01_ground_kit.blend"
GLB_DIR = "F:/SEKAI/assets/models/environment/mistvale"

os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
os.makedirs(GLB_DIR, exist_ok=True)

col = bpy.data.collections.get(COLLECTION)
if col is None:
    raise RuntimeError("collection %r not found in the scene" % COLLECTION)

# Review-only helpers must not end up in the shipped source file.
for name in ("ReviewCam", "ReviewKey", "Cube"):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        bpy.data.objects.remove(obj, do_unlink=True)

# Every piece must sit back on its own grid-centre origin.
for obj in col.objects:
    if obj.type == 'MESH':
        obj.location = (0.0, 0.0, 0.0)
        obj.rotation_euler = (0.0, 0.0, 0.0)
        obj.scale = (1.0, 1.0, 1.0)

pieces = sorted(o.name for o in col.objects if o.type == 'MESH')
if not pieces:
    raise RuntimeError("no mesh pieces inside collection %r" % COLLECTION)

bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
print("saved blend: %s (%d bytes)" % (BLEND_PATH, os.path.getsize(BLEND_PATH)))

total_tris = 0
total_bytes = 0
for name in pieces:
    obj = bpy.data.objects[name]
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    path = os.path.join(GLB_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )

    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    size = os.path.getsize(path)
    total_tris += tris
    total_bytes += size
    print("EXPORT %-34s tris=%-6d mats=%-2d %8d bytes" % (name, tris, len(obj.data.materials), size))

print("KIT EXPORT DONE | pieces=%d total_tris=%d total_bytes=%d" % (
    len(pieces), total_tris, total_bytes))
