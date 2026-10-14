"""Slate tick captures: actual UE rendered images, fixed settings, no auto acceptance."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import unreal
from pathlib import Path
import json
import os
VERSION=os.environ.get('SEKAI_REVIEW_VERSION','v001')
ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Versions'))/VERSION
OUT=ROOT/'UE_Review'
OUT.mkdir(exist_ok=True)
unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).load_level('/Game/Environment/Village/Review/L_Tavern_'+VERSION)
actors=unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors()
cameras=sorted([a for a in actors if a.get_actor_label().startswith('CAM_HERO_')],key=lambda a:a.get_actor_label())
if len(cameras)!=5:raise RuntimeError('Expected five fixed hero review cameras')
state={'frame':0,'index':0,'task':None,'cooldown':0}
def tick(dt):
    state['frame']+=1
    if state['frame']>9000:
        unreal.unregister_slate_post_tick_callback(handle)
        (OUT/'capture_failure.json').write_text(json.dumps({'reason':'Review capture exceeded the tick limit','state':str(state)}))
        unreal.SystemLibrary.quit_editor()
        return
    if state['frame']<300:return
    if state['task'] is not None:
        if not state['task'].is_task_done():return
        state['task']=None;state['cooldown']=state['frame']+60
        state['index']+=1
        return
    if state['frame']<state['cooldown']:return
    if state['index']==len(cameras):
        unreal.unregister_slate_post_tick_callback(handle)
        files=list(OUT.glob('*.png'))
        (OUT/'capture_result.json').write_text(json.dumps({'files':[str(f) for f in files],'engine':'UE5.8','status':'CAPTURED_NOT_ACCEPTED'},indent=2))
        print('SEKAI_CAPTURE_COMPLETE',len(files))
        unreal.SystemLibrary.quit_editor()
        return
    cam=cameras[state['index']]
    filename=str(OUT/(cam.get_actor_label()+'.png'))
    state['task']=unreal.AutomationLibrary.take_high_res_screenshot(1400,1000,filename,camera=cam)
    print('SEKAI_CAPTURE',filename)
handle=unreal.register_slate_post_tick_callback(tick)
