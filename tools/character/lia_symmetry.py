# -*- coding: utf-8 -*-
"""LIA V0 — regional mirror-symmetry audit (decides if mirrored weighting is viable).
   "G:/blender.exe" -b --factory-startup --python tools/character/lia_symmetry.py -- --fbx <path> --out <dir>
"""
import bpy, json, math, os, sys
from mathutils import Vector, kdtree

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
OUT = os.path.abspath(A.get("out", "."))

bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
bpy.ops.import_scene.fbx(filepath=FBX, use_custom_normals=True, global_scale=1.0)
obj = [o for o in bpy.data.objects if o.type == 'MESH'][0]
mw = obj.matrix_world
CO = [mw @ v.co for v in obj.data.vertices]
ZMIN = min(p.z for p in CO)
H = max(p.z for p in CO) - ZMIN
XC = 0.008

kdt = kdtree.KDTree(len(CO))
for i, p in enumerate(CO):
    kdt.insert(p, i)
kdt.balance()

REGIONS = [
    ("boots/feet      ", 0.00, 0.20, None),
    ("lower legs      ", 0.20, 0.34, None),
    ("knees           ", 0.30, 0.40, None),
    ("thighs          ", 0.36, 0.50, None),
    ("hips/skirt      ", 0.50, 0.60, None),
    ("waist           ", 0.56, 0.62, None),
    ("chest/bust      ", 0.60, 0.70, None),
    ("shoulders/arms  ", 0.66, 0.80, None),
    ("shoulders-core  ", 0.66, 0.80, 0.115),   # |x-XC| < 0.115 : body core only
    ("arms            ", 0.70, 0.80, -0.115),  # |x-XC| > 0.115 : limb only
    ("hands           ", 0.42, 0.56, -0.115),
    ("neck            ", 0.78, 0.84, 0.06),
    ("head            ", 0.80, 0.96, None),
    ("head (skull)    ", 0.84, 0.96, 0.075),
]

rows = []
for name, fl, fh, xf in REGIONS:
    lo = ZMIN + H * fl
    hi = ZMIN + H * fh
    errs = []
    for i, p in enumerate(CO):
        if not (lo <= p.z < hi):
            continue
        d = abs(p.x - XC)
        if xf is not None:
            if xf >= 0 and d >= xf:
                continue
            if xf < 0 and d <= -xf:
                continue
        m = Vector((2 * XC - p.x, p.y, p.z))
        _, _, dist = kdt.find(m)
        errs.append(dist)
    if not errs:
        continue
    errs.sort()
    rms = math.sqrt(sum(e * e for e in errs) / len(errs))
    rows.append({
        "region": name.strip(),
        "verts": len(errs),
        "rms_mm": round(rms * 1000, 2),
        "p50_mm": round(errs[len(errs) // 2] * 1000, 2),
        "p95_mm": round(errs[int(len(errs) * 0.95)] * 1000, 2),
        "max_mm": round(errs[-1] * 1000, 2),
    })

print("=== LIA V0 REGIONAL SYMMETRY (mirror plane x=%.3f) ===" % XC)
print("  median mesh edge = 2.38 mm   ->  rms ~<3 mm means symmetric")
print("  %-17s %-8s %-9s %-9s %-9s %-9s" % ("region", "verts", "rms_mm", "p50_mm", "p95_mm", "max_mm"))
for r in rows:
    verdict = "SYMMETRIC" if r["rms_mm"] < 6 else ("LOOSE" if r["rms_mm"] < 15 else "ASYMMETRIC")
    print("  %-17s %-8d %-9.2f %-9.2f %-9.2f %-9.2f  %s" %
          (r["region"], r["verts"], r["rms_mm"], r["p50_mm"], r["p95_mm"], r["max_mm"], verdict))

with open(os.path.join(OUT, "LIA_V0_symmetry.json"), "w", encoding="utf-8") as f:
    json.dump({"mirror_plane_x": XC, "rows": rows}, f, indent=2)
print("SYMMETRY_DONE")
