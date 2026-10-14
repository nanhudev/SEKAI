# -*- coding: utf-8 -*-
"""
SEKAI / CHARACTER LINE — LIA V0 LANDMARK EXTRACTION
Derives body landmarks (chin, neck, shoulder, crotch, knee) from the raw cloud
with hair/limb-aware strips, because the source has no rig and no materials.

Run:
  "G:/blender.exe" -b --factory-startup --python tools/character/lia_landmarks.py -- \
      --fbx <path> --out <dir>
"""

import bpy
import os
import sys
from mathutils import Vector

argv = sys.argv
argv = argv[argv.index("--") + 1:] if "--" in argv else []
ARGS = {}
i = 0
while i < len(argv):
    if argv[i].startswith("--"):
        ARGS[argv[i][2:]] = argv[i + 1] if i + 1 < len(argv) else ""
        i += 2
    else:
        i += 1

FBX = os.path.abspath(ARGS.get("fbx"))
OUT = os.path.abspath(ARGS.get("out"))
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
bpy.ops.import_scene.fbx(filepath=FBX, use_custom_normals=True, global_scale=1.0)

obj = [o for o in bpy.data.objects if o.type == 'MESH'][0]
mw = obj.matrix_world
CO = [mw @ v.co for v in obj.data.vertices]

ZMIN = min(p.z for p in CO)
ZMAX = max(p.z for p in CO)
H = ZMAX - ZMIN
XC = 0.008          # measured symmetry plane
out = []


def w(s=""):
    out.append(str(s))


w("LIA V0 LANDMARKS   H=%.5f m  feet z=%.5f  top z=%.5f  symmetry plane x=%.3f" % (H, ZMIN, ZMAX, XC))
w()
w("== HEAD CENTRE STRIP (|x-0.008| < 0.045) : front Y = nose/chin silhouette ==")
w("   %-8s %-9s %-9s %-9s" % ("z(m)", "z/H", "front_y", "back_y"))
step = 0.002
z = ZMIN + H * 0.78
while z <= ZMAX:
    pts = [p for p in CO if abs(p.x - XC) < 0.045 and z <= p.z < z + step]
    if pts:
        fy = min(p.y for p in pts)
        by = max(p.y for p in pts)
        w("   %-8.4f %-9.3f %-9.4f %-9.4f" % (z, (z - ZMIN) / H, fy, by))
    z += step
w()

w("== HEAD CORE WIDTH (|y| < 0.07 around head) ==")
w("   %-8s %-9s %-9s %-9s" % ("z(m)", "z/H", "x_min", "x_max"))
z = ZMIN + H * 0.78
while z <= ZMAX:
    pts = [p for p in CO if -0.07 < p.y < 0.07 and z <= p.z < z + step]
    if pts:
        w("   %-8.4f %-9.3f %-9.4f %-9.4f" % (z, (z - ZMIN) / H,
                                              min(p.x for p in pts), max(p.x for p in pts)))
    z += step
w()

w("== TORSO / SHOULDER (|y| < 0.13, excludes arms/hair thrown back) ==")
w("   %-8s %-9s %-9s %-9s %-9s" % ("z(m)", "z/H", "x_min", "x_max", "width"))
z = ZMIN + H * 0.55
while z <= ZMIN + H * 0.95:
    pts = [p for p in CO if -0.13 < p.y < 0.13 and z <= p.z < z + 0.004]
    if pts:
        x0 = min(p.x for p in pts)
        x1 = max(p.x for p in pts)
        w("   %-8.4f %-9.3f %-9.4f %-9.4f %-9.4f" % (z, (z - ZMIN) / H, x0, x1, x1 - x0))
    z += 0.004
w()

w("== LEG SEPARATION (front view, X coverage per 4 mm row) ==")
w("   %-8s %-9s %-9s" % ("z(m)", "z/H", "X runs (metres)"))
z = ZMIN + H * 0.02
while z <= ZMIN + H * 0.50:
    xs = sorted(p.x for p in CO if z <= p.z < z + 0.004)
    if xs:
        runs = []
        s = xs[0]
        prev = xs[0]
        for x in xs[1:]:
            if x - prev > 0.012:
                runs.append((s, prev))
                s = x
            prev = x
        runs.append((s, prev))
        rs = "  ".join("[%.3f..%.3f w=%.3f]" % (a, b, b - a) for a, b in runs)
        w("   %-8.4f %-9.3f %s" % (z, (z - ZMIN) / H, rs))
    z += 0.004
w()

w("== ARM EXTENT (|x|>0.115, hand/glove region) ==")
w("   %-8s %-9s %-9s %-9s %-9s %-9s" % ("z(m)", "z/H", "x_min", "x_max", "y_min", "y_max"))
z = ZMIN + H * 0.38
while z <= ZMIN + H * 0.85:
    pts = [p for p in CO if abs(p.x - XC) > 0.115 and z <= p.z < z + 0.006]
    if pts:
        w("   %-8.4f %-9.3f %-9.4f %-9.4f %-9.4f %-9.4f" %
          (z, (z - ZMIN) / H, min(p.x for p in pts), max(p.x for p in pts),
           min(p.y for p in pts), max(p.y for p in pts)))
    z += 0.006

txt = os.path.join(OUT, "LIA_V0_landmarks.txt")
with open(txt, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
print("LANDMARKS_DONE " + txt)
