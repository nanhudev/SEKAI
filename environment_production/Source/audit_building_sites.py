"""Sample the actual terrain; pick existing usable land instead of inventing floor heights."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
from pathlib import Path
import math
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain/v052'))
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'SEKAI_Valley_Terrain_v052.blend'))
bpy.context.view_layer.update()
bvh=BVHTree.FromObject(bpy.data.objects['SM_VIL_Valley_Terrain_v009'],bpy.context.evaluated_depsgraph_get())
regions={'forge':[(x,y) for x in range(42,73,3) for y in range(7,41,3)],
         'lower_home':[(x,y) for x in range(-75,-35,3) for y in range(-10,31,3)],
         'upper_home':[(x,y) for x in range(-73,-30,3) for y in range(40,80,3)]}
samples={}
for label,coordinates in regions.items():
    rows=[]
    for x,y in coordinates:
        hit=bvh.ray_cast(Vector((x,y,200)),Vector((0,0,-1)),400)[0]
        rows.append([x,y,round(hit.z,3) if hit else None])
    samples[label]=rows
(ROOT/'building_site_samples.json').write_text(json.dumps(samples,indent=2))
proposals={}
for label,cx,cy,angle,w,d in [('forge',63,27,-1.12,11.5,14.5),
                            ('lower_home',-55,5,1.43,9,12),
                            ('upper_home',-53,58,1.78,9.8,11.8)]:
    candidates=[];rotation=Matrix.Rotation(angle,4,'Z')
    for x,y,_ in samples[label]:
        # Stay in the existing functional area; no redesign of the village.
        if math.hypot(x-cx,y-cy)>19:continue
        heights=[]
        for a in [-w/2,0,w/2]:
            for b in [-d/2,0,d/2]:
                p=rotation@Vector((a,b,0));hit=bvh.ray_cast(Vector((x+p.x,y+p.y,200)),Vector((0,0,-1)),400)[0]
                if hit:heights.append(hit.z)
        if len(heights)!=9:continue
        spread=max(heights)-min(heights)
        candidates.append({'center':[x,y],'height_range':spread,'samples':heights,
                           'score':spread*20+math.hypot(x-cx,y-cy)})
    proposals[label]=sorted(candidates,key=lambda r:r['score'])[:5]
(ROOT/'building_site_proposals.json').write_text(json.dumps(proposals,indent=2))
print('SITE_SAMPLES_SAVED')
