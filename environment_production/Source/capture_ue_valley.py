"""Capture the six fixed valley cameras in the actual engine."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
import os
from pathlib import Path
import unreal
VERSION=os.environ.get('SEKAI_REVIEW_VERSION','v003')
OUT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/VERSION/'UE_Review'
OUT.mkdir(exist_ok=True)
map_path='/Game/Environment/Village/Landscape/L_StarterValley_'+VERSION
world=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
if world.get_path_name().split('.')[0]!=map_path:
    assert unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).load_level(map_path)
world=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
assert world.get_path_name().split('.')[0]==map_path
actors=unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors()
cameras=sorted([a for a in actors
    if a.get_actor_label().startswith('CAM_')],key=lambda a:a.get_actor_label())
if len(cameras)!=6:raise RuntimeError('Expected six review cameras')
lighting=[]
for actor in actors:
    if isinstance(actor,(unreal.SkyLight,unreal.DirectionalLight)):
        c=actor.light_component
        row={'actor':actor.get_actor_label(),'mobility':str(c.get_editor_property('mobility')),
             'intensity':c.get_editor_property('intensity')}
        if isinstance(actor,unreal.SkyLight):row['real_time_capture']=c.get_editor_property('real_time_capture')
        if isinstance(actor,unreal.DirectionalLight):
            row['use_temperature']=c.get_editor_property('use_temperature')
            row['temperature_kelvin']=c.get_editor_property('temperature')
        lighting.append(row)
    if isinstance(actor,unreal.SkyAtmosphere):
        c=actor.get_component_by_class(unreal.SkyAtmosphereComponent)
        factor=c.get_editor_property('sky_luminance_factor')
        lighting.append({'actor':actor.get_actor_label(),'sky_luminance_factor':[factor.r,factor.g,factor.b]})
(OUT/'lighting_state.json').write_text(json.dumps(lighting,indent=2))
bindings=[]
for actor in actors:
    if not isinstance(actor,unreal.StaticMeshActor):continue
    component=actor.static_mesh_component
    rows=[component.get_material(i).get_path_name() for i in range(component.get_num_materials())]
    bindings.append({'actor':actor.get_actor_label(),'materials':rows})
(OUT/'scene_bindings.json').write_text(json.dumps(bindings,indent=2))
if any('/Engine/EngineMaterials/WorldGridMaterial' in path for row in bindings for path in row['materials']):
    raise RuntimeError('Default checker material still present; scene bindings recorded')
state={'frame':0,'index':0,'task':None,'cooldown':0}
def tick(dt):
    state['frame']+=1
    if state['frame']==100:
        for actor in actors:
            if isinstance(actor,unreal.SkyLight):actor.light_component.recapture_sky()
    if state['frame']>9000:
        unreal.unregister_slate_post_tick_callback(handle)
        (OUT/'capture_failure.json').write_text(json.dumps({'state':str(state)}))
        unreal.SystemLibrary.quit_editor();return
    if state['frame']<300:return
    if state['task'] is not None:
        if not state['task'].is_task_done():return
        state['task']=None;state['cooldown']=state['frame']+60;state['index']+=1;return
    if state['frame']<state['cooldown']:return
    if state['index']==len(cameras):
        unreal.unregister_slate_post_tick_callback(handle)
        files=list(OUT.glob('*.png'))
        (OUT/'capture_result.json').write_text(json.dumps({'files':[str(f) for f in files],'status':'CAPTURED_NOT_ACCEPTED'},indent=2))
        print('SEKAI_CAPTURE_COMPLETE',len(files));unreal.SystemLibrary.quit_editor();return
    cam=cameras[state['index']]
    state['task']=unreal.AutomationLibrary.take_high_res_screenshot(1400,1000,str(OUT/(cam.get_actor_label()+'.png')),camera=cam)
handle=unreal.register_slate_post_tick_callback(tick)
