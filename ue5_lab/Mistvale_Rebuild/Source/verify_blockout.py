from pathlib import Path
import json
import unreal

level = "/Game/Maps/Mistvale_Rebuild_Blockout"
unreal.EditorLevelLibrary.load_level(level)
actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors()
labels = [a.get_actor_label() for a in actors]
required = ["TEMP_Landscape_Proxy_Replace_With_R16", "MainStoneBridge_DECK",
            "SmallServiceBridge_DECK", "HERO_Guild_HorizontalHall",
            "HERO_Church_BellTower", "HERO_NorthGate_Left",
            "SouthForest_PlayerStart", "C07_RooftopDensity",
            "MainStoneBridge_SouthRamp", "MainStoneBridge_NorthRamp"]
missing = [x for x in required if x not in labels]
terrain = unreal.load_asset("/Game/Blockout/SM_Mistvale_Terrain_Proxy")
collision = str(terrain.get_editor_property("body_setup").get_editor_property("collision_trace_flag"))
terrain_actor = next(a for a in actors if a.get_actor_label() == "TEMP_Landscape_Proxy_Replace_With_R16")
origin, extent = terrain_actor.get_actor_bounds(False)
guild_actor = next(a for a in actors if a.get_actor_label() == "HERO_Guild_HorizontalHall")
guild_origin, guild_extent = guild_actor.get_actor_bounds(False)
guild_asset = guild_actor.static_mesh_component.get_editor_property("static_mesh")
bridge_actor = next(a for a in actors if a.get_actor_label() == "MainStoneBridge_DECK")
bridge_asset = bridge_actor.static_mesh_component.get_editor_property("static_mesh")
bridge_origin, bridge_extent = bridge_actor.get_actor_bounds(False)
first_road = next(a for a in actors if a.get_actor_label() == "GoldenRoute_00_00")
first_river = next(a for a in actors if a.get_actor_label() == "TEMP_River_00")
out = Path(__file__).with_name("verify_result.txt")
out.write_text("\n".join([
    f"actor_count={len(actors)}",
    f"house_masses={sum('_House_' in x or x.startswith(('CornerBuilding_', 'InfillBuilding_')) for x in labels)}",
    f"river_segments={sum(x.startswith('TEMP_River_') for x in labels)}",
    f"review_cameras={sum(x.startswith(('C0','C10_')) for x in labels)}",
    f"terrain_collision={collision}",
    f"terrain_origin_cm={origin}",
    f"terrain_extent_cm={extent}",
    f"guild_asset={guild_asset.get_path_name()}",
    f"guild_origin_cm={guild_origin}",
    f"guild_extent_cm={guild_extent}",
    f"guild_material_slots={len(guild_asset.get_editor_property('static_materials'))}",
    f"main_bridge_asset={bridge_asset.get_path_name()}",
    f"main_bridge_origin_cm={bridge_origin}",
    f"main_bridge_extent_cm={bridge_extent}",
    f"main_bridge_collision={bridge_asset.get_editor_property('body_setup').get_editor_property('collision_trace_flag')}",
    f"south_road_yaw={first_road.get_actor_rotation().yaw:.1f}",
    f"water_collision_enabled={first_river.get_actor_enable_collision()}",
    f"missing={missing}",
]), encoding="utf-8")
layout = []
for a in actors:
    label = a.get_actor_label()
    if label.startswith(("GoldenRoute_", "LowerMarketLoop_", "MarketEastLoop_",
                         "RiversideStreet_", "UpperResidential_", "ChurchLane_",
                         "DockTrack_", "MainStoneBridge_DECK", "SmallServiceBridge_DECK",
                         "HERO_", "MarketStall_", "MarketSquare_", "CornerBuilding_",
                         "InfillBuilding_")) or "_House_" in label:
        p = a.get_actor_location()
        s = a.get_actor_scale3d()
        if label in ("HERO_Guild_HorizontalHall", "MainStoneBridge_DECK"):
            p, bounds = a.get_actor_bounds(False)
            sx, sy = bounds.x * 2 / 100, bounds.y * 2 / 100
        else:
            sx, sy = s.x, s.y
        layout.append({"name": label, "x": p.x/100, "y": p.y/100, "z": p.z/100,
                       "sx": sx, "sy": sy, "yaw": a.get_actor_rotation().yaw,
                       "pitch": a.get_actor_rotation().pitch})
Path(__file__).with_name("blockout_layout.json").write_text(
    json.dumps(layout, indent=2), encoding="utf-8")
if missing or len(actors) < 350 or abs(first_road.get_actor_rotation().yaw-90) > 15 or first_river.get_actor_enable_collision():
    raise RuntimeError("Blockout audit failed: " + str(missing))
