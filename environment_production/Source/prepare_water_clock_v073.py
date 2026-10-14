from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json,os,shutil,sys
from pathlib import Path
source,version=sys.argv[1:3] if len(sys.argv)>2 else ('v072','v073')
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/source
assert (base/'ue_import.json').exists()
out=Path(str(_SEKAI_RUNTIME / 'Checkpoints'))/version;out.mkdir(exist_ok=False)
pass  # Checkpoints stay inside the portable project.
m=json.loads((base/'terrain_manifest.json').read_text())
for name in m['assets']:m.setdefault('mesh_source_versions',{}).setdefault(name,source)
for p in base.iterdir():
    if p.suffix.lower() in ['.fbx','.png']:os.link(p,out/p.name)
    elif p.name in ['material_sources.json','planting_report.json']:shutil.copy2(p,out/p.name)
shutil.copy2(base/('SEKAI_Valley_Terrain_'+source+'.blend'),out/('SEKAI_Valley_Terrain_'+version+'.blend'))
m['version']=version;m['water_clock_parameters']=True
(out/'terrain_manifest.json').write_text(json.dumps(m,indent=2))
