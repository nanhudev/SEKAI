"""Producer review render. Sets up a temporary camera and renders the asset.

Not modelling code. The MCP viewport screenshot caches its GPU buffer and does
not reflect viewport changes, so review images come from a real render instead.

Renders two views into one pass:
  <filepath>            three-quarter view
  <filepath>_side.png   edge-on view (checks blade direction and thickness)
"""

import bpy
import math
from mathutils import Vector

TARGET_CENTER = Vector((0.0, 0.43, 0.0))   # overall sword centre
TARGETS = ["Blade", "Guard", "Grip", "Pommel"]
OUT = "F:/SEKAI/assets_source/review/fp_sword_render.png"

# Drop the startup cube if it is still around.
cube = bpy.data.objects.get("Cube")
if cube is not None:
    bpy.data.objects.remove(cube, do_unlink=True)

scene = bpy.context.scene


def get_camera(name):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam_data = bpy.data.cameras.new(name)
        cam = bpy.data.objects.new(name, cam_data)
        scene.collection.objects.link(cam)
    cam.data.lens = 45.0
    scene.camera = cam
    return cam


def aim(cam, location):
    cam.location = location
    direction = TARGET_CENTER - Vector(location)
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()


def render_to(path, width=1100, height=900):
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered " + path)


try:
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
except Exception:
    scene.render.engine = 'BLENDER_EEVEE'

scene.render.film_transparent = False
if scene.world is None:
    scene.world = bpy.data.worlds.new("ReviewWorld")
scene.world.use_nodes = True
bg = scene.world.node_tree.nodes.get("Background")
if bg:
    bg.inputs[0].default_value = (0.34, 0.36, 0.40, 1.0)
    bg.inputs[1].default_value = 1.2

# Key light so the steel reads.
light = bpy.data.objects.get("ReviewKey")
if light is None:
    light_data = bpy.data.lights.new("ReviewKey", type='AREA')
    light_data.energy = 55.0
    light_data.size = 2.5
    light = bpy.data.objects.new("ReviewKey", light_data)
    scene.collection.objects.link(light)
light.location = (1.2, 0.9, 1.3)
aim_direction = TARGET_CENTER - Vector(light.location)
light.rotation_euler = aim_direction.to_track_quat('-Z', 'Y').to_euler()

present = [t for t in TARGETS if t in bpy.data.objects]
print("review targets present: " + ", ".join(present))

cam = get_camera("ReviewCam")

# Three-quarter view: readable silhouette and guard/grip relationship.
aim(cam, (1.75, -0.42, 1.05))
render_to(OUT)

# Near top-down: blade outline, taper and cutting edge in profile.
aim(cam, (0.42, 0.43, 2.05))
cam.data.lens = 50.0
render_to(OUT.replace(".png", "_side.png"))

print("review render complete")
