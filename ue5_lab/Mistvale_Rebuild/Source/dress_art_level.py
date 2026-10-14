"""First on-map material and landmark pass for L_Mistvale_Rebuild.

This edits only the new art level. All additions are named and idempotent.
"""
import json
import math
import sys
from pathlib import Path

import unreal

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from generate_heightmap import elevation

LEVEL = "/Game/Maps/L_Mistvale_Rebuild"
MAT_DIR = "/Game/MistvaleArt/Materials"
unreal.EditorLevelLibrary.load_level(LEVEL)
actor_sys = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
actors = actor_sys.get_all_level_actors()
by_label = {a.get_actor_label(): a for a in actors}
asset_tools = unreal.AssetToolsHelpers.get_asset_tools()


def color_material(name, rgb, roughness):
    path = MAT_DIR + "/" + name
    mat = unreal.load_asset(path)
    if not mat:
        mat = asset_tools.create_asset(name, MAT_DIR, unreal.Material,
                                       unreal.MaterialFactoryNew())
        if not mat:
            raise RuntimeError("Cannot create material " + path)
        tint = unreal.MaterialEditingLibrary.create_material_expression(
            mat, unreal.MaterialExpressionConstant3Vector, -400, 0)
        tint.set_editor_property("constant", unreal.LinearColor(*rgb, 1.0))
        unreal.MaterialEditingLibrary.connect_material_property(
            tint, "", unreal.MaterialProperty.MP_BASE_COLOR)
        matte = unreal.MaterialEditingLibrary.create_material_expression(
            mat, unreal.MaterialExpressionConstant, -400, 200)
        matte.set_editor_property("r", roughness)
        unreal.MaterialEditingLibrary.connect_material_property(
            matte, "", unreal.MaterialProperty.MP_ROUGHNESS)
        unreal.MaterialEditingLibrary.recompile_material(mat)
        unreal.EditorAssetLibrary.save_loaded_asset(mat)
    return mat


grass = color_material("M_Valley_Grass_01", (0.31, 0.39, 0.22), .94)
road = color_material("M_Town_Road_01", (0.43, 0.34, 0.24), .91)
track = color_material("M_River_Track_01", (0.34, 0.29, 0.23), .92)
water = color_material("M_River_Surface_Proxy_01", (0.035, 0.22, 0.27), .17)
stone = color_material("M_Weathered_Stone_01", (0.45, 0.42, 0.34), .88)

counts = {"terrain": 0, "roads": 0, "water": 0, "stone": 0,
          "fences": 0, "landmarks": 0}

for a in actors:
    if not isinstance(a, unreal.StaticMeshActor):
        continue
    label = a.get_actor_label()
    if label.startswith("TEMP_Landscape_Proxy"):
        a.static_mesh_component.set_material(0, grass)
        counts["terrain"] += 1
    elif label.startswith("TEMP_River_"):
        a.static_mesh_component.set_material(0, water)
        counts["water"] += 1
    elif label.startswith(("GoldenRoute_", "LowerMarketLoop_",
                           "MarketEastLoop_", "UpperResidential_",
                           "ChurchLane_")):
        a.static_mesh_component.set_material(0, road)
        counts["roads"] += 1
    elif label.startswith(("RiversideStreet_", "DockTrack_")):
        a.static_mesh_component.set_material(0, track)
        counts["roads"] += 1
    elif label.startswith(("SmallServiceBridge_", "HERO_Guild_TrainingYard")):
        a.static_mesh_component.set_material(0, stone)
        counts["stone"] += 1


def loaded_mesh(name):
    obj = unreal.load_asset("/Game/Fab/SlavicLite/" + name)
    if not obj:
        raise RuntimeError("Missing imported art asset " + name)
    return obj


rock_gate = loaded_mesh("EA03_Fence_RockGate_01a_LOD0")
tower = loaded_mesh("EA03_Village_Tover_01a_LOD0")
fence = loaded_mesh("EA03_Fence_Cobble_01a_LOD0")


def fit_existing(label, mesh, scale, x, y, yaw=0):
    a = by_label[label]
    a.static_mesh_component.set_static_mesh(mesh)
    a.set_actor_scale3d(unreal.Vector(*scale))
    a.set_actor_location(unreal.Vector(x*100, y*100, elevation(x, y)*100), False, False)
    a.set_actor_rotation(unreal.Rotator(pitch=0, yaw=yaw, roll=0), False)
    a.set_folder_path("ART/Landmarks")
    counts["landmarks"] += 1


# Use the kit's actual open arch for the north gate. Keep the paired towers.
fit_existing("HERO_NorthGate_Lintel", rock_gate, (3.05, 1.65, 3.05), 0, 283)
# The source church bell tower was still an engine cube.
fit_existing("HERO_Church_BellTower", tower, (1.05, 1.05, 2.05), 99, 234)


def place_fence(label, x, y, yaw, scale=1.0):
    a = by_label.get(label)
    if not a:
        a = actor_sys.spawn_actor_from_class(
            unreal.StaticMeshActor,
            unreal.Vector(x*100, y*100, elevation(x, y)*100))
        a.set_actor_label(label)
        by_label[label] = a
    a.static_mesh_component.set_static_mesh(fence)
    a.set_actor_scale3d(unreal.Vector(scale, scale, scale))
    a.set_actor_location(unreal.Vector(x*100, y*100, elevation(x, y)*100), False, False)
    a.set_actor_rotation(unreal.Rotator(pitch=0, yaw=yaw, roll=0), False)
    a.set_folder_path("ART/Guild_Yard_Fence")
    counts["fences"] += 1


# Low stone fence around the training yard; east side stays open to the guild.
# Segments are spaced just under their imported 3.79 m length.
for side, x in (("W", -93.0),):
    for i in range(5):
        place_fence(f"ART_GuildFence_{side}_{i:02d}", x, 154.5+i*3.7, 90)
for side, y in (("S", 152.5), ("N", 171.5)):
    for i in range(6):
        place_fence(f"ART_GuildFence_{side}_{i:02d}", -91.0+i*3.7, y, 0)

unreal.EditorLevelLibrary.save_current_level()
out = {"level": LEVEL, "actors": len(actor_sys.get_all_level_actors()),
       "changed": counts}
(HERE / "art_dress_result.json").write_text(json.dumps(out, indent=2), encoding="utf-8")
print("ART_DRESS", json.dumps(out))
