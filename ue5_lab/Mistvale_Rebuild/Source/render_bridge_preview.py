"""Render the standalone bridge asset for silhouette and structure review."""
import bpy
from mathutils import Vector
from pathlib import Path

root=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(root/"Source"/"Mistvale_StoneBridge.blend"))
bpy.ops.object.camera_add(location=(32,-31,20))
cam=bpy.context.object
cam.rotation_euler=(Vector((0,0,4.8))-cam.location).to_track_quat("-Z","Y").to_euler()
cam.data.type="ORTHO"
cam.data.ortho_scale=46
bpy.context.scene.camera=cam
bpy.ops.object.light_add(type="AREA",location=(-18,-20,27))
lamp=bpy.context.object
lamp.data.energy=6000
lamp.data.size=25
world=bpy.context.scene.world
world.use_nodes=True
bg=next(n for n in world.node_tree.nodes if n.type=="BACKGROUND")
bg.inputs["Color"].default_value=(.52,.68,.72,1)
bg.inputs["Strength"].default_value=.8
scene=bpy.context.scene
scene.render.engine="BLENDER_EEVEE"
scene.render.resolution_x=1280
scene.render.resolution_y=800
scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
scene.render.film_transparent=False
scene.render.filepath=str(root/"Review"/"bridge_model_preview.png")
bpy.ops.render.render(write_still=True)
print("BRIDGE_PREVIEW",scene.render.filepath)
