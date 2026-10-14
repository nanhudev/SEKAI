"""Restore the original approach grade across the river-carved road depression."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy,bmesh,json,sys,os,shutil,math,random
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder,export_mesh
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/'v076'
target=Path(str(_SEKAI_ROOT / 'environment_production/Terrain/v077'));target.mkdir(exist_ok=False)
out=root/'v077';pass  # Checkpoints stay inside the portable project.
bpy.ops.wm.open_mainfile(filepath=str(base/'SEKAI_Valley_Terrain_v076.blend'))
m=json.loads((base/'terrain_manifest.json').read_text())
for p in base.iterdir():
    if p.suffix.lower() in ['.fbx','.png']:os.link(p,target/p.name)
    elif p.name in ['material_sources.json','homes_report.json','bridge_approach_profile.json']:shutil.copy2(p,target/p.name)
bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
terrain=BVHTree.FromObject(bpy.data.objects['SM_VIL_Valley_Terrain_v009'],deps)
mesh=MeshBuilder();rng=random.Random(26101477)
stone=[mesh.material('MV_Polish_Limestone_'+str(i),m['material_palette']['MV_Polish_Limestone_'+str(i)]) for i in range(5)]
mortar=mesh.material('MV_Polish_Mortar',m['material_palette']['MV_Polish_Mortar'])
a=Vector(m['route_m'][2]);b=Vector(m['route_m'][3]);c=Vector(m['route_m'][4])
u=(b-a).normalized();v=(c-b).normalized();end=b+v*.45
n0=Vector((-u.y,u.x,0));n1=Vector((-v.y,v.x,0));length=(b-a).length+.45
def section(s,w):
    if s<=(b-a).length:
        t=s/(b-a).length;p=a.lerp(b,t)
        # Turn the final four metres into a real landing at the existing bridge.
        blend=max(0,min(1,(s-((b-a).length-4))/4))
        normal=n0.lerp(n1,blend).normalized()
        z=2.48+(3.075-2.48)*t
    else:p=b+v*(s-(b-a).length);normal=n1;z=3.075
    return Vector((p.x+normal.x*w,p.y+normal.y*w,z))
def ground(p):
    hit=terrain.ray_cast(Vector((p.x,p.y,180)),Vector((0,0,-1)),300)[0]
    assert hit is not None;return hit.z
def closed(top,bottom,material):
    lower=[Vector((p.x,p.y,z)) for p,z in zip(top,bottom)]
    mesh.face(top,material);mesh.face(list(reversed(lower)),material)
    for i in range(4):j=(i+1)%4;mesh.face([top[i],lower[i],lower[j],top[j]],material)
rows=math.ceil(length/.43)
for row in range(rows):
    s0=length*row/rows;s1=length*(row+1)/rows
    top=[section(s0,-2.5),section(s1,-2.5),section(s1,2.5),section(s0,2.5)]
    closed(top,[ground(p)-.18 for p in top],mortar)
    for col in range(7):
        w0=-2.48+col*4.96/7+.008;w1=-2.48+(col+1)*4.96/7-.008
        paving=[section(s0+.006,w0),section(s1-.006,w0),section(s1-.006,w1),section(s0+.006,w1)]
        for p in paving:p.z+=.045+rng.uniform(-.003,.003)
        closed(paving,[p.z-.10 for p in paving],stone[(row+col)%5])
    # Ground-reaching stone shoulders make the bridgehead an abutment.
    for side in [-1,1]:
        p0=section(s0,side*2.5);p1=section(s1,side*2.5)
        bottom=min(ground(p0),ground(p1))-.16
        count=max(1,math.ceil((max(p0.z,p1.z)-bottom)/.28))
        for course in range(count):
            lo=bottom+course*.28;hi=min(max(p0.z,p1.z),lo+.27)
            if hi-lo<.02:continue
            p=(p0+p1)/2;angle=math.atan2(p1.y-p0.y,p1.x-p0.x)
            mesh.block((p.x,p.y,(lo+hi)/2),((p1-p0).to_2d().length+.008,.24,hi-lo),stone[(course+row)%5],angle=angle,bevel=.018)
ob=mesh.build('SM_VIL_Bridge_LeftApproach_v077')
bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
export_mesh(ob,out/(ob.name+'.fbx'));m['assets'].append(ob.name)
m['version']='v077';m['geometry_changes']=['Restore original left approach from riverbed depression to continuous 2.52-3.12m stone grade with ground-reaching shoulders','Two west terrace homes carried from v076; terrain/layout/cameras/light/water fix preserved']
(out/'terrain_manifest.json').write_text(json.dumps(m,indent=2))
(out/'bridge_left_repair.json').write_text(json.dumps({'source':'Measured old route depressed to approximately -0.55m before 3.12m bridge deck','start_m':list(a),'end_m':list(end),'length_m':length,'surface_grade_m':[2.525,3.12],'walkable_width_m':4.96,'scope':'Source repair; requires actual mesh collision and physical traversal verification'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(out/'SEKAI_Valley_Terrain_v077.blend'))
