"""Save a separate playable tour map from the latest fixed-camera review map."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
import math
import os
from pathlib import Path
import unreal

VERSION=os.environ.get('SEKAI_REVIEW_VERSION','v092')
ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/VERSION
SOURCE='/Game/Environment/Village/Landscape/L_StarterValley_'+VERSION
DEST=SOURCE+'_Explore'
library=unreal.EditorAssetLibrary
assert not library.does_asset_exist(DEST), 'Keep existing exploration map intact'
assert library.duplicate_asset(SOURCE,DEST), 'Tour-map copy failed'
level=unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
assert level.load_level(DEST)
world=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
world.get_world_settings().set_editor_property('default_game_mode',unreal.GameModeBase)
default_mode=unreal.get_default_object(unreal.GameModeBase)
pawn_class=default_mode.get_editor_property('default_pawn_class')
assert pawn_class==unreal.DefaultPawn.static_class(), str(pawn_class)
assert unreal.get_default_object(unreal.DefaultPawn).get_editor_property('add_default_movement_bindings')
actors=unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
for actor in actors.get_all_level_actors():
    if isinstance(actor,unreal.PlayerStart):actors.destroy_actor(actor)
manifest=json.loads((ROOT/'terrain_manifest.json').read_text())
camera=next(row for row in manifest['cameras'] if row['name']=='CAM_01_Entrance')
x,y,z=camera['position_m'];tx,ty,tz=camera['target_m']
start=actors.spawn_actor_from_class(unreal.PlayerStart,unreal.Vector(x*100,-y*100,z*100))
start.set_actor_label('PLAYERSTART_VillageEntrance_Tour')
yaw=math.degrees(math.atan2(-(ty-y),tx-x))
pitch=math.degrees(math.atan2(tz-z,math.hypot(tx-x,ty-y)))
start.set_actor_rotation(unreal.Rotator(pitch=pitch,yaw=yaw),False)
assert level.save_current_level()
(ROOT/'explore_map.json').write_text(json.dumps({'map':DEST,'review_map_preserved':SOURCE,
    'spawn':{'position_m':[x,y,z],'yaw_degrees':yaw,'pitch_degrees':pitch},
    'mode':'DefaultPawn free flight tour; not RPG walking/gameplay acceptance',
    'controls':'WASD + mouse look, E up, Q down, Alt+F4 exits',
    'status':'SAVED_REQUIRES_RUNTIME_CHECK'},indent=2))
print('VILLAGE_EXPLORE_MAP_SAVED',DEST)
