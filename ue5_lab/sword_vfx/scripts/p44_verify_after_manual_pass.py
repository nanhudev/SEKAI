"""
p44_verify_after_manual_pass.py - the check to run AFTER the one human editor pass.

WHAT THE MANUAL PASS IS, AND WHY IT IS THE ONLY THING LEFT
    Everything this line can build from a script has been built. What it cannot
    do is make the engine compile a Niagara system, and here is the whole
    evidence chain, all of it measured, none of it inferred:

      p11   reported its own nine systems back as
                status=UpToDate err=False warn=False compiling=True   (8 of 9)
                status=UpToDate err=False warn=False compiling=False   (Hit)
            and aggregated that as "compile NOT STALE : 1 / 9".

      p43   asked the same nine assets the same question in a fresh session and
            every one of eighteen answers was
                "Timed out after 120 seconds waiting for Niagara System compile
                 to complete."
            while that session's engine log contains ZERO Niagara
            "Compiling System" lines - the only compiles it issued were the nine
            Blueprints it had just created. A wait for a compile that is never
            issued cannot finish; the timeouts are the symptom, not the fault.

      p41   the nine Lab_FX_* components report active=False, tick=False,
            auto_activate=True, in the editor world AND in the PIE world
            (UEDPIE_0_L_SwordVFX_Lab), and activate(True) on all nine inside the
            game world gave before=False after=False for every one.

      p42   ten cumulative lever configurations - including Niagara's own
            deterministic-capture path (DESIRED_AGE + seek_to_desired_age) and
            its hand-drive path (advance_simulation) - produced a frame that is
            byte-identical to twelve decimal places, while the levers that should
            stick did stick (never_distance_cull, max_sim_time, desired_age, the
            component tick flag all read back changed).

      p36   the same capture DOES render a mesh and a material (85320 pixels
            changed when two quads appeared), so the capture is not the problem.

      p40   a level load made all nine compile once - the log shows
            "Compiling System ... took 4.66 sec" for every one of them - but
            p43's level load did not reproduce that, and in the sessions where
            they did compile the components still refused to activate.

    So: an asset carrying an outstanding compile will not run, no setter fixes
    it, and no session type this harness can launch will resolve it. The one
    move left is a human opening each system in the Niagara editor, letting it
    compile, and saving - which is precisely the class of step section 0 of the
    brief says to mark rather than fake.

    THIS SCRIPT IS WHAT MAKES THAT PASS CHECKABLE. Do the pass, run this, and
    the two questions that decide the whole batch get answered:
        do the nine systems now report compiling=False?
        do the nine components now activate, and does a frame change?

MODE, AND WHY IT IS --render
    Two phases with incompatible needs, so the order matters.
      Phase 1 asks the compile question. It must run with NO level loaded: p32
      measured that with the review map open the question times out (9 x 40 s,
      361.8 s total) and the engine then access-violates on quit.
      Phase 2 needs pixels, so the level has to be loaded.
    Phase 1 therefore runs in the script body and across the first ticks, and
    the level is only loaded once phase 1 has been answered or given up on.

OUTPUT
    render/pass01_check/_p44_<Core>_before.png    as loaded
    render/pass01_check/_p44_<Core>_after.png     after activate(True) + 20 ticks
    exports/p44_verify.txt

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p44_verify_after_manual_pass.py --render
    python tools/frame_pairs.py render/pass01_check
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

import swcap  # noqa: E402
import swimg  # noqa: E402
import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p44_verify.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/pass01_check')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
SYS_DIR = "/Game/SEKAI/VFX/Sword/Systems"
BP_DIR = "/Game/SEKAI/VFX/Sword/BP"

WIDTH = 1280
HEIGHT = 720

CORES = ["EdgeTrail", "Glint", "AirSlice", "Wave", "SpatialScar", "MajorArc",
         "MistWake", "PurpleMotes", "Hit"]

# The gallery row: p20 spawned the nine Lab_FX_* actors from y=-1200 upward in
# 300 cm steps at x=900, z=150, and p40/p42 both read that back. The camera is
# derived from the row rather than hand-copied per core, so a change in the row
# cannot silently point the camera at empty ground.
ROW_X = 900.0
ROW_Y0 = -1200.0
ROW_STEP = 300.0
ROW_Z = 150.0
CAM_DIST = 300.0

POLL_DEADLINE = 150.0
HOLD_TICKS = 20
EXPORT_GAP = 2
BUDGET_SECONDS = 560.0

WFX.bind_log(EXPORT)
log = WFX.log

os.makedirs(OUT_DIR, exist_ok=True)
if os.path.isdir(OUT_DIR):
    for _f in os.listdir(OUT_DIR):
        try:
            os.remove(os.path.join(OUT_DIR, _f))
        except Exception:
            pass

log("engine: %s" % unreal.SystemLibrary.get_engine_version())


# ---------------------------------------------------------------------------
# PHASE 1 - the compile question, asked before any level exists
# ---------------------------------------------------------------------------
log("")
log("=" * 74)
log("PHASE 1 - do the nine systems report an outstanding compile?")
log("=" * 74)
log("Asked with NO level loaded, on purpose: with the review map open this")
log("question times out for every system and the engine dies on quit (p32).")

RAW = []
for core in CORES:
    try:
        RAW.append((core,
                    WFX.call_async("GetSystemCompileState",
                                   {"system": WFX.ref("%s/NS_SW_Core_%s"
                                                      % (SYS_DIR, core))})))
    except Exception as exc:
        RAW.append((core, "FIRE FAILED: %s" % str(exc)[:90]))
log("  %d questions fired" % len(RAW))


# ---------------------------------------------------------------------------
# capture, built on demand in phase 2
# ---------------------------------------------------------------------------
ST = {"handle": None, "ticks": 0, "phase": "poll1", "started": time.time(),
      "errors": 0, "answers": {}, "poll_started": time.time(),
      "i": -1, "shot": False, "wait": 0, "rows": {}, "lums": {},
      "ew": None, "rt": None, "cc": None, "subjects": []}


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
    log("--- the compile question ---")
    clean, stale, unanswered = 0, 0, 0
    for core, _raw in RAW:
        ok, val = ST["answers"].get(core, (None, "not answered"))
        if not ok:
            unanswered += 1
            log("  %-12s UNANSWERED: %s" % (core, str(val)[:100]))
            continue
        blob = json.dumps(val, ensure_ascii=False, sort_keys=True)
        compiling = None
        if isinstance(val, dict):
            for k in ("compiling", "bCompiling", "isCompiling"):
                if k in val:
                    compiling = val[k]
                    break
            if compiling is None and isinstance(val.get("compileState"), dict):
                compiling = val["compileState"].get("compiling")
        if compiling is False:
            clean += 1
        elif compiling is True:
            stale += 1
        log("  %-12s compiling=%-5s %s" % (core, compiling, blob[:220]))
    log("")
    log("  compiling=False: %d   compiling=True: %d   unanswered: %d"
        % (clean, stale, unanswered))

    log("")
    log("--- the components ---")
    moved = []
    for core in CORES:
        r = ST["rows"].get(core, {})
        b = ST["lums"].get("_p44_%s_before" % core)
        a = ST["lums"].get("_p44_%s_after" % core)
        d = "-"
        if b is not None and a is not None:
            d = "%+.3f" % (a - b)
            if abs(a - b) > 0.05:
                moved.append(core)
        log("  %-12s active=%-6s tick=%-6s rendered=%-6s before=%-9s after=%-9s d=%s"
            % (core, r.get("active"), r.get("tick"), r.get("rendered"), b, a, d))

    log("")
    log("WHAT THE NUMBERS MEAN, AND NOTHING MORE")
    if clean == len(CORES) and moved:
        log("=> BOTH QUESTIONS ANSWERED YES. The systems compile and the")
        log("   components come up and draw. IMPLEMENTED is earned for the nine")
        log("   cores, and the pass01 movie is the next step, not a blocker.")
    elif clean == len(CORES):
        log("=> THE COMPILE IS FIXED and the components still draw nothing. The")
        log("   graph is now the only suspect left, and the frames say which")
        log("   cores emit and which do not - check them individually, because")
        log("   the burst-driven cores need the timing captured, while EdgeTrail")
        log("   and PurpleMotes are rate-driven and should show up in any frame.")
    elif stale:
        log("=> STILL UNCOMPILED. %d of nine still report compiling=True, so the" % stale)
        log("   manual pass did not take. Open the system, confirm the stack")
        log("   shows no compile-in-progress indicator, then SAVE the package -")
        log("   compiling without saving leaves the asset exactly as it was.")
    else:
        log("=> THE COMPILE QUESTION IS STILL UNANSWERABLE. Nothing about the")
        log("   graphs can be judged from this run; do not read the component")
        log("   rows as evidence either way.")
    log("P44 DONE")
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


def editor_world():
    for holder, name in (("UnrealEditorSubsystem", "get_editor_world"),
                         ("EditorLevelLibrary", "get_editor_world")):
        try:
            w = getattr(getattr(unreal, holder)(), name)()
            if w is not None:
                return w
        except Exception:
            continue
    return None


def enumerate_actors():
    raw = []
    for holder in ("EditorActorSubsystem", "EditorLevelLibrary"):
        try:
            raw = list(getattr(unreal, holder)().get_all_level_actors())
            break
        except Exception:
            continue
    out, seen = [], set()
    for a in raw:            # every actor comes back TWICE in this build
        try:
            key = a.get_path_name()
        except Exception:
            key = str(id(a))
        if key in seen:
            continue
        seen.add(key)
        out.append(a)
    return out


def find_subjects():
    """The nine Lab_FX_* components, in CORES order, with their positions."""
    by_label = {}
    for a in enumerate_actors():
        try:
            if not isinstance(a, unreal.NiagaraActor):
                continue
            comp = a.get_component_by_class(unreal.NiagaraComponent)
            if comp is None:
                continue
            by_label[a.get_actor_label()] = (a, comp)
        except Exception:
            continue
    out = []
    for idx, core in enumerate(CORES):
        label = "Lab_FX_%s" % core
        if label not in by_label:
            log("    %-22s MISSING from the level" % label)
            continue
        out.append((core, label) + by_label[label])
    return out


def setup_capture(world):
    rt = swcap.make_rt(world, WIDTH, HEIGHT)
    if rt is None:
        return None, None, None
    cap = None
    for maker in (
            lambda: unreal.EditorLevelLibrary.spawn_actor_from_class(
                unreal.SceneCapture2D, unreal.Vector(0, 0, 0), unreal.Rotator()),
            lambda: unreal.EditorActorSubsystem().spawn_actor_from_class(
                unreal.SceneCapture2D, unreal.Vector(0, 0, 0), unreal.Rotator()),
    ):
        try:
            cap = maker()
            if cap is not None:
                break
        except Exception as exc:
            log("    capture spawn failed: %s" % str(exc)[:90])
    if cap is None:
        return rt, None, None
    cc = cap.capture_component2d
    swcap.set_prop(cc, "texture_target", rt)
    v = getattr(unreal.SceneCaptureSource, "SCS_FINAL_COLOR_LDR", None)
    if v is not None:
        swcap.set_prop(cc, "capture_source", v)
    swcap.set_prop(cc, "capture_every_frame", False)
    return rt, cc, cap


def aim_at(idx):
    """Camera pose derived from the row, never hand-copied per core."""
    y = ROW_Y0 + idx * ROW_STEP
    return (unreal.Vector(ROW_X + CAM_DIST, y, ROW_Z),
            unreal.Rotator(pitch=0.0, yaw=180.0, roll=0.0))


def read_component(comp):
    d = {}
    for k, fn in (("active", comp.is_active),
                  ("tick", comp.is_component_tick_enabled),
                  ("rendered", comp.was_recently_rendered)):
        try:
            d[k] = fn()
        except Exception:
            d[k] = "?"
    return d


def phase_poll1():
    done = 0
    for core, raw in RAW:
        if core in ST["answers"]:
            done += 1
            continue
        if isinstance(raw, str):
            ST["answers"][core] = (False, raw)
            done += 1
            continue
        try:
            fin, ok, val = WFX.poll(raw, core)
        except Exception as exc:
            ST["answers"][core] = (False, "poll raised: %s" % str(exc)[:80])
            done += 1
            continue
        if not fin:
            continue
        ST["answers"][core] = (ok, val)
        done += 1
    return done


def phase_load_level():
    for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
        try:
            getattr(unreal, how)().load_level(LVL)
            log("  level loaded via %s" % how)
            return True
        except Exception as exc:
            log("  %s failed: %s" % (how, str(exc)[:100]))
    return False


def tick(delta):
    st = ST
    if st["phase"] == "done":
        return
    st["ticks"] += 1
    if time.time() - st["started"] > BUDGET_SECONDS:
        _finish("budget exhausted")
        return
    try:
        if st["phase"] == "poll1":
            done = phase_poll1()
            waited = time.time() - st["poll_started"]
            if done < len(RAW) and waited < POLL_DEADLINE:
                if st["ticks"] % 120 == 0:
                    log("    phase 1: %d/%d answered at %.0f s"
                        % (done, len(RAW), waited))
                return
            log("  %d of %d answered after %.1f s" % (done, len(RAW), waited))
            for core, _raw in RAW:
                if core not in st["answers"]:
                    st["answers"][core] = (
                        False, "never completed within %.0f s" % waited)
            log("")
            log("--- loading the review map for phase 2 ---")
            if not phase_load_level():
                _finish("no level, so no frames")
                return
            st["ew"] = editor_world()
            st["rt"], st["cc"], _cap = setup_capture(st["ew"])
            if st["rt"] is None or st["cc"] is None:
                _finish("no capture")
                return
            log("")
            log("--- the nine components ---")
            st["subjects"] = find_subjects()
            log("  %d of %d found in the level" % (len(st["subjects"]), len(CORES)))
            # One warm-up frame. create_render_target2d's construction-time
            # content is opaque near-black and the FIRST clear after creating a
            # target does not take, so the first export is never the answer.
            swcap.clear_rt(st["ew"], st["rt"])
            try:
                st["cc"].capture_scene()
            except Exception as exc:
                log("  warm capture_scene raised: %s" % str(exc)[:100])
            swcap.export_rt(st["ew"], st["rt"], OUT_DIR, "_p44_warm")
            got = swimg.collect(OUT_DIR, "_p44_warm")
            s = swimg.png_stats(got) if got else None
            log("  warm-up frame luma=%s"
                % (s["mean_luma"] if s else "NO FILE"))
            st["i"] = -1
            st["tasks"] = build_tasks()
            st["ti"] = 0
            st["phase"] = "tasks"
            st["wait"] = 4
            return

        if st["phase"] == "tasks":
            # A flat task queue, not named phases. The first version of this
            # section used a shoot/gap pair and never captured the AFTER frame at
            # all - the queue advanced to the next core straight after exporting
            # the before frame, so all eighteen images would have been nine pairs
            # of identical files. A linear list makes the omission impossible to
            # hide: the list either contains a shoot for both sides or it does
            # not, and run_task names each step in the log.
            if st["wait"] > 0:
                st["wait"] -= 1
                return
            if st["ti"] >= len(st["tasks"]):
                _finish("nine pairs taken")
                return
            kind, arg = st["tasks"][st["ti"]]
            st["ti"] += 1
            run_task(kind, arg)
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:170]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 12:
            _finish("too many tick errors")


def build_tasks():
    tasks = []
    for idx, (core, label, actor, comp) in enumerate(ST["subjects"]):
        tasks.append(("aim", idx))
        tasks.append(("shoot", idx))
        tasks.append(("exp", (idx, "before")))
        tasks.append(("activate", idx))
        tasks.append(("wait", HOLD_TICKS))
        tasks.append(("read", idx))
        tasks.append(("shoot", idx))
        tasks.append(("exp", (idx, "after")))
        tasks.append(("wait", EXPORT_GAP))
    return tasks


def run_task(kind, arg):
    st = ST
    if kind == "aim":
        core, label, actor, comp = st["subjects"][arg]
        loc, rot = aim_at(arg)
        ok, why = swcap.place_capture(st["cc"], actor, loc, rot,
                                      loc_tol=5.0, rot_tol=5.0)
        log("")
        log("  --- %s (%s) ---" % (core, label))
        if not ok:
            # place_capture moves AND verifies. If it did not land, say so - p23
            # reported "capture placed ... True" while measuring elsewhere and
            # the probe then drew conclusions about the whole world.
            log("    CAMERA DID NOT LAND: %s" % str(why)[:90])
        return

    if kind == "shoot":
        idx = arg
        comp = st["subjects"][idx][3]
        for fn in (lambda: comp.set_hidden_in_scene_capture(False),
                   lambda: comp.set_visibility(True),
                   lambda: comp.set_rendering_enabled(True),
                   lambda: comp.set_component_tick_enabled(True)):
            try:
                fn()
            except Exception:
                pass
        swcap.clear_rt(st["ew"], st["rt"])
        try:
            st["cc"].capture_scene()
        except Exception as exc:
            log("    capture_scene raised: %s" % str(exc)[:100])
        st["wait"] = EXPORT_GAP
        return

    if kind == "exp":
        idx, which = arg
        core = CORES[idx]
        name = "_p44_%s_%s" % (core, which)
        swcap.export_rt(st["ew"], st["rt"], OUT_DIR, name)
        got = swimg.collect(OUT_DIR, name)
        s = swimg.png_stats(got) if got else None
        lum = s["mean_luma"] if s else None
        st["lums"][name] = lum
        log("    %-22s luma=%s%s" % (name, lum,
                                     "" if s is None else
                                     " distinct=%s" % s["distinct_rgb"]))
        st["wait"] = EXPORT_GAP
        return

    if kind == "activate":
        core = CORES[arg]
        comp = st["subjects"][arg][3]
        try:
            comp.activate(True)
        except Exception as exc:
            log("    activate raised: %s" % str(exc)[:90])
        st["rows"].setdefault(core, {}).update(read_component(comp))
        log("    after activate(True): %s" % st["rows"][core])
        return

    if kind == "read":
        core = CORES[arg]
        comp = st["subjects"][arg][3]
        st["rows"].setdefault(core, {}).update(read_component(comp))
        log("    %d ticks after activate: %s" % (HOLD_TICKS, st["rows"][core]))
        return

    if kind == "wait":
        st["wait"] = int(arg)
        return


log("")
log("--- phase 1 first, then the map ---")
WFX.install_watchdog(grace_ticks=1000000, grace_seconds=BUDGET_SECONDS + 40.0)
ST["handle"] = unreal.register_slate_post_tick_callback(tick)
