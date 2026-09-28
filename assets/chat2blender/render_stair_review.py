"""Producer review render for KIT-02a. Not modelling code.

Renders the stair from the angles the acceptance gate actually names, then prints
the measured facts (dimensions, rotation, scale, materials) so the screenshot and
the numbers in the same log describe the same object.

The MCP viewport screenshot returns a cached GPU buffer and does not update after
the viewport moves, so review images come from a real render, not a screenshot.

Views:
  kit02a_01_threequarter.png   silhouette + secondary structure
  kit02a_02_profile.png        the step profile and the cheek's top line
  kit02a_03_firstperson.png    eye at 1.62 m, 1.6 m from the bottom step (gate 1)
  kit02a_04_nosing.png         close on one nosing: tertiary detail and wear
  kit02a_05_top.png            plan: width, course break-up
  kit02a_06_low_along.png      low and along the run: does it read as built stone
"""

import bpy
import math
from mathutils import Vector

OUT_DIR = "F:/SEKAI/assets_source/review/kit02a/"
VISUAL = "KIT02A_Stair_R20_7W4"
RAMP = "KIT02A_Stair_R20_7W4_RAMP"


def purge_startup():
    cube = bpy.data.objects.get("Cube")
    if cube is not None:
        bpy.data.objects.remove(cube, do_unlink=True)


purge_startup()

scene = bpy.context.scene
try:
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
except Exception:
    scene.render.engine = 'BLENDER_EEVEE'

scene.render.film_transparent = False

# Exposure discipline. The first pass of this rig ran a 900 W key with a 1.2
# strength world and drove ENV-01's stone (albedo 0.42-0.47, a mid grey) to
# near-white, which makes every material judgement worthless - the reviewer ends
# up reviewing the light rig. AgX gives the same highlight rolloff the game's
# tonemapper has, and the energies below put mid-grey back at mid-grey.
try:
    scene.view_settings.view_transform = 'AgX'
except Exception:
    try:
        scene.view_settings.view_transform = 'Filmic'
    except Exception:
        pass
scene.view_settings.look = 'None'
scene.view_settings.exposure = 0.0

if scene.world is None:
    scene.world = bpy.data.worlds.new("ReviewWorld")
scene.world.use_nodes = True
bg = scene.world.node_tree.nodes.get("Background")
if bg:
    bg.inputs[0].default_value = (0.30, 0.33, 0.37, 1.0)
    bg.inputs[1].default_value = 0.45


def get_camera(name):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam_data = bpy.data.cameras.new(name)
        cam = bpy.data.objects.new(name, cam_data)
        scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def aim(cam, location, target):
    cam.location = Vector(location)
    direction = Vector(target) - Vector(location)
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()


def render_to(name, width=1280, height=860):
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = OUT_DIR + name
    bpy.ops.render.render(write_still=True)
    print("rendered " + OUT_DIR + name)


# --- key + fill, aimed at the stair's centre ---------------------------------
CENTRE = (0.0, 1.0, 0.70)

light = bpy.data.objects.get("ReviewKey")
if light is None:
    light_data = bpy.data.lights.new("ReviewKey", type='AREA')
    light_data.size = 4.0
    light = bpy.data.objects.new("ReviewKey", light_data)
    scene.collection.objects.link(light)
light.data.energy = 260.0
light.location = (3.4, -3.0, 4.6)
d = Vector(CENTRE) - Vector(light.location)
light.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()

fill = bpy.data.objects.get("ReviewFill")
if fill is None:
    fill_data = bpy.data.lights.new("ReviewFill", type='AREA')
    fill_data.size = 5.0
    fill_data.energy = 70.0
    fill = bpy.data.objects.new("ReviewFill", fill_data)
    scene.collection.objects.link(fill)
fill.location = (-4.2, -2.0, 2.6)
fill.rotation_euler = (Vector(CENTRE) - Vector(fill.location)).to_track_quat('-Z', 'Y').to_euler()

cam = get_camera("ReviewCam")

VIEWS = [
    ("kit02a_01_threequarter.png", (4.4, -3.2, 3.1), CENTRE, 42.0),
    ("kit02a_02_profile.png", (7.6, 1.0, 1.75), (0.0, 1.0, 0.70), 55.0),
    # Gate 1: "first-person distance of 1.5 m" - eye height 1.62 m, standing in
    # front of the bottom step. Framed to hold the first four treads AND the
    # flank, because a gate that only shows three flat slabs cannot tell you
    # whether the piece reads as built stone.
    ("kit02a_03_firstperson.png", (0.0, -1.7, 1.62), (0.0, 1.35, 0.95), 68.0),
    ("kit02a_04_nosing.png", (-1.05, 0.05, 0.72), (0.35, 0.62, 0.32), 55.0),
    ("kit02a_05_top.png", (0.0, 1.0, 5.0), (0.0, 1.0, 0.30), 45.0),
    # Low and along the run: the view that answers "built stone or scaled cube".
    ("kit02a_06_low_along.png", (0.55, -2.3, 0.55), (0.0, 1.2, 0.72), 48.0),
]

for name, loc, target, lens in VIEWS:
    cam.data.lens = lens
    aim(cam, loc, target)
    render_to(name)


# --- measured facts, printed next to the images ------------------------------
print("")
print("=== MEASURED ===")
for obj_name in (VISUAL, RAMP):
    obj = bpy.data.objects.get(obj_name)
    if obj is None:
        print("MISSING OBJECT: " + obj_name)
        continue
    dims = obj.dimensions
    tris = 0
    if obj.type == 'MESH' and obj.data is not None:
        obj.data.calc_loop_triangles()
        tris = len(obj.data.loop_triangles)
    mats = [ms.material.name if ms.material else "(none)" for ms in obj.material_slots]
    print("%s dims=(%.4f, %.4f, %.4f) tris=%d rot=(%.4f, %.4f, %.4f) scale=(%.4f, %.4f, %.4f) mats=%s" % (
        obj_name, dims.x, dims.y, dims.z, tris,
        obj.rotation_euler.x, obj.rotation_euler.y, obj.rotation_euler.z,
        obj.scale.x, obj.scale.y, obj.scale.z, mats))

# The modulus check, from the mesh rather than from the code's own variable.
obj = bpy.data.objects.get(VISUAL)
if obj is not None and obj.type == 'MESH':
    zs = sorted({round(v.co.z, 6) for v in obj.data.vertices if v.co.z > 0.0005})
    print("distinct step-top heights: %s" % zs)
    if len(zs) >= 2:
        steps = [round(zs[i + 1] - zs[i], 6) for i in range(len(zs) - 1)]
        print("riser deltas between those heights: %s" % steps)

print("review render complete")
