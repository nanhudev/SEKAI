"""Authored road shoulders, embedded stones and a supported timber crossing."""
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

ROOT = Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
BASE = ROOT/'v038'
OUT = ROOT/'v039'
OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v038.blend'))
manifest = json.loads((BASE/'terrain_manifest.json').read_text())
rng = random.Random(26101239)
terrain = bpy.data.objects['SM_VIL_Valley_Terrain_v009']
bvh = BVHTree.FromObject(terrain, bpy.context.evaluated_depsgraph_get())
collection = terrain.users_collection[0]
road = bpy.data.objects['SM_VIL_Valley_CriticalRoute_v009']
road_bvh = BVHTree.FromObject(road, bpy.context.evaluated_depsgraph_get())
route = manifest['route_m']

def material(name, color):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    manifest['material_palette'][name] = list(color)
    return mat

dirt = [material('MV_Road_Earth_%02d'%i, c) for i,c in enumerate([
    (.25,.19,.115),(.29,.225,.14),(.33,.265,.17),(.36,.295,.195),
    (.31,.245,.155),(.39,.32,.22),(.275,.205,.13)])]
stones = [material('MV_Road_Stone_%02d'%i, c) for i,c in enumerate([
    (.34,.37,.32),(.40,.415,.35),(.46,.445,.365),(.30,.325,.285),(.49,.48,.41)])]
timber = [material('MV_Timber_Bridge_%02d'%i, c) for i,c in enumerate([
    (.27,.15,.065),(.33,.195,.085),(.23,.12,.049),(.38,.23,.11)])]
iron = material('MV_Metal_BlackIron',(.035,.043,.047))

def ground(x,y):
    hit = bvh.ray_cast(Vector((x,y,150)),Vector((0,0,-1)),260)[0]
    return hit.z if hit else None

def route_point(segment,t,lateral=0):
    a,b = route[segment:segment+2]
    d = Vector((b[0]-a[0],b[1]-a[1],0)).normalized()
    p = Vector(a).lerp(Vector(b),t)
    return p+Vector((-d.y,d.x,0))*lateral,d

def mesh_object(name,verts,faces,mats,indices):
    data = bpy.data.meshes.new(name+'_Geometry')
    data.from_pydata(verts,[],faces)
    data.update()
    for mat in mats: data.materials.append(mat)
    for face,index in zip(data.polygons,indices): face.material_index=index
    uv = data.uv_layers.new(name='UV_Metric')
    for face in data.polygons:
        normal = face.normal
        axes = (0,1) if abs(normal.z)>.6 else ((0,2) if abs(normal.y)>.5 else (1,2))
        for li in face.loop_indices:
            co = data.vertices[data.loops[li].vertex_index].co
            uv.data[li].uv = (co[axes[0]]*.7,co[axes[1]]*.7)
    obj = bpy.data.objects.new(name,data)
    collection.objects.link(obj)
    return obj

# Keep the shared road cross sections and its grade; break up the surface itself.
old_materials = list(road.data.materials)
for mat in dirt: road.data.materials.append(mat)
for vertex in road.data.vertices:
    x,y,z = vertex.co
    if not -49<y<-38 and math.hypot(x-20,y-13)>13.8:
        vertex.co.z += .017*math.sin(x*2.8+y*1.5)+.012*math.sin(y*4.2-x)
for face in road.data.polygons:
    center = sum((road.data.vertices[i].co for i in face.vertices),Vector())/len(face.vertices)
    if center.y < -12:
        signal = .5+.26*math.sin(center.x*.62+center.y*.39)+.17*math.sin(center.y*1.6-center.x*.73)
        face.material_index = len(old_materials)+max(0,min(6,int(signal*7)))
road.data.update()

verts=[];faces=[];indices=[]
def stone(center, radius, height, index):
    start=len(verts);n=rng.randrange(5,9);phase=rng.uniform(0,math.tau)
    ring=[rng.uniform(.8,1.12) for _ in range(n)]
    for z,scale in [(-height*.48,1.0),(height*.12,1.03),(height*.5,.75)]:
        for k in range(n):
            a=phase+k*math.tau/n
            verts.append((center[0]+math.cos(a)*radius*ring[k]*scale,
                          center[1]+math.sin(a)*radius*ring[k]*scale*rng.uniform(.74,1),center[2]+z))
    for j in range(2):
        for k in range(n):
            a=start+j*n+k;b=start+j*n+(k+1)%n
            faces.append((a,b,b+n,a+n));indices.append(index)
    faces.append(tuple(start+2*n+k for k in range(n)));indices.append(index)
    faces.append(tuple(start+k for k in reversed(range(n))));indices.append(index)

stone_count=0
for segment in range(len(route)-1):
    if segment==3:continue
    a,b=route[segment:segment+2];length=math.dist(a[:2],b[:2])
    for j in range(math.ceil(length*15)):
        t=rng.random();lateral=rng.uniform(-3.15,3.15)
        p,d=route_point(segment,t,lateral)
        if math.hypot(p.x-20,p.y-13)<14.0:continue
        # Stones concentrate in broken verges and between two worn wheel lanes.
        wear=min(abs(lateral-.9),abs(lateral+.9))
        if wear<.38 and rng.random()<.87:continue
        hit=road_bvh.ray_cast(Vector((p.x,p.y,150)),Vector((0,0,-1)),260)[0]
        z=hit.z if hit and abs(lateral)<2.45 else ground(p.x,p.y)
        if z is None:continue
        radius=rng.uniform(.09,.24) if abs(lateral)<2.2 else rng.uniform(.17,.46)
        stone((p.x,p.y,z+.006),radius,radius*.40,rng.randrange(len(stones)))
        stone_count+=1
