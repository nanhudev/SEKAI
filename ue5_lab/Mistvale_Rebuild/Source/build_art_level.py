"""Turn the saved spatial plan into the first real Mistvale UE art level.

The source blockout stays intact. This creates /Game/Maps/L_Mistvale_Rebuild
and replaces town boxes with the owned Fab town kit at authored parcel sites.
"""
import json
import math
import sys
from pathlib import Path
import unreal

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from generate_heightmap import elevation

SOURCE_LEVEL = "/Game/Maps/Mistvale_Rebuild_Blockout"
ART_LEVEL = "/Game/Maps/L_Mistvale_Rebuild"
if not unreal.EditorAssetLibrary.does_asset_exist(ART_LEVEL):
    if not unreal.EditorAssetLibrary.duplicate_asset(SOURCE_LEVEL, ART_LEVEL):
        raise RuntimeError("Could not create art level")
unreal.EditorLevelLibrary.load_level(ART_LEVEL)
actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

index = {row["name"]: row for row in json.loads(
    (HERE / "slavic_mesh_dimensions.json").read_text(encoding="utf-8"))}


def mesh(name):
    row = index[name]
    asset = unreal.load_asset(row["asset"])
    if not asset:
        raise RuntimeError("Missing Fab mesh: " + name)
    asset.get_editor_property("body_setup").set_editor_property(
        "collision_trace_flag", unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
    unreal.EditorAssetLibrary.save_loaded_asset(asset)
    return asset, row["size_m"]


names = {
    "cubby": "EA03_Village_OutBuilding_Cubby_01d_LOD0",
    "pent": "EA03_Village_OutBuilding_PentHouse_01a_LOD0",
    "shed": "EA03_Village_OutBuilding_Shed_01a_LOD0",
    "wide_shed": "EA03_Village_OutBuilding_Shed_03b_LOD0",
    "admin": "EA03_Town_Building_Administrative__01a_LOD0",
    "tower": "EA03_Village_Tover_01a_LOD0",
    "woodroof": "EA03_Village_OutBuilding_WoodRoof_01b_LOD0",
}
models = {key: mesh(value) for key, value in names.items()}


def replace(a, kind, target_w, target_d, yaw=None, margin=.94):
    asset, dims = models[kind]
    x, y = a.get_actor_location().x/100, a.get_actor_location().y/100
    new_yaw = a.get_actor_rotation().yaw if yaw is None else yaw
    turned = int(round(new_yaw / 90)) % 2 == 1
    base_w, base_d = (dims[1], dims[0]) if turned else (dims[0], dims[1])
    scale = min(1.22, target_w*margin/base_w, target_d*margin/base_d)
    a.static_mesh_component.set_static_mesh(asset)
    a.set_actor_scale3d(unreal.Vector(scale,scale,scale))
    a.set_actor_location(unreal.Vector(x*100,y*100,elevation(x,y)*100),False,False)
    a.set_actor_rotation(unreal.Rotator(pitch=0,yaw=new_yaw,roll=0),False)
    a.set_folder_path("ART/Fab_SlavicLite/" + kind)
    return {"label": a.get_actor_label(), "kind":kind,
            "position_m":[round(x,1),round(y,1)],"scale":round(scale,3)}


changed=[]
for actor in actors.get_all_level_actors():
    label=actor.get_actor_label()
    if not isinstance(actor, unreal.StaticMeshActor):
        continue
    if str(actor.get_folder_path()).startswith("ART/"):
        continue
    old=actor.get_actor_scale3d()
    if "_House_" in label or label.startswith("InfillBuilding_"):
        # Repeated neighbourhood shapes use three house silhouettes, changing
        # the mix by district and turning selected lots toward alley bends.
        seed=sum(ord(c) for c in label)
        kind=("cubby","pent","shed")[(seed + (seed//7)) % 3]
        changed.append(replace(actor,kind,old.x,old.y,margin=.96))
    elif label.startswith("CornerBuilding_"):
        changed.append(replace(actor,"admin",old.x,old.y,margin=.96))
    elif label=="HERO_MainInn":
        changed.append(replace(actor,"admin",20,14,yaw=0))
    elif label=="HERO_Blacksmith":
        changed.append(replace(actor,"shed",15,13,yaw=90))
    elif label=="HERO_DockWarehouse":
        changed.append(replace(actor,"wide_shed",26,14,yaw=90))
    elif label=="HERO_Church_Nave":
        changed.append(replace(actor,"admin",18,32,yaw=90))
    elif label in ("HERO_NorthGate_Left","HERO_NorthGate_Right"):
        changed.append(replace(actor,"tower",7,9,yaw=0))
    elif label.startswith("MarketStall_"):
        changed.append(replace(actor,"woodroof",3.4,2.5,
                               yaw=0 if sum(ord(c) for c in label)%2 else 180))

unreal.EditorLevelLibrary.save_current_level()
out=HERE / "art_level_placements.json"
out.write_text(json.dumps(changed,indent=2),encoding="utf-8")
print("ART_LEVEL",ART_LEVEL,"FAB_REPLACEMENTS",len(changed),"RESULT",out)
