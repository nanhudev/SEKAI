"""Preserve ground polish; add a distant border-count estate and a real arched viaduct."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import bmesh
import json
import math
import shutil
import sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder,export_mesh

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));BASE,OUT=ROOT/'v059',ROOT/'v060'
OUT.mkdir(exist_ok=True);assert not (OUT/'terrain_manifest.json').exists()
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v059.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
bpy.context.view_layer.update()
surfaces=[BVHTree.FromObject(bpy.data.objects[n],bpy.context.evaluated_depsgraph_get()) for n in
    ['SM_VIL_Valley_Terrain_v009','SM_VIL_Valley_Surroundings']]
def ground(x,y):
    hits=[b.ray_cast(Vector((x,y,300)),Vector((0,0,-1)),600)[0] for b in surfaces]
    hits=[p.z for p in hits if p is not None]
    assert hits,(x,y)
    return max(hits)

# Repair native triangulation and bridge-shell winding before the next import.
plaza=bpy.data.objects['SM_VIL_Plaza_PavingAndTreeTerrace']
support=bpy.data.objects['SM_VIL_EntranceBridge_StoneSupports']
bm=bmesh.new();bm.from_mesh(support.data);bm.faces.ensure_lookup_table()
for i in range(112*6):
    if i%6>=2:bm.faces[i].normal_flip()
bm.to_mesh(support.data);bm.free()
for obj in [plaza,support]:
    bm=bmesh.new();bm.from_mesh(obj.data)
    bmesh.ops.dissolve_degenerate(bm,dist=.00001,edges=list(bm.edges))
    bmesh.ops.triangulate(bm,faces=list(bm.faces))
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(obj.data);bm.free();obj.data.update()

mesh=MeshBuilder()
palette={'MV_Estate_Stone_Warm':(.29,.30,.265),'MV_Estate_Stone_Shadow':(.19,.22,.23),
    'MV_Estate_Plaster':(.46,.43,.35),'MV_Estate_Timber':(.14,.083,.048),
    'MV_Estate_Slate':(.10,.15,.20),'MV_Estate_Window':(.12,.18,.19),'MV_Estate_Copper':(.22,.29,.25)}
mat={k:mesh.material(k,c) for k,c in palette.items()}
stone=mat['MV_Estate_Stone_Warm'];dark=mat['MV_Estate_Stone_Shadow']
plaster=mat['MV_Estate_Plaster'];wood=mat['MV_Estate_Timber'];slate=mat['MV_Estate_Slate']
glass=mat['MV_Estate_Window']
cx,cy=152,187
foot=[ground(cx+x,cy+y) for x in [-23,0,23] for y in [-17,0,17]]
base=max(foot)+.4
for side in [-1,1]:
    for i in range(11):
        x=cx+side*23;y=cy-17+i*3.4;bottom=ground(x,y)-.7
        mesh.block((x,y,(base+bottom)*.5),(1.9,3.45,base-bottom),stone,bevel=.08)
for i in range(14):
    x=cx-23+i*46/13;y=cy-17;bottom=ground(x,y)-.7
    mesh.block((x,y,(base+bottom)*.5),(3.65,2.0,base-bottom),stone,bevel=.07)
mesh.block((cx,cy,base-.32),(47,35,.72),stone,bevel=.12)

def roof(x,y,z,w,d,h):
    for side in [-1,1]:
        top=[Vector((x,y-d/2,z+h)),Vector((x+side*w/2,y-d/2,z)),
             Vector((x+side*w/2,y+d/2,z)),Vector((x,y+d/2,z+h))]
        if side<0:top.reverse()
        lower=[p-Vector((0,0,.30)) for p in top]
        mesh.face(top,slate);mesh.face(list(reversed(lower)),slate)
        for i in range(4):j=(i+1)%4;mesh.face([top[i],lower[i],lower[j],top[j]],slate)
    mesh.beam((x,y-d/2-.3,z+h),(x,y+d/2+.3,z+h),.40,wood)

mesh.block((cx,cy+1,base+6.6),(28,17,13.2),plaster,bevel=.12)
roof(cx,cy+1,base+13.1,31,20,7)
for side in [-1,1]:
    x=cx+side*17
    mesh.block((x,cy+4,base+4.5),(7,20,9),stone,bevel=.10)
    roof(x,cy+4,base+9,9.2,23,4.1)
for x in [cx-14,cx-7,cx,cx+7,cx+14]:
    for y in [cy-7.7,cy+9.7]:
        mesh.beam((x,y,base+.4),(x,y,base+13.2),.38,wood)
for z in [base+.6,base+5.7,base+10.2,base+13.1]:
    for y in [cy-7.7,cy+9.7]:mesh.beam((cx-14.4,y,z),(cx+14.4,y,z),.42,wood)
for x in [cx-10,cx-5,cx,cx+5,cx+10]:
    for z in [base+3.1,base+8.1,base+11.65]:
        mesh.block((x,cy-7.9,z),(1.45,.22,2.15),glass,bevel=.025)
        mesh.beam((x-.85,cy-8.05,z-1.17),(x+.85,cy-8.05,z-1.17),.25,stone)
        mesh.beam((x,cy-8.07,z-1.03),(x,cy-8.07,z+1.03),.09,wood)
# Three watchtowers give the count's residence a recognizable defensive silhouette.
for x,y,h in [(cx-20,cy-13,20),(cx+20,cy-13,23),(cx+15,cy+13,28)]:
    mesh.block((x,y,base+h*.5),(6.0,6.0,h),stone,bevel=.14)
    mesh.block((x,y,base+h),(7.0,7.0,.65),dark,bevel=.10)
    for side in [-1,1]:
        for dx in [-2.6,0,2.6]:
            mesh.block((x+dx,y+side*3.1,base+h+.85),(1.3,.85,1.1),stone,bevel=.07)
    # Steep closed pyramidal slate roof, visible at the valley's scale.
    corners=[Vector((x+dx,y+dy,base+h+1.0)) for dx,dy in [(-4,-4),(4,-4),(4,4),(-4,4)]]
    tip=Vector((x,y,base+h+8.4))
    mesh.face(list(reversed(corners)),slate)
    for i in range(4):mesh.face([corners[i],corners[(i+1)%4],tip],slate)
    for z in [base+6,base+12,base+17]:mesh.block((x,y-3.10,z),(.72,.19,1.85),glass,bevel=.018)
estate=mesh.build('SM_VIL_BorderCount_Estate_v060')

bridge=MeshBuilder();s=bridge.material('MV_Estate_Stone_Warm',palette['MV_Estate_Stone_Warm'])
shadow=bridge.material('MV_Estate_Stone_Shadow',palette['MV_Estate_Stone_Shadow'])
a,b=Vector((83,133,0)),Vector((141,169,0));u=(b-a).normalized();v=Vector((-u.y,u.x,0));length=(b-a).length
heights=[ground(*(a+(b-a)*(i/16))[:2]) for i in range(17)]
deck=max(base,max(heights)+4)
def point(t,w,z):return a+u*t+v*w+Vector((0,0,z))
for bay in range(8):
    start=bay*length/8;span=length/8
    for j in range(14):
        ts=[start+j*span/14,start+(j+1)*span/14]
        lower=[deck-2.1-9.4*(1-math.sin(math.pi*(t-start)/span)) for t in ts]
        rings=[[point(t,w,z) for w,z in [(-2.8,lo),(2.8,lo),(2.8,deck),(-2.8,deck)]] for t,lo in zip(ts,lower)]
        bridge.face(list(reversed(rings[0])),shadow);bridge.face(rings[1],shadow)
        for i in range(4):k=(i+1)%4;bridge.face([rings[0][i],rings[0][k],rings[1][k],rings[1][i]],s)
    t=start+.25;p=point(t,0,0);bottom=ground(p.x,p.y)-.7
    bridge.block(tuple(point(t,0,(deck+bottom)*.5)),(2.2,7.0,deck-bottom),s,angle=math.atan2(u.y,u.x),bevel=.13)
for side in [-1,1]:
    for i in range(28):
        p=point((i+.5)*length/28,side*2.9,deck+.58)
        bridge.block(tuple(p),(length/28+.02,.70,1.1),s,angle=math.atan2(u.y,u.x),bevel=.04)
viaduct=bridge.build('SM_VIL_BorderCount_Viaduct_v060')

changed=[plaza,support,bpy.data.objects['SM_VIL_EntranceBridge_Railing'],estate,viaduct]
aliases=manifest.get('mesh_source_versions',{})
manifest['mesh_source_versions']={name:aliases[name] for name in manifest['assets'] if name in aliases and name not in [o.name for o in changed]}
for name in manifest['assets']:
    if name not in [o.name for o in changed]:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
for obj in changed:
    export_mesh(obj,OUT/(obj.name+'.fbx'))
    if obj.name not in manifest['assets']:manifest['assets'].append(obj.name)
manifest['material_palette'].update({k:list(c) for k,c in palette.items()})
manifest['atmosphere_trial']={'cloud_layer_bottom_km':1.8,'cloud_layer_height_km':3.2,'haze_density':.004,
    'note':'Cloud/haze additions change atmosphere; original sun/exposure and six cameras retained'}
manifest['water_animation_trial']=True
manifest['geometry_source_version']='v059';manifest['stage']='GROUND_POLISH_COUNT_ESTATE_AND_ATMOSPHERE_REQUIRES_REVIEW'
manifest['geometry_changes']+=['Distant border-count estate with three roofed watchtowers and a ground-supported terrace',
    'Eight-arch high viaduct grounded against existing background terrain; approximate distant architecture only',
    'Native stone triangulation and outward bridge-shell winding corrected']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'estate_report.json').write_text(json.dumps({'center_m':[cx,cy,base],'viaduct_deck_m':deck,
    'viaduct_span_m':length,'ground_samples_m':heights,'architecture_stage':'DISTANT_SILHOUETTE_BLOCKOUT',
    'status':'NOT_VISUALLY_ACCEPTED'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v060.blend'))
print('COUNT_ESTATE_AND_VIADUCT_SAVED',base,deck)
