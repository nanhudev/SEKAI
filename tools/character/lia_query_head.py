# -*- coding: utf-8 -*-
"""LIA V0 — targeted head landmark queries. Read-only.
   "G:/blender.exe" -b --factory-startup --python tools/character/lia_query_head.py -- --fbx <path>
"""
import bpy, os, sys
from mathutils import Vector

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

bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
bpy.ops.import_scene.fbx(filepath=FBX, use_custom_normals=True, global_scale=1.0)
obj = [o for o in bpy.data.objects if o.type == 'MESH'][0]
mw = obj.matrix_world
CO = [mw @ v.co for v in obj.data.vertices]
XC = 0.008
print("=== head landmark queries ===")
print("z-band      npts  |x-XC|max   y_min    y_max   xmin     xmax   note")

bands = [
    (0.930, 0.938, "above-lip"),
    (0.938, 0.948, "nose?"),
    (0.948, 0.960, "lips/chin?"),
    (0.960, 0.974, "chin/neck?"),
    (0.974, 0.990, "neck?"),
    (0.990, 1.005, "jaw/ear?"),
    (1.005, 1.020, "eye/cheek"),
    (1.020, 1.035, "brow"),
    (1.035, 1.050, "forehead/crown"),
    (1.050, 1.062, "crown?"),
    (1.062, 1.074, "ponytail base"),
    (1.074, 1.090, "ponytail"),
    (1.090, 1.106, "ponytail"),
    (1.106, 1.123, "ponytail tip"),
]
for lo, hi, note in bands:
    pts = [p for p in CO if lo <= p.z < hi]
    if not pts:
        print("  %.3f-%.3f  (none)" % (lo, hi))
        continue
    # front-most surface (min y) - report the x spread of the front 15% of points
    ys = sorted(p.y for p in pts)
    cut = ys[int(len(ys) * 0.10)]
    front = [p for p in pts if p.y <= cut]
    fx = [abs(p.x - XC) for p in front]
    print("  %.3f-%.3f %5d  front15%%: |x|max=%.4f  ymin=%.4f   all: y=%.4f..%.4f  x=%.4f..%.4f  %s"
          % (lo, hi, len(pts), max(fx) if fx else 0, min(ys), min(ys), max(ys),
             min(p.x for p in pts), max(p.x for p in pts), note))

print()
print("=== sagittal column probe: |x-XC| < 0.012 (true centre line) ===")
pts = [p for p in CO if abs(p.x - XC) < 0.012 and p.z > 0.86]
zs = sorted(set(round(p.z, 3) for p in pts))
for z in zs:
    band = [p for p in pts if abs(p.z - z) < 0.0015]
    if band:
        print("  z=%.3f  y_min=%.4f  y_max=%.4f  n=%d" %
              (z, min(p.y for p in band), max(p.y for p in band), len(band)))
print("QUERY_DONE")
