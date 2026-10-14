from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy,json,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain/v076'))
bpy.ops.wm.open_mainfile(filepath=str(root/'SEKAI_Valley_Terrain_v076.blend'))
bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
names=['SM_VIL_Valley_Terrain_v009','SM_VIL_Valley_CriticalRoute_v009','SM_VIL_Route_FittedStone_v065','SM_VIL_EntranceBridge_StoneSupports']
bvhs={name:BVHTree.FromObject(bpy.data.objects[name],deps) for name in names}
rows=[]
for x in range(-53,-41):
    for y in range(-51,-39):
        hits={}
        for name,bvh in bvhs.items():
            hit=bvh.ray_cast(Vector((x,y,30)),Vector((0,0,-1)),60)[0]
            if hit is not None:hits[name]=round(hit.z,4)
        rows.append({'xy':[x,y],'hits':hits})
(root/'bridge_left_heights.json').write_text(json.dumps(rows,indent=2))
manifest=json.loads((root/'terrain_manifest.json').read_text());profile=[]
for segment in [1,2]:
    a,b=[Vector(manifest['route_m'][i]) for i in [segment,segment+1]]
    for i in range(11):
        p=a.lerp(b,i/10);hits={}
        for name,bvh in bvhs.items():
            hit=bvh.ray_cast(Vector((p.x,p.y,30)),Vector((0,0,-1)),60)[0]
            if hit is not None:hits[name]=round(hit.z,4)
        profile.append({'segment':segment,'t':i/10,'xy':[round(p.x,2),round(p.y,2)],'hits':hits})
(root/'bridge_approach_profile.json').write_text(json.dumps(profile,indent=2))
