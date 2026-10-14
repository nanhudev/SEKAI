from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import sys
from pathlib import Path
version=sys.argv[-1]
root=Path(str(_SEKAI_ROOT / 'environment_production/Versions'))/version
bpy.context.scene.cycles.use_denoising=False
bpy.context.scene.cycles.samples=24
bpy.context.scene.render.threads_mode='FIXED'
bpy.context.scene.render.threads=6
bpy.context.scene.render.filepath=str(root/('Tavern_Blender_Preview_'+version+'.png'))
bpy.ops.render.render(write_still=True)
