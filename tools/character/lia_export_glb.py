"""LIA EXPORT GLB -- export the rigged mesh for Godot 4.4.1.

Checks before/after so the export cannot silently drop the skeleton, the skin,
or the material.

Run:
  "/g/blender.exe" -b --factory-startup --python tools/character/lia_export_glb.py \
      -- --blend <rigged.blend> --out <dir> --name lia_v3
"""

import bpy
import sys
import os
import json

# ---------------------------------------------------------------- args


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    d = {}
    i = 0
    while i < len(argv):
        t = argv[i]
        if t.startswith("--"):
            k = t[2:]
            if i + 1 < len(argv) and not argv[i + 1].startswith("--"):
                d[k] = argv[i + 1]
                i += 2
            else:
                d[k] = True
                i += 1
        else:
            i += 1
    return d


ARGS = parse_args()
SRC = os.path.abspath(ARGS["blend"])
OUT_DIR = os.path.abspath(ARGS["out"])
NAME = ARGS.get("name", "lia")
WITH_ANIM = str(ARGS.get("animations", "0")) not in ("0", "false", "no")
os.makedirs(OUT_DIR, exist_ok=True)


def log(msg):
    print("[LIA-EXPORT] %s" % msg, flush=True)


bpy.ops.wm.open_mainfile(filepath=SRC)

rig = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
mesh = next((o for o in bpy.data.objects if o.type == "MESH"), None)
if rig is None or mesh is None:
    raise RuntimeError("need one armature + one mesh")

log("rig=%s bones=%d  mesh=%s verts=%d polys=%d" % (
    rig.name, len(rig.data.bones), mesh.name,
    len(mesh.data.vertices), len(mesh.data.polygons)))

# --- pre-flight ------------------------------------------------------------
probs = []
if len(mesh.data.uv_layers) == 0:
    probs.append("no UV layer")
if len(mesh.material_slots) == 0:
    probs.append("no material")
if not any(m.type == "ARMATURE" for m in mesh.modifiers):
    probs.append("mesh has no armature modifier")
if len(mesh.vertex_groups) == 0:
    probs.append("no vertex groups")
for b in rig.data.bones:
    if not b.use_deform:
        continue
    if b.name not in mesh.vertex_groups:
        probs.append("deform bone without a vertex group: %s" % b.name)
if probs:
    log("PRE-FLIGHT WARNINGS: %s" % "; ".join(probs))
else:
    log("pre-flight ok")

# --- scene hygiene ---------------------------------------------------------
# only the rig + its mesh should reach the exporter
for o in list(bpy.data.objects):
    if o not in (rig, mesh):
        bpy.data.objects.remove(o, do_unlink=True)

# object transforms must be identity or the GLB gets a bogus root offset
for o in (rig, mesh):
    if tuple(o.location) != (0.0, 0.0, 0.0) or tuple(o.scale) != (1.0, 1.0, 1.0):
        log("WARNING %s has a non-identity transform %s / %s"
            % (o.name, tuple(o.location), tuple(o.scale)))

bpy.ops.object.select_all(action="DESELECT")
mesh.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig

path = os.path.join(OUT_DIR, "%s.glb" % NAME)
export_kwargs = dict(
    filepath=path,
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_apply=False,
    export_skins=True,
    export_def_bones=False,
    export_morph=False,
    export_animations=WITH_ANIM,
    export_materials="EXPORT",
    export_normals=True,
    export_texcoords=True,
    export_tangents=False,
    export_extras=False,
)
if WITH_ANIM:
    export_kwargs.update(
        export_animation_mode="ACTIONS",
        export_frame_range=False,
        export_force_sampling=True,
        export_optimize_animation_size=False,
        export_bake_animation=False,
    )
try:
    bpy.ops.export_scene.gltf(**export_kwargs)
except TypeError as exc:
    log("exporter rejected some animation kwargs (%s) - retrying minimal" % exc)
    for k in ("export_animation_mode", "export_frame_range", "export_force_sampling",
              "export_optimize_animation_size", "export_bake_animation"):
        export_kwargs.pop(k, None)
    bpy.ops.export_scene.gltf(**export_kwargs)
log("wrote %s (%.2f MB)" % (path, os.path.getsize(path) / 1048576.0))

# --- verify the result -----------------------------------------------------
import struct
with open(path, "rb") as f:
    magic, ver, length = struct.unpack("<III", f.read(12))
    clen, ctype = struct.unpack("<II", f.read(8))
    js = json.loads(f.read(clen).decode("utf-8"))

report = {
    "file": path,
    "size_bytes": os.path.getsize(path),
    "gltf_version": ver,
    "meshes": len(js.get("meshes", [])),
    "nodes": len(js.get("nodes", [])),
    "skins": len(js.get("skins", [])),
    "materials": len(js.get("materials", [])),
    "animations": len(js.get("animations", [])),
    "joints": len(js["skins"][0]["joints"]) if js.get("skins") else 0,
    "mesh_primitives": len(js["meshes"][0]["primitives"]) if js.get("meshes") else 0,
    "has_JOINTS_0": False,
    "has_WEIGHTS_0": False,
    "has_TEXCOORD_0": False,
    "has_NORMAL": False,
}
if js.get("meshes"):
    attrs = js["meshes"][0]["primitives"][0].get("attributes", {})
    report["has_JOINTS_0"] = "JOINTS_0" in attrs
    report["has_WEIGHTS_0"] = "WEIGHTS_0" in attrs
    report["has_TEXCOORD_0"] = "TEXCOORD_0" in attrs
    report["has_NORMAL"] = "NORMAL" in attrs
    report["vertex_attributes"] = sorted(attrs.keys())

log("GLB CONTENT: %s" % json.dumps(report, indent=2))

assert report["skins"] == 1, "expected exactly one skin"
assert report["joints"] > 0, "skin has no joints"
assert report["has_JOINTS_0"] and report["has_WEIGHTS_0"], "skin data missing from mesh"
assert report["has_NORMAL"], "normals missing"
assert report["materials"] >= 1, "no material in export"

with open(os.path.join(OUT_DIR, "%s_glb_report.json" % NAME), "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2, ensure_ascii=False)

log("EXPORT_DONE")
