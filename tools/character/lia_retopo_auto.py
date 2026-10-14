# -*- coding: utf-8 -*-
"""
SEKAI / CHARACTER LINE — AUTOMATIC RETOPOLOGY PASS (PHASE 02, path B)

Pipeline: source mesh -> (optional) collapse pre-decimate -> QuadriFlow remesh
          -> optional light relax -> save .blend + stats JSON + before/after renders.

QuadriFlow runs with mesh symmetry DISABLED by default on purpose: Lia's hair mass
and the shoulder cape are deliberately asymmetric, and QuadriFlow's symmetry
constraint would force a symmetric compromise and mangle both.

Run:
  "G:/blender.exe" -b --factory-startup --python tools/character/lia_retopo_auto.py -- \
      --blend <in.blend> --out-blend <out.blend> --out-json <out.json> \
      --pre-ratio 0.15 --target-faces 24000 [--symmetry] [--preserve-sharp]
"""

import bpy
import bmesh
import json
import os
import sys
import time

argv = sys.argv
argv = argv[argv.index("--") + 1:] if "--" in argv else []
A = {}
i = 0
while i < len(argv):
    if argv[i].startswith("--"):
        nxt = argv[i + 1] if i + 1 < len(argv) else ""
        A[argv[i][2:]] = nxt
        i += 2
    else:
        i += 1


def flag(name):
    return name in A and A[name] not in ("", "0", "false", "False")


BLEND = os.path.abspath(A["blend"])
OUT_BLEND = os.path.abspath(A["out-blend"])
OUT_JSON = os.path.abspath(A["out-json"])
PRE = float(A.get("pre-ratio", 0.0))
TARGET = int(A.get("target-faces", 24000))
SYM = flag("symmetry")
SHARP = flag("preserve-sharp")
os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)


def log(m):
    print("[LIA-RETOPO] " + str(m), flush=True)


def counts(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    t = q = n = 0
    for f in bm.faces:
        k = len(f.verts)
        if k == 3:
            t += 1
        elif k == 4:
            q += 1
        else:
            n += 1
    elens = sorted(e.calc_length() for e in bm.edges)
    bm.free()
    med = elens[len(elens) // 2] if elens else 0.0
    return {"verts": len(obj.data.vertices), "faces": len(obj.data.polygons),
            "tris": t, "quads": q, "ngons": n,
            "quad_pct": round(100.0 * q / max(1, len(obj.data.polygons)), 2),
            "median_edge_mm": round(med * 1000, 3)}


bpy.ops.wm.open_mainfile(filepath=BLEND)
obj = [o for o in bpy.data.objects if o.type == 'MESH'][0]
for o in bpy.data.objects:
    o.select_set(o is obj)
bpy.context.view_layer.objects.active = obj

stats = {"input_blend": BLEND, "input": counts(obj), "pre_ratio": PRE,
         "target_faces": TARGET, "use_mesh_symmetry": SYM, "preserve_sharp": SHARP}
log("input %s" % stats["input"])

# ---------------------------------------------------------------- 1. pre decimate
t0 = time.time()
if 0.0 < PRE < 1.0:
    m = obj.modifiers.new("PREDEC", 'DECIMATE')
    m.decimate_type = 'COLLAPSE'
    m.ratio = PRE
    bpy.ops.object.modifier_apply(modifier=m.name)
    stats["after_predecimate"] = counts(obj)
    log("pre-decimate ratio %.3f -> %s  (%.1fs)" % (PRE, stats["after_predecimate"], time.time() - t0))

# ---------------------------------------------------------------- 2. quadriflow
t1 = time.time()
try:
    bpy.ops.object.quadriflow_remesh(use_mesh_symmetry=SYM,
                                     use_preserve_sharp=SHARP,
                                     use_preserve_boundary=False,
                                     preserve_attributes=False,
                                     smooth_normals=True,
                                     mode='FACES',
                                     target_faces=TARGET,
                                     seed=0)
    ok = True
except Exception as e:
    ok = False
    stats["quadriflow_error"] = repr(e)
    log("quadriflow FAILED: %r" % (e,))
stats["quadriflow_ok"] = ok
stats["quadriflow_seconds"] = round(time.time() - t1, 1)
stats["output"] = counts(obj)
log("quadriflow %.1fs -> %s" % (stats["quadriflow_seconds"], stats["output"]))

# ---------------------------------------------------------------- 3. cleanup
bm = bmesh.new()
bm.from_mesh(obj.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bm.to_mesh(obj.data)
bm.free()
obj.data.update()
stats["after_remove_doubles"] = counts(obj)

# ---------------------------------------------------------------- 4. verify
CO = [v.co.copy() for v in obj.data.vertices]
mn = [min(p[k] for p in CO) for k in range(3)]
mx = [max(p[k] for p in CO) for k in range(3)]
stats["bbox_min"] = [round(v, 5) for v in mn]
stats["bbox_max"] = [round(v, 5) for v in mx]
stats["size"] = [round(mx[k] - mn[k], 5) for k in range(3)]
stats["shading"] = "smooth" if all(p.use_smooth for p in obj.data.polygons[:50]) else "mixed"
log("bbox %s .. %s" % (stats["bbox_min"], stats["bbox_max"]))

with open(OUT_JSON, "w", encoding="utf-8") as f:
    json.dump(stats, f, indent=2, ensure_ascii=False)

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
log("saved " + OUT_BLEND)
print("RETOPO_DONE")
