"""
p33_particle_frames.py - do the nine systems actually RUN? (section 35, second half)

THE QUESTION
    p32 asks the engine whether the nine graphs COMPILE. Section 35's
    IMPLEMENTED needs both halves: "the Niagara graph really exists AND RUNS".
    A compile state is a statement about the graph. Whether particles come out
    is a statement about a FRAME.

WHY EVERY SHOT IS AN A/B PAIR  (and why a single frame would have lied)
    Five of the nine emitters use SpawnBurst_Instantaneous:
        E_Slice, E_Wave, E_Scar, E_Arc, E_Hit
    and three more use a rate parameter that is ZERO in the Normal profile:
        E_MistWake (User.MistRate = 0), E_ScarMist / E_ArcMist (User.MistCount = 0)

    A burst fires once, on activation - and the component activates when the
    LEVEL LOADS. With User.Lifetime = 0.25 s, every burst particle is long dead
    before a camera reaches it. Photographing the gallery as-loaded would show
    nothing for those emitters, and "nothing" is exactly what a broken graph
    looks like. The two cases are indistinguishable in a single frame.

    So each system is shot TWICE from the same camera:
        _before   as-loaded (no forced activation)
        _after    immediately after activate(reset=True)
    The pair is the measurement. If the two frames are identical, the system
    produced nothing; if they differ, something on screen is its output and the
    location of the difference is where it landed.

    The mist emitters are expected to be a no-op pair in the Normal profile -
    that is the profile doing its job, not a defect - and the report says so
    rather than counting them as failures.

ONE CAPTURE PER TICK
    The capture reads the back buffer, so it must run after the frame is drawn.
    Capture and export are separated by two ticks for the same reason.

WHERE THE CAMERA GOES
    Three metres in front of each gallery actor on -X, level with it. The
    gallery stands at x = 900 cm spread along Y, so this frames one system.

OUTPUT
    render/particles/_p33_<Actor>_{before,after}.png
    exports/p33_particles.txt

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p33_particle_frames.py --render
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p33_particles.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/particles')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"

WIDTH = 1280
HEIGHT = 720

# Emitters whose spawn parameter is zero in the Normal profile. Named here so
# the report can distinguish "produced nothing because the profile says so"
# from "produced nothing because the graph is broken".
MIST_SYSTEMS = ("NS_SW_Core_MistWake",)

SETTLE_TICKS = 120
SETTLE_SHOT = 8
BURST_TICKS = 25
TAIL_TICKS = 6
BUDGET_SECONDS = 900.0

WFX.bind_log(EXPORT)
log = WFX.log

os.makedirs(OUT_DIR, exist_ok=True)
for _f in os.listdir(OUT_DIR):
    try:
        os.remove(os.path.join(OUT_DIR, _f))
    except Exception:
        pass

log("engine: %s" % unreal.SystemLibrary.get_engine_version())
log("")

loaded = False
for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
    try:
        getattr(unreal, how)().load_level(LVL)
        log("level loaded via %s" % how)
        loaded = True
        break
    except Exception as exc:
        log("  %s failed: %s" % (how, str(exc)[:140]))
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
    log("ABORT: no editor world")
    raise SystemExit(0)

# ------------------------------------------------------------------ targets
TARGETS = {}
for a in unreal.EditorLevelLibrary.get_all_level_actors() or []:
    try:
        if not isinstance(a, unreal.NiagaraActor):
            continue
        comp = a.get_component_by_class(unreal.NiagaraComponent)
        if comp is None:
            continue
        asset = comp.get_editor_property("asset")
        if asset is None:
            continue
        name = asset.get_path_name().split(".")[-1]
        TARGETS[a.get_actor_label()] = {"actor": a, "comp": comp, "name": name,
                                        "loc": a.get_actor_location()}
    except Exception:
        continue

log("")
log("--- %d Niagara actors in the level ---" % len(TARGETS))
for label in sorted(TARGETS):
    L = TARGETS[label]["loc"]
    log("    %-30s (%7.1f, %7.1f, %7.1f)  %s"
        % (label, L.x, L.y, L.z, TARGETS[label]["name"]))

if not TARGETS:
    log("ABORT: no Niagara actors to photograph")
    raise SystemExit(0)

# ------------------------------------------------------------------ capture
rt = swcap.make_rt(W, WIDTH, HEIGHT)
if rt is None:
    log("ABORT: no render target")
    raise SystemExit(0)

cap = unreal.EditorLevelLibrary.spawn_actor_from_class(
    unreal.SceneCapture2D, unreal.Vector(0, 0, 0),
    unreal.Rotator(pitch=0.0, yaw=0.0, roll=0.0))
if cap is None:
    log("ABORT: no SceneCapture2D")
    raise SystemExit(0)

cc = cap.capture_component2d
try:
    cc.set_editor_property("texture_target", rt)
except Exception as exc:
    log("    texture_target failed: %s" % str(exc)[:140])
v = getattr(unreal.SceneCaptureSource, "SCS_FINAL_COLOR_LDR", None)
if v is not None:
    try:
        cc.set_editor_property("capture_source", v)
        log("    capture_source = SCS_FINAL_COLOR_LDR")
    except Exception as exc:
        log("    capture_source failed: %s" % str(exc)[:140])
try:
    cc.set_editor_property("capture_every_frame", False)
except Exception:
    pass

# ------------------------------------------------------------------ task list
#
# A flat queue rather than a hand-written phase machine: the sequence per system
# is five steps long and there are nine systems, and spelling that out as named
# phases is how the last version lost track of which step it was on.
TASKS = []
ORDER = sorted(TARGETS)
for label in ORDER:
    t = TARGETS[label]
    L = t["loc"]
    TASKS.append(("move", {"loc": unreal.Vector(L.x + 300.0, L.y, L.z),
                           "rot": unreal.Rotator(pitch=0.0, yaw=180.0, roll=0.0)}))
    TASKS.append(("wait", SETTLE_SHOT))
    TASKS.append(("shot", "%s_before" % label))
    TASKS.append(("reactivate", label))
    TASKS.append(("wait", BURST_TICKS))
    TASKS.append(("shot", "%s_after" % label))
    TASKS.append(("wait", TAIL_TICKS))

ST = {
    "handle": None, "started": time.time(), "ticks": 0,
    "phase": "settle", "wait": SETTLE_TICKS,
    "cur": None, "sub": 0, "results": [], "errors": 0, "npending": None,
}


def _note(name, verdict, detail):
    ST["results"].append({"name": name, "verdict": verdict, "detail": detail})


def _finish(reason):
    if ST["phase"] == "done":
        return
    ST["phase"] = "done"
    el = time.time() - ST["started"]
    log("")
    log("--- summary ---")
    log("stop reason      : %s" % reason)
    log("elapsed          : %.1f s over %d ticks" % (el, ST["ticks"]))
    log("frames exported  : %d" % len(ST["results"]))
    log("tick-loop errors : %d" % ST["errors"])
    log("")
    for r in ST["results"]:
        log("    %-46s %-10s %s" % (r["name"], r["verdict"], r["detail"]))
    log("")
    log("NOTE: this script does not compare the A/B pairs - a difference needs")
    log("      pixel arithmetic, not string reading. Run the host-side differ:")
    log("          tools/frame_pairs.py render/particles")
    log("      Equal pairs = the system produced nothing after a forced")
    log("      reactivate. Unequal pairs = it ran, and the bounding box of the")
    log("      difference says where.")
    log("")
    log("      The mist emitters (E_ScarMist / E_ArcMist / E_MistWake) have")
    log("      User.MistCount / User.MistRate = 0 in the Normal profile ON")
    log("      PURPOSE. An equal pair for those is the profile working.")
    log("P33 DONE")
    try:
        if ST["handle"] is not None:
            unreal.unregister_slate_post_tick_callback(ST["handle"])
    except Exception:
        pass
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception as exc:
        log("quit_editor failed: %s" % str(exc)[:120])


def _reactivate(comp):
    for how, fn in (
            ("activate(True)", lambda: comp.activate(True)),
            ("reactivate()", lambda: comp.reactivate()),
            ("activate()", lambda: comp.activate()),
    ):
        try:
            fn()
            return how
        except Exception:
            continue
    return None


def _do_shot(n):
    """clear -> capture. The export happens two ticks later."""
    swcap.clear_rt(W, rt)
    try:
        cc.capture_scene()
    except Exception as exc:
        _note(n, "CAPTURE-FAIL", str(exc)[:90])
        return False
    return True


def _do_export(n):
    swcap.export_rt(W, rt, OUT_DIR, n)
    path = swimg.collect(OUT_DIR, n)
    if not path:
        _note(n, "NO-FILE", "export produced nothing")
        return
    stats = swimg.png_stats(path)
    if stats is None or stats["mean_luma"] is None:
        _note(n, "UNREADABLE", path)
        return
    _note(n, "OK", "luma=%.2f distinct=%s top=%s %.1f%%"
          % (stats["mean_luma"], stats["distinct_rgb"], stats["top_rgb"],
             100.0 * stats["top_rgb_frac"]))


def tick(delta):
    st = ST
    if st["phase"] == "done":
        return
    st["ticks"] += 1

    if time.time() - st["started"] > BUDGET_SECONDS:
        _finish("wall-clock budget of %.0fs exhausted" % BUDGET_SECONDS)
        return

    try:
        if st["phase"] == "settle":
            st["wait"] -= 1
            if st["wait"] <= 0:
                log("")
                log("--- settle done (%d ticks). %d tasks queued ---"
                    % (st["ticks"], len(TASKS)))
                st["phase"] = "run"
            return

        if st["phase"] == "wait":
            st["wait"] -= 1
            if st["wait"] <= 0:
                st["phase"] = "run"
            return

        if st["phase"] == "shot_export":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            _do_export(st["cur"])
            st["phase"] = "run"
            return

        if st["phase"] != "run":
            return

        # ---- pull the next task
        if not TASKS:
            _finish("all tasks complete")
            return
        kind, arg = TASKS.pop(0)

        if kind == "move":
            ok, why = swcap.place_capture(cc, cap, arg["loc"], arg["rot"],
                                          loc_tol=5.0, rot_tol=5.0)
            if not ok:
                log("!! camera move failed: %s" % why)
                st["errors"] += 1
            return

        if kind == "wait":
            st["wait"] = int(arg)
            st["phase"] = "wait"
            return

        if kind == "reactivate":
            how = _reactivate(TARGETS[arg]["comp"])
            log("    reactivate %-30s -> %s" % (arg, how))
            if how is None:
                # Without this the _after frame is a copy of _before and the
                # pair proves nothing, so it is an ERROR, not a warning.
                st["errors"] += 1
                log("        !! reactivate FAILED - the _after frame will be a")
                log("           copy of _before whatever the graph's health is")
            return

        if kind == "shot":
            st["cur"] = arg
            if not _do_shot(arg):
                return
            st["wait"] = 2
            st["phase"] = "shot_export"
            return

    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:160]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 30:
            _finish("too many tick errors")


log("")
log("--- %d tasks, %d systems ---" % (len(TASKS), len(TARGETS)))
ST["handle"] = unreal.register_slate_post_tick_callback(tick)
