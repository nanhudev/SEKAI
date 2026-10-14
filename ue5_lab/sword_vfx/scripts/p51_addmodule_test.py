"""
p51_addmodule_test.py - does AddModule stick? And if it does, repair E_Trail.

WHAT THIS SETTLES
    p50 proved, with a control, that all eleven emitters in the nine systems
    have ZERO modules:

        ours/EdgeTrail / E_Trail : particleSpawnScript verbatim
            { "scriptName": "ParticleSpawnScript", "modules": [] }
        stock/RadialBurst / RibbonTrailFollower : particleSpawnScript verbatim
            { "scriptName": "ParticleSpawnScript",
              "modules": [ { "moduleName": "InitializeParticle", ... } ] }

    same call, same session, same key, same shape. And p11 - the script that
    built them - reported "links confirmed 37 modules, 49 pins, unverified pins
    0, errors 0". Both cannot be true of the same assets.

    The interesting part is the ASYMMETRY. p11's AddEmitter calls persisted:
    every emitter is there under the intended name (E_Trail, E_Glint, E_Slice,
    E_Wave, E_MistWake, E_Scar, E_ScarMist, E_Arc, E_Wisp, E_Motes, E_Hit), and
    each system carries its renderers. Only AddModule left no trace.

    So the question is narrow and answerable: when AddModule is called on one of
    these emitters, in this build, does a module appear in the stack?

        it appears  -> scripted authoring works, p11's module phase was broken
                       in a way that can be fixed, and the nine can be rebuilt
                       by script
        it does not -> section 0 of the brief was right: a Niagara graph cannot
                       be built by script here, and the nine need the editor

    p11 never checked this. It counted AddModule's own return value and called
    that confirmation, which is a tool reporting on its own request rather than a
    read of the graph. This reads the graph.

WHAT IT DOES, IN ORDER
    1. baseline GetEmitterTopology on E_Trail          (expect 0 modules)
    2. AddModule InitializeParticle  @ ParticleSpawnScript
    3. read the graph back                             (0 -> 1?)
    4. AddModule SolveForcesAndVelocity @ ParticleUpdateScript
    5. AddModule Color               @ ParticleUpdateScript
    6. AddModule SpawnRate           @ EmitterUpdateScript
    7. read the graph back
    8. save_dirty_packages, and report what the save returned

    Every step is logged with both what the tool returned AND what the graph
    says afterwards, because the whole failure being chased is the gap between
    those two.

OUTPUT
    exports/p51_addmodule.txt

Usage:
    cd sword_vfx/scripts && UE_TIMEOUT=260 ./run_ue.sh p51_addmodule_test.py --editor
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p51_addmodule.txt')
SYS = "/Game/SEKAI/VFX/Sword/Systems/NS_SW_Core_EdgeTrail"
EMITTER = "E_Trail"

MODULES = {
    "Init": "/Niagara/Modules/Spawn/Initialization/V2/InitializeParticle",
    "Solve": "/Niagara/Modules/Solvers/SolveForcesAndVelocity",
    "Color": "/Niagara/Modules/Update/Color/Color",
    "SpawnRate": "/Niagara/Modules/Emitter/SpawnRate",
    "ParticleState": "/Niagara/Modules/Update/Lifetime/ParticleState",
}

DEADLINE = 25.0
BUDGET_SECONDS = 230.0

WFX.bind_log(EXPORT)
log = WFX.log

log("engine: %s" % unreal.SystemLibrary.get_engine_version())
log("subject: %s emitter %s" % (SYS, EMITTER))

ST = {"handle": None, "started": time.time(), "ticks": 0, "errors": 0,
      "steps": [], "i": 0, "pending": None, "counts": [], "save": None}

WFX.install_watchdog(grace_seconds=BUDGET_SECONDS + 25.0)


# ---------------------------------------------------------------- graph read
def stack_mods(topology, key):
    """(found, names). `found` is the key that was used, so a shape change is
    visible instead of being read as zero modules."""
    if not isinstance(topology, dict):
        return None, []
    stack = topology.get(key)
    if not isinstance(stack, dict):
        return None, []
    for k in ("modules", "Modules", "moduleTopologies"):
        if isinstance(stack.get(k), (list, tuple)):
            names = []
            for m in stack[k]:
                if isinstance(m, dict):
                    names.append(str(m.get("moduleName") or m.get("name") or "?"))
                else:
                    names.append(str(m)[:20])
            return k, names
    return None, []


def summarise(topology):
    out = []
    total = 0
    for label, key in (("EmitSpawn", "emitterSpawnScript"),
                       ("EmitUpdate", "emitterUpdateScript"),
                       ("PartSpawn", "particleSpawnScript"),
                       ("PartUpdate", "particleUpdateScript")):
        used, names = stack_mods(topology, key)
        total += len(names)
        out.append("%s=%d%s" % (label, len(names),
                                ("[%s]" % ",".join(names[:4]) if names else "")))
    return total, " · ".join(out)


def read_topo_ok(tag, value):
    total, line = summarise(value)
    ST["counts"].append((tag, total))
    log("    %-14s total=%d   %s" % (tag, total, line))
    return total


def after_add(tag, value):
    """What AddModule itself returned. Logged separately from the graph read,
    because the entire lesson of this run is that the two can disagree."""
    if not isinstance(value, dict):
        log("    %-14s returned %s" % (tag, str(value)[:140]))
        return
    nm = value.get("moduleName") or value.get("name") or "?"
    ins = value.get("inputs")
    log("    %-14s returned module %r with %s inputs"
        % (tag, nm, len(ins) if isinstance(ins, (list, tuple)) else "?"))


def q(label, tool, payload, handler, toolset=None):
    ST["steps"].append({"label": label, "tool": tool, "payload": payload,
                        "handler": handler, "toolset": toolset})


# ---------------------------------------------------------------- the queue
for key, path in MODULES.items():
    ok = unreal.EditorAssetLibrary.does_asset_exist(path)
    log("  module asset %-14s exists=%s" % (key, ok))

q("topo/baseline", "GetEmitterTopology",
  {"emitterRef": WFX.stack_ref(SYS, emitter=EMITTER)}, read_topo_ok)

q("add/Init", "AddModule",
  {"moduleLocationRef": WFX.stack_ref(SYS, emitter=EMITTER,
                                      script="ParticleSpawnScript"),
   "moduleAsset": WFX.ref(MODULES["Init"])}, after_add,
  toolset=WFX.TOOLSET)

q("topo/after-init", "GetEmitterTopology",
  {"emitterRef": WFX.stack_ref(SYS, emitter=EMITTER)}, read_topo_ok)

q("add/Solve", "AddModule",
  {"moduleLocationRef": WFX.stack_ref(SYS, emitter=EMITTER,
                                      script="ParticleUpdateScript"),
   "moduleAsset": WFX.ref(MODULES["Solve"])}, after_add)
q("add/Color", "AddModule",
  {"moduleLocationRef": WFX.stack_ref(SYS, emitter=EMITTER,
                                      script="ParticleUpdateScript"),
   "moduleAsset": WFX.ref(MODULES["Color"])}, after_add)
q("add/ParticleState", "AddModule",
  {"moduleLocationRef": WFX.stack_ref(SYS, emitter=EMITTER,
                                      script="ParticleUpdateScript"),
   "moduleAsset": WFX.ref(MODULES["ParticleState"])}, after_add)
q("add/SpawnRate", "AddModule",
  {"moduleLocationRef": WFX.stack_ref(SYS, emitter=EMITTER,
                                      script="EmitterUpdateScript"),
   "moduleAsset": WFX.ref(MODULES["SpawnRate"])}, after_add)

q("topo/final", "GetEmitterTopology",
  {"emitterRef": WFX.stack_ref(SYS, emitter=EMITTER)}, read_topo_ok)


def do_save(_tag, _value):
    log("")
    log("    saving with save_dirty_packages (p11 recorded that")
    log("    EditorAssetLibrary.save_asset access-violates on this project)")
    try:
        res = unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True)
        ST["save"] = res
        log("    save_dirty_packages -> %s" % res)
    except Exception as exc:
        ST["save"] = "raised %s" % str(exc)[:120]
        log("    save_dirty_packages raised: %s" % str(exc)[:160])


q("save", None, None, do_save)


# ---------------------------------------------------------------- driver
def tick(delta):
    st = ST
    st["ticks"] += 1
    if time.time() - st["started"] > BUDGET_SECONDS:
        _finish("budget exhausted")
        return
    try:
        if st["pending"] is not None:
            p = st["pending"]
            try:
                done, ok, value = WFX.poll(p["raw"], p["tool"])
            except Exception as exc:
                log("  %-18s poll raised %s" % (p["label"], str(exc)[:90]))
                st["pending"] = None
                return
            if done:
                st["pending"] = None
                if ok:
                    p["handler"](p["label"], value)
                else:
                    log("  %-18s NO ANSWER %s" % (p["label"], str(value)[:130]))
                return
            if time.time() > p["deadline"]:
                st["pending"] = None
                log("  %-18s UNANSWERED within %.0f s" % (p["label"], DEADLINE))
            return

        if st["i"] >= len(st["steps"]):
            _finish("all steps done")
            return
        s = st["steps"][st["i"]]
        st["i"] += 1
        log("")
        log("  [%d/%d] %s" % (st["i"], len(st["steps"]), s["label"]))
        if s["tool"] is None:
            # A local step, not a tool call. Kept in the same queue so the
            # order on the page is the order that happened.
            s["handler"](s["label"], None)
            return
        try:
            raw = WFX.call_async(s["tool"], s["payload"], s["toolset"])
        except Exception as exc:
            log("    FIRE FAILED: %s" % str(exc)[:140])
            return
        st["pending"] = {"label": s["label"], "tool": s["tool"], "raw": raw,
                         "deadline": time.time() + DEADLINE,
                         "handler": s["handler"]}
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:170]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 10:
            _finish("too many tick errors")


def _finish(reason):
    if ST.get("phase") == "done":
        return
    ST["phase"] = "done"
    base = next((c for t, c in ST["counts"] if t == "topo/baseline"), None)
    final = next((c for t, c in ST["counts"] if t == "topo/final"), None)
    log("")
    log("=" * 74)
    log("SUMMARY")
    log("=" * 74)
    log("stop reason : %s" % reason)
    log("elapsed     : %.1f s over %d ticks" % (time.time() - ST["started"],
                                                ST["ticks"]))
    log("tick errors : %d" % ST["errors"])
    log("")
    log("graph reads : %s" % ", ".join("%s=%d" % (t, c) for t, c in ST["counts"]))
    log("save        : %s" % ST["save"])
    log("")
    if base is None or final is None:
        log("=> NO BEFORE/AFTER PAIR. One of the two graph reads did not answer,")
        log("   so nothing about AddModule has been measured. Record the")
        log("   unanswered step above and re-run rather than concluding.")
    elif final > base:
        log("=> AddModule WORKS: the graph went from %d to %d modules, read back"
            % (base, final))
        log("   with the same call that showed the stack empty. Scripted")
        log("   authoring is therefore possible in this build, and p11's module")
        log("   phase failed in a way that is fixable - the nine systems can be")
        log("   rebuilt by script rather than by hand.")
    else:
        log("=> AddModule DID NOT CHANGE THE GRAPH: it was %d before and %d"
            % (base, final))
        log("   after six calls, while the calls themselves reported success.")
        log("   That is section 0 of the brief, measured: a Niagara graph cannot")
        log("   be built by script here. p11's '37 modules' was a tool reporting")
        log("   on its own request, never a read of the graph - and the nine")
        log("   systems are empty shells that need the editor.")
    log("P51 DONE")
    try:
        if ST["handle"] is not None:
            unreal.unregister_slate_post_tick_callback(ST["handle"])
    except Exception:
        pass
    try:
        WFX.watchdog_handover()
    except Exception:
        pass
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception as exc:
        log("quit_editor failed: %s" % str(exc)[:120])


ST["handle"] = unreal.register_slate_post_tick_callback(tick)
