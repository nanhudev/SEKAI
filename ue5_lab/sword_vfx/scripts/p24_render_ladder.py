"""SEKAI Sword VFX - P24: the render ladder. Can anything be made to draw?

THE QUESTION, NOW SHARPLY STATED

    P23 concluded "PATH A black, PATH B none", which was inconclusive for three
    separate reasons, all of them my own bugs:

      - PATH A placed the capture at (0, 0, 200) and reported success anyway
        ("capture placed on Review_TP34: True", while the camera it copied was
        at (-520, 300, 235)). So it measured the wrong place.
      - PATH B fired `HighResShot 1920 x 1080`, and UE reads a bare number as a
        MULTIPLIER, not a resolution:
            The specified multiplier for high resolution screenshot is too large
            (requested size 2929920x1655040, max size 16384x16384)
        So the viewport path was never actually sampled.
      - and there was no calibration, so "black" could have meant "the export
        path is broken" just as easily as "nothing rendered".

    Then png_dump.py settled what the old frames ARE. All five byte-identical,
    alpha 255 everywhere, RGB (0,0,0) for 89.81% and (1,1,1) for 10.19% - which
    is create_render_target2d's clear colour plus the exporter's dither, not a
    scene. The target was never rendered into.

    So the remaining question is not "is it black" but:

        does ANY render pass run in this editor session, and if not, which
        available lever makes one run?

HOW THIS ANSWERS IT

    1. CALIBRATION FIRST. Clear the target to bright green and read it back. If
       that does not read green, the export path is the problem and every later
       reading is meaningless - so it aborts instead of producing a table of
       numbers nobody can trust.

    2. THE GREEN-CLEAR TEST, WIRED INTO EVERY RUNG. A target that was never
       rendered into and a target showing a black scene both read as "dark".
       Green does not:

           still green after the lever  -> nothing rendered. Unambiguous.
           anything else                -> something rendered. Now look at it.

    3. A LADDER, ONE LEVER PER RUNG, EACH MEASURED. Six candidate ways to make
       this session draw, cheapest and most likely first, each with its own
       clear-read cycle. One session, one table, so the answer is a row rather
       than a hunch.

    4. CVARS LAST. If no lever works, the next move is to stop guessing CVar
       names and read them. This dumps what the engine actually has.

WHY 512x512 FOR THE LADDER

    The question per rung is binary, and swimg's decoder is pure Python
    (~1 s per 1080p frame). At 512 that is ~0.1 s and the ladder stays cheap.
    The deliverable frames are still 1920x1080 - this only decides HOW to get
    them.

Usage:
    ./run_ue.sh scripts/p24_render_ladder.py --render
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swcap  # noqa: E402
import swimg  # noqa: E402
import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p24_ladder.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/ladder')
SHOT_DIR = str(_SEKAI_ROOT / 'ue5_lab/SwordVFX_Lab/Saved/Screenshots')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"

RT_W, RT_H = 512, 512
WAIT_TICKS = 15
GREEN_RGB = (0, 255, 0)
BUDGET = 900

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
    log("P24 ABORTED")
    print("P24 ABORTED")
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception:
        pass
    raise SystemExit(0)


# --------------------------------------------------------------------------
# engine access, all of it non-throwing
# --------------------------------------------------------------------------
def world():
    for how in (("get_editor_subsystem", unreal.UnrealEditorSubsystem),
                "EditorLevelLibrary"):
        try:
            if isinstance(how, tuple):
                return getattr(unreal, how[0])(how[1]).get_editor_world()
            return getattr(unreal, how)().get_editor_world()
        except Exception:
            continue
    return None


def _subsystems():
    """Every editor subsystem instance available, most modern first.

    Deliberately not one hard-coded call: this build emits deprecation warnings
    for the class-style accessors, and the `editor_*` helpers have moved between
    EditorLevelLibrary and LevelEditorSubsystem across UE5 releases. A lever that
    exists in only one of them should still be found.
    """
    out = []
    for cls_name in ("LevelEditorSubsystem", "EditorActorSubsystem",
                     "EditorAssetLibrary"):
        try:
            out.append((cls_name + "(subsystem)",
                        unreal.get_editor_subsystem(getattr(unreal, cls_name))))
        except Exception:
            pass
    for cls_name in ("LevelEditorSubsystem", "EditorLevelLibrary",
                     "EditorActorSubsystem"):
        try:
            out.append((cls_name + "(class)", getattr(unreal, cls_name)()))
        except Exception:
            pass
    return out


def try_methods(method_name, *args):
    """Call `method_name` on whatever exposes it. Returns (ok, how, err)."""
    errs = []
    for label, obj in _subsystems():
        fn = getattr(obj, method_name, None)
        if fn is None:
            continue
        try:
            fn(*args)
            return True, label, ""
        except Exception as exc:
            errs.append("%s -> %s" % (label, str(exc)[:70]))
    if errs:
        return False, "", " | ".join(errs)
    return False, "", "no object exposes %s()" % method_name


def console(cmd):
    """Execute a console command in this world. Returns whether it was sent."""
    for target in (W, None):
        try:
            unreal.SystemLibrary.execute_console_command(target, cmd)
            return True
        except Exception:
            continue
    return False


def all_actors():
    """Every level actor, deduplicated.

    MEASURED: this build returns each actor TWICE. P20's tally read "actors: 68"
    for a level holding 34 until that was noticed, so anything counting actors
    must dedupe first.
    """
    raw = []
    for label, obj in _subsystems():
        fn = getattr(obj, "get_all_level_actors", None)
        if fn is None:
            continue
        try:
            raw = fn()
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


def read_cvar(name):
    """Read a console variable if this engine exposes a getter for it.

    Returns (found, value). `found` False covers both "no getter" and "no such
    cvar", which is noted in the output rather than papered over.
    """
    for holder in ("KismetSystemLibrary", "SystemLibrary"):
        obj = getattr(unreal, holder, None)
        if obj is None:
            continue
        for meth in ("get_console_variable_string_value",
                     "get_console_variable_int_value"):
            fn = getattr(obj, meth, None)
            if fn is None:
                continue
            for ctx in (W, None):
                try:
                    return True, str(fn(ctx, name))
                except Exception:
                    continue
    return False, ""


# --------------------------------------------------------------------------
# boot + facts
# --------------------------------------------------------------------------
log("engine: " + unreal.SystemLibrary.get_engine_version())
log("mode  : editor, real rasterizer")
_nullrhi = False
try:
    _nullrhi = "-nullrhi" in str(unreal.SystemLibrary.get_command_line())
except Exception:
    pass
log("rasterizer: %s" % ("NONE (-nullrhi)" if _nullrhi else "available"))
if _nullrhi:
    abort("a probe about rendering cannot run without a rasterizer; use --render")

for label, obj in _subsystems():
    fn = getattr(obj, "load_level", None)
    if fn is None:
        continue
    try:
        fn(LVL)
        log("level loaded via %s" % label)
        break
    except Exception as exc:
        log("load_level via %s failed: %s" % (label, str(exc)[:110]))

W = world()
if W is None:
    abort("no editor world")
log("world: %s" % W.get_path_name())
os.makedirs(OUT_DIR, exist_ok=True)

# --- is there a level viewport, and is there anything to look at? ---------
log("")
log("--- facts (these exclude the dull explanations) ---")
try:
    vp = unreal.EditorLevelLibrary.get_level_viewport_camera_info()
    if vp and vp[0] is not None:
        log("    level viewport camera : loc=(%.0f,%.0f,%.0f) "
            "pitch=%.1f yaw=%.1f" % (vp[0].x, vp[0].y, vp[0].z,
                                     vp[1].pitch, vp[1].yaw))
    else:
        log("    level viewport camera : none returned")
except Exception as exc:
    log("    level viewport camera : unavailable (%s)" % str(exc)[:80])

ACTORS = all_actors()
log("    level actors          : %d (deduped)" % len(ACTORS))

cam_actor, cam_loc, cam_rot = None, None, None
for a in ACTORS:
    try:
        if a.get_actor_label() == "Review_TP34":
            cam_actor = a
            cam_loc = a.get_actor_location()
            cam_rot = a.get_actor_rotation()
            break
    except Exception:
        continue
if cam_actor is None:
    abort("Review_TP34 is not in the level, so there is no shot to take")
log("    Review_TP34           : loc=(%.0f,%.0f,%.0f) pitch=%.1f yaw=%.1f"
    % (cam_loc.x, cam_loc.y, cam_loc.z, cam_rot.pitch, cam_rot.yaw))
near = swcap.actors_near(ACTORS, cam_loc, 3000.0, limit=8)
log("    actors within 30 m of it: %d  %s"
    % (len(near), ", ".join("%s@%.0fcm" % (l, d) for d, l in near[:6])))

# --- the capture ---------------------------------------------------------
rt = swcap.make_rt(W, RT_W, RT_H)
if rt is None:
    abort("could not create a render target")
cap = None
for label, obj in _subsystems():
    fn = getattr(obj, "spawn_actor_from_class", None)
    if fn is None:
        continue
    try:
        cap = fn(unreal.SceneCapture2D, unreal.Vector(0, 0, 200),
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
    abort("no capture component on the spawned SceneCapture2D")

log("")
log("--- capture wiring, every set logged with its readback ---")
ok = swcap.set_prop(cc, "texture_target", rt)
cur = swcap.get_prop(cc, "texture_target")[1]
log("    texture_target        : set=%s  readback=%s"
    % (ok, "THE RENDER TARGET" if cur is rt else repr(cur)))
src = getattr(unreal.SceneCaptureSource, "SCS_FINAL_COLOR_LDR", None)
if src is None:
    log("    capture_source        : enum member SCS_FINAL_COLOR_LDR NOT FOUND")
else:
    set_ok = swcap.set_prop(cc, "capture_source", src)
    got = swcap.get_prop(cc, "capture_source")[1]
    log("    capture_source        : set=%s  readback=%s" % (set_ok, got))
swcap.set_prop(cc, "capture_every_frame", True)
log("    capture_every_frame   : readback=%s"
    % (swcap.get_prop(cc, "capture_every_frame")[1],))
swcap.set_prop(cc, "capture_on_movement", False)
for p in ("fov_angle", "primitive_render_mode", "hidden_actors"):
    okp, val = swcap.get_prop(cc, p)
    log("    %-21s : %s" % (p, val if okp else "unreadable"))
try:
    log("    component visible     : %s" % cc.is_visible())
except Exception as exc:
    log("    component visible     : unreadable (%s)" % str(exc)[:60])

moved, why = swcap.place_capture(cc, cap, cam_loc, cam_rot)
log("    placed on Review_TP34 : %s  (%s)" % (moved, why))
if not moved:
    abort("the capture cannot be placed at the shot, so nothing measured here "
          "would be about the world")

# --------------------------------------------------------------------------
# the ladder
# --------------------------------------------------------------------------
Screenshots_before = set(glob.glob(os.path.join(SHOT_DIR, "**", "*.png"),
                                   recursive=True))
log("    screenshots on disk   : %d before the ladder" % len(Screenshots_before))


def measure(note):
    """Export the target and classify it. Returns 'GREEN', 'CHANGED' or '?'.

    THE EXPORT NAME IS UNIQUE PER CALL, and that is load-bearing. swimg.collect
    prefers an already-normalised `<name>.png` if one exists, so re-exporting a
    fixed name would hand back the PREVIOUS rung's image and every rung after
    the first would report the first rung's state. That is the same
    stale-artifact shape as the review gate that once printed "5 frames written"
    for a pass that wrote none, so it gets pre-empted rather than discovered.
    The side benefit is that each rung's target state is left on disk as
    evidence.
    """
    MEASURED["n"] += 1
    name = "_p24_%02d" % MEASURED["n"]
    swcap.export_rt(W, rt, OUT_DIR, name)
    path = swimg.collect(OUT_DIR, name)
    if not path:
        log("        %-9s NO FILE WAS WRITTEN" % note)
        return "?"
    st = swimg.png_stats(path)
    if st is None or st["mean_luma"] is None:
        log("        %-9s unreadable" % note)
        return "?"
    top = st["top_rgb"] or (0, 0, 0)
    frac = st["top_rgb_frac"] or 0.0
    green = (abs(top[0] - GREEN_RGB[0]) <= 12
             and abs(top[1] - GREEN_RGB[1]) <= 12
             and abs(top[2] - GREEN_RGB[2]) <= 12
             and frac >= 0.75)
    verdict = "GREEN" if green else "CHANGED"
    log("        %-9s %-8s top=%-14s %5.1f%%  mean_luma=%-7.2f distinct_rgb=%s"
        % (note, verdict, str(top), 100.0 * frac, st["mean_luma"],
           st["distinct_rgb"]))
    if verdict == "CHANGED":
        log("                     kept as %s" % os.path.basename(path))
    return verdict


MEASURED = {"n": 0}


def clear_green():
    swcap.clear_rt(W, rt)


# --- lever definitions. Each returns a note; none may raise. -------------
def lev_none():
    return "nothing - the baseline"


def lev_invalidate():
    ok, how, err = try_methods("editor_invalidate_viewports")
    return "invalidate viewports: %s%s" % ("ok via " + how if ok else "FAILED "
                                           + err[:90])


def lev_viewport_camera():
    ok, how, err = try_methods("set_level_viewport_camera_info", cam_loc, cam_rot)
    return "level viewport camera -> TP34: %s" % (
        "ok via " + how if ok else "FAILED " + err[:90])


def lev_pilot():
    ok, how, err = try_methods("pilot_level_actor", cam_actor)
    return "pilot TP34 into the viewport: %s" % (
        "ok via " + how if ok else "FAILED " + err[:90])


def lev_game_view_on():
    ok, how, err = try_methods("editor_set_game_view", True)
    return "game view ON: %s" % ("ok via " + how if ok else "FAILED " + err[:90])


def lev_capture_scene():
    try:
        cc.capture_scene()
        return "forced capture_scene()"
    except Exception as exc:
        return "forced capture_scene() FAILED: %s" % str(exc)[:90]


def lev_highresshot():
    # `HighResShot 1920 x 1080` is read as a MULTIPLIER. MEASURED:
    #   requested size 2929920x1655040
    # so the dimensions go in WITHOUT spaces.
    sent = console("HighResShot 1920x1080")
    return "HighResShot 1920x1080 (no spaces): %s" % (
        "sent" if sent else "the command could not be sent")


def lev_setres():
    sent = console("r.SetRes 1280x720w")
    return "r.SetRes 1280x720w (a resize forces a window redraw): %s" % (
        "sent" if sent else "could not be sent")


def lev_tonemap_off():
    # Ruled out as a cause, kept as a control: if tonemapping were eating the
    # image, disabling it would change the target.
    sent = console("r.Tonemapper.Quality 0")
    return "r.Tonemapper.Quality 0 (control): %s" % (
        "sent" if sent else "could not be sent")


def lev_lights_off():
    sent = console("ShowFlag.Lighting 1")
    return "ShowFlag.Lighting 1 (control): %s" % (
        "sent" if sent else "could not be sent")


PLAN = [
    {"label": "CALIBRATION: clear to green, no lever",
     "pre": clear_green, "post": lambda: measure("after"),
     "wait": WAIT_TICKS, "kind": "calib"},
    {"label": "0 baseline (no lever at all)",
     "pre": clear_green, "post": lambda: measure("after"), "wait": WAIT_TICKS},
    {"label": "1 " + "editor_invalidate_viewports()",
     "pre": lambda: (clear_green(), log("        " + lev_invalidate())),
     "post": lambda: measure("after"), "wait": WAIT_TICKS},
    {"label": "2 level viewport camera -> TP34",
     "pre": lambda: (clear_green(), log("        " + lev_viewport_camera())),
     "post": lambda: measure("after"), "wait": WAIT_TICKS},
    {"label": "3 pilot TP34 into the level viewport",
     "pre": lambda: (clear_green(), log("        " + lev_pilot())),
     "post": lambda: measure("after"), "wait": WAIT_TICKS},
    {"label": "4 game view ON",
     "pre": lambda: (clear_green(), log("        " + lev_game_view_on())),
     "post": lambda: measure("after"), "wait": WAIT_TICKS},
    {"label": "5 forced capture_scene()",
     "pre": lambda: (clear_green(), log("        " + lev_capture_scene())),
     "post": lambda: measure("after"), "wait": WAIT_TICKS},
    {"label": "6 HighResShot 1920x1080 (correct syntax)",
     "pre": lambda: (clear_green(), log("        " + lev_highresshot())),
     "post": lambda: measure("after"), "wait": WAIT_TICKS},
    {"label": "7 r.SetRes 1280x720w",
     "pre": lambda: (clear_green(), log("        " + lev_setres())),
     "post": lambda: measure("after"), "wait": WAIT_TICKS},
    {"label": "8 control: tonemapper + lighting showflags",
     "pre": lambda: (clear_green(), log("        " + lev_tonemap_off()),
                     console("ShowFlag.Lighting 1")),
     "post": lambda: measure("after"), "wait": WAIT_TICKS},
]

# A per-step clear-read cycle. Each step runs `pre` (which clears the target to
# green and applies one lever), waits, then runs `post` (which reads it). Green
# at the end means the lever produced no render.
STATE = {"idx": 0, "stage": "pre", "wait": 0, "errors": 0, "t": 0,
         "handed": False, "results": [], "done": False}


def _run(fn, where):
    try:
        return fn()
    except Exception as exc:
        STATE["errors"] += 1
        log("        %s raised: %s: %s"
            % (where, type(exc).__name__, str(exc)[:120]))
        return None


def _finish(reason):
    st = STATE
    if st["done"]:
        return
    st["done"] = True
    log("")
    log("--- the ladder, as a table ---")
    log("    %-46s %s" % ("lever (in the order tried)", "target afterwards"))
    for label, verdict in st["results"]:
        if verdict == "GREEN":
            meaning = "STILL GREEN - nothing rendered"
        elif verdict == "CHANGED":
            meaning = "CHANGED - SOMETHING RENDERED"
        else:
            meaning = "no reading"
        log("    %-46s %s" % (label[:46], meaning))

    new_shots = sorted(set(glob.glob(os.path.join(SHOT_DIR, "**", "*.png"),
                                     recursive=True)) - Screenshots_before)
    log("")
    log("    engine screenshots written during the ladder: %d" % len(new_shots))
    for s in new_shots[:4]:
        log("        %s  %s" % (os.path.basename(s), swimg.describe(s)))

    rendered = [l for l, v in st["results"] if v == "CHANGED"]
    log("")
    if rendered:
        log("    => SOMETHING IN THIS SESSION RENDERS. The rung(s) that produced")
        log("       pixels: %s" % "; ".join(rendered))
        log("       P21 should capture the way that rung does.")
    elif new_shots:
        log("    => THE TARGET NEVER CHANGED, BUT THE ENGINE WROTE A SCREENSHOT.")
        log("       The world draws; the SceneCapture2D path specifically does not.")
        log("       P21 should capture through the viewport.")
    else:
        log("    => NOTHING RENDERS IN THIS SESSION, and no lever tried here")
        log("       changes that. The SceneCapture2D is not a special case: there")
        log("       is no render pass to feed it from. Resolve the rendering")
        log("       environment before any frame work resumes.")
    log("")
    log("    ticks used: %d, tick errors: %d (reason: %s)"
        % (st["t"], st["errors"], reason))
    log("P24 VERDICT : %d rung(s) changed the target, %d screenshot(s), "
        "%d tick error(s)" % (len(rendered), len(new_shots), st["errors"]))
    log("P24 DONE")
    print("P24 DONE")
    try:
        unreal.unregister_slate_post_tick_callback(st["handle"])
    except Exception:
        pass
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception:
        pass


def tick(delta):
    st = STATE
    if st["done"]:
        return
    st["t"] += 1
    if st["t"] > BUDGET:
        _finish("tick budget exhausted")
        return
    st["wait"] -= 1
    if st["wait"] > 0:
        return
    if st["idx"] >= len(PLAN):
        _finish("ladder complete")
        return
    step = PLAN[st["idx"]]
    if st["stage"] == "pre":
        log("")
        log("[%d/%d] %s" % (st["idx"] + 1, len(PLAN), step["label"]))
        _run(step["pre"], "pre")
        st["stage"] = "post"
        st["wait"] = step["wait"]
        if not st["handed"]:
            # Armed until the callback has completed a tick: its whole job is to
            # catch "the callback never ran at all", and handing over before the
            # loop throws that net away.
            WFX.watchdog_handover()
            st["handed"] = True
    else:
        st["results"].append((step["label"], _run(step["post"], "post")))
        st["idx"] += 1
        st["stage"] = "pre"


# --- CVar truth, so the next attempt is not guesswork -------------------
log("")
log("--- console variables the engine actually has ---")
log("    (reading these is how the next lever gets chosen, instead of")
log("     guessing at names and watching them silently do nothing)")
for name in ("Slate.bAllowThrottling",
             "Slate.ThrottleWhenMouseIsMoving",
             "Slate.EnableGlobalInvalidation",
             "r.SceneCapture.CullByDetailMode",
             "r.HighResScreenshot.EnableHDRCapture",
             "t.MaxFPS",
             "r.ScreenPercentage",
             "r.DefaultFeature.AutoExposure"):
    found, val = read_cvar(name)
    log("    %-38s %s" % (name, val if found else "(no getter / not present)"))
sent = console("DumpCVars Slate")
log("    DumpCVars Slate sent: %s - its output goes to the engine log; grep "
    "Saved/Logs" % sent)

log("")
log("--- ladder: %d rungs, %d ticks apart ---" % (len(PLAN), WAIT_TICKS))
STATE["handle"] = unreal.register_slate_post_tick_callback(tick)
