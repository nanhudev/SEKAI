import unreal,json
from pathlib import Path
HERE=Path(__file__).parent
assert unreal.EditorLevelLibrary.load_level('/Game/Maps/L_Mistvale_Rebuild')
data=json.loads((HERE/'handoff_geometry.json').read_text())
sub=unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
actors=list(sub.get_all_level_actors());by={a.get_actor_label():a for a in actors}
for row in data['meshes']:
 t=unreal.AssetImportTask();t.filename=row['file'];t.destination_path='/Game/MistvaleArt/GroundSurfaces';t.destination_name=row['name'];t.automated=True;t.save=True;t.replace_existing=True
 unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([t])
 mesh=unreal.load_asset(t.destination_path+'/'+row['name'])
 assert mesh
 a=by.get(row['name']) or sub.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector())
 a.set_actor_label(row['name']);a.set_folder_path('ART/Handoff');a.static_mesh_component.set_static_mesh(mesh)
 a.static_mesh_component.set_material(0,unreal.load_asset('/Game/MistvaleArt/Materials/M_Town_Road_01'))
for label in ['MainStoneBridge_SouthRamp','MainStoneBridge_NorthRamp']:
 if label in by:sub.destroy_actor(by[label])
checked=[];missing=[]
for a in sub.get_all_level_actors():
 if not isinstance(a,unreal.StaticMeshActor):continue
 c=a.static_mesh_component;m=c.static_mesh
 if not m:missing.append(a.get_actor_label());continue
 label=a.get_actor_label()
 if any(s in label for s in ['Terrain','Route','Plaza','Bridge','Handoff','NorthGate','TrainingYard']):
  if 'PARAPET' not in label:
   m.get_editor_property('body_setup').set_editor_property('collision_trace_flag',unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
   unreal.EditorAssetLibrary.save_loaded_asset(m)
  c.set_collision_profile_name('BlockAll');a.set_actor_enable_collision(True);checked.append(label)
starts=[a for a in sub.get_all_level_actors() if isinstance(a,unreal.PlayerStart)]
p=next((a for a in starts if a.get_actor_label()=='PlayerStart_MistvaleSouth'),None) or (starts[0] if starts else sub.spawn_actor_from_class(unreal.PlayerStart,unreal.Vector(*data['spawn'])))
p.set_actor_label('PlayerStart_MistvaleSouth');p.set_actor_location(unreal.Vector(*data['spawn']),False,False);p.set_actor_rotation(unreal.Rotator(0,90,0),False)
assert unreal.EditorLevelLibrary.save_current_level()
world=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
report={'map':world.get_path_name(),'player_start':p.get_actor_label(),'location_cm':data['spawn'],'rotation_degrees':{'pitch':0,'yaw':90,'roll':0},'collision_checked':checked,'missing_static_meshes':missing,'saved':True}
(HERE/'handoff_verified.json').write_text(json.dumps(report,indent=2))
print('HANDOFF_SAVED',json.dumps(report))