stone_obj=mesh_object('SM_VIL_Road_EmbeddedStones',verts,faces,stones,indices)

# Broken, terrain-following dirt shoulders remove the ruler-straight road boundary.
verts=[];faces=[];indices=[]
for segment in range(len(route)-1):
    if segment==3:continue
    length=math.dist(route[segment][:2],route[segment+1][:2]);steps=math.ceil(length/.55)
    for side in [-1,1]:
        start=len(verts)
        for j in range(steps+1):
            t=j/steps
            for col in range(3):
                offset=side*(2.25+col*.37+.12*math.sin(j*.77+segment)*col)
                p,_=route_point(segment,t,offset);z=ground(p.x,p.y)
                if z is None:z=p.z
                # Preserve the paving and river opening.
                hide=math.hypot(p.x-20,p.y-13)<14 or -49<p.y<-38
                verts.append((p.x,p.y,z+(.007 if not hide else -.12)))
        for j in range(steps):
            for col in range(2):
                k=start+j*3+col;faces.append((k,k+3,k+4,k+1));indices.append(rng.randrange(len(dirt)))
shoulders=mesh_object('SM_VIL_Road_BrokenShoulders',verts,faces,dirt,indices)

# Build a full-span crossing along the existing endpoints, with visible structure.
verts=[];faces=[];indices=[]
a=Vector(route[3]);b=Vector(route[4]);direction=(b-a).normalized()
normal=Vector((-direction.y,direction.x,0));length=(b-a).length
def local(s,w,z):return a+direction*s+normal*w+Vector((0,0,z-a.z))
def beam(p,q,width,depth,index):
    tangent=(q-p).normalized();right=tangent.cross(Vector((0,0,1)))
    if right.length<.01:right=Vector((1,0,0))
    right.normalize();up=right.cross(tangent).normalized()
    start=len(verts)
    for center in [p,q]:
        for r,u in [(-1,-1),(1,-1),(1,1),(-1,1)]:
            verts.append(tuple(center+right*r*width/2+up*u*depth/2))
    for face in [(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]:
        faces.append(tuple(start+i for i in face));indices.append(index)

board_count=math.ceil(length/.35)
for j in range(board_count):
    s=(j+.5)*length/board_count
    beam(local(s,-2.48,3.075),local(s,2.48,3.075),length/board_count-.018,.20,j%4)
for w in [-1.85,0,1.85]:beam(local(.05,w,2.75),local(length-.05,w,2.75),.28,.40,2)
for side in [-1,1]:
    for j in range(13):
        s=.18+(length-.36)*j/12
        beam(local(s,side*2.52,2.82),local(s,side*2.52,4.30),.22,.24,j%4)
    for z in [3.56,4.13]:
        beam(local(.18,side*2.52,z),local(length-.18,side*2.52,z),.15,.20,0)
    # Paired king-post braces on either side, supported by mid-channel pier.
    for s0,s1 in [(0,length/2),(length/2,length)]:
        mid=(s0+s1)/2
        beam(local(s0+.3,side*1.85,1.1),local(mid,side*1.85,2.75),.24,.26,2)
        beam(local(s1-.3,side*1.85,1.1),local(mid,side*1.85,2.75),.24,.26,2)
legacy=bpy.data.objects.get('SM_VIL_EntranceBridge_Railing')
if legacy:bpy.data.objects.remove(legacy,do_unlink=True)
bridge=mesh_object('SM_VIL_EntranceBridge_Railing',verts,faces,timber,indices)
bevel=bridge.modifiers.new('Softened cut timber edges','BEVEL');bevel.width=.018;bevel.segments=2
bpy.context.view_layer.objects.active=bridge
bpy.ops.object.modifier_apply(modifier=bevel.name)

verts=[];faces=[];indices=[]
for s in [.65,length/2,length-.65]:
    for row in range(7):
        for column in range(6):
            w=(column-2.5)*.77+(row%2)*.12
            p=local(s,w,-.5+row*.49)
            stone(p,.48,.56,(row+column)%len(stones))
pier=mesh_object('SM_VIL_EntranceBridge_StoneSupports',verts,faces,stones,indices)

changed=[road,stone_obj,shoulders,bridge,pier]
assert stone_count>800 and board_count>70
assert manifest['cameras']==json.loads((BASE/'terrain_manifest.json').read_text())['cameras']
for name in manifest['assets']:
    if name not in [o.name for o in changed]:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
for obj in changed:
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.fbx(filepath=str(OUT/(obj.name+'.fbx')),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
    if obj.name not in manifest['assets']:manifest['assets'].append(obj.name)
manifest['stage']='ENTRANCE_GROUND_STRUCTURE_REVIEW_NOT_ACCEPTED'
manifest['geometry_source_version']='v038'
manifest['geometry_changes']=['Worn earth variations, embedded fieldstones and broken graded shoulders',
    'Full-span plank deck, aligned rails, stringers, braces and stone piers',
    'Fixed cameras, daylight, forest and landmarks retained']
manifest['entrance_detail_counts']={'embedded_stones':stone_count,'deck_boards':board_count}
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v039.blend'))
print('SEKAI_ENTRANCE_GROUND_SAVED',stone_count,board_count)
