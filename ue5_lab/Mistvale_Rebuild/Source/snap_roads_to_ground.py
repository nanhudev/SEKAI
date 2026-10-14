"""Re-seat the existing route strips after town-pad grading and audit contact."""
import json
import sys
from pathlib import Path

import unreal

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from grade_town_ground import graded_elevation

unreal.EditorLevelLibrary.load_level("/Game/Maps/L_Mistvale_Rebuild")
actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors()
by_label = {a.get_actor_label():a for a in actors}

road_moves=[]
for a in actors:
    if not isinstance(a, unreal.StaticMeshActor):
        continue
    if str(a.get_folder_path()) != "Roads":
        continue
    p=a.get_actor_location()
    x,y=p.x/100,p.y/100
    target=graded_elevation(x,y)-.045
    road_moves.append((abs(target-p.z/100),a.get_actor_label()))
    a.set_actor_location(unreal.Vector(p.x,p.y,target*100),False,False)

building_gaps=[]
for a in actors:
    if not isinstance(a, unreal.StaticMeshActor):
        continue
    label=a.get_actor_label()
    if not str(a.get_folder_path()).startswith("ART/Fab_SlavicLite/"):
        continue
    o,e=a.get_actor_bounds(False)
    x,y=o.x/100,o.y/100
    bottom=(o.z-e.z)/100
    building_gaps.append((round(bottom-graded_elevation(x,y),3),label))

riverside=[]
for i in range(1,10):
    a=by_label[f"Riverside_House_{i:02d}"]
    p=a.get_actor_location()
    riverside.append((round(p.x/100,1),round(p.y/100,1)))

if not unreal.EditorLevelLibrary.save_current_level():
    raise RuntimeError("Cannot save road alignment")

out={"roads_reseated":len(road_moves),
     "largest_road_shift_m":max(road_moves),
     "building_bottom_gap_m":{
         "min":min(building_gaps)[0],
         "max":max(building_gaps)[0],
         "largest_abs":sorted(building_gaps,key=lambda r:abs(r[0]),reverse=True)[:10]},
     "riverside_positions_m":riverside,
     "terrain_asset":by_label["ART_Graded_Terrain_Proxy"].static_mesh_component.static_mesh.get_path_name(),
     "foundations":sum(a.get_actor_label().startswith("ART_Foundation_") for a in actors)}
(HERE/"ground_final_audit.json").write_text(
    json.dumps(out,indent=2),encoding="utf-8")
print("GROUND_FINAL_AUDIT",json.dumps(out))
