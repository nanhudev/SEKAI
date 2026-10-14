from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy,json,os,sys,shutil
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import export_mesh
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/'v077'
out=Path(str(_SEKAI_ROOT / 'environment_production/Terrain/v078'));out.mkdir(exist_ok=False)
pass  # Checkpoints stay inside the portable project.
bpy.ops.wm.open_mainfile(filepath=str(base/'SEKAI_Valley_Terrain_v077.blend'))
m=json.loads((base/'terrain_manifest.json').read_text());changed='SM_VIL_Home_PorchCottage_v076'
for name in m['assets']:
    if name!=changed:m.setdefault('mesh_source_versions',{}).setdefault(name,'v077')
m['mesh_source_versions'].pop(changed,None)
for p in base.iterdir():
    if p.suffix.lower() in ['.fbx','.png'] and p.name!=changed+'.fbx':os.link(p,out/p.name)
    elif p.name in ['material_sources.json','bridge_left_repair.json']:shutil.copy2(p,out/p.name)
bpy.context.view_layer.update();bvh=BVHTree.FromObject(bpy.data.objects['SM_VIL_Valley_Terrain_v009'],bpy.context.evaluated_depsgraph_get())
report=json.loads((base/'homes_report.json').read_text());old=report['houses'][0]['center_m']
cx,cy=-52,28;rotate=Matrix.Rotation(1.43,4,'Z');heights=[]
for x in [-3.1,0,3.1]:
    for y in [-3.6,0,3.6]:
        p=rotate@Vector((x,y,0));hit=bvh.ray_cast(Vector((cx+p.x,cy+p.y,180)),Vector((0,0,-1)),300)[0]
        assert hit is not None;heights.append(hit.z)
assert max(heights)-min(heights)<.5
new=Vector((cx,cy,max(heights)-.05));delta=new-Vector(old)
obj=bpy.data.objects[changed]
for v in obj.data.vertices:v.co+=delta
obj.data.update();export_mesh(obj,out/(changed+'.fbx'))
report['houses'][0]['center_m']=list(new);report['houses'][0]['ground_samples_m']=heights
m['version']='v078';m['geometry_changes']=['Retain repaired left bridge approach and two west homes; relocate lower cottage to clear original residential camera without moving any camera']
(out/'terrain_manifest.json').write_text(json.dumps(m,indent=2));(out/'homes_report.json').write_text(json.dumps(report,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(out/'SEKAI_Valley_Terrain_v078.blend'))
