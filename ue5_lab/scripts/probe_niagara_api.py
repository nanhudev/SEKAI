"""Feasibility probe: can we author Niagara from headless Python?

Writes a report to F:/SEKAI/ue5_lab/exports/niagara_probe.txt
Never raises: every question is wrapped.
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import unreal
import os

OUT = str(_SEKAI_ROOT / 'ue5_lab/exports/niagara_probe.txt')
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
try:
    log("engine_version = %s" % unreal.SystemLibrary.get_engine_version())
except Exception as exc:
    log("engine_version FAILED %r" % (exc,))


def dump(cls_name, attrs=None):
    cls = getattr(unreal, cls_name, None)
    log("")
    log("--- unreal.%s -> %r" % (cls_name, cls))
    if cls is None:
        return None
    try:
        names = [a for a in dir(cls) if not a.startswith("_")]
        if attrs:
            names = [a for a in names if any(k.lower() in a.lower() for k in attrs)]
        log("    n=%d  %s" % (len(names), names[:80]))
    except Exception as exc:
        log("    dir FAILED %r" % (exc,))
    return cls


log("")
log("############ 1. CLASS SURFACE ############")
for c in ("NiagaraSystem", "NiagaraEmitter", "NiagaraComponent", "NiagaraFunctionLibrary",
          "NiagaraSystemFactoryNew", "NiagaraEmitterFactoryNew", "NiagaraActor",
          "NiagaraComponentPool", "NiagaraParameterStore", "NiagaraUserRedirectionParameterStore",
          "NiagaraDataInterface", "NiagaraScript", "NiagaraScriptSource",
          "NiagaraParameterCollection", "NiagaraParameterCollectionInstance"):
    dump(c)

log("")
log("############ 2. NiagaraSystem members (full) ############")
ns = getattr(unreal, "NiagaraSystem", None)
if ns is not None:
    log(repr([a for a in dir(ns) if not a.startswith("_")]))

log("")
log("############ 3. EdGraph / editor script types ############")
for c in ("NiagaraScriptConversionContext", "NiagaraScriptConversionContextInput",
          "NiagaraEditorUtilities", "NiagaraStackEditorData", "NiagaraScriptLibrary"):
    dump(c)

log("")
log("############ 4. template assets on disk ############")
pat = "/Niagara/DefaultAssets/Templates"
try:
    ar = unreal.EditorAssetLibrary
    for folder in ("/Niagara/DefaultAssets/Templates/Systems",
                   "/Niagara/DefaultAssets/Templates/Emitters",
                   "/Niagara/DefaultAssets/Templates",
                   "/Niagara/Modules",
                   "/Niagara/DefaultAssets"):
        try:
            lst = ar.list_assets(folder, recursive=False, include_folder=False)
        except Exception as exc:
            lst = None
        log("  %-52s -> %s" % (folder, (len(lst) if lst else lst)))

    for folder in ("/Niagara/DefaultAssets/Templates/Systems",
                   "/Niagara/DefaultAssets/Templates/Emitters"):
        try:
            lst = ar.list_assets(folder, recursive=True, include_folder=False)
            log("  RECURSIVE %s -> n=%s" % (folder, len(lst) if lst else lst))
            for p in (lst or [])[:60]:
                log("      %s" % p)
        except Exception as exc:
            log("  RECURSIVE %s FAILED %r" % (folder, exc))
except Exception as exc:
    log("template scan FAILED %r" % (exc,))

log("")
log("############ 5. can we CREATE a NiagaraSystem asset? ############")
try:
    asset_tools = unreal.AssetToolsHelpers.get_asset_tools()
    log("asset_tools = %r" % asset_tools)
    fac = getattr(unreal, "NiagaraSystemFactoryNew", None)
    log("NiagaraSystemFactoryNew = %r" % fac)
    if fac is not None:
        f = fac()
        log("factory instance = %r" % f)
        try:
            log("  supported_class = %r" % f.get_editor_property("supported_class"))
        except Exception as exc:
            log("  supported_class FAILED %r" % (exc,))
        dest = "/Game/SEKAI/VFX/Sword/Test"
        sys_asset = asset_tools.create_asset("NS_PROBE_Tmp", dest, unreal.NiagaraSystem, f)
        log("  create_asset -> %r" % sys_asset)
        if sys_asset is not None:
            try:
                hl = sys_asset.get_emitter_handles()
                log("  emitter_handles = %r len=%d" % (hl, len(hl)))
            except Exception as exc:
                log("  get_emitter_handles FAILED %r" % (exc,))
            try:
                sys_asset.add_emitter(unreal.NiagaraEmitter())
                log("  add_emitter(NiagaraEmitter()) OK")
            except Exception as exc:
                log("  add_emitter FAILED %r" % (exc,))
            for m in [a for a in dir(sys_asset) if not a.startswith("_")]:
                log("     method: %s" % m)
except Exception as exc:
    log("create_asset block FAILED %r" % (exc,))

log("")
log("############ 6. NiagaraFunctionLibrary ############")
nfl = getattr(unreal, "NiagaraFunctionLibrary", None)
if nfl is not None:
    for m in [a for a in dir(nfl) if not a.startswith("_")]:
        log("   %s" % m)

log("")
log("############ 7. unreal module: anything niagara-ish? ############")
try:
    names = [a for a in dir(unreal) if "niagara" in a.lower()]
    log("n=%d" % len(names))
    for n in names:
        log("   unreal.%s" % n)
except Exception as exc:
    log("FAILED %r" % (exc,))

log("")
log("=== DONE ===")
try:
    with open(OUT, "a", encoding="utf-8") as f:
        f.write("")
except Exception:
    pass
print("PROBE WROTE", OUT, len(lines), "lines")
