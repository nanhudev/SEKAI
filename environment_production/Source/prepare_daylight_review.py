"""Prepare an independently reviewable daylight balance without geometry changes."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
import shutil
from pathlib import Path

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
BASE=ROOT/'v026';OUT=ROOT/'v027'
OUT.mkdir(exist_ok=False)
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
for name in manifest['assets']:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for texture in manifest.get('surface_color_textures',{}).values():
    shutil.copy2(BASE/(texture+'.png'),OUT/(texture+'.png'))
shutil.copy2(BASE/'SEKAI_Valley_Terrain_v026.blend',OUT/'SEKAI_Valley_Terrain_v027.blend')
manifest['stage']='DAYLIGHT_BALANCE_REVIEW_NOT_VISUALLY_ACCEPTED'
manifest['geometry_source_version']='v026'
manifest['review_lighting'].update({'sky_intensity':2.0,'sky_luminance_factor':2.0,
    'sun_temperature_kelvin':5700.0,
    'note':'Isolated daylight balance trial against v026; geometry, cameras, sun direction and exposure unchanged'})
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
print('SEKAI_DAYLIGHT_REVIEW_PREPARED',OUT)
