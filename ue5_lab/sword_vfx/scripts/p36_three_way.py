"""
p36_three_way.py - one camera, three frames, so the diff answers by itself.

WHY THREE AND NOT TWO
    p33's gallery pairs were identical and p35's probe row was either empty or
    full of a 50 m plane, depending on a scale value I got wrong. Both times the
    frame was ambiguous because I could not tell "nothing is there" from "there
    is something there and I framed it wrong".

    So this holds the camera still and changes ONE thing at a time:

        _p36_empty     the scene, nothing of mine in it   <- the baseline
        _p36_objects   + a WorldGrid quad, an MI quad, and a Niagara actor
        _p36_active    + the Niagara system reactivated

    Now the two diffs are each a single question:
        objects vs empty   are the MESH and MATERIAL visible at all?
        active  vs objects does the NIAGARA system add anything?

    Neither answer can be confused with a framing mistake, because the camera
    never moves and the baseline is the same scene without the objects.

THE ROW IS BUILT TO BE READ
    Camera at the origin looking along +X at 2 m, level, 90 degree FOV - the
    same rig shape p21 uses, which is known to render this level. At 2 m a 90
    degree frustum is 4 m wide, so three objects at y = -2, 0, +2 m land at the
    left third, centre and right third, each a metre across: a quarter of the
    frame apiece. Nothing is allowed to be scale=100 this time - a 1 m sheet
    blown up 100x is a 50 m wall and it hides the frame, which is what happened
    to the previous version.

    Each generated sheet is rotated pitch=+90 so its +Z normal points at -X,
    square on to the camera. They are zero-thickness sheets; left flat they are
    edge-on and one pixel wide.

OUTPUT
    render/threeway/_p36_{empty,objects,active}.png
    exports/p36_threeway.txt

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p36_three_way.py --render
    then: tools/frame_pairs.py render/threeway --base _p36_empty
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p36_threeway.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/threeway')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
ROOT = "/Game/SEKAI/VFX/Sword"
GRID = "/Engine/EngineMaterials/WorldGridMaterial"

WIDTH = 1280
HEIGHT = 720

CAM = unreal.Vector(0.0, 0.0, 100.0)
CAM_YAW = 0.0            # +X
ROW_X = 200.0            # 2 m
SHEET_PITCH = 90.0

SHOTS = ("_p36_empty", "_p36_objects", "_p36_active")
SETTLE_TICKS = 120
OBJECT_SETTLE = 15
BURST_TICKS = 25
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


# ------------------------------------------------------------------ camera
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
cr = cap.get_actor_rotation()
log("")
log("camera placed=%s via %s" % (ok, why))
log("    readback loc=(%.0f, %.0f, %.0f) roll=%.0f pitch=%.0f yaw=%.0f"
    % (cl.x, cl.y, cl.z, cr.roll, cr.pitch, cr.yaw))
log("    looking along +X at 2 m; the row spans y = -2 m .. +2 m")

PLACED = {}


def _spawn_row():
    """WorldGrid quad | MI quad | Niagara, at y = -200, 0, +200 cm."""
    rot = unreal.Rotator(pitch=SHEET_PITCH, yaw=CAM_YAW, roll=0.0)
    specs = (
        ("grid", "mesh", "%s/Meshes/SM_SW_GlintQuad" % ROOT, GRID, -200.0),
        ("mi", "mesh", "%s/Meshes/SM_SW_GlintQuad" % ROOT,
         "%s/Materials/MI_SW_Glint_Normal" % ROOT, 0.0),
        ("niagara", "niagara", "%s/Systems/NS_SW_Core_Glint" % ROOT, None, 200.0),
    )
    for tag, kind, asset_path, mat_path, dy in specs:
        loc = unreal.Vector(ROW_X, CAM.y + dy, CAM.z)
        asset = load(asset_path)
        if asset is None:
            log("    %-8s ASSET MISSING %s" % (tag, asset_path))
            continue
        if kind == "mesh":
            a = unreal.EditorLevelLibrary.spawn_actor_from_class(
                unreal.StaticMeshActor, loc, rot)
            if a is None:
                log("    %-8s SPAWN FAILED" % tag)
                continue
            smc = a.static_mesh_component
            try:
                smc.set_mobility(unreal.ComponentMobility.MOVABLE)
            except Exception:
                pass
            try:
                smc.set_static_mesh(asset)
            except Exception as exc:
                log("    %-8s set_static_mesh: %s" % (tag, str(exc)[:110]))
            mat = load(mat_path)
            if mat is None:
                log("    %-8s MATERIAL MISSING %s" % (tag, mat_path))
            else:
                try:
                    smc.set_material(0, mat)
                except Exception as exc:
                    log("    %-8s set_material: %s" % (tag, str(exc)[:110]))
            try:
                bl = a.get_actor_location()
                br = a.get_actor_rotation()
                log("    %-8s quad at (%.0f, %.0f, %.0f) roll=%.0f pitch=%.0f"
                    "  mat=%s" % (tag, bl.x, bl.y, bl.z, br.roll, br.pitch,
                                  mat_path.rsplit("/", 1)[-1] if mat_path else "-"))
            except Exception as exc:
                log("    %-8s readback failed: %s" % (tag, str(exc)[:110]))
        else:
            a = unreal.EditorLevelLibrary.spawn_actor_from_class(
                unreal.NiagaraActor, loc, rot)
            if a is None:
                log("    %-8s SPAWN FAILED" % tag)
                continue
            comp = a.get_component_by_class(unreal.NiagaraComponent)
            if comp is None:
                log("    %-8s NO COMPONENT" % tag)
                continue
            try:
                comp.set_asset(asset)
                comp.set_editor_property("auto_activate", True)
            except Exception as exc:
                log("    %-8s set_asset: %s" % (tag, str(exc)[:110]))
            try:
                bl = a.get_actor_location()
                log("    %-8s Niagara at (%.0f, %.0f, %.0f)"
                    % (tag, bl.x, bl.y, bl.z))
            except Exception:
                pass
        PLACED[tag] = a


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
        log("    %-16s NO FILE" % name)
        return
    st = swimg.png_stats(got)
    if st and st["mean_luma"] is not None:
        log("    %-16s luma=%.2f distinct=%s top=%s %.1f%%"
            % (name, st["mean_luma"], st["distinct_rgb"],
               st["top_rgb"], 100.0 * st["top_rgb_frac"]))
    else:
        log("    %-16s unreadable" % name)


def _activate():
    a = PLACED.get("niagara")
    if a is None:
        log("    no niagara actor - 'active' would equal 'objects'")
        return
    comp = a.get_component_by_class(unreal.NiagaraComponent)
    for how, fn in (("activate(True)", lambda: comp.activate(True)),
                    ("reactivate()", lambda: comp.reactivate())):
        try:
            fn()
            log("    niagara reactivate via %s" % how)
            return
        except Exception:
            continue
    log("    niagara reactivate FAILED")


ST = {"handle": None, "started": time.time(), "ticks": 0, "phase": "settle",
      "wait": SETTLE_TICKS, "errors": 0, "i": 0}


def _finish(reason):
    if ST["phase"] == "done":
        return
    ST["phase"] = "done"
    log("")
    log("--- summary ---")
    log("stop reason : %s" % reason)
    log("elapsed     : %.1f s over %d ticks"
        % (time.time() - ST["started"], ST["ticks"]))
    log("tick errors : %d" % ST["errors"])
    log("")
    log("frames in %s :" % OUT_DIR)
    for f in sorted(os.listdir(OUT_DIR)):
        p = os.path.join(OUT_DIR, f)
        st = swimg.png_stats(p)
        if st and st["mean_luma"] is not None:
            log("    %-24s luma=%.2f distinct=%s" % (f, st["mean_luma"],
                                                      st["distinct_rgb"]))
    log("")
    log("NEXT: the two diffs, not the three frames.")
    log("    tools/frame_pairs.py render/threeway   # needs the pairing below")
    log("  empty -> objects : are the mesh and material visible at all?")
    log("  objects -> active: does the Niagara system add anything?")
    log("P36 DONE")
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
                log("--- shot 1/3: empty scene (baseline) ---")
                _capture()
                st["wait"] = 2
                st["phase"] = "exp_empty"
            return

        if st["phase"] == "exp_empty":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            _export(SHOTS[0])
            log("")
            log("--- placing the row ---")
            _spawn_row()
            st["wait"] = OBJECT_SETTLE
            st["phase"] = "settle_obj"
            return

        if st["phase"] == "settle_obj":
            st["wait"] -= 1
            if st["wait"] <= 0:
                log("")
                log("--- shot 2/3: objects placed, niagara not forced ---")
                _capture()
                st["wait"] = 2
                st["phase"] = "exp_obj"
            return

        if st["phase"] == "exp_obj":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            _export(SHOTS[1])
            log("")
            log("--- reactivating the niagara system ---")
            _activate()
            st["wait"] = BURST_TICKS
            st["phase"] = "wait_burst"
            return

        if st["phase"] == "wait_burst":
            st["wait"] -= 1
            if st["wait"] <= 0:
                log("")
                log("--- shot 3/3: immediately after the reactivate ---")
                _capture()
                st["wait"] = 2
                st["phase"] = "exp_active"
            return

        if st["phase"] == "exp_active":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            _export(SHOTS[2])
            _finish("three frames exported")
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:160]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 20:
            _finish("too many tick errors")


log("")
log("--- settle %d ticks ---" % SETTLE_TICKS)
ST["handle"] = unreal.register_slate_post_tick_callback(tick)
