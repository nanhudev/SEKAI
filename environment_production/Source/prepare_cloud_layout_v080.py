from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json,os,shutil
from pathlib import Path
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/'v079'
out=Path(str(_SEKAI_ROOT / 'environment_production/Terrain/v080'));out.mkdir(exist_ok=False)
pass  # Checkpoints stay inside the portable project.
m=json.loads((base/'terrain_manifest.json').read_text())
for name in m['assets']:m.setdefault('mesh_source_versions',{}).setdefault(name,'v079')
for p in base.iterdir():
    if p.suffix.lower() in ['.fbx','.png']:os.link(p,out/p.name)
    elif p.name=='material_sources.json':shutil.copy2(p,out/p.name)
shutil.copy2(base/'SEKAI_Valley_Terrain_v079.blend',out/'SEKAI_Valley_Terrain_v080.blend')
m['version']='v080'
m['atmosphere_trial']['cloud_scalar_overrides']={'Cloud_GlobalCoverage':.15,'Layout_CloudGlobalScale':96.0,'Cloud_GlobalDensity':.006}
m['atmosphere_trial']['cloud_vector_overrides']={'Layout_CloudType':[1,.15,.05,0]}
m['atmosphere_trial']['note']='Persisted cloud material; favor cumulus layout and raise coverage. Geometry, sun, exposure and fixed cameras unchanged.'
(out/'terrain_manifest.json').write_text(json.dumps(m,indent=2))
