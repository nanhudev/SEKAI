"""Export the authored Blender checkpoint; glTF maps (x,y,z) to (x,z,-y)."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy,json,sys
from pathlib import Path
from mathutils import Vector
args=sys.argv[sys.argv.index('--')+1:];version=args[0];export_version=args[1] if len(args)>1 else version
base=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/version
out=Path(str(_SEKAI_ROOT / 'godot/models/starter_village'))/export_version;out.mkdir(parents=True,exist_ok=True)
assert not (out/'starter_village.glb').exists(),'Preserve completed export'
bpy.ops.wm.open_mainfile(filepath=str(base/('SEKAI_Valley_Terrain_'+version+'.blend')))
m=json.loads((base/'terrain_manifest.json').read_text())
for name,color in m['material_palette'].items():
    material=bpy.data.materials.get(name)
    if material:
        material.use_nodes=True
        material.node_tree.nodes.clear()
        bsdf=material.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
        output=material.node_tree.nodes.new('ShaderNodeOutputMaterial')
        material.node_tree.links.new(bsdf.outputs['BSDF'],output.inputs['Surface'])
        bsdf.inputs['Base Color'].default_value=(*color,1)
        bsdf.inputs['Roughness'].default_value=m.get('material_properties',{}).get(name,{}).get('roughness',.85)
for name,filename in m.get('surface_color_textures',{}).items():
    material=bpy.data.materials.get(name)
    if not material:continue
    tex=material.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(base/(filename+'.png')))
    tex.image.colorspace_settings.name='Non-Color'
    bsdf=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    material.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
for i,row in enumerate(m.get('instances',[])):
    original=bpy.data.objects[row['mesh']];ob=original.copy();ob.data=original.data
    bpy.context.collection.objects.link(ob);ob.name='Forest_%03d'%i
    ob.location=row['position_m'];ob.rotation_euler=(0,0,__import__('math').radians(row['yaw_degrees']))
    ob.scale=(row['scale'],)*3
bpy.ops.object.select_all(action='DESELECT')
library=set(m.get('library_assets',[]))
for ob in bpy.data.objects:
    if ob.type=='MESH' and ob.name not in library and (ob.name in m['assets'] or ob.name.startswith('Forest_')):
        ob.select_set(True)
        if ob.data.uv_layers:
            ob.data.uv_layers.active_index=0;ob.data.uv_layers[0].active_render=True
        if ob.name in ['SM_VIL_Valley_Terrain_v009','SM_VIL_Valley_Surroundings']:
            for face in ob.data.polygons:face.use_smooth=True
bpy.ops.export_scene.gltf(filepath=str(out/'starter_village.glb'),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT')
route=[[x,z,-y] for x,y,z in m['route_m']]
(out/'map_manifest.json').write_text(json.dumps({'version':version,'route':route,'source':'authored Blender checkpoint','axis_mapping':'Godot=(Blender.x,Blender.z,-Blender.y)','noncollision_assets':m.get('noncollision_assets',[]),'materials':'baked palette; UE shader graph is not transferred'},indent=2))
print('GODOT_EXPORT',out)
