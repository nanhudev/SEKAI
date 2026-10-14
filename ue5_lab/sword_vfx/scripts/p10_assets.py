"""SEKAI Sword VFX - P10: content folder, texture/mesh import, materials, profiles.

Run inside the UE editor session (see run_ue.sh). Idempotent: every asset is
deleted and rebuilt, so re-running is the normal workflow.

Layout it creates under /Game/SEKAI/VFX/Sword/:
    Textures/   imported masks
    Meshes/     imported VFX meshes
    Materials/  M_SW_* masters + MI_SW_*_Normal / _Magic instances
    Data/       sword VFX profile + event contract spec
    Systems/    (filled by p11_niagara.py, one subfolder per core system)
    Lab/        (filled by p12_review_map.py)
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swmat  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p10_assets.txt')
SRC_TEX = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/source/textures')
SRC_MESH = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/source/meshes')

ROOT = "/Game/SEKAI/VFX/Sword"
DIR_TEX = ROOT + "/Textures"
DIR_MESH = ROOT + "/Meshes"
DIR_MAT = ROOT + "/Materials"
DIR_DATA = ROOT + "/Data"
DIR_SYS = ROOT + "/Systems"

_LOG = []


def log(s=""):
    s = str(s)
    _LOG.append(s)
    print(s)
    with open(EXPORT, "a", encoding="utf-8") as fh:
        fh.write(s + "\n")


open(EXPORT, "w", encoding="utf-8").close()

EAL = unreal.EditorAssetLibrary
AT = unreal.AssetToolsHelpers.get_asset_tools()

log("engine: " + unreal.SystemLibrary.get_engine_version())

# --------------------------------------------------------------- 1. folders
log("")
log("--- 1. folder structure ---")
for d in (ROOT, DIR_TEX, DIR_MESH, DIR_MAT, DIR_DATA, DIR_SYS):
    EAL.make_directory(d)
    log("    %-42s exists=%s" % (d, EAL.does_directory_exist(d)))

# --------------------------------------------------------------- 2. textures
log("")
log("--- 2. texture import ---")

# import settings per map. Masks must be non-sRGB or every value is gamma
# mangled before it reaches the material, and the distortion map must keep its
# signed direction data on the RG channels.
TEX_SETTINGS = {
    "T_SW_EdgeMask": (unreal.TextureCompressionSettings.TC_DEFAULT, False),
    "T_SW_Streak": (unreal.TextureCompressionSettings.TC_DEFAULT, False),
    "T_SW_Mote": (unreal.TextureCompressionSettings.TC_DEFAULT, False),
    "T_SW_ScarMask": (unreal.TextureCompressionSettings.TC_DEFAULT, False),
    "T_SW_WaveMask": (unreal.TextureCompressionSettings.TC_DEFAULT, False),
    "T_SW_MistMask": (unreal.TextureCompressionSettings.TC_DEFAULT, False),
    "T_SW_DistortionNormal": (unreal.TextureCompressionSettings.TC_DEFAULT, False),
}

textures = {}
for name, (comp, srgb) in TEX_SETTINGS.items():
    src = os.path.join(SRC_TEX, name + ".png")
    if not os.path.isfile(src):
        log("    MISSING SOURCE %s" % src)
        continue
    full = "%s/%s" % (DIR_TEX, name)
    if EAL.does_asset_exist(full):
        EAL.delete_asset(full)
    task = unreal.AssetImportTask()
    task.filename = src
    task.destination_path = DIR_TEX
    task.destination_name = name
    task.automated = True
    task.replace_existing = True
    task.save = False
    AT.import_asset_tasks([task])
    tex = EAL.load_asset(full)
    if tex is None:
        log("    IMPORT FAILED %s" % name)
        continue
    tex.set_editor_property("compression_settings", comp)
    tex.set_editor_property("srgb", srgb)
    tex.set_editor_property("filter", unreal.TextureFilter.TF_BILINEAR)
    EAL.save_loaded_asset(tex, only_if_is_dirty=False)
    textures[name] = tex
    log("    %-24s imported  srgb=%s comp=%s" % (name, srgb, comp))

# ------------------------------------------------------------------ 3. meshes
log("")
log("--- 3. mesh import ---")
meshes = {}
for name in ("SM_SW_ArcSheet", "SM_SW_WaveSheet", "SM_SW_ScarStrip", "SM_SW_GlintQuad"):
    src = os.path.join(SRC_MESH, name + ".obj")
    if not os.path.isfile(src):
        log("    MISSING SOURCE %s" % src)
        continue
    full = "%s/%s" % (DIR_MESH, name)
    if EAL.does_asset_exist(full):
        EAL.delete_asset(full)
    task = unreal.AssetImportTask()
    task.filename = src
    task.destination_path = DIR_MESH
    task.destination_name = name
    task.automated = True
    task.replace_existing = True
    task.save = False
    AT.import_asset_tasks([task])
    mesh = EAL.load_asset(full)
    if mesh is None:
        log("    IMPORT FAILED %s" % name)
        continue
    try:
        b = mesh.get_bounds().box_extent
        log("    %-20s imported  extent=(%.1f, %.1f, %.1f) cm" % (name, b.x, b.y, b.z))
    except Exception as exc:
        log("    %-20s imported (bounds read failed: %s)" % (name, exc))
    meshes[name] = mesh
    EAL.save_loaded_asset(mesh, only_if_is_dirty=False)

# --------------------------------------------------------------- 4. masters
log("")
log("--- 4. master materials ---")

MASTERS = {
    "M_SW_Trail": dict(additive=False, fresnel_edge=False, dark_term=False),
    "M_SW_Wave": dict(additive=False, fresnel_edge=True, dark_term=True),
    "M_SW_SpatialScar": dict(additive=False, fresnel_edge=False, dark_term=True),
    "M_SW_Mist": dict(additive=False, fresnel_edge=False, dark_term=True),
    "M_SW_Glint": dict(additive=True, dark_term=False),
    "M_SW_Mote": dict(additive=True, dark_term=False),
}

masters = {}
for name, opts in MASTERS.items():
    try:
        if name in ("M_SW_Glint", "M_SW_Mote"):
            mat = swmat.build_glint_material(DIR_MAT, name)
        else:
            mat = swmat.build_sheet_material(DIR_MAT, name, **opts)
        EAL.save_loaded_asset(mat, only_if_is_dirty=False)
        masters[name] = mat
        used = []
        for flag in ("used_with_niagara_sprites", "used_with_niagara_ribbons",
                     "used_with_niagara_mesh_particles"):
            try:
                if mat.get_editor_property(flag):
                    used.append(flag.replace("used_with_niagara_", ""))
            except Exception:
                pass
        log("    %-20s built  niagara_usage=%s" % (name, used))
    except Exception as exc:
        log("    %-20s FAILED %s: %s" % (name, type(exc).__name__, exc))

# ------------------------------------------------- 5. normal / magic instances
log("")
log("--- 5. material instances (the only difference between the two swords) ---")

# Normal sword: WHITE / SILVER / PALE CYAN, thin sharp fast clean air pressure.
NORMAL = dict(
    PrimaryColor=(0.62, 0.80, 1.00, 1.0),
    CoreColor=(1.00, 1.00, 1.00, 1.0),
    DarkColor=(0.020, 0.028, 0.045, 1.0),
    Intensity=1.0,
)
# Magic sword: the sword cuts space and darkness leaks through the cut.
# deep violet / cold purple / pale purple-white core / blue-black mist.
MAGIC = dict(
    PrimaryColor=(0.30, 0.07, 0.62, 1.0),
    CoreColor=(0.88, 0.80, 1.00, 1.0),
    DarkColor=(0.008, 0.005, 0.024, 1.0),
    Intensity=1.05,
)

MIST_NORMAL = dict(PrimaryColor=(0.42, 0.55, 0.70, 1.0),
                   CoreColor=(0.10, 0.14, 0.20, 1.0),
                   DarkColor=(0.010, 0.014, 0.025, 1.0),
                   VoidAmount=0.35)
MIST_MAGIC = dict(PrimaryColor=(0.10, 0.03, 0.26, 1.0),
                  CoreColor=(0.03, 0.01, 0.09, 1.0),
                  DarkColor=(0.004, 0.003, 0.012, 1.0),
                  VoidAmount=0.85)

instances = {}
for mat_name, mat in masters.items():
    mask_key = "T_SW_EdgeMask"
    if "Scar" in mat_name:
        mask_key = "T_SW_ScarMask"
    elif "Wave" in mat_name:
        mask_key = "T_SW_WaveMask"
    elif "Mist" in mat_name:
        mask_key = "T_SW_MistMask"
    elif "Glint" in mat_name:
        mask_key = "T_SW_Streak"
    elif "Mote" in mat_name:
        mask_key = "T_SW_Mote"
    mask_tex = textures.get(mask_key)

    base_extra = {"MaskTex": mask_tex}
    for flavour, palette in (("Normal", NORMAL), ("Magic", MAGIC)):
        params = dict(base_extra)
        if "Mist" in mat_name:
            params.update(MIST_NORMAL if flavour == "Normal" else MIST_MAGIC)
        else:
            params.update(palette)
        if "Mist" in mat_name:
            params["MaskTex"] = mask_tex
        inst_name = "MI_SW_%s_%s" % (mat_name[5:], flavour)
        try:
            mi = swmat.build_instance(mat, DIR_MAT, inst_name, params)
            EAL.save_loaded_asset(mi, only_if_is_dirty=False)
            instances[inst_name] = mi
            log("    %-32s parent=%-16s mask=%s"
                % (inst_name, mat_name, mask_key))
        except Exception as exc:
            log("    %-32s FAILED %s: %s" % (inst_name, type(exc).__name__, exc))

# ------------------------------------------------------------ 6. data assets
log("")
log("--- 6. data / profile assets ---")

for probe in ("StructureFactory", "UserDefinedStructFactory", "DataTableFactory",
              "DataAssetFactory", "PrimaryDataAssetFactory", "DataTableFunctionLibrary"):
    log("    unreal.%-30s %s" % (probe, getattr(unreal, probe, "MISSING")))

# The Niagara user parameters ARE the runtime profile surface: every core system
# exposes the same User.* names, so a profile is a parameter set, not a new
# asset type. This spec is the authoritative machine-readable form of it.
PROFILE = {
    "schema": "SwordVisualProfile/v1",
    "note": ("Profiles differ only by material instance and User.* values. "
             "Animation timing is never owned here."),
    "common_user_params": [
        "User.PrimaryColor", "User.CoreColor", "User.MistColor", "User.DarkColor",
        "User.Intensity", "User.Width", "User.Length", "User.Radius",
        "User.ArcAngle", "User.Lifetime", "User.Speed", "User.Distortion",
        "User.MistAmount", "User.SpawnRate", "User.StartPosition",
        "User.EndPosition", "User.BladeBase", "User.BladeTip",
    ],
    "profiles": {
        "VP_Sword_Normal": {
            "identity": ["white", "silver", "pale cyan"],
            "keywords": ["thin", "sharp", "fast", "clean", "air pressure", "space cut"],
            "system_params": {
                "Glint": {"mi": "MI_SW_Glint_Normal", "Intensity": 1.0, "Lifetime": 0.14},
                "Trail": {"mi": "MI_SW_Trail_Normal", "Width": 0.045, "Lifetime": 0.18},
                "A1Slice": {"mi": "MI_SW_Trail_Normal", "Length": 2.0, "Lifetime": 0.09},
                "A2Wave": {"mi": "MI_SW_Wave_Normal", "Length": 8.0, "Speed": 34.0,
                           "Lifetime": 0.30, "Width": 0.60},
                "A3Scar": {"mi": "MI_SW_SpatialScar_Normal", "Lifetime": 0.42,
                           "Width": 0.055, "MistAmount": 0.05},
                "A4Arc": {"mi": "MI_SW_Trail_Normal", "ArcAngle": 300.0,
                          "Lifetime": 0.30, "Width": 0.34},
                "Mist": {"mi": "MI_SW_Mist_Normal", "MistAmount": 0.0},
            },
        },
        "VP_Sword_Magic": {
            "identity": ["deep violet", "cold purple", "pale purple-white core",
                         "black / blue-black mist"],
            "keywords": ["the sword cuts space and darkness leaks through the cut"],
            "system_params": {
                "Glint": {"mi": "MI_SW_Glint_Magic", "Intensity": 1.05, "Lifetime": 0.16},
                "Trail": {"mi": "MI_SW_Trail_Magic", "Width": 0.050, "Lifetime": 0.20},
                "A1Slice": {"mi": "MI_SW_Trail_Magic", "Length": 2.0, "Lifetime": 0.24},
                "A2Wave": {"mi": "MI_SW_Wave_Magic", "Length": 8.0, "Speed": 32.0,
                           "Lifetime": 0.34, "Width": 0.62, "MistAmount": 0.35},
                "A3Scar": {"mi": "MI_SW_SpatialScar_Magic", "Lifetime": 0.55,
                           "Width": 0.062, "MistAmount": 0.55},
                "A4Arc": {"mi": "MI_SW_Trail_Magic", "ArcAngle": 300.0,
                          "Lifetime": 0.34, "Width": 0.36, "MistAmount": 0.30},
                "Mist": {"mi": "MI_SW_Mist_Magic", "MistAmount": 1.0},
            },
        },
    },
}

EAL.make_directory(DIR_DATA)
json_path = os.path.join(str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/source'), "sword_visual_profile.json")
with open(json_path, "w", encoding="utf-8") as fh:
    json.dump(PROFILE, fh, ensure_ascii=False, indent=2)
log("    profile spec -> %s" % json_path)

# ------------------------------------------------------------------- 7. tally
log("")
log("--- 7. tally ---")
log("    textures  = %d" % len(textures))
log("    meshes    = %d" % len(meshes))
log("    masters   = %d" % len(masters))
log("    instances = %d" % len(instances))

def _count(path):
    try:
        return len(EAL.list_assets(path, recursive=True, include_folder=False) or [])
    except Exception:
        return -1


for d in (DIR_TEX, DIR_MESH, DIR_MAT, DIR_DATA):
    log("    %-42s %s assets" % (d, _count(d)))

log("")
log("P10 DONE")
print("P10 DONE")
