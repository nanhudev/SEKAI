"""Preserve a geometry checkpoint for an independently reviewable import change."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
import shutil
import sys
from pathlib import Path

root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
source,target=sys.argv[1:3]
base=root/source;out=root/target
out.mkdir(exist_ok=False)
manifest=json.loads((base/'terrain_manifest.json').read_text())
for name in manifest['assets']:shutil.copy2(base/(name+'.fbx'),out/(name+'.fbx'))
shutil.copy2(base/('SEKAI_Valley_Terrain_'+source+'.blend'),out/('SEKAI_Valley_Terrain_'+target+'.blend'))
manifest['stage']='VERTEX_COLOR_IMPORT_REVIEW_NOT_VISUALLY_ACCEPTED'
manifest['geometry_source_version']=source
manifest['import_changes']=['VertexColor default output with asserted material connection',
    'Legacy FBX importer honors explicit REPLACE vertex-color option']
(out/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
print('IMPORT_REVIEW_PREPARED',out)
