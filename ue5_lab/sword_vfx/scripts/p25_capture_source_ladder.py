"""SEKAI Sword VFX - P25: WHICH STAGE is black?

WHAT P24 ESTABLISHED, AND WHAT IT LEFT OPEN

    P24 ran ten levers against a render target cleared to bright green, so
    "nothing wrote to it" became a bit rather than a judgement call. Result:

        baseline (no lever)                 STILL GREEN
        editor_invalidate_viewports()       STILL GREEN   (rung invalid, see below)
        level viewport camera -> TP34       STILL GREEN
        pilot TP34 into the viewport        STILL GREEN
        game view ON                        STILL GREEN
        r.SetRes 1280x720w                  STILL GREEN
        HighResShot 1920x1080 (fixed syntax) STILL GREEN
        forced capture_scene()              CHANGED -> opaque near-black
        engine screenshots written            0

    Two things follow, and they are not the same thing:

      * `capture_every_frame = True` (readback verified) produced NO writes over
        15 ticks each time. So the per-frame capture path is not running.
      * An EXPLICIT `capture_scene()` DID overwrite the green with near-black.
        So the capture pipeline executes - it is the IMAGE that is black.

    That kills the earlier hypothesis, "no render pass exists, so a capture has
    nothing to feed on". A capture runs and returns black. The question is now
    narrow and mechanical: is it the geometry, the lighting, or the
    post-process/tonemap stage?

HOW THIS LOCALISES IT

    `capture_source` selects which stage of the render pipeline lands in the
    target. Each value bypasses everything after it:

        SCS_SCENE_COLOR_HDR   scene colour, BEFORE tonemap/exposure
        SCS_BASE_COLOR        material albedo only - no lighting at all
        SCS_NORMAL            world normals, no lighting, no post
        SCS_SCENE_DEPTH       depth, no lighting, no post
        SCS_FINAL_COLOR_LDR   the full chain (what we actually want)

    So:

        normals/depth/base-colour have an image, final colour does not
            -> geometry and materials render. The fault is in lighting or
               tonemap. (Normals bypass lighting entirely; that is the point.)
        every source is flat black
            -> no geometry reaches the capture at all. The fault is upstream of
               lighting: culling, show flags, or the component not being where
               it thinks it is.
        everything including final colour has an image
            -> the fault was transient, and the fix is in how the capture is
               driven, not in the capture's settings.

    Plus the rungs that are not about capture_source: sky-facing, no post-process,
    an explicit exposure override, render-primitives mode, and a movement-
    triggered capture. Together they separate "the capture cannot see" from "the
    capture sees and renders it black".

A BUG IN P24 WORTH NAMING, because it changed a reading

    P24's rung 1 built its message with "invalidate viewports: %s%s" % (one
    value) - two format specifiers, one argument - so `pre` raised TypeError and
    the lever never ran. The rung still printed "STILL GREEN", which reads as
    evidence about editor_invalidate_viewports and is not. The clear had already
    happened (tuple evaluation is left to right), so the rung measured a green
    target and no lever. It is retested here, and the harness now reports a
    raised `pre` as invalid rather than as a reading.

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p25_capture_source_ladder.py --render
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p25_sources.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/sources')
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
    log("P25 ABORTED")
    print("P25 ABORTED")
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
            out.append((cls + "(subsystem)",
                        unreal.get_editor_subsystem(getattr(unreal, cls))))
        except Exception:
            pass
    for cls in ("LevelEditorSubsystem", "EditorLevelLibrary",
                "EditorActorSubsystem"):
        try:
            out.append((cls + "(class)", getattr(unreal, cls)()))
        except Exception:
            pass
    return out


def try_methods(method_name, *args):
    errs = []
    for label, obj in subsystems():
        if not hasattr(obj, method_name):
            continue
        try:
            getattr(obj, method_name)(*args)
            return True, label, ""
        except Exception as exc:
            errs.append("%s -> %s" % (label, str(exc)[:70]))
    return False, "", (" | ".join(errs) if errs
                       else "nobody exposes %s()" % method_name)


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
# facts
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
for how in ("UnrealEditorSubsystem", "EditorLevelLibrary"):
    try:
        if how == "UnrealEditorSubsystem":
            W = unreal.get_editor_subsystem(
                unreal.UnrealEditorSubsystem).get_editor_world()
        else:
            W = getattr(unreal, how)().get_editor_world()
        if W is not None:
            break
    except Exception:
        continue
if W is None:
    abort("no editor world")
log("world: %s" % W.get_path_name())
os.makedirs(OUT_DIR, exist_ok=True)

# --- the enum, printed rather than assumed ------------------------------
try:
    members = [m for m in dir(unreal.SceneCaptureSource) if m.startswith("SCS")]
    log("")
    log("    SceneCaptureSource members this build actually has:")
    for m in members:
        log("        %-26s = %s" % (m, getattr(unreal.SceneCaptureSource, m)))
except Exception as exc:
    log("    could not enumerate SceneCaptureSource: %s" % str(exc)[:90])

ACTORS = all_actors()
cam_actor, cam_loc, cam_rot = None, None, None
for a in ACTORS:
    try:
        if a.get_actor_label() == "Review_TP34":
            cam_actor, cam_loc, cam_rot = a, a.get_actor_location(), \
                a.get_actor_rotation()
            break
    except Exception:
        continue
if cam_actor is None:
    abort("Review_TP34 is not in the level")
log("    level actors: %d   Review_TP34: (%.0f,%.0f,%.0f) pitch=%.1f yaw=%.1f"
    % (len(ACTORS), cam_loc.x, cam_loc.y, cam_loc.z, cam_rot.pitch, cam_rot.yaw))
near = swcap.actors_near(ACTORS, cam_loc, 3000.0, limit=6)
log("    what is in front of it: %s"
    % ", ".join("%s@%.0fcm" % (l, d) for d, l in near))

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
swcap.set_prop(cc, "capture_on_movement", False)
ok, why = swcap.place_capture(cc, cap, cam_loc, cam_rot)
log("    capture placed on TP34: %s (%s)" % (ok, why))
if not ok:
    abort("the capture will not go where the shot is")

try:
    cloc, cfwd = swcap.component_transform(cc)
    if cloc is not None:
        aloc = cap.get_actor_location()
        log("    COMPONENT world loc : (%.1f,%.1f,%.1f)"
            % (cloc.x, cloc.y, cloc.z))
        log("    actor     world loc : (%.1f,%.1f,%.1f)"
            % (aloc.x, aloc.y, aloc.z))
        if abs(cloc.x - cam_loc.x) > 1 or abs(cloc.y - cam_loc.y) > 1:
            log("    !! the component and the actor DISAGREE. The capture is not")
            log("       at the shot, and every reading below would be about the")
            log("       wrong place.")
        else:
            log("    component agrees with the shot: the capture looks where")
            log("    TP34 looks")
    if cfwd is not None:
        log("    COMPONENT forward   : (%.3f,%.3f,%.3f)"
            % (cfwd.x, cfwd.y, cfwd.z))
except Exception as exc:
    # The facts phase reports; it must never abort. It already cost a whole run
    # once: a TypeError here ran BEFORE the ladder, so 3m39s bought no readings
    # at all. Everything in this block is diagnostics - none of it is worth
    # sacrificing the measurements for.
    log("    component transform: UNREADABLE (%s: %s)"
        % (type(exc).__name__, str(exc)[:90]))

# A trace along the capture's own view axis. If this hits nothing, "the frame
# is black because there is nothing in front" is the whole story.
try:
    start = unreal.Vector(cam_loc.x, cam_loc.y, cam_loc.z)
    end = unreal.Vector(cam_loc.x + cfwd.x * 2000.0,
                        cam_loc.y + cfwd.y * 2000.0,
                        cam_loc.z + cfwd.z * 2000.0)
    hit = unreal.SystemLibrary.line_trace_single(
        W, start, end, unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,
        True, [], unreal.DrawDebugTrace.NONE, True)
    # The return shape varies: some builds hand back the FHitResult, others a
    # (bHit, FHitResult) pair. Neither is assumed.
    result = None
    if isinstance(hit, (tuple, list)):
        for item in hit:
            if hasattr(item, "impact_point"):
                result = item
    elif hasattr(hit, "impact_point"):
        result = hit
    if result is not None:
        log("    trace 20 m along the view axis: HIT at %.0f cm"
            % swcap.vdist(start, result.impact_point))
    else:
        log("    trace 20 m along the view axis: no hit reported (either the")
        log("        view axis is empty, or this build's trace API differs).")
except Exception as exc:
    log("    trace unavailable: %s: %s"
        % (type(exc).__name__, str(exc)[:90]))

# Read the post-process / show-flag state, so a later rung is not guesswork.
try:
    pps = cc.get_editor_property("post_process_settings")
    for f in ("auto_exposure_method", "auto_exposure_min_brightness",
              "auto_exposure_max_brightness", "auto_exposure_bias",
              "auto_exposure_min_ev100", "auto_exposure_max_ev100"):
        try:
            log("    pps.%-28s = %s" % (f, pps.get_editor_property(f)))
        except Exception:
            pass
except Exception as exc:
    log("    post_process_settings unreadable: %s" % str(exc)[:80])
try:
    log("    post_process_blend_weight = %s"
        % cc.get_editor_property("post_process_blend_weight"))
except Exception:
    pass
try:
    sfs = cc.get_editor_property("show_flag_settings")
    log("    show_flag_settings overrides: %d" % len(sfs))
    for s in sfs:
        try:
            log("        %s = %s" % (s.get_editor_property("name"),
                                     s.get_editor_property("enabled")))
        except Exception:
            pass
except Exception as exc:
    log("    show_flag_settings unreadable: %s" % str(exc)[:80])


# --------------------------------------------------------------------------
# measurement
# --------------------------------------------------------------------------
MEASURED = {"n": 0}


def measure(note="after"):
    """Export the target and classify. GREEN / BLACK / IMAGE / ?"""
    MEASURED["n"] += 1
    name = "_p25_%02d" % MEASURED["n"]
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
    is_green = (abs(top[0] - GREEN_RGB[0]) <= 12
                and abs(top[1] - GREEN_RGB[1]) <= 12
                and abs(top[2] - GREEN_RGB[2]) <= 12 and frac >= 0.75)
    if is_green:
        verdict = "GREEN"
    elif (st["distinct_rgb"] or 0) <= 4 and (st["mean_luma"] or 0) < 2.0:
        verdict = "BLACK"
    else:
        verdict = "IMAGE"
    log("        %-7s %-5s top=%-14s %5.1f%%  mean_luma=%-7.2f distinct_rgb=%s"
        % (note, verdict, str(top), 100.0 * frac, st["mean_luma"],
           st["distinct_rgb"]))
    return verdict


def clear_green():
    swcap.clear_rt(W, rt)


def set_source(name):
    val = getattr(unreal.SceneCaptureSource, name, None)
    if val is None:
        log("        source %s DOES NOT EXIST in this build" % name)
        return False
    swcap.set_prop(cc, "capture_source", val)
    got = swcap.get_prop(cc, "capture_source")[1]
    log("        source -> %s (readback %s)" % (name, got))
    return True


def shoot():
    try:
        cc.capture_scene()
        return "capture_scene() called"
    except Exception as exc:
        return "capture_scene() FAILED: %s" % str(exc)[:90]


def rung_source(name, extra=None):
    """pre for a capture-source rung."""
    def pre():
        clear_green()
        set_source(name)
        if extra:
            log("        " + extra())
        log("        " + shoot())
    return pre


def _turn_capture(pitch, yaw):
    # Positional, in (ROLL, PITCH, YAW) order. MEASURED earlier in this project:
    # `unreal.Rotator(*t)` expands a tuple in that order, and assuming
    # (pitch, yaw, roll) rolled all five QA cameras.
    rot = unreal.Rotator(0.0, pitch, yaw)
    ok, why = swcap.place_capture(cc, cap, cam_loc, rot)
    return "turned to pitch=%.0f yaw=%.0f: %s" % (pitch, yaw, ok)


def extra_no_post():
    ok = swcap.set_prop(cc, "post_process_blend_weight", 0.0)
    return "post_process_blend_weight -> 0.0 (set=%s, readback=%s)" % (
        ok, swcap.get_prop(cc, "post_process_blend_weight")[1])


def extra_render_primitives():
    val = getattr(unreal.SceneCapturePrimitiveRenderMode,
                  "PRM_RENDER_SCENE_PRIMITIVES", None)
    ok = swcap.set_prop(cc, "primitive_render_mode", val) \
        if val is not None else False
    return "primitive_render_mode -> PRM_RENDER_SCENE_PRIMITIVES (set=%s)" % ok


def extra_exposure():
    try:
        pps = cc.get_editor_property("post_process_settings")
        pps.set_editor_property("auto_exposure_min_brightness", 0.03)
        pps.set_editor_property("auto_exposure_max_brightness", 8.0)
        pps.set_editor_property("auto_exposure_bias", 1.0)
        cc.set_editor_property("post_process_settings", pps)
        return ("exposure override 0.03..8.0 bias 1.0 applied; readback min=%s "
                "max=%s" % (pps.get_editor_property("auto_exposure_min_brightness"),
                            pps.get_editor_property("auto_exposure_max_brightness")))
    except Exception as exc:
        return "exposure override FAILED: %s" % str(exc)[:90]


def extra_every_frame():
    ok = swcap.set_prop(cc, "capture_every_frame", True)
    return "capture_every_frame -> True (set=%s, readback=%s)" % (
        ok, swcap.get_prop(cc, "capture_every_frame")[1])


def _pre_invalidate():
    """P24's broken rung, redone.

    P24 wrote `"invalidate viewports: %s%s" % (one_value)` - two specifiers, one
    argument - so this raised TypeError, the lever never ran, and the rung still
    reported "STILL GREEN". That reading was about an empty rung, not about
    editor_invalidate_viewports.
    """
    clear_green()
    ok, how, err = try_methods("editor_invalidate_viewports")
    log("        invalidate viewports: %s"
        % ("ok via " + how if ok else "FAILED: " + err[:80]))
    log("        " + shoot())


PLAN = [
    {"label": "calibration: clear, no capture at all",
     "pre": clear_green, "post": measure},
    {"label": "calibration: clear, then one explicit capture (expect BLACK)",
     "pre": lambda: (clear_green(), log("        " + shoot())),
     "post": measure},
    {"label": "re-test of P24's broken rung: editor_invalidate_viewports()",
     "pre": _pre_invalidate, "post": measure},
    {"label": "SCS_SCENE_COLOR_HDR  (scene colour, before tonemap)",
     "pre": rung_source("SCS_SCENE_COLOR_HDR"), "post": measure},
    {"label": "SCS_BASE_COLOR  (albedo only - no lighting, no post)",
     "pre": rung_source("SCS_BASE_COLOR"), "post": measure},
    {"label": "SCS_NORMAL  (normals - proves geometry reaches the capture)",
     "pre": rung_source("SCS_NORMAL"), "post": measure},
    {"label": "SCS_SCENE_DEPTH  (depth - also post-free)",
     "pre": rung_source("SCS_SCENE_DEPTH"), "post": measure},
    {"label": "SCS_FINAL_COLOR_LDR  (the control: expect black)",
     "pre": rung_source("SCS_FINAL_COLOR_LDR"), "post": measure},
    {"label": "FINAL_COLOR_LDR with post_process_blend_weight = 0",
     "pre": rung_source("SCS_FINAL_COLOR_LDR", extra_no_post), "post": measure},
    {"label": "FINAL_COLOR_LDR with PRM_RENDER_SCENE_PRIMITIVES",
     "pre": rung_source("SCS_FINAL_COLOR_LDR", extra_render_primitives),
     "post": measure},
    {"label": "FINAL_COLOR_LDR with an explicit exposure override",
     "pre": rung_source("SCS_FINAL_COLOR_LDR", extra_exposure), "post": measure},
    {"label": "FINAL_COLOR_LDR looking straight up at the sky",
     "pre": lambda: (clear_green(),
                     log("        " + _turn_capture(70.0, cam_rot.yaw)),
                     log("        " + shoot())),
     "post": measure},
    {"label": "back to TP34, capture_every_frame = True (does it self-drive?)",
     "pre": lambda: (clear_green(),
                     log("        " + _turn_capture(cam_rot.pitch, cam_rot.yaw)),
                     log("        " + extra_every_frame())),
     "post": measure},
]

STATE = {"done": False, "handle": None}


def finish(st, reason):
    if STATE["done"]:
        return
    STATE["done"] = True
    log("")
    log("--- table ---")
    log("    %-58s %s" % ("rung", "target after it"))
    for label, verdict in st["results"]:
        if verdict == "GREEN":
            meaning = "GREEN (nothing wrote to it)"
        elif verdict == "BLACK":
            meaning = "BLACK (wrote, flat black)"
        elif verdict == "IMAGE":
            meaning = "IMAGE (wrote, has content)"
        else:
            meaning = "no reading"
        log("    %-58s %s" % (label[:58], meaning))

    images = [l for l, v in st["results"] if v == "IMAGE"]
    blacks = [l for l, v in st["results"] if v == "BLACK"]
    greens = [l for l, v in st["results"] if v == "GREEN"]
    log("")
    log("    IMAGE rungs: %d   BLACK rungs: %d   GREEN rungs: %d"
        % (len(images), len(blacks), len(greens)))
    log("")
    normal_rung = [l for l in images if "SCS_NORMAL" in l]
    base_rung = [l for l in images if "SCS_BASE_COLOR" in l]
    final_wrote_black = [l for l in blacks if "SCS_FINAL_COLOR_LDR" in l]
    if normal_rung or base_rung:
        n = "SCS_NORMAL" if normal_rung else "SCS_BASE_COLOR"
        log("    => GEOMETRY REACHES THE CAPTURE: %s produced a real image." % n)
        log("       Both bypass lighting and post-process, so the fault is")
        log("       downstream of the base pass - in lighting or tonemap - and")
        log("       NOT in culling, show flags, or where the capture sits.")
    elif blacks:
        log("    => captures write, but every source is flat BLACK. Lighting and")
        log("       tonemap are ruled out (normals and depth bypass both), so the")
        log("       geometry is not reaching the capture. Look at show flags,")
        log("       culling, and whether the component's view matches the shot.")
    else:
        log("    => NOTHING WROTE ON ANY RUNG, including the explicit captures.")
        log("       This is not a pipeline-stage problem: the captures are not")
        log("       running at all.")
    if final_wrote_black:
        log("")
        log("    note: the SCS_FINAL_COLOR_LDR rungs wrote black, which is the")
        log("          symptom under investigation - see which stage differs.")
    log("")
    log("    ticks: %d, 'pre raised' errors: %d (reason: %s)"
        % (st["t"], st["errors"], reason))
    log("P25 VERDICT : %d IMAGE, %d BLACK, %d GREEN, %d tick error(s)"
        % (len(images), len(blacks), len(greens), st["errors"]))
    log("P25 DONE")
    print("P25 DONE")
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception:
        pass


log("")
log("--- ladder: %d rungs, %d ticks apart ---" % (len(PLAN), WAIT))
swcap.Ladder(PLAN, log, wait=WAIT, budget=600, name="P25").start(
    on_done=finish, handover=lambda: WFX.watchdog_handover())
