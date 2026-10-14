"""Make the plaza and its connecting road share a continuous grading profile."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import shutil
import sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
source,version=args[:2] if len(args)>=2 else ('v032','v033')
BASE=ROOT/source;OUT=ROOT/version;OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/('SEKAI_Valley_Terrain_'+source+'.blend')))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
route=manifest['route_m']
if len(route)==12:route=route[:7]+[(19,0,8.2),(20,16,8.2),(20,26,8.2)]+route[8:]

def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def closest(x,y):
    best=(1e9,0)
    for a,b in zip(route,route[1:]):
        dx,dy=b[0]-a[0],b[1]-a[1];t=max(0,min(1,((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy)))
        distance=math.hypot(x-a[0]-dx*t,y-a[1]-dy*t)
        if distance<best[0]:best=(distance,a[2]+(b[2]-a[2])*t)
    return best
def river_x(y):return -29+13*math.sin(y/38)+3.3*math.sin(y/15)
terrain=bpy.data.objects['SM_VIL_Valley_Terrain_v009']
for v in terrain.data.vertices:
    if source!='v032':break
    x,y,z=v.co
    if -49<y<-38 or abs(x-river_x(y))<8:continue
    distance,level=closest(x,y)
    if distance<6:
        weight=1-smooth(2.8,6,distance)
        v.co.z=z*(1-weight)+(level-.022)*weight
    if math.hypot(x-20,y-13)<13.5:v.co.z=8.2
terrain.data.update()
colors=terrain.data.color_attributes['Color']
for p in terrain.data.polygons:
    if source!='v032':break
    slope=smooth(.12,.65,1-max(0,p.normal.z));p.use_smooth=p.normal.z>.7
    for li in p.loop_indices:
        v=terrain.data.vertices[terrain.data.loops[li].vertex_index].co
        variation=1+.055*math.sin(v.x*.061+v.y*.079)+.03*math.sin(v.x*.23-v.y*.12)
        grass=(.16,.27,.095);rock=(.25,.29,.30)
        colors.data[li].color=(*(variation*(grass[k]*(1-slope)+rock[k]*slope) for k in range(3)),1)
bvh=BVHTree.FromObject(terrain,bpy.context.evaluated_depsgraph_get())
old=bpy.data.objects['SM_VIL_Valley_CriticalRoute_v009'];collection=old.users_collection[0];mats=list(old.data.materials)
verts=[];faces=[];indices=[]
edge_normals=[]
for a,b in zip(route,route[1:]):
    direction=Vector((b[0]-a[0],b[1]-a[1])).normalized()
    edge_normals.append(Vector((-direction.y,direction.x)))
joint_normals=[edge_normals[0]]
for i in range(1,len(route)-1):
    normal=(edge_normals[i-1]+edge_normals[i]).normalized()
    joint_normals.append(normal/max(.6,normal.dot(edge_normals[i])))
joint_normals.append(edge_normals[-1])
for segment,(a,b) in enumerate(zip(route,route[1:])):
    dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy);normal=(-dy/length,dx/length)
    count=math.ceil(length/.5);start=len(verts);cols=11
    for j in range(count+1):
        t=j/count;cx=a[0]+dx*t;cy=a[1]+dy*t
        normal=joint_normals[segment]*(1-t)+joint_normals[segment+1]*t
        for i in range(cols):
            lateral=(i/(cols-1)*2-1)*2.5;x=cx+normal[0]*lateral;y=cy+normal[1]*lateral
            hit=bvh.ray_cast(Vector((x,y,120)),Vector((0,0,-1)),200)[0]
            z=hit.z+.008 if hit else a[2]+(b[2]-a[2])*t
            if segment==3:z=3.04
            if (j==0 and segment in [3,4]) or (j==count and segment in [2,3]):z=3.04
            if math.hypot(x-20,y-13)<13.65:z=8.10
            verts.append((x,y,z))
    for j in range(count):
        for i in range(cols-1):
            k=start+j*cols+i;faces.append((k,k+cols,k+cols+1,k+1));indices.append(1 if a[1]+dy*(j+.5)/count>-12 else 0)
mesh=bpy.data.meshes.new('Graded_CriticalRoad');mesh.from_pydata(verts,[],faces);mesh.update()
for mat in mats:mesh.materials.append(mat)
for p,index in zip(mesh.polygons,indices):p.material_index=index
old.data=mesh
for name in manifest['assets']:
    if name not in [terrain.name,old.name]:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
for obj in [terrain,old]:
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.fbx(filepath=str(OUT/(obj.name+'.fbx')),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
manifest['route_m']=route
manifest['stage']='ROUTE_GRADE_REQUIRES_COLOR_REBAKE_AND_REVIEW' if source=='v032' else 'ROAD_JOINT_REVIEW_NOT_ACCEPTED'
manifest['geometry_source_version']=source
manifest['geometry_changes']=['Continuous plaza approach and uphill road grading profile',
    'Road cross-section subdivision and actual terrain projection; plaza overlaps recessed below bedding',
    'Updated slope colors for rebake; tree, river, tavern, fixed cameras and daylight retained']
if source!='v032':manifest['geometry_changes']=['Shared mitered cross-sections close road joints',
    'Bridge and approach endpoint heights aligned; corrected per-face dirt/paving assignment',
    'Existing graded terrain, baked colors, tree, river, tavern, cameras and daylight retained']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('SEKAI_Valley_Terrain_'+version+'.blend')))
