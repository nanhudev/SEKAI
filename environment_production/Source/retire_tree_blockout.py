"""Remove the superseded terrace proxy obscuring the authored tree retaining wall."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import shutil
from pathlib import Path

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
BASE=ROOT/'v019';OUT=ROOT/'v020'
OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v019.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
obsolete='SM_VIL_Terrace_Face_Tree'
obj=bpy.data.objects[obsolete]
bpy.data.objects.remove(obj,do_unlink=True)
manifest['assets'].remove(obsolete)
for name in manifest['assets']:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for texture in manifest.get('surface_color_textures',{}).values():
    shutil.copy2(BASE/(texture+'.png'),OUT/(texture+'.png'))
manifest['stage']='TREE_PLATFORM_INTEGRATION_NOT_VISUALLY_ACCEPTED'
manifest['geometry_source_version']='v019'
manifest['geometry_changes']=['Removed obsolete tree terrace proxy overlapping actual stairs and wall',
    'Retained graded terrain, structural masonry, recessed plaza route and all six cameras']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v020.blend'))
print('SEKAI_TREE_BLOCKOUT_RETIRED',OUT)
