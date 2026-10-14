# Golden-route walkability audit, done on the real geometry before Godot ever
# opens. Answers the only question the directive actually cares about -- "can a
# player walk from South Entry to North Gate" -- as a number, not an opinion.
#
# Method: build a BVH per exported object, then march down the town spine
# casting a ray straight down every 0.5 m. For each sample record what was hit
# and at what height. Two failure modes fall out of the profile:
#
#   HOLE     no hit at all  -> the player falls through the world
#   STEP     height jump between neighbouring samples greater than the step the
#            capsule can climb (0.35 m rise per 0.5 m of travel; the player is a
#            Capsule3D r=0.35 h=1.80) -> a wall the player cannot pass
#
# A mesh-name change between samples is NOT automatically a defect: the route is
# eight separate meshes and a seam between two of them is fine as long as the
# heights agree. Only the height discontinuity matters.
#
# Run:
#   "/g/blender.exe" -b --factory-startup --python audit_route.py -- <fbx> <out.json>

import bpy
import json
import sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
fbx_path, out_path = argv[0], argv[1]

for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)

import io_scene_fbx.import_fbx as _imp  # noqa: E402

_original_read_light = _imp.blen_read_light


def _tolerant(fbx_tmpl, fbx_obj, settings):
    try:
        return _original_read_light(fbx_tmpl, fbx_obj, settings)
    except AttributeError:
        return None


_imp.blen_read_light = _tolerant
bpy.ops.import_scene.fbx(filepath=fbx_path)

# RIVER_SKIP: the water plane is a visual proxy on top of the riverbed. Whether
# it should stop the player is a gameplay decision, so it is measured against
# the terrain rather than silently collided with.
RIVER_SKIP = "River_Continuous"

trees = {}
for ob in bpy.data.objects:
    if ob.type != "MESH" or RIVER_SKIP in ob.name:
        continue
    me = ob.data
    verts = [ob.matrix_world @ v.co for v in me.vertices]
    faces = [list(p.vertices) for p in me.polygons]
    if not faces:
        continue
    trees[ob.name] = BVHTree.FromPolygons(verts, faces, all_triangles=False)

river = None
for ob in bpy.data.objects:
    if ob.type == "MESH" and RIVER_SKIP in ob.name:
        me = ob.data
        river = BVHTree.FromPolygons(
            [ob.matrix_world @ v.co for v in me.vertices],
            [list(p.vertices) for p in me.polygons], all_triangles=False)


def cast(x, y, start=250.0, depth=420.0):
    """Topmost surface under (x, y) in Blender/UE Z-up space."""
    o = Vector((x, y, start))
    d = Vector((0.0, 0.0, -1.0))
    best = None
    for name, tree in trees.items():
        loc, _, _, _ = tree.ray_cast(o, d, depth)
        if loc is not None and (best is None or loc.z > best[1]):
            best = (name, loc.z)
    return best


STEP_LIMIT = 0.35        # capsule r=0.35 -> this is the rise it can climb
TRAVEL = 0.5             # metres between samples

spine = []
prev_z = None
prev_hit = None
z = -340.0
while z <= 345.0:
    hit = cast(0.0, z)
    if hit is None:
        spine.append({"godot_z": z, "hit": None})
    else:
        name, hz = hit
        step = None if prev_hit is None else round(hz - prev_hit, 4)
        spine.append({
            "godot_z": round(z, 2),
            "hit": name,
            "godot_y": round(hz, 4),
            "step": step,
        })
    if hit is not None:
        prev_hit = hit[1]
    z += TRAVEL

holes = [s for s in spine if s["hit"] is None]
steps = [s for s in spine if s.get("step") is not None and abs(s["step"]) > STEP_LIMIT]

# River: how deep is the water plane relative to whatever is under it?
river_probe = []
for gy in (-200.0, -170.0, -140.0, -110.0, -80.0):
    hit = cast(0.0, gy)
    rl = None
    if river is not None:
        loc, _, _, _ = river.ray_cast(Vector((0.0, gy, 250.0)), Vector((0.0, 0.0, -1.0)), 420.0)
        if loc is not None:
            rl = round(loc.z, 4)
    river_probe.append({
        "godot_z": gy,
        "water_top": rl,
        "solid_top": None if hit is None else {"name": hit[0], "godot_y": round(hit[1], 4)},
    })

# Spawn candidate the previous session left, converted to Godot space.
SPAWN_UE = (6.0, -310.0, 1.5762)
spawn_hit = cast(SPAWN_UE[0], SPAWN_UE[1])

report = {
    "trees": len(trees),
    "step_limit": STEP_LIMIT,
    "travel": TRAVEL,
    "spine_samples": len(spine),
    "holes": holes[:40],
    "hole_count": len(holes),
    "steps_over_limit": steps[:40],
    "step_count": len(steps),
    "spine": spine,
    "river_probe": river_probe,
    "handoff_spawn_godot": [SPAWN_UE[0], SPAWN_UE[2], -SPAWN_UE[1]],
    "handoff_spawn_ground": None if spawn_hit is None else {
        "name": spawn_hit[0], "godot_y": round(spawn_hit[1], 4)},
}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=1)

print("ROUTE trees=%d samples=%d holes=%d steps>%.2fm=%d"
      % (len(trees), len(spine), len(holes), STEP_LIMIT, len(steps)))
for s in steps[:12]:
    print("  STEP %+.3f m at godot_z=%.1f  hit=%s" % (s["step"], s["godot_z"], s["hit"]))
for s in holes[:12]:
    print("  HOLE at godot_z=%.1f" % s["godot_z"])
print("ROUTE spawn_ground=%s" % (report["handoff_spawn_ground"],))
for r in river_probe:
    print("  RIVER godot_z=%.0f water=%s solid=%s" % (r["godot_z"], r["water_top"], r["solid_top"]))
