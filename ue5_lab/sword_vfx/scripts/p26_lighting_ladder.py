"""SEKAI Sword VFX - P26: the lab has no light. Make it have light.

WHAT P25 PROVED

    P25 varied `capture_source` on a capture whose placement had been verified
    two ways (actor readback AND component readback both at TP34, forward
    (0.968, -0.238, -0.075), ring dummies 2.8-5.5 m in front). Result:

        SCS_BASE_COLOR    IMAGE   mean luma 35.70, 5 colours
        SCS_NORMAL        IMAGE   top (0,0,255) 50.1%  <- up-facing ground
        SCS_SCENE_DEPTH   IMAGE
        SCS_SCENE_COLOR_HDR   BLACK
        SCS_FINAL_COLOR_LDR   BLACK
          ... with post_process_blend_weight=0   still BLACK
          ... with PRM_RENDER_SCENE_PRIMITIVES   still BLACK
          ... with an exposure override          still BLACK
          ... pointed straight up at the sky     still BLACK

    Albedo renders. Normals render - and their top colour is pure blue, which
    is the ground plane's +Z normal. Geometry and materials are unambiguously in
    front of the capture.

    But the scene colour AFTER LIGHTING is black, and no post-process or
    exposure setting changes that, because those stages are downstream of a
    black input. So the answer is not "the capture is broken" and not "the
    tonemap is broken". It is:

        THE LAB HAS NO EFFECTIVE LIGHT.

    Which also means section 30's premise - a bright wall, a dark wall, all VFX
    holding up on a bright background - is currently unmet. Nothing about the
    review map means what it says until this is fixed.

THE PRIME SUSPECT, AND WHY IT IS MECHANICAL RATHER THAN MYSTICAL

    An unbuilt Static or Stationary light contributes nothing to a render pass.
    The editor viewport hides that from a human by substituting preview
    lighting, which a SceneCapture2D does not get. So "someone would have
    noticed" is not true here.

    P20 spawned the sun and the sky light and then set their mobility with

        MAT.set_prop(sun.light_component, "mobility", ComponentMobility.MOVABLE)

    `set_prop` swallows failures and P20 never read the value back - the same
    shape as every other bug in this project: a setter that returns, no
    readback, and a build report that says it worked. If that call did not take,
    the lights are still Static, the level has no built lighting, and the scene
    captures black while rendering albedo and normals perfectly.

    That is a hypothesis. This script does not assume it - it reads every
    light's mobility back first, then tries the fixes one rung at a time, each
    measured with SCS_SCENE_COLOR_HDR.

WHY SCS_SCENE_COLOR_HDR IS THE INSTRUMENT

    It is the lit scene colour before tonemap. Nothing downstream can fake it:
    it is non-black if and only if light is reaching the surface. Every rung
    below is judged on whether that source stops being black.

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p26_lighting_ladder.py --render
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swcap  # noqa: E402
import swimg  # noqa: E402
import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p26_lighting.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/lighting')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
RT_W, RT_H = 512, 512
WAIT = 5
GREEN_RGB = (0, 255, 0)
LINES = []


def log(msg=""):
    msg = str(msg)
    LINES.append(msg)
    print(msg)
    with open(EXPORT, "a", encoding="utf-8") as fh:
        fh.write(msg + "\n")


open(EXPORT, "w", encoding="utf-8").close()
WFX.bind_log(EXPORT, truncate=False)
WFX.install_watchdog(400)


def abort(msg):
    log("")
    log("    ABORTING: %s" % msg)
    log("P26 ABORTED")
    print("P26 ABORTED")
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception:
        pass
    raise SystemExit(0)


def subsystems():
    out = []
    for cls in ("LevelEditorSubsystem", "EditorActorSubsystem",
                "EditorLevelLibrary"):
        try:
            out.append((cls, unreal.get_editor_subsystem(getattr(unreal, cls))))
        except Exception:
            pass
    for cls in ("LevelEditorSubsystem", "EditorLevelLibrary",
                "EditorActorSubsystem"):
        try:
            out.append((cls, getattr(unreal, cls)()))
        except Exception:
            pass
    return out


def all_actors():
    raw = []
    for label, obj in subsystems():
        if not hasattr(obj, "get_all_level_actors"):
            continue
        try:
            raw = obj.get_all_level_actors()
            break
        except Exception:
            continue
    seen, out = set(), []
    for a in raw:
        try:
            key = a.get_path_name()
        except Exception:
            key = id(a)
        if key in seen:
            continue
        seen.add(key)
        out.append(a)
    return out


# --------------------------------------------------------------------------
# boot
# --------------------------------------------------------------------------
log("engine: " + unreal.SystemLibrary.get_engine_version())
_nullrhi = False
try:
    _nullrhi = "-nullrhi" in str(unreal.SystemLibrary.get_command_line())
except Exception:
    pass
if _nullrhi:
    abort("this probe needs a rasterizer; use --render")
log("rasterizer: available")

for label, obj in subsystems():
    if not hasattr(obj, "load_level"):
        continue
    try:
        obj.load_level(LVL)
        log("level loaded via %s" % label)
        break
    except Exception as exc:
        log("load_level via %s failed: %s" % (label, str(exc)[:110]))

W = None
try:
    W = unreal.get_editor_subsystem(
        unreal.UnrealEditorSubsystem).get_editor_world()
except Exception:
    pass
if W is None:
    for how in ("EditorLevelLibrary",):
        try:
            W = getattr(unreal, how)().get_editor_world()
            break
        except Exception:
            continue
if W is None:
    abort("no editor world")
os.makedirs(OUT_DIR, exist_ok=True)

ACTORS = all_actors()
log("level actors: %d" % len(ACTORS))

# --------------------------------------------------------------------------
# FACTS: every light, read back. This is the hypothesis test, and it is free.
# --------------------------------------------------------------------------
log("")
log("--- every light in the level, read back ---")
LIGHTS = []
for a in ACTORS:
    try:
        cls = a.get_class().get_name()
    except Exception:
        continue
    if "Light" not in cls:
        continue
    try:
        label = a.get_actor_label()
    except Exception:
        label = "?"
    entry = {"actor": a, "label": label, "class": cls}
    comp = None
    for attr in ("light_component", "sky_light_component", "component"):
        try:
            comp = getattr(a, attr)
            break
        except Exception:
            continue
    entry["comp"] = comp
    bits = []
    if comp is not None:
        for p in ("mobility", "intensity", "intensity_units", "visible",
                  "affects_world", "real_time_capture", "source_type",
                  "cast_shadows", "cast_dynamic_shadows"):
            ok, val = swcap.get_prop(comp, p)
            if ok:
                bits.append("%s=%s" % (p, val))
    entry["state"] = bits
    log("    %-18s %-20s %s" % (label, cls, "  ".join(bits) if bits
                               else "(no readable component properties)"))
    LIGHTS.append(entry)

if not LIGHTS:
    log("    !! THERE IS NO LIGHT ACTOR IN THIS LEVEL AT ALL.")
    log("       That, on its own, would fully explain P25.")

# WorldSettings, for the force-dynamic-lighting switch.
WS = None
for a in ACTORS:
    try:
        if "WorldSettings" in a.get_class().get_name():
            WS = a
            break
    except Exception:
        continue
if WS is not None:
    ok, val = swcap.get_prop(WS, "force_no_precomputed_lighting")
    log("    WorldSettings.force_no_precomputed_lighting = %s"
        % (val if ok else "unreadable"))
else:
    log("    WorldSettings: not found in the actor list")

# --------------------------------------------------------------------------
# capture
# --------------------------------------------------------------------------
cam_actor, cam_loc, cam_rot = None, None, None
for a in ACTORS:
    try:
        if a.get_actor_label() == "Review_TP34":
            cam_actor = a
            cam_loc, cam_rot = a.get_actor_location(), a.get_actor_rotation()
            break
    except Exception:
        continue
if cam_actor is None:
    abort("Review_TP34 is not in the level")

rt = swcap.make_rt(W, RT_W, RT_H)
if rt is None:
    abort("could not create a render target")
cap = None
for label, obj in subsystems():
    if not hasattr(obj, "spawn_actor_from_class"):
        continue
    try:
        cap = obj.spawn_actor_from_class(unreal.SceneCapture2D,
                                         unreal.Vector(0, 0, 200),
                                         unreal.Rotator(0, 0, 0))
        break
    except Exception:
        continue
if cap is None:
    abort("could not spawn a SceneCapture2D")
cc = None
for attr in ("capture_component2d", "capture_component"):
    try:
        cc = getattr(cap, attr)
        break
    except Exception:
        continue
if cc is None:
    abort("no capture component")

swcap.set_prop(cc, "texture_target", rt)
swcap.set_prop(cc, "capture_every_frame", False)
swcap.set_prop(cc, "capture_source",
               getattr(unreal.SceneCaptureSource, "SCS_SCENE_COLOR_HDR"))
ok, why = swcap.place_capture(cc, cap, cam_loc, cam_rot)
log("")
log("capture at TP34: %s (%s)" % (ok, why))
if not ok:
    abort("the capture will not go where the shot is")
log("capture_source: %s" % swcap.get_prop(cc, "capture_source")[1])

# Discard the very first clear: MEASURED in P24/P25 that the first
# clear_render_target2d after creating the target does not take, so the first
# reading of the run shows the target's construction-time content instead.
swcap.clear_rt(W, rt)

MEASURED = {"n": 0}


def measure(note="after"):
    MEASURED["n"] += 1
    name = "_p26_%02d" % MEASURED["n"]
    swcap.export_rt(W, rt, OUT_DIR, name)
    path = swimg.collect(OUT_DIR, name)
    if not path:
        log("        %-7s NO FILE" % note)
        return "?"
    st = swimg.png_stats(path)
    if st is None or st["mean_luma"] is None:
        log("        %-7s unreadable" % note)
        return "?"
    top = st["top_rgb"] or (0, 0, 0)
    frac = st["top_rgb_frac"] or 0.0
    green = (abs(top[0] - GREEN_RGB[0]) <= 12
             and abs(top[1] - GREEN_RGB[1]) <= 12
             and abs(top[2] - GREEN_RGB[2]) <= 12 and frac >= 0.75)
    if green:
        verdict = "GREEN"
    elif (st["distinct_rgb"] or 0) <= 3 and (st["mean_luma"] or 0) < 2.0:
        verdict = "BLACK"
    else:
        verdict = "LIT"
    log("        %-7s %-5s top=%-14s %5.1f%%  mean_luma=%-7.2f distinct_rgb=%s"
        % (note, verdict, str(top), 100.0 * frac, st["mean_luma"],
           st["distinct_rgb"]))
    return verdict


def shoot():
    swcap.clear_rt(W, rt)
    try:
        cc.capture_scene()
    except Exception as exc:
        return "capture FAILED: %s" % str(exc)[:90]
    return "captured"


def source(name):
    val = getattr(unreal.SceneCaptureSource, name, None)
    if val is None:
        return "%s DOES NOT EXIST" % name
    swcap.set_prop(cc, "capture_source", val)
    return "source=%s" % name


# --- the fixes, each individually measured ------------------------------
def fix_force_dynamic():
    if WS is None:
        return "no WorldSettings actor to set"
    ok = swcap.set_prop(WS, "force_no_precomputed_lighting", True)
    got = swcap.get_prop(WS, "force_no_precomputed_lighting")[1]
    return "force_no_precomputed_lighting = True (set=%s readback=%s)" % (ok, got)


def fix_mobility_movable():
    notes = []
    val = getattr(unreal.ComponentMobility, "MOVABLE", None)
    for e in LIGHTS:
        comp = e["comp"]
        if comp is None:
            continue
        ok = swcap.set_prop(comp, "mobility", val)
        got = swcap.get_prop(comp, "mobility")[1]
        notes.append("%s: set=%s readback=%s" % (e["label"], ok, got))
    return "; ".join(notes) if notes else "no light components"


def fix_sun_bright():
    notes = []
    for e in LIGHTS:
        if "DirectionalLight" not in e["class"]:
            continue
        comp = e["comp"]
        units = getattr(unreal.LightUnits, "LUX", None)
        if units is not None:
            swcap.set_prop(comp, "intensity_units", units)
        # A daylight-scale value. The point of this rung is to make "is it
        # zero or is it merely dim" unambiguous, so it goes far past plausible.
        ok = swcap.set_prop(comp, "intensity", 100000.0)
        notes.append("%s: intensity set=%s readback=%s units=%s"
                     % (e["label"], ok,
                        swcap.get_prop(comp, "intensity")[1],
                        swcap.get_prop(comp, "intensity_units")[1]))
    return "; ".join(notes) if notes else "no directional light found"


def fix_skylight_realtime():
    notes = []
    for e in LIGHTS:
        if "SkyLight" not in e["class"]:
            continue
        comp = e["comp"]
        rtc = swcap.set_prop(comp, "real_time_capture", True)
        swcap.set_prop(comp, "intensity", 5.0)
        # A Static sky light with no captured cubemap contributes nothing; ask
        # for a recapture explicitly as well, in case real-time is unsupported.
        recap = ""
        for meth in ("recapture_sky", "set_cubemap"):
            fn = getattr(comp, meth, None)
            if fn is None:
                continue
            try:
                fn()
                recap = "%s() ok" % meth
                break
            except Exception as exc:
                recap = "%s() failed: %s" % (meth, str(exc)[:50])
        notes.append("%s: real_time_capture set=%s readback=%s intensity=%s %s"
                     % (e["label"], rtc,
                        swcap.get_prop(comp, "real_time_capture")[1],
                        swcap.get_prop(comp, "intensity")[1], recap))
    return "; ".join(notes) if notes else "no sky light found"


FRESH = {"sun": None, "sky": None}


def fix_add_fresh_sun():
    """A brand-new Movable sun. Separates "this actor is misconfigured" from
    "no light works in this world at all"."""
    for label, obj in subsystems():
        if not hasattr(obj, "spawn_actor_from_class"):
            continue
        try:
            a = obj.spawn_actor_from_class(unreal.DirectionalLight,
                                           unreal.Vector(0, 0, 900),
                                           unreal.Rotator(0.0, -55.0, 20.0))
            comp = a.light_component
            units = getattr(unreal.LightUnits, "LUX", None)
            if units is not None:
                swcap.set_prop(comp, "intensity_units", units)
            swcap.set_prop(comp, "intensity", 100000.0)
            swcap.set_prop(comp, "mobility",
                           getattr(unreal.ComponentMobility, "MOVABLE", None))
            FRESH["sun"] = a
            return ("spawned P26_FreshSun: mobility=%s intensity=%s units=%s"
                    % (swcap.get_prop(comp, "mobility")[1],
                       swcap.get_prop(comp, "intensity")[1],
                       swcap.get_prop(comp, "intensity_units")[1]))
        except Exception as exc:
            continue
    return "could not spawn a fresh directional light"


def fix_add_fresh_skylight():
    for label, obj in subsystems():
        if not hasattr(obj, "spawn_actor_from_class"):
            continue
        try:
            a = obj.spawn_actor_from_class(unreal.SkyLight,
                                           unreal.Vector(0, 0, 500),
                                           unreal.Rotator(0, 0, 0))
            comp = a.light_component
            swcap.set_prop(comp, "mobility",
                           getattr(unreal.ComponentMobility, "MOVABLE", None))
            swcap.set_prop(comp, "real_time_capture", True)
            swcap.set_prop(comp, "intensity", 5.0)
            FRESH["sky"] = a
            return ("spawned P26_FreshSky: mobility=%s real_time=%s intensity=%s"
                    % (swcap.get_prop(comp, "mobility")[1],
                       swcap.get_prop(comp, "real_time_capture")[1],
                       swcap.get_prop(comp, "intensity")[1]))
        except Exception as exc:
            continue
    return "could not spawn a fresh sky light"


def pre_source_hdr(extra=None):
    def pre():
        log("        " + source("SCS_SCENE_COLOR_HDR"))
        if extra:
            log("        " + extra())
        log("        " + shoot())
    return pre


def pre_final(extra=None):
    def pre():
        log("        " + source("SCS_FINAL_COLOR_LDR"))
        if extra:
            log("        " + extra())
        log("        " + shoot())
    return pre


def _pre_sky():
    """Defined BEFORE PLAN: a function referenced inside a dict literal has to
    exist when the literal is evaluated, and py_compile does not catch this."""
    rot = unreal.Rotator(0.0, 70.0, cam_rot.yaw)
    ok, why = swcap.place_capture(cc, cap, cam_loc, rot)
    log("        turned up: %s (%s)" % (ok, why))
    log("        " + source("SCS_FINAL_COLOR_LDR"))
    log("        " + shoot())


PLAN = [
    {"label": "reproduce P25: SCENE_COLOR_HDR, no change",
     "pre": pre_source_hdr(), "post": measure},
    {"label": "WorldSettings.force_no_precomputed_lighting = True",
     "pre": pre_source_hdr(fix_force_dynamic), "post": measure},
    {"label": "every light's mobility -> MOVABLE (read back)",
     "pre": pre_source_hdr(fix_mobility_movable), "post": measure},
    {"label": "sun intensity -> 100000 lux",
     "pre": pre_source_hdr(fix_sun_bright), "post": measure},
    {"label": "sky light -> real-time capture, intensity 5",
     "pre": pre_source_hdr(fix_skylight_realtime), "post": measure},
    {"label": "PLUS a brand-new Movable sun",
     "pre": pre_source_hdr(fix_add_fresh_sun), "post": measure},
    {"label": "PLUS a brand-new Movable sky light",
     "pre": pre_source_hdr(fix_add_fresh_skylight), "post": measure},
    {"label": "best state, switched back to FINAL_COLOR_LDR",
     "pre": pre_final(), "post": measure},
    {"label": "and now pointed at the sky (FinalColorLDR, pitch +70)",
     "pre": _pre_sky, "post": measure},
]

STATE = {"done": False}


def finish(st, reason):
    if STATE["done"]:
        return
    STATE["done"] = True
    log("")
    log("--- table (all measured on the lit scene colour unless noted) ---")
    for label, verdict in st["results"]:
        meaning = {"GREEN": "GREEN (nothing wrote)",
                   "BLACK": "BLACK (no light)",
                   "LIT": "LIT (HAS AN IMAGE)",
                   "?": "no reading"}.get(verdict, verdict)
        log("    %-56s %s" % (label[:56], meaning))

    lit = [l for l, v in st["results"] if v == "LIT"]
    log("")
    log("    rungs that produced LIGHT: %d" % len(lit))
    if lit:
        log("    first one: %s" % lit[0])
        log("")
        log("    => A LIGHTING CONFIGURATION HERE WORKS. The lab has been unlit;")
        log("       apply the same change in P20 so the level is built lit, then")
        log("       re-render. Section 30's bright-background premise depends on")
        log("       this and could not have been met before.")
    else:
        log("    => NOTHING HERE LIT THE SCENE, including a brand-new Movable sun")
        log("       and a brand-new real-time sky light. That rules out 'the")
        log("       existing lights are misconfigured' - no light reaches a capture")
        log("       in this world at all. Next: check whether the level renders in")
        log("       the editor viewport, and whether show flags disable lighting")
        log("       for scene captures in this configuration.")
    log("")
    log("    ticks: %d, pre-raised errors: %d (reason: %s)"
        % (st["t"], st["errors"], reason))
    log("P26 VERDICT : %d lit rung(s), %d tick error(s)"
        % (len(lit), st["errors"]))
    log("P26 DONE")
    print("P26 DONE")
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception:
        pass


log("")
log("--- lighting ladder: %d rungs ---" % len(PLAN))
swcap.Ladder(PLAN, log, wait=WAIT, budget=600, name="P26").start(
    on_done=finish, handover=lambda: WFX.watchdog_handover())
