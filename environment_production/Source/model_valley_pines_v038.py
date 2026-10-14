"""Original branched conifers and terrain-aware forest composition."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import random
import shutil
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
BASE=ROOT/'v037';OUT=ROOT/'v038';OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v037.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
terrain=bpy.data.objects['SM_VIL_Valley_Terrain_v009'];collection=terrain.users_collection[0]
bvh=BVHTree.FromObject(terrain,bpy.context.evaluated_depsgraph_get())
wood=bpy.data.materials['MV_Tree_Bark']
leaf_mats=[]
for i,color in enumerate([(.09,.205,.095),(.145,.265,.075),(.19,.30,.085)]):
    name='MV_Foliage_Leaf_Pine_%d'%i
    mat=bpy.data.materials.get(name) or bpy.data.materials.new(name);mat.diffuse_color=(*color,1)
    leaf_mats.append(mat);manifest['material_palette'][name]=list(color)
library=[]
for variant,(height,radius) in enumerate([(14,3.15),(18,3.9),(21,4.2)]):
    rng=random.Random(26101238+variant);verts=[];faces=[];indices=[]
    def tube(points,radii,sides=8):
        start=len(verts)
        for j,p in enumerate(points):
            before=points[max(0,j-1)];after=points[min(len(points)-1,j+1)]
            tangent=(after-before).normalized();helper=Vector((0,1,0))
            if abs(tangent.y)>.94:helper=Vector((1,0,0))
            right=tangent.cross(helper).normalized();up=right.cross(tangent).normalized()
            for k in range(sides):
                a=k*math.tau/sides;verts.append(tuple(p+radii[j]*(right*math.cos(a)+up*math.sin(a))))
        for j in range(len(points)-1):
            for k in range(sides):
                a=start+j*sides+k;b=start+j*sides+(k+1)%sides
                faces.append((a,b,b+sides,a+sides));indices.append(0)
        faces.append(tuple(start+(len(points)-1)*sides+k for k in range(sides)));indices.append(0)
    trunk=[Vector((.13*math.sin(i*.4+variant),.09*math.cos(i*.7),height*i/12)) for i in range(13)]
    tube(trunk,[.40*(1-i/13)**1.1+.025 for i in range(13)],14)
    def spray(center,direction,length,width):
        start=len(verts);right=Vector((-direction.y,direction.x,0)).normalized()
        tilt=Vector((0,0,rng.uniform(-.25,.18)))
        for j in range(6):
            t=j/5;spine=center+direction*length*t+Vector((0,0,.15*math.sin(t*math.pi)))
            spread=width*math.sin(math.pi*(.08+t*.90))*(1+.22*math.sin(j*2+variant))
            for side in [-1,0,1]:verts.append(tuple(spine+right*side*spread+tilt*abs(side)))
        index=1+rng.randrange(3)
        for j in range(5):
            k=start+j*3
            faces.extend([(k,k+3,k+4,k+1),(k+1,k+4,k+5,k+2)]);indices.extend([index,index])
    for tier in range(17):
        z=height*(.18+.79*tier/16);reach=radius*(1-z/height)**.62
        count=8 if tier<12 else 6;phase=tier*.69+rng.uniform(-.15,.15)
        for arm in range(count):
            a=arm*math.tau/count+phase;direction=Vector((math.cos(a),math.sin(a),0))
            length=reach*rng.uniform(.82,1.17);drop=rng.uniform(.20,.65)
            root=Vector((0,0,z));middle=root+direction*length*.48+Vector((0,0,-drop*.35))
            tip=root+direction*length+Vector((0,0,-drop))
            tube([root,middle,tip],[.09*(1-z/height)+.018,.035,.008],6)
            for j in range(16):
                t=.15+j*.053;center=root+direction*length*t+Vector((0,0,-drop*t))
                sign=1 if j%2 else -1;angle=a+sign*rng.uniform(.48,1.05)
                lateral=Vector((math.cos(angle),math.sin(angle),rng.uniform(-.15,.22))).normalized()
                spray(center,lateral,rng.uniform(.50,.90)*(1-t*.3),rng.uniform(.18,.32))
    for j in range(8):
        a=j*math.tau/8;spray(Vector((0,0,height-.8)),Vector((math.cos(a)*.3,math.sin(a)*.3,.95)).normalized(),1.0,.20)
    mesh=bpy.data.meshes.new('Pine_BranchAndNeedleSprays_%d'%variant);mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new('SM_VIL_Pine_Library_%d'%variant,mesh);collection.objects.link(obj)
    for mat in [wood]+leaf_mats:mesh.materials.append(mat)
    for p,index in zip(mesh.polygons,indices):p.material_index=index;p.use_smooth=index==0
    uv=mesh.uv_layers.new(name='UV_Pine_Metric')
    for p in mesh.polygons:
        for li in p.loop_indices:
            v=mesh.vertices[mesh.loops[li].vertex_index].co;uv.data[li].uv=(v.x*.4+v.y*.2,v.z*.4)
    library.append(obj)

def route_distance(x,y):
    best=1e9
    for a,b in zip(manifest['route_m'],manifest['route_m'][1:]):
        dx,dy=b[0]-a[0],b[1]-a[1];t=max(0,min(1,((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy)))
        best=min(best,math.hypot(x-a[0]-dx*t,y-a[1]-dy*t))
    return best
def river_x(y):return -29+13*math.sin(y/38)+3.3*math.sin(y/15)
rng=random.Random(261012381);candidates=[]
for side in [-1,1]:
    for row in range(26):
        for column in range(7):
            x=side*(36+column*10+rng.uniform(-3.8,3.8));y=-112+row*10+rng.uniform(-3.8,3.8)
            if route_distance(x,y)<8 or abs(x-river_x(y))<12:continue
            if any(((x-p['center_m'][0])/(p['radius_m'][0]+3))**2+
                   ((y-p['center_m'][1])/(p['radius_m'][1]+3))**2<1 for p in manifest['pads']):continue
            hit,normal,_,_=bvh.ray_cast(Vector((x,y,140)),Vector((0,0,-1)),240)
            if hit is None or normal.z<.80 or hit.z<1:continue
            candidates.append((x,y,hit.z-.12))
rng.shuffle(candidates);instances=[]
for position in candidates:
    if any(math.dist(position[:2],row['position_m'][:2])<7.8 for row in instances):continue
    instances.append({'mesh':library[len(instances)%3].name,'position_m':list(position),
                      'yaw_degrees':rng.uniform(-180,180),'scale':rng.uniform(.72,1.15)})
    if len(instances)>=105:break
assert len(instances)>=35,'Forest composition selection unexpectedly empty'
for name in manifest['assets']:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
for obj in library:
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.fbx(filepath=str(OUT/(obj.name+'.fbx')),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
    obj.hide_render=True;obj.hide_viewport=True
manifest['assets'].extend(o.name for o in library)
manifest['library_assets']=[o.name for o in library];manifest['instances']=instances
manifest['stage']='FOREST_COMPOSITION_REVIEW_NOT_ACCEPTED'
manifest['geometry_source_version']='v037'
manifest['geometry_changes']=['Original branched conifer variants with serrated needle sprays',
    'Terrain-aware clustered forest on village slopes; roads, river and functional pads kept open',
    'Existing cliff geometry, landmarks, fixed cameras and daylight unchanged']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v038.blend'))
print('SEKAI_FOREST_REVIEW_INSTANCES',len(instances))
