"""Transient water-clock experiment in the actual map, with a repeated static control."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import unreal,os,json
from pathlib import Path
version=os.environ['SEKAI_REVIEW_VERSION']
out=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/version/'Water_Viewport_Probe';out.mkdir(exist_ok=True)
world=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
map_path='/Game/Environment/Village/Landscape/L_StarterValley_'+version
if world.get_path_name().split('.')[0]!=map_path:
    assert unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).load_level(map_path)
world=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
assert world.get_path_name().split('.')[0]==map_path
actors=unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
materials=[]
for actor in actors.get_all_level_actors():
    if not isinstance(actor,unreal.StaticMeshActor):continue
    component=actor.static_mesh_component
    for index in range(component.get_num_materials()):
        original=component.get_material(index)
        if original and original.get_name() in ['MV_Valley_Water_Prototype','MV_Valley_FallingWater','MV_Valley_Foam_Detail']:
            material=unreal.MaterialLibrary.create_dynamic_material_instance(world,original)
            assert material
            material.set_scalar_parameter_value('WaterUseRuntimeTime',0.0)
            material.set_scalar_parameter_value('WaterFlowTestTime',0.0)
            component.set_material(index,material);materials.append(material)
assert len(materials)>=2,'Water test materials were not bound'
for command in ['r.AntiAliasingMethod 0','r.DynamicGlobalIlluminationMethod 0','r.ReflectionMethod 0','r.SSR.Quality 0','r.Shadow.Virtual.SMRT.RayCountDirectional 0']:
    unreal.SystemLibrary.execute_console_command(world,command)
camera=actors.spawn_actor_from_class(unreal.CameraActor,unreal.Vector(-4100,5900,380))
camera.set_actor_rotation(unreal.MathLibrary.find_look_at_rotation(camera.get_actor_location(),unreal.Vector(-4000,3200,140)),False)
camera.camera_component.set_editor_property('field_of_view',75.0)
unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).pilot_level_actor(camera)
unreal.get_editor_subsystem(unreal.LevelEditorSubsystem).editor_set_viewport_realtime(True)
phases=[0,0,.8,1.6,2.4]
state={'frame':0,'index':0,'task':None,'busy':False,'wait':300,'prepared':False,'parameters':[]}
def tick(dt):
    if state['busy']:return
    state['frame']+=1
    if state['task'] is not None:
        if not state['task'].is_task_done():return
        state['task']=None;state['index']+=1;state['wait']=state['frame']+45;state['prepared']=False
    if state['index']==len(phases):
        (out/'capture_scope.json').write_text(json.dumps({'world':world.get_path_name(),'phases':phases,'materials':len(materials),
            'parameters':state['parameters'],
            'scope':'Actual rendered frames; runtime water time disabled, explicit water phase only. First two frames identical phase control. Diagnostic AA, GI, reflection and stochastic shadow filtering disabled to isolate animation. Map not saved.'},indent=2))
        unreal.unregister_slate_post_tick_callback(handle);unreal.SystemLibrary.quit_editor();return
    if not state['prepared']:
        for material in materials:material.set_scalar_parameter_value('WaterFlowTestTime',phases[state['index']])
        state['parameters'].append([{'runtime_time':mat.get_scalar_parameter_value('WaterUseRuntimeTime'),'test_time':mat.get_scalar_parameter_value('WaterFlowTestTime')} for mat in materials])
        state['prepared']=True
    if state['frame']<state['wait'] or unreal.SystemLibrary.get_frame_count()%8!=1:return
    state['busy']=True
    try:state['task']=unreal.AutomationLibrary.take_high_res_screenshot(1280,720,str(out/('phase_%02d.png'%state['index'])))
    finally:state['busy']=False
handle=unreal.register_slate_post_tick_callback(tick)
