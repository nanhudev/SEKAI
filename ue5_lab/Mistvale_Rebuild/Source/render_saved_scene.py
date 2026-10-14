"""Visual geometry audit of the complete FBX exported from the saved UE level."""
import bpy, json, math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
# Blender 5.1's bundled FBX importer still writes this removed Cycles property.
# Supply it in this review process only; installed Blender files stay intact.
from cycles.properties import CyclesLightSettings
if not hasattr(CyclesLightSettings,'cast_shadow'):
    CyclesLightSettings.cast_shadow=bpy.props.BoolProperty(default=True)
bpy.ops.import_scene.fbx(filepath=str(ROOT/'Source/Mistvale_ActualScene_Review.fbx'))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
saved={r['label']:r for r in json.loads((ROOT/'Source/saved_art_scene.json').read_text())}
# FBX level export can reuse a cube mesh material for all its instances.
# Restore each actor's actual override names from the same UE readback.
for o in meshes:
    row=saved.get(o.name)
    if not row:continue
    o.data=o.data.copy()
    for i,name in enumerate(row['materials']):
        if name and i<len(o.data.materials):
            mat=bpy.data.materials.get(name) or bpy.data.materials.new(name)
            o.data.materials[i]=mat
report=[]
for o in meshes:
    vs=[o.matrix_world @ Vector(c) for c in o.bound_box]
    lo=[min(v[i] for v in vs) for i in range(3)]
    hi=[max(v[i] for v in vs) for i in range(3)]
    report.append({'name':o.name,'min':lo,'max':hi,'materials':[m.name for m in o.data.materials if m]})
(ROOT/'Source/exported_scene_bounds.json').write_text(json.dumps(report,indent=2))

colors={'M_Valley':(.24,.32,.15),'M_Town_Road':(.44,.35,.25),
 'M_River_Track':(.38,.30,.21),'M_River_Surface':(.035,.25,.31),
 'M_Weathered':(.40,.37,.30),'M_House_Russet':(.55,.29,.17),
 'M_House_Slate':(.18,.29,.34),'M_House_Moss':(.30,.37,.21),
 'M_House_Clay':(.54,.36,.20)}
for m in bpy.data.materials:
    color=next((c for key,c in colors.items() if key in m.name),None)
    if color:
        m.use_nodes=True
        m.node_tree.nodes.clear()
        bs=m.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
        out=m.node_tree.nodes.new('ShaderNodeOutputMaterial')
        bs.inputs['Base Color'].default_value=(*color,1)
        bs.inputs['Roughness'].default_value=.83
        m.node_tree.links.new(bs.outputs['BSDF'],out.inputs['Surface'])
for o in list(bpy.data.objects):
    if o.type in ('LIGHT','CAMERA'):bpy.data.objects.remove(o,do_unlink=True)
world=bpy.context.scene.world
world.use_nodes=True
bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND')
bg.inputs['Color'].default_value=(.55,.66,.76,1)
bg.inputs['Strength'].default_value=.65
bpy.ops.object.light_add(type='SUN',location=(0,0,200))
bpy.context.object.rotation_euler=(.55,-.4,-.6)
bpy.context.object.data.energy=2
bpy.context.object.data.angle=.08
scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE'
scene.eevee.taa_render_samples=32
scene.render.resolution_x=1500;scene.render.resolution_y=1000
scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
scene.render.image_settings.file_format='PNG'
def render(name,loc,target,scale):
    bpy.ops.object.camera_add(location=loc)
    c=bpy.context.object
    c.rotation_euler=(Vector(target)-c.location).to_track_quat('-Z','Y').to_euler()
    c.data.type='ORTHO';c.data.ortho_scale=scale;c.data.clip_end=3000
    scene.camera=c;scene.render.filepath=str(ROOT/'Review'/name)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(c,do_unlink=True)
render('saved_scene_overview.png',(240,340,360),(0,-55,8),470)
render('saved_scene_riverside.png',(-210,220,100),(-85,110,6),205)
print('EXPORTED_SCENE_RENDER',len(meshes))
