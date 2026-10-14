# Read-only audit of the UE5 Mistvale export.
#
# Answers, with numbers: how many objects the FBX really carries, how many
# triangles, what world box they occupy in Blender's Y-up space, and whether any
# texture came along. The point is to decide the Godot pipeline on evidence -- a
# 3.3 MB FBX could be the whole town or a review subset, and those two need
# completely different next steps.
#
# Run:  "/g/blender.exe" -b --factory-startup --python audit_export.py -- <fbx> <out.json>

import bpy
import json
import sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
fbx_path, out_path = argv[0], argv[1]

# --factory-startup is NOT an empty scene: it ships a cube, a light and a
# camera. Leaving them in would put the default 2 m cube inside every bbox and
# every triangle count. This bug already cost this project a round of
# mis-measured calibration cards, so it is cleared explicitly and asserted on.
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
assert len(bpy.data.objects) == 0, "scene was not empty before import"

# BLENDER 5.1 IMPORT REGRESSION. io_scene_fbx blen_read_light ends with
#
#     if hasattr(lamp, "cycles"):
#         lamp.cycles.cast_shadow = lamp.use_shadow
#
# The guard is insufficient: the RNA struct exists, the property does not, so
# every import of an FBX containing a light node dies with
# "'CyclesLightSettings' object has no attribute 'cast_shadow'" -- and the
# operator aborts the WHOLE file, not just the light. The UE level export
# carries the level's lights, so without this shim nothing imports at all.
#
# The lamp datablock is already created by the time the failing line runs, so
# swallowing the AttributeError and returning None yields "this node has no
# Blender data" -- which is what a light is anyway. Lights are then dropped,
# which is also what we want: UE's sun and sky have no business in the Godot
# scene, which brings its own.
import io_scene_fbx.import_fbx as _imp  # noqa: E402

_original_read_light = _imp.blen_read_light


def _read_light_tolerating_cycles_regression(fbx_tmpl, fbx_obj, settings):
    try:
        return _original_read_light(fbx_tmpl, fbx_obj, settings)
    except AttributeError:
        return None


_imp.blen_read_light = _read_light_tolerating_cycles_regression

bpy.ops.import_scene.fbx(filepath=fbx_path)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
empties = [o for o in bpy.data.objects if o.type != "MESH"]

verts = 0
tris = 0
per_object = []
lo = Vector((1e18, 1e18, 1e18))
hi = Vector((-1e18, -1e18, -1e18))

for ob in meshes:
    me = ob.data
    verts += len(me.vertices)
    me.calc_loop_triangles()
    t = len(me.loop_triangles)
    tris += t
    omn = Vector((1e18,) * 3)
    omx = Vector((-1e18,) * 3)
    for corner in ob.bound_box:
        w = ob.matrix_world @ Vector(corner)
        for i in range(3):
            lo[i] = min(lo[i], w[i])
            hi[i] = max(hi[i], w[i])
            omn[i] = min(omn[i], w[i])
            omx[i] = max(omx[i], w[i])
    per_object.append({
        "name": ob.name,
        "verts": len(me.vertices),
        "tris": t,
        "min": [round(v, 3) for v in omn],
        "max": [round(v, 3) for v in omx],
        "materials": [s.material.name for s in ob.material_slots if s.material],
    })

materials = sorted({m for o in meshes for s in o.material_slots if s.material
                    for m in [s.material.name]})
images = sorted(i.name for i in bpy.data.images)

report = {
    "source": fbx_path,
    "mesh_objects": len(meshes),
    "non_mesh_objects": len(empties),
    "non_mesh_names": sorted(o.name for o in empties)[:20],
    "verts": verts,
    "tris": tris,
    "bbox_min": [round(v, 3) for v in lo],
    "bbox_max": [round(v, 3) for v in hi],
    "size": [round(hi[i] - lo[i], 3) for i in range(3)],
    "materials": len(materials),
    "material_names": materials[:60],
    "images": len(images),
    "image_names": images[:60],
    "objects": sorted(per_object, key=lambda r: -r["tris"]),
}

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=1)

print("AUDIT mesh_objects=%d tris=%d size=%s materials=%d images=%d"
      % (len(meshes), tris, report["size"], len(materials), len(images)))
print("AUDIT bbox_min=%s bbox_max=%s" % (report["bbox_min"], report["bbox_max"]))
print("AUDIT images=%s" % (images[:10],))
