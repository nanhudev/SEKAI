"""Give the downloaded geometry an authored roof/wall palette.

The Fab FBX refers to a texture on the vendor's H: drive. That texture is not
in the downloaded FBX package, so the imported material renders white. These
local UE materials restore readable town massing without modifying source FBX.
"""
import json
from pathlib import Path
import unreal

HERE = Path(__file__).resolve().parent
LEVEL = "/Game/Maps/L_Mistvale_Rebuild"
DIR = "/Game/MistvaleArt/Materials"
unreal.EditorLevelLibrary.load_level(LEVEL)
actor_sys = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
tools = unreal.AssetToolsHelpers.get_asset_tools()


def expr(mat, cls, x, y):
    return unreal.MaterialEditingLibrary.create_material_expression(mat, cls, x, y)


def link(src, dst, input_name):
    unreal.MaterialEditingLibrary.connect_material_expressions(src, "", dst, input_name)


def make_palette(name, wall, roof):
    path = DIR + "/" + name
    mat = unreal.load_asset(path)
    if mat:
        return mat
    mat = tools.create_asset(name, DIR, unreal.Material, unreal.MaterialFactoryNew())
    if not mat:
        raise RuntimeError("Cannot create " + path)

    wall_c = expr(mat, unreal.MaterialExpressionConstant3Vector, -560, -190)
    wall_c.set_editor_property("constant", unreal.LinearColor(*wall, 1))
    roof_c = expr(mat, unreal.MaterialExpressionConstant3Vector, -560, -40)
    roof_c.set_editor_property("constant", unreal.LinearColor(*roof, 1))
    normal = expr(mat, unreal.MaterialExpressionVertexNormalWS, -760, 160)
    blue = expr(mat, unreal.MaterialExpressionComponentMask, -560, 160)
    blue.set_editor_property("r", False)
    blue.set_editor_property("g", False)
    blue.set_editor_property("b", True)
    link(normal, blue, "Input")
    sub = expr(mat, unreal.MaterialExpressionSubtract, -360, 160)
    sub.set_editor_property("const_b", 0.22)
    link(blue, sub, "A")
    mul = expr(mat, unreal.MaterialExpressionMultiply, -180, 160)
    mul.set_editor_property("const_b", 2.5)
    link(sub, mul, "A")
    sat = expr(mat, unreal.MaterialExpressionSaturate, 0, 160)
    link(mul, sat, "Input")
    blend = expr(mat, unreal.MaterialExpressionLinearInterpolate, 200, 0)
    link(wall_c, blend, "A")
    link(roof_c, blend, "B")
    link(sat, blend, "Alpha")
    unreal.MaterialEditingLibrary.connect_material_property(
        blend, "", unreal.MaterialProperty.MP_BASE_COLOR)
    rough = expr(mat, unreal.MaterialExpressionConstant, 0, 320)
    rough.set_editor_property("r", .86)
    unreal.MaterialEditingLibrary.connect_material_property(
        rough, "", unreal.MaterialProperty.MP_ROUGHNESS)
    unreal.MaterialEditingLibrary.recompile_material(mat)
    unreal.EditorAssetLibrary.save_loaded_asset(mat)
    return mat


palettes = [
    make_palette("M_House_Russet", (.72,.63,.47), (.38,.15,.105)),
    make_palette("M_House_Slate", (.67,.65,.52), (.12,.20,.26)),
    make_palette("M_House_Moss", (.66,.61,.46), (.22,.31,.19)),
    make_palette("M_House_Clay", (.78,.69,.54), (.47,.28,.16)),
]
stone = unreal.load_asset(DIR + "/M_Weathered_Stone_01")
changed = []
for actor in actor_sys.get_all_level_actors():
    if not isinstance(actor, unreal.StaticMeshActor):
        continue
    label = actor.get_actor_label()
    folder = str(actor.get_folder_path())
    if folder.startswith("ART/Fab_SlavicLite/"):
        variant = sum(ord(c) for c in label) % len(palettes)
        actor.static_mesh_component.set_material(0, palettes[variant])
        changed.append(label)
    elif label in ("HERO_Church_BellTower", "HERO_NorthGate_Left",
                   "HERO_NorthGate_Right"):
        actor.static_mesh_component.set_material(0, palettes[1])
        changed.append(label)
    elif label == "HERO_NorthGate_Lintel" or folder == "ART/Guild_Yard_Fence":
        actor.static_mesh_component.set_material(0, stone)
        changed.append(label)

unreal.EditorLevelLibrary.save_current_level()
out = {"level":LEVEL, "palette_materials":len(palettes),
       "colored_actors":len(changed)}
(HERE / "colorize_result.json").write_text(json.dumps(out,indent=2),encoding="utf-8")
print("COLORIZE_TOWN",json.dumps(out))
