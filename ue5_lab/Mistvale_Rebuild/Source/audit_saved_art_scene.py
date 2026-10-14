"""Read back actual UE geometry/transforms and export a complete visual review."""
import json
from pathlib import Path
import unreal

HERE=Path(__file__).resolve().parent
unreal.EditorLevelLibrary.load_level('/Game/Maps/L_Mistvale_Rebuild')
world=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
actors=unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors()
rows=[]
terrain=None
def xyz(v): return [v.x/100,v.y/100,v.z/100]
for a in actors:
    if not isinstance(a,unreal.StaticMeshActor):continue
    p=a.get_actor_location(); s=a.get_actor_scale3d(); r=a.get_actor_rotation()
    o,e=a.get_actor_bounds(False)
    mesh=a.static_mesh_component.get_editor_property('static_mesh')
    rows.append({'label':a.get_actor_label(),'folder':str(a.get_folder_path()),
                 'position_m':xyz(p),'scale':[s.x,s.y,s.z],
                 'rotation':[r.pitch,r.yaw,r.roll],
                 'bounds_center_m':xyz(o),'bounds_extent_m':xyz(e),
                 'mesh':mesh.get_path_name() if mesh else None,
                 'materials':[a.static_mesh_component.get_material(i).get_name()
                    if a.static_mesh_component.get_material(i) else None
                    for i in range(a.static_mesh_component.get_num_materials())]})
    if a.get_actor_label()=='ART_Graded_Terrain_Proxy':terrain=a
(HERE/'saved_art_scene.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
if not terrain:raise RuntimeError('Saved terrain actor missing')
o,e=terrain.get_actor_bounds(False)
if not (abs(e.x*2/100-504)<1 and abs(e.y*2/100-706)<1 and e.z*2/100<60):
    raise RuntimeError('Unexpected terrain dimensions: '+str(e))
traces=[]
ignored=[a for a in actors if a!=terrain]
for x,y in [(0,0),(0,100),(-175,-152.65),(-55,165),(115.43,207.74),(0,283),(0,-88)]:
    try:
        h=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x*100,y*100,10000),
            unreal.Vector(x*100,y*100,-10000),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,
            True,ignored,unreal.DrawDebugTrace.NONE,False)
        traces.append({'xy':[x,y],'result':str(h)})
    except Exception as ex:traces.append({'xy':[x,y],'error':str(ex)})
report={'terrain_size_m':xyz(e*2),'terrain_center_m':xyz(o),'traces':traces}
(HERE/'saved_terrain_audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
task=unreal.AssetExportTask()
task.object=world
task.exporter=unreal.LevelExporterFBX()
task.filename=str(HERE/'Mistvale_ActualScene_Review.fbx')
task.automated=True
task.prompt=False
unreal.get_editor_subsystem(unreal.EditorActorSubsystem).set_selected_level_actors(
    [a for a in actors if isinstance(a,unreal.StaticMeshActor)])
task.selected=False
task.replace_identical=True
options=unreal.FbxExportOption()
options.ascii=False
options.collision=False
options.level_of_detail=False
options.bake_material_inputs=unreal.FbxMaterialBakeMode.DISABLED
task.options=options
if not unreal.Exporter.run_asset_export_task(task):raise RuntimeError('Scene FBX export failed')
print('SAVED_SCENE_AUDIT',json.dumps(report))
