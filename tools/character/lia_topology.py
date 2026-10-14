# -*- coding: utf-8 -*-
"""
SEKAI / CHARACTER LINE — LIA V0 TOPOLOGY + PROPORTION ANALYSIS
Read-only. Produces machine-measured landmarks and surface-noise metrics.

Run:
  "G:/blender.exe" -b --factory-startup --python tools/character/lia_topology.py -- \
      --fbx <path.fbx> --out <dir>
"""

import bpy
import bmesh
import json
import math
import os
import sys
from mathutils import Vector, kdtree

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
meta = json.loads(ARGS.get("meta", "{}"))


def log(m):
    print("[LIA-TOPO] " + str(m), flush=True)


bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
bpy.ops.import_scene.fbx(filepath=FBX, use_custom_normals=True, global_scale=1.0)

obj = [o for o in bpy.data.objects if o.type == 'MESH'][0]
me = obj.data
mw = obj.matrix_world
log("object %s  verts=%d  matrix=%s" % (obj.name, len(me.vertices), [round(x, 4) for x in sum([list(r) for r in mw], [])]))

co = [mw @ v.co for v in me.vertices]

bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
bm.edges.ensure_lookup_table()
bm.faces.ensure_lookup_table()

R = {}

# ---------------------------------------------------------------- edge length stats
elens = [e.calc_length() for e in bm.edges]
elens_sorted = sorted(elens)
n = len(elens_sorted)


def pct(p):
    return elens_sorted[min(n - 1, int(p * n))]


R["edge_length_m"] = {
    "min": round(elens_sorted[0], 6),
    "p01": round(pct(0.01), 6),
    "p10": round(pct(0.10), 6),
    "median": round(pct(0.50), 6),
    "p90": round(pct(0.90), 6),
    "p99": round(pct(0.99), 6),
    "max": round(elens_sorted[-1], 6),
    "mean": round(sum(elens_sorted) / n, 6),
    "edges_under_2mm": round(sum(1 for e in elens_sorted if e < 0.002) / n, 4),
    "edges_under_5mm": round(sum(1 for e in elens_sorted if e < 0.005) / n, 4),
}

# ---------------------------------------------------------------- face quality
thin = 0
sliver = 0
areas = []
for f in bm.faces:
    a = f.calc_area()
    areas.append(a)
    # aspect ratio proxy: longest edge^2 / area
    le = max(e.calc_length() for e in f.edges)
    if a > 1e-12:
        if (le * le) / a > 40:
            thin += 1
    if a < 1e-9:
        sliver += 1
R["face_quality"] = {
    "faces": len(areas),
    "sliver_faces": sliver,
    "thin_faces_aspect_gt40": thin,
    "thin_faces_pct": round(thin / max(1, len(areas)), 4),
}

# ---------------------------------------------------------------- connected components (shells)
seen = set()
comps = []
bm.verts.ensure_lookup_table()
for v in bm.verts:
    if v.index in seen:
        continue
    stack = [v]
    seen.add(v.index)
    idx = []
    while stack:
        cur = stack.pop()
        idx.append(cur.index)
        for e in cur.link_edges:
            o = e.other_vert(cur)
            if o.index not in seen:
                seen.add(o.index)
                stack.append(o)
    comps.append(idx)

comp_report = []
for idxs in comps:
    pts = [co[i] for i in idxs]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    c = sum(pts, Vector()) / len(pts)
    fcount = 0
    comp_report.append({
        "verts": len(idxs),
        "bbox_min": [round(v, 4) for v in mn],
        "bbox_max": [round(v, 4) for v in mx],
        "size": [round(v, 4) for v in (mx - mn)],
        "centroid": [round(v, 4) for v in c],
        "z_range_frac": [round((mn.z - min(p.z for p in co)) / (max(p.z for p in co) - min(p.z for p in co)), 4),
                         round((mx.z - min(p.z for p in co)) / (max(p.z for p in co) - min(p.z for p in co)), 4)],
    })
comp_report.sort(key=lambda r: -r["verts"])
R["shells"] = {"count": len(comp_report), "top": comp_report[:40]}
log("shells = %d" % len(comp_report))

zmin = min(p.z for p in co)
zmax = max(p.z for p in co)
H = zmax - zmin

