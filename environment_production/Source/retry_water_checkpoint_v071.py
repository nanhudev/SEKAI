from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json,os,shutil
from pathlib import Path
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/'v070'
out=Path(str(_SEKAI_ROOT / 'environment_production/Terrain/v071'));out.mkdir(exist_ok=False)
pass  # Checkpoints stay inside the portable project.
for p in base.iterdir():
    if p.suffix.lower() in ['.png','.fbx']:os.link(p,out/p.name)
    elif p.name in ['material_sources.json','footing_support.json']:shutil.copy2(p,out/p.name)
shutil.copy2(base/'SEKAI_Valley_Terrain_v070.blend',out/'SEKAI_Valley_Terrain_v071.blend')
m=json.loads((base/'terrain_manifest.json').read_text());m['version']='v071'
(out/'terrain_manifest.json').write_text(json.dumps(m,indent=2))
