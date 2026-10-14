# -*- coding: utf-8 -*-
"""
SEKAI / CHARACTER LINE — LIA V1 BASE
Mechanical, reversible normalisation of the source FBX into a working .blend.
Does NOT touch topology, UVs, materials or normals — those are later phases.

  * world transform baked (FBX -90deg X rotation applied to mesh data)
  * mirror plane moved to x = 0
  * object origin at the ground point under the mirror plane (feet centre)
  * optional uniform scale (--scale), used once the stature is locked
  * saves .blend + writes a verification JSON

Run:
  "G:/blender.exe" -b --factory-startup --python tools/character/lia_make_base.py -- \
      --fbx <src.fbx> --out-blend <dst.blend> --out-json <dst.json> [--scale 1.508]
"""

import bpy
import json
import os
import sys
from mathutils import Matrix, Vector, kdtree

argv = sys.argv
argv = argv[argv.index("--") + 1:] if "--" in argv else []
A = {}
i = 0
while i < len(argv):
    if argv[i].startswith("--"):
        A[argv[i][2:]] = argv[i + 1] if i + 1 < len(argv) else ""
        i += 2
    else:
        i += 1

FBX = os.path.abspath(A["fbx"])
OUT_BLEND = os.path.abspath(A["out-blend"])
OUT_JSON = os.path.abspath(A["out-json"])
SCALE = float(A.get("scale", 1.0))
SYM = A.get("symmetry", "auto")

os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
def log(m):
    print("[LIA-BASE] " + str(m), flush=True)


bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
bpy.ops.import_scene.fbx(filepath=FBX, use_custom_normals=True, global_scale=1.0)

obj = [o for o in bpy.data.objects if o.type == 'MESH'][0]
log("source object %s verts=%d faces=%d" % (obj.name, len(obj.data.vertices), len(obj.data.polygons)))

me = obj.data
M = obj.matrix_world.copy()
log("source matrix row0=%s row1=%s" % ([round(v, 5) for v in M[0]], [round(v, 5) for v in M[1]]))

# -- 1. bake world transform into mesh data
me.transform(M)
obj.matrix_world = Matrix.Identity(4)

CO = [v.co.copy() for v in me.vertices]
zmin0 = min(p.z for p in CO)

# -- 2. mirror plane: robust least-squares scan over the lower body (symmetric in source)
low = [p for p in CO if p.z < zmin0 + 0.35]
if SYM == "auto":
    sub = low[::5]
    kdt = kdtree.KDTree(len(sub))
    for i, p in enumerate(sub):
        kdt.insert(p, i)
    kdt.balance()
    best = None
    for k in range(-80, 81):
        cand = 0.004 + k * 0.0005          # +-20 mm around the coarse guess
        acc = 0.0
        for p in sub:
            _, _, d = kdt.find(Vector((2 * cand - p.x, p.y, p.z)))
            acc += d * d
        rms = (acc / len(sub)) ** 0.5
        if best is None or rms < best[1]:
            best = (cand, rms)
    plane_x = best[0]
    log("mirror plane scan: x=%.5f rms=%.5f m over %d lower-body verts" % (best[0], best[1], len(sub)))
else:
    plane_x = float(SYM)
log("mirror plane x = %.5f" % plane_x)

# -- 3. uniform scale + translate so mirror plane -> x=0 and feet -> z=0 (origin at feet centre)
me.transform(Matrix.Scale(SCALE, 4))
me.transform(Matrix.Translation(Vector((-plane_x * SCALE, 0.0, -zmin0 * SCALE))))
me.update()

# -- 4. verify
CO2 = [v.co.copy() for v in me.vertices]
mn = Vector((min(p.x for p in CO2), min(p.y for p in CO2), min(p.z for p in CO2)))
mx = Vector((max(p.x for p in CO2), max(p.y for p in CO2), max(p.z for p in CO2)))
size = mx - mn
low2 = [p for p in CO2 if p.z < size.z * (0.35 / 1.12229)][::5]   # same band as the scan
kdt2 = kdtree.KDTree(len(low2))
for i_, p_ in enumerate(low2):
    kdt2.insert(p_, i_)
kdt2.balance()
_acc = 0.0
for p_ in low2:
    _, _, d_ = kdt2.find(Vector((-p_.x, p_.y, p_.z)))
    _acc += d_ * d_
sym_rms_after = (_acc / len(low2)) ** 0.5
plane_after = sym_rms_after

stats = {
    "source_fbx": FBX,
    "scale_applied": SCALE,
    "mesh_name": obj.name,
    "verts": len(me.vertices),
    "faces": len(me.polygons),
    "uv_layers": len(me.uv_layers),
    "materials": len(me.materials),
    "bbox_min": [round(v, 5) for v in mn],
    "bbox_max": [round(v, 5) for v in mx],
    "size": [round(v, 5) for v in size],
    "crown_z_m": round(mx.z, 5),
    "lower_body_mirror_rms_about_x0_m": round(sym_rms_after, 6),
    "matrix_is_identity": all(abs(obj.matrix_world[r][c] - (1.0 if r == c else 0.0)) < 1e-6
                              for r in range(4) for c in range(4)),
    "custom_normals_present": bool(me.has_custom_normals),
    "note": "V1 BASE = transform baked + mirror plane at x=0 + origin at feet centre. "
            "Topology / UV / material / normals UNCHANGED.",
}
log("bbox %s .. %s  size %s" % (stats["bbox_min"], stats["bbox_max"], stats["size"]))
log("crown z = %.4f m" % mx.z)
log("lower-body mirror rms about x=0 after shift = %.5f m (mesh edge median 0.00238)" % sym_rms_after)

with open(OUT_JSON, "w", encoding="utf-8") as f:
    json.dump(stats, f, indent=2, ensure_ascii=False)

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
log("saved " + OUT_BLEND)
print("BASE_DONE")
