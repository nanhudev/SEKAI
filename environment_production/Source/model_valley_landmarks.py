"""Place original village landmarks into the proven fixed-camera terrain scene."""
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
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(str(_SEKAI_ROOT / 'environment_production'))
VERSION=sys.argv[-1] if '--' in sys.argv else 'v010'
BASE=ROOT/'Terrain'/'v009'
OUT=ROOT/'Terrain'/VERSION
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v009.blend'))
scene=bpy.context.scene
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
for name in manifest['assets']:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
terrain=bpy.data.objects['SM_VIL_Valley_Terrain_v009']
bvh=BVHTree.FromObject(terrain,bpy.context.evaluated_depsgraph_get())
def ground(x,y):
    hit=bvh.ray_cast(Vector((x,y,120)),Vector((0,0,-1)),200)[0]
    return hit.z if hit else 0

collection=bpy.data.collections.new('SEKAI_VILLAGE_LANDMARKS')
scene.collection.children.link(collection)
rng=random.Random(74129)
new_assets=[]
def material(name,color):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes=True;m.diffuse_color=(*color,1)
    bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Roughness'].default_value=.85
    return m
bark=material('MV_Tree_Bark',(.25,.20,.13))
leaf_mats=[material('MV_Foliage_Leaf_%02d'%i,c) for i,c in enumerate([
    (.16,.26,.055),(.22,.34,.08),(.31,.39,.09),(.12,.22,.065),(.27,.36,.06)])]
stone_mats=[material('MV_Plaza_Stone_%02d'%i,c) for i,c in enumerate([
    (.43,.45,.40),(.34,.38,.36),(.48,.46,.38),(.38,.41,.39)])]
wood=material('MV_Bridge_Timber',(.27,.17,.085))

def mesh(name,vertices,faces,mats,indices=None,smooth=False):
    data=bpy.data.meshes.new(name+'_Geometry');data.from_pydata(vertices,[],faces);data.update()
    obj=bpy.data.objects.new(name,data);collection.objects.link(obj)
    for m in mats:data.materials.append(m)
    for i,p in enumerate(data.polygons):
        p.material_index=indices[i] if indices else 0;p.use_smooth=smooth
    new_assets.append(obj);return obj

wood_v=[];wood_f=[]
def tube(points,radii,segments=14):
    start=len(wood_v)
    for j,point in enumerate(points):
        before=Vector(points[max(0,j-1)]);after=Vector(points[min(len(points)-1,j+1)])
        tangent=(after-before).normalized()
        right=tangent.cross(Vector((0,1,0))).normalized();up=right.cross(tangent).normalized()
        for i in range(segments):
            angle=i*math.tau/segments
            radius=radii[j]*(1+.08*math.sin(i*4.1+j*.7))
            wood_v.append(tuple(Vector(point)+radius*(right*math.cos(angle)+up*math.sin(angle))))
    for j in range(len(points)-1):
        for i in range(segments):
            a=start+j*segments+i;b=start+j*segments+(i+1)%segments
            wood_f.append((a,b,b+segments,a+segments))
    wood_f.append(tuple(start+(len(points)-1)*segments+i for i in range(segments)))

tx,ty,tz=-1,47,13.4
tube([(tx,ty,tz-.25),(tx+.3,ty+.2,tz+2),(tx-.2,ty+.4,tz+5),
      (tx+.4,ty-.2,tz+8),(tx+1.1,ty+.1,tz+11),(tx+1.6,ty+.7,tz+15)],
     [3.0,2.25,1.8,1.55,1.25,.75],22)
for i in range(9):
    angle=i*math.tau/9+.25;dx,dy=math.cos(angle),math.sin(angle)
    radius=8+rng.uniform(-1,2)
    tube([(tx+dx*1.3,ty+dy*1.3,tz+2),(tx+dx*4,ty+dy*4,tz+.7),
          (tx+dx*radius,ty+dy*radius,ground(tx+dx*radius,ty+dy*radius)+.08)], [.95,.52,.10],12)
crowns=[]
for i in range(12):
    angle=i*math.tau/12+.2;dx,dy=math.cos(angle),math.sin(angle)
    reach=8+rng.uniform(-1,3);lift=18+rng.uniform(-1,5)
    start=(tx+.5,ty,tz+7+(i%3)*2)
    end=(tx+dx*reach,ty+dy*reach,tz+lift)
    middle=(tx+dx*4,ty+dy*4,tz+12+(i%3))
    tube([start,middle,(tx+dx*7,ty+dy*7,tz+lift-2),end],[.85,.58,.30,.08],12)
    for sign in [-1,1]:
        spread=Vector((-dy,dx,0))*sign*2.8
        fork=tuple(Vector(end)+spread+Vector((0,0,1.5)))
        tube([middle,end,fork],[.38,.17,.04],9)
    crowns.append((*end,4.5+rng.uniform(-.6,.8),2.3+rng.uniform(-.2,.8)))
crowns.append((tx+.7,ty+.5,tz+24,4.7,2.5))
tree=mesh('SM_VIL_Hero_AncientTree_Wood',wood_v,wood_f,[bark],smooth=True)

