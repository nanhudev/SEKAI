"""Continuous fitted route paving and grounded verges on the preserved village route."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import bmesh
import json
import math
import os
import random
import shutil
import sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder,export_mesh
ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));BASE,OUT=ROOT/'v064',ROOT/'v065'
OUT.mkdir(exist_ok=True);assert not (OUT/'terrain_manifest.json').exists()
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v064.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text());rng=random.Random(26101365)
bpy.context.view_layer.update()
road=bpy.data.objects['SM_VIL_Valley_CriticalRoute_v009']
terrain=bpy.data.objects['SM_VIL_Valley_Terrain_v009']
road_bvh=BVHTree.FromObject(road,bpy.context.evaluated_depsgraph_get())
terrain_bvh=BVHTree.FromObject(terrain,bpy.context.evaluated_depsgraph_get())
route=[Vector(p) for p in manifest['route_m']]
lengths=[(b-a).to_2d().length for a,b in zip(route,route[1:])]
stations=[0]
for length in lengths:stations.append(stations[-1]+length)
normals=[]
for a,b in zip(route,route[1:]):
    u=(b-a).to_2d().normalized();normals.append(Vector((-u.y,u.x)))
miters=[]
for i in range(len(route)):
    if i==0:miters.append(normals[0]);continue
    if i==len(route)-1:miters.append(normals[-1]);continue
    m=(normals[i-1]+normals[i]).normalized()
    miters.append(m/max(.72,m.dot(normals[i])))

def plan(s,w):
    segment=next((i for i in range(len(lengths)) if s<=stations[i+1]),len(lengths)-1)
    t=max(0,min(1,(s-stations[segment])/lengths[segment]))
    p=route[segment].lerp(route[segment+1],t)
    n=miters[segment].lerp(miters[segment+1],t)
    return Vector((p.x+n.x*w,p.y+n.y*w,p.z)),segment
def sample(bvh,x,y):
    hit=bvh.ray_cast(Vector((x,y,180)),Vector((0,0,-1)),350)[0]
    return hit.z if hit is not None else None
def elevation(p):
    road_z=sample(road_bvh,p.x,p.y);ground_z=sample(terrain_bvh,p.x,p.y)
    if road_z is None:return ground_z
    if ground_z is not None and ground_z-road_z<.20:return max(road_z,ground_z)
    return road_z
def distance(x,y):
    result=(1e9,-1)
    for i,(a,b) in enumerate(zip(route,route[1:])):
        d=(b-a).to_2d();t=max(0,min(1,Vector((x-a.x,y-a.y)).dot(d)/d.length_squared))
        gap=(Vector((x,y))-a.to_2d()-d*t).length
        if gap<result[0]:result=(gap,i)
    return result

# Remove whole old stone islands inside the newly paved corridor, not partial faces.
old=bpy.data.objects['SM_VIL_Road_EmbeddedStones']
bm=bmesh.new();bm.from_mesh(old.data);seen=set();remove=[];removed=0
for start in list(bm.verts):
    if start in seen:continue
    stack=[start];seen.add(start);group=[]
    while stack:
        vertex=stack.pop();group.append(vertex)
        for edge in vertex.link_edges:
            other=edge.other_vert(vertex)
            if other not in seen:seen.add(other);stack.append(other)
    center=sum((v.co for v in group),Vector())/len(group)
    gap,segment=distance(center.x,center.y)
    if gap<2.60 and segment!=3 and math.hypot(center.x-20,center.y-13)>13.1:
        remove.extend(group);removed+=1
if remove:bmesh.ops.delete(bm,geom=remove,context='VERTS')
bm.to_mesh(old.data);bm.free();old.data.update()

mesh=MeshBuilder();stone=[mesh.material('MV_Polish_Limestone_'+str(i)) for i in range(5)]
mortar=mesh.material('MV_Polish_Mortar')
piece_count=0;support_count=0
row_count=math.ceil(stations[-1]/.59)
for row in range(row_count):
    sa=row*stations[-1]/row_count+.008;sb=(row+1)*stations[-1]/row_count-.008
    center,segment=plan((sa+sb)*.5,0)
    if segment==3:continue
    for col in range(10):
        wl=-2.34+col*.468+.012;wr=wl+.444
        center,_=plan((sa+sb)*.5,(wl+wr)*.5)
        if math.hypot(center.x-20,center.y-13)<13.12:continue
        points=[plan(s,w)[0] for s,w in [(sa,wl),(sb,wl),(sb,wr),(sa,wr)]]
        # Clipped corner outlines follow shared mitered road sections at every bend.
        outline=[]
        for i,p in enumerate(points):
            prev=points[(i-1)%4];nxt=points[(i+1)%4]
            cut=rng.uniform(.018,.047)
            outline.extend([p+(prev-p).normalized()*cut,p+(nxt-p).normalized()*cut])
        center=sum(outline,Vector())/8
        tops=[]
        for p in outline:
            z=elevation(p)
            assert z is not None
            tops.append(z+.028)
        jitter=rng.uniform(-.003,.004)
        rings=[]
        for inset,dz in [(0,-.11),(0,-.013),(.009,0)]:
            ring=[]
            for p,z in zip(outline,tops):
                d=(p-center).to_2d().normalized()*inset
                ring.append(Vector((p.x-d.x,p.y-d.y,z+dz+jitter)))
            rings.append(ring)
        material=rng.choices(stone,[3,5,4,3,1])[0]
        mesh.face(list(reversed(rings[0])),material);mesh.face(rings[-1],material)
        for a,b in zip(rings,rings[1:]):
            for i in range(8):j=(i+1)%8;mesh.face([a[i],a[j],b[j],b[i]],material)
        piece_count+=1
    # Ground-reaching edge support, hidden where road and terrain already meet.
    for side in [-1,1]:
        p0,_=plan(sa,side*2.37);p1,_=plan(sb,side*2.37)
        p2,_=plan(sb,side*2.55);p3,_=plan(sa,side*2.55)
        if math.hypot(p0.x-20,p0.y-13)<13.5:continue
        top0=elevation(p0);top1=elevation(p1)
        z2=sample(terrain_bvh,p2.x,p2.y);z3=sample(terrain_bvh,p3.x,p3.y)
        if any(z is None for z in [top0,top1,z2,z3]):continue
        if max(top0-z3,top1-z2)>.1:
            lower=[Vector((p.x,p.y,z-.12)) for p,z in [(p0,z3),(p1,z2),(p2,z2),(p3,z3)]]
            upper=[Vector((p.x,p.y,z+.006)) for p,z in [(p0,top0),(p1,top1),(p2,z2),(p3,z3)]]
            mesh.face(list(reversed(lower)),mortar);mesh.face(upper,mortar)
            for i in range(4):j=(i+1)%4;mesh.face([lower[i],lower[j],upper[j],upper[i]],mortar)
            support_count+=1
new=mesh.build('SM_VIL_Route_FittedStone_v065')
bm=bmesh.new();bm.from_mesh(new.data)
bmesh.ops.triangulate(bm,faces=list(bm.faces))
bad=[f for f in bm.faces if f.calc_area()<1e-9]
if bad:bmesh.ops.delete(bm,geom=bad,context='FACES')
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
bm.to_mesh(new.data);bm.free();new.data.update()
changed=[old,new]
manifest['mesh_source_versions']={n:manifest.get('mesh_source_versions',{}).get(n,'v064') for n in manifest['assets'] if n!=old.name}
for n in manifest['assets']:
    if n!=old.name:os.link(BASE/(n+'.fbx'),OUT/(n+'.fbx'))
for f in BASE.glob('*.png'):os.link(f,OUT/f.name)
for obj in changed:export_mesh(obj,OUT/(obj.name+'.fbx'))
manifest['assets'].append(new.name);manifest['geometry_source_version']='v064'
manifest['geometry_changes']=['Continuous fitted stone courses follow existing mitered route and measured road height',
    'Only old loose stones inside the paving corridor removed; whole verge islands retained',
    'Ground-reaching road-edge support added where needed; bridge/plaza/tree/buildings/terrain/cameras/light retained']
manifest['stage']='CONTINUOUS_ROUTE_PAVING_REQUIRES_FIXED_AND_PLAYER_HEIGHT_REVIEW'
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'route_paving_report.json').write_text(json.dumps({'paving_pieces':piece_count,'grounded_edge_sections':support_count,
    'removed_old_stone_islands':removed,'removed_degenerate_faces':len(bad),'route_length_m':stations[-1],
    'status':'MODELED_NOT_VISUALLY_ACCEPTED'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v065.blend'))
print('CONTINUOUS_ROUTE_PAVING_SAVED',piece_count,support_count)
