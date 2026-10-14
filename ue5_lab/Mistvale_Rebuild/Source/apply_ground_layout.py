"""Install graded art terrain and ground every town building in the new map."""
import json
import sys
from pathlib import Path

import unreal

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from grade_town_ground import RELOCATIONS, graded_elevation
import correct_terrain_handedness

LEVEL = "/Game/Maps/L_Mistvale_Rebuild"
unreal.EditorLevelLibrary.load_level(LEVEL)
actor_sys = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
by_label = {a.get_actor_label(): a for a in actor_sys.get_all_level_actors()}

task = unreal.AssetImportTask()
task.filename = str(HERE / "Mistvale_Terrain_UE.obj")
task.destination_path = "/Game/MistvaleArt/Terrain"
task.destination_name = "SM_Mistvale_Terrain_Corrected"
task.automated = True
task.save = True
task.replace_existing = True
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task])
terrain_mesh = unreal.load_asset(
    "/Game/MistvaleArt/Terrain/SM_Mistvale_Terrain_Corrected")
if not terrain_mesh:
    raise RuntimeError("Art terrain import failed")
terrain_mesh.get_editor_property("body_setup").set_editor_property(
    "collision_trace_flag", unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
unreal.EditorAssetLibrary.save_loaded_asset(terrain_mesh)
terrain = by_label.get("ART_Graded_Terrain_Proxy") or by_label[
    "TEMP_Landscape_Proxy_Replace_With_R16"]
terrain.static_mesh_component.set_static_mesh(terrain_mesh)
grass = unreal.load_asset("/Game/MistvaleArt/Materials/M_Valley_Grass_01")
terrain.static_mesh_component.set_material(0, grass)
terrain.set_actor_label("ART_Graded_Terrain_Proxy")
terrain.set_folder_path("ART/Terrain_Graded")

cube = unreal.load_asset("/Engine/BasicShapes/Cube.Cube")
stone = unreal.load_asset("/Game/MistvaleArt/Materials/M_Weathered_Stone_01")
if not cube or not stone:
    raise RuntimeError("Foundation assets missing")

resettled = []
foundations = 0
max_lift = 0.0
max_corner_gap = 0.0
for label, actor in list(by_label.items()):
    if not isinstance(actor, unreal.StaticMeshActor):
        continue
    art_house = str(actor.get_folder_path()).startswith("ART/Fab_SlavicLite/")
    landmark = label in ("HERO_Guild_HorizontalHall", "HERO_Church_BellTower",
                         "HERO_NorthGate_Lintel", "HERO_NorthGate_Left",
                         "HERO_NorthGate_Right")
    if not art_house and not landmark:
        continue
    if label in RELOCATIONS:
        x, y = RELOCATIONS[label]
        p = actor.get_actor_location()
        actor.set_actor_location(unreal.Vector(x*100,y*100,p.z),False,False)
        resettled.append(label)
    origin, extent = actor.get_actor_bounds(False)
    cx,cy = origin.x/100,origin.y/100
    hx,hy = extent.x/100*.80,extent.y/100*.80
    # Support at the highest ground point inside the footprint, then fill the
    # remaining small down-slope gap with a visible stone foundation.
    samples = [graded_elevation(cx,cy)]
    for sx in (-1,1):
        for sy in (-1,1):
            samples.append(graded_elevation(cx+sx*hx,cy+sy*hy))
    target_bottom = max(samples) + .035
    max_corner_gap = max(max_corner_gap, max(samples)-min(samples))
    current_bottom = (origin.z-extent.z)/100
    lift = target_bottom-current_bottom
    p = actor.get_actor_location()
    actor.set_actor_location(unreal.Vector(p.x,p.y,p.z+lift*100),False,False)
    max_lift = max(max_lift,abs(lift))

    if not art_house or label.startswith("MarketStall_"):
        continue
    base_name = "ART_Foundation_" + label
    foundation = by_label.get(base_name)
    if not foundation:
        foundation = actor_sys.spawn_actor_from_class(
            unreal.StaticMeshActor,
            unreal.Vector(cx*100,cy*100,(target_bottom-.45)*100))
        foundation.set_actor_label(base_name)
        by_label[base_name] = foundation
    foundation.static_mesh_component.set_static_mesh(cube)
    foundation.static_mesh_component.set_material(0, stone)
    foundation.set_actor_location(unreal.Vector(
        cx*100,cy*100,(target_bottom-.45)*100),False,False)
    foundation.set_actor_scale3d(unreal.Vector(
        max(1.0,extent.x/100*1.82),
        max(1.0,extent.y/100*1.82),.90))
    foundation.set_folder_path("ART/Building_Foundations")
    foundations += 1

if not unreal.EditorLevelLibrary.save_current_level():
    raise RuntimeError("Could not save graded art level")

out = {"level":LEVEL,"terrain_asset":terrain_mesh.get_path_name(),
       "buildings_resettled":len(resettled),
       "foundations":foundations,
       "max_actor_vertical_adjust_m":round(max_lift,3),
       "max_sampled_footprint_relief_m":round(max_corner_gap,3),
       "actors":len(actor_sys.get_all_level_actors())}
(HERE/"apply_ground_result.json").write_text(
    json.dumps(out,indent=2),encoding="utf-8")
print("GROUND_APPLY",json.dumps(out))
