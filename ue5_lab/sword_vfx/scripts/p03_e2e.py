"""SEKAI Sword VFX - P03 end-to-end proof.

Proves the whole chain works headlessly:
  create system -> add emitter -> add renderer -> add user parameters
  -> add module -> set a module input value -> compile check -> save

If this passes, the nine NS_SW_Core_* systems are IMPLEMENTED by script, not by
hand, and the brief's "Niagara graphs cannot be scripted" premise is retired.
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

import swvfx as S  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p03_e2e.txt')
S.dir_hint = None
S.bind_log(EXPORT)

OUT_DIR = "/Game/SEKAI/VFX/Sword/Probe"
NAME = "NS_P03_EndToEnd"

S.log("engine: " + unreal.SystemLibrary.get_engine_version())
S.log("toolset: " + S.TOOLSET)

results = {}


def record(key, fn):
    try:
        v = fn()
        results[key] = v
        S.log("OK   %-28s %s" % (key, json.dumps(v, ensure_ascii=False)[:400]))
        return v
    except Exception as exc:
        results[key] = "FAIL: %s" % exc
        S.log("FAIL %-28s %s: %s" % (key, type(exc).__name__, exc))
        return None


S.log("")
S.log("--- 1. create system from engine template ---")
TPL_SYS = "/Niagara/DefaultAssets/DefaultSystem"
sys_ref = record("CreateNiagaraSystem", lambda: S.call("CreateNiagaraSystem", {
    "assetName": NAME,
    "assetPath": OUT_DIR,
    "templateSystem": S.ref(TPL_SYS),
}))
if not sys_ref:
    S.log("ABORT: no system")
    raise SystemExit(0)

SYS = sys_ref["refPath"]
S.log("system path = %s" % SYS)

with open(str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p03_topology.json'), "w",
          encoding="utf-8") as fh:
    fh.write("")

S.log("")
S.log("--- 2. system summary (inherited emitters) ---")
record("GetSystemSummary", lambda: S.call("GetSystemSummary", {"system": S.ref(SYS)}))

S.log("")
S.log("--- 3. add emitter from engine template ---")
TPL_EM = "/Niagara/DefaultAssets/Templates/Emitters/Minimal"
topo = record("AddEmitter", lambda: S.call("AddEmitter", {
    "system": S.ref(SYS),
    "templateEmitter": S.ref(TPL_EM),
    "emitterName": "E_Proof",
}))
EMITTER = "E_Proof"
if topo:
    S.log("     emitter simTarget  = %s" % topo.get("simTarget"))
    S.log("     renderer classes   = %s" % topo.get("rendererClasses"))
    for sk in ("EmitterSpawnScript", "EmitterUpdateScript",
               "ParticleSpawnScript", "ParticleUpdateScript"):
        stack = topo.get(sk) or {}
        mods = [m.get("moduleName") for m in (stack.get("modules") or [])]
        S.log("     %-20s modules=%s" % (sk, mods))

    with open(str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p03_topology.json'), "w",
              encoding="utf-8") as fh:
        json.dump(topo, fh, ensure_ascii=False, indent=1)
    S.log("     full topology -> exports/p03_topology.json")

S.log("")
S.log("--- 4. add ribbon renderer ---")
record("AddRenderer(ribbon)", lambda: S.call("AddRenderer", {
    "newRendererLocation": S.stack_ref(SYS, emitter=EMITTER),
    "rendererClass": S.ref("/Script/Niagara.NiagaraRibbonRendererProperties"),
}))

S.log("")
S.log("--- 5. add user parameters ---")
record("AddUserVariables", lambda: S.call("AddUserVariables", {
    "system": S.ref(SYS),
    "variablesToAdd": [
        {"name": "User.PrimaryColor",
         "type": S.typedef(S.T_COLOR),
         "defaultValue": S.color(1.0, 1.0, 1.0, 1.0),
         "description": "edge / body primary"},
        {"name": "User.CoreColor",
         "type": S.typedef(S.T_COLOR),
         "defaultValue": S.color(0.85, 0.95, 1.0, 1.0),
         "description": "hot core"},
        {"name": "User.Intensity",
         "type": S.typedef(S.T_FLOAT),
         "defaultValue": S.f(1.0),
         "description": "global multiplier"},
        {"name": "User.Width",
         "type": S.typedef(S.T_FLOAT),
         "defaultValue": S.f(0.06),
         "description": "metres"},
        {"name": "User.Length",
         "type": S.typedef(S.T_FLOAT),
         "defaultValue": S.f(2.0),
         "description": "metres"},
        {"name": "User.StartPosition",
         "type": S.typedef(S.T_POS),
         "defaultValue": S.pos(0, 0, 0),
         "description": "world space start"},
        {"name": "User.EndPosition",
         "type": S.typedef(S.T_POS),
         "defaultValue": S.pos(200, 0, 0),
         "description": "world space end"},
    ],
}))

S.log("")
S.log("--- 6. read back user variables ---")
uv = record("GetUserVariables", lambda: S.call("GetUserVariables", {"system": S.ref(SYS)}))
if uv:
    for v in (uv.get("userVariables") or []):
        S.log("     %-24s type=%s" % (v.get("name"), v.get("type")))

S.log("")
S.log("--- 7. add a module to Particle Spawn ---")
MOD = "/Niagara/Modules/Spawn/Initialization/V2/InitializeParticle"
ok, mod_topo = S.call_quiet("AddModule", {
    "moduleLocationRef": S.stack_ref(SYS, emitter=EMITTER,
                                     script="ParticleSpawnScript"),
    "moduleAsset": S.ref(MOD),
})
S.log("%s AddModule(InitializeParticle) %s" % ("OK  " if ok else "FAIL", "" if ok else mod_topo))
if ok and mod_topo:
    S.log("     moduleName = %s  inputs=%d" % (mod_topo.get("moduleName"),
                                               len(mod_topo.get("inputs") or [])))
    MODULE = mod_topo.get("moduleName")

    S.log("")
    S.log("--- 8. write a module input value ---")
    cand = None
    for inp in (mod_topo.get("inputs") or []):
        if inp.get("bIsEditable") and not inp.get("bIsDynamic"):
            cand = inp
            break
    if cand:
        S.log("     target input: %s (%s)" % (cand.get("name"), cand.get("type")))
        ok2, res2 = S.call_quiet("SetStackInputData", {
            "stackInputRef": S.stack_ref(SYS, emitter=EMITTER,
                                         script="ParticleSpawnScript",
                                         module=MODULE,
                                         input_stack=[cand.get("name")]),
            "inputData": S.color(1.0, 1.0, 1.0, 1.0),
        })
        S.log("%s SetStackInputData -> %s" % ("OK  " if ok2 else "FAIL",
                                              json.dumps(res2, ensure_ascii=False)[:300]
                                              if ok2 else res2))
    else:
        S.log("     no editable non-dynamic input found on this module")

S.log("")
S.log("--- 9. diagnostics: stack issues + compile state ---")
issues = record("GetStackIssues", lambda: S.call("GetStackIssues", {"system": S.ref(SYS)}))
if issues:
    S.log("     errors=%s warnings=%s infos=%s" % (issues.get("numErrors"),
                                                   issues.get("numWarnings"),
                                                   issues.get("numInfos")))
    for isx in (issues.get("issues") or [])[:12]:
        S.log("       [%s] %s  (%s)" % (isx.get("severity"),
                                        isx.get("shortDescription"),
                                        isx.get("stackDisplayPath")))

state = record("GetSystemCompileState",
               lambda: S.call("GetSystemCompileState", {"system": S.ref(SYS)}))
if state:
    S.log("     aggregate = %s" % state.get("aggregateStatus"))
    for si in (state.get("scriptInfos") or [])[:12]:
        S.log("       %-28s %s" % (si.get("scriptName"), si.get("status")))

S.log("")
S.log("--- 10. save ---")
record("save", lambda: bool(unreal.EditorAssetLibrary.save_loaded_asset(
    unreal.EditorAssetLibrary.load_asset(SYS), only_if_is_dirty=False)))
S.log("     exists on disk = %s" % unreal.EditorAssetLibrary.does_asset_exist(
    OUT_DIR + "/" + NAME))

S.log("")
S.log("--- call log ---")
for tool, status, msg in S.call_log():
    S.log("   %-8s %-28s %s" % (status, tool, msg))

S.log("")
S.log("P03 DONE")
print("P03 DONE")
