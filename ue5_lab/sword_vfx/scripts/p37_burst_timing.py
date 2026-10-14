"""
p37_burst_timing.py - the particles may have been alive all along; I was late.

WHAT p36 PROVED
    empty -> objects   : 85320 px changed. The mesh and the material RENDER.
    objects -> active  : 0 px changed, after activate(reset=True) + 25 ticks.

    So the geometry and the materials are fine and the Niagara step added
    nothing. But look at what the emitter actually does:

        E_Glint    SpawnBurst   Spawn Count = 1
                   Init         Lifetime = User.Lifetime = 0.25 s

    ONE particle, alive for a QUARTER OF A SECOND. And p36 measured its own
    tick rate at 26 ticks/s, so the 25-tick wait between "activate" and
    "shutter" was 0.96 s - nearly four lifetimes. Every frame I have taken of a
    burst emitter was taken after the burst was dead.

    That is not a guess about the emitters; it is arithmetic on two numbers I
    measured. It also explains why p33's nine pairs were perfectly identical:
    identical because both frames were empty.

THE EXPERIMENT
    Hold the camera still and take a TIME SERIES, not a pair:

        _p37_pre     before activation
        _p37_t01     1 tick after   (~0.04 s)
        _p37_t03     3 ticks after  (~0.12 s)
        _p37_t10     10 ticks after (~0.38 s)
        _p37_t40     40 ticks after (~1.5 s)

    and to take the timing question off the table entirely, User.Lifetime is
    set to 5 s and User.Intensity to 5 before activating - if the system can
    emit at all, five seconds of lifetime cannot be missed by a shutter that
    fires within one second.

    A known-visible quad (GlintQuad + MI_SW_Glint_Normal, which p36 measured as
    85320 changed pixels) sits in the same frame as a reference, so a blank
    frame can never be mistaken for a broken shot.

    E_Glint is the system under test because a sprite renderer is a billboard:
    it has no orientation to get wrong. The mesh renderers do - their sheets lie
    in the XY plane - and they are deliberately NOT part of this question.

OUTPUT
    render/burst/_p37_*.png
    exports/p37_burst.txt

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p37_burst_timing.py --render
    then: tools/frame_pairs.py render/burst --names _p37_pre,_p37_t01,...
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p37_burst.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/burst')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
ROOT = "/Game/SEKAI/VFX/Sword"

WIDTH = 1280
HEIGHT = 720

CAM = unreal.Vector(0.0, 0.0, 100.0)
CAM_YAW = 0.0
ROW_X = 200.0
SHEET_PITCH = 90.0

# (label, ticks after activation) -- the last two also re-check that what the
# early frames show is still there once the nominal lifetime would have expired.
PLAN = (("_p37_pre", None), ("_p37_t01", 1), ("_p37_t03", 3),
        ("_p37_t10", 10), ("_p37_t40", 40))

LIFETIME_OVERRIDE = 5.0
INTENSITY_OVERRIDE = 5.0

SETTLE_TICKS = 120
BUDGET_SECONDS = 600.0

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
except Exception as exc:
    log("texture_target: %s" % str(exc)[:120])
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

ok, why = swcap.place_capture(cc, cap, CAM, CAP_ROT, loc_tol=5.0, rot_tol=5.0)
cl = cap.get_actor_location()
log("")
log("camera placed=%s (%s) loc=(%.0f, %.0f, %.0f)"
    % (ok, why, cl.x, cl.y, cl.z))

# ------------------------------------------------------------------ the row
log("")
log("--- building the row (2 m ahead, along +X) ---")

# reference quad: p36 measured this exact combination as visible
ref = None
qmesh = load("%s/Meshes/SM_SW_GlintQuad" % ROOT)
qmat = load("%s/Materials/MI_SW_Glint_Normal" % ROOT)
if qmesh and qmat:
    ref = unreal.EditorLevelLibrary.spawn_actor_from_class(
        unreal.StaticMeshActor, unreal.Vector(ROW_X, -150.0, CAM.z),
        unreal.Rotator(pitch=SHEET_PITCH, yaw=CAM_YAW, roll=0.0))
    if ref is not None:
        smc = ref.static_mesh_component
        try:
            smc.set_mobility(unreal.ComponentMobility.MOVABLE)
            smc.set_static_mesh(qmesh)
            smc.set_material(0, qmat)
        except Exception as exc:
            log("    reference quad setup: %s" % str(exc)[:110])
        log("    reference quad at y=-150 (GlintQuad + MI_SW_Glint_Normal)")

# system under test
sysasset = load("%s/Systems/NS_SW_Core_Glint" % ROOT)
nact = None
comp = None
if sysasset is not None:
    nact = unreal.EditorLevelLibrary.spawn_actor_from_class(
        unreal.NiagaraActor, unreal.Vector(ROW_X, 150.0, CAM.z),
        unreal.Rotator(pitch=0.0, yaw=CAM_YAW, roll=0.0))
    if nact is not None:
        comp = nact.get_component_by_class(unreal.NiagaraComponent)
        if comp is not None:
            try:
                comp.set_asset(sysasset)
            except Exception as exc:
                log("    set_asset: %s" % str(exc)[:110])
        log("    Niagara NS_SW_Core_Glint at y=+150")
if comp is None:
    log("ABORT: could not place the system under test")
    raise SystemExit(0)

# read what the component thinks it is, before touching anything
for prop in ("auto_activate", "asset", "is_active"):
    try:
        if prop == "is_active":
            log("    comp.is_active()      = %s" % comp.is_active())
        else:
            log("    comp.%s = %s" % (prop, comp.get_editor_property(prop)))
    except Exception as exc:
        log("    comp.%s <raised %s>" % (prop, str(exc)[:70]))

# ------------------------------------------------------------------ overrides
#
# Raising Lifetime to 5 s is the whole point: it takes "did I shoot too late"
# off the table. If the system emits at all, a 5-second particle cannot be
# missed by a shutter firing inside one second.
log("")
log("--- User parameter overrides ---")
SET_RESULTS = {}
for name, val in (("User.Lifetime", LIFETIME_OVERRIDE),
                  ("User.Intensity", INTENSITY_OVERRIDE)):
    done = False
    for setter in ("set_float_parameter", "setFloatParameter"):
        try:
            getattr(comp, setter)(name, float(val))
            done = True
            break
        except Exception as exc:
            last = str(exc)[:90]
    back = None
    for getter in ("get_float_parameter", "getFloatParameter"):
        try:
            back = getattr(comp, getter)(name)
            break
        except Exception:
            continue
    SET_RESULTS[name] = back
    log("    %-18s -> %.3f   readback=%s   %s"
        % (name, val, back, "ok" if done else "SETTER FAILED: " + str(last)[:60]))
if all(v is None for v in SET_RESULTS.values()):
    log("    BOTH readbacks are None. The override may not have applied, in which")
    log("    case Lifetime is still 0.25 s and only the first shots can show it.")
else:
    log("    readback is the number that matters: it is the value the component")
    log("    will actually evaluate, not the value I passed.")

ST = {"handle": None, "started": time.time(), "ticks": 0, "phase": "settle",
      "wait": SETTLE_TICKS, "i": 0, "errors": 0, "t_act": 0, "results": []}


def _capture():
    swcap.clear_rt(W, rt)
    try:
        cc.capture_scene()
    except Exception as exc:
        log("    capture_scene raised: %s" % str(exc)[:120])


def _export(name):
    swcap.export_rt(W, rt, OUT_DIR, name)
    got = swimg.collect(OUT_DIR, name)
    if not got:
        log("    %-12s NO FILE" % name)
        ST["results"].append((name, None))
        return
    st = swimg.png_stats(got)
    if st and st["mean_luma"] is not None:
        dt = (ST["ticks"] - ST["t_act"]) if ST["t_act"] else -1
        log("    %-12s luma=%.2f distinct=%s   (+%d ticks after activate)"
            % (name, st["mean_luma"], st["distinct_rgb"], dt))
        ST["results"].append((name, st["mean_luma"]))
    else:
        log("    %-12s unreadable" % name)
        ST["results"].append((name, None))


def _activate():
    for how, fn in (("activate(True)", lambda: comp.activate(True)),
                    ("reactivate()", lambda: comp.reactivate())):
        try:
            fn()
            log("    niagara reactivate via %s" % how)
            return True
        except Exception:
            continue
    log("    niagara reactivate FAILED")
    return False


def _finish(reason):
    if ST["phase"] == "done":
        return
    ST["phase"] = "done"
    log("")
    log("--- summary ---")
    log("stop reason : %s" % reason)
    log("elapsed     : %.1f s over %d ticks (%.1f ticks/s)"
        % (time.time() - ST["started"], ST["ticks"],
           ST["ticks"] / max(0.01, time.time() - ST["started"])))
    log("tick errors : %d" % ST["errors"])
    log("")
    lums = [l for _, l in ST["results"] if l is not None]
    if len(lums) >= 2:
        spread = max(lums) - min(lums)
        log("luma spread across the series: %.2f" % spread)
        if spread < 0.5:
            log("  ALL FRAMES MATCH. With Lifetime forced to %.1f s, a system that"
                % LIFETIME_OVERRIDE)
            log("  emits at all cannot be missed - so this system produced no")
            log("  visible particles in any of these frames.")
        else:
            log("  THE FRAMES DIFFER, so particles appeared and then left. Compare")
            log("  the per-shot luma above with the tick offsets to read the")
            log("  emitter's real lifetime off the data.")
    log("")
    log("NEXT: tools/frame_pairs.py render/burst --names " + ",".join(
        n for n, _ in ST["results"]))
    log("P37 DONE")
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
                log("--- shot 1: BEFORE activation ---")
                _capture()
                st["wait"] = 2
                st["phase"] = "exp"
            return

        if st["phase"] == "exp":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            _export(PLAN[st["i"]][0])
            st["i"] += 1
            if st["i"] >= len(PLAN):
                _finish("all shots taken")
                return
            label, ticks = PLAN[st["i"]]
            if ticks is None:
                st["phase"] = "settle"
                st["wait"] = 2
                return
            if st["t_act"] == 0:
                log("")
                log("--- activating; the next shots are timed off this tick ---")
                _activate()
                st["t_act"] = st["ticks"]
                st["wait"] = ticks
            else:
                st["wait"] = ticks - (st["ticks"] - st["t_act"])
            st["phase"] = "gap"
            return

        if st["phase"] == "gap":
            st["wait"] -= 1
            if st["wait"] <= 0:
                log("")
                log("--- shot: target +%d ticks ---" % PLAN[st["i"]][1])
                _capture()
                st["wait"] = 2
                st["phase"] = "exp"
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:160]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 20:
            _finish("too many tick errors")


log("")
log("--- %d shots planned, settle %d ticks ---" % (len(PLAN), SETTLE_TICKS))
ST["handle"] = unreal.register_slate_post_tick_callback(tick)
