"""SEKAI Sword VFX - P28: which call actually crashes the engine?

WHY THIS EXISTS

    P22 was written to ask the engine whether the nine core systems are valid,
    and it hard-crashed:

        Fatal error! Unhandled Exception: EXCEPTION_ACCESS_VIOLATION
        reading address 0x0000000000000000
        [Callstack] UnrealEditor-Engine.dll!UnknownFunction
        [Callstack] UnrealEditor-CoreUObject.dll!UnknownFunction
        [Callstack] UnrealEditor-PythonScriptPlugin.dll!UnknownFunction
        [Callstack] python311.dll!UnknownFunction

    exit=3, and P22's own export file stops one line after
    "--- NS_SW_Core_EdgeTrail".

    THAT SINGLE LINE IS NOT ENOUGH TO NAME A CULPRIT, and this is the whole
    reason P28 exists. P22's per-system block is:

        log("--- %s" % name)                          <-- last line written
        asset = unreal.EditorAssetLibrary.load_asset(path)   <-- A
        WFX.call_quiet("GetSystemCompileState", ...)         <-- B
        WFX.call_quiet("GetStackIssues", ...)                <-- C
        WFX.call_quiet("GetEmitterTopology", ...)            <-- D

    Four candidates, one log line before all of them. Reading the record as
    "it died in GetSystemCompileState" would be a guess dressed as a finding,
    and the first guess about this crash (made before P22 was even run) was
    already wrong once.

    So P28 runs ONE stage per engine launch and brackets each stage with a
    start marker and an end marker. If the file holds ">>> STAGE ..." and not
    "<<< STAGE ...", the crash is inside that stage, observed rather than
    deduced. One launch per question, at roughly 30 s each, is a cheap price
    for a named cause instead of a plausible one.

TWO COMPETING HYPOTHESES, AND THEY NEED DIFFERENT FIXES

    (H1) THE COMMANDLET HAS NO NIAGARA STACK VIEW MODEL.
         P22's own header asserted this is why a commandlet was safe: "a
         commandlet never builds the Niagara editor's stack VIEW MODEL". That
         is exactly the claim under test. If GetStackIssues reaches into a
         stack view model that a commandlet never built, it dereferences null -
         which is precisely EXCEPTION_ACCESS_VIOLATION reading address 0x0,
         and precisely the callstack shape (Python -> PythonScriptPlugin ->
         CoreUObject -> Engine). Under H1 the fix is: run these two questions
         in an editor session (--editor) and read the answer there.

    (H2) THE SPIN NEVER COMPLETES, AND THE SPIN IS THE BUG.
         swvfx.py carries this note verbatim:

             call() spins until is_complete. That is fine for the authoring
             tools, which complete synchronously, but it deadlocks for
             anything that genuinely waits on a tick (GetStackIssues and
             GetSystemCompileState both wait on a Niagara compile).

         i.e. the module's own author already knew these two need
         call_async/poll. P22 called them with the SPINNING call_quiet anyway.
         Under H2 a commandlet simply never finishes those calls - the fix is
         call_async + poll across ticks, in an editor session.

    Both hypotheses point at the same repair (editor session + async poll), but
    they are separated here because a fix applied to an unproven cause is how
    this project has already lost mornings. The `compile_sync` and
    `issues_sync` stages test whether the spinning form survives a commandlet
    AT ALL; `*_async` stages test the polling form in an editor session.

    There is also (H3), which must not be skipped because it is cheap to test:
    loading the asset itself crashes. That is stage `load`, and it runs first.

Usage:
    cd sword_vfx/scripts
    P28_STAGE=load         ./run_ue.sh p28_iso.py     # EXPECTED TO CRASH (control)
    P28_STAGE=rawload      ./run_ue.sh p28_iso.py     # unreal.load_asset instead
    P28_STAGE=compile_no_load ./run_ue.sh p28_iso.py  # toolset, no load
    P28_STAGE=issues_no_load  ./run_ue.sh p28_iso.py
    P28_STAGE=topology_no_load ./run_ue.sh p28_iso.py
    P28_STAGE=compile_async ./run_ue.sh p28_iso.py --editor
    P28_STAGE=issues_async  ./run_ue.sh p28_iso.py --editor
    P28_STAGE=sweep         ./run_ue.sh p28_iso.py --editor   # all 9, p22's job

    THE ENVIRONMENT VARIABLE IS NOT OPTIONAL. Forgetting it does not fail - it
    silently re-runs the DEFAULT stage, which is what happened on the first
    batch: four launches were meant to test four stages and all four ran
    `load`, producing four replications of the crash and zero new information.
    Four replications of the control is a fine control; it is a wasted batch.

    P28_SYS=NS_SW_Core_Wave overrides the single system under test.

    Every stage appends to exports/p28_<stage>.txt. The file is reopened and
    closed per line, so whatever was written before a hard crash is already on
    disk - that durability is the entire instrument here.
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

STAGE = os.environ.get("P28_STAGE", "load").strip() or "load"
SYS_NAME = os.environ.get("P28_SYS", "").strip() or "NS_SW_Core_EdgeTrail"

OUTDIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports')
EXPORT = "%s/p28_%s.txt" % (OUTDIR, STAGE)

SYS_DIR = "/Game/SEKAI/VFX/Sword/Systems"

EMITTERS = {
    "NS_SW_Core_EdgeTrail": ("E_Trail",),
    "NS_SW_Core_Glint": ("E_Glint",),
    "NS_SW_Core_AirSlice": ("E_Slice",),
    "NS_SW_Core_Wave": ("E_Wave", "E_MistWake"),
    "NS_SW_Core_SpatialScar": ("E_Scar", "E_ScarMist"),
    "NS_SW_Core_MajorArc": ("E_Arc", "E_ArcMist"),
    "NS_SW_Core_MistWake": ("E_Wisp",),
    "NS_SW_Core_PurpleMotes": ("E_Motes",),
    "NS_SW_Core_Hit": ("E_Hit",),
}
ALL_SYSTEMS = tuple(EMITTERS.keys())

# --- logging -------------------------------------------------------------
# TWO SINKS ON PURPOSE.
#
#   file  - written with open/close per line, so it is durable through a hard
#           crash. This is the instrument that localises the fault.
#   unreal.log() - reaches Saved/Logs/SwordVFX_Lab.log as a `LogPython:` line,
#           which is the ONE place a python-side message survives an editor
#           session that swallows its exceptions. print() does NOT reach either
#           the run log or, reliably, anywhere a post-mortem looks.
LINES = []


def log(msg=""):
    msg = str(msg)
    LINES.append(msg)
    print(msg)
    try:
        with open(EXPORT, "a", encoding="utf-8") as fh:
            fh.write(msg + "\n")
    except Exception:
        pass
    try:
        unreal.log("P28[%s] %s" % (STAGE, msg))
    except Exception:
        pass


def brief(value, limit=240):
    if isinstance(value, (dict, list)):
        try:
            text = json.dumps(value, ensure_ascii=False, default=str)
        except Exception:
            text = repr(value)
    else:
        text = str(value)
    text = " ".join(text.split())
    return text if len(text) <= limit else text[:limit] + " ..."


def sys_path(name):
    return "%s/%s.%s" % (SYS_DIR, name, name)


def stage_start(label):
    log("")
    log(">>> STAGE START : %s" % label)


def stage_ok(label, note=""):
    log("<<< STAGE END   : %s OK%s" % (label, (" - " + note) if note else ""))


open(EXPORT, "w", encoding="utf-8").close()
WFX.bind_log(EXPORT, truncate=False)

log("engine: " + unreal.SystemLibrary.get_engine_version())
log("stage : %s" % STAGE)
log("system: %s" % SYS_NAME)
log("")
log("A file that holds '>>> STAGE START' but never '<<< STAGE END' for a")
log("stage names the crashing stage. That is the measurement.")
log("")

# =========================================================================
# stage: load - does a NiagaraSystem asset even load in a commandlet?
#
# MEASURED ANSWER, and it is the finding P22 could not reach: this stage
# crashes. `unreal.EditorAssetLibrary.load_asset()` on a NiagaraSystem raises
# EXCEPTION_ACCESS_VIOLATION reading 0x0 and takes the engine down before the
# END marker below. Four separate launches reproduced it, exit=3 each time.
#
# AND THIS HAZARD WAS ALREADY DOCUMENTED IN THIS PROJECT, in p11_niagara.py's
# own `save_all()` docstring:
#
#     EditorAssetLibrary.save_asset         -> EXCEPTION_ACCESS_VIOLATION 0x0
#     EditorAssetLibrary.save_loaded_asset  -> same
#     EditorLoadingAndSavingUtils.save_packages([pkg], False) -> same
#
# so p11 was written to avoid EditorAssetLibrary entirely for Niagara assets,
# and P22 then reintroduced it on the very first line of its per-system loop -
# as a mere existence check that the toolset did not need. That one line is
# what killed P22, and the toolset calls P22 was actually asking about were
# never reached.
#
# The stage is kept, and kept first, because it is now the negative control:
# `rawload` below tests the same asset through a DIFFERENT loader, and the
# `*_no_load` stages test whether the toolset needs any load at all.
# =========================================================================
if STAGE == "load":
    path = sys_path(SYS_NAME)
    stage_start("load %s" % SYS_NAME)
    log("    path: %s" % path)
    log("    loader: unreal.EditorAssetLibrary.load_asset")
    log("    (expected to CRASH - no END marker will follow; that is the")
    log("     replication of P22's fatal line, run on purpose)")
    a = unreal.EditorAssetLibrary.load_asset(path)
    log("    load_asset returned: %s  (None=%s)" % (type(a).__name__, a is None))
    stage_ok("load", "load_asset survived - NOT the expected result")
    log("")
    log("P28-STAGE VERDICT: EditorAssetLibrary.load_asset SURVIVED")

# =========================================================================
# stage: rawload - the same asset through a loader that is NOT
# EditorAssetLibrary. If this survives, the fix is a one-line substitution.
# =========================================================================
elif STAGE == "rawload":
    path = sys_path(SYS_NAME)
    stage_start("rawload %s via unreal.load_asset" % SYS_NAME)
    log("    path: %s" % path)
    fn = getattr(unreal, "load_asset", None)
    log("    unreal.load_asset present: %s" % (fn is not None))
    a = None
    if fn is not None:
        a = fn(path)
    log("    returned: %s  (None=%s)" % (type(a).__name__, a is None))
    if a is not None:
        try:
            log("    class: %s" % a.get_class().get_name())
            log("    path_name: %s" % a.get_path_name())
        except Exception as exc:
            log("    introspect raised: %s" % str(exc)[:160])
    stage_ok("rawload")
    log("")
    log("P28-STAGE VERDICT: unreal.load_asset %s"
        % ("FAILED (returned None)" if a is None else "SURVIVED"))

# =========================================================================
# stage: *_no_load - the toolset, with NO asset load anywhere.
#
# This is the decisive stage. P22's structure assumed the toolset needs a
# loaded UObject; swvfx.ref() passes a refPath STRING and the toolset resolves
# it on the C++ side. If these survive, P22 never needed to load anything and
# the whole probe can be rebuilt without touching EditorAssetLibrary.
# =========================================================================
elif STAGE in ("compile_no_load", "issues_no_load", "topology_no_load"):
    TOOL = {"compile_no_load": "GetSystemCompileState",
            "issues_no_load": "GetStackIssues",
            "topology_no_load": "GetEmitterTopology"}[STAGE]
    path = sys_path(SYS_NAME)

    stage_start("%s (NO asset load at all)" % TOOL)
    if TOOL == "GetEmitterTopology":
        em = (EMITTERS.get(SYS_NAME) or ("E_Dummy",))[0]
        payload = {"emitterRef": WFX.stack_ref(path, emitter=em)}
        log("    emitter: %s" % em)
    else:
        payload = {"system": WFX.ref(path)}
    log("    payload: %s" % brief(payload, 300))
    log("    calling WFX.call_quiet ...")
    ok, res = WFX.call_quiet(TOOL, payload)
    log("    returned: ok=%s" % ok)
    if ok:
        log("    value: %s" % brief(res, 500))
    else:
        log("    error: %s" % str(res)[:400])
    stage_ok(TOOL)
    log("")
    log("P28-STAGE VERDICT: %s SURVIVED without any load (ok=%s)" % (TOOL, ok))

# =========================================================================
# stage: *_sync - the SPINNING form, with the load removed.
#
# Identical to *_no_load except that it names the mechanism. Both end up in
# WFX.call_quiet; the distinction that matters is "no load", which is now
# established as the safe form.
# =========================================================================
elif STAGE in ("compile_sync", "issues_sync", "topology"):
    TOOL = {"compile_sync": "GetSystemCompileState",
            "issues_sync": "GetStackIssues",
            "topology": "GetEmitterTopology"}[STAGE]
    path = sys_path(SYS_NAME)

    stage_start("%s (SPINNING call_quiet, NO asset load)" % TOOL)
    if TOOL == "GetEmitterTopology":
        em = (EMITTERS.get(SYS_NAME) or ("E_Dummy",))[0]
        payload = {"emitterRef": WFX.stack_ref(path, emitter=em)}
        log("    emitter: %s" % em)
    else:
        payload = {"system": WFX.ref(path)}
    log("    payload: %s" % brief(payload, 300))
    log("    calling WFX.call_quiet ...")
    ok, res = WFX.call_quiet(TOOL, payload)
    log("    returned: ok=%s" % ok)
    if ok:
        log("    value: %s" % brief(res, 400))
    else:
        log("    error: %s" % str(res)[:400])
    stage_ok(TOOL)
    log("")
    log("P28-STAGE VERDICT: %s SURVIVED the spinning form (ok=%s)" % (TOOL, ok))

# =========================================================================
# stages: *_async - the polling form, needs an editor session with ticks
# =========================================================================
elif STAGE in ("compile_async", "issues_async", "sweep"):
    TOOL_OF = {"compile": "GetSystemCompileState",
               "issues": "GetStackIssues",
               "topology": "GetEmitterTopology"}
    if STAGE == "sweep":
        TARGETS = list(ALL_SYSTEMS)
        ASK = ("compile", "issues", "topology")
    else:
        TARGETS = [SYS_NAME]
        ASK = ("compile" if STAGE == "compile_async" else "issues",)

    WFX.install_watchdog(300)

    STATE = {"handle": None, "t": 0, "wait": 0, "done": False,
             "errors": 0, "idx": 0, "phase": "launch", "raw": None,
             "tool": "", "results": [], "ticks_seen": 0, "handed": False,
             "t0": time.time(), "call_t0": 0.0}

    TICK_BUDGET = 900
    POLL_TICKS = 20          # ticks between polls of an in-flight call
    # A TICK COUNT IS NOT A DURATION, and measuring a compile against one is how
    # "never completed" gets reported for something that was never given a
    # chance. In -nullrhi -unattended the editor has no vsync and no frames to
    # draw, so its tick rate is unrelated to wall clock; measured here at
    # roughly 4-5 ticks/second in one session and unknown in another. A Niagara
    # compile is a wall-clock job. So the give-up condition is SECONDS.
    POLL_SECONDS = float(os.environ.get("P28_POLL_SECONDS", "45") or 45)
    SETTLE = 8               # ticks between systems

    # flatten the work: (system, tool) pairs
    WORK = []
    for s in TARGETS:
        for k in ASK:
            WORK.append((s, TOOL_OF[k]))

    def _finish(reason):
        st = STATE
        if st["done"]:
            return
        st["done"] = True
        log("")
        log("=" * 74)
        log("--- async results ---")
        for s, tool, ok, val in st["results"]:
            if ok:
                log("    %-26s %-22s OK   %s" % (s, tool, brief(val, 300)))
            else:
                log("    %-26s %-22s FAIL %s" % (s, tool, brief(val, 200)))
        done_n = sum(1 for r in st["results"] if r[2])
        log("")
        log("    calls completed : %d / %d" % (done_n, len(WORK)))
        log("    ticks observed  : %d" % st["ticks_seen"])
        elapsed = time.time() - (st["t0"] or time.time())
        log("    wall clock      : %.1f s  (%.1f ticks/s - which is why the "
            "timeout is in seconds, not ticks)"
            % (elapsed, st["ticks_seen"] / max(elapsed, 0.001)))
        log("    tick errors     : %d" % st["errors"])
        log("    stop reason     : %s" % reason)
        log("")
        if st["ticks_seen"] == 0:
            log("    => THE TICK CALLBACK NEVER RAN. Nothing about the toolset")
            log("       is established - the session had no editor loop at all.")
        elif done_n == 0:
            log("    => THE ASYNC TOOLS NEVER COMPLETE, even with ticks. So")
            log("       'waits on a Niagara compile' is not the whole story;")
            log("       these tools need something this session does not have.")
        elif done_n < len(WORK):
            log("    => PARTIAL: %d of %d answered. Read the per-call lines." %
                (done_n, len(WORK)))
        else:
            log("    => EVERY ASYNC CALL RETURNED AN ANSWER. This is the")
            log("       working path for section 35: an editor session and")
            log("       call_async + poll, not a commandlet and not a spin.")
        log("")
        log("P28 VERDICT [%s]: %d/%d answered, %d tick(s), %d error(s)"
            % (STAGE, done_n, len(WORK), st["ticks_seen"], st["errors"]))
        log("P28 DONE")
        print("P28 DONE")
        try:
            unreal.unregister_slate_post_tick_callback(st["handle"])
        except Exception:
            pass
        try:
            unreal.SystemLibrary.quit_editor()
        except Exception:
            pass

    def _launch():
        """Fire the next async call, or finish."""
        st = STATE
        if st["idx"] >= len(WORK):
            _finish("all work complete")
            return
        s, tool = WORK[st["idx"]]
        path = sys_path(s)
        st["tool"] = tool
        st["sys"] = s
        log("")
        log("[%d/%d] %s  %s" % (st["idx"] + 1, len(WORK), s, tool))
        # NO ASSET LOAD HERE, and that is the point of this file: the load is
        # what crashes (stage `load`), and the toolset resolves the refPath
        # itself. Loading would both crash and be redundant.
        if tool == "GetEmitterTopology":
            em = (EMITTERS.get(s) or ("E_Dummy",))[0]
            payload = {"emitterRef": WFX.stack_ref(path, emitter=em)}
            log("    emitter: %s" % em)
        else:
            payload = {"system": WFX.ref(path)}
        log("    payload: %s" % brief(payload, 220))
        log("    execute_tool -> NOT spinning; polling across ticks")
        try:
            st["raw"] = WFX.call_async(tool, payload)
            log("    result object: %s  is_complete=%s"
                % (type(st["raw"]).__name__,
                   st["raw"].get_editor_property("is_complete")))
        except Exception as exc:
            log("    execute_tool RAISED: %s" % str(exc)[:300])
            st["results"].append((s, tool, False, "raise: %s" % str(exc)[:160]))
            st["idx"] += 1
            st["phase"] = "settle"
            st["wait"] = SETTLE
            return
        st["phase"] = "poll"
        st["call_t0"] = time.time()
        st["wait"] = POLL_TICKS

    def tick(delta):
        st = STATE
        if st["done"]:
            return
        st["ticks_seen"] += 1
        st["t"] += 1
        if st["t"] > TICK_BUDGET:
            _finish("tick budget exhausted")
            return
        if not st["handed"]:
            # Armed only after the callback has demonstrably ticked once - its
            # job is to catch "the callback never ran", so handing over before
            # the first tick would throw that net away.
            WFX.watchdog_handover()
            st["handed"] = True
        st["wait"] -= 1
        if st["wait"] > 0:
            return
        # `launch` and `settle` both mean "start the next call"; settle is
        # only here so consecutive calls cannot run inside the same tick,
        # which in a synchronous-execute toolset would make two results look
        # like one.
        if st["phase"] in ("launch", "settle"):
            st["phase"] = "launch"
            _launch()
            return
        # phase == poll
        raw = st["raw"]
        try:
            done, ok, val = WFX.poll(raw, st["tool"])
        except Exception as exc:
            st["errors"] += 1
            log("    poll RAISED: %s" % str(exc)[:200])
            st["results"].append((st["sys"], st["tool"], False,
                                  "poll raise: %s" % str(exc)[:160]))
            st["idx"] += 1
            st["phase"] = "settle"
            st["wait"] = SETTLE
            return
        if not done:
            waited = time.time() - (st["call_t0"] or time.time())
            if waited >= POLL_SECONDS:
                log("    GAVE UP after %.1f wall-clock seconds (%d ticks, "
                    "%.1f ticks/s): is_complete stayed False."
                    % (waited, st["ticks_seen"],
                       st["ticks_seen"] / max(waited, 0.001)))
                log("    => it did not complete in the time allowed. That is not")
                log("       the same as 'it can never complete' - if the wait was")
                log("       short, re-run with a larger P28_POLL_SECONDS before")
                log("       concluding anything.")
                st["results"].append((st["sys"], st["tool"], False,
                                      "not complete after %.0fs" % waited))
                st["idx"] += 1
                st["phase"] = "settle"
                st["wait"] = SETTLE
                return
            return
        log("    completed: ok=%s value=%s" % (ok, brief(val, 300)))
        st["results"].append((st["sys"], st["tool"], bool(ok),
                              val if ok else str(val)[:200]))
        st["idx"] += 1
        st["phase"] = "settle"
        st["wait"] = SETTLE

    log("")
    log("--- async plan: %d call(s) over %d system(s) ---"
        % (len(WORK), len(TARGETS)))
    log("    poll every %d ticks, give up after %.0f wall-clock seconds, "
        "settle %d ticks, budget %d ticks"
        % (POLL_TICKS, POLL_SECONDS, SETTLE, TICK_BUDGET))
    log("")
    log("    NOTE: these tools resolve only when a Niagara component is")
    log("    REGISTERED IN A LEVEL, because that is what instantiates the")
    log("    system and dispatches a compile. This stage loads no level, so a")
    log("    non-completion here is expected and is NOT evidence that the")
    log("    tools cannot work - it is evidence that they need a world.")
    log("    p20_review_map.py builds exactly that: a Niagara gallery whose")
    log("    comment records the same conclusion (aggregateStatus=UpToDate while")
    log("    is_stale=True, i.e. 'no compile was performed').")
    stage_start("async loop")
    STATE["handle"] = unreal.register_slate_post_tick_callback(tick)

else:
    log("UNKNOWN STAGE %r" % STAGE)
    log("known: load rawload compile_no_load issues_no_load topology_no_load")
    log("       compile_sync issues_sync topology")
    log("       compile_async issues_async sweep")
    log("P28 DONE (no work)")
