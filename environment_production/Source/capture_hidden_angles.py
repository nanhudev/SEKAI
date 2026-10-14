"""Identical close-range diagnostic cameras in the actual UE world; no map edits saved."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
import math
import os
from pathlib import Path
import unreal

VERSION=os.environ['SEKAI_REVIEW_VERSION']
OUT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/VERSION/'Hidden_Review';OUT.mkdir(exist_ok=True)
MAP='/Game/Environment/Village/Landscape/L_StarterValley_'+VERSION
level=unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
world=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
if world.get_path_name().split('.')[0]!=MAP:assert level.load_level(MAP)
actors=unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
views=[
 ('01_Bridge_East',[-12,-51,5.0],[-20,-42,2.2]),
 ('02_Bridge_Under',[-41,-48.5,1.0],[-41,-42,2.7]),
 ('03_River_Edge',[-16,-30,5.3],[-19,-42,1.8]),
 ('04_Tree_RiverRear',[-18,48,11],[-2,47,14.1]),
 ('05_Tree_Roots',[3,39,15.2],[-1,48,13.8]),
 ('06_Tavern_Back',[44,62,13],[39,47,16.5]),
 ('07_Tavern_Side',[54,34,12.95],[39,40,16]),
 ('08_Road_Junction',[29,6,9.9],[20,16,8.2]),
 ('09_Cliff_Foot',[-44,25,10.4],[-68,34,15.8]),
 ('10_Plaza_Edge',[37,8,9.9],[25,14,8.4]),
 ('11_Tree_BackHigh',[-17,66,19],[-1,47,14]),
 ('12_Forge_Front',[34,20,10.1],[50.5,20,13.4]),
 ('13_Home_LowerBack',[-63,6,10.4],[-51,5,12.0]),
 ('14_Home_UpperSide',[-52,70,16.0],[-49,58,18.0]),
]
manifest=json.loads((OUT.parent/'terrain_manifest.json').read_text())
views.extend(manifest.get('additional_review_views',[]))
route=manifest['route_m']
for i,(a,b) in enumerate(zip(route,route[1:])):
    position=[(a[k]+b[k])*.5 for k in range(3)]
    position[2]+=1.65
    target=[b[0],b[1],b[2]+1.65]
    views.append(('ROUTE_%02d_Forward'%(i+1),position,target))
for label,index in [('Bridge',3),('Plaza',8),('Exit',11)]:
    x,y,z=route[index]
    for direction in [-1,1]:
        views.append(('TURN_'+label+('_Left' if direction<0 else '_Right'),
            [x,y,z+1.65],[x+direction*10,y,z+1.65]))
cameras=[]
for name,position,target in views:
    x,y,z=position;tx,ty,tz=target
    camera=actors.spawn_actor_from_class(unreal.CameraActor,unreal.Vector(x*100,-y*100,z*100))
    camera.set_actor_label('HIDDEN_'+name)
    yaw=math.degrees(math.atan2(-(ty-y),tx-x));pitch=math.degrees(math.atan2(tz-z,math.hypot(tx-x,ty-y)))
    camera.set_actor_rotation(unreal.Rotator(pitch=pitch,yaw=yaw),False)
    camera.camera_component.set_editor_property('field_of_view',75.0)
    cameras.append((name,camera))
(OUT/'camera_scope.json').write_text(json.dumps({'version':VERSION,'views':views,
    'scope':'Low free camera, eye-height viewpoints, side/rear/under-bridge and elevated inspection',
    'route_scope':'13 segment midpoint images at manifest route height plus 1.65m; six side looks. Camera inspection, not collision-tested player walking.',
    'map_saved':False,'acceptance':'REQUIRES_VISUAL_INSPECTION'},indent=2))
state={'frame':0,'index':0,'task':None,'cooldown':0}
def tick(dt):
    state['frame']+=1
    if state['frame']==100:
        for actor in actors.get_all_level_actors():
            if isinstance(actor,unreal.SkyLight):actor.light_component.recapture_sky()
    if state['frame']<300:return
    if state['task'] is not None:
        if not state['task'].is_task_done():return
        state['task']=None;state['index']+=1;state['cooldown']=state['frame']+45;return
    if state['frame']<state['cooldown']:return
    if state['index']==len(cameras):
        (OUT/'capture_result.json').write_text(json.dumps({'status':'CAPTURED_NOT_ACCEPTED',
            'expected_views':len(cameras),'files':[p.name for p in OUT.glob('*.png')]},indent=2))
        unreal.unregister_slate_post_tick_callback(handle)
        print('HIDDEN_ANGLE_CAPTURE_COMPLETE',VERSION,len(cameras));unreal.SystemLibrary.quit_editor();return
    name,camera=cameras[state['index']]
    state['task']=unreal.AutomationLibrary.take_high_res_screenshot(1280,720,str(OUT/(name+'.png')),camera=camera)
handle=unreal.register_slate_post_tick_callback(tick)
