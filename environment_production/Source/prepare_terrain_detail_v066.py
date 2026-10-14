from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json,os,shutil,sys
from pathlib import Path
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/'v065'
version=sys.argv[1] if len(sys.argv)>1 else 'v066'
target=Path(str(_SEKAI_RUNTIME / 'Checkpoints'))/version
target.mkdir(exist_ok=False)
pass  # Checkpoints stay inside the portable project.
m=json.loads((base/'terrain_manifest.json').read_text())
for p in base.iterdir():
    if p.suffix.lower() in ['.fbx','.png']:os.link(p,target/p.name)
shutil.copy2(base/'SEKAI_Valley_Terrain_v065.blend',target/('SEKAI_Valley_Terrain_'+version+'.blend'))
for name in m['assets']:m.setdefault('mesh_source_versions',{}).setdefault(name,'v065')
sources=Path(str(_SEKAI_ROOT / 'environment_production/LicensedMaterials/PolyHaven/source_manifest.json'))
rows=json.loads(sources.read_text())
m['terrain_detail_trial']={'materials':['MV_Valley_Surface','MV_Valley_BackdropSurface'],'textures':rows,'description':'World projected slope-blended grass/rock detail preserving authored color.'}
m['version']=version
(target/'terrain_manifest.json').write_text(json.dumps(m,indent=2))
shutil.copy2(sources,target/'material_sources.json')
print(target)
