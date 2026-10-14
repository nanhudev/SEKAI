"""P61b - per-variant isolation probe: one variant visible per frame.

    v0  SM_SW_GlintQuad + MID(MI_SW_Glint_Normal), Opacity=1   <- p60's path
    v1  /Engine/BasicShapes/Cube + MID(MI_SW_Glint_Normal)     <- UV test
    v2  SM_SW_GlintQuad + raw MI (no MID)                      <- MID test
    v3  SM_SW_GlintQuad + MID(M_SW_Glint parent), no MaskTex   <- expect INVISIBLE
    v4  SM_SW_ScarStrip + MID(MI_SW_SpatialScar_Normal)        <- translucent path
    v5  SM_SW_GlintQuad + M_Lab_Dummy (lit, known good)        <- sanity
    v6  SM_SW_GlintQuad + MID(MI_SW_Trail_Normal)              <- trail (translucent)

Frames: render/probe61/vN.png   (one variant centred per frame)
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swcap  # noqa: E402
import swimg  # noqa: E402
import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p61_probe.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/probe61')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
ROOT = "/Game/SEKAI/VFX/Sword"
WIDTH, HEIGHT = 1280, 720
SETTLE_TICKS = 60

WFX.bind_log(EXPORT)
log = WFX.log
os.makedirs(OUT_DIR, exist_ok=True)
for _f in os.listdir(OUT_DIR):
    try:
        os.remove(os.path.join(OUT_DIR, _f))
    except Exception:
        pass
MEL = unreal.MaterialEditingLibrary


def V(x, y, z):
    return unreal.Vector(x * 100.0, y * 100.0, z * 100.0)


def R(pitch, yaw, roll=0.0):
    return unreal.Rotator(pitch=pitch, yaw=yaw, roll=roll)


def look_rot(frm, to):
    import math
    d = (to[0] - frm[0], to[1] - frm[1], to[2] - frm[2])
    h = max(math.hypot(d[0], d[1]), 1e-6)
    return R(math.degrees(math.atan2(d[2], h)),
             math.degrees(math.atan2(d[1], d[0])), 0.0)


log("P61B VFX PROBE - engine=%s"
    % unreal.SystemLibrary.get_engine_version())

for _h in ("LevelEditorSubsystem", "EditorLevelLibrary"):
    try:
        getattr(unreal, _h)().load_level(LVL)
        log("level loaded via %s" % _h)
        break
    except Exception as exc:
        log("  %s failed: %s" % (_h, str(exc)[:100]))
W = None
for _h in ("UnrealEditorSubsystem", "EditorLevelLibrary"):
    try:
        W = getattr(unreal, _h)().get_editor_world()
        if W is not None:
            break
    except Exception:
        W = None

need = {
    "quad": ROOT + "/Meshes/SM_SW_GlintQuad",
    "scar": ROOT + "/Meshes/SM_SW_ScarStrip",
    "cube": "/Engine/BasicShapes/Cube",
    "mi_glint_n": ROOT + "/Materials/MI_SW_Glint_Normal",
    "mi_scar_n": ROOT + "/Materials/MI_SW_SpatialScar_Normal",
    "mi_trail_n": ROOT + "/Materials/MI_SW_Trail_Normal",
    "m_glint": ROOT + "/Materials/M_SW_Glint",
    "lab_dummy": ROOT + "/Lab/Materials/M_Lab_Dummy",
    "tex_streak": ROOT + "/Textures/T_SW_Streak",
}
ASSETS = {}
for k, p in need.items():
    _full = p if "." in p.rsplit("/", 1)[-1] else "%s.%s" % (
        p, p.rsplit("/", 1)[-1])
    ASSETS[k] = unreal.EditorAssetLibrary.load_asset(_full)
    if ASSETS[k] is None:
        log("  LOAD FAILED: %s (%s)" % (k, p))

mi_glint = ASSETS["mi_glint_n"]
if mi_glint is not None:
    try:
        t = MEL.get_material_instance_texture_parameter_value(mi_glint,
                                                              "MaskTex")
        log("  MI MaskTex readback: %s" % (t.get_name() if t else "NONE"))
    except Exception as exc:
        log("  MI MaskTex readback failed: %s" % str(exc)[:100])

# ---- one actor per variant, all parked at the same spot (only one visible
# at a time), camera fixed -------------------------------------------
AX, AY, AZ = 0.0, 14.0, 1.15


def make_variant(label, mesh, mat, from_mi):
    a = unreal.EditorLevelLibrary.spawn_actor_from_object(
        mesh, V(AX, AY, AZ), R(-90.0, 0.0))
    a.set_actor_label("P61B_%s" % label)
    smc = a.static_mesh_component
    smc.set_mobility(unreal.ComponentMobility.MOVABLE)
    if mat is not None:
        if from_mi:
            mid = smc.create_dynamic_material_instance(0, mat)
            if mid is not None:
                mid.set_scalar_parameter_value("Opacity", 1.0)
                mid.set_scalar_parameter_value("Intensity", 2.0)
            log("  %s MID=%s" % (label, mid))
        else:
            smc.set_material(0, mat)
            log("  %s raw material set" % label)
    smc.set_visibility(False)
    return a


variants = []
variants.append(make_variant("v0_quad_MID", ASSETS["quad"],
                             ASSETS["mi_glint_n"], True))
_c = make_variant("v1_cube_MID", ASSETS["cube"], ASSETS["mi_glint_n"], True)
_c.set_actor_scale3d(unreal.Vector(0.6, 0.6, 0.6))
variants.append(_c)
variants.append(make_variant("v2_quad_MIraw", ASSETS["quad"],
                             ASSETS["mi_glint_n"], False))
variants.append(make_variant("v3_quad_PARENTMID", ASSETS["quad"],
                             ASSETS["m_glint"], True))
variants.append(make_variant("v4_scar_MID", ASSETS["scar"],
                             ASSETS["mi_scar_n"], True))
variants.append(make_variant("v5_quad_LIT", ASSETS["quad"],
                             ASSETS["lab_dummy"], False))
variants.append(make_variant("v6_trail_MID", ASSETS["quad"],
                             ASSETS["mi_trail_n"], True))
log("variants built: %d" % len(variants))

rt = swcap.make_rt(W, WIDTH, HEIGHT)
CAP = unreal.EditorLevelLibrary.spawn_actor_from_class(
    unreal.SceneCapture2D, V(AX, AY - 2.6, AZ + 0.05), R(0, 0))
cc = CAP.capture_component2d
swcap.set_prop(cc, "texture_target", rt)
_v = getattr(unreal.SceneCaptureSource, "SCS_FINAL_COLOR_LDR", None)
if _v is not None:
    swcap.set_prop(cc, "capture_source", _v)
swcap.set_prop(cc, "capture_every_frame", False)
swcap.set_prop(cc, "fov_angle", 60.0)
swcap.place_capture(cc, CAP, V(AX, AY - 2.6, AZ + 0.05),
                    look_rot((AX, AY - 2.6, AZ + 0.05), (AX, AY, AZ)))
log("camera placed")

ST = {"phase": "settle", "wait": SETTLE_TICKS, "ticks": 0,
      "handle": None, "started": time.time(), "idx": -1,
      "sub": 0}


def _finish(reason):
    if ST.get("finished"):
        return
    ST["finished"] = True
    log("")
    log("--- summary ---")
    log("stop reason : %s" % reason)
    log("elapsed     : %.1f s over %d ticks"
        % (time.time() - ST["started"], ST["ticks"]))
    log("output      : %s" % OUT_DIR)
    log("P61B PROBE DONE")
    try:
        if ST["handle"] is not None:
            unreal.unregister_slate_post_tick_callback(ST["handle"])
    except Exception:
        pass
    unreal.SystemLibrary.quit_editor()


def tick(_dt=0.0):
    ST["ticks"] += 1
    try:
        if ST.get("finished"):
            return
        if ST["phase"] == "settle":
            ST["wait"] -= 1
            if ST["wait"] <= 0:
                ST["phase"] = "show"
                ST["idx"] = 0
                ST["sub"] = 0
                log("--- settle done ---")
            return
        if ST["phase"] == "show":
            if ST["sub"] == 0:
                for i, a in enumerate(variants):
                    a.static_mesh_component.set_visibility(i == ST["idx"])
                cc.capture_scene()
            ST["sub"] += 1
            if ST["sub"] == 3:
                name = "v%d" % ST["idx"]
                unreal.RenderingLibrary.export_render_target(
                    W, rt, OUT_DIR, name)
                got = swimg.collect(OUT_DIR, name)
                log("captured %s -> %s" % (name, got))
                ST["idx"] += 1
                ST["sub"] = 0
                if ST["idx"] >= len(variants):
                    _finish("all variants captured")
            return
    except Exception as exc:
        import traceback
        log("TICK ERROR: %s" % str(exc)[:200])
        log(traceback.format_exc()[-600:])
        _finish("tick error")


ST["handle"] = unreal.register_slate_post_tick_callback(tick)
