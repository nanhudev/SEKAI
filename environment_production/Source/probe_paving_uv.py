from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy,json
from pathlib import Path
r=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
bpy.ops.wm.open_mainfile(filepath=str(r/'v091/SEKAI_Valley_Terrain_v091.blend'))
o=bpy.data.objects['SM_VIL_Plaza_PavingAndTreeTerrace'];loops=[li for p in o.data.polygons if o.data.materials[p.material_index].name.startswith('MV_Polish_Limestone') and p.center.z<8.5 for li in p.loop_indices]
rows=[]
for uv in o.data.uv_layers:
 values=[tuple(uv.data[i].uv) for i in loops]
 rows.append({'name':uv.name,'active_render':uv.active_render,'min':[min(p[k] for p in values) for k in range(2)],'max':[max(p[k] for p in values) for k in range(2)]})
Path(str(_SEKAI_RUNTIME / 'v091_paving_uv.json')).write_text(json.dumps(rows,indent=2))
