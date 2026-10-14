"""
p39_tick_in_editor.py - turn the component's tick on, properly this time.

WHAT p38 MEASURED
    tick.start_with_tick_enabled       False
    comp.is_component_tick_enabled()   False     (and set_component_tick_enabled(True)
                                                  read back True, then read False 90
                                                  ticks later - something resets it)
    comp.is_active()                   False     even straight after activate(True)
    comp.is_paused()                   False
    comp.auto_activate                 True

    while in the SAME world:
    capture.tick.start_with_tick_enabled  True    <- the SceneCapture component ticks

    So this is not "Niagara is broken". It is "this component is not being ticked
    in this world", and the scene capture in the same world proves the world
    itself is alive. An unticked component never runs its spawn script, which is
    why nine systems produced 0 pixels across eighteen frames.

THE LEVERS, TRIED IN ORDER AND EACH READ BACK
    1. primary_component_tick.b_tick_in_editor = True
       The tick function of an actor component is skipped in the editor unless
       this flag is set. It is the flag that separates the capture component
       (ticks, works) from the Niagara component (does not).
    2. primary_component_tick.start_with_tick_enabled = True
    3. set_component_tick_enabled(True)
    4. set_tickable_when_paused(True)
    5. a fresh spawn via NiagaraFunctionLibrary.spawn_system_at_location, which
       builds a component that is active from birth rather than one that was
       placed and then asked to wake up.

    After each, is_active() and is_component_tick_enabled() are read in the SAME
    tick and then again 10 ticks later - because p38 caught a setter that read
    back True immediately and False afterwards, and an immediate readback is not
    evidence that a setting stuck.

OUTPUT
    render/tickp/_p39_*.png
    exports/p39_tickprops.txt

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p39_tick_in_editor.py --render
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p39_tickprops.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/tickp')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
ROOT = "/Game/SEKAI/VFX/Sword"

WIDTH = 1280
HEIGHT = 720
CAM = unreal.Vector(0.0, 0.0, 100.0)
CAM_YAW = 0.0
ROW_X = 200.0

SETTLE_TICKS = 60
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
comp = nact.get_component_by_class(unreal.NiagaraComponent)
try:
    comp.set_asset(sysasset)
except Exception as exc:
    log("set_asset: %s" % str(exc)[:110])


def state(tag):
    def g(fn):
        try:
            return fn()
        except Exception as exc:
            return "<%s>" % str(exc)[:40]
    log("    [%-22s] active=%-5s tick_enabled=%-5s tickable_when_paused=%-5s"
        % (tag, g(lambda: comp.is_active()),
           g(lambda: comp.is_component_tick_enabled()),
           g(lambda: comp.is_tickable_when_paused())))


log("")
log("=" * 72)
log("LEVERS (each applied in the script body, before the first tick)")
log("=" * 72)
state("as spawned")

try:
    tf = comp.get_editor_property("primary_component_tick")
except Exception as exc:
    tf = None
    log("    primary_component_tick unavailable: %s" % str(exc)[:90])

if tf is not None:
    for prop, val in (("b_tick_in_editor", True),
                      ("start_with_tick_enabled", True),
                      ("tick_interval", 0.0)):
        try:
            tf.set_editor_property(prop, val)
        except Exception as exc:
            log("    tick.%-26s SET FAILED: %s" % (prop, str(exc)[:70]))
            continue
        try:
            back = tf.get_editor_property(prop)
        except Exception as exc:
            back = "<%s>" % str(exc)[:40]
        log("    tick.%-26s set to %-6s readback=%s" % (prop, val, back))

for label, fn, verify in (
        ("set_component_tick_enabled(True)", lambda: comp.set_component_tick_enabled(True),
         lambda: comp.is_component_tick_enabled()),
        ("set_tickable_when_paused(True)", lambda: comp.set_tickable_when_paused(True),
         lambda: comp.is_tickable_when_paused()),
        ("activate(True)", lambda: comp.activate(True), None),
):
    try:
        fn()
    except Exception as exc:
        log("    %-34s SET FAILED: %s" % (label, str(exc)[:70]))
        continue
    if verify is None:
        log("    %-34s applied" % label)
    else:
        try:
            log("    %-34s applied -> readback %s" % (label, verify()))
        except Exception as exc:
            log("    %-34s applied, readback raised %s" % (label, str(exc)[:50]))

state("all levers applied")

# --- lever 5: a component born active, rather than one woken up afterwards
log("")
log("--- lever 5: spawn_system_at_location (a component active from birth) ---")
fresh = None
try:
    fresh = unreal.NiagaraFunctionLibrary.spawn_system_at_location(
        W, sysasset, unreal.Vector(ROW_X, 100.0, CAM.z))
    if fresh is None:
        log("    spawn_system_at_location returned None")
    else:
        state("fresh component")
except Exception as exc:
    log("    spawn_system_at_location raised: %s" % str(exc)[:120])


def snapshot(name):
    swcap.clear_rt(W, rt)
    try:
        cc.capture_scene()
    except Exception as exc:
        log("    capture_scene raised: %s" % str(exc)[:110])
    return name


ST = {"handle": None, "started": time.time(), "ticks": 0, "phase": "settle",
      "wait": SETTLE_TICKS, "errors": 0, "shots": [], "step": 0}


def _export(name):
    swcap.export_rt(W, rt, OUT_DIR, name)
    got = swimg.collect(OUT_DIR, name)
    st = swimg.png_stats(got) if got else None
    if st and st["mean_luma"] is not None:
        log("    %-22s luma=%.2f distinct=%s" % (name, st["mean_luma"],
                                                 st["distinct_rgb"]))
        ST["shots"].append((name, st["mean_luma"]))
    else:
        log("    %-22s NO FILE" % name)


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
    log("shot luma spread : %s" % (("%.2f" % (max(lums) - min(lums)))
                                   if len(lums) >= 2 else "n/a"))
    state("final")
    log("")
    log("If active=True and tick_enabled=True here but the shot spread is still")
    log("0.00, the component is running and the graph emits nothing. If the flags")
    log("are still False, the editor world refuses to tick this component and the")
    log("answer is Play-In-Editor, not more property poking.")
    log("P39 DONE")
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
                log("")
                log("--- 60 ticks later: did the levers STICK? ---")
                state("after 60 ticks")
                snapshot("_p39_a")
                st["wait"] = 2
                st["phase"] = "exp"
            return

        if st["phase"] == "exp":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            _export("_p39_after_tickfix")
            # one more try, everything on, then a short wait
            try:
                comp.set_component_tick_enabled(True)
                comp.set_tickable_when_paused(True)
                comp.activate(True)
            except Exception:
                pass
            if fresh is not None:
                try:
                    fresh.activate(True)
                except Exception:
                    pass
            st["wait"] = 8
            st["phase"] = "wait2"
            return

        if st["phase"] == "wait2":
            st["wait"] -= 1
            if st["wait"] <= 0:
                state("after second activate")
                snapshot("_p39_b")
                st["wait"] = 2
                st["phase"] = "exp2"
            return

        if st["phase"] == "exp2":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            _export("_p39_final")
            _finish("done")
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:160]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 20:
            _finish("too many tick errors")


log("")
ST["handle"] = unreal.register_slate_post_tick_callback(tick)
