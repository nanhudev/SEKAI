from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json,os,shutil
from pathlib import Path
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/'v080'
out=Path(str(_SEKAI_ROOT / 'environment_production/Terrain/v081'));out.mkdir(exist_ok=False)
pass  # Checkpoints stay inside the portable project.
m=json.loads((base/'terrain_manifest.json').read_text())
for name in m['assets']:m.setdefault('mesh_source_versions',{}).setdefault(name,'v080')
for p in base.iterdir():
    if p.suffix.lower() in ['.fbx','.png']:os.link(p,out/p.name)
    elif p.name=='material_sources.json':shutil.copy2(p,out/p.name)
shutil.copy2(base/'SEKAI_Valley_Terrain_v080.blend',out/'SEKAI_Valley_Terrain_v081.blend')
m['version']='v081'
m['atmosphere_trial']['cloud_scalar_overrides']['Cloud_GlobalCoverage']=.22
m['atmosphere_trial']['cloud_vector_overrides']['Layout_GlobalTexturePlacement']=[24.5,24.5,0,0]
m['atmosphere_trial']['note']='Weather layout placement trial for primary camera visibility; geometry/sun/exposure/cameras unchanged.'
(out/'terrain_manifest.json').write_text(json.dumps(m,indent=2))
