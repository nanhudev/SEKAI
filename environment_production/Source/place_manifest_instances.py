"""Keep editable Blender placements aligned with the Unreal instance manifest."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import sys
from pathlib import Path

version=sys.argv[-1]
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/version
path=root/('SEKAI_Valley_Terrain_'+version+'.blend')
bpy.ops.wm.open_mainfile(filepath=str(path))
manifest=json.loads((root/'terrain_manifest.json').read_text())
collection=bpy.data.collections.get('Forest_Placements') or bpy.data.collections.new('Forest_Placements')
if collection.name not in bpy.context.scene.collection.children:bpy.context.scene.collection.children.link(collection)
for i,row in enumerate(manifest.get('instances',[])):
    name='Forest_%03d'%i
    obj=bpy.data.objects.get(name) or bpy.data.objects.new(name,bpy.data.objects[row['mesh']].data)
    if not obj.users_collection:collection.objects.link(obj)
    obj.location=row['position_m'];obj.rotation_euler.z=math.radians(row['yaw_degrees'])
    obj.scale=(row['scale'],)*3
bpy.ops.wm.save_as_mainfile(filepath=str(path))
