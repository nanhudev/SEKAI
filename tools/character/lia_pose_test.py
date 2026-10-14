"""LIA POSE TEST -- deformation QA renders for the rigged mesh.

Renders a fixed set of extreme poses from a canonical set of angles so that
skinning problems (shoulder collapse, elbow pinch, crotch tearing, cape
intersection) are visible instead of hidden behind a pretty rest pose.

World-axis convention used for the pose table (armature space):
    X = left/right axis   -> pitch  (limb swings forward / backward)
    Y = front/back axis   -> roll   (limb swings out to the side)
    Z = up axis           -> yaw    (twist)
Negative X on a thigh = leg swings FORWARD (-Y is the facing direction).

Run:
  "/g/blender.exe" -b --factory-startup --python tools/character/lia_pose_test.py \
      -- --blend <rigged.blend> --out <dir> --tag LIA_V3
"""

import bpy
import sys
import os
import math
from mathutils import Vector, Quaternion

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
OUT = os.path.abspath(ARGS["out"])
TAG = ARGS.get("tag", "LIA_POSE")
ONLY = ARGS.get("only", "")
RES_X = int(ARGS.get("resx", 520))
RES_Y = int(ARGS.get("resy", 780))
os.makedirs(OUT, exist_ok=True)


def log(msg):
    print("[LIA-POSE] %s" % msg, flush=True)


# ---------------------------------------------------------------- pose table
# (bone, world_axis, degrees) -- applied in listed order, additive
POSES = [
    ("01_rest", []),
    ("02_arm_fwd", [
        ("upperarm_l", "X", -75), ("upperarm_r", "X", -75),
    ]),
    ("03_arm_up", [
        ("upperarm_l", "Y", -80), ("upperarm_r", "Y", 80),
    ]),
    ("04_arm_cross", [
        ("upperarm_l", "Y", -38), ("upperarm_r", "Y", 38),
        ("upperarm_l", "X", -28), ("upperarm_r", "X", -28),
        ("lowerarm_l", "X", -65), ("lowerarm_r", "X", -65),
    ]),
    ("05_elbow_130", [
        ("lowerarm_l", "X", -130), ("lowerarm_r", "X", -130),
    ]),
    ("06_crouch", [
        ("spine_01", "X", -18), ("spine_02", "X", -12),
        ("thigh_l", "X", -80), ("thigh_r", "X", -80),
        ("calf_l", "X", 115), ("calf_r", "X", 115),
        ("foot_l", "X", -35), ("foot_r", "X", -35),
    ]),
    ("07_spine_bend", [
        ("spine_01", "X", -32), ("spine_02", "X", -26), ("spine_03", "X", -16),
    ]),
    ("08_spine_twist", [
        ("spine_02", "Z", 38), ("spine_03", "Z", 26), ("neck", "Z", 18),
    ]),
    ("09_side_bend", [
        ("spine_01", "Y", 22), ("spine_02", "Y", 18), ("spine_03", "Y", 12),
    ]),
    ("10_head_turn", [
        ("neck", "Z", 22), ("head", "Z", 48), ("head", "X", -16),
    ]),
    ("11_high_step", [
        ("thigh_l", "X", -85), ("calf_l", "X", 62), ("foot_l", "X", 25),
        ("thigh_r", "X", 18), ("calf_r", "X", 12),
        ("upperarm_l", "X", -30), ("upperarm_r", "X", 25),
    ]),
    ("12_wide_stance", [
        ("thigh_l", "Y", -26), ("thigh_r", "Y", 26),
        ("calf_l", "X", 34), ("calf_r", "X", 34),
        ("foot_l", "X", -30), ("foot_r", "X", -30),
    ]),
]

VIEWS = [
    ("front", (0.0, -4.0, 0.86), 1.95),
    ("right", (4.0, 0.0, 0.86), 1.95),
    ("q34", (2.9, -2.9, 1.00), 1.95),
]


# ---------------------------------------------------------------- scene


def deselect_all():
    for o in bpy.context.view_layer.objects:
        o.select_set(False)


def rotate_world(pb, axis_name, deg):
    """Rotate a pose bone about a WORLD-space axis, additive."""
    axis = {"X": Vector((1, 0, 0)),
            "Y": Vector((0, 1, 0)),
            "Z": Vector((0, 0, 1))}[axis_name]
    m = pb.bone.matrix_local.to_3x3()
    local_axis = m.inverted() @ axis
    q = Quaternion(local_axis.normalized(), math.radians(deg))
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = pb.rotation_quaternion @ q


log("opening %s" % SRC)
bpy.ops.wm.open_mainfile(filepath=SRC)

rig = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
mesh = next((o for o in bpy.data.objects if o.type == "MESH"), None)
if rig is None or mesh is None:
    raise RuntimeError("need one armature + one mesh, got rig=%s mesh=%s" % (rig, mesh))
log("rig=%s mesh=%s bones=%d" % (rig.name, mesh.name, len(rig.data.bones)))

# --- render setup (Workbench, studio light + cavity so creases show)
scn = bpy.context.scene
scn.render.engine = "BLENDER_WORKBENCH"
scn.render.resolution_x = RES_X
scn.render.resolution_y = RES_Y
scn.render.resolution_percentage = 100
scn.render.image_settings.file_format = "PNG"
scn.render.film_transparent = False
scn.view_settings.view_transform = "Standard"

sh = scn.display.shading
sh.light = "STUDIO"
sh.studio_light = "Default"
sh.color_type = "SINGLE"
sh.single_color = (0.74, 0.74, 0.76)
sh.show_cavity = True
sh.cavity_type = "BOTH"
sh.curvature_ridge_factor = 1.0
sh.curvature_valley_factor = 1.0
sh.show_object_outline = False
sh.show_shadows = True
scn.display.render_aa = "16"

cam_data = bpy.data.cameras.new("POSE_CAM")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("POSE_CAM", cam_data)
scn.collection.objects.link(cam)
scn.camera = cam


def place_cam(pos, ortho):
    cam.location = Vector(pos)
    d = Vector((0.0, 0.0, 0.86)) - Vector(pos)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cam_data.ortho_scale = ortho


def scan_bbox():
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(dg)
    me = ev.to_mesh()
    mw = mesh.matrix_world
    pts = [mw @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx


def clear_pose():
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.location = (0, 0, 0)


written = []
for name, ops in POSES:
    if ONLY and ONLY not in name:
        continue
    clear_pose()
    for bone, axis, deg in ops:
        pb = rig.pose.bones.get(bone)
        if pb is None:
            log("MISSING BONE %s in pose %s" % (bone, name))
            continue
        rotate_world(pb, axis, deg)
    bpy.context.view_layer.update()
    mn, mx = scan_bbox()
    for vname, pos, ortho in VIEWS:
        # keep the camera framing the posed silhouette
        cam_center_z = (mn.z + mx.z) * 0.5
        place_cam((pos[0], pos[1], cam_center_z), ortho)
        path = os.path.join(OUT, "%s_%s_%s.png" % (TAG, name, vname))
        scn.render.filepath = path
        bpy.ops.render.render(write_still=True)
        written.append(path)
    log("%-16s bbox z=[%.3f .. %.3f]  x=[%.3f .. %.3f]" % (
        name, mn.z, mx.z, mn.x, mx.x))

log("rendered %d images" % len(written))
with open(os.path.join(OUT, "%s_pose_list.txt" % TAG), "w", encoding="utf-8") as f:
    for p in written:
        f.write(p + "\n")
log("POSE_DONE")
