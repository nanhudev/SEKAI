"""Masonry bridge skin, shallower stone joints, rooted planting and a distant eastern estate."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import random
import shutil
import sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder,export_mesh

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));BASE,OUT=ROOT/'v060',ROOT/'v061'
OUT.mkdir(exist_ok=True);assert not (OUT/'terrain_manifest.json').exists()
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v060.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text());rng=random.Random(26101361)
bpy.context.view_layer.update()
surfaces=[BVHTree.FromObject(bpy.data.objects[n],bpy.context.evaluated_depsgraph_get()) for n in
    ['SM_VIL_Valley_Terrain_v009','SM_VIL_Valley_Surroundings']]
def ground(x,y):
    hits=[b.ray_cast(Vector((x,y,300)),Vector((0,0,-1)),600)[0] for b in surfaces]
    zs=[p.z for p in hits if p is not None];assert zs,(x,y)
    return max(zs)
def join(old,new):
    new.data.uv_layers.active.name=old.data.uv_layers.active.name
    bpy.ops.object.select_all(action='DESELECT');old.select_set(True);new.select_set(True)
    bpy.context.view_layer.objects.active=old;bpy.ops.object.join()

plaza=bpy.data.objects['SM_VIL_Plaza_PavingAndTreeTerrace']
lowered=0
for vertex in plaza.data.vertices:
    p=vertex.co
    if math.hypot(p.x-20,p.y-13)<14.2 and 8.21<p.z<8.30:
        p.z-=.016;lowered+=1
plaza.data.update()
manifest['material_palette']['MV_Polish_Mortar']=[.185,.18,.145]

mesh=MeshBuilder();stone=[mesh.material('MV_Polish_Limestone_'+str(i)) for i in range(5)]
a,b=[Vector(manifest['route_m'][i]) for i in [3,4]]
u=(b-a).normalized();v=Vector((-u.y,u.x,0));length=(b-a).length
angle=math.atan2(u.y,u.x)
def point(t,w,z):return a+u*t+v*w+Vector((0,0,z-a.z))
def opening(t):
    x=(t-5.45)/5.20
    return .10+2*math.sqrt(max(0,1-x*x)) if abs(x)<1 else ground(*point(t,0,0)[:2])-.25
count=math.ceil(length/.54)
for side in [-1,1]:
    for row in range(13):
        bottom=-.48+row*.275;top=bottom+.26
        for col in range(count+1):
            t=(col+.5*(row%2))*length/count
            if t<.10 or t>length-.10:continue
            lo=max(bottom,opening(t)+.012)
            if top-lo<.06:continue
            p=point(t,side*2.485,(top+lo)*.5)
            mesh.block(tuple(p),(length/count-.014,.27,top-lo),rng.choice(stone),angle=angle,bevel=.033)
    # Dressed voussoirs follow the arch intrados; they are real extruded wedges.
    for i in range(31):
        s0=.30+(10.25)*i/31;s1=.30+(10.25)*(i+1)/31
        z0=opening(s0);z1=opening(s1)
        ztop0=min(3.035,z0+.33);ztop1=min(3.035,z1+.33)
        ring=[]
        for w in [side*2.43,side*2.72]:
            ring.append([point(s0+.010,w,z0),point(s1-.010,w,z1),point(s1-.010,w,ztop1),point(s0+.010,w,ztop0)])
        m=rng.choice(stone)
        if side>0:
            mesh.face(list(reversed(ring[0])),m);mesh.face(ring[1],m)
        else:
            mesh.face(ring[0],m);mesh.face(list(reversed(ring[1])),m)
        for j in range(4):k=(j+1)%4;mesh.face([ring[0][j],ring[0][k],ring[1][k],ring[1][j]],m)
support=bpy.data.objects['SM_VIL_EntranceBridge_StoneSupports']
join(support,mesh.build('BRIDGE_MASONRY_SKIN'))

# Real soil follows the irregular root footprint, with low fern/grass edges.
plants=MeshBuilder()
soil=plants.material('MV_Root_Soil',(.105,.095,.06))
leaf=plants.material('MV_Foliage_Leaf_UnderstoryMid')
sunleaf=plants.material('MV_Foliage_Leaf_UnderstorySun')
stem=plants.material('MV_Foliage_Leaf_UnderstoryStem')
manifest['material_palette']['MV_Root_Soil']=[.105,.095,.06]
origin=Vector((-1,47,13.4))
ring=[]
for i in range(72):
    t=i*math.tau/72;r=3.7+.24*math.sin(t*3)+.32*math.sin(t*7+.5)
    x,y=-1+r*math.cos(t),47+r*math.sin(t)
    ring.append(Vector((x,y,ground(x,y)+.009)))
center=Vector((-1,47,ground(-1,47)+.009))
for p,q in zip(ring,ring[1:]+ring[:1]):plants.face([center,p,q],soil)
def frond(root,heading,size,material):
    root=Vector(root);direction=Vector((math.cos(heading),math.sin(heading),0));cross=Vector((-direction.y,direction.x,0))
    points=[root+direction*(i/5*size)+Vector((0,0,.55*size*math.sin(i/5*math.pi*.80))) for i in range(6)]
    plants.tube(points,[.008*(1-i/7) for i in range(6)],stem,4)
    for i,p in enumerate(points[1:-1],1):
        for side in [-1,1]:
            end=p+cross*side*size*.17+direction*size*.06
            mid=(p+end)*.5+Vector((0,0,.015))
            plants.face([p,mid-direction*size*.06,end,mid+direction*size*.06],material)
for i in range(85):
    t=i*2.399;r=rng.uniform(3.8,8.8)
    x,y=-1+r*math.cos(t),47+r*math.sin(t);z=ground(x,y)
    for j in range(5):frond((x,y,z),t+j*math.tau/5,rng.uniform(.30,.64),leaf if j%3 else sunleaf)
for angle0 in [-2.9,-2.4,-1.9,-.92,-.58,-.2,.4,1.0,1.65,2.4]:
    x,y=-1+12.45*math.cos(angle0),47+12.45*math.sin(angle0)
    fall=min(rng.uniform(1.6,3.0),13.50-ground(x,y)-.20)
    if fall<.30:continue
    for strand in range(3):
        angle=angle0+(strand-1)*.04;points=[]
        for j in range(14):
            t=j/13;a=angle+.025*math.sin(t*7+strand)
            radius=12.47+.06*(1-t)
            points.append(Vector((-1+radius*math.cos(a),47+radius*math.sin(a),13.56-fall*t)))
        plants.tube(points,[.010]*14,stem,5)
        tangent=Vector((-math.sin(angle),math.cos(angle),-.1))
        for j,p in enumerate(points):
            for sign in [-1,1]:
                end=p+tangent*sign*.17+Vector((0,0,-.10))
                mid=(p+end)*.5
                plants.face([p,mid+Vector((0,0,.055)),end,mid-Vector((0,0,.055))],leaf if j%3 else sunleaf)
rootbed=plants.build('SM_VIL_TreeRoot_Grounding_v061')
manifest['noncollision_assets'].append(rootbed.name)

# Relocate the rough eastern landmark by its terrain-supported plan, not its camera.
estate=bpy.data.objects['SM_VIL_BorderCount_Estate_v060']
old_report=json.loads((BASE/'estate_report.json').read_text())
new_center=Vector((207,167,0))
new_base=max(ground(207+x,167+y) for x in [-23,0,23] for y in [-17,0,17])+.4
offset=Vector((55,-20,new_base-old_report['center_m'][2]))
for vertex in estate.data.vertices:vertex.co+=offset
foundation=MeshBuilder();m=foundation.material('MV_Estate_Stone_Warm')
for side in [-1,1]:
    for i in range(11):
        x,y=207+side*23,167-17+i*3.4;bottom=ground(x,y)-.7
        foundation.block((x,y,(new_base+bottom)*.5),(1.9,3.45,new_base-bottom),m,bevel=.08)
for i in range(14):
    x,y=207-23+i*46/13,150;bottom=ground(x,y)-.7
    foundation.block((x,y,(new_base+bottom)*.5),(3.65,2,new_base-bottom),m,bevel=.08)
join(estate,foundation.build('ESTATE_RESEATED_FOUNDATION'))
viaduct=bpy.data.objects['SM_VIL_BorderCount_Viaduct_v060']
old_a=Vector((83,133,0));old_b=Vector((141,169,0));old_u=(old_b-old_a).normalized();old_v=Vector((-old_u.y,old_u.x,0))
new_b=Vector((196,149,0));new_u=(new_b-old_a).normalized();new_v=Vector((-new_u.y,new_u.x,0))
old_length=(old_b-old_a).length;new_length=(new_b-old_a).length
deck=max(new_base,max(ground(*(old_a+(new_b-old_a)*i/24)[:2]) for i in range(25))+4)
for vertex in viaduct.data.vertices:
    p=vertex.co;delta=p-old_a;t=delta.dot(old_u);width=delta.dot(old_v)
    q=old_a+new_u*(t*new_length/old_length)+new_v*width
    vertex.co=Vector((q.x,q.y,p.z+deck-old_report['viaduct_deck_m']))
piers=MeshBuilder();m=piers.material('MV_Estate_Stone_Warm')
for i in range(8):
    t=(i/8+.25/old_length)*new_length;p=old_a+new_u*t;bottom=ground(p.x,p.y)-.7
    piers.block((p.x,p.y,(deck+bottom)*.5),(2.2*new_length/old_length,7.0,deck-bottom),m,angle=math.atan2(new_u.y,new_u.x),bevel=.1)
join(viaduct,piers.build('VIADUCT_RESEATED_PIERS'))

changed=[plaza,support,estate,viaduct,rootbed]
manifest['mesh_source_versions']={name:manifest.get('mesh_source_versions',{}).get(name,'v060') for name in manifest['assets'] if name not in [o.name for o in changed]}
for name in manifest['assets']:
    if name not in [o.name for o in changed]:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
for obj in changed:
    export_mesh(obj,OUT/(obj.name+'.fbx'))
    if obj.name not in manifest['assets']:manifest['assets'].append(obj.name)
manifest['authored_detail_textures']+=['T_Polish_BarkColor','T_Polish_BarkNormal']
manifest['material_properties']['MV_Tree_Bark']={'detail_color_map':'T_Polish_BarkColor','detail_normal_map':'T_Polish_BarkNormal'}
manifest['atmosphere_trial'].update({'coverage':-.04,'global_scale':192.0,'global_density':.008})
manifest['geometry_source_version']='v060';manifest['stage']='BRIDGE_ROOT_AND_SKY_DETAIL_REQUIRES_REVIEW'
manifest['geometry_changes']=['Dressed bridge facade courses and arch voussoirs replace flat mortar exterior',
    'Shallower paving joints with warmer mortar; root soil, ferns and masonry-hugging ivy',
    'Terrain-supported count estate and viaduct shifted to the eastern background; fixed cameras retained']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'detail_report.json').write_text(json.dumps({'lowered_paving_vertices':lowered,'estate_center_m':[207,167,new_base],
    'viaduct_deck_m':deck,'viaduct_span_m':new_length,'status':'NOT_VISUALLY_ACCEPTED'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v061.blend'))
print('BRIDGE_ROOT_ESTATE_DETAIL_SAVED')
