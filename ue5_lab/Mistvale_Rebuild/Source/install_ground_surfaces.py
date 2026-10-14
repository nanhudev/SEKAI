import json
from pathlib import Path
import unreal

HERE = Path(__file__).resolve().parent
unreal.EditorLevelLibrary.load_level('/Game/Maps/L_Mistvale_Rebuild')
manifest = json.loads((HERE/'ground_surface_manifest.json').read_text())
tasks = []
for row in manifest:
    task = unreal.AssetImportTask()
    task.filename = row['file']
    task.destination_path = '/Game/MistvaleArt/GroundSurfaces'
    task.destination_name = row['name']
    task.automated = True
    task.save = True
    task.replace_existing = True
    tasks.append(task)
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks(tasks)
meshes = {r['name']:unreal.load_asset('/Game/MistvaleArt/GroundSurfaces/'+r['name']) for r in manifest}
if not all(meshes.values()):
    raise RuntimeError('Incomplete ground surface import; old roads retained')
mesh_editor = unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
terrain = unreal.load_asset('/Game/MistvaleArt/Terrain/SM_Mistvale_Terrain_Corrected')
for mesh in list(meshes.values())+[terrain]:
    settings = mesh.get_editor_property('nanite_settings')
    settings.enabled = False
    mesh.set_editor_property('nanite_settings', settings)
    mesh.get_editor_property('body_setup').set_editor_property('collision_trace_flag', unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
    unreal.EditorAssetLibrary.save_loaded_asset(mesh)
sub = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
actors = list(sub.get_all_level_actors())
existing = {a.get_actor_label():a for a in actors}
for name, mesh in meshes.items():
    label = 'ART_Surface_'+name
    actor = existing.get(label) or sub.spawn_actor_from_class(unreal.StaticMeshActor, unreal.Vector(0,0,0))
    actor.set_actor_label(label)
    actor.set_folder_path('ART/GroundSurfaces')
    actor.static_mesh_component.set_static_mesh(mesh)
    water = name.startswith('SM_River_')
    material = 'M_River_Surface_Proxy_01' if water else ('M_Weathered_Stone_01' if 'Plaza' in name else ('M_River_Track_01' if 'Dock' in name or 'Riverside' in name else 'M_Town_Road_01'))
    actor.static_mesh_component.set_material(0, unreal.load_asset('/Game/MistvaleArt/Materials/'+material))
    actor.set_actor_enable_collision(not water)
removed = []
for actor in actors:
    label = actor.get_actor_label()
    if str(actor.get_folder_path()) == 'Roads' or label.startswith('TEMP_River_'):
        removed.append(label)
        sub.destroy_actor(actor)
if not unreal.EditorLevelLibrary.save_current_level():
    raise RuntimeError('Map save failed')
report = {'installed':list(meshes), 'removed_actor_count':len(removed), 'remaining_actor_count':len(sub.get_all_level_actors()), 'terrain_nanite':False}
(HERE/'ground_surfaces_install_report.json').write_text(json.dumps(report,indent=2))
print('GROUND_SURFACES_INSTALLED',json.dumps(report))
