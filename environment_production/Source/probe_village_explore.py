"""Check the real game-world spawn, possession and movement, then restore the entrance."""
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
OUT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/VERSION/'explore_runtime.json'
state={'frames':0,'pawn':None,'start':None,'elapsed':0.0}
WORLD_PATH='/Game/Environment/Village/Landscape/L_StarterValley_'+VERSION+'_Explore.L_StarterValley_'+VERSION+'_Explore'
def tick(dt):
    state['frames']+=1
    # Standalone -game uses GameEngine and has no editor subsystems.
    world=unreal.find_object(None,WORLD_PATH)
    if not world:return
    pawn=unreal.GameplayStatics.get_player_pawn(world,0)
    if not pawn:return
    if state['pawn'] is None:
        state['pawn']=pawn;state['start']=pawn.get_actor_location()
        assert isinstance(pawn,unreal.DefaultPawn),str(pawn)
        assert pawn.get_editor_property('add_default_movement_bindings')
        assert pawn.get_controller() is not None
        start=state['start']
        assert abs(start.x+5800)<200 and abs(start.y-10000)<200 and start.z>250,str(start)
        return
    state['elapsed']+=dt
    if state['elapsed']<1.5:
        pawn.add_movement_input(pawn.get_actor_forward_vector(),1.0,False)
        return
    start=state['start'];end=pawn.get_actor_location()
    distance=math.sqrt((end.x-start.x)**2+(end.y-start.y)**2+(end.z-start.z)**2)
    assert distance>100,'Tour pawn did not move'
    pawn.get_movement_component().stop_movement_immediately()
    pawn.set_actor_location(start,False,True)
    OUT.write_text(json.dumps({'status':'RUNTIME_SPAWN_POSSESSION_MOVEMENT_VERIFIED',
        'world':world.get_path_name(),'pawn_class':pawn.get_class().get_name(),
        'start_cm':[start.x,start.y,start.z],'movement_distance_cm':distance,
        'default_movement_bindings':True,'restored_to_entrance':True,
        'scope':'Real game world, programmatic movement. Physical keyboard/mouse not simulated.'},indent=2))
    unreal.unregister_slate_post_tick_callback(handle)
    print('VILLAGE_EXPLORE_RUNTIME_VERIFIED',distance)
    if os.environ.get('SEKAI_EXPLORE_VERIFY_EXIT')=='1':
        unreal.SystemLibrary.execute_console_command(world,'quit')
handle=unreal.register_slate_post_tick_callback(tick)
