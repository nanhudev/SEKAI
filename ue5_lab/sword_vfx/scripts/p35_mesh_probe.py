"""
p35_mesh_probe.py - put the VFX meshes and materials in a frame, next to a Niagara system.

THE SPLIT THIS MAKES
    p33 measured 0 differing pixels across all nine A/B pairs. That leaves three
    different diagnoses which a frame of the gallery cannot separate:

        (a) the MESHES are the wrong size          -> nothing to see, even bound
        (b) the MATERIALS render as nothing        -> geometry there, invisible
        (c) the NIAGARA systems produce no particles

    A gallery shot confounds all three because every one of them looks like
    "a picture of the level". So this puts them side by side in ONE frame, at a
    known distance from a known camera:

        y -200   SM_SW_GlintQuad + WorldGridMaterial   scale 1     baseline
        y -100   SM_SW_GlintQuad + WorldGridMaterial   scale 100   size probe
        y    0   NiagaraActor  NS_SW_Core_Glint                     the system
        y +100   SM_SW_GlintQuad + MI_SW_Glint_Normal  scale 1
        y +200   SM_SW_GlintQuad + MI_SW_Glint_Normal  scale 100

    Reading it:
        baseline visible                          -> the mesh has geometry and a
                                                     sane size
        baseline invisible, size probe visible    -> the mesh is 100x too small,
                                                     same bug class as the
                                                     review dummies
        WorldGrid visible, MI invisible           -> the material is the problem
        everything static visible, Niagara blank  -> the particles never spawn

    WorldGridMaterial is UE's own default opaque checker - it is the control
    because nothing about it is ours to get wrong.

OUTPUT
    render/meshprobe/_p35_before.png   (as loaded)
    render/meshprobe/_p35_after.png    (immediately after activating the system)
    exports/p35_meshprobe.txt

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p35_mesh_probe.py --render
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p35_meshprobe.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/meshprobe')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"

ROOT = "/Game/SEKAI/VFX/Sword"
GRID = "/Engine/EngineMaterials/WorldGridMaterial"

WIDTH = 1280
HEIGHT = 720

# STANDING THE SHEETS UP, AND STANDING LEVEL.
#
# Every generated VFX mesh reports box extent z == 0: they are flat sheets in
# the XY plane with their normal along +Z. Two earlier shots of this row came
# back blank - first level (edge on: zero pixels wide), then looking down 55
# degrees, which should have worked but did not, and a blank frame cannot say
# why. Both readings were about the shot, not about the meshes.
#
# So the ambiguity is removed at the source: each sheet is rotated pitch=+90,
# which turns its +Z normal to -X, i.e. square on to a camera looking along +X.
# Level camera, level row, faces towards the lens. There is nothing left for
# the framing to hide behind.
CAM = unreal.Vector(0.0, 1500.0, 100.0)
CAM_PITCH = 0.0
CAM_YAW = 0.0
DIST_X = 300.0
SHEET_PITCH = 90.0       # +Z normal -> -X normal, facing the camera

LAYOUT = (
    ("cube", "mesh", "/Engine/BasicShapes/Cube", GRID, 100.0, -300.0),
    ("grid_x1", "mesh", "SM_SW_GlintQuad", GRID, 1.0, -200.0),
    ("grid_x100", "mesh", "SM_SW_GlintQuad", GRID, 100.0, -100.0),
    ("niagara", "niagara", "NS_SW_Core_Glint", None, 1.0, 0.0),
    ("mi_x1", "mesh", "SM_SW_GlintQuad",
     "%s/Materials/MI_SW_Glint_Normal" % ROOT, 1.0, 100.0),
    ("mi_x100", "mesh", "SM_SW_GlintQuad",
     "%s/Materials/MI_SW_Glint_Normal" % ROOT, 100.0, 200.0),
)

SETTLE_TICKS = 120
BURST_TICKS = 25
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
    p = path if "." in path.rsplit("/", 1)[-1] else "%s.%s" % (path, path.rsplit("/", 1)[-1])
    try:
        return unreal.EditorAssetLibrary.load_asset(p)
    except Exception as exc:
        log("    load %s failed: %s" % (path, str(exc)[:120]))
        return None


# ------------------------------------------------------------------ build
log("")
log("--- building the probe row 3 m in front of the camera ---")
PLACED = {}
for tag, kind, asset_name, mat_path, scale, dy in LAYOUT:
    loc = unreal.Vector(CAM.x + DIST_X, CAM.y + dy, CAM.z)
    rot = unreal.Rotator(pitch=SHEET_PITCH, yaw=CAM_YAW, roll=0.0)
    if kind == "mesh":
        mpath = asset_name if asset_name.startswith("/") else (
            "%s/Meshes/%s" % (ROOT, asset_name))
        mesh = load(mpath)
        if mesh is None:
            log("    %-10s MESH MISSING (%s)" % (tag, mpath))
            continue
        a = unreal.EditorLevelLibrary.spawn_actor_from_class(
            unreal.StaticMeshActor, loc, rot)
        if a is None:
            log("    %-10s SPAWN FAILED" % tag)
            continue
        smc = a.static_mesh_component
        try:
            smc.set_mobility(unreal.ComponentMobility.MOVABLE)
        except Exception as exc:
            log("    %-10s mobility: %s" % (tag, str(exc)[:80]))
        try:
            smc.set_static_mesh(mesh)
        except Exception as exc:
            log("    %-10s set_static_mesh: %s" % (tag, str(exc)[:120]))
        mat = load(mat_path)
        if mat is None:
            log("    %-10s MATERIAL MISSING (%s)" % (tag, mat_path))
        else:
            try:
                smc.set_material(0, mat)
            except Exception as exc:
                log("    %-10s set_material: %s" % (tag, str(exc)[:120]))
        try:
            a.set_actor_scale3d(unreal.Vector(scale, scale, scale))
        except Exception as exc:
            log("    %-10s set scale: %s" % (tag, str(exc)[:120]))
        PLACED[tag] = a
        log("    %-10s StaticMeshActor %-20s mat=%-30s scale=%g at dy=%+.0f"
            % (tag, asset_name, (mat_path or "").rsplit("/", 1)[-1], scale, dy))
        # READ BACK. A spawn or a setter that returns without applying leaves
        # the row empty, and every conclusion drawn from the frame is then
        # about an empty row. This project has paid for that more than once.
        try:
            bl = a.get_actor_location()
            br = a.get_actor_rotation()
            bs = smc.get_editor_property("static_mesh")
            log("        readback: loc=(%.0f, %.0f, %.0f)"
                "  roll=%.0f pitch=%.0f yaw=%.0f  mesh=%s"
                % (bl.x, bl.y, bl.z, br.roll, br.pitch, br.yaw,
                   bs.get_path_name() if bs else "None"))
        except Exception as exc:
            log("        readback FAILED: %s" % str(exc)[:110])
        try:
            b = mesh.get_bounds().box_extent
            log("        mesh bounds extent=(%.1f, %.1f, %.1f) cm"
                % (b.x, b.y, b.z))
        except Exception as exc:
            log("        bounds unreadable: %s" % str(exc)[:110])
    else:
        sysasset = load("%s/Systems/%s" % (ROOT, asset_name))
        if sysasset is None:
            log("    %-10s SYSTEM MISSING" % tag)
            continue
        a = unreal.EditorLevelLibrary.spawn_actor_from_class(
            unreal.NiagaraActor, loc, rot)
        if a is None:
            log("    %-10s SPAWN FAILED" % tag)
            continue
        comp = a.get_component_by_class(unreal.NiagaraComponent)
        if comp is None:
            log("    %-10s NO COMPONENT" % tag)
            continue
        try:
            comp.set_asset(sysasset)
            comp.set_editor_property("auto_activate", True)
        except Exception as exc:
            log("    %-10s set_asset: %s" % (tag, str(exc)[:120]))
        PLACED[tag] = a
        log("    %-10s NiagaraActor  %-20s at dy=%+.0f" % (tag, asset_name, dy))

# ------------------------------------------------------------------ capture
rt = swcap.make_rt(W, WIDTH, HEIGHT)
CAP_ROT = unreal.Rotator(pitch=CAM_PITCH, yaw=CAM_YAW, roll=0.0)
cap = unreal.EditorLevelLibrary.spawn_actor_from_class(
    unreal.SceneCapture2D, CAM, CAP_ROT)
cc = cap.capture_component2d
try:
    cc.set_editor_property("texture_target", rt)
except Exception as exc:
    log("    texture_target: %s" % str(exc)[:120])
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
try:
    cc.set_editor_property("fov_angle", 90.0)
except Exception:
    pass

ok, why = swcap.place_capture(cc, cap, CAM, CAP_ROT, loc_tol=5.0, rot_tol=5.0)
log("")
log("camera placed: %s (%s)" % (ok, why))
# READ THE CAMERA BACK TOO. "placed: True" only means the setter raised nothing
# and the readback agreed with the target - it does not print what the target
# WAS, and a wrong yaw looks exactly like a broken row.
try:
    cl = cap.get_actor_location()
    cr = cap.get_actor_rotation()
    log("    camera READBACK: loc=(%.0f, %.0f, %.0f)"
        "  roll=%.0f pitch=%.0f yaw=%.0f"
        % (cl.x, cl.y, cl.z, cr.roll, cr.pitch, cr.yaw))
    log("    UE yaw 0 = +X, so this looks along +X - towards the bright wall")
    log("    at x=+2000. The row sits 3 m down that axis.")
except Exception as exc:
    log("    camera readback FAILED: %s" % str(exc)[:110])

# ------------------------------------------------------------------ state
ST = {"handle": None, "started": time.time(), "ticks": 0,
      "phase": "settle", "wait": SETTLE_TICKS, "errors": 0, "step": 0}


def _finish(reason):
    if ST["phase"] == "done":
        return
    ST["phase"] = "done"
    log("")
    log("--- summary ---")
    log("stop reason     : %s" % reason)
    log("elapsed         : %.1f s over %d ticks" % (time.time() - ST["started"],
                                                    ST["ticks"]))
    log("tick errors     : %d" % ST["errors"])
    log("")
    log("frames in %s :" % OUT_DIR)
    for f in sorted(os.listdir(OUT_DIR)):
        p = os.path.join(OUT_DIR, f)
        st = swimg.png_stats(p)
        if st and st["mean_luma"] is not None:
            log("    %-26s luma=%.2f distinct=%s" % (f, st["mean_luma"],
                                                      st["distinct_rgb"]))
        else:
            log("    %-26s <unreadable>" % f)
    log("")
    log("READ IT AS A ROW (dy -300 .. +200):")
    log("    cube  grid_x1  grid_x100  niagara  mi_x1  mi_x100")
    log("  * cube is the control. If the cube does not show, the shot is")
    log("    broken and nothing else in the frame means anything.")
    log("  * grid_x1 visible -> the mesh has sane geometry, so a blank Niagara")
    log("    frame is about particles, not meshes.")
    log("  * grid_x1 blank but grid_x100 visible -> the mesh is 100x too small.")
    log("  * grid_x1 and mi_x1 both visible -> the material is fine too, and the")
    log("    particles are simply not being produced.")
    log("P35 DONE")
    try:
        if ST["handle"] is not None:
            unreal.unregister_slate_post_tick_callback(ST["handle"])
    except Exception:
        pass
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception as exc:
        log("quit_editor failed: %s" % str(exc)[:120])


def _capture():
    swcap.clear_rt(W, rt)
    try:
        cc.capture_scene()
    except Exception as exc:
        log("    capture_scene raised: %s" % str(exc)[:120])


def _activate_niagara():
    """Activate ONLY. Capturing before this call is what makes the pair
    meaningful - a capture taken after activation has the burst in both frames
    and the comparison says nothing."""
    act = PLACED.get("niagara")
    if act is None:
        log("    no niagara actor placed - the pair will match by design")
        return
    comp = act.get_component_by_class(unreal.NiagaraComponent)
    for how, fn in (("activate(True)", lambda: comp.activate(True)),
                    ("reactivate()", lambda: comp.reactivate())):
        try:
            fn()
            log("    niagara reactivate: %s" % how)
            return
        except Exception:
            continue
    log("    niagara reactivate FAILED - the pair cannot be trusted")


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
                log("--- settle done. shot 1: as loaded ---")
                _capture()
                st["wait"] = 2
                st["phase"] = "exp_before"
            return

        if st["phase"] == "exp_before":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            swcap.export_rt(W, rt, OUT_DIR, "_p35_before")
            got = swimg.collect(OUT_DIR, "_p35_before")
            log("    exported _p35_before -> %s"
                % (os.path.basename(got) if got else "NO FILE"))
            # activate now, with the "before" frame already on disk
            _activate_niagara()
            st["wait"] = BURST_TICKS
            st["phase"] = "wait_burst"
            return

        if st["phase"] == "wait_burst":
            st["wait"] -= 1
            if st["wait"] <= 0:
                log("    shot 2: after the forced reactivate")
                _capture()
                st["wait"] = 2
                st["phase"] = "exp_after"
            return

        if st["phase"] == "exp_after":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            swcap.export_rt(W, rt, OUT_DIR, "_p35_after")
            got = swimg.collect(OUT_DIR, "_p35_after")
            log("    exported _p35_after  -> %s"
                % (os.path.basename(got) if got else "NO FILE"))
            _finish("both frames exported")
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:160]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 20:
            _finish("too many tick errors")


log("")
log("--- %d objects placed, settle %d ticks ---" % (len(PLACED), SETTLE_TICKS))
ST["handle"] = unreal.register_slate_post_tick_callback(tick)
