"""SEKAI Sword VFX - P12: read the real colour-module inputs, then settle the
inline-edit-condition question that broke the P11 build.

Three questions, in order of cheapness:

  1. What inputs does /Niagara/Modules/Update/Color/Color actually expose?
     GetModuleSchemaFromAsset answers this from the asset alone - no system, no
     emitter, no compile. Everything the build sheet quotes should come from
     here rather than from memory.

  2. ScaleColor's "Scale RGB" is an inline edit condition: a bool that gates its
     siblings. Write order should therefore be gate first, colour second. This
     probe does exactly that and re-reads the topology between the two writes to
     prove the sibling actually became editable, instead of assuming it.

  3. Colour can be driven from two places: ScaleColor (multiplies the existing
     particle colour) or Color (assigns it). This probe links User.PrimaryColor
     into both and reports which one the toolset accepts as a linked value.

Nothing is saved. The P11 run died inside SaveLoadedAsset, so this probe keeps
the whole experiment in memory and only writes text.
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p12_module_probe.txt')
DUMP = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p12_module_inputs.json')

S.bind_log(EXPORT)
EAL = unreal.EditorAssetLibrary

TPL_SYSTEM = "/Niagara/DefaultAssets/DefaultSystem"
TPL_EMITTER = "/Niagara/DefaultAssets/Templates/Emitters/Minimal"

PROBE_DIR = "/Game/SEKAI/VFX/Sword/_probe"
PROBE_SYS = PROBE_DIR + "/PROBE_Color"

CANDIDATES = [
    "/Niagara/Modules/Update/Color/Color",
    "/Niagara/Modules/Update/Color/ScaleColor",
    "/Niagara/Modules/Update/Size/ScaleSpriteSize",
    "/Niagara/Modules/Update/Size/ScaleMeshSize",
    "/Niagara/Modules/Ribbons/RibbonWidth",
    "/Niagara/Modules/Solvers/SolveForcesAndVelocity",
]

dump = {}


def describe(inp):
    return {"name": inp.get("name"), "visible": inp.get("bIsVisible"),
            "editable": inp.get("bIsEditable"), "dynamic": inp.get("bIsDynamic"),
            "staticSwitch": inp.get("bIsStaticSwitch"),
            "type": ((inp.get("type") or {}).get("classStructOrEnum") or {}).get("refPath")}


# ---------------------------------------------------------------- question 1
S.log("=" * 70)
S.log("1. module assets, described without any system context")
S.log("=" * 70)
for path in CANDIDATES:
    ok, res = S.call_quiet("GetModuleSchemaFromAsset",
                           {"moduleAsset": S.ref(path)})
    if not ok:
        S.log("  %-58s FAILED %s" % (path.rsplit("/", 1)[-1], res))
        dump[path] = {"error": str(res)}
        continue
    inputs = res.get("inputs") or []
    S.log("  %s  (%d inputs)" % (path, len(inputs)))
    rows = []
    for inp in inputs:
        d = describe(inp)
        rows.append(d)
        S.log("      %-26s %-46s vis=%-5s edit=%-5s sw=%s"
              % (d["name"], str(d["type"]).rsplit(".", 1)[-1],
                 d["visible"], d["editable"], d["staticSwitch"]))
    dump[path] = {"inputs": rows}

# ---------------------------------------------------------------- question 2+3
S.log("")
S.log("=" * 70)
S.log("2/3. live emitter: gate write, then colour link")
S.log("=" * 70)

if EAL.does_asset_exist(PROBE_SYS):
    EAL.delete_asset(PROBE_SYS)

sys_path = S.call("CreateNiagaraSystem", {
    "assetName": "PROBE_Color", "assetPath": PROBE_DIR,
    "templateSystem": S.ref(TPL_SYSTEM)})["refPath"]
S.log("  probe system: %s" % sys_path)

summary = S.call("GetSystemSummary", {"system": S.ref(sys_path)})
for em in (summary.get("emitters") or []):
    S.call_quiet("RemoveEmitter", {
        "emitterToRemove": S.stack_ref(sys_path, emitter=em.get("emitterName"))})

S.call("AddUserVariables", {
    "system": S.ref(sys_path),
    "variablesToAdd": [
        {"name": "User.PrimaryColor", "type": S.typedef(S.T_COLOR),
         "defaultValue": S.color(0.72, 0.86, 1.0), "description": "probe"},
        {"name": "User.Intensity", "type": S.typedef(S.T_FLOAT),
         "defaultValue": S.f(1.0), "description": "probe"}]})

topo = S.call("AddEmitter", {
    "system": S.ref(sys_path),
    "templateEmitter": S.ref(TPL_EMITTER),
    "emitterName": "E_Probe"})
em_name = topo.get("emitterName")
S.log("  emitter: %s" % em_name)


def topology(script, module):
    res = S.call("GetModuleTopology", {
        "moduleRef": S.stack_ref(sys_path, emitter=em_name, script=script,
                                 module=module)})
    return [describe(i) for i in (res.get("inputs") or [])], res


def show(tag, rows):
    S.log("    [%s]" % tag)
    for r in rows:
        S.log("      %-26s %-40s edit=%-5s dyn=%-5s sw=%s"
              % (r["name"], str(r["type"]).rsplit(".", 1)[-1], r["editable"],
                 r["dynamic"], r["staticSwitch"]))


def try_set(script, module, iname, value, label):
    ok, res = S.call_quiet("SetStackInputData", {
        "stackInputRef": S.stack_ref(sys_path, emitter=em_name, script=script,
                                     module=module, input_stack=[iname]),
        "inputData": value})
    S.log("      set %-24s %-30s -> %s%s"
          % (iname, label, "OK" if ok else "FAIL", "" if ok else "  " + str(res)[:160]))
    return ok


# --- 2. ScaleColor, gate first then colour -------------------------------
S.log("")
S.log("  --- ScaleColor: gate before colour ---")
ok, res = S.call_quiet("AddModule", {
    "moduleLocationRef": S.stack_ref(sys_path, emitter=em_name,
                                     script="ParticleUpdateScript"),
    "moduleAsset": S.ref("/Niagara/Modules/Update/Color/ScaleColor")})
if not ok:
    S.log("    AddModule failed: %s" % res)
else:
    sc = res.get("moduleName")
    rows, raw = topology("ParticleUpdateScript", sc)
    show("ScaleColor as added", rows)
    dump["ScaleColor_as_added"] = rows

    try_set("ParticleUpdateScript", sc, "Scale RGB", S.b(True), "bool gate")
    rows2, _ = topology("ParticleUpdateScript", sc)
    show("ScaleColor after gate=True", rows2)
    dump["ScaleColor_after_gate"] = rows2

    became = sorted({r["name"] for r in rows2 if r["editable"]}
                    - {r["name"] for r in rows if r["editable"]})
    S.log("    newly editable after gate: %s" % (became or "NOTHING"))

    for candidate in ("ScaleRGB", "Scale RGBA", "ScaleRGBA"):
        present = [r for r in rows2 if r["name"] == candidate]
        if present and present[0]["editable"]:
            try_set("ParticleUpdateScript", sc, candidate,
                    S.link("User.PrimaryColor", S.T_COLOR), "link PrimaryColor")
            break

# --- 3. Color module -----------------------------------------------------
S.log("")
S.log("  --- Color module: assign instead of multiply ---")
ok, res = S.call_quiet("AddModule", {
    "moduleLocationRef": S.stack_ref(sys_path, emitter=em_name,
                                     script="ParticleUpdateScript"),
    "moduleAsset": S.ref("/Niagara/Modules/Update/Color/Color")})
if not ok:
    S.log("    AddModule failed: %s" % res)
else:
    cm = res.get("moduleName")
    rows, _ = topology("ParticleUpdateScript", cm)
    show("Color as added", rows)
    dump["Color_as_added"] = rows

    target = None
    for r in rows:
        if r["name"] == "Color":
            target = r
    if target is None:
        S.log("    no input literally named 'Color'; nothing linked")
    elif target["editable"]:
        try_set("ParticleUpdateScript", cm, "Color",
                S.link("User.PrimaryColor", S.T_COLOR), "link PrimaryColor")
    else:
        S.log("    'Color' is not editable as added (edit=%s, vis=%s) - try gate first"
              % (target["editable"], target["visible"]))
        for gate in ("Scale RGB", "Assign Color"):
            if any(r["name"] == gate for r in rows):
                try_set("ParticleUpdateScript", cm, gate, S.b(True), "bool gate")
                rows3, _ = topology("ParticleUpdateScript", cm)
                show("Color after gate %s=True" % gate, rows3)
                t3 = [r for r in rows3 if r["name"] == "Color"]
                if t3 and t3[0]["editable"]:
                    try_set("ParticleUpdateScript", cm, "Color",
                            S.link("User.PrimaryColor", S.T_COLOR), "link PrimaryColor")
                    break

# ---------------------------------------------------------------- report
with open(DUMP, "w", encoding="utf-8") as fh:
    json.dump(dump, fh, ensure_ascii=False, indent=1)

S.log("")
S.log("=" * 70)
S.log("NOT saving the probe system - this run is read-only by design.")
S.log("dump -> %s" % DUMP)
S.log("P12 DONE")
print("P12 DONE")
