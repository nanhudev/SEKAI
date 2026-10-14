"""LIA WEIGHT CLEANUP -- fix automatic-weight bleed on the single-shell mesh.

Why this exists
---------------
The working mesh is ONE connected shell (body + hair + clothes + boots welded
together).  Blender's heat-map automatic weights therefore give skirt panels
and clothing that hangs beside the arms to the forearm/hand bones, so raising
an arm inflates the skirt into a wing.

Measured on the rigged mesh (`lia_deform_probe.py`, pose arm_up):
  * 7050 verts move > 12 cm; 5457 of them sit > 7 cm away from the arm chain
  * the worst offenders sit at (-0.22, -0.14, 0.61) - skirt hem, front-right -
    and are driven by hand_r=0.67 / lowerarm_r=0.26

Rules applied
  1. d_arm > R_ARM           -> no arm influence at all (outside the arm volume)
  2. d_body + MARGIN < d_arm -> no arm influence (clearly a torso vertex)
  3. drop weights < MIN_W, clamp to <= MAX_INF influences, renormalise

IMPORTANT implementation note
  The first version of this script used `vertex_groups[i].remove(idx_list)` and
  then re-read `mesh.vertices[v].groups` in the next pass.  That silently kept
  the OLD values, so `rebuild()` wrote the stripped arm weights straight back.
  Everything here therefore goes through plain Python dicts: read once, mutate,
  clear the vertex groups, write back.  No dependance on Blender's MDeformVert
  cache at all.

Run:
  "/g/blender.exe" -b --factory-startup --python tools/character/lia_weight_cleanup.py \
      -- --blend <rigged.blend> --out-blend <out.blend> --out-json <out.json>
"""

import bpy
import sys
import os
import json
from mathutils import Vector

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
OUT_BLEND = os.path.abspath(ARGS["out-blend"])
OUT_JSON = os.path.abspath(ARGS["out-json"]) if ARGS.get("out-json") else ""
R_ARM = float(ARGS.get("r-arm", 0.070))
MARGIN = float(ARGS.get("margin", 0.045))
MAX_INF = int(ARGS.get("max-influences", 4))
MIN_W = float(ARGS.get("min-weight", 0.006))
SMOOTH = int(ARGS.get("smooth", 0))
SMOOTH_F = float(ARGS.get("smooth-factor", 0.5))


def log(msg):
    print("[LIA-WCLEAN] %s" % msg, flush=True)


# ---------------------------------------------------------------- load

bpy.ops.wm.open_mainfile(filepath=SRC)
rig = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
mesh = next((o for o in bpy.data.objects if o.type == "MESH"), None)
if rig is None or mesh is None:
    raise RuntimeError("need one armature + one mesh")
me = mesh.data
mw = mesh.matrix_world

SEG = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones}
ARM_PREFIX = ("clavicle_", "upperarm_", "lowerarm_", "hand_")
ARM_NAMES = [n for n in SEG if n.startswith(ARM_PREFIX)]
BODY_NAMES = [n for n in SEG if n not in ARM_NAMES and n != "root"]
ALL_DEFORM = ARM_NAMES + BODY_NAMES

log("rig=%s mesh=%s verts=%d groups=%d" % (
    rig.name, mesh.name, len(me.vertices), len(mesh.vertex_groups)))


def seg_dist(p, seg):
    a, b = seg
    ab = b - a
    l2 = ab.length_squared
    if l2 < 1e-12:
        return (p - a).length
    t = (p - a).dot(ab) / l2
    t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
    return (p - (a + ab * t)).length


def nearest(p, names):
    best, bd = None, 1e9
    for n in names:
        d = seg_dist(p, SEG[n])
        if d < bd:
            bd, best = d, n
    return best, bd


arm_segs = [SEG[n] for n in ARM_NAMES]
body_segs = [SEG[n] for n in BODY_NAMES]

# per-vertex geometry (constant across passes)
REST = [mw @ v.co for v in me.vertices]
N = len(REST)
D_ARM = [min(seg_dist(p, s) for s in arm_segs) for p in REST]
D_BODY = [min(seg_dist(p, s) for s in body_segs) for p in REST]
KEEP_ARM = [not (D_ARM[i] > R_ARM or D_BODY[i] + MARGIN < D_ARM[i]) for i in range(N)]
log("arm influence forbidden on %d / %d verts (%.1f%%)  [r_arm=%.3f margin=%.3f]"
    % (N - sum(KEEP_ARM), N, 100.0 * (N - sum(KEEP_ARM)) / N, R_ARM, MARGIN))


