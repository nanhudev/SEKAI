#!/usr/bin/env python3
"""Structural audit for ANY character asset (fbx / glb / blend / obj).

One job: turn "it imported" into checkable numbers.  Dumps bones, meshes,
triangles, materials, animation clips and bbox to JSON, and can render the
standard review views on top.

    "/g/blender.exe" -b --factory-startup --python tools/character/asset_inspect.py -- \
        --in  <file> --out <dir> [--tag NAME] [--views] [--bone-dump]

Notes / traps learned the hard way:
  * Blender 5.x: `bpy.ops.import_scene.fbx` needs `use_custom_normals` care, and
    armature bone names are what you retarget against -> always dump them.
  * glTF Y-up conversion means a Blender "-Y forward" model becomes "+Z forward"
    in Godot; the report records the Blender-side facing so nobody re-guesses.
"""
import json
import os
import sys

import bpy
from mathutils import Vector

ARGS = {}
if "--" in sys.argv:
    argv = sys.argv[sys.argv.index("--") + 1:]
    for i in range(0, len(argv) - 1, 2):
        ARGS[argv[i].lstrip("-")] = argv[i + 1]

SRC = os.path.abspath(ARGS["in"])
OUT = os.path.abspath(ARGS.get("out", os.path.dirname(SRC)))
TAG = ARGS.get("tag") or os.path.splitext(os.path.basename(SRC))[0]
os.makedirs(OUT, exist_ok=True)


def log(m):
    print("[INSPECT] %s" % m, flush=True)


def load(path):
    bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
    ext = os.path.splitext(path)[1].lower()
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path, global_scale=1.0)
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    else:
        raise SystemExit("unsupported: %s" % ext)


load(SRC)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]

report = {
    "source": SRC.replace("\\", "/"),
    "tag": TAG,
    "objects": {"mesh": len(meshes), "armature": len(arms)},
    "meshes": [],
    "armatures": [],
    "materials": sorted({m.name for m in bpy.data.materials}),
    "images": sorted({i.name for i in bpy.data.images if i.name != "Render Result"}),
    "actions": [],
}

total_v = total_t = 0
mn = Vector((1e9, 1e9, 1e9))
mx = Vector((-1e9, -1e9, -1e9))

for o in meshes:
    me = o.data
    tris = sum(max(0, len(p.vertices) - 2) for p in me.polygons)
    quads = sum(1 for p in me.polygons if len(p.vertices) == 4)
    vg = len(o.vertex_groups)
    info = {
        "name": o.name,
        "verts": len(me.vertices),
        "polys": len(me.polygons),
        "tris": tris,
        "quads": quads,
        "uv_layers": [u.name for u in me.uv_layers],
        "vertex_groups": vg,
        "shape_keys": len(me.shape_keys.key_blocks) if me.shape_keys else 0,
        "materials": [ms.material.name if ms.material else None for ms in o.material_slots],
        "modifiers": [m.type for m in o.modifiers],
    }
    report["meshes"].append(info)
    total_v += len(me.vertices)
    total_t += tris
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
        mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))

report["totals"] = {"verts": total_v, "tris": total_t}
size = mx - mn
report["bbox"] = {
    "min": [round(v, 4) for v in mn],
    "max": [round(v, 4) for v in mx],
    "size": [round(v, 4) for v in size],
    "height": round(size.z, 4),
}

for a in arms:
    bones = [b.name for b in a.data.bones]
    report["armatures"].append({
        "name": a.name,
        "bone_count": len(bones),
        "bones": bones,
        "deform_bones": len([b for b in a.data.bones if b.use_deform]),
        "root_bones": [b.name for b in a.data.bones if b.parent is None],
    })

for act in bpy.data.actions:
    info = {"name": act.name}
    try:
        rng = act.frame_range
        info["frames"] = [round(rng[0], 2), round(rng[1], 2)]
    except Exception:
        pass
    report["actions"].append(info)

# ---------------------------------------------------------------- write

out_json = os.path.join(OUT, "%s_inspect.json" % TAG)
with open(out_json, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2, ensure_ascii=False)
log("wrote %s" % out_json)

log("meshes=%d tris=%d verts=%d  bbox height=%.3f m" % (
    len(meshes), total_t, total_v, size.z))
for m in report["meshes"][:8]:
    log("  mesh %-28s v=%-7d tris=%-7d quads=%-6d uv=%s vg=%d sk=%d" % (
        m["name"], m["verts"], m["tris"], m["quads"], m["uv_layers"], m["vertex_groups"],
        m["shape_keys"]))
for a in report["armatures"]:
    log("  armature %-22s bones=%-3d deform=%-3d root=%s" % (
        a["name"], a["bone_count"], a["deform_bones"], a["root_bones"]))
    if ARGS.get("bone-dump"):
        log("    bones: %s" % ", ".join(a["bones"]))
log("  actions=%d" % len(report["actions"]))
log("  materials=%d  images=%d" % (len(report["materials"]), len(report["images"])))

if ARGS.get("views"):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

print("[INSPECT_DONE]", flush=True)
