"""Capture actual time-separated river frames in UE; no synthetic scrolling."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
import math
import os
import time
from pathlib import Path
import unreal

version=os.environ['SEKAI_REVIEW_VERSION']
out=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/version/'Water_Motion'
out.mkdir(exist_ok=True)
world=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
map_path='/Game/Environment/Village/Landscape/L_StarterValley_'+version
if world.get_path_name().split('.')[0]!=map_path:
    assert unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).load_level(map_path)
world=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
assert world.get_path_name().split('.')[0]==map_path
actors=unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
pos=unreal.Vector(-4100,5900,380);target=unreal.Vector(-4000,3200,140)
camera=actors.spawn_actor_from_class(unreal.CameraActor,pos)
camera.set_actor_rotation(unreal.MathLibrary.find_look_at_rotation(pos,target),False)
camera.camera_component.set_editor_property('field_of_view',75.0)
camera.set_actor_label('WATER_MOTION_FIXED_DIAGNOSTIC')
cloud_mat=unreal.load_asset('/Engine/EngineSky/VolumetricClouds/m_SimpleVolumetricCloud_Inst')
cloud_names=unreal.MaterialEditingLibrary.get_scalar_parameter_names(cloud_mat)
cloud_parent=unreal.load_asset('/Engine/EngineSky/VolumetricClouds/m_SimpleVolumetricCloud')
(out/'cloud_material_parameters.json').write_text(json.dumps({
    'defaults':{str(n):unreal.MaterialEditingLibrary.get_material_default_scalar_parameter_value(cloud_parent,n) for n in cloud_names},
    'overrides':{str(row.parameter_info.name):row.parameter_value for row in cloud_mat.get_editor_property('scalar_parameter_values')}},indent=2))
unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).editor_set_viewport_realtime(True)
state={'frame':0,'task':None,'index':0,'next_time':0,'times':[],'requesting':False}
def tick(dt):
    if state['requesting']:return
    state['frame']+=1
    if state['frame']<300:return
    if state['task'] is not None:
        if not state['task'].is_task_done():return
        state['task']=None;state['index']+=1;state['next_time']=time.monotonic()+1.2
        return
    if time.monotonic()<state['next_time']:return
    if state['index']==6:
        (out/'motion_capture.json').write_text(json.dumps({'version':version,'world':world.get_path_name(),'frames':state['times'],
            'camera_position_cm':[pos.x,pos.y,pos.z],'camera_target_cm':[target.x,target.y,target.z],
            'scope':'Actual UE frames separated by real elapsed time. No camera/material phase changes; not physical fluid simulation.',
            'status':'CAPTURED_REQUIRES_MOTION_INSPECTION'},indent=2))
        unreal.unregister_slate_post_tick_callback(handle);unreal.SystemLibrary.quit_editor();return
    filename='flow_%02d.png'%state['index']
    state['requesting']=True
    try:
        state['task']=unreal.AutomationLibrary.take_high_res_screenshot(1280,720,str(out/filename),camera=camera)
    finally:
        state['requesting']=False
    if state['task'] is not None:
        state['times'].append({'file':filename,'monotonic_seconds':time.monotonic(),
            'world_real_seconds':unreal.GameplayStatics.get_real_time_seconds(world)})
handle=unreal.register_slate_post_tick_callback(tick)