# ---------------------------------------------------------------- read

def read_weights():
    names = [vg.name for vg in mesh.vertex_groups]
    data = [dict() for _ in range(N)]
    for v in me.vertices:
        d = data[v.index]
        for g in v.groups:
            d[names[g.group]] = g.weight
    return names, data


# ---------------------------------------------------------------- process

def process(names, data):
    stats = {"stripped_verts": 0, "dropped_small": 0,
             "clamped": 0, "rescaled": 0, "orphans": 0}
    for i in range(N):
        d = data[i]

        if not KEEP_ARM[i]:
            before = len(d)
            for nm in ARM_NAMES:
                d.pop(nm, None)
            if len(d) != before:
                stats["stripped_verts"] += 1

        small = [nm for nm, w in d.items() if w < MIN_W]
        for nm in small:
            del d[nm]
        if small:
            stats["dropped_small"] += 1

        if not d:
            # orphan -> nearest bone on the correct chain
            pool = ARM_NAMES if D_ARM[i] < D_BODY[i] and KEEP_ARM[i] else BODY_NAMES
            d[nearest(REST[i], pool)[0]] = 1.0
            stats["orphans"] += 1
            continue

        if len(d) > MAX_INF:
            keep = sorted(d.items(), key=lambda t: -t[1])[:MAX_INF]
            d.clear()
            d.update(keep)
            stats["clamped"] += 1

        total = sum(d.values())
        if total > 0.0 and abs(total - 1.0) > 1e-5:
            for nm in d:
                d[nm] /= total
            stats["rescaled"] += 1
    return stats


# ---------------------------------------------------------------- write

def write_weights(names, data):
    mesh.vertex_groups.clear()
    vg = {nm: mesh.vertex_groups.new(name=nm) for nm in names}
    for i in range(N):
        for nm, w in data[i].items():
            vg[nm].add([i], w, "REPLACE")


# ---------------------------------------------------------------- run

names, data = read_weights()
stats1 = process(names, data)
write_weights(names, data)
log("pass 1: %s" % json.dumps(stats1))

if SMOOTH > 0:
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
    try:
        bpy.ops.object.vertex_group_smooth(
            group_select_mode="BONE_DEFORM", factor=SMOOTH_F, repeat=SMOOTH)
        log("vertex_group_smooth repeat=%d factor=%.2f" % (SMOOTH, SMOOTH_F))
    except Exception as exc:
        log("smooth failed: %s" % exc)
    bpy.ops.object.mode_set(mode="OBJECT")

    names, data = read_weights()
    stats2 = process(names, data)
    write_weights(names, data)
    log("pass 2 (post-smooth): %s" % json.dumps(stats2))
else:
    stats2 = {}

# ---------------------------------------------------------------- verify

names, data = read_weights()
counts = [len(d) for d in data]
counts.sort()
bad_arm = sum(1 for i in range(N)
              if (not KEEP_ARM[i]) and any(nm in data[i] and data[i][nm] > 0.005
                                           for nm in ARM_NAMES))
over = sum(1 for c in counts if c > MAX_INF)
unassigned = sum(1 for c in counts if c == 0)

report = {
    "source": SRC,
    "output_blend": OUT_BLEND,
    "r_arm": R_ARM,
    "margin": MARGIN,
    "max_influences": MAX_INF,
    "forbidden_arm_verts": N - sum(KEEP_ARM),
    "pass1": stats1,
    "pass2": stats2,
    "influences_median": counts[len(counts) // 2],
    "influences_p95": counts[int(len(counts) * 0.95)],
    "influences_max": counts[-1],
    "over_max": over,
    "unassigned_verts": unassigned,
    "forbidden_verts_still_armed": bad_arm,
}
log("VERIFY: %s" % json.dumps(report))

assert unassigned == 0, "unassigned vertices remain"
assert over == 0, "influence clamp failed"
assert bad_arm == 0, "arm influence still present on forbidden vertices"

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
if OUT_JSON:
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
log("saved %s" % OUT_BLEND)
log("WCLEAN_DONE")
