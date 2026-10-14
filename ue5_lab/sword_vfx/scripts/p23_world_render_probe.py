"""SEKAI Sword VFX - P23: why is nothing rendering?

THE QUESTION

    P21 has now produced this three times:

        warm-up  300 ticks  mean luma 0.10   (47 s wall)
        NO IMAGE after 300 ticks.

    300 frames, 47 seconds, and the capture target held its cleared value the
    whole time - with `texture_target` verified by readback as the exact render
    target that was created, `capture_every_frame` set, `capture_scene()` raising
    nothing, and a level that loads with five cameras at correct transforms.

    Two explanations fit that evidence equally well, and they lead to completely
    different fixes:

        (a) the WORLD is not being rendered at all - no viewport draws, so a
            scene capture has nothing to capture and no capture method will work;
        (b) the world renders fine and only the SceneCapture2D path is broken -
            in which case switching capture method fixes it.

    No amount of staring at p21's log separates them. So this script tests both
    paths IN THE SAME SESSION, under identical conditions:

        PATH A  SceneCapture2D into a render target, exported and measured.
                (The path that fails.)
        PATH B  pilot one Review_* camera into the LEVEL EDITOR VIEWPORT and use
                the engine's own screenshot command - the same path a human
                pressing the screenshot key would use, and the path the editor
                is certainly driving since it is showing the level.

    If A is black and B has an image: the world renders, SceneCapture is the
    problem, and p21 should use the viewport.
    If both are black: nothing in this session draws, and the fix is not in the
    capture code at all.

    It reports; it does not decide.

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p23_world_render_probe.py --render

SUPERSEDED BY P24. The three defects listed above are all fixed in
scripts/p24_render_ladder.py, which also calibrates before measuring and tests
six levers instead of two. Run P24.
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import glob
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swimg  # noqa: E402
import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p23_probe.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/probe')
SHOT_DIR = str(_SEKAI_ROOT / 'ue5_lab/SwordVFX_Lab/Saved/Screenshots')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
WIDTH, HEIGHT = 1920, 1080
PROBE_EVERY = 10
BUDGET = 180

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
    log("P23 ABORTED")
    print("P23 ABORTED")
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception:
        pass
    raise SystemExit(0)


def world():
    for cls in ("UnrealEditorSubsystem", "EditorLevelLibrary"):
        try:
            w = getattr(unreal, cls)().get_editor_world()
            if w is not None:
                return w
        except Exception:
            continue
    return None


def all_actors():
    for cls in ("EditorActorSubsystem", "EditorLevelLibrary"):
        try:
            return getattr(unreal, cls)().get_all_level_actors()
        except Exception:
            continue
    return []


def actor_label(a):
    try:
        return a.get_actor_label()
    except Exception:
        try:
            return a.get_name()
        except Exception:
            return ""


def set_prop(obj, name, value):
    try:
        obj.set_editor_property(name, value)
        return True
    except Exception:
        return False


log("engine: " + unreal.SystemLibrary.get_engine_version())
_nullrhi = False
try:
    _nullrhi = "-nullrhi" in str(unreal.SystemLibrary.get_command_line())
except Exception:
    pass
log("rasterizer: %s" % ("NONE (-nullrhi)" if _nullrhi else "available"))
if _nullrhi:
    abort("a probe about rendering cannot run without a rasterizer; "
          "use --render")

for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
    try:
        getattr(unreal, how)().load_level(LVL)
        log("level loaded via %s" % how)
        break
    except Exception as exc:
        log("load_level via %s failed: %s" % (how, str(exc)[:120]))
W = world()
if W is None:
    abort("no editor world")
log("world: %s" % W.get_path_name())

screenshots_dir = os.path.join(SHOT_DIR, "WindowsEditor")
os.makedirs(OUT_DIR, exist_ok=True)
before = set(glob.glob(os.path.join(SHOT_DIR, "**", "*.png"), recursive=True))
log("screenshots already on disk: %d" % len(before))

# --------------------------------------------------------------- PATH A
log("")
log("--- PATH A: SceneCapture2D into a render target ---")
fmt = unreal.TextureRenderTargetFormat.RTF_RGBA8
rt = None
try:
    rt = unreal.RenderingLibrary.create_render_target2d(W, WIDTH, HEIGHT, fmt)
except Exception as exc:
    log("    create_render_target2d failed: %s" % str(exc)[:120])
log("    render target: %s" % ("created" if rt is not None else "NONE"))

cap = None
for how in ("EditorActorSubsystem", "EditorLevelLibrary"):
    try:
        cap = getattr(unreal, how)().spawn_actor_from_class(
            unreal.SceneCapture2D, unreal.Vector(0, 0, 200),
            unreal.Rotator(0, 0, 0))
        break
    except Exception:
        continue
cc = None
if cap is not None:
    for attr in ("capture_component2d", "capture_component"):
        try:
            cc = getattr(cap, attr)
            break
        except Exception:
            continue
if cc is None:
    abort("no capture component on the spawned SceneCapture2D")
set_prop(cc, "texture_target", rt)
set_prop(cc, "capture_every_frame", True)
src = getattr(unreal.SceneCaptureSource, "SCS_FINAL_COLOR_LDR", None)
if src is not None:
    set_prop(cc, "capture_source", src)
try:
    current = cc.get_editor_property("texture_target")
    log("    texture_target readback: %s"
        % ("is the render target" if current == rt else repr(current)))
except Exception as exc:
    log("    texture_target readback failed: %s" % str(exc)[:80])

# Put the capture on the level's own TP34 camera so both paths look at the same
# place - otherwise a difference between them could just be a difference in
# what is in front of them.
cam_actor = None
for a in all_actors():
    try:
        if a.get_actor_label() == "Review_TP34":
            cam_actor = a
            break
    except Exception:
        continue
if cam_actor is not None:
    loc = cam_actor.get_actor_location()
    rot = cam_actor.get_actor_rotation()
    moved = False
    for attempt in (lambda: cc.set_world_location_and_rotation(loc, rot, False, False),
                    lambda: cap.set_actor_location(loc, False, False),
                    lambda: cc.set_world_location_and_rotation(loc, rot)):
        try:
            attempt()
            moved = True
            break
        except Exception:
            continue
    log("    capture placed on Review_TP34: %s" % moved)
    try:
        gl = cap.get_actor_location()
        log("    capture world loc: (%.1f,%.1f,%.1f)  camera loc: "
            "(%.1f,%.1f,%.1f)" % (gl.x, gl.y, gl.z, loc.x, loc.y, loc.z))
    except Exception:
        pass
else:
    log("    Review_TP34 not found - the capture stays at the origin")

# --------------------------------------------------------------- PATH B
log("")
log("--- PATH B: pilot the camera into the level viewport, engine screenshot ---")
piloted = False
for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
    try:
        getattr(unreal, how)().pilot_level_actor(cam_actor)
        piloted = True
        log("    pilot_level_actor via %s" % how)
        break
    except Exception as exc:
        log("    pilot_level_actor via %s failed: %s" % (how, str(exc)[:110]))
if not piloted:
    log("    COULD NOT PILOT: path B cannot be tested this way")

STATE = {"t": 0, "phase": "warm", "fired": False, "screenshot": None,
         "a_luma": None, "handle": None}


def probe_rt():
    name = "_probe"
    try:
        unreal.RenderingLibrary.export_render_target(W, rt, OUT_DIR, name)
    except Exception as exc:
        log("    export failed: %s" % str(exc)[:120])
        return None
    path = swimg.collect(OUT_DIR, name)
    if not path:
        return None
    return swimg.png_probe(path)


def tick(delta):
    st = STATE
    if st["phase"] == "closed":
        return
    st["t"] += 1
    if not st["fired"] and st["t"] >= 20:
        st["fired"] = True
        set_prop(cc, "capture_every_frame", True)
        try:
            cc.capture_scene()
        except Exception:
            pass
        try:
            unreal.SystemLibrary.execute_console_command(
                W, "HighResShot %d x %d" % (WIDTH, HEIGHT))
            log("    fired HighResShot %dx%d" % (WIDTH, HEIGHT))
        except Exception as exc:
            log("    HighResShot failed: %s" % str(exc)[:120])
        # Disarm the watchdog only now. It exists to catch "the callback never
        # ran at all", and calling handover before the loop - which the first
        # draft did - throws away the only net that can catch exactly that.
        WFX.watchdog_handover()
        return
    if st["fired"] and st["t"] % PROBE_EVERY == 0:
        if st["a_luma"] is None and rt is not None:
            probe = probe_rt()
            if probe is not None:
                st["a_luma"] = probe[2]
                log("    PATH A t=%-4d %dx%d mean_luma=%s distinct=%s"
                    % (st["t"], probe[0], probe[1],
                       "?" if probe[2] is None else "%.2f" % probe[2],
                       probe[3]))
        new = sorted(set(glob.glob(os.path.join(SHOT_DIR, "**", "*.png"),
                                   recursive=True)) - before)
        if new:
            st["screenshot"] = new[-1]
            log("    PATH B t=%-4d %s" % (st["t"], new[-1]))
            log("                     %s" % swimg.describe(st["screenshot"]))
            st["phase"] = "done"
    if st["t"] > BUDGET and st["phase"] != "done":
        st["phase"] = "done"
        log("    PATH B never wrote a screenshot within %d ticks" % BUDGET)
    if st["phase"] == "done":
        st["phase"] = "closed"
        log("")
        log("--- findings ---")
        a = st["a_luma"]
        log("    PATH A (SceneCapture2D): mean luma %s"
            % ("?" if a is None else "%.2f" % a))
        if st["screenshot"]:
            probe = swimg.png_probe(st["screenshot"])
            b = None if probe is None else probe[2]
            log("    PATH B (viewport screenshot): mean luma %s"
                % ("?" if b is None else "%.2f" % b))
            log("")
            about_a = "EMPTY" if (a is not None and a < 1.0) else "has an image"
            about_b = "EMPTY" if (b is not None and b < 1.0) else "has an image"
            log("    SceneCapture2D  : %s" % about_a)
            log("    Editor viewport : %s" % about_b)
            if b is not None and b >= 1.0 and (a is None or a < 1.0):
                log("")
                log("    => THE WORLD RENDERS. The SceneCapture2D path is the")
                log("       broken one. P21 should capture through the viewport.")
            elif (a is None or a < 1.0) and (b is None or b < 1.0):
                log("")
                log("    => NOTHING DRAWS IN THIS SESSION. This is not a")
                log("       capture-method problem; no capture method will win.")
        else:
            log("    PATH B (viewport screenshot): no file appeared")
        log("P23 VERDICT  : A=%s B=%s"
            % ("?" if a is None else "%.2f" % a,
               "none" if not st["screenshot"] else "see above"))
        log("P23 DONE")
        print("P23 DONE")
        try:
            unreal.unregister_slate_post_tick_callback(st["handle"])
        except Exception:
            pass
        try:
            unreal.SystemLibrary.quit_editor()
        except Exception:
            pass


log("")
log("--- probing: 20 ticks to settle, then one of each ---")
STATE["handle"] = unreal.register_slate_post_tick_callback(tick)
