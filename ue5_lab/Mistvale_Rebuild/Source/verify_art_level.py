"""Check saved town art placements against source terrain and expected assets."""
import json
import sys
from pathlib import Path
import unreal

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from generate_heightmap import elevation

unreal.EditorLevelLibrary.load_level("/Game/Maps/L_Mistvale_Rebuild")
actors=unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors()
labels={a.get_actor_label():a for a in actors}
expected=json.loads((HERE/"art_level_placements.json").read_text(encoding="utf-8"))
missing=[]
wrong=[]
ground=[]
for row in expected:
    label=row["label"]
    a=labels.get(label)
    if not a:
        missing.append(label)
        continue
    mesh=a.static_mesh_component.get_editor_property("static_mesh")
    if not mesh or not mesh.get_path_name().startswith("/Game/Fab/SlavicLite/"):
        wrong.append(label)
    origin,extent=a.get_actor_bounds(False)
    x,y=row["position_m"]
    bottom=(origin.z-extent.z)/100
    ground.append((abs(bottom-elevation(x,y)),label))
out={"level":"/Game/Maps/L_Mistvale_Rebuild", "actors":len(actors),
     "fab_replacements":len(expected), "missing":missing,
     "wrong_asset":wrong, "max_ground_offset_m":max(ground),
     "house_count":sum("_House_" in a.get_actor_label() or
                         a.get_actor_label().startswith(("InfillBuilding_","CornerBuilding_"))
                         for a in actors)}
(HERE/"art_level_verify.json").write_text(json.dumps(out,indent=2),encoding="utf-8")
print("ART_VERIFY",json.dumps(out))
if missing or wrong or out["fab_replacements"]<90:
    raise RuntimeError("Art-level replacement audit failed")
