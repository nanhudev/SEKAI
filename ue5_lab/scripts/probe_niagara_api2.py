"""Probe 2: the NiagaraEditorScriptingExtensions authoring API surface.

Writes F:/SEKAI/ue5_lab/exports/niagara_probe2.txt
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import unreal

OUT = str(_SEKAI_ROOT / 'ue5_lab/exports/niagara_probe2.txt')
lines = []


def log(s):
    lines.append(str(s))
    try:
        with open(OUT, "a", encoding="utf-8") as f:
            f.write(str(s) + "\n")
    except Exception:
        pass


open(OUT, "w", encoding="utf-8").close()

log("=== engine ===")
log(unreal.SystemLibrary.get_engine_version())


def dump(cls_name, full=True):
    cls = getattr(unreal, cls_name, None)
    log("")
    log("--- unreal.%s -> %r" % (cls_name, cls))
    if cls is None:
        return None
    try:
        names = sorted(a for a in dir(cls) if not a.startswith("_"))
        log("    n=%d" % len(names))
        for n in names:
            log("      .%s" % n)
    except Exception as exc:
        log("    dir FAILED %r" % (exc,))
    return cls


log("")
log("######## NIHARA EXT API (editor scripting) ########")
for c in ("NiagaraExt_SystemSchema", "NiagaraExt_SystemData", "NiagaraExt_SystemSummary",
          "NiagaraExt_SystemDependencies", "NiagaraExt_SystemCompileState",
          "NiagaraExt_EmitterSchema", "NiagaraExt_EmitterData", "NiagaraExt_EmitterSummary",
          "NiagaraExt_EmitterTopology",
          "NiagaraExt_ModuleSchema", "NiagaraExt_ModuleData", "NiagaraExt_ModuleTopology",
          "NiagaraExt_ModuleInputValues",
          "NiagaraExt_StackInputSchema", "NiagaraExt_StackInputData",
          "NiagaraExt_StackInputTopology", "NiagaraExt_StackInputValue",
          "NiagaraExt_RendererSchema", "NiagaraExt_RendererData",
          "NiagaraExt_UserVariable", "NiagaraExt_UserVariables",
          "NiagaraExt_Variable", "NiagaraExt_VariableValue", "NiagaraExt_VariableValueBase",
          "NiagaraExt_InstancedValue", "NiagaraExt_DynamicInputChain",
          "NiagaraExt_DynamicInputSchema", "NiagaraExt_DataInterfaceSchema",
          "NiagaraExt_SetParameterEntry", "NiagaraExt_StackItemReference"):
    dump(c)

log("")
log("######## classic python authoring helpers ########")
for c in ("NiagaraPythonEmitter", "NiagaraPythonModule", "NiagaraPythonScriptModuleInput",
          "NiagaraClipboardEditorScriptingUtilities", "NiagaraClipboardFunctionInput",
          "NiagaraClipboardFunction",
          "NiagaraEditorDataBase", "NiagaraEditorParametersAdapterBase",
          "NiagaraEmitterFactoryNew", "NiagaraScriptFactoryNew",
          "NiagaraRendererProperties", "NiagaraSpriteRendererProperties",
          "NiagaraRibbonRendererProperties", "NiagaraMeshRendererProperties"):
    dump(c)

log("")
log("######## renderer props enums we will need ########")
for c in ("NiagaraSpriteFacingMode", "NiagaraSpriteAlignment", "NiagaraMeshPivotOffsetSpace",
          "NiagaraSimTarget", "NiagaraSortMode", "NiagaraEmitterCalculateBoundMode",
          "NiagaraAlignment", "NiagaraRibbonFacingMode", "NiagaraRibbonUVEdgeMode",
          "NiagaraRibbonShapeMode", "NiagaraRibbonDrawDirection",
          "NiagaraMeshAlignmentMode", "NiagaraMeshLockedAxisSpace",
          "NiagaraMeshFacingMode", "NiagaraMeshOrientation"):
    cls = getattr(unreal, c, None)
    log("--- unreal.%s -> %r" % (c, cls))
    if cls is not None:
        try:
            log("      %s" % sorted(a for a in dir(cls) if not a.startswith("_")))
        except Exception as exc:
            log("      FAILED %r" % (exc,))

log("")
log("######## can the asset registry see engine niagara content? ########")
ar = unreal.EditorAssetLibrary
for root in ("/Niagara", "/Niagara/DefaultAssets", "/Niagara/DefaultAssets/Templates",
             "/Niagara/DefaultAssets/Templates/Emitters",
             "/Niagara/DefaultAssets/Templates/Systems",
             "/Niagara/Modules", "/Niagara/Modules/Update", "/Niagara/Modules/Render"):
    try:
        lst = ar.list_assets(root, recursive=False, include_folder=False)
        log("  %-56s n=%s" % (root, "None" if lst is None else len(lst)))
    except Exception as exc:
        log("  %-56s FAILED %r" % (root, exc))

log("")
log("######## known template emitter paths that MUST exist ########")
cands = [
    "/Niagara/DefaultAssets/Templates/Emitters/Fountain",
    "/Niagara/DefaultAssets/Templates/Emitters/SimpleSpriteBurst",
    "/Niagara/DefaultAssets/Templates/Emitters/DirectionalBurst",
    "/Niagara/DefaultAssets/Templates/Emitters/OmnidirectionalBurst",
    "/Niagara/DefaultAssets/Templates/Emitters/Minimal",
    "/Niagara/DefaultAssets/Templates/Emitters/Ribbon",
    "/Niagara/DefaultAssets/Templates/Systems/Minimal",
    "/Niagara/DefaultAssets/DefaultSystem",
]
for p in cands:
    try:
        ex = ar.does_asset_exist(p)
        log("  exists=%-6s %s" % (ex, p))
    except Exception as exc:
        log("  %s FAILED %r" % (p, exc))

log("")
log("=== DONE ===")
print("PROBE2 WROTE")
