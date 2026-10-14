from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy,json
from pathlib import Path
from mathutils import Vector
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain/v085'))
bpy.ops.wm.open_mainfile(filepath=str(root/'SEKAI_Valley_Terrain_v085.blend'))
rows=[]
for name in ['SM_VIL_Hero_AncientTree_Wood','SM_VIL_Hero_AncientTree_Foliage','SM_VIL_Plaza_PavingAndTreeTerrace']:
 o=bpy.data.objects[name];ps=[o.matrix_world@v.co for v in o.data.vertices]
 rows.append({'name':name,'vertices':len(ps),'location':list(o.location),'min':[min(p[i] for p in ps) for i in range(3)],'max':[max(p[i] for p in ps) for i in range(3)],'materials':[m.name for m in o.data.materials]})
Path(str(_SEKAI_RUNTIME / 'tree_bounds_v085.json')).write_text(json.dumps(rows,indent=2))
