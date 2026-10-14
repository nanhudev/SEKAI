"""Open the rear elevation from the fixed exit camera, without moving the building."""
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
BASE,OUT=ROOT/'v046',ROOT/'v047';OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v046.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
transform=Matrix.Translation(Vector((38,42,11.3)))@Matrix.Rotation(-.35,4,'Z')
inverse=transform.inverted();terrain=bpy.data.objects['SM_VIL_Valley_Terrain_v009']
original=[v.co.copy() for v in terrain.data.vertices]

def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)

def road_distance(x,y):
    result=999.
    for a,b in zip(manifest['route_m'],manifest['route_m'][1:]):
        dx,dy=b[0]-a[0],b[1]-a[1]
        t=max(0,min(1,((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy)))
        result=min(result,math.hypot(x-a[0]-t*dx,y-a[1]-t*dy))
    return result

changed=set()
for i,vertex in enumerate(terrain.data.vertices):
    local=inverse@vertex.co
    if not (4.5<local.y<35 and abs(local.x)<13):continue
    weight=smooth(4.5,7,local.y)*(1-smooth(25,35,local.y))*(1-smooth(8,13,abs(local.x)))
    weight*=smooth(3.0,4.5,road_distance(vertex.co.x,vertex.co.y))
    target=11.27+max(0,local.y-9)*.12
    vertex.co.z-=max(0,vertex.co.z-target)*weight
    if abs(vertex.co.z-original[i].z)>.001:changed.add(i)
terrain.data.update()
colors=terrain.data.color_attributes['Color']
for poly in terrain.data.polygons:
    if not any(i in changed for i in poly.vertices):continue
    poly.use_smooth=poly.normal.z>.82
    slope=1-smooth(.4,.84,poly.normal.z)
    for li in poly.loop_indices:
        p=terrain.data.vertices[terrain.data.loops[li].vertex_index].co
        local=inverse@p;apron=1-smooth(8.3,11,local.y)
        grass=[.16,.27,.095];rock=[.235,.27,.285];dirt=[.23,.20,.14]
        colors.data[li].color=(*(grass[k]*(1-slope)*(1-apron)+rock[k]*slope*(1-apron)+dirt[k]*apron
                               for k in range(3)),1)
assert changed
assert all((vertex.co-old).length<.00001 for vertex,old in zip(terrain.data.vertices,original)
           if road_distance(old.x,old.y)<=3), 'Road support changed'

parts=[]
def box(name,center,size,material):
    bpy.ops.mesh.primitive_cube_add(size=1,location=center);obj=bpy.context.object
    obj.name=name;obj.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.data.materials.append(bpy.data.materials[material])
    bevel=obj.modifiers.new('Crafted_Edge','BEVEL');bevel.width=.014;bevel.segments=2
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return obj
def beam(a,b,width=.19):
    a,b=Vector(a),Vector(b);obj=box('Tavern_Rear_Gable_Timber',(a+b)*.5,(width,.18,(b-a).length),'MV_Timber_Dark')
    obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();parts.append(obj)
    return obj
for side in [-1,1]:
    beam((side*5.2,7.075,6.82),(0,7.075,11.15),.21)
    beam((side*3.9,7.075,6.84),(side*1.5,7.075,8.84),.16)
beam((-5.3,7.075,6.82),(5.3,7.075,6.82),.23)
beam((0,7.075,6.8),(0,7.075,11.15),.20)
beam((-2.4,7.075,9.08),(2.4,7.075,9.08),.17)
for side in [-1,1]:
    obj=box('Tavern_Attic_Window',(side*.57,7.10,8.06),(.70,.075,1.25),'MV_Window_Amber');parts.append(obj)
    for dx in [-.41,.41]:
        parts.append(box('Tavern_Attic_Window_Jamb',(side*.57+dx,7.15,8.06),(.10,.13,1.42),'MV_Timber_Warm'))
    for dz in [-.67,.67]:
        parts.append(box('Tavern_Attic_Window_Header',(side*.57,7.15,8.06+dz),(.92,.13,.11),'MV_Timber_Warm'))
for obj in parts:obj.matrix_world=transform@obj.matrix_world
bpy.context.view_layer.update()
rear=bpy.data.objects['SM_VIL_Tavern_Rear_Completion_v045']
bpy.ops.object.select_all(action='DESELECT');rear.select_set(True)
for obj in parts:obj.select_set(True)
bpy.context.view_layer.objects.active=rear;bpy.ops.object.join()
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=1.1,island_margin=.02);bpy.ops.object.mode_set(mode='OBJECT')
manifest['mesh_source_versions']={name:manifest.get('mesh_source_versions',{}).get(name,'v046')
                                  for name in manifest['assets'] if name not in [terrain.name,rear.name]}
for name in manifest['assets']:
    if name not in [terrain.name,rear.name]:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
for obj in [terrain,rear]:
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.fbx(filepath=str(OUT/(obj.name+'.fbx')),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
manifest['stage']='TAVERN_BACKYARD_REQUIRES_REBAKE_AND_FIXED_CAPTURE'
manifest['geometry_source_version']='v046'
manifest['geometry_changes']=['Lowered the intervening rear slope into a continuous backyard approach',
    'Preserved road support within 3m of centerline',
    'Exterior gable kingpost, rafters and paired attic windows restore timber hierarchy',
    'Existing scene and six fixed cameras/daylight retained']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'backyard_grade_report.json').write_text(json.dumps({'changed_vertices':len(changed),
    'road_support_preserved':True,'status':'NOT_VISUALLY_ACCEPTED'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v047.blend'))
print('TAVERN_BACKYARD_GRADED',len(changed))
