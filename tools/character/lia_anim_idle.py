"""LIA ANIM IDLE -- authored breathing idle loop.

Deliberately restrained: Lia is an NPC ferry-keeper, not a hero doing a pose.
Weight settles slightly onto one leg, the ribcage lifts, the head drifts a
degree or two.  No big gestures, no metronome sway.

Axis convention matches lia_pose_test.py (armature space):
    X = pitch, Y = roll/abduct, Z = yaw
Negative X on a spine bone = lean forward; positive = chest lifts.

Run:
  "/g/blender.exe" -b --factory-startup --python tools/character/lia_anim_idle.py \
      -- --blend <rigged.blend> --out-blend <rigged_anim.blend>
"""

import bpy
import sys
import os
import math
from mathutils import Vector, Quaternion


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
ACTION = ARGS.get("name", "Idle")
FPS = int(ARGS.get("fps", 24))


def log(msg):
    print("[LIA-ANIM] %s" % msg, flush=True)


bpy.ops.wm.open_mainfile(filepath=SRC)
rig = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
if rig is None:
    raise RuntimeError("no armature in %s" % SRC)

# 5 s cycle at 24 fps: frames 1 .. 121, last frame repeats the first
KEYS = [1, 25, 49, 73, 97, 121]

# deg, world axis.  A full breath in, then out.
CURVES = {
    "pelvis":    {1: [],               25: [("Y", 0.4)],   49: [("Y", 0.7)],
                  73: [("Y", 0.3)],    97: [("Y", 0.1)],   121: []},
    "spine_01":  {1: [("X", 0.0)],     25: [("X", 0.5)],   49: [("X", 0.9)],
                  73: [("X", 0.4)],    97: [("X", 0.1)],   121: [("X", 0.0)]},
    "spine_02":  {1: [("X", 0.0)],     25: [("X", 0.8)],   49: [("X", 1.4)],
                  73: [("X", 0.6)],    97: [("X", 0.2)],   121: [("X", 0.0)]},
    "spine_03":  {1: [("X", 0.0)],     25: [("X", 0.9)],   49: [("X", 1.6)],
                  73: [("X", 0.7)],    97: [("X", 0.2)],   121: [("X", 0.0)]},
    "neck":      {1: [("X", 0.0)],     25: [("X", -0.5)],  49: [("X", -0.9)],
                  73: [("X", -0.4)],   97: [("X", -0.1)],  121: [("X", 0.0)]},
    # head drifts: a touch of yaw over the cycle, a touch of pitch with breath
    "head":      {1: [("Z", 0.0)],     25: [("Z", 1.2), ("X", -0.8)],
                  49: [("Z", 1.8), ("X", -1.4)],
                  73: [("Z", 0.9), ("X", -0.7)],
                  97: [("Z", 0.2), ("X", -0.2)],  121: [("Z", 0.0)]},
    # arms open a hair on the inhale
    "upperarm_l": {1: [("Y", 0.0)],    25: [("Y", -0.7)],  49: [("Y", -1.3)],
                   73: [("Y", -0.6)],  97: [("Y", -0.2)],  121: [("Y", 0.0)]},
    "upperarm_r": {1: [("Y", 0.0)],    25: [("Y", 0.7)],   49: [("Y", 1.3)],
                   73: [("Y", 0.6)],   97: [("Y", 0.2)],   121: [("Y", 0.0)]},
    "lowerarm_l": {1: [("X", 0.0)],    25: [("X", -0.5)],  49: [("X", -0.9)],
                   73: [("X", -0.4)],  97: [("X", -0.1)],  121: [("X", 0.0)]},
    "lowerarm_r": {1: [("X", 0.0)],    25: [("X", -0.5)],  49: [("X", -0.9)],
                   73: [("X", -0.4)],  97: [("X", -0.1)],  121: [("X", 0.0)]},
}

# pelvis sinks ~3 mm as the ribcage lifts (weight settling, not a bounce)
PELVIS_LOC = {1: 0.0, 25: -0.0018, 49: -0.0030, 73: -0.0015, 97: -0.0004, 121: 0.0}


def rot_world(pb, axis_name, deg):
    axis = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}[axis_name]
    m = pb.bone.matrix_local.to_3x3()
    q = Quaternion((m.inverted() @ axis).normalized(), math.radians(deg))
    pb.rotation_quaternion = pb.rotation_quaternion @ q


def clear_pose():
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.location = (0.0, 0.0, 0.0)


def all_fcurves(act):
    """Blender 4.4+ moved fcurves under action.layers -> strips -> channelbags."""
    fcs = getattr(act, "fcurves", None)
    if fcs is not None:
        try:
            return list(fcs)
        except Exception:
            pass
    out = []
    for layer in getattr(act, "layers", []) or []:
        for strip in getattr(layer, "strips", []) or []:
            for cb in getattr(strip, "channelbags", []) or []:
                out.extend(cb.fcurves)
    return out


# let Blender create and own the action/slot pair, then rename it - the explicit
# bpy.data.actions.new() + animation_data.action path trips over slotted actions
# on Blender 5.1.
rig.animation_data_create()

for f in KEYS:
    clear_pose()
    for bone, curve in CURVES.items():
        pb = rig.pose.bones.get(bone)
        if pb is None:
            continue
        for axis_name, deg in curve.get(f, []):
            rot_world(pb, axis_name, deg)
    pel = rig.pose.bones.get("pelvis")
    if pel is not None:
        pel.location = (0.0, PELVIS_LOC.get(f, 0.0), 0.0)

    scn = bpy.context.scene
    scn.frame_set(f)
    for bone in CURVES:
        pb = rig.pose.bones.get(bone)
        if pb is not None:
            pb.keyframe_insert("rotation_quaternion", frame=f)
    if pel is not None:
        pel.keyframe_insert("location", frame=f)

# smooth in/out everywhere so nothing snaps
act = rig.animation_data.action
if act is None:
    raise RuntimeError("keyframe_insert did not create an action")
act.name = ACTION
fcurves = all_fcurves(act)
for fc in fcurves:
    for kp in fc.keyframe_points:
        kp.interpolation = "BEZIER"
        kp.handle_left_type = "AUTO_CLAMPED"
        kp.handle_right_type = "AUTO_CLAMPED"
    fc.update()

scn = bpy.context.scene
scn.render.fps = FPS
scn.frame_start = KEYS[0]
scn.frame_end = KEYS[-1]

clear_pose()
scn.frame_set(KEYS[0])

bones_animated = sorted({fc.data_path.split('"')[1] for fc in fcurves
                         if '"' in fc.data_path})
log("action '%s': %d fcurves over %d bones, frames %d..%d @ %d fps"
    % (act.name, len(fcurves), len(bones_animated), KEYS[0], KEYS[-1], FPS))
log("bones: %s" % ", ".join(bones_animated))
if len(fcurves) == 0:
    raise RuntimeError("action has no fcurves - animation would export empty")

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
log("saved %s" % OUT_BLEND)
log("ANIM_DONE")
