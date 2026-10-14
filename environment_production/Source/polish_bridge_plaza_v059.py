"""Reference-led stone crossing, fitted paving and ancient-tree retaining masonry."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import bmesh
import json
import math
import random
import shutil
import sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder, export_mesh

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
BASE,OUT=ROOT/'v058',ROOT/'v059'
OUT.mkdir(exist_ok=True)
assert not (OUT/'terrain_manifest.json').exists()
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v058.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
bpy.context.view_layer.update()
terrain=BVHTree.FromObject(bpy.data.objects['SM_VIL_Valley_Terrain_v009'],bpy.context.evaluated_depsgraph_get())
rng=random.Random(26101359)
palette={
 'MV_Polish_Limestone_0':(.25,.265,.24),'MV_Polish_Limestone_1':(.30,.29,.25),
 'MV_Polish_Limestone_2':(.34,.32,.27),'MV_Polish_Limestone_3':(.27,.29,.28),
 'MV_Polish_Limestone_4':(.37,.35,.29),'MV_Polish_Mortar':(.14,.135,.11),
 'MV_Polish_Moss':(.12,.19,.052),
}
manifest['material_palette'].update({k:list(v) for k,v in palette.items()})
manifest['authored_detail_textures']=['T_Polish_StoneColor','T_Polish_StoneNormal','T_Polish_StoneRoughness']
for name in list(palette)[:5]:
    manifest.setdefault('material_properties',{})[name]={'detail_color_map':'T_Polish_StoneColor',
        'detail_normal_map':'T_Polish_StoneNormal','detail_roughness_map':'T_Polish_StoneRoughness'}

def ground(x,y):
    hit=terrain.ray_cast(Vector((x,y,180)),Vector((0,0,-1)),350)[0]
    assert hit is not None,(x,y)
    return hit.z

def builder():
    mesh=MeshBuilder()
    stones=[mesh.material(k,c) for k,c in list(palette.items())[:5]]
    mortar=mesh.material('MV_Polish_Mortar',palette['MV_Polish_Mortar'])
    return mesh,stones,mortar

def cut_stone(mesh,x,y,z,w,d,h,material,angle=0):
    # Unequal chipped corners, rather than identical bevelled dominoes.
    c=[rng.uniform(.025,.085) for _ in range(4)]
    outline=[(-w/2+c[0],-d/2),(w/2-c[1],-d/2),(w/2,-d/2+c[1]),
        (w/2,d/2-c[2]),(w/2-c[2],d/2),(-w/2+c[3],d/2),
        (-w/2,d/2-c[3]),(-w/2,-d/2+c[0])]
    rings=[]
    for inset,height in [(0,-h/2),(0,h/2-.026),(.026,h/2)]:
        rings.append([Vector((x+(px-math.copysign(inset,px))*math.cos(angle)-(py-math.copysign(inset,py))*math.sin(angle),
            y+(px-math.copysign(inset,px))*math.sin(angle)+(py-math.copysign(inset,py))*math.cos(angle),z+height)) for px,py in outline])
    mesh.face(list(reversed(rings[0])),material);mesh.face(rings[-1],material)
    for a,b in zip(rings,rings[1:]):
        for i in range(8):j=(i+1)%8;mesh.face([a[i],a[j],b[j],b[i]],material)

# Remove only the lower circular paving and the old tree-wall ring. Stairs remain.
plaza=bpy.data.objects['SM_VIL_Plaza_PavingAndTreeTerrace']
bm=bmesh.new();bm.from_mesh(plaza.data)
remove=[]
for face in bm.faces:
    p=face.calc_center_median();top=max(v.co.z for v in face.verts)
    lower=math.hypot(p.x-20,p.y-13)<14.2 and top<8.45
    wall=10.7<math.hypot(p.x+1,p.y-47)<13.4 and p.y>35.8 and top<13.75
    if lower or wall:remove.append(face)
bmesh.ops.delete(bm,geom=remove,context='FACES')
bm.to_mesh(plaza.data);bm.free();plaza.data.update()

# Fitted stones: radial medallion seeds transition to staggered irregular flags.
mesh,stones,mortar=builder();seeds=[Vector((20,13))]
for row in range(1,9):
    r=row*.56;count=round(math.tau*r/.68)
    for i in range(count):
        a=(i+.5*(row%2))*math.tau/count
        seeds.append(Vector((20+r*math.cos(a),13+r*math.sin(a))))
for row in range(-13,14):
    for col in range(-12,13):
        x=col*1.03+(row%2)*.515+rng.uniform(-.18,.18)
        y=row*1.0+rng.uniform(-.18,.18)
        if 5.10<math.hypot(x,y)<12.95:seeds.append(Vector((20+x,13+y)))
boundary=[Vector((20+13.05*(1+.008*math.sin(i*.51))*math.cos(i*math.tau/96),
                         13+13.05*(1+.008*math.sin(i*.51))*math.sin(i*math.tau/96))) for i in range(96)]

def clip(poly,n,k):
    result=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        da=a.dot(n)-k;db=b.dot(n)-k
        if da<=0:result.append(a)
        if (da<0)!=(db<0):result.append(a+(b-a)*(da/(da-db)))
    return result

mesh.face([Vector((p.x,p.y,8.202)) for p in boundary],mortar)
for seed in seeds:
    poly=boundary[:]
    for other in sorted((p for p in seeds if p is not seed),key=lambda p:(p-seed).length_squared)[:32]:
        poly=clip(poly,other-seed,(other.length_squared-seed.length_squared)*.5)
        if len(poly)<3:break
    if len(poly)<3:continue
    center=sum(poly,Vector((0,0)))/len(poly)
    poly=[center+(p-center)*max(.86,1-.024/max(.15,(p-center).length)) for p in poly]
    top=8.246+rng.uniform(-.013,.018)
    material=rng.choices(stones,[3,5,4,3,1])[0]
    rings=[]
    for inset,z in [(0,8.085),(0,top-.025),(.025,top)]:
        rings.append([Vector((p.x,p.y,z)) if inset==0 else Vector((center.x+(p.x-center.x)*(1-inset/max(.1,(p-center).length)),
            center.y+(p.y-center.y)*(1-inset/max(.1,(p-center).length)),z)) for p in poly])
    mesh.face(list(reversed(rings[0])),material);mesh.face(rings[-1],material)
    for a,b in zip(rings,rings[1:]):
        for i in range(len(a)):j=(i+1)%len(a);mesh.face([a[i],a[j],b[j],b[i]],material)

# Ground-reaching backing and varied masonry courses retain the exact platform size.
for i in range(96):
    a=i*math.tau/96;b=(i+1)*math.tau/96
    x,y=-1+12*math.cos((a+b)*.5),47+12*math.sin((a+b)*.5)
    if y<36 and abs(x+1)<3.95:continue
    bottom=ground(x,y)-.25
    ring=[]
    for z in [bottom,13.43]:
        ring.append([Vector((-1+r*math.cos(t),47+r*math.sin(t),z)) for r,t in [(11.18,a),(12.08,a),(12.08,b),(11.18,b)]])
    mesh.face(list(reversed(ring[0])),mortar);mesh.face(ring[1],mortar)
    for j in range(4):k=(j+1)%4;mesh.face([ring[0][j],ring[0][k],ring[1][k],ring[1][j]],mortar)
z=6.8;row=0
while z<13.43:
    h=min(13.43-z,rng.uniform(.32,.43));count=rng.randrange(84,102);step=math.tau/count
    for i in range(count):
        a=(i+.5*(row%2))*step;radius=12.05+rng.uniform(-.035,.035)
        x,y=-1+radius*math.cos(a),47+radius*math.sin(a)
        if y<36 and abs(x+1)<4.0:continue
        if z+h<ground(x,y)-.12:continue
        cut_stone(mesh,x,y,z+h*.5,step*radius-.021,.72,h-.017,rng.choice(stones),a+math.pi/2)
    z+=h;row+=1
for i in range(94):
    a=(i+.5)*math.tau/94;x,y=-1+12*math.cos(a),47+12*math.sin(a)
    if y<36 and abs(x+1)<3.95:continue
    cut_stone(mesh,x,y,13.55,math.tau*12/94-.012,.97,.19,rng.choice(stones),a+math.pi/2)
new=mesh.build('PLAZA_REPAIR_GEOMETRY')
new.data.uv_layers.active.name=plaza.data.uv_layers.active.name
bpy.ops.object.select_all(action='DESELECT');plaza.select_set(True);new.select_set(True)
bpy.context.view_layer.objects.active=plaza;bpy.ops.object.join()

# Replace the overlong timber deck with stone paving; retain the route endpoints.
for name in ['SM_VIL_EntranceBridge_Railing','SM_VIL_EntranceBridge_StoneSupports']:
    bpy.data.objects.remove(bpy.data.objects[name],do_unlink=True)
bridge,stones,mortar=builder();rail=MeshBuilder()
wood=[rail.material('MV_Timber_Bridge_%02d'%i) for i in range(4)]
iron=rail.material('MV_Metal_BlackIron')
a,b=[Vector(manifest['route_m'][i]) for i in [3,4]]
direction=(b-a).normalized();normal=Vector((-direction.y,direction.x,0));length=(b-a).length
def local(s,w,z):return a+direction*s+normal*w+Vector((0,0,z-a.z))
def arch(s):
    t=(s-5.45)/5.20
    return .10+2.0*math.sqrt(max(0,1-t*t)) if abs(t)<1 else ground(*local(s,0,0)[:2])-.25
for i in range(112):
    s0=i*length/112;s1=(i+1)*length/112
    bottom0=min(2.80,arch(s0));bottom1=min(2.80,arch(s1))
    ring0=[local(s0,w,z) for w,z in [(-2.48,bottom0),(2.48,bottom0),(2.48,3.035),(-2.48,3.035)]]
    ring1=[local(s1,w,z) for w,z in [(-2.48,bottom1),(2.48,bottom1),(2.48,3.035),(-2.48,3.035)]]
    bridge.face(list(reversed(ring0)),mortar);bridge.face(ring1,mortar)
    for j in range(4):k=(j+1)%4;bridge.face([ring0[j],ring0[k],ring1[k],ring1[j]],mortar)
for i in range(math.ceil(length/.46)):
    s=(i+.5)*length/math.ceil(length/.46)
    for col in range(12):
        p=local(s,-2.30+col*.418,3.055+rng.uniform(-.008,.009))
        cut_stone(bridge,p.x,p.y,p.z,length/math.ceil(length/.46)-.014,.401,.12,rng.choice(stones),math.atan2(direction.y,direction.x))
    for side in [-1,1]:
        p=local(s,side*2.40,2.96)
        cut_stone(bridge,p.x,p.y,p.z,.45,.40,.25,rng.choice(stones),math.atan2(direction.y,direction.x))
for i in range(19):
    s=.14+(length-.28)*i/18
    for side in [-1,1]:
        rail.beam(local(s,side*2.47,3.035),local(s,side*2.47,4.18),.19,wood[i%4])
        for dz in [3.58,4.07]:
            rail.beam(local(s,side*2.58,dz-.055),local(s,side*2.58,dz+.055),.21,iron,depth=.032)
for side in [-1,1]:
    for z in [3.57,4.075]:rail.beam(local(.12,side*2.47,z),local(length-.12,side*2.47,z),.14,wood[0],depth=.19)
supports=bridge.build('SM_VIL_EntranceBridge_StoneSupports')
railing=rail.build('SM_VIL_EntranceBridge_Railing')

changed=[plaza,supports,railing]
manifest['mesh_source_versions']={name:manifest.get('mesh_source_versions',{}).get(name,'v058') for name in manifest['assets'] if name not in [o.name for o in changed]}
for name in manifest['assets']:
    if name not in [o.name for o in changed]:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
for obj in changed:export_mesh(obj,OUT/(obj.name+'.fbx'))
manifest['geometry_source_version']='v058';manifest['stage']='BRIDGE_PAVING_TREE_BASE_REQUIRES_REVIEW'
manifest['geometry_changes']=['Stone-faced crossing with a real river arch and stone deck on existing route endpoints',
    'Fitted irregular plaza flags and smaller radial medallion; mortar gaps and exposed stone bevels',
    'Continuous tree-wall support with irregular stone courses and retained stair mouth, rails and platform elevations']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'ground_polish_report.json').write_text(json.dumps({'paving_cells':len(seeds),'bridge_span_m':length,
    'river_arch_center_station_m':5.45,'river_arch_half_width_m':5.20,'modified_meshes':[o.name for o in changed],
    'status':'MODELED_NOT_VISUALLY_ACCEPTED'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v059.blend'))
print('GROUND_POLISH_SAVED',len(seeds))
