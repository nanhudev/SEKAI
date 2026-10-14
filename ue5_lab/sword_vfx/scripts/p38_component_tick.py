"""
p38_component_tick.py - is the component even running? (not "does it emit")

WHERE THIS COMES FROM
    p36 split the problem cleanly: the mesh and the material render (85320 px
    changed when the quads were placed), and the Niagara step adds nothing.
    p37 then ruled out my own timing error - Lifetime forced to 5 s, and five
    frames taken at +3/+6/+12/+42 ticks were IDENTICAL, spread 0.00.

    And p37 reported one number that had been sitting in plain sight:

        comp.is_active() = False

    after spawning the actor with auto_activate=True. A component that is not
    active does not simulate, and that is a different fault from "the emitter's
    spawn count is zero". So this asks the component directly, and separately
    asks the WORLD - because in an editor session the world is a different kind
    of world than the one a game runs in, and actors in it are not obliged to
    tick.

THE FOUR THINGS THAT WOULD EXPLAIN IT, AND HOW TO TELL THEM APART
    world delta time == 0        the world is not advancing at all
    tick enabled == False        the component is excluded from the tick
    is_active False, both above fine
                                 the component is alive but not activated
    all fine and still nothing   the emitter really does emit nothing

    Everything is read, nothing is inferred, and every setter is read back.

OUTPUT
    render/tick/_p38_*.png
    exports/p38_tick.txt

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p38_component_tick.py --render
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p38_tick.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/tick')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
ROOT = "/Game/SEKAI/VFX/Sword"

WIDTH = 1280
HEIGHT = 720

CAM = unreal.Vector(0.0, 0.0, 100.0)
CAM_YAW = 0.0
ROW_X = 200.0

SETTLE_TICKS = 90
BUDGET_SECONDS = 420.0

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

loaded = False
for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
    try:
        getattr(unreal, how)().load_level(LVL)
        log("level loaded via %s" % how)
        loaded = True
        break
    except Exception as exc:
        log("  %s failed: %s" % (how, str(exc)[:120]))
if not loaded:
    log("ABORT: no level")
    raise SystemExit(0)

W = None
for getter in ("UnrealEditorSubsystem", "EditorLevelLibrary"):
    try:
        W = getattr(unreal, getter)().get_editor_world()
        if W is not None:
            break
    except Exception:
        W = None
if W is None:
    log("ABORT: no world")
    raise SystemExit(0)


def load(path):
    p = path if "." in path.rsplit("/", 1)[-1] else "%s.%s" % (
        path, path.rsplit("/", 1)[-1])
    try:
        return unreal.EditorAssetLibrary.load_asset(p)
    except Exception as exc:
        log("    load %s failed: %s" % (path, str(exc)[:120]))
        return None


CAP_ROT = unreal.Rotator(pitch=0.0, yaw=CAM_YAW, roll=0.0)
rt = swcap.make_rt(W, WIDTH, HEIGHT)
cap = unreal.EditorLevelLibrary.spawn_actor_from_class(
    unreal.SceneCapture2D, CAM, CAP_ROT)
cc = cap.capture_component2d
try:
    cc.set_editor_property("texture_target", rt)
except Exception:
    pass
v = getattr(unreal.SceneCaptureSource, "SCS_FINAL_COLOR_LDR", None)
if v is not None:
    try:
        cc.set_editor_property("capture_source", v)
    except Exception:
        pass
try:
    cc.set_editor_property("capture_every_frame", False)
except Exception:
    pass
swcap.place_capture(cc, cap, CAM, CAP_ROT, loc_tol=5.0, rot_tol=5.0)

sysasset = load("%s/Systems/NS_SW_Core_Glint" % ROOT)
nact = unreal.EditorLevelLibrary.spawn_actor_from_class(
    unreal.NiagaraActor, unreal.Vector(ROW_X, 0.0, CAM.z),
    unreal.Rotator(pitch=0.0, yaw=CAM_YAW, roll=0.0))
comp = nact.get_component_by_class(unreal.NiagaraComponent) if nact else None
if comp is None:
    log("ABORT: no component")
    raise SystemExit(0)
try:
    comp.set_asset(sysasset)
except Exception as exc:
    log("set_asset: %s" % str(exc)[:110])

log("")
log("=" * 72)
log("DIAGNOSTICS")
log("=" * 72)


def diag(tag, extra_seconds=None):
    log("")
    log("--- %s" % tag)
    checks = (
        ("world delta time", lambda: unreal.SystemLibrary.get_world_delta_time(W)),
        ("world time dilation", lambda: W.get_editor_property("time_dilation")),
        ("comp.is_active()", lambda: comp.is_active()),
        ("comp.is_component_tick_enabled()", lambda: comp.is_component_tick_enabled()),
        ("comp.is_paused()", lambda: comp.is_paused()),
        ("comp.auto_activate", lambda: comp.get_editor_property("auto_activate")),
    )
    for label, fn in checks:
        try:
            log("    %-34s %s" % (label, fn()))
        except Exception as exc:
            log("    %-34s <raised %s>" % (label, str(exc)[:60]))
    try:
        t = comp.get_editor_property("primary_component_tick")
        for p in ("tick_interval", "tick_group", "start_with_tick_enabled",
                  "b_tick_even_when_paused", "end_tick_group"):
            try:
                log("    tick.%-29s %s" % (p, t.get_editor_property(p)))
            except Exception:
                pass
    except Exception as exc:
        log("    primary_component_tick <raised %s>" % str(exc)[:60])
    # The scene capture's own tick is a second witness: it is an actor
    # component too, and it demonstrably works (its image changes when the
    # camera moves), so comparing the two tells "this component" from
    # "components in this world".
    try:
        cct = cap.capture_component2d.get_editor_property("primary_component_tick")
        log("    capture.tick.start_with_tick_enabled  %s"
            % cct.get_editor_property("start_with_tick_enabled"))
    except Exception:
        pass


diag("as spawned")


def try_set(label, fn, verify=None):
    try:
        fn()
    except Exception as exc:
        log("    %-40s SET FAILED: %s" % (label, str(exc)[:70]))
        return
    if verify is None:
        log("    %-40s set (no readback)" % label)
        return
    try:
        log("    %-40s set -> readback %s" % (label, verify()))
    except Exception as exc:
        log("    %-40s set, readback raised %s" % (label, str(exc)[:60]))


log("")
log("--- forcing the component to be tickable, then activating ---")
try_set("set_component_tick_enabled(True)",
        lambda: comp.set_component_tick_enabled(True),
        lambda: comp.is_component_tick_enabled())
try_set("set_tickable_when_paused(True)",
        lambda: comp.set_tickable_when_paused(True))
try_set("set_paused(False)", lambda: comp.set_paused(False),
        lambda: comp.is_paused())
try_set("activate(True)", lambda: comp.activate(True),
        lambda: comp.is_active())

ST = {"handle": None, "started": time.time(), "ticks": 0, "phase": "settle",
      "wait": SETTLE_TICKS, "errors": 0, "shots": [], "rechecked": False}


def _do_export(name):
    swcap.export_rt(W, rt, OUT_DIR, name)
    got = swimg.collect(OUT_DIR, name)
    st = swimg.png_stats(got) if got else None
    if st and st["mean_luma"] is not None:
        log("    %-14s luma=%.2f distinct=%s" % (name, st["mean_luma"],
                                                 st["distinct_rgb"]))
        ST["shots"].append((name, st["mean_luma"]))
    else:
        log("    %-14s NO FILE / unreadable" % name)


def _finish(reason):
    if ST["phase"] == "done":
        return
    ST["phase"] = "done"
    log("")
    log("=" * 72)
    log("VERDICT")
    log("=" * 72)
    log("stop reason : %s" % reason)
    log("elapsed     : %.1f s over %d ticks" % (time.time() - ST["started"],
                                                ST["ticks"]))
    lums = [l for _, l in ST["shots"] if l is not None]
    spread = (max(lums) - min(lums)) if len(lums) >= 2 else None
    log("shot luma spread: %s" % ("%.2f" % spread if spread is not None else "n/a"))
    log("")
    log("Read the diagnostics above in this order:")
    log("  world delta time 0            -> the world is not advancing; no")
    log("                                   component in it can simulate, and")
    log("                                   this is an environment problem, not")
    log("                                   a Niagara one.")
    log("  is_active False after activate-> the component never started.")
    log("  tick enabled False            -> the component is excluded from tick.")
    log("  everything true, spread 0     -> the component runs and the emitter")
    log("                                   produces nothing: a graph problem.")
    log("P38 DONE")
    try:
        if ST["handle"] is not None:
            unreal.unregister_slate_post_tick_callback(ST["handle"])
    except Exception:
        pass
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception as exc:
        log("quit_editor failed: %s" % str(exc)[:120])


def tick(delta):
    st = ST
    if st["phase"] == "done":
        return
    st["ticks"] += 1
    if time.time() - st["started"] > BUDGET_SECONDS:
        _finish("budget exhausted")
        return
    try:
        if st["phase"] == "settle":
            st["wait"] -= 1
            if st["wait"] <= 0:
                diag("after %d ticks of world time" % st["ticks"])
                log("")
                log("--- shot A: should contain the particles if any exist ---")
                swcap.clear_rt(W, rt)
                cc.capture_scene()
                st["wait"] = 2
                st["phase"] = "expA"
            return

        if st["phase"] == "expA":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            _do_export("_p38_after_activate")
            diag("at shot A")
            # Activate again with everything tickable, then wait a short,
            # explicit number of ticks and shoot again.
            comp.activate(True)
            st["wait"] = 4
            st["phase"] = "waitB"
            return

        if st["phase"] == "waitB":
            st["wait"] -= 1
            if st["wait"] <= 0:
                log("")
                log("--- shot B: 4 ticks after a second activate ---")
                swcap.clear_rt(W, rt)
                cc.capture_scene()
                st["wait"] = 2
                st["phase"] = "expB"
            return

        if st["phase"] == "expB":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            _do_export("_p38_activate_again")
            diag("at shot B")
            _finish("diagnostics complete")
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:160]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 20:
            _finish("too many tick errors")


log("")
log("--- settle %d ticks then re-diagnose ---" % SETTLE_TICKS)
ST["handle"] = unreal.register_slate_post_tick_callback(tick)
