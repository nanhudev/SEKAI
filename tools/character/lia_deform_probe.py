"""LIA DEFORM PROBE -- find out WHY a pose drags the wrong geometry.

Poses the rig, evaluates the deformed mesh, and reports which vertices moved
the most together with their rest position, their distance to the arm bone
chain, and which bone groups actually drive them.  This turns "the skirt blows
up when I raise my arm" into a concrete list of weights to fix.

Run:
  "/g/blender.exe" -b --factory-startup --python tools/character/lia_deform_probe.py \
      -- --blend <rigged.blend> --pose arm_up --out <report.txt>
"""

import bpy
import sys
import os
import math
from mathutils import Vector, Quaternion

POSE = {
    "arm_up": [("upperarm_l", "Y", -80), ("upperarm_r", "Y", 80)],
    "arm_fwd": [("upperarm_l", "X", -75), ("upperarm_r", "X", -75)],
    "crouch": [("thigh_l", "X", -80), ("thigh_r", "X", -80),
               ("calf_l", "X", 115), ("calf_r", "X", 115)],
}


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
POSE_NAME = ARGS.get("pose", "arm_up")
OUT = os.path.abspath(ARGS["out"]) if ARGS.get("out") else ""
MOVE_MIN = float(ARGS.get("min-move", 0.12))
ARM_PREFIX = ("clavicle_", "upperarm_", "lowerarm_", "hand_")


def log(msg):
    print("[LIA-PROBE] %s" % msg, flush=True)


bpy.ops.wm.open_mainfile(filepath=SRC)
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.data.objects if o.type == "MESH")
me = mesh.data
mw = mesh.matrix_world

SEG = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones}
ARM = [n for n in SEG if n.startswith(ARM_PREFIX)]
BODY = [n for n in SEG if n not in ARM and n != "root"]


def seg_dist(p, seg):
    a, b = seg
    ab = b - a
    l2 = ab.length_squared
    if l2 < 1e-12:
        return (p - a).length
    t = max(0.0, min(1.0, (p - a).dot(ab) / l2))
    return (p - (a + ab * t)).length


rest = [mw @ v.co for v in me.vertices]
gname = {vg.index: vg.name for vg in mesh.vertex_groups}
d_arm = [min(seg_dist(p, SEG[n]) for n in ARM) for p in rest]
d_body = [min(seg_dist(p, SEG[n]) for n in BODY) for p in rest]

# snapshot weights on the REST mesh
weights = []
for v in me.vertices:
    pairs = sorted(((gname[g.group], g.weight) for g in v.groups if g.weight > 0.01),
                   key=lambda t: -t[1])
    weights.append(pairs)

# --- pose
for pb in rig.pose.bones:
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = Quaternion((1, 0, 0, 0))


def rotate_world(pb, axis_name, deg):
    axis = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}[axis_name]
    m = pb.bone.matrix_local.to_3x3()
    q = Quaternion((m.inverted() @ axis).normalized(), math.radians(deg))
    pb.rotation_quaternion = pb.rotation_quaternion @ q


for bone, axis, deg in POSE[POSE_NAME]:
    rotate_world(rig.pose.bones[bone], axis, deg)
bpy.context.view_layer.update()

dg = bpy.context.evaluated_depsgraph_get()
ev = mesh.evaluated_get(dg)
dm = ev.to_mesh()
posed = [mw @ v.co for v in dm.vertices]
ev.to_mesh_clear()

moved = [(i, (posed[i] - rest[i]).length) for i in range(len(rest))
         if (posed[i] - rest[i]).length > MOVE_MIN]
moved.sort(key=lambda t: -t[1])

lines = []
lines.append("pose=%s  moved>%.3fm : %d / %d verts (%.1f%%)" %
             (POSE_NAME, MOVE_MIN, len(moved), len(rest),
              100.0 * len(moved) / len(rest)))

# cluster the movers by their dominant bone group
from collections import Counter
dom = Counter()
for i, _d in moved:
    dom[weights[i][0][0] if weights[i] else "<none>"] += 1
lines.append("")
lines.append("dominant weight group of the movers:")
for name, c in dom.most_common(12):
    lines.append("   %-16s %5d" % (name, c))

# arm-driven movers that sit far from the arm bone chain = the bug
suspects = [i for i, _d in moved if d_arm[i] > 0.07]
lines.append("")
lines.append("SUSPECTS (moved far AND >7cm from the arm chain): %d" % len(suspects))
if suspects:
    zs = [rest[i].z for i in suspects]
    xs = [abs(rest[i].x) for i in suspects]
    ys = [abs(rest[i].y) for i in suspects]
    da = [d_arm[i] for i in suspects]
    lines.append("   rest z   : min %.3f  max %.3f  median %.3f" %
                 (min(zs), max(zs), sorted(zs)[len(zs) // 2]))
    lines.append("   rest |x| : min %.3f  max %.3f  median %.3f" %
                 (min(xs), max(xs), sorted(xs)[len(xs) // 2]))
    lines.append("   rest |y| : min %.3f  max %.3f  median %.3f" %
                 (min(ys), max(ys), sorted(ys)[len(ys) // 2]))
    lines.append("   d_arm    : min %.3f  max %.3f  median %.3f" %
                 (min(da), max(da), sorted(da)[len(da) // 2]))
    ds = Counter()
    for i in suspects:
        ds[weights[i][0][0] if weights[i] else "<none>"] += 1
    lines.append("   dominant group:")
    for name, c in ds.most_common(10):
        lines.append("      %-16s %5d" % (name, c))
    lines.append("")
    lines.append("   worst 12 movers:")
    for i, d in moved[:12]:
        w = ", ".join("%s=%.2f" % t for t in weights[i][:3])
        lines.append("      move=%.3f rest=(%.3f, %.3f, %.3f) d_arm=%.3f  [%s]" %
                     (d, rest[i].x, rest[i].y, rest[i].z, d_arm[i], w))

# d_arm histogram over the whole mesh, to pick a sane radius threshold
lines.append("")
lines.append("d_arm histogram (all verts):")
bins = [0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.08, 0.10, 0.15, 0.25, 10.0]
prev = 0.0
for b in bins:
    c = sum(1 for x in d_arm if prev <= x < b)
    lines.append("   [%.2f .. %.2f)  %6d" % (prev, b, c))
    prev = b

text = "\n".join(lines)
print(text, flush=True)
if OUT:
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text + "\n")
log("PROBE_DONE")
