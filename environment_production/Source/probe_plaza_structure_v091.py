from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy,json,math,collections,sys
from pathlib import Path
r=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
def structural_faces(version):
 bpy.ops.wm.open_mainfile(filepath=str(r/version/('SEKAI_Valley_Terrain_'+version+'.blend')))
 o=bpy.data.objects['SM_VIL_Plaza_PavingAndTreeTerrace'];rows=[]
 for p in o.data.polygons:
  ps=[o.data.vertices[i].co for i in p.vertices]
  if any(v.z>8.5 for v in ps) or all(math.hypot(v.x-20,v.y-13)>14.3 for v in ps):
   rows.append((o.data.materials[p.material_index].name,tuple(sorted(tuple(round(c,5) for c in v) for v in ps))))
 return collections.Counter(rows)
version=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'v091'
a=structural_faces('v090');b=structural_faces(version)
missing=a-b
assert not missing, len(missing)
(r/version/'structural_preservation.json').write_text(json.dumps({'scope':'Independent face-coordinate/material check above plaza grade or outside plaza footprint','original_structural_faces':sum(a.values()),'all_original_structural_faces_preserved':True},indent=2))
if version=='v092':
 o=bpy.data.objects['SM_VIL_Plaza_PavingAndTreeTerrace'];uv=o.data.uv_layers[0];checked=0;zero=0
 for p in o.data.polygons:
  if p.normal.z<.8 or not 8.21<p.center.z<8.4 or not o.data.materials[p.material_index].name.startswith('MV_Polish_Limestone'):continue
  checked+=1
  if all(uv.data[i].uv.length<1e-6 for i in p.loop_indices):zero+=1
 assert checked>1000 and zero==0,(checked,zero)
 (r/version/'paving_uv_check.json').write_text(json.dumps({'uv0_name':uv.name,'top_faces_checked':checked,'zero_uv_top_faces':zero,'scope':'Source UV0 validation; native surface review required'},indent=2))
