from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy,json,sys,os,shutil,math
from pathlib import Path
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder,export_mesh
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/'v068'
version='v070'
target=Path(str(_SEKAI_RUNTIME / 'Checkpoints'))/version;target.mkdir(exist_ok=False)
out=root/version;pass  # Checkpoints stay inside the portable project.
bpy.ops.wm.open_mainfile(filepath=str(base/'SEKAI_Valley_Terrain_v068.blend'))
m=json.loads((base/'terrain_manifest.json').read_text())
for name in m['assets']:m.setdefault('mesh_source_versions',{}).setdefault(name,'v068')
for p in base.iterdir():
    if p.suffix.lower() in ['.fbx','.png']:os.link(p,target/p.name)
if (base/'material_sources.json').exists():shutil.copy2(base/'material_sources.json',out/'material_sources.json')
bpy.context.view_layer.update()
bvh=BVHTree.FromObject(bpy.data.objects['SM_VIL_Valley_Terrain_v009'],bpy.context.evaluated_depsgraph_get())
mesh=MeshBuilder();stone=mesh.material('MV_Home_Stone_0',(.28,.32,.29));records=[]
homes=json.loads((base/'homes_report.json').read_text())['houses']
for i,row in enumerate(homes):
    cx,cy,z=row['center_m'];xf=Matrix.Translation(Vector((cx,cy,z)))@Matrix.Rotation(-math.pi/2,4,'Z')
    def ground(x,y):
        p=xf@Vector((x,y,0));hit=bvh.ray_cast(Vector((p.x,p.y,180)),Vector((0,0,-1)),300)[0]
        assert hit is not None;return hit.z-z
    def supported_box(x,y,width,depth,top):
        bottom=min(ground(x+dx,y+dy) for dx in [-width/2,0,width/2] for dy in [-depth/2,0,depth/2])-.18
        local=MeshBuilder();index=local.material('MV_Home_Stone_0',(.28,.32,.29))
        local.block((x,y,(top+bottom)/2),(width,depth,top-bottom),index,bevel=.012)
        for face in local.faces:mesh.face([xf@Vector(local.vertices[j]) for j in face],stone)
        records.append({'house':row['name'],'local_xy':[x,y],'bottom':bottom,'top':top})
    supported_box(0,0,6.8,7.4,.30)
    for x in ([-2.3,2.3] if i==0 else [-1.85,3.2]):supported_box(x,-3.5-(1.35 if i==0 else 1.93),.43,.43,.28)
    for step in range(3):supported_box(-.8 if i==0 else 1.05,-3.5-.65-step*.37,2.25,.40,.48-step*.13-.05)
ob=mesh.build('SM_VIL_Home_Footings_'+version);export_mesh(ob,out/(ob.name+'.fbx'));m['assets'].append(ob.name)
m['version']=version;m['surface_water_flow']=True
(out/'terrain_manifest.json').write_text(json.dumps(m,indent=2));(out/'footing_support.json').write_text(json.dumps(records,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(out/('SEKAI_Valley_Terrain_'+version+'.blend')))
print('HOME_SUPPORT_AND_WATER_TRIAL_READY')
