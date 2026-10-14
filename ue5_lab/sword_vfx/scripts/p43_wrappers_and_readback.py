"""
p43_wrappers_and_readback.py - read the nine systems back, then build the UE-side
                               integration asset for each of them.

WHY THIS RUN EXISTS, AFTER p42
    p42 tried ten cumulative lever configurations on Lab_FX_EdgeTrail, including
    Niagara's own deterministic-capture path (DESIRED_AGE + seek_to_desired_age)
    and its hand-drive path (advance_simulation). The frame was byte-identical
    across all ten - luma equal to twelve decimal places - while the levers that
    should stick did stick (never_distance_cull, max_sim_time, desired_age and
    the component tick flag all read back changed).

    So: a scripted -ExecCmds session cannot bring this component up, in the
    editor world or in a PIE world. That is now a measurement.

    Which leaves a fork, and this run takes the productive side of it. The
    component being inert says NOTHING about the graph - an inert component
    renders nothing however good its emitters are. So the graph is not
    condemned, and it is not confirmed either. What p11 claimed was structural:
    37 modules, 49 pins, 0 unverified pins, 0 errors. This re-reads that claim
    with the same instruments, and while it is in there it builds the one
    production asset the batch still owes that does not need a human.

WHY NO LEVEL IS LOADED
    p32 measured this the expensive way: with L_SwordVFX_Lab loaded, all nine
    GetSystemCompileState calls time out at 40 s each - 361.8 s for nine
    questions - and the engine then access-violates on quit. p11 ran the same
    tools in an editor session with NO level and got answers.

    p32 also fired those calls ONE AT A TIME. This fires all of them before
    polling any, because they are independent: the wall clock should be one
    compile, not nine.

ORDER, AND WHY THE WRAPPERS COME FIRST
    First run of this script put the questions first and lost the whole run: the
    poll sat at 0/18 and the WATCHDOG killed the session at 4000 ticks. Two
    faults, and the second is the instructive one.

      1. The questions still do not resolve without a level either - 0 of 18
         inside 56 s - so "no level loaded" is not by itself what makes them
         answerable, and p11's answers must have come from somewhere else.
      2. install_watchdog(4000) is a grace in TICKS while the poll deadline is
         in SECONDS. The tick rate is ~71 ticks/s in this session type, so 4000
         ticks is 56 s, not 200 s. The watchdog fired 56 s into a wait that was
         allowed 200 s, and its message ("the script body never reached its
         finish path") reads as a hung script rather than as a mis-set unit.

    The wrapper tool is synchronous and fast, so it now runs first: a hung
    question can no longer cost the assets. And swvfx.install_watchdog takes
    grace_seconds now, so the watchdog and the deadline are in the same unit.

OUTPUT
    exports/p43_wrappers.txt
    Content/SEKAI/VFX/Sword/BP/B_SW_Core_*.uasset   (nine new assets)

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p43_wrappers_and_readback.py --editor
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import json
import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p43_wrappers.txt')

SYS_DIR = "/Game/SEKAI/VFX/Sword/Systems"
BP_DIR = "/Game/SEKAI/VFX/Sword/BP"
SYS_DISK = str(_SEKAI_ROOT / 'ue5_lab/SwordVFX_Lab/Content/SEKAI/VFX/Sword/Systems')
BP_DISK = str(_SEKAI_ROOT / 'ue5_lab/SwordVFX_Lab/Content/SEKAI/VFX/Sword/BP')

CORES = ["EdgeTrail", "Glint", "AirSlice", "Wave", "SpatialScar", "MajorArc",
         "MistWake", "PurpleMotes", "Hit"]

PARENT_CLASS = "/Script/Engine.Actor"

POLL_DEADLINE = 200.0
BUDGET_SECONDS = 420.0

WFX.bind_log(EXPORT)
log = WFX.log

log("engine: %s" % unreal.SystemLibrary.get_engine_version())
log("")
log("=" * 74)
log("PART A - what the engine says the nine systems contain")
log("=" * 74)
log("No level is loaded, deliberately. p32 measured that with the review map")
log("open, every compile-state question times out and the engine then dies on")
log("quit.")

SUMMARIES = {}
for core in CORES:
    path = "%s/NS_SW_Core_%s" % (SYS_DIR, core)
    ok, res = WFX.call_quiet("GetSystemSummary", {"system": WFX.ref(path)})
    SUMMARIES[core] = (ok, res)
    if not ok:
        log("")
        log("  %-12s FAILED: %s" % (core, str(res)[:150]))
        continue
    blob = json.dumps(res, ensure_ascii=False, sort_keys=True)
    log("")
    log("  %-12s %s" % (core, blob[:600]))
    if len(blob) > 600:
        log("               ... (%d chars total)" % len(blob))

# What p11 claimed, restated here so this run can contradict it in the same page
# rather than in a different file a week later.
CLAIM = {"modules": 37, "pins": 49, "unverified_pins": 0, "errors": 0}


# ---------------------------------------------------------------------------
# PART B/C - fired together, polled together
# ---------------------------------------------------------------------------
ST = {"handle": None, "ticks": 0, "phase": "wrap", "started": time.time(),
      "errors": 0, "raw": [], "answers": {}, "made": {}, "saved": None,
      "before": {}, "after": {}, "touched": None}


def _finish(reason):
    if ST["phase"] == "done":
        return
    ST["phase"] = "done"
    log("")
    log("=" * 74)
    log("VERDICT")
    log("=" * 74)
    log("stop reason : %s" % reason)
    log("elapsed     : %.1f s over %d ticks" % (time.time() - ST["started"],
                                                ST["ticks"]))
    log("tick errors : %d" % ST["errors"])

    log("")
    log("--- stack issues, per system ---")
    any_issue = False
    for key, (ok, val) in sorted(ST["answers"].items()):
        if not ok:
            log("  %-30s UNANSWERED: %s" % (key, str(val)[:110]))
            any_issue = True
            continue
        if val is None:
            log("  %-30s clean (no issues reported)" % key)
            continue
        try:
            n = len(val) if hasattr(val, "__len__") else 1
        except Exception:
            n = "?"
        log("  %-30s %s item(s)" % (key, n))
        log("      %s" % json.dumps(val, ensure_ascii=False)[:900])
        any_issue = True
    log("")
    if not any_issue:
        log("=> EVERY SYSTEM CAME BACK CLEAN on both questions, which is what")
        log("   p11 claimed and this is the first independent confirmation of it.")
    else:
        log("=> SOMETHING IS REPORTED. Read the items above before building")
        log("   anything on top of these systems - an unanswered question is not")
        log("   a clean one, and this run does not treat it as one.")

    log("")
    log("--- wrappers ---")
    built, on_disk, tool_ok = 0, 0, 0
    for core in CORES:
        name = "B_SW_Core_%s" % core
        ok, why = ST["made"].get(core, (None, "not attempted"))
        disk = os.path.join(BP_DISK, name + ".uasset")
        size = os.path.getsize(disk) if os.path.isfile(disk) else -1
        if size > 0:
            on_disk += 1
        if ok:
            tool_ok += 1
        if ok and size > 0:
            built += 1
        log("  %-20s tool=%-5s disk=%s  %s"
            % (name, ok, ("%d bytes" % size) if size >= 0 else "MISSING",
               "" if ok else str(why)[:90].replace("\n", " ")))
    log("")
    # MEASURED, and the reporting has to keep these apart. The tool returned an
    # error on all nine -
    #     无法获取变量值：数据无效或未初始化。  ("failed to get variable value:
    #     data invalid or uninitialized")
    # five times per call, which is almost certainly it reading user-variable
    # overrides off a component whose system carries the outstanding compile
    # below - AND nine non-empty .uasset files appeared on disk anyway, and the
    # engine log for that session shows
    #     LogBlueprint: Compiling Blueprint '.../BP/B_SW_Core_SpatialScar...'
    #     ... one line per core
    # which is a Blueprint compiler run over nine real Blueprint assets.
    #
    # So "tool=OK" and "the file exists" are different facts and the first run of
    # this script collapsed them, reporting 0/9 for a directory holding nine
    # 198 KB assets. Both numbers are printed now, and the one that is a fact
    # about the disk is named as such.
    log("  tool reported success          : %d / %d" % (tool_ok, len(CORES)))
    log("  non-empty .uasset on disk      : %d / %d" % (on_disk, len(CORES)))
    log("  both                           : %d / %d" % (built, len(CORES)))
    log("  p11 structural claim was %s" % json.dumps(CLAIM))
    log("  UNVERIFIED HERE: that each wrapper's Niagara component actually")
    log("  references its system. The packages are compressed, so a byte grep")
    log("  finds nothing, and reading it back needs another engine run. Say")
    log("  'nine Blueprint assets exist'; do not say 'nine wrappers are wired'.")
    log("")
    log("--- the compile pass ---")
    log("  system packages written: %s of %d"
        % (ST["touched"] if ST["touched"] is not None else "not attempted",
           len(CORES)))
    log("")
    log("WHAT THIS DOES AND DOES NOT ESTABLISH")
    log("  ASSET READY  for the nine wrappers, if the count above is 9 - they")
    log("               are new files with non-zero size, which is a fact about")
    log("               the disk and not about the graph.")
    log("  IMPLEMENTED  STILL NOT CLAIMED. p42 measured that a scripted session")
    log("               cannot bring a Niagara component up at all, so nothing")
    log("               built here has ever been seen running.")
    log("  VISUALLY VERIFIED  not claimable for the same reason.")
    log("")
    log("  THE ONE THING THAT MATTERS MOST HERE is the compile pass. p11's own")
    log("  readback says 8 of 9 systems report compiling=True, i.e. an")
    log("  outstanding compile. This run then asked the same nine assets the")
    log("  same question in a fresh session and every answer was")
    log("      Timed out ... waiting for Niagara System compile to complete")
    log("  with zero Compiling System lines in that session's engine log. A wait")
    log("  for a compile that was never issued cannot finish.")
    log("  If the packages above were rewritten, the compile was issued by the")
    log("  level load, completed, and has now been persisted - and the next")
    log("  thing to check is whether the components activate at all. If they")
    log("  were NOT rewritten, nothing was persisted and the remaining move is")
    log("  one human pass: open each system in the Niagara editor, let it")
    log("  compile, save.")
    log("P43 DONE")
    WFX.watchdog_handover()
    try:
        if ST["handle"] is not None:
            unreal.unregister_slate_post_tick_callback(ST["handle"])
    except Exception:
        pass
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception as exc:
        log("quit_editor failed: %s" % str(exc)[:120])


def phase_fire():
    """Fire every question before waiting on any of them.

    The tools are independent; p32's 361.8 s was nine compiles end to end, not
    one. Firing first turns the wall clock into a max instead of a sum.
    """
    for core in CORES:
        path = WFX.ref("%s/NS_SW_Core_%s" % (SYS_DIR, core))
        for tool in ("GetStackIssues", "GetSystemCompileState"):
            tag = "%s/%s" % (core, tool)
            try:
                ST["raw"].append((tag, WFX.call_async(tool, {"system": path})))
            except Exception as exc:
                ST["answers"][tag] = (False, "fire failed: %s" % str(exc)[:90])
    log("")
    log("=" * 74)
    log("PART C - %d questions fired, none polled yet" % len(ST["raw"]))
    log("=" * 74)


def phase_poll():
    done = 0
    for tag, raw in ST["raw"]:
        if tag in ST["answers"]:
            done += 1
            continue
        try:
            fin, ok, val = WFX.poll(raw, tag)
        except Exception as exc:
            ST["answers"][tag] = (False, "poll raised: %s" % str(exc)[:90])
            done += 1
            continue
        if not fin:
            continue
        ST["answers"][tag] = (ok, val)
        done += 1
    return done, len(ST["raw"])


def phase_wrap():
    unreal.EditorAssetLibrary.make_directory(BP_DIR)
    for core in CORES:
        target = "%s/B_SW_Core_%s" % (BP_DIR, core)
        payload = {
            "system": WFX.ref("%s/NS_SW_Core_%s" % (SYS_DIR, core)),
            "newAssetPath": target,
            "parentClass": {"refPath": PARENT_CLASS},
        }
        # MEASURED, first run: through WFX's default toolset this came back
        #     Unknown tool ConstructNiagaraBPWrapperFromSystem
        # The tool is real; it lives in NiagaraToolset_Blueprint. "Unknown tool"
        # reads as "this build cannot do it", which is why the toolset is now an
        # explicit argument instead of a module constant.
        ok, res = WFX.call_quiet("ConstructNiagaraBPWrapperFromSystem", payload,
                                 WFX.BLUEPRINT_TOOLSET)
        ST["made"][core] = (ok, res)
        log("")
        log("  %-20s %s" % ("B_SW_Core_%s" % core,
                            "OK" if ok else "FAILED: %s" % str(res)[:130]))
        if ok:
            blob = json.dumps(res, ensure_ascii=False)[:200] if res else "(none)"
            log("      %s" % blob)


def phase_save():
    """save_dirty_packages, which p11 found actually writes.

    p11's note, kept because it saves the next person the experiment: a console
    "SaveAll" survives but writes nothing, and EditorAssetLibrary.save_asset
    takes the editor down with EXCEPTION_ACCESS_VIOLATION. A freshly created
    asset is already dirty, so no dirty-marking step is needed - UPackage has no
    set_dirty_flag in the Python API and marking turned out not to matter.
    """
    try:
        unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True)
        ST["saved"] = "save_dirty_packages returned"
    except Exception as exc:
        ST["saved"] = "save_dirty_packages raised: %s" % str(exc)[:120]
    log("")
    log("  save: %s" % ST["saved"])


def mtimes():
    out = {}
    for core in CORES:
        p = os.path.join(SYS_DISK, "NS_SW_Core_%s.uasset" % core)
        out[core] = os.path.getmtime(p) if os.path.exists(p) else 0.0
    return out


def load_level():
    for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
        try:
            getattr(unreal, how)().load_level(
                "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab")
            return how
        except Exception as exc:
            log("    %s failed: %s" % (how, str(exc)[:100]))
    return None


def tick(delta):
    st = ST
    if st["phase"] == "done":
        return
    st["ticks"] += 1
    if time.time() - st["started"] > BUDGET_SECONDS:
        _finish("budget exhausted")
        return
    try:
        if st["phase"] == "wrap":
            log("")
            log("=" * 74)
            log("PART B - the integration asset, one per core")
            log("=" * 74)
            log("Built BEFORE the questions, because the questions are the part")
            log("that hung on the first run and the assets are the part that")
            log("cannot be replaced by waiting longer.")
            phase_wrap()
            st["phase"] = "save"
            return

        if st["phase"] == "save":
            phase_save()
            st["phase"] = "fire"
            return

        if st["phase"] == "fire":
            phase_fire()
            st["phase"] = "poll"
            st["poll_started"] = time.time()
            return

        if st["phase"] == "poll":
            done, total = phase_poll()
            waited = time.time() - st["poll_started"]
            if done < total and waited < POLL_DEADLINE:
                if st["ticks"] % 120 == 0:
                    log("    polled %d/%d at %.0f s" % (done, total, waited))
                return
            log("")
            log("  %d of %d questions answered after %.1f s"
                % (done, total, waited))
            if done < total:
                for tag, raw in ST["raw"]:
                    if tag not in st["answers"]:
                        # An unanswered question is recorded as unanswered. p11
                        # made this point and it is the whole reason this file
                        # has a three-state answer instead of a boolean.
                        st["answers"][tag] = (
                            False, "never completed within %.0f s" % waited)
            st["phase"] = "compile_pass"
            return

        if st["phase"] == "compile_pass":
            # The one thing p43 learned that is actionable, and this phase is the
            # attempt to act on it.
            #
            # p11's own readback, re-read this session:
            #     status=UpToDate err=False warn=False compiling=True    (8 of 9)
            #     status=UpToDate err=False warn=False compiling=False   (Hit only)
            # and p11 aggregated that as "compile NOT STALE : 1 / 9".
            #
            # p43 then asked the same question of the same nine assets and got
            #     18 of 18: "Timed out after 120 seconds waiting for Niagara
            #     System compile to complete."
            # while Saved/Logs for that session contains ZERO "Compiling System"
            # lines. A wait for a compile that was never issued cannot finish, so
            # the assets on disk are carrying an outstanding compile and a plain
            # load does not re-issue it.
            #
            # But a LEVEL LOAD does. MEASURED in the p40 session's log, all nine:
            #     LogNiagara: Compiling System NiagaraSystem ... took 4.66 sec
            # So: load the map, give the compiles the same handful of seconds the
            # log shows them taking, then save. If the compile completing is what
            # UNiagaraComponent::Activate refuses on - which is the hypothesis,
            # not yet a proof - then this single pass is what unblocks the whole
            # batch, and either way the mtimes below say whether it wrote.
            st["before"] = mtimes()
            log("")
            log("=" * 74)
            log("PART D - attempt: issue the compiles, then persist them")
            log("=" * 74)
            log("  loading the review map; a level load is what makes the engine")
            log("  issue a compile for each of the nine (see the p40 log).")
            how = load_level()
            log("  level load via: %s" % how)
            if how is None:
                st["phase"] = "settle"
                st["wait"] = 2
                return
            # Seconds, not ticks. The tick rate here is ~117/s, so a tick count
            # is a unit nobody can read and any conversion is a guess.
            #
            # CONSEQUENCE FOR tools/preflight_ue_script.py: its tick dry-run
            # drives ticks without letting wall-clock time pass, so this phase
            # reports "still ticking after 2000 ticks" and the dry run cannot
            # reach the finish path. That is a limit of the dry run, not a fault
            # here - the dry run's job is "does the script load", and it says
            # LOADS OK. Every wait in this file that the dry run CAN exercise is
            # tick-based on purpose.
            st["wait_until"] = time.time() + 40.0
            st["phase"] = "let_compile"
            return

        if st["phase"] == "let_compile":
            if time.time() < st["wait_until"]:
                return
            phase_save()
            st["after"] = mtimes()
            log("")
            log("  --- system .uasset mtimes ---")
            touched = 0
            for core in CORES:
                b = st["before"].get(core, 0.0)
                a = st["after"].get(core, 0.0)
                if a > b:
                    touched += 1
                log("    %-12s %s -> %s %s" % (core, b, a,
                                               "WROTE" if a > b else "unchanged"))
            st["touched"] = touched
            st["phase"] = "settle"
            st["wait"] = 3
            return

        if st["phase"] == "settle":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            _finish("all phases done")
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:170]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 12:
            _finish("too many tick errors")


log("")
log("--- wrappers first, then %d systems x 2 questions ---" % len(CORES))
# grace_seconds is set ABOVE the poll deadline on purpose: the watchdog exists to
# catch an uncaught exception, not to cut off a wait the script is deliberately
# holding. The first run of this script had them the other way round and lost the
# assets to a healthy poll.
WFX.install_watchdog(grace_ticks=1000000, grace_seconds=BUDGET_SECONDS + 30.0)
ST["handle"] = unreal.register_slate_post_tick_callback(tick)
