"""
p49_stack_readback.py - read the nine stacks back, without waiting on a compile.

WHY THIS TOOL AND NOT THE ONE USED BEFORE
    Every previous attempt to ask a Niagara toolset question went through
    GetSystemCompileState or GetStackIssues, and both of those documents say, in
    their own description:

        等待任何正在进行的编译完成，然后进行收集
        ("waits for any in-progress compile to complete, then collects")

    That is why they never returned: they wait on a compile that this session
    type does not dispatch, and the wait names itself only as "timed out".

    GetEmitterTopology has no such clause. Its description says the opposite:

        返回完整的发射器拓扑：包含所有模块和输入的四个脚本堆栈、渲染器引用。
        所有字段始终填充。
        ("returns the full emitter topology: the FOUR SCRIPT STACKS with all
          modules and inputs, and the renderer references. All fields are
          always populated.")

    So the structure has been readable the whole time, through a different door.

WHAT IT ANSWERS, AND WHY IT IS THE LAST MISSING PIECE
    p48 measured, with a warmed-up control in one session:

        stock (never-edited engine system)  activate(True) -> active=True, stays True
        ours  (NS_SW_Core_EdgeTrail)        activate(True) -> active=False, stays False

    A NiagaraComponent refuses to activate when its system is not ready to run.
    So the nine assets are defective - and the engine log says how:

        LogNiagara: Warning: [AssetLog] ...NS_SW_Core_*.uasset:
            无法找到通向类型为4的输出节点的任何连接！
            无法找到通向类型为5的输出节点的任何连接！

    Types 4 and 5 in ENiagaraScriptUsage are ParticleSpawnScriptInterpolated and
    ParticleUpdateScript. "No connection to the output node" means nothing is
    wired into that script's Output node.

    What this prints is whether the modules p11 added are in those two stacks at
    all. Two very different repairs follow:

        modules missing from Particle Spawn / Particle Update
            -> p11 added them to the wrong usage, the fix is a one-line change
               to the builder, and the nine can be rebuilt by script
        modules present but not wired to the Output node
            -> the stacks are right and the OUTPUT LINK is missing, which is the
               editor-graph problem section 0 of the brief predicted, and it is
               a MANUAL EDITOR STEP

OUTPUT
    exports/p49_stacks.txt

Usage:
    cd sword_vfx/scripts && UE_TIMEOUT=240 ./run_ue.sh p49_stack_readback.py --editor
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p49_stacks.txt')
SYS_DIR = "/Game/SEKAI/VFX/Sword/Systems"

CORES = ("EdgeTrail", "Glint", "AirSlice", "Wave", "SpatialScar",
         "MajorArc", "MistWake", "PurpleMotes", "Hit")

DEADLINE = 25.0
BUDGET_SECONDS = 200.0

WFX.bind_log(EXPORT)
log = WFX.log

log("engine: %s" % unreal.SystemLibrary.get_engine_version())
log("")
log("no level is loaded on purpose: p43 measured that a level load makes the")
log("compile-state tools wait forever, and this asks none of them.")

ST = {"handle": None, "started": time.time(), "ticks": 0, "phase": "fire",
      "errors": 0, "pending": [], "results": {}, "emitters": {},
      "issues": {}, "wait": 30}

WFX.install_watchdog(grace_seconds=BUDGET_SECONDS + 25.0)


def fire(tag, tool, payload):
    """Start a call and register it as pending. Never spins.

    `swvfx.call` spins until the tool completes, which is exactly the wrong
    primitive for a tool that may wait on a compile: the spin has no deadline
    and the failure arrives as a hung session. Everything here goes through
    call_async + poll so the deadline is mine and an unanswered question is
    recorded as unanswered.
    """
    try:
        raw = WFX.call_async(tool, payload)
    except Exception as exc:
        ST["results"][tag] = {"ok": False, "why": "fire failed: %s"
                              % str(exc)[:110]}
        log("  %-26s FIRE FAILED  %s" % (tag, str(exc)[:90]))
        return
    ST["pending"].append({"tag": tag, "tool": tool, "raw": raw,
                          "deadline": time.time() + DEADLINE})


def drain():
    still = []
    for p in ST["pending"]:
        done, ok, value = False, False, None
        try:
            done, ok, value = WFX.poll(p["raw"], p["tool"])
        except Exception as exc:
            ST["results"][p["tag"]] = {"ok": False,
                                       "why": "poll raised %s" % str(exc)[:100]}
            continue
        if done:
            ST["results"][p["tag"]] = {"ok": bool(ok), "value": value}
        elif time.time() > p["deadline"]:
            ST["results"][p["tag"]] = {
                "ok": False, "why": "no answer within %.0f s" % DEADLINE}
        else:
            still.append(p)
    ST["pending"] = still
    return len(still)


def summerise(value):
    """Pull the emitter list out of a GetSystemSummary answer, whatever shape
    the wrapper used. The key names are logged when they are not recognised so a
    shape change is visible rather than silently producing zero emitters."""
    out = []
    if not isinstance(value, dict):
        return out, "answer is %s, not a dict" % type(value).__name__
    for key in ("emitters", "Emitters", "emitterSummaries"):
        if key in value and isinstance(value[key], (list, tuple)):
            for e in value[key]:
                if isinstance(e, dict):
                    nm = e.get("name") or e.get("emitterName") or e.get("Name")
                    if nm:
                        out.append(str(nm))
            return out, "via key %r" % key
    # maybe the answer nests one level down
    for k, v in value.items():
        if isinstance(v, dict):
            for key in ("emitters", "Emitters", "emitterSummaries"):
                if isinstance(v.get(key), (list, tuple)):
                    for e in v[key]:
                        if isinstance(e, dict):
                            nm = (e.get("name") or e.get("emitterName")
                                  or e.get("Name"))
                            if nm:
                                out.append(str(nm))
                    return out, "via %r.%r" % (k, key)
    return out, "no emitter list; keys = %s" % ", ".join(sorted(value)[:12])


def describe_stack(stack, label):
    """One script stack: module names in execution order, and how many inputs
    each module exposes. The count matters because p11's own report claimed 49
    pins, and a stack with modules but zero inputs is a different defect from a
    stack with no modules at all."""
    if not isinstance(stack, dict):
        log("      %-22s <not a dict: %s>" % (label, type(stack).__name__))
        return 0
    mods = None
    for key in ("modules", "Modules", "moduleTopologies"):
        if isinstance(stack.get(key), (list, tuple)):
            mods = stack[key]
            break
    if mods is None:
        log("      %-22s no module list; keys = %s"
            % (label, ", ".join(sorted(stack)[:10])))
        return 0
    names = []
    for m in mods:
        if isinstance(m, dict):
            nm = m.get("name") or m.get("moduleName") or m.get("Name") or "?"
            ins = m.get("inputs") or m.get("Inputs") or []
            names.append("%s(%d)" % (nm, len(ins) if hasattr(ins, "__len__")
                                     else -1))
        else:
            names.append(str(m)[:30])
    log("      %-22s %2d modules: %s"
        % (label, len(mods), ", ".join(names) if names else "(none)"))
    return len(mods)


def dump_emitter(tag, value):
    if not isinstance(value, dict):
        log("    %s -> %s" % (tag, str(value)[:200]))
        return
    # find the four stacks under whatever key the wrapper chose
    stacks = None
    for key in ("scriptStacks", "stacks", "Stacks", "scripts"):
        if isinstance(value.get(key), (list, tuple)):
            stacks = value[key]
            break
    keys = ", ".join(sorted(value)[:16])
    log("    %s  available keys: %s" % (tag, keys))
    if stacks is None:
        # maybe named individually
        for label, key in (("Emitter Spawn", "emitterSpawnScript"),
                           ("Emitter Update", "emitterUpdateScript"),
                           ("Particle Spawn", "particleSpawnScript"),
                           ("Particle Update", "particleUpdateScript")):
            if key in value:
                describe_stack(value[key], label)
        return
    for s in stacks:
        if not isinstance(s, dict):
            continue
        label = (s.get("usage") or s.get("scriptUsage") or s.get("name")
                 or s.get("scriptName") or "?")
        describe_stack(s, str(label))


def tick(delta):
    st = ST
    st["ticks"] += 1
    if time.time() - st["started"] > BUDGET_SECONDS:
        _finish("budget exhausted")
        return
    try:
        if st["phase"] == "fire":
            log("")
            log("=" * 74)
            log("ROUND 1 - GetSystemSummary for the nine")
            log("=" * 74)
            for core in CORES:
                fire("summary/%s" % core, "GetSystemSummary",
                     {"system": WFX.ref("%s/NS_SW_Core_%s" % (SYS_DIR, core))})
            log("  %d questions fired, none polled yet" % len(st["pending"]))
            st["phase"] = "poll_summary"
            return

        if st["phase"] == "poll_summary":
            if drain():
                return
            log("")
            for core in CORES:
                r = st["results"].get("summary/%s" % core) or {}
                if not r.get("ok"):
                    log("  %-12s NO ANSWER  %s"
                        % (core, str(r.get("why"))[:90]))
                    continue
                ems, how = summerise(r.get("value"))
                st["emitters"][core] = ems
                log("  %-12s %d emitter(s) %s -> %s"
                    % (core, len(ems), how, ", ".join(ems) if ems else "-"))
            log("")
            log("=" * 74)
            log("ROUND 2 - GetEmitterTopology, the four script stacks")
            log("=" * 74)
            n = 0
            for core, ems in st["emitters"].items():
                for em in ems:
                    fire("topo/%s/%s" % (core, em), "GetEmitterTopology",
                         {"emitterRef": WFX.stack_ref(
                             "%s/NS_SW_Core_%s" % (SYS_DIR, core), emitter=em)})
                    n += 1
            if n == 0:
                log("  no emitter names were recovered, so no topology could be")
                log("  asked for. The summary answers above carry the reason.")
                _finish("no emitters named")
                return
            log("  %d questions fired, none polled yet" % n)
            st["phase"] = "poll_topo"
            return

        if st["phase"] == "poll_topo":
            if drain():
                return
            log("")
            for core in CORES:
                for em in st["emitters"].get(core, []):
                    r = st["results"].get("topo/%s/%s" % (core, em)) or {}
                    log("")
                    log("  --- %s / %s ---" % (core, em))
                    if not r.get("ok"):
                        log("      NO ANSWER  %s" % str(r.get("why"))[:110])
                        continue
                    dump_emitter(core, r.get("value"))
            log("")
            log("=" * 74)
            log("ROUND 3 - GetStackIssues on ONE system, with my own deadline")
            log("=" * 74)
            log("  this is the tool that waits on a compile. It is asked once,")
            log("  on the core p48 measured, and an unanswered question is")
            log("  recorded as unanswered rather than waited on.")
            fire("issues/EdgeTrail", "GetStackIssues",
                 {"system": WFX.ref("%s/NS_SW_Core_EdgeTrail" % SYS_DIR)})
            st["phase"] = "poll_issues"
            return

        if st["phase"] == "poll_issues":
            if drain():
                return
            r = st["results"].get("issues/EdgeTrail") or {}
            log("")
            if r.get("ok"):
                log("  ANSWER: %s" % str(r.get("value"))[:4000])
                st["issues"]["EdgeTrail"] = r.get("value")
            else:
                log("  NO ANSWER: %s" % str(r.get("why"))[:140])
                log("  (identical in kind to p32/p43; recorded, not waited on)")
            _finish("readback complete")
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:170]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 12:
            _finish("too many tick errors")


def _finish(reason):
    if ST.get("phase") == "done":
        return
    ST["phase"] = "done"
    log("")
    log("=" * 74)
    log("SUMMARY")
    log("=" * 74)
    log("stop reason : %s" % reason)
    log("elapsed     : %.1f s over %d ticks" % (time.time() - ST["started"],
                                                ST["ticks"]))
    log("tick errors : %d" % ST["errors"])
    answered = sum(1 for r in ST["results"].values() if r.get("ok"))
    log("answered    : %d of %d questions"
        % (answered, len(ST["results"])))
    log("")
    log("HOW TO READ THIS")
    log("  Each stack line is '<script> <n> modules: name(inputs), ...'.")
    log("  What matters is whether PARTICLE SPAWN and PARTICLE UPDATE have any")
    log("  modules at all, because those are the two the engine log says have")
    log("  nothing connected to their output node.")
    log("P49 DONE")
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
