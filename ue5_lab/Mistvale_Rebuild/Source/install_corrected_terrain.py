import json
from pathlib import Path
import unreal
HERE=Path(__file__).resolve().parent
unreal.EditorLevelLibrary.load_level('/Game/Maps/L_Mistvale_Rebuild')
t=unreal.AssetImportTask()
t.filename=str(HERE/'Mistvale_Terrain_UE.obj')
t.destination_path='/Game/MistvaleArt/Terrain'
t.destination_name='SM_Mistvale_Terrain_Corrected'
t.automated=True;t.save=True;t.replace_existing=True
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([t])
m=unreal.load_asset('/Game/MistvaleArt/Terrain/SM_Mistvale_Terrain_Corrected')
if not m:raise RuntimeError('Corrected terrain import missing')
m.get_editor_property('body_setup').set_editor_property('collision_trace_flag',
    unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
unreal.EditorAssetLibrary.save_loaded_asset(m)
actors=unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors()
a=next(a for a in actors if a.get_actor_label()=='ART_Graded_Terrain_Proxy')
a.static_mesh_component.set_static_mesh(m)
a.static_mesh_component.set_material(0,unreal.load_asset('/Game/MistvaleArt/Materials/M_Valley_Grass_01'))
if not unreal.EditorLevelLibrary.save_current_level():raise RuntimeError('Map save failed')
print('TERRAIN_HANDEDNESS_FIXED',m.get_path_name())
