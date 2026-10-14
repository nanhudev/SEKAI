"""Reassemble the original authored tavern after evaluating linked transforms."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import shutil
from pathlib import Path
from mathutils import Matrix, Vector

ROOT=Path(str(_SEKAI_ROOT / 'environment_production'))
BASE=ROOT/'Terrain/v012';OUT=ROOT/'Terrain/v013'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v012.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
name='SM_VIL_Hero_Tavern_Placed'
old=bpy.data.objects[name]
old_bounds=[tuple(old.matrix_world@Vector(c)) for c in old.bound_box]
bpy.data.objects.remove(old,do_unlink=True)
collection=bpy.data.collections.new('SEKAI_TAVERN_TRANSFORM_REPAIR')
bpy.context.scene.collection.children.link(collection)
with bpy.data.libraries.load(str(ROOT/'Versions/v005/SEKAI_VillageKit_v005.blend'),link=False) as (src,dst):
    dst.objects=list(src.objects)
parts=[]
for obj in dst.objects:
    if obj and obj.type=='MESH':
        collection.objects.link(obj);parts.append(obj)

# Library-loaded matrices are not evaluated until linked objects update.
bpy.context.view_layer.update()
foundation=next(o for o in parts if o.name.startswith('SM_VIL_Tavern_Foundation'))
assert abs(foundation.matrix_world.translation.z-.35)<.01,foundation.matrix_world
transform=Matrix.Translation(Vector((38,42,11.3)))@Matrix.Rotation(-.35,4,'Z')
for obj in parts:
    obj.matrix_world=transform@obj.matrix_world
    for index,material in enumerate(obj.data.materials):
        key=material.name.split('.')[0]
        if bpy.data.materials.get(key):obj.data.materials[index]=bpy.data.materials[key]
bpy.context.view_layer.update()
assert abs(foundation.matrix_world.translation.z-11.65)<.01
bpy.ops.object.select_all(action='DESELECT')
for obj in parts:obj.select_set(True)
bpy.context.view_layer.objects.active=foundation
bpy.ops.object.join()
hero=bpy.context.object;hero.name=name
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
bpy.context.view_layer.update()
new_bounds=[tuple(hero.matrix_world@Vector(c)) for c in hero.bound_box]
for asset in manifest['assets']:
    if asset!=name:shutil.copy2(BASE/(asset+'.fbx'),OUT/(asset+'.fbx'))
bpy.ops.export_scene.fbx(filepath=str(OUT/(name+'.fbx')),use_selection=True,object_types={'MESH'},
    axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
manifest['stage']='LANDMARK_TRANSFORM_REPAIRED_NOT_VISUALLY_ACCEPTED'
manifest['geometry_changes'] += ['Linked-object transforms evaluated before tavern merge']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'tavern_transform_check.json').write_text(json.dumps({'old_bounds':old_bounds,'new_bounds':new_bounds,
    'foundation_z_m':11.65,'status':'AUTHORING_CHECK_PASSED_ENGINE_PENDING'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v013.blend'))
print('SEKAI_TAVERN_TRANSFORM_REPAIRED',OUT)
