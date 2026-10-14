"""
p32_compile_audit.py - put the section-35 question to the engine, on the record.

THE QUESTION
    Section 35 says IMPLEMENTED means "the Niagara graph really exists AND
    RUNS". P11 built nine systems and reported `0 errors / 49 pins / 9 saved`.
    A later reading of a crash ensure -

        Ensure condition failed: !ModuleGroup.StartNodes.IsEmpty()
        [NiagaraStackGraphUtilities.cpp:906] -> EXCEPTION_ACCESS_VIOLATION

    - was taken as evidence that the module stacks were never wired into the
    execution chain, which would mean IMPLEMENTED was never earned.

    P20's own comment records where that ensure actually came from:
    `EditorAssetLibrary.list_assets`, i.e. ASSET DISCOVERY, not stack content.
    The two readings cannot both be right, and neither of them is the engine's
    verdict. So ask the engine.

WHY THE LEVEL HAS TO BE LOADED
    GetSystemCompileState and GetStackIssues both wait on a Niagara compile.
    With no level open nothing instantiates the systems, nothing dispatches a
    compile, and the call has nothing to resolve - which is exactly what p28
    measured: `--editor`, no crash, promise never completes in 80 ticks.

    P11 got an answer because its nine systems were in memory and its gallery
    had activated them. This probe does the same thing deliberately: load the
    review level, let the nine `Lab_FX_*` components activate, then ask.

WHY THE TIMEOUT IS A WALL CLOCK
    "80 ticks" is not a duration. In a `-nullrhi` editor the tick rate is
    whatever the CPU manages, so a tick budget cannot be reported as a wait.
    Every wait below is seconds, and the report says how many seconds elapsed.

OUTPUT
    exports/p32_compile_audit.txt
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p32_compile_audit.txt')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
SYS_DIR = "/Game/SEKAI/VFX/Sword/Systems"

SYSTEMS = (
    "NS_SW_Core_EdgeTrail", "NS_SW_Core_Glint", "NS_SW_Core_AirSlice",
    "NS_SW_Core_Wave", "NS_SW_Core_SpatialScar", "NS_SW_Core_MajorArc",
    "NS_SW_Core_MistWake", "NS_SW_Core_PurpleMotes", "NS_SW_Core_Hit",
)

SETTLE_TICKS = 90          # let the level's Niagara components activate
CALL_SECONDS = 40.0        # one tool call may wait on one compile
BUDGET_SECONDS = 480.0     # whole run

WFX.bind_log(EXPORT)
log = WFX.log
WFX.install_watchdog(grace_ticks=240)


def sys_path(name):
    return "%s/%s.%s" % (SYS_DIR, name, name)


# ------------------------------------------------------------------ level
log("engine: %s" % unreal.SystemLibrary.get_engine_version())
log("")
log("--- loading the review level (this is what activates the gallery) ---")
loaded = False
for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
    try:
        getattr(unreal, how)().load_level(LVL)
        log("    loaded via %s" % how)
        loaded = True
        break
    except Exception as exc:
        log("    %s failed: %s" % (how, str(exc)[:140]))
if not loaded:
    log("    COULD NOT LOAD %s" % LVL)
    log("P32 DONE (no level, nothing to audit)")
    raise SystemExit(0)

# ------------------------------------------------------------------ cast
#
# Which systems are actually instantiated right now. A system that is in the
# gallery is being compiled for real; one that is only on disk is not. Counting
# the actors separates "the level lost them" from "the engine rejects them".
log("")
log("--- Niagara actors present in the level ---")
try:
    actors = unreal.EditorLevelLibrary.get_all_level_actors()
except Exception as exc:
    actors = []
    log("    get_all_level_actors raised: %s" % str(exc)[:140])

seen = {}
for a in actors or []:
    try:
        if not isinstance(a, unreal.NiagaraActor):
            continue
        label = a.get_actor_label()
        comp = a.get_component_by_class(unreal.NiagaraComponent)
        asset = comp.get_editor_property("asset") if comp is not None else None
        if asset is not None:
            ap = asset.get_path_name()
            seen[ap.split(".")[0]] = (label, bool(comp.get_editor_property("auto_activate")))
    except Exception:
        continue

log("    distinct Niagara systems instantiated: %d" % len(seen))
for name in SYSTEMS:
    key = "%s/%s" % (SYS_DIR, name)
    if key in seen:
        label, auto = seen[key]
        log("      %-26s actor %-28s auto_activate=%s" % (name, label, auto))
    else:
        log("      %-26s NOT INSTANTIATED (no actor holds it)" % name)

# ------------------------------------------------------------------ plan
#
# FIFO of questions. A compile answer that reports err or warn pushes an issue
# question onto the front, so the payload is fetched while the system is still
# hot in the compile cache rather than minutes later.
PENDING = []
for name in SYSTEMS:
    PENDING.append({"sys": name, "tool": "GetSystemCompileState",
                    "payload": {"system": WFX.ref(sys_path(name))}})

ST = {
    "handle": None,
    "started": time.time(),
    "ticks": 0,
    "handed": False,
    "phase": "settle",
    "wait": SETTLE_TICKS,
    "pending": PENDING,
    "cur": None,
    "raw": None,
    "deadline": 0.0,
    "results": [],
    "timeouts": 0,
    "errors": 0,
    "n": 0,
    "dumped_full": 0,
}


def _finish(reason):
    if ST["phase"] == "done":
        return
    ST["phase"] = "done"
    el = time.time() - ST["started"]
    n_err = n_warn = n_ok = 0
    for r in ST["results"]:
        if r.get("tool") != "GetSystemCompileState":
            continue
        if r.get("verdict") == "ERR":
            n_err += 1
        elif r.get("verdict") == "WARN":
            n_warn += 1
        elif r.get("verdict") == "OK":
            n_ok += 1

    log("")
    log("--- summary ---")
    log("stop reason        : %s" % reason)
    log("elapsed            : %.1f s over %d ticks" % (el, ST["ticks"]))
    log("questions asked    : %d" % len(ST["results"]))
    log("call timeouts      : %d" % ST["timeouts"])
    log("tick-loop errors   : %d" % ST["errors"])
    log("")
    log("compile state read : %d of %d systems" % (n_err + n_warn + n_ok, len(SYSTEMS)))
    log("    clean          : %d" % n_ok)
    log("    warnings       : %d" % n_warn)
    log("    ERRORS         : %d" % n_err)
    log("")
    if n_ok + n_warn + n_err < len(SYSTEMS):
        log("P32 VERDICT: INCOMPLETE - the engine did not answer for every system,")
        log("             so no claim about section 35 can be made from this run.")
    elif n_err:
        log("P32 VERDICT: COMPILE ERRORS - the graphs exist but the compiler")
        log("             rejects them. Section 35 IMPLEMENTED is NOT earned.")
    elif n_warn:
        log("P32 VERDICT: COMPILES WITH WARNINGS - read the warnings before")
        log("             claiming IMPLEMENTED; a warning is not a pass.")
    else:
        log("P32 VERDICT: ALL NINE SYSTEMS COMPILE CLEAN")
        log("             This is the engine's own answer, not p11's self-report.")
        log("             IMPLEMENTED per section 35 still also requires that they")
        log("             RUN (produce particles) - that is a VISUAL question and")
        log("             is answered by a frame, not by a status string.")
    log("P32 DONE")
    try:
        if ST["handle"] is not None:
            unreal.unregister_slate_post_tick_callback(ST["handle"])
    except Exception:
        pass
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception as exc:
        log("quit_editor failed: %s" % str(exc)[:120])


def _absorb(cur, done, ok, val, note):
    """Record one tool answer, and push a follow-up if the answer is bad."""
    ST["n"] += 1
    tag = "[%d]" % ST["n"]
    tool = cur["tool"]
    name = cur["sys"]

    if not done:
        ST["timeouts"] += 1
        log("%s %-26s %-24s TIMEOUT after %.1f s" % (tag, name, tool, CALL_SECONDS))
        ST["results"].append({"sys": name, "tool": tool, "verdict": "TIMEOUT"})
        return

    if not ok:
        ST["errors"] += 1
        log("%s %-26s %-24s TOOL ERROR: %s" % (tag, name, tool, str(val)[:200]))
        ST["results"].append({"sys": name, "tool": tool, "verdict": "TOOLERROR",
                              "detail": str(val)[:400]})
        return

    if tool == "GetSystemCompileState":
        # Dump the first answer in full: the schema is the thing being learned,
        # and a summary I have not verified is a guess about the engine.
        if ST["dumped_full"] < 1:
            ST["dumped_full"] += 1
            log("%s %-26s FULL JSON:" % (tag, name))
            try:
                txt = json.dumps(val, indent=2, ensure_ascii=False)
            except Exception:
                txt = repr(val)
            for line in txt.splitlines()[:80]:
                log("      " + line)
        st = val if isinstance(val, dict) else {}
        agg = st.get("aggregateStatus")
        stale = st.get("isStale")
        err = st.get("error") or st.get("hasErrors") or st.get("errors")
        warn = st.get("warnings") or st.get("hasWarnings") or st.get("warn")
        scripts = st.get("scriptStates") or st.get("scripts") or []

        bad = []
        if isinstance(scripts, list):
            for s in scripts:
                if not isinstance(s, dict):
                    continue
                sname = "%s/%s" % (s.get("emitterName", "?"), s.get("usage", "?"))
                sstat = s.get("state") or s.get("status")
                serr = s.get("error") or s.get("hasErrors")
                swarn = s.get("warning") or s.get("hasWarnings")
                if serr or swarn:
                    bad.append("%s %s" % (sname, sstat))

        if err or bad:
            verdict = "ERR"
        elif warn:
            verdict = "WARN"
        else:
            verdict = "OK"

        log("%s %-26s status=%-22s stale=%-6s err=%-6s warn=%-6s scripts=%s"
            % (tag, name, agg, stale, bool(err), bool(warn), len(scripts)))
        for b in bad[:6]:
            log("      ! %s" % b)

        ST["results"].append({"sys": name, "tool": tool, "verdict": verdict,
                              "aggregateStatus": agg, "isStale": stale})

        if verdict != "OK":
            # Front of the queue, while the compile cache is warm.
            ST["pending"].insert(0, {"sys": name, "tool": "GetStackIssues",
                                     "payload": {"system": WFX.ref(sys_path(name))}})
        return

    if tool == "GetStackIssues":
        issues = val if isinstance(val, list) else (
            (val or {}).get("issues") if isinstance(val, dict) else None) or []
        log("%s %-26s %d issue(s)" % (tag, name, len(issues)))
        for it in issues[:10]:
            if not isinstance(it, dict):
                log("      ? %s" % str(it)[:200])
                continue
            log("      - [%s] %s" % (it.get("severity") or it.get("type") or "?",
                                     str(it.get("message") or it.get("text") or "")[:180]))
            fixes = it.get("fixes") or it.get("possibleFixes") or []
            for fx in (fixes or [])[:4]:
                if isinstance(fx, dict):
                    log("          fix: %s" % str(fx.get("label") or fx.get("fixId")
                                                  or fx)[:140])
        ST["results"].append({"sys": name, "tool": tool, "verdict": "ISSUES",
                              "count": len(issues)})
        return

    log("%s %-26s %s" % (tag, name, str(val)[:200]))
    ST["results"].append({"sys": name, "tool": tool, "verdict": "OK"})


def tick(delta):
    st = ST
    if st["phase"] == "done":
        return
    st["ticks"] += 1

    if not st["handed"]:
        WFX.watchdog_handover()
        st["handed"] = True

    if time.time() - st["started"] > BUDGET_SECONDS:
        _finish("wall-clock budget of %ds exhausted" % BUDGET_SECONDS)
        return

    try:
        if st["phase"] == "settle":
            st["wait"] -= 1
            if st["wait"] <= 0:
                log("")
                log("--- settle complete after %d ticks, %.1f s: asking the engine ---"
                    % (st["ticks"], time.time() - st["started"]))
                st["phase"] = "ask"
            return

        if st["phase"] == "ask":
            if not st["pending"]:
                _finish("every question answered")
                return
            cur = st["pending"][0]
            st["cur"] = cur
            try:
                st["raw"] = WFX.call_async(cur["tool"], cur["payload"])
            except Exception as exc:
                st["pending"].pop(0)
                _absorb(cur, True, False, str(exc), "raise")
                st["phase"] = "ask"
                return
            # Same-tick completion is the common case (p11 measured it), so try
            # once immediately: most answers never need a second tick.
            done, ok, val = WFX.poll(st["raw"], cur["tool"])
            if done:
                st["pending"].pop(0)
                _absorb(cur, True, ok, val, "")
                st["phase"] = "ask"
                return
            st["deadline"] = time.time() + CALL_SECONDS
            st["phase"] = "poll"
            return

        if st["phase"] == "poll":
            done, ok, val = WFX.poll(st["raw"], st["cur"]["tool"])
            if done:
                cur = st["cur"]
                st["pending"].pop(0)
                _absorb(cur, True, ok, val, "")
                st["phase"] = "ask"
                return
            if time.time() > st["deadline"]:
                cur = st["cur"]
                st["pending"].pop(0)
                _absorb(cur, False, None, None, "timeout")
                st["phase"] = "ask"
                return
            return
    except Exception as exc:
        # A tick callback that raises re-raises forever in an editor session
        # (measured: 954 consecutive frames), so nothing escapes this function.
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:200]))
        if st["errors"] > 20:
            _finish("too many tick errors")


log("")
log("--- %d systems will be asked GetSystemCompileState ---" % len(PENDING))
log("    settle %d ticks, call timeout %.0f s, budget %.0f s"
    % (SETTLE_TICKS, CALL_SECONDS, BUDGET_SECONDS))
ST["handle"] = unreal.register_slate_post_tick_callback(tick)
