"""LIA RIG BUILD -- bind a CLEAN HUMANOID RIG onto the Lia working mesh.

Design notes
------------
* Headless, reproducible, no addons required (no Rigify control layer).
  We build the DEFORM skeleton we actually want to ship to Godot.
* Rest pose = current mesh shape (arms hang, close to a relaxed A-pose).
  An explicit 35-45 deg A-pose conversion is deferred until the final
  art pass; the rig is authored so that swap is cheap.
* Joint heights follow the measured V0 landmarks, rescaled to the locked
  1.580 m crown height (see docs/characters/LIA_V0_AUDIT.md).
* Fingers are intentionally omitted: the current working mesh has no
  finger separation left. They are added in the high-detail art pass.

Run:
  "/g/blender.exe" -b --factory-startup --python tools/character/lia_rig_build.py \
      -- --blend <in.blend> --out-blend <out.blend> --out-json <out.json>
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
DO_CLEAN = str(ARGS.get("clean", "1")) not in ("0", "false", "no")
DO_UV = str(ARGS.get("uv", "1")) not in ("0", "false", "no")
DO_WEIGHTS = str(ARGS.get("weights", "1")) not in ("0", "false", "no")
BASE_COLOR = ARGS.get("base-color", "#8C93A3")


def log(msg):
    print("[LIA-RIG] %s" % msg, flush=True)


# ---------------------------------------------------------------- rig spec
# All values in metres, world space, origin at floor centre, +X = character
# LEFT, -Y = facing direction, +Z = up.  Derived from the V0 landmark scan
# scaled by 1.5076 (crown 1.048 -> 1.580 m).
Z_HIP = 0.860      # hip joint
Z_KNEE = 0.482     # measured knee
Z_ANKLE = 0.105    # just above the foot, inside the boot
Z_TOE_BASE = 0.028
Z_TOE_TIP = 0.022
Z_PELVIS_TIP = 0.950
Z_SPINE1 = 0.950
Z_SPINE2 = 1.030
Z_SPINE3 = 1.110
Z_CHEST = 1.185
Z_NECK = 1.215
Z_HEAD = 1.330     # skull base / jaw line is 1.375, head bone starts below it
Z_CROWN = 1.580    # measured crown

Z_SHOULDER = 1.205
Z_ELBOW = 0.972
Z_WRIST = 0.754
Z_HANDTIP = 0.620

X_HIP = 0.098
X_KNEE = 0.093
X_ANKLE = 0.088
X_CLAV = 0.028
X_SHOULDER = 0.148
X_ELBOW = 0.180
X_WRIST = 0.207
X_HANDTIP = 0.216

Y_TOE_BASE = -0.105
Y_TOE_TIP = -0.180

# name, parent, head, tail, connected, deform
BONE_SPEC = [
    ("root",      None,      (0, 0, 0.0),          (0, -0.22, 0.0),       False, False),
    ("pelvis",    "root",    (0, 0, Z_HIP),        (0, 0, Z_PELVIS_TIP),  False, True),
    ("spine_01",  "pelvis",  (0, 0, Z_SPINE1),     (0, 0, Z_SPINE2),      True,  True),
    ("spine_02",  "spine_01", (0, 0, Z_SPINE2),    (0, 0, Z_SPINE3),      True,  True),
    ("spine_03",  "spine_02", (0, 0, Z_SPINE3),    (0, 0, Z_CHEST),       True,  True),
    ("neck",      "spine_03", (0, 0, Z_NECK),      (0, 0, Z_HEAD),        True,  True),
    ("head",      "neck",    (0, 0, Z_HEAD),       (0, 0, Z_CROWN),       True,  True),
]

for side, s in (("l", 1.0), ("r", -1.0)):
    BONE_SPEC += [
        ("clavicle_%s" % side, "spine_03", (s * X_CLAV, 0, Z_SHOULDER),
         (s * X_SHOULDER, 0, Z_SHOULDER), False, True),
        ("upperarm_%s" % side, "clavicle_%s" % side, (s * X_SHOULDER, 0, Z_SHOULDER),
         (s * X_ELBOW, 0, Z_ELBOW), True, True),
        ("lowerarm_%s" % side, "upperarm_%s" % side, (s * X_ELBOW, 0, Z_ELBOW),
         (s * X_WRIST, 0, Z_WRIST), True, True),
        ("hand_%s" % side, "lowerarm_%s" % side, (s * X_WRIST, 0, Z_WRIST),
         (s * X_HANDTIP, 0, Z_HANDTIP), True, True),

        ("thigh_%s" % side, "pelvis", (s * X_HIP, 0, Z_HIP),
         (s * X_KNEE, 0, Z_KNEE), False, True),
        ("calf_%s" % side, "thigh_%s" % side, (s * X_KNEE, 0, Z_KNEE),
         (s * X_ANKLE, 0, Z_ANKLE), True, True),
        ("foot_%s" % side, "calf_%s" % side, (s * X_ANKLE, 0, Z_ANKLE),
         (s * X_ANKLE, Y_TOE_BASE, Z_TOE_BASE), True, True),
        ("toe_%s" % side, "foot_%s" % side, (s * X_ANKLE, Y_TOE_BASE, Z_TOE_BASE),
         (s * X_ANKLE, Y_TOE_TIP, Z_TOE_TIP), True, True),
    ]


# ---------------------------------------------------------------- helpers


def deselect_all():
    for o in bpy.context.view_layer.objects:
        o.select_set(False)


def activate(obj):
    deselect_all()
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)) + (1.0,)


def mesh_stats(obj):
    me = obj.data
    tris = sum(1 for p in me.polygons if len(p.vertices) == 3)
    quads = sum(1 for p in me.polygons if len(p.vertices) == 4)
    ngons = sum(1 for p in me.polygons if len(p.vertices) > 4)

    # connected shells via union-find over edges
    n = len(me.vertices)
    parent = list(range(n))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for e in me.edges:
        a, b = find(e.vertices[0]), find(e.vertices[1])
        if a != b:
            parent[a] = b
    shells = len({find(i) for i in range(n)})

    return {
        "verts": n,
        "edges": len(me.edges),
        "polys": len(me.polygons),
        "tris": tris,
        "quads": quads,
        "ngons": ngons,
        "shells": shells,
        "uv_layers": len(me.uv_layers),
        "material_slots": len(obj.material_slots),
        "vertex_groups": len(obj.vertex_groups),
        "has_armature_mod": any(m.type == "ARMATURE" for m in obj.modifiers),
    }


# ---------------------------------------------------------------- load

log("opening %s" % SRC)
bpy.ops.wm.open_mainfile(filepath=SRC)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
if not meshes:
    raise RuntimeError("no mesh object in %s" % SRC)
if len(meshes) > 1:
    log("WARNING %d mesh objects, binding the largest" % len(meshes))
mesh = max(meshes, key=lambda o: len(o.data.vertices))
log("target mesh = %s" % mesh.name)

stats_before = mesh_stats(mesh)
log("before: %s" % json.dumps(stats_before))

# make sure the object transform is identity so world == local
if tuple(mesh.matrix_world.to_translation()) != (0.0, 0.0, 0.0) or \
        tuple(mesh.scale) != (1.0, 1.0, 1.0):
    log("applying object transform")
    activate(mesh)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

co = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
bb_min = Vector((min(p.x for p in co), min(p.y for p in co), min(p.z for p in co)))
bb_max = Vector((max(p.x for p in co), max(p.y for p in co), max(p.z for p in co)))
size = bb_max - bb_min
log("bbox min=%s max=%s size=%s" % (
    tuple(round(v, 4) for v in bb_min),
    tuple(round(v, 4) for v in bb_max),
    tuple(round(v, 4) for v in size)))


# ---------------------------------------------------------------- cleanup

if DO_CLEAN:
    activate(mesh)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    log("cleanup: remove_doubles + recalc normals")

    bpy.ops.object.shade_smooth()
    # Blender 4.1+ dropped mesh.use_auto_smooth in favour of a modifier
    try:
        mesh.data.use_auto_smooth = True
        mesh.data.auto_smooth_angle = 1.0472  # 60 deg
        log("shade smooth + auto_smooth 60deg (legacy API)")
    except AttributeError:
        log("shade smooth only (auto_smooth API absent on this Blender)")


# ---------------------------------------------------------------- uv

if DO_UV and len(mesh.data.uv_layers) == 0:
    activate(mesh)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15192, island_margin=0.006,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    log("smart uv project done -> %d uv layer(s)" % len(mesh.data.uv_layers))
elif DO_UV:
    log("uv already present (%d layer(s)), left as is" % len(mesh.data.uv_layers))

# ---------------------------------------------------------------- material

if len(mesh.material_slots) == 0:
    mat = bpy.data.materials.new("LIA_SURFACE_PLACEHOLDER")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = hex_to_rgb(BASE_COLOR)
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = 0.62
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = 0.0
    mesh.data.materials.append(mat)
    log("placeholder material added %s" % BASE_COLOR)


# ---------------------------------------------------------------- armature

arm_data = bpy.data.armatures.new("LIA_RIG")
rig = bpy.data.objects.new("LIA_RIG", arm_data)
bpy.context.scene.collection.objects.link(rig)
activate(rig)
bpy.ops.object.mode_set(mode="EDIT")

eb = arm_data.edit_bones
created = []
for name, parent, head, tail, connect, deform in BONE_SPEC:
    b = eb.new(name)
    b.head = Vector(head)
    b.tail = Vector(tail)
    b.use_deform = deform
    if parent:
        b.parent = eb[parent]
        b.use_connect = connect
    created.append(name)

# roll: give the whole rig a consistent, readable convention
bpy.ops.armature.select_all(action="SELECT")
for roll_type in ("GLOBAL_NEG_Y", "GLOBAL_POS_Z"):
    try:
        bpy.ops.armature.calculate_roll(type=roll_type)
        log("calculate_roll(%s) ok" % roll_type)
        break
    except Exception as exc:      # pragma: no cover - Blender version drift
        log("calculate_roll(%s) failed: %s" % (roll_type, exc))

bpy.ops.object.mode_set(mode="OBJECT")
log("armature built: %d bones (%d deform)" % (
    len(arm_data.bones), sum(1 for b in arm_data.bones if b.use_deform)))


# ---------------------------------------------------------------- skin

weight_report = {}
if DO_WEIGHTS:
    deselect_all()
    mesh.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    log("automatic weights bound")

    # diagnostics: influence count per vertex
    vg_names = {vg.index: vg.name for vg in mesh.vertex_groups}
    deform_idx = {vg.index for vg in mesh.vertex_groups
                  if vg.name in {n for n, *_r in BONE_SPEC if _r[-1]}}
    counts = []
    unassigned = 0
    for v in mesh.data.vertices:
        n = sum(1 for g in v.groups if g.group in deform_idx and g.weight > 0.0005)
        if n == 0:
            unassigned += 1
        counts.append(n)
    counts.sort()
    weight_report = {
        "groups": len(mesh.vertex_groups),
        "unassigned_verts": unassigned,
        "influences_median": counts[len(counts) // 2] if counts else 0,
        "influences_p95": counts[int(len(counts) * 0.95)] if counts else 0,
        "influences_max": counts[-1] if counts else 0,
        "over4": sum(1 for c in counts if c > 4),
    }
    log("weights: %s" % json.dumps(weight_report))

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
log("saved %s" % OUT_BLEND)

report = {
    "source": SRC,
    "output_blend": OUT_BLEND,
    "mesh": mesh.name,
    "stats_before": stats_before,
    "stats_after": mesh_stats(mesh),
    "bbox_min": [round(v, 5) for v in bb_min],
    "bbox_max": [round(v, 5) for v in bb_max],
    "bbox_size": [round(v, 5) for v in size],
    "bones": [b.name for b in arm_data.bones],
    "bone_count": len(arm_data.bones),
    "deform_bone_count": sum(1 for b in arm_data.bones if b.use_deform),
    "weights": weight_report,
}
if OUT_JSON:
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    log("wrote %s" % OUT_JSON)

log("RIG_DONE")