lv=[];lf=[];li=[]
for cx,cy,cz,radius,depth in crowns:
    for i in range(1600):
        angle=rng.random()*math.tau;r=math.sqrt(rng.random())
        x=cx+math.cos(angle)*radius*r;y=cy+math.sin(angle)*radius*r
        z=cz+rng.uniform(-1,1)*depth*math.sqrt(max(.05,1-r*r))
        heading=rng.random()*math.tau
        right=Vector((math.cos(heading),math.sin(heading),rng.uniform(-.7,.7))).normalized()
        cross=right.cross(Vector((0,0,1))).normalized()
        length=rng.uniform(.26,.48);width=length*.48;center=Vector((x,y,z))
        start=len(lv)
        for a,b,h in [(-1,0,0),(-.38,-1,.025),(.45,-.7,.035),(1,0,0),(.45,.7,.035),(-.38,1,.025)]:
            lv.append(tuple(center+right*a*length+cross*b*width+Vector((0,0,h))))
        for face in [(0,1,2),(0,2,3),(0,3,4),(0,4,5)]:
            lf.append(tuple(start+k for k in face));li.append(rng.randrange(len(leaf_mats)))
mesh('SM_VIL_Hero_AncientTree_Foliage',lv,lf,leaf_mats,li)

pv=[];pf=[];pi=[]
def block(center,size,angle=0,index=0):
    start=len(pv);cx,cy,cz=center;sx,sy,sz=size
    for x,y,z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]:
        x*=sx*.5;y*=sy*.5
        pv.append((cx+x*math.cos(angle)-y*math.sin(angle),cy+x*math.sin(angle)+y*math.cos(angle),cz+z*sz*.5))
    for face in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]:
        pf.append(tuple(start+k for k in face));pi.append(index)

for ring in range(1,17):
    radius=ring*.78;count=math.ceil(math.tau*radius/.95)
    for i in range(count):
        a=i*math.tau/count+(ring%2)*.03
        x=20+radius*math.cos(a);y=13+radius*math.sin(a)
        block((x,y,ground(x,y)+.025+rng.uniform(-.01,.01)),(.74,math.tau*radius/count-.05,.10),a,rng.randrange(4))
for i in range(16):
    x=4;y=24+i*.85;top=9.2+(i+1)*.27
    block((x,y,top-.15),(4.0,.85,.30),0,i%4)
for i in range(80):
    a=i*math.tau/80;x=tx+12*math.cos(a);y=ty+12*math.sin(a)
    base=ground(x,y)-.15
    for course in range(max(0,math.ceil((13.45-base)/.42))):
        block((x,y,base+course*.42+.2),(.90,.65,.40),a+math.pi/2,(i+course)%4)
mesh('SM_VIL_Plaza_PavingAndTreeTerrace',pv,pf,stone_mats,pi)

pv=[];pf=[];pi=[]
for x in [-46,-43,-40,-37,-34,-31,-28]:
    y=-45+(x+46)*3/28
    for sign in [-1,1]:
        block((x,y+sign*2.6,3.72),(.22,.22,1.45))
for sign in [-1,1]:
    block((-37,-44+sign*2.6,4.20),(18.2,.18,.20),math.atan2(3,28))
    block((-37,-44+sign*2.6,3.65),(18.2,.14,.16),math.atan2(3,28))
mesh('SM_VIL_EntranceBridge_Railing',pv,pf,[wood])

with bpy.data.libraries.load(str(ROOT/'Versions'/'v005'/'SEKAI_VillageKit_v005.blend'),link=False) as (src,dst):
    dst.objects=list(src.objects)
hero_parts=[]
transform=Matrix.Translation(Vector((38,42,11.3)))@Matrix.Rotation(-.35,4,'Z')
for obj in dst.objects:
    if obj and obj.type=='MESH':
        collection.objects.link(obj);hero_parts.append(obj)
bpy.context.view_layer.update()
for obj in hero_parts:obj.matrix_world=transform@obj.matrix_world
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
for obj in hero_parts:obj.select_set(True)
bpy.context.view_layer.objects.active=hero_parts[0]
bpy.ops.object.join()
hero=bpy.context.object;hero.name='SM_VIL_Hero_Tavern_Placed'
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
new_assets.append(hero)

for obj in new_assets:
    if not obj.data.uv_layers:
        uv=obj.data.uv_layers.new(name='UV_Metric')
        for p in obj.data.polygons:
            axis=max(range(3),key=lambda i:abs(p.normal[i]))
            for loop in p.loop_indices:
                v=obj.data.vertices[obj.data.loops[loop].vertex_index].co
                a,b=(v.y,v.z) if axis==0 else ((v.x,v.z) if axis==1 else (v.x,v.y))
                uv.data[loop].uv=(a*.5,b*.5)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.fbx(filepath=str(OUT/(obj.name+'.fbx')),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
manifest['assets'] += [o.name for o in new_assets]
manifest['material_palette']={m.name:list(m.diffuse_color)[:3] for o in new_assets for m in o.data.materials if m}
manifest['acceptance_reference']='SEKAI_REFERENCES/MASTER/acceptance_stylized_20261012.png'
manifest['stage']='LANDMARK_COMPOSITION_NOT_VISUALLY_ACCEPTED'
manifest['known_gaps']=['reference composition fidelity','forge and other architecture','terrain geology and PBR',
    'tree crown density and branch transitions','water shading and waterfall foam','walkability verification']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('SEKAI_Valley_Terrain_'+VERSION+'.blend')))
print('SEKAI_LANDMARK_COMPOSITION_SAVED',OUT)
