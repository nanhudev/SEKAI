"""Expose the existing tavern foundation and close its single-sided rear gable."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import shutil
from pathlib import Path
from mathutils import Matrix, Vector

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
BASE,OUT=ROOT/'v044',ROOT/'v045'
OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v044.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
terrain=bpy.data.objects['SM_VIL_Valley_Terrain_v009']
transform=Matrix.Translation(Vector((38,42,11.3)))@Matrix.Rotation(-.35,4,'Z')
inverse=transform.inverted()

def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)

original=[v.co.copy() for v in terrain.data.vertices]
changed=set()
for i,vertex in enumerate(terrain.data.vertices):
    local=inverse@vertex.co
    # A continuous foundation apron around the actual rotated building.
    distance=max(abs(local.x)-5.65,abs(local.y)-6.95)
    if distance>4.5:continue
    weight=1-smooth(1.5,4.5,distance)
    target=min(vertex.co.z,11.27)
    vertex.co.z=vertex.co.z*(1-weight)+target*weight
    if abs(vertex.co.z-original[i].z)>.001:changed.add(i)
terrain.data.update()
colors=terrain.data.color_attributes['Color']
for poly in terrain.data.polygons:
    if not any(i in changed for i in poly.vertices):continue
    poly.use_smooth=poly.normal.z>.82
    slope=1-smooth(.4,.84,poly.normal.z)
    for li in poly.loop_indices:
        p=terrain.data.vertices[terrain.data.loops[li].vertex_index].co
        local=inverse@p
        apron=1-smooth(.8,2.,max(abs(local.x)-5.65,abs(local.y)-6.95))
        grass=[.16,.27,.095];rock=[.235,.27,.285];dirt=[.23,.20,.14]
        colors.data[li].color=(*(grass[k]*(1-slope)*(1-apron)+rock[k]*slope*(1-apron)+dirt[k]*apron
                                      for k in range(3)),1)

parts=[]
plaster=bpy.data.materials['MV_Plaster_Warm']
timber=bpy.data.materials['MV_Timber_Dark']
stone=bpy.data.materials['MV_Stone_1']
glass=bpy.data.materials['MV_Window_Amber']

def box(name,local,size,material,bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1,location=local)
    obj=bpy.context.object;obj.name=name;obj.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.data.materials.append(material)
    if bevel:
        mod=obj.modifiers.new('Dressed_Edges','BEVEL');mod.width=bevel;mod.segments=2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.matrix_world=transform@obj.matrix_world;parts.append(obj)
    return obj

# The old rear triangle has the front's winding and vanishes under back-face culling.
# Build an actual wall thickness, keeping the original roof/timber envelope.
vertices=[]
for y in [6.79,6.94]:vertices.extend([(-5.29,y,6.71),(5.29,y,6.71),(0,y,11.19)])
mesh=bpy.data.meshes.new('Tavern_Rear_Gable_Solid')
mesh.from_pydata(vertices,[],[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)]);mesh.update()
obj=bpy.data.objects.new('Tavern_Rear_Gable_Solid',mesh);bpy.context.scene.collection.objects.link(obj)
mesh.materials.append(plaster);obj.matrix_world=transform;parts.append(obj)

# Human-scale rear service windows, sills, and a dressed foundation course.
for x in [-2.6,2.6]:
    for z in [2.25,5.35]:
        y=6.73 if z<4 else 7.00
        box('Tavern_Rear_Window', (x,y,z),(.98,.09,1.18),glass,.008)
        for dx in [-.57,.57]:box('Tavern_Rear_Jamb',(x+dx,y+.055,z),(.13,.14,1.47),timber)
        for dz in [-.68,.68]:box('Tavern_Rear_Lintel',(x,y+.055,z+dz),(1.28,.14,.14),timber)
        box('Tavern_Rear_Mullion',(x,y+.10,z),(.055,.08,1.20),timber,.006)
        box('Tavern_Rear_Sill',(x,y+.16,z-.75),(1.38,.44,.14),timber)
for i in range(12):
    box('Tavern_Rear_Foundation_Block',(-5.04+i*.916,6.64,.30),(.89,.37,.46),stone,.035)

bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
for obj in parts:obj.select_set(True)
bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join()
rear=bpy.context.object;rear.name='SM_VIL_Tavern_Rear_Completion_v045'
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=1.1,island_margin=.02);bpy.ops.object.mode_set(mode='OBJECT')

manifest['mesh_source_versions']={name:manifest.get('mesh_source_versions',{}).get(name,'v044')
                                  for name in manifest['assets'] if name!=terrain.name}
manifest['assets'].append(rear.name)
for name in manifest['assets']:
    if name not in [terrain.name,rear.name]:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
for obj in [terrain,rear]:
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.fbx(filepath=str(OUT/(obj.name+'.fbx')),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
manifest['stage']='TAVERN_REAR_REPAIR_REQUIRES_COLOR_REBAKE_AND_UE_CAPTURE'
manifest['geometry_source_version']='v044'
manifest['geometry_changes']=['Local grade lowered to the existing rotated tavern foundation apron',
    'Solid rear gable closes one-sided wall; service windows, timber frames and foundation course added',
    'Existing tavern, road, river, tree, plaza dressing, cameras and lighting retained']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'tavern_rear_report.json').write_text(json.dumps({'changed_terrain_vertices':len(changed),
    'foundation_apron_z_m':11.27,'solid_gable_thickness_m':.15,'status':'NOT_VISUALLY_ACCEPTED'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v045.blend'))
print('TAVERN_REAR_REPAIRED',len(changed))