# ---------------------------------------------------------------- z-slice profile
SLICES = 120
prof = []
for s in range(SLICES):
    z0 = zmin + H * s / SLICES
    z1 = zmin + H * (s + 1) / SLICES
    pts = [p for p in co if z0 <= p.z < z1]
    if not pts:
        prof.append(None)
        continue
    xs = [p.x for p in pts]
    ys = [p.y for p in pts]
    prof.append({
        "z": round((z0 + z1) * 0.5 - zmin, 4),
        "frac": round(((z0 + z1) * 0.5 - zmin) / H, 4),
        "n": len(pts),
        "x": [round(min(xs), 4), round(max(xs), 4)],
        "xw": round(max(xs) - min(xs), 4),
        "y": [round(min(ys), 4), round(max(ys), 4)],
        "yw": round(max(ys) - min(ys), 4),
    })
R["z_profile"] = prof

# ---------------------------------------------------------------- symmetry
kdt = kdtree.KDTree(len(co))
for i, p in enumerate(co):
    kdt.insert(p, i)
kdt.balance()

best = None
for x0 in [round(x * 0.002, 3) for x in range(-60, 61)]:
    errs = []
    for i, p in enumerate(co):
        if i % 7:
            continue
        m = Vector((2 * x0 - p.x, p.y, p.z))
        _, _, d = kdt.find(m)
        errs.append(d)
    rms = math.sqrt(sum(d * d for d in errs) / len(errs))
    if best is None or rms < best[1]:
        best = (x0, rms, max(errs))
R["symmetry"] = {
    "best_x_plane": best[0],
    "rms_m": round(best[1], 5),
    "worst_m": round(best[2], 5),
    "note": "rms of nearest-vertex distance between mesh and its mirror across X=x0. "
            "An ideal symmetric model gives rms ~ median edge length.",
    "median_edge_for_reference": R["edge_length_m"]["median"],
}

# ---------------------------------------------------------------- landmark search
def slice_span(frac_lo, frac_hi):
    pts = [p for p in co if zmin + H * frac_lo <= p.z <= zmin + H * frac_hi]
    if not pts:
        return None
    return {
        "xw": round(max(p.x for p in pts) - min(p.x for p in pts), 4),
        "yw": round(max(p.y for p in pts) - min(p.y for p in pts), 4),
    }


R["landmark_hints"] = {
    "feet_z": round(zmin, 4),
    "top_z": round(zmax, 4),
    "total_h_m": round(H, 5),
    "note": "read z_profile: neck = local minimum of xw in 0.78-0.92; shoulder = first steep xw rise below neck; waist = local min xw in 0.55-0.65; crotch = yw/lower-body split",
}

# ---------------------------------------------------------------- output
with open(os.path.join(OUT, "LIA_V0_TOPOLOGY.json"), "w", encoding="utf-8") as f:
    json.dump(R, f, indent=2, ensure_ascii=False)

with open(os.path.join(OUT, "LIA_V0_TOPOLOGY_raw.txt"), "w", encoding="utf-8") as f:
    def w(s=""):
        f.write(str(s) + "\n")
    w("LIA V0 TOPOLOGY / PROPORTION  (blender %s)" % bpy.app.version_string)
    w("object=%s verts=%d faces=%d" % (obj.name, len(me.vertices), len(me.polygons)))
    w("world matrix:")
    for row in mw:
        w("   " + "  ".join("%9.5f" % v for v in row))
    w()
    w("== EDGE LENGTH (m) ==")
    for k, v in R["edge_length_m"].items():
        w("  %-20s %s" % (k, v))
    w()
    w("== FACE QUALITY ==")
    for k, v in R["face_quality"].items():
        w("  %-22s %s" % (k, v))
    w()
    w("== SYMMETRY ==")
    for k, v in R["symmetry"].items():
        w("  %-26s %s" % (k, v))
    w()
    w("== SHELLS (%d) ==" % len(comp_report))
    for i, c in enumerate(comp_report[:60]):
        w("  #%-3d verts=%-7d z%%=%.2f-%.2f  size=%s centroid=%s" %
          (i, c["verts"], c["z_range_frac"][0], c["z_range_frac"][1], c["size"], c["centroid"]))
    w()
    w("== Z PROFILE (frac from feet, widths in m) ==")
    w("  %-7s %-7s %-8s %-16s %-16s" % ("z", "frac", "nverts", "x[min,max]", "y[min,max]"))
    for p in prof:
        if p is None:
            continue
        w("  %-7.4f %-7.4f %-8d %-16s %-16s  xw=%.4f yw=%.4f" %
          (p["z"], p["frac"], p["n"], p["x"], p["y"], p["xw"], p["yw"]))

print("TOPO_DONE")
