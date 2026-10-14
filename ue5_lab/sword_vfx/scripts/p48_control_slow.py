"""
p48_control_slow.py - the same control, given long enough to be a control.

WHY p47 IS NOT ALLOWED TO STAND AS EVIDENCE
    p47 ran the right experiment and finished in 6.1 s. In that same project the
    engine log records

        LogNiagara: Compiling System ... took 6.7341 s   (x9, at level load)

    so a Niagara system needs about 6.7 s before it is ready to run, and p47
    activated the stock system, waited 20 ticks, read it, and concluded. Twenty
    ticks was about 2 s. The negative was taken BEFORE the compile it depends on
    could have finished.

    That is the exact failure p33 already made once - a single early frame read
    as "produced nothing" when it meant "produced nothing yet" - and it is worse
    here, because the answer it produces is the one that closes the whole line.
    p33's lesson: an A/B is only an instrument if both arms got to run.

WHAT CHANGED FOR THIS RUN
    1. a 90-tick warm-up after the assets are assigned, before anything is read
       or shot, so the compiles are done when the first frame is taken
    2. both subjects at the SAME location, only one visible at a time, and all
       three frames from the SAME camera pose - so a difference between frames
       can only be the subject, never the viewpoint
       (p47 moved the camera between the stock shot and the ours shot, which
       made its `ours` frame incomparable to the other two even though the
       numbers looked like a difference)
    3. after activation, another 30 ticks, and the state read AGAIN before the
       shot - so "asked to activate" and "is running" are two separate readings
    4. a final re-read 30 ticks after the last shot, to catch a late activation

THE THREE ARMS
    _p48_empty   both subjects hidden           - the pose on its own
    _p48_stock   /Niagara/.../FountainLightweight visible
    _p48_ours    NS_SW_Core_EdgeTrail visible

    Identical code path for stock and ours: same spawn call, same set_asset,
    same auto_activate, same activation, same camera, same wait.

OUTPUT
    render/pie/_p48_empty.png, _p48_stock.png, _p48_ours.png
    exports/p48_control_slow.txt

Usage:
    cd sword_vfx/scripts && UE_TIMEOUT=300 ./run_ue.sh p48_control_slow.py --render
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p48_control_slow.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/pie')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
SYS_DIR = "/Game/SEKAI/VFX/Sword/Systems"
STOCK = "/Niagara/DefaultAssets/Templates/Systems/FountainLightweight"
OURS = "NS_SW_Core_EdgeTrail"

WIDTH = 1280
HEIGHT = 720

# One subject position, one camera pose, for all three arms.
SUBJECT = unreal.Vector(900.0, -1200.0, 150.0)
CAM = unreal.Vector(1200.0, -1200.0, 150.0)
CAM_ROT = unreal.Rotator(pitch=0.0, yaw=180.0, roll=0.0)

WARM_TICKS = 90
RUN_TICKS = 30
BUDGET_SECONDS = 230.0

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
log("")
log("timing plan: %d ticks warm-up before the first read, then %d ticks after"
    % (WARM_TICKS, RUN_TICKS))
log("each activation. p47 used 20 and 6.1 s total, against a 6.7 s compile.")

ST = {"handle": None, "started": time.time(), "ticks": 0, "phase": "boot",
      "wait": 0, "errors": 0, "lums": {}, "notes": [], "ew": None, "ert": None,
      "ecc": None, "ecap": None, "stock": None, "ours": None,
      "stock_log": [], "ours_log": []}

WFX.install_watchdog(grace_seconds=BUDGET_SECONDS + 25.0)


def _call(holder, name):
    try:
        return getattr(getattr(unreal, holder)(), name)()
    except Exception:
        return None


def spawn_actor(cls, loc, rot, label):
    for how, fn in (
            ("EditorActorSubsystem",
             lambda: unreal.EditorActorSubsystem().spawn_actor_from_class(
                 cls, loc, rot)),
            ("EditorLevelLibrary",
             lambda: unreal.EditorLevelLibrary().spawn_actor_from_class(
                 cls, loc, rot)),
    ):
        try:
            a = fn()
            if a is None:
                continue
            try:
                a.set_actor_label(label)
            except Exception:
                pass
            return a, how
        except Exception as exc:
            log("    %s failed: %s" % (how, str(exc)[:80]))
    return None, None


def read_comp(comp):
    if comp is None:
        return {"missing": True}
    d = {}
    for name, fn in (("active", lambda: comp.is_active()),
                     ("tick", lambda: comp.is_component_tick_enabled()),
                     ("auto", lambda: comp.get_editor_property("auto_activate"))):
        try:
            d[name] = fn()
        except Exception as exc:
            d[name] = "<%s>" % str(exc)[:40]
    for name in ("get_asset", "get_fx_system_asset"):
        fn = getattr(comp, name, None)
        try:
            a = fn() if fn else None
            d[name] = (a.get_path_name().rsplit(".", 1)[-1]
                       if a is not None else None)
        except Exception as exc:
            d[name] = "<%s>" % str(exc)[:40]
    return d


def show(comp, on):
    """Only the scene-capture visibility matters here - that is the renderer
    the frames come from, and an actor can be visible in the world while still
    being excluded from a capture."""
    for name, val in (("set_hidden_in_scene_capture", not on),
                      ("set_visibility", on),
                      ("set_rendering_enabled", on)):
        fn = getattr(comp, name, None)
        if fn is None:
            continue
        try:
            fn(val)
        except Exception:
            pass


def shoot(name):
    swcap.clear_rt(ST["ew"], ST["ert"])
    try:
        ST["ecc"].capture_scene()
    except Exception as exc:
        log("    capture_scene raised: %s" % str(exc)[:100])


def export(name):
    swcap.export_rt(ST["ew"], ST["ert"], OUT_DIR, name)
    got = swimg.collect(OUT_DIR, name)
    st = swimg.png_stats(got) if got else None
    if st and st["mean_luma"] is not None:
        log("    %-14s luma=%.2f distinct=%s top=%s %.1f%%"
            % (name, st["mean_luma"], st["distinct_rgb"], st["top_rgb"],
               100.0 * st["top_rgb_frac"]))
        ST["lums"][name] = st["mean_luma"]
        return
    log("    %-14s NO FILE" % name)


def boot():
    loaded = False
    for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
        try:
            getattr(unreal, how)().load_level(LVL)
            log("level loaded via %s" % how)
            loaded = True
            break
        except Exception as exc:
            log("  %s failed: %s" % (how, str(exc)[:110]))
    if not loaded:
        ST["notes"].append("no level")
        return
    ST["ew"] = _call("UnrealEditorSubsystem", "get_editor_world") \
        or _call("EditorLevelLibrary", "get_editor_world")
    if ST["ew"] is None:
        ST["notes"].append("no editor world")
        return

    stock_asset = unreal.EditorAssetLibrary.load_asset(
        "%s.%s" % (STOCK, STOCK.rsplit("/", 1)[-1]))
    ours_asset = unreal.EditorAssetLibrary.load_asset(
        "%s/%s.%s" % (SYS_DIR, OURS, OURS))
    if stock_asset is None or ours_asset is None:
        ST["notes"].append("stock=%s ours=%s"
                           % (stock_asset is not None, ours_asset is not None))
        return

    log("")
    log("stock asset: %s" % stock_asset.get_path_name())
    log("ours  asset: %s" % ours_asset.get_path_name())
    log("")

    for tag, asset in (("stock", stock_asset), ("ours", ours_asset)):
        a, how = spawn_actor(unreal.NiagaraActor, SUBJECT, unreal.Rotator(),
                             "P48_%s" % tag.capitalize())
        if a is None:
            ST["notes"].append("could not spawn %s" % tag)
            continue
        comp = a.get_component_by_class(unreal.NiagaraComponent)
        try:
            comp.set_asset(asset)
            comp.set_editor_property("auto_activate", True)
        except Exception as exc:
            log("  %s set_asset raised: %s" % (tag, str(exc)[:100]))
        # The COMPONENT, not the actor: set_hidden_in_scene_capture is a
        # SceneComponent method, so hiding the actor would leave the emitter
        # fully visible to the capture and arm 1 would not be an empty frame.
        show(comp, False)
        ST[tag] = comp
        log("  %-6s spawned via %s at the shared subject position -> %s"
            % (tag, how, read_comp(comp)))

    ST["ert"] = swcap.make_rt(ST["ew"], WIDTH, HEIGHT)
    cap, how = spawn_actor(unreal.SceneCapture2D, CAM, CAM_ROT, "P48_Capture")
    if cap is None:
        ST["notes"].append("no capture")
        return
    try:
        cap.capture_component2d.set_editor_property("texture_target", ST["ert"])
        cap.capture_component2d.set_editor_property(
            "capture_source",
            getattr(unreal.SceneCaptureSource, "SCS_FINAL_COLOR_LDR", None))
        cap.capture_component2d.set_editor_property("capture_every_frame", False)
    except Exception as exc:
        log("  capture props: %s" % str(exc)[:90])
    ST["ecap"] = cap
    ST["ecc"] = cap.capture_component2d
    ok, why = swcap.place_capture(ST["ecc"], ST["ecap"], CAM, CAM_ROT,
                                  loc_tol=5.0, rot_tol=5.0)
    log("")
    log("  camera: placed=%s at (%.0f, %.0f, %.0f) %s"
        % (ok, CAM.x, CAM.y, CAM.z, str(why)[:50]))
    log("  SETTLING: turning off the editor viewport's own draw cost is not")
    log("  possible from here, so the warm-up is what makes the compile land")
    log("  before the first read. %d ticks." % WARM_TICKS)


def _finish(reason):
    if ST["phase"] == "done":
        return
    ST["phase"] = "done"
    log("")
    log("=" * 74)
    log("SUMMARY")
    log("=" * 74)
    log("stop reason : %s" % reason)
    log("notes       : %s" % ("; ".join(ST["notes"]) if ST["notes"] else "none"))
    log("elapsed     : %.1f s over %d ticks (%.1f ticks/s)"
        % (time.time() - ST["started"], ST["ticks"],
           ST["ticks"] / maxf(0.001, time.time() - ST["started"])))
    log("tick errors : %d" % ST["errors"])
    log("")
    log("stock timeline: %s" % " | ".join(ST["stock_log"]))
    log("ours  timeline: %s" % " | ".join(ST["ours_log"]))
    log("")
    e = ST["lums"].get("_p48_empty")
    s = ST["lums"].get("_p48_stock")
    o = ST["lums"].get("_p48_ours")
    log("luma  empty=%s  stock=%s  ours=%s" % (e, s, o))
    log("")
    sa = (ST.get("stock") is not None
          and read_comp(ST["stock"]).get("active") is True)
    oa = (ST.get("ours") is not None
          and read_comp(ST["ours"]).get("active") is True)
    log("final is_active: stock=%s ours=%s" % (sa, oa))
    log("")
    if e is None or s is None or o is None:
        log("=> A FRAME IS MISSING. No comparison is possible.")
    elif s == e and o == e:
        log("=> NEITHER SUBJECT ADDED A SINGLE PIXEL, with the camera, the code")
        log("   path and the wait identical, and 90 ticks of settling so the")
        log("   6.7 s compile was done first. A stock, never-edited engine")
        log("   system fails exactly as ours does.")
        log("   => The session cannot bring up a Niagara component. This is not")
        log("      a property of the nine assets and no rebuild can fix it.")
    elif s != e and o == e:
        log("=> THE STOCK SYSTEM DREW AND OURS DID NOT. The session is fine, so")
        log("   the nine assets are the defect and the fix is in the build.")
    elif s == e and o != e:
        log("=> OURS DREW AND THE STOCK DID NOT - read this as an asset result")
        log("   only if the stock arm is otherwise shown healthy; a stock engine")
        log("   template that draws nothing is a session result, not ours.")
    else:
        log("=> BOTH DREW. The components were never the problem, and the")
        log("   earlier 'nothing on screen' readings were camera or scale, not")
        log("   wiring.")
    log("P48 DONE")
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


def maxf(a, b):
    return a if a > b else b


def tick(delta):
    st = ST
    if st["phase"] == "done":
        return
    st["ticks"] += 1
    if time.time() - st["started"] > BUDGET_SECONDS:
        _finish("budget exhausted")
        return
    try:
        if st["phase"] == "boot":
            boot()
            st["wait"] = WARM_TICKS
            st["phase"] = "warm"
            return

        if st["phase"] == "warm":
            st["wait"] -= 1
            if st["wait"] % 30 == 0 and st["wait"] > 0:
                log("    warming: %d ticks left · stock=%s"
                    % (st["wait"], read_comp(st["stock"]).get("active")))
            if st["wait"] > 0:
                return
            log("")
            log("--- after the warm-up, before any activation ---")
            log("  stock -> %s" % read_comp(st["stock"]))
            log("  ours  -> %s" % read_comp(st["ours"]))
            log("")
            log("--- arm 1: EMPTY (both subjects hidden, camera fixed) ---")
            show(st["stock"], False)
            show(st["ours"], False)
            shoot("_p48_empty")
            st["wait"] = 2
            st["phase"] = "exp_empty"
            return

        if st["phase"] == "exp_empty":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            export("_p48_empty")
            log("")
            log("--- arm 2: STOCK visible, then activate it ---")
            show(st["stock"], True)
            if st["stock"] is not None:
                try:
                    st["stock"].activate(True)
                except Exception as exc:
                    log("    stock activate raised: %s" % str(exc)[:90])
                d = read_comp(st["stock"])
                st["stock_log"].append("after activate: active=%s tick=%s"
                                       % (d.get("active"), d.get("tick")))
                log("    stock -> %s" % d)
            st["wait"] = RUN_TICKS
            st["phase"] = "stock_run"
            return

        if st["phase"] == "stock_run":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            d = read_comp(st["stock"])
            st["stock_log"].append("+%d ticks: active=%s" % (RUN_TICKS,
                                                             d.get("active")))
            log("    stock after %d ticks -> %s" % (RUN_TICKS, d))
            shoot("_p48_stock")
            st["wait"] = 2
            st["phase"] = "exp_stock"
            return

        if st["phase"] == "exp_stock":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            export("_p48_stock")
            log("")
            log("--- arm 3: OURS visible, stock hidden, same camera ---")
            show(st["stock"], False)
            show(st["ours"], True)
            if st["ours"] is not None:
                try:
                    st["ours"].activate(True)
                except Exception as exc:
                    log("    ours activate raised: %s" % str(exc)[:90])
                d = read_comp(st["ours"])
                st["ours_log"].append("after activate: active=%s tick=%s"
                                      % (d.get("active"), d.get("tick")))
                log("    ours -> %s" % d)
            st["wait"] = RUN_TICKS
            st["phase"] = "ours_run"
            return

        if st["phase"] == "ours_run":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            d = read_comp(st["ours"])
            st["ours_log"].append("+%d ticks: active=%s" % (RUN_TICKS,
                                                            d.get("active")))
            log("    ours after %d ticks -> %s" % (RUN_TICKS, d))
            shoot("_p48_ours")
            st["wait"] = 2
            st["phase"] = "exp_ours"
            return

        if st["phase"] == "exp_ours":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            export("_p48_ours")
            log("")
            log("--- late check: another %d ticks, in case activation is slow ---"
                % RUN_TICKS)
            st["wait"] = RUN_TICKS
            st["phase"] = "late"
            return

        if st["phase"] == "late":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            log("  stock late -> %s" % read_comp(st["stock"]))
            log("  ours  late -> %s" % read_comp(st["ours"]))
            _finish("three arms taken with a full warm-up")
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:160]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 15:
            _finish("too many tick errors")


ST["handle"] = unreal.register_slate_post_tick_callback(tick)
