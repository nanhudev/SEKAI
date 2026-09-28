"""Producer review render for ENV-01. Lights + camera + layout, then render.

Not modelling code. Two images:
  env01_kit_grid.png     -- all 12 pieces laid out on a grid, silhouette check
  env01_kit_assembly.png -- a kitbash demo: six pieces snapped together flush

Positions are restored to the origin at the end, so the .blend keeps every piece
on its own grid-centre origin as required.
"""

import bpy
import math
from mathutils import Vector

OUT = "F:/SEKAI/assets_source/review/env01_kit_grid.png"
COLLECTION = "SEKAI_ENV01_KIT"

scene = bpy.context.scene

try:
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
except Exception:
    scene.render.engine = 'BLENDER_EEVEE'

if scene.world is None:
    scene.world = bpy.data.worlds.new("ReviewWorld")
scene.world.use_nodes = True
bg = scene.world.node_tree.nodes.get("Background")
if bg is None:
    raise RuntimeError("world has no Background node; cannot set review lighting")
bg.inputs[0].default_value = (0.36, 0.38, 0.42, 1.0)
bg.inputs[1].default_value = 1.15

col = bpy.data.collections.get(COLLECTION)
if col is None:
    raise RuntimeError("collection %r not found" % COLLECTION)

pieces = {o.name: o for o in col.objects if o.type == 'MESH'}
if len(pieces) != 12:
    print("WARNING expected 12 pieces, found %d" % len(pieces))


def get_camera(name):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam_data = bpy.data.cameras.new(name)
        cam = bpy.data.objects.new(name, cam_data)
        scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def aim(obj, location, target):
    obj.location = Vector(location)
    direction = Vector(target) - Vector(location)
    obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()


cam = get_camera("ReviewCam")

light = bpy.data.objects.get("ReviewKey")
if light is None:
    light_data = bpy.data.lights.new("ReviewKey", type='AREA')
    light_data.size = 9.0
    light = bpy.data.objects.new("ReviewKey", light_data)
    scene.collection.objects.link(light)
light.data.energy = 900.0


def render_to(path, width=1400, height=950):
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered " + path)


def place(name, x, y, z=0.0, yaw=0.0, pitch=0.0):
    obj = pieces.get(name)
    if obj is None:
        raise RuntimeError("placement references missing piece %r" % name)
    obj.location = (x, y, z)
    obj.rotation_euler = (pitch, 0.0, yaw)


def restore_all():
    for obj in pieces.values():
        obj.location = (0.0, 0.0, 0.0)
        obj.rotation_euler = (0.0, 0.0, 0.0)


# ---------------------------------------------------------------- grid overview
GRID = [
    ("ENV01_Terrace_8x8", 0, 0),
    ("ENV01_Terrace_4x4", 1, 0),
    ("ENV01_Terrace_StepEdge_4", 2, 0),
    ("ENV01_Stair_Landing_2x2", 3, 0),
    ("ENV01_Stair_Straight_4", 0, 1),
    ("ENV01_Ramp_4x2", 1, 1),
    ("ENV01_RetainingWall_4x1p5", 2, 1),
    ("ENV01_RetainingWall_Corner", 3, 1),
    ("ENV01_Curb_4", 0, 2),
    ("ENV01_CliffEdge_4", 1, 2),
    ("ENV01_BridgeDeck_4", 2, 2),
    ("ENV01_BridgeRail_4", 3, 2),
]

restore_all()
SPACING = 11.0
for name, gx, gy in GRID:
    place(name, (gx - 1.5) * SPACING, (1.0 - gy) * SPACING)

aim(cam, (30.0, -34.0, 27.0), (0.0, 0.0, 0.0))
cam.data.lens = 30.0
aim(light, (18.0, -14.0, 40.0), (0.0, 0.0, 0.0))
render_to(OUT)

# ------------------------------------------------------------- kitbash assembly
restore_all()

# 8x8 plaza, a 4x4 terrace flush against it, landing flush beyond that.
place("ENV01_Terrace_8x8", 0.0, 0.0)
place("ENV01_Terrace_4x4", 0.0, 6.0)
place("ENV01_Stair_Landing_2x2", 0.0, 9.0)

# kerb along the plaza's -Y edge
place("ENV01_Curb_4", 0.0, -4.15)

# bench edge sitting on top of the plaza slab (plaza top Z = 0.30)
place("ENV01_Terrace_StepEdge_4", 1.0, -1.4, z=0.30)

# retaining wall turned 90 degrees so its 4 m run lies along the plaza's -X edge
place("ENV01_RetainingWall_4x1p5", -4.225, 0.0, yaw=math.pi * 0.5)

# bridge deck continues past the landing; deck top lands flush at Z = 0.30
place("ENV01_BridgeDeck_4", 0.0, 11.0, z=-0.05)
place("ENV01_BridgeRail_4", 0.925, 11.0, z=0.30)

aim(cam, (13.0, -17.0, 9.5), (0.0, 3.5, 0.4))
cam.data.lens = 34.0
aim(light, (6.0, -10.0, 22.0), (0.0, 3.0, 0.0))
render_to(OUT.replace("_grid", "_assembly"), width=1500, height=900)

restore_all()
print("review render complete; all pieces restored to origin")
