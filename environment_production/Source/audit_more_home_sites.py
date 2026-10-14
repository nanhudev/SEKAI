from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy,json,math,sys
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
version=args[0] if args else 'v067'
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/version
bpy.ops.wm.open_mainfile(filepath=str(root/('SEKAI_Valley_Terrain_'+version+'.blend')))
bpy.context.view_layer.update()
bvh=BVHTree.FromObject(bpy.data.objects['SM_VIL_Valley_Terrain_v009'],bpy.context.evaluated_depsgraph_get())
bounds={}
for ob in bpy.data.objects:
    if any(s in ob.name for s in ['Home_','Tavern','Forge']):
        corners=[ob.matrix_world@Vector(p) for p in ob.bound_box]
        bounds[ob.name]=[[min(p[i] for p in corners),max(p[i] for p in corners)] for i in range(3)]
rows=[]
for x in (range(-73,-35,3) if len(args)>1 and args[1]=='west' else range(25,71,3)):
    for y in range(-8,75,3):
        heights=[]
        for dx in [-4,0,4]:
            for dy in [-5,0,5]:
                hit=bvh.ray_cast(Vector((x+dx,y+dy,180)),Vector((0,0,-1)),300)[0]
                if hit:heights.append(hit.z)
        if len(heights)!=9 or max(heights)-min(heights)>.8:continue
        if any(b[0][0]-6<x<b[0][1]+6 and b[1][0]-7<y<b[1][1]+7 for b in bounds.values()):continue
        rows.append({'xy':[x,y],'range':max(heights)-min(heights),'heights':heights})
(root/('west_home_sites.json' if len(args)>1 and args[1]=='west' else 'more_home_sites.json')).write_text(json.dumps({'buildings':bounds,'sites':rows},indent=2))
print('SITE_AUDIT',len(rows))
