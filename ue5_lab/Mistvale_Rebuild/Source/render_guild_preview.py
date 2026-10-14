"""Render an isolated asset review image; the final level uses the FBX mesh."""
import bpy
import math
from mathutils import Vector
from pathlib import Path

root = Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(root / "Source" / "Mistvale_Guild.blend"))

bpy.ops.mesh.primitive_plane_add(size=200)
ground = bpy.context.object
ground.name = "PreviewGround_NotExported"
ground.location.z = -.04
ground.data.materials.append(bpy.data.materials["MV_Guild_WarmStone"])

bpy.ops.object.camera_add(location=(46,-57,35))
cam = bpy.context.object
target = Vector((0,0,9))
cam.rotation_euler = (target-cam.location).to_track_quat("-Z","Y").to_euler()
cam.data.type = "ORTHO"
cam.data.ortho_scale = 56
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type="AREA", location=(-24,-32,42))
key = bpy.context.object
key.data.energy = 7000
key.data.shape = "DISK"
key.data.size = 30

world = bpy.context.scene.world
world.use_nodes = True
bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs["Color"].default_value = (.55,.70,.76,1)
bg.inputs["Strength"].default_value = .65

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1280
scene.render.resolution_y = 850
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(root / "Review" / "guild_model_preview.png")
scene.view_settings.view_transform = "AgX"
bpy.ops.render.render(write_still=True)
print("PREVIEW", scene.render.filepath)
