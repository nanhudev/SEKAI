"""Import the locally owned Slavic Medieval Town Kit Lite building family."""
import json
from pathlib import Path
import unreal

SOURCE = Path(r"C:\ProgramData\Epic\EpicGamesLauncher\VaultCache\FabLibrary\Slavic_Medieval_Town_Kit_-_Lite__Free_Starter_Pack_-b99a0776\fbx\fbx_extracted\FBX")
DEST = "/Game/Fab/SlavicLite"
NAMES = [
    "EA03_Town_Building_Administrative _01a",
    "EA03_Village_AnimalBreeding_Hovel_01a",
    "EA03_Village_OutBuilding_Convenience_01a",
    "EA03_Village_OutBuilding_Cubby_01d",
    "EA03_Village_OutBuilding_PentHouse_01a",
    "EA03_Village_OutBuilding_Shed_01a",
    "EA03_Village_OutBuilding_Shed_03b",
    "EA03_Village_OutBuilding_WoodRoof_01b",
    "EA03_Village_Tover_01a",
    "EA03_Village_HouseModule_Porch_01d",
    "EA03_Village_HouseModule_Porch_R_03b",
    "EA03_Village_Hut_Roof_01c",
    "EA03_Village_Hut_Wall_Front_02d",
    "EA03_Village_Hut_Wall_Painted_Front_02a",
    "EA03_Village_Hut_Wall_Painted_Side_02c",
    "EA03_Fence_Cobble_01a",
    "EA03_Fence_RockGate_01a",
    "EA03_Fence_Plank_02a",
    "EA03_Prop_House_Door_01b",
    "EA03_Village_platform_01a",
]
tasks = []
for stem in NAMES:
    path = SOURCE / (stem + ".fbx")
    if not path.is_file():
        raise FileNotFoundError(path)
    task = unreal.AssetImportTask()
    task.filename = str(path)
    task.destination_path = DEST
    task.destination_name = "SM_" + stem.replace(" ", "")
    task.automated = True
    task.save = True
    task.replace_existing = False
    tasks.append(task)
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks(tasks)

result = []
for task in tasks:
    mesh = unreal.load_asset(DEST + "/" + task.destination_name)
    if not mesh:
        raise RuntimeError("Failed to import " + task.destination_name)
    mesh.get_editor_property("body_setup").set_editor_property(
        "collision_trace_flag", unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
    unreal.EditorAssetLibrary.save_loaded_asset(mesh)
    result.append({"asset": mesh.get_path_name(), "source": task.filename,
                   "materials": len(mesh.get_editor_property("static_materials"))})
out = Path(__file__).with_name("slavic_import_result.json")
out.write_text(json.dumps(result, indent=2), encoding="utf-8")
print("SLAVIC_IMPORT_COUNT", len(result), "RESULT", out)
