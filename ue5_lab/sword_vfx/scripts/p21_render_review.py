"""SEKAI Sword VFX - P21: render the QA cameras of L_SwordVFX_Lab to PNG.

WHY A SCENE CAPTURE AND NOT A SCREENSHOT

    A screenshot is whatever the window happens to be, clamped by the desktop,
    and its size is not reproducible between passes - so two passes cannot be
    compared and a later pass cannot be diffed against an earlier one. A
    SceneCapture2D renders into a RenderTarget at an EXACT resolution and hands
    back a texture, so the output is deterministic and headless-safe. This is the
    UE5 equivalent of the SubViewport rule the Godot line already follows.

CAMERAS COME FROM THE SCENE

    The shot list is read from the level's own `Review_*` actors. Hand-copied
    coordinates here would be a second copy of the framing, and the copy that is
    wrong would be the one used to shoot.

ONE CAMERA PER FRAME, AND WHY

    The capture reads the BACK BUFFER, so it must run after the frame has been
    drawn. Firing all five in one tick would give five copies of whichever frame
    was last on the GPU. So this walks the cameras one per tick, with a settle
    tick after the capture component is moved, and only then exports.

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p21_render_review.py --render

    --render, NOT --editor. This script aborts on a session without a
    rasterizer, because a SceneCapture2D cannot produce pixels without one; it
    says so in its own pre-flight and prints the command to re-run with.
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p21_render.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"

WIDTH = 1920
HEIGHT = 1080
SETTLE_TICKS = 8          # frames to let the moved capture draw (was 4: with
                          # continuous capture on, the shot is safe only once
                          # the target has been rewritten from the NEW position,
                          # and the first real-RHI session here ran at roughly
                          # four seconds per frame)
WARM_EVERY = 10           # ticks between render-target readiness probes
WARM_BUDGET = 300         # ticks we are willing to wait for a first real frame
WARM_MIN_LUMA = 1.0       # below this a frame is still the cleared value
TICK_BUDGET = 1200        # absolute ceiling; the editor must not be able to linger
MAX_TICK_ERRORS = 12      # give up rather than spin on one broken call
LOC_TOL_CM = 1.0          # a camera that did not move is not a camera
ROT_TOL_DEG = 0.5

LINES = []
try:
    open(EXPORT, "w", encoding="utf-8").close()
except Exception:
    pass


def log(msg=""):
    msg = str(msg)
    LINES.append(msg)
    print(msg)
    with open(EXPORT, "a", encoding="utf-8") as fh:
        fh.write(msg + "\n")


# Armed before anything can fail. This script has five early exits, and every
# one of them used to `raise SystemExit`, which in -ExecCmds mode leaves the
# editor running with no script attached - indistinguishable from a hang and
# needing a manual kill. The watchdog covers the exits that are not written by
# hand; `abort()` covers the ones that are.
WFX.bind_log(EXPORT, truncate=False)
WFX.install_watchdog(300)


def abort(msg):
    """Stop, and take the editor down with us."""
    log("")
    log("    ABORTING: %s" % msg)
    log("P21 ABORTED")
    print("P21 ABORTED")
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception:
        pass
    raise SystemExit(0)


def try_call(*fn_and_names):
    """First callable that works, with the name it worked under."""
    for name, fn in fn_and_names:
        try:
            return name, fn()
        except Exception as exc:
            log("      %s failed: %s" % (name, str(exc)[:140]))
    return None, None


def set_prop(obj, name, value):
    try:
        obj.set_editor_property(name, value)
        return True
    except Exception:
        return False


def vdist(a, b):
    """Euclidean distance, hand-rolled.

    Not `unreal.Vector.distance()` or `.length()`: this build has moved that
    method around more than once, and a wrong guess here would raise inside the
    verification path - which is the one place that must not raise, because its
    whole job is to report whether something else worked.
    """
    return ((a.x - b.x) ** 2 + (a.y - b.y) ** 2 + (a.z - b.z) ** 2) ** 0.5


def adiff(a, b):
    """Smallest absolute angle between two headings, in degrees, wrap-aware.

    Without the modulo a camera at yaw 179 and one at -179 reads as 358 degrees
    apart, which would fail a shot that is in fact correctly placed.
    """
    return abs((a - b + 180.0) % 360.0 - 180.0)


def move_capture(cc, cap, loc, rot):
    """Put the capture at a shot. Returns (ok, how, why).

    The arity of these setters is NOT uniform in this build. Measured, verbatim:

        TypeError: set_world_location_and_rotation() required argument
                   'sweep' (pos 3) not found

    so `sweep` is exposed as a REQUIRED positional here and the natural
    two-argument call raises instead of defaulting. Guessing one call shape is
    what broke the first run, and that failure was expensive in a way that makes
    a cascade worth it: the exception came from inside the TICK CALLBACK, so it
    fired once per frame for 954 frames and the editor never went down.

    The actor is tried first because the capture component IS the
    SceneCapture2D's root, so moving either moves the same transform - and the
    caller verifies against the actor either way.
    """
    attempts = (
        ("actor loc(1)+rot(2)",
         lambda: (cap.set_actor_location(loc),
                  cap.set_actor_rotation(rot, False))),
        ("actor loc(2)+rot(2)",
         lambda: (cap.set_actor_location(loc, False),
                  cap.set_actor_rotation(rot, False))),
        ("actor loc(3)+rot(2)",
         lambda: (cap.set_actor_location(loc, False, False),
                  cap.set_actor_rotation(rot, False))),
        ("comp loc+rot 4-arg",
         lambda: cc.set_world_location_and_rotation(loc, rot, False, False)),
        ("comp loc+rot 3-arg",
         lambda: cc.set_world_location_and_rotation(loc, rot, False)),
        ("comp loc+rot 2-arg",
         lambda: cc.set_world_location_and_rotation(loc, rot)),
        ("comp split(1)",
         lambda: (cc.set_world_location(loc), cc.set_world_rotation(rot))),
        ("comp split(2)",
         lambda: (cc.set_world_location(loc, False),
                  cc.set_world_rotation(rot, False))),
        ("comp split(3)",
         lambda: (cc.set_world_location(loc, False, False),
                  cc.set_world_rotation(rot, False, False))),
    )
    errs = []
    for how, fn in attempts:
        try:
            fn()
        except Exception as exc:
            errs.append("%s -> %s" % (how, str(exc)[:60]))
            continue
        return True, how, ""
    return False, "", " | ".join(errs)


def verify_shot(cap, loc, rot):
    """Read the capture ACTOR back and compare with the shot.

    This is the check that stops the render pass from lying to me. If the move
    is a no-op - wrong arity, a setter that returns without applying, a mobility
    refusal - the capture stays where it was and every shot exports the SAME
    frame under a different filename. The contact sheet would then show five
    plausible images, the log would say "5 frames", and the only way to notice
    would be to look at two of them side by side and wonder why the top-down
    camera has a horizon in it. That is the exact shape of failure this project
    keeps meeting: the log reports success and the pixels disagree.

    Returns ((dloc_cm, drot_deg), "") or (None, why) if the readback is
    unavailable - which is reported, not treated as a pass.
    """
    try:
        gl = cap.get_actor_location()
        gr = cap.get_actor_rotation()
    except Exception as exc:
        return None, str(exc)[:100]
    dl = vdist(gl, loc)
    dr = max(adiff(gr.pitch, rot.pitch),
             adiff(gr.yaw, rot.yaw),
             adiff(gr.roll, rot.roll))
    return (dl, dr), ""


def pin_post_process(cc):
    """Remove the two things that would move between passes, and nothing else.

    REVISED. The first version also pinned exposure - override flags ON with
    min = max = 1.0 and bias 0 - on the theory that a capture which re-frames
    its own exposure would make the bright-wall and dark-wall frames
    incomparable. The theory was sound and the execution was probably wrong:
    those two fields are the CD/m^2 bounds the exposure adapts WITHIN, so
    pinning both to 1.0 asks the camera to expose for a 1 cd/m^2 scene. A
    daylight level under that instruction comes out very nearly black.

    MEASURED, and it is why they are gone: five frames at mean luminance 0.10
    with five distinct byte values in the whole image. That is not a scene.

    Nothing is lost by removing them, because the exposure they were defending
    against cannot happen anyway: Config/DefaultEngine.ini already sets
    `r.DefaultFeature.AutoExposure=False` project-wide, so the capture inherits
    a fixed manual exposure. Overriding it here was solving an already-solved
    problem, and it introduced a variable into the one stage whose whole job is
    to be trustworthy.

    Bloom and motion blur stay off: both smear a VFX's true extent, and a review
    frame is supposed to show what the effect actually occupies.
    """
    try:
        pps = cc.get_editor_property("post_process_settings")
    except Exception as exc:
        log("    post_process_settings unreadable (%s)" % str(exc)[:80])
        return
    fields = (
        ("override_motion_blur_amount", True),
        ("motion_blur_amount", 0.0),
        ("override_bloom_intensity", True),
        ("bloom_intensity", 0.0),
    )
    pinned, missing = [], []
    for name, val in fields:
        try:
            pps.set_editor_property(name, val)
            pinned.append(name)
        except Exception:
            missing.append(name)
    wrote = True
    try:
        cc.set_editor_property("post_process_settings", pps)
    except Exception as exc:
        wrote = False
        log("    writing post_process_settings back failed: %s"
            % str(exc)[:100])
    log("    bloom/motion-blur pinned: %d / %d%s"
        % (len(pinned), len(fields), "" if wrote else " (NOT COMMITTED)"))
    if missing:
        log("    not available in PostProcessSettings: %s" % ", ".join(missing))
    log("    post_process_blend_weight: %s"
        % ("set" if set_prop(cc, "post_process_blend_weight", 1.0)
           else "NOT AVAILABLE"))
    log("    exposure: NOT overridden - the project already sets "
        "r.DefaultFeature.AutoExposure=False")
    try:
        log("    auto exposure method on the capture: %s"
            % cc.get_editor_property("post_process_settings")
                .get_editor_property("auto_exposure_method"))
    except Exception:
        pass


def actor_label(a):
    for getter in ("get_actor_label",):
        try:
            return getattr(a, getter)()
        except Exception:
            pass
    try:
        return a.get_name()
    except Exception:
        return ""


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


def spawn(cls, loc, rot=(0, 0, 0), label=None):
    for cls_name in ("EditorActorSubsystem", "EditorLevelLibrary"):
        try:
            sub = getattr(unreal, cls_name)()
            a = sub.spawn_actor_from_class(cls, unreal.Vector(*loc),
                                           unreal.Rotator(*rot))
            if a is not None:
                if label:
                    try:
                        a.set_actor_label(label)
                    except Exception:
                        pass
                return a
        except Exception:
            continue
    return None


log("engine: " + unreal.SystemLibrary.get_engine_version())

# Can this session produce pixels at all?
#
# MEASURED, and it is the reason this check exists: the first render pass ran
# under `-nullrhi` - the flag the authoring scripts use, which means "no
# rendering hardware interface", i.e. no rasterizer. Everything that does not
# need pixels worked perfectly: the shot list was read from the level, all five
# cameras were moved and verified, the exposure pin applied 10/10, and
# `capture_scene()` raised nothing. Then every single export reported
#
#     Review_FP export via RenderingLibrary.export_render_target  file=MISSING
#
# with no exception and zero bytes on disk. Nothing in that output says "there
# is no rasterizer"; it says "the export API is broken", which is the wrong
# place to go looking. So the session states its own capability up front, while
# the log is still short enough to read.
_nullrhi = False
try:
    _cmdline = unreal.SystemLibrary.get_command_line()
    _nullrhi = "-nullrhi" in str(_cmdline)
except Exception:
    pass
log("rasterizer : %s" % ("NONE (-nullrhi)" if _nullrhi else "available"))
if _nullrhi:
    abort("this session was started with -nullrhi, so there is no rasterizer "
          "and a SceneCapture2D cannot produce a single pixel. The exports "
          "would all report file=MISSING without raising anything.\n"
          "    re-run as:  ./run_ue.sh scripts/p21_render_review.py --render")

# ------------------------------------------------------------- load the map
loaded = False
for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
    try:
        getattr(unreal, how)().load_level(LVL)
        log("    level loaded via %s" % how)
        loaded = True
        break
    except Exception as exc:
        log("    load_level via %s failed: %s" % (how, str(exc)[:140]))
if not loaded:
    abort("could not load %s" % LVL)

W = world()
log("    world: %s" % ("ok" if W is not None else "NONE"))

# ------------------------------------------------------- the shot list
#
# Deduplicated by actor path. `get_all_level_actors()` returned every camera
# TWICE in this build - measured: the shot list came back with ten entries for
# five cameras, at identical positions. Rendering each camera twice would waste
# half the pass and, worse, produce a "10 frames" log that looks like more
# coverage than there is.
shots, seen_paths = [], set()
for a in all_actors():
    lbl = actor_label(a)
    if not lbl.startswith("Review_"):
        continue
    try:
        path = str(a.get_path_name())
    except Exception:
        path = lbl
    if path in seen_paths:
        continue
    seen_paths.add(path)
    comp = None
    for attr in ("camera_component",):
        try:
            comp = getattr(a, attr)
        except Exception:
            comp = None
    if comp is None:
        log("    %-16s has no camera component, skipped (a SceneCapture2D "
            "would land here)" % lbl)
        continue
    loc = a.get_actor_location()
    rot = a.get_actor_rotation()
    fov = None
    try:
        fov = comp.get_editor_property("field_of_view")
    except Exception:
        pass
    shots.append({"label": lbl, "loc": loc, "rot": rot, "fov": fov})
shots.sort(key=lambda s: s["label"])

log("")
log("--- shot list read from the level's Review_* anchors ---")
if not shots:
    abort("the level has no Review_* camera anchors. Sections 30/31 need "
          "L_SwordVFX_Lab built first - run p20a then p20.")
for s in shots:
    log("    %-16s (%7.1f,%7.1f,%7.1f)  pitch=%6.1f yaw=%6.1f  fov=%s"
        % (s["label"], s["loc"].x, s["loc"].y, s["loc"].z,
           s["rot"].pitch, s["rot"].yaw, s["fov"]))

# ------------------------------------------------------- render target
os.makedirs(OUT_DIR, exist_ok=True)
fmt = unreal.TextureRenderTargetFormat.RTF_RGBA8
name, rt = try_call(
    ("KismetRenderingLibrary.create_render_target2d",
     lambda: unreal.KismetRenderingLibrary.create_render_target2d(
         W, WIDTH, HEIGHT, fmt)),
    ("RenderingLibrary.create_render_target2d",
     lambda: unreal.RenderingLibrary.create_render_target2d(
         W, WIDTH, HEIGHT, fmt)),
)
if rt is None:
    abort("could not create a %dx%d render target" % (WIDTH, HEIGHT))
log("")
log("--- render target ---")
log("    %dx%d via %s" % (WIDTH, HEIGHT, name))

# ------------------------------------------------------- capture actor
cap = spawn(unreal.SceneCapture2D, (0, 0, 0), label="Review_Capture")
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
    abort("the SceneCapture2D has no capture component")

# A Static component refuses to be moved, and it refuses by doing nothing -
# there is no exception, so it would present as a no-op move rather than a
# failure. Spawned actors normally inherit Movable, but this is one line and it
# removes a whole class of silent failure before the loop starts.
try:
    cc.set_mobility(unreal.ComponentMobility.MOVABLE)
    log("    capture mobility: MOVABLE")
except Exception as exc:
    log("    capture mobility NOT SET (%s)" % str(exc)[:80])
    log("      a static capture would silently refuse to move; the readback "
        "check will catch it, but the frames would be lost")

# ------------------------------------------------------- capture wiring
#
# EVERY one of these results is logged, and that is the point.
#
# MEASURED, and it cost a whole pass: with a real rasterizer, five valid PNGs
# came back at exactly 439,995 bytes each, and decoding them gave
#
#     mean luminance 0.10, and only TWO distinct luma values in the whole
#     1920x1080 frame (0 and 1)
#
# i.e. every frame was the render target's cleared value and nothing had ever
# rendered into it. `capture_scene()` raised nothing and the shot list, camera
# moves and readback verification had all passed, so the log looked healthy.
#
# The one thing that could produce exactly that is `texture_target` never being
# set - and its result was the only `set_prop` in this file whose return value
# was discarded. A property that is silently not applied is indistinguishable
# from one that is, right up until you decode the pixels. So: no set_prop on the
# capture component goes unchecked any more, and texture_target is read back and
# compared against the render target we actually created.
log("")
log("--- capture component wiring ---")


def wire(prop, value, expect=None):
    """Set a capture property and report whether it took, with readback."""
    ok = set_prop(cc, prop, value)
    back = "?"
    if expect is not None:
        try:
            cur = cc.get_editor_property(prop)
            back = "readback ok" if cur == expect else "readback %r" % (cur,)
        except Exception as exc:
            back = "readback failed (%s)" % str(exc)[:40]
    log("    %-28s %s" % (prop, "set" if ok else "FAILED - NOT APPLIED"
                         + ("" if expect is None else ", " + back)))
    return ok


wire("texture_target", rt, rt)
try:
    _cur = cc.get_editor_property("texture_target")
    log("    texture_target is %s"
        % ("the render target we made" if _cur == rt
           else ("NONE - NOTHING WILL EVER RENDER" if _cur is None
                 else repr(_cur))))
except Exception as exc:
    log("    texture_target unreadable: %s" % str(exc)[:80])

try:
    log("    component registered: %s" % cc.is_registered())
except Exception as exc:
    log("    is_registered unavailable: %s" % str(exc)[:60])

# The capture is driven by the ENGINE's own path, not by a manual
# `capture_scene()` call per shot.
#
# Reason: a manual CaptureScene is a single fire-and-forget request, and the
# first real-RHI session on this machine ran at roughly four seconds per frame
# while shaders compiled. Anything that silently no-ops once has no second
# chance, and the evidence above says exactly that happened. `capture_every_frame`
# asks the component to re-capture on every rendered frame, so by the time the
# settle window below elapses the target is being written continuously and a
# stale-or-empty read is not possible.
#
# The cost is real and accepted: five 1080p captures per frame while this script
# runs. It is a review stage, not the shipping build.
wire("capture_every_frame", True)
wire("capture_on_movement", False)

# Show flags: the classic reason a programmatically spawned scene capture
# renders nothing at all.
#
# A capture component built through the editor's own capture-actor factory gets
# a default set of show flags. One created with NewObject does not necessarily,
# and "every flag off" renders an empty scene - which is byte-for-byte
# indistinguishable from a render target that was never drawn into. Since the
# previous pass produced exactly that and had its target correctly wired, this
# is read out rather than assumed.
try:
    _sf = cc.get_editor_property("show_flags")
    _keys = ("atmosphere", "fog", "static_meshes", "skeletal_meshes",
             "particles", "translucency", "post_processing", "bloom",
             "tonemapper", "eye_adaptation", "direct_lighting")
    _on, _off = [], []
    for _k in _keys:
        try:
            (_on if _sf.get_editor_property(_k) else _off).append(_k)
        except Exception:
            _off.append(_k + "(unreadable)")
    log("    show flags ON : %s" % (", ".join(_on) if _on else "NONE"))
    log("    show flags OFF: %s" % (", ".join(_off) if _off else "none"))
    if not _on:
        log("      EVERY SHOW FLAG IS OFF - this capture can only ever produce "
            "an empty frame")
except Exception as exc:
    log("    show_flags unreadable: %s" % str(exc)[:100])
log("")
log("--- post process pin (bright/dark comparability) ---")
pin_post_process(cc)

# Final colour, not the HDR source: the review is about the picture the player
# sees, and an HDR read-back would need its own tone mapping to be meaningful.
for cand in ("SCS_FINAL_COLOR_LDR", "SCS_FINAL_TONE_CURVE", "SCS_FINAL_COLOR_HDR"):
    src = getattr(unreal.SceneCaptureSource, cand, None)
    if src is not None and set_prop(cc, "capture_source", src):
        log("    capture source: %s" % cand)
        break

STATE = {"i": 0, "settle": 0, "place_tries": 0, "phase": "warm", "done": [],
         "failed": [], "unverified": [], "handle": None, "ticks": 0,
         "tick_errors": 0, "seen_errors": set(), "handed_over": False,
         "frames": [], "warm_ticks": 0}


def _probe_target():
    """Export the current target to a scratch file and return its mean luma.

    Only used during warm-up, to answer "does the capture contain an image yet"
    before spending the whole shot list on a target that is still holding its
    cleared value. Returns None when the export or the probe fails, which is
    reported by the caller rather than treated as a pass.
    """
    scratch = "_warm"
    try_call(
        ("RenderingLibrary.export_render_target",
         lambda: unreal.RenderingLibrary.export_render_target(
             W, rt, OUT_DIR, scratch)),
    )
    path = _collect(scratch)
    if not path:
        return None
    try:
        probe = _png_probe(path)
    finally:
        try:
            os.remove(path)
        except Exception:
            pass
    return None if probe is None else probe[2]


def _collect(fname):
    """Find what the engine wrote, and normalise it to <fname>.png.

    MEASURED: `RenderingLibrary.export_render_target(W, rt, dir, "review_fp")`
    writes a perfectly valid PNG at `dir/review_fp` - with NO extension. Only
    the name is wrong. So a check for `review_fp.png` reports MISSING while five
    real frames sit on disk, and the natural next move is to go and debug the
    export API, which is working fine.

    Those five frames were also all black, which is a separate fault - but this
    is what hid it.
    """
    plain = os.path.join(OUT_DIR, fname)
    dotted = plain + ".png"
    if os.path.exists(dotted) and os.path.getsize(dotted) > 0:
        return dotted
    if os.path.exists(plain) and os.path.getsize(plain) > 0:
        try:
            os.replace(plain, dotted)   # the extension every tool downstream wants
            return dotted
        except Exception:
            return plain
    return None


def _png_probe(path):
    """(width, height, mean_luma, distinct_byte_values) for an 8-bit PNG.

    Deliberately minimal, and hand-rolled because this runs inside the engine's
    Python, which has no image library. It answers exactly one question: is this
    frame a flat block of the render target's clear colour, or is there an image
    in it?

    THE UNFILTERING IS NOT OPTIONAL. PNG scanlines are stored with a per-row
    filter - Sub, Up, Average, Paeth - so the decompressed IDAT stream holds
    DELTAS, not pixels. A first version of this function sampled that stream
    directly and reported mean luma 2.44 for a frame that PIL measures at 0.10.
    The number looked plausible and was meaningless. Since the entire point of
    this function is to be the check nobody else performs, a plausible wrong
    number is worse than no number: it would have passed black frames.

    Verified against PIL on the five known-black frames from the first pass:
    both report mean 0.10. That comparison is why the filter reconstruction
    below is trusted.
    """
    import struct
    import zlib
    try:
        blob = open(path, "rb").read()
    except Exception:
        return None
    if blob[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    pos, idat, w, h, bitd, ctype = 8, [], 0, 0, 8, 6
    while pos + 8 <= len(blob):
        ln = struct.unpack(">I", blob[pos:pos + 4])[0]
        typ = blob[pos + 4:pos + 8]
        data = blob[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, bitd, ctype = struct.unpack(">IIBB", data[:10])
        elif typ == b"IDAT":
            idat.append(data)
        elif typ == b"IEND":
            break
        pos += 12 + ln
    try:
        raw = zlib.decompress(b"".join(idat))
    except Exception:
        return (w, h, None, None)
    if bitd != 8:
        # A 16-bit target cannot be judged with this shortcut; report the shape
        # and leave the numbers None rather than inventing a scale factor.
        return (w, h, None, None)
    step = {0: 1, 2: 3, 4: 2, 6: 4}.get(ctype)
    if step is None or w <= 0 or h <= 0:
        return (w, h, None, None)
    stride = w * step
    if len(raw) < h * (stride + 1):
        return (w, h, None, None)

    prev = bytearray(stride)
    total, n = 0, 0
    for y in range(h):
        base = y * (stride + 1)
        ftype = raw[base]
        line = bytearray(raw[base + 1:base + 1 + stride])
        if ftype == 1:                      # Sub
            for i in range(step, stride):
                line[i] = (line[i] + line[i - step]) & 0xFF
        elif ftype == 2:                    # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:                    # Average
            for i in range(stride):
                a = line[i - step] if i >= step else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:                    # Paeth
            for i in range(stride):
                a = line[i - step] if i >= step else 0
                b = prev[i]
                c = prev[i - step] if i >= step else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        elif ftype != 0:
            return (w, h, None, None)
        prev = line
        if y % 3 == 0:                      # every third row is plenty
            for x in range(0, max(1, stride - step + 1), step * 3):
                if step >= 3:
                    r, g, b = line[x], line[x + 1], line[x + 2]
                else:
                    r = g = b = line[x]
                total += (r * 299 + g * 587 + b * 114) // 1000
                n += 1
    distinct = len(set(raw[i] for i in range(0, len(raw),
                                             max(1, len(raw) // 200000))))
    return (w, h, (float(total) / n) if n else None, distinct)


def _check_frames():
    """Refuse to call this pass successful when the frames hold no image.

    This is the assertion whose absence let a whole pass report "5 frames
    written" for five black images. Every other signal was healthy: valid PNG
    headers, plausible byte counts (all 439,995, which should itself have been
    a clue), the shot list read from the level, camera moves verified against
    readback, and a 10/10 exposure pin.

    A pass that hands back five black frames is worse than one that fails,
    because the failure is discovered later, by eye, and by then the graph has
    been blamed for it.
    """
    if not STATE["frames"]:
        return False
    import hashlib
    log("")
    log("--- frame check (is there an image in these) ---")
    digests, lumas = {}, {}
    for label, path, size in STATE["frames"]:
        try:
            digest = hashlib.md5(open(path, "rb").read()).hexdigest()
        except Exception:
            digest = "unreadable-%s" % label
        digests.setdefault(digest, []).append(label)
        probe = _png_probe(path)
        if probe is None:
            log("    %-16s not a PNG" % label)
            continue
        w, h, mean, distinct = probe
        lumas[label] = mean
        log("    %-16s %dx%d  mean_luma=%-7s distinct_values=%s"
            % (label, w, h,
               "?" if mean is None else "%.2f" % mean,
               "?" if distinct is None else distinct))
    bad = False
    for digest, labels in digests.items():
        if len(labels) > 1:
            bad = True
            log("    IDENTICAL BYTES: %s - one camera's frame is another "
                "camera's frame" % ", ".join(labels))
    flat = sorted(l for l, m in lumas.items() if m is not None and m < 1.0)
    if flat:
        bad = True
        log("    NO IMAGE (mean luma ~0): %s" % ", ".join(flat))
        log("      a frame at mean 0 is the render target's cleared value, so")
        log("      nothing was ever rendered into it. Check the capture")
        log("      wiring above for a FAILED texture_target before looking")
        log("      anywhere else.")
    if not bad:
        log("    frames look like frames: distinct bytes, non-zero luma")
    return bad


def _finish(reason):
    """Emit the summary and take the editor down. Idempotent."""
    st = STATE
    st["phase"] = "closed"
    log("")
    log("--- export complete (%s) ---" % reason)
    for d in st["done"]:
        log("    %s" % d)
    if st["unverified"]:
        log("    position NOT confirmed by readback: %s"
            % ", ".join(st["unverified"]))
    if st["failed"]:
        log("    FAILED: %s" % ", ".join(st["failed"]))
    if st["handle"] is not None:
        try:
            unreal.unregister_slate_post_tick_callback(st["handle"])
        except Exception:
            pass
    log("    ticks used: %d, tick errors: %d"
        % (st["ticks"], st["tick_errors"]))
    hollow = _check_frames()
    if hollow:
        log("")
        log("    These frames are NOT a review. They are written, and every")
        log("    other step reported success, which is exactly why this check")
        log("    exists rather than being left to a later glance.")
        log("P21 VERDICT  : %d FRAMES WRITTEN BUT HOLLOW - do not review"
            % len(st["done"]))
    elif st["failed"]:
        log("P21 VERDICT  : %d frames written, %d failed"
            % (len(st["done"]), len(st["failed"])))
    else:
        log("P21 VERDICT  : %d frames written" % len(st["done"]))
    log("P21 DONE")
    print("P21 DONE")
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception:
        pass


def _on_tick_error(exc):
    """Last-resort handler for anything raised inside the tick callback.

    This exists because of a measured failure that the watchdog could not have
    caught. An exception raised in the SCRIPT BODY during an -ExecCmds editor
    session is logged and then swallowed, which is why the watchdog was built.
    An exception raised inside a SLATE TICK CALLBACK behaves differently: it
    propagates out of the callback, so the callback's own finish branch is never
    reached, and it is simply raised again on the next tick - measured: 954
    consecutive frames, one identical traceback each, and an editor that stayed
    up until it was killed. From the outside that is indistinguishable from a
    hang, and there is no counter inside the failing code to notice.

    So: report the first occurrence of each distinct message WITH its traceback
    (the traceback is the only thing that says which call), spend one shot, and
    stop after MAX_TICK_ERRORS rather than spinning.
    """
    st = STATE
    where = shots[st["i"]]["label"] if st["i"] < len(shots) else "-"
    text = "%s: %s" % (type(exc).__name__, exc)
    log("    %-16s TICK ERROR %s" % (where, text[:150]))
    if text not in st["seen_errors"]:
        st["seen_errors"].add(text)
        import traceback
        log("      first occurrence; traceback:")
        for line in traceback.format_exc().rstrip().splitlines():
            log("        " + line.strip())
    st["tick_errors"] += 1
    if st["i"] < len(shots):
        # Spend the shot rather than retrying it forever: a retry loop on a
        # deterministic error always burns the tick budget and writes nothing.
        st["failed"].append("%s (tick error)" % shots[st["i"]]["label"])
        st["i"] += 1
    st["settle"] = 0
    st["place_tries"] = 0
    st["phase"] = "place"
    if st["tick_errors"] > MAX_TICK_ERRORS:
        log("    more than %d tick errors; stopping" % MAX_TICK_ERRORS)
        _finish("tick error budget")


def _body(delta):
    st = STATE
    if st["i"] >= len(shots):
        _finish("complete")
        return

    shot = shots[st["i"]]

    # ------------------------------------------------------------- warm-up
    #
    # Do not spend the shot list until the render target is known to contain an
    # image. MEASURED: two consecutive passes wrote five valid, correctly sized
    # PNGs whose content was the target's cleared value. In the first of those
    # the capture target was correctly wired the whole time, so "the wiring is
    # right" is not evidence that anything rendered.
    #
    # The check is a real one - export the target and measure the pixels with
    # _png_probe - rather than "wait N frames and hope". It is also the only
    # honest way to handle the other possibility: this editor ran at roughly two
    # to four SECONDS per frame during its first real-RHI session while shaders
    # compiled, so a fixed settle count can expire long before the scene has
    # ever been drawn.
    if st["phase"] == "warm":
        st["warm_ticks"] += 1
        if st["warm_ticks"] % WARM_EVERY:
            return
        first = shots[0]
        move_capture(cc, cap, first["loc"], first["rot"])
        if first["fov"]:
            set_prop(cc, "fov_angle", first["fov"])
        set_prop(cc, "capture_every_frame", True)
        # EXPLICIT capture_scene(), AND THIS IS WHY THE WARM-UP WAS DEADLOCKED.
        #
        # `capture_every_frame=True` WAS MEASURED TO WRITE NOTHING into the
        # target over 15 ticks with the readback confirmed True, while an
        # explicit `cc.capture_scene()` does write. Every later probe in this
        # project (p24-p27, p29) works by calling it explicitly, and p29
        # produced 2902-colour frames this way.
        #
        # This warm-up waited on capture_every_frame instead, so the gate it
        # guards could never open: it logged "mean luma 0.10" - the cleared
        # value - 30 times over 136 seconds and then declared that "rendering
        # into a SceneCapture2D is failing, not slow". The conclusion was drawn
        # from a configuration that had no way to succeed.
        try:
            cc.capture_scene()
        except Exception as exc:
            log("    warm-up capture_scene FAILED: %s" % str(exc)[:120])
        mean = _probe_target()
        elapsed = time.time() - st.get("t0", time.time())
        log("    warm-up %4d ticks  mean luma %-6s  (%.0f s wall)"
            % (st["warm_ticks"], "?" if mean is None else "%.2f" % mean,
               elapsed))
        if mean is not None and mean >= WARM_MIN_LUMA:
            log("    the target has an image in it after %d ticks / %.0f s - "
                "starting the shot list" % (st["warm_ticks"], elapsed))
            st["phase"] = "place"
            return
        if st["warm_ticks"] >= WARM_BUDGET:
            log("")
            log("    NO IMAGE after %d ticks, with an explicit capture_scene() "
                "on every probe." % st["warm_ticks"])
            log("    Reaching this line no longer means 'nothing renders' on its")
            log("    own: it means the target still reads as its cleared value")
            log("    even though a capture was requested. Check that the level is")
            log("    LIT before blaming the capture path - p29 MEASURED that a sun")
            log("    aimed at the sky gives mean 0.10 at any intensity, and a sun")
            log("    aimed down gives 43-79 for the same level.")
            _finish("warm-up failed")
        return

    if st["phase"] == "place":
        moved, how, why = move_capture(cc, cap, shot["loc"], shot["rot"])
        if not moved:
            log("    %-16s MOVE FAILED (every arity refused)" % shot["label"])
            log("      %s" % why[:400])
            st["failed"].append("%s (move)" % shot["label"])
            st["i"] += 1
            st["place_tries"] = 0
            return
        if st["place_tries"] == 0:
            log("    %-16s placed via %s" % (shot["label"], how))
        if shot["fov"]:
            set_prop(cc, "fov_angle", shot["fov"])
        st["place_tries"] += 1

        # Verify BEFORE spending frames on the shot. See verify_shot().
        delta, why = verify_shot(cap, shot["loc"], shot["rot"])
        if delta is None:
            # Readback unavailable. Do not pretend it passed - record it and
            # continue, because refusing outright would block every frame on an
            # API detail rather than on anything about the VFX.
            if st["place_tries"] == 1:
                log("    %-16s position UNVERIFIED (%s)"
                    % (shot["label"], why))
                st["unverified"].append(shot["label"])
            st["settle"] = 0
            st["phase"] = "settle"
            return
        dl, dr = delta
        if dl > LOC_TOL_CM or dr > ROT_TOL_DEG:
            # The move reported success and did not happen. Exporting now would
            # write a duplicate of the previous camera's frame under this
            # camera's name, so this is a hard skip, not a warning.
            log("    %-16s MOVE DID NOT TAKE: off by %.1f cm / %.1f deg"
                % (shot["label"], dl, dr))
            log("      expected (%.1f,%.1f,%.1f) pitch=%.1f yaw=%.1f"
                % (shot["loc"].x, shot["loc"].y, shot["loc"].z,
                   shot["rot"].pitch, shot["rot"].yaw))
            try:
                gl, gr = cap.get_actor_location(), cap.get_actor_rotation()
                log("      actual   (%.1f,%.1f,%.1f) pitch=%.1f yaw=%.1f"
                    % (gl.x, gl.y, gl.z, gr.pitch, gr.yaw))
            except Exception:
                pass
            log("      not exporting this frame: a frame from the wrong camera "
                "is worse than a missing one")
            st["failed"].append("%s (move no-op)" % shot["label"])
            st["i"] += 1
            st["place_tries"] = 0
            return
        st["settle"] = 0
        st["phase"] = "settle"
        return

    if st["phase"] == "settle":
        st["settle"] += 1
        if st["settle"] < SETTLE_TICKS:
            return
        try:
            cc.capture_scene()
        except Exception as exc:
            # Skip the shot and keep walking. An earlier revision set a phase
            # ("export") that no branch handled, which stalled the state machine
            # forever on the first failure - a silent hang produced by error
            # handling, which is the worst kind. Failing loudly is also wrong
            # here: one bad camera should not cost the other four frames.
            log("    %-16s capture_scene FAILED: %s"
                % (shot["label"], str(exc)[:140]))
            st["failed"].append(shot["label"])
            st["i"] += 1
            st["phase"] = "place"
            st["place_tries"] = 0
            return
        # Re-assert continuous capture straight after the explicit one. Some
        # builds make CaptureScene() clear bCaptureEveryFrame, and if that
        # happens here the target would go stale on the NEXT shot with nothing
        # reporting it - the same silent-stale shape as the fault this whole
        # section was rewritten to fix. Re-asserting is idempotent and cheap.
        set_prop(cc, "capture_every_frame", True)
        st["phase"] = "post"
        return

    if st["phase"] == "post":
        # The capture reads the back buffer, so the frame it asked for has not
        # been produced yet on the tick it asked. Wait one more draw.
        fname = "review_%s" % shot["label"].replace("Review_", "").lower()
        ok_name, res = try_call(
            ("KismetRenderingLibrary.export_render_target",
             lambda: unreal.KismetRenderingLibrary.export_render_target(
                 W, rt, OUT_DIR, fname)),
            ("RenderingLibrary.export_render_target",
             lambda: unreal.RenderingLibrary.export_render_target(
                 W, rt, OUT_DIR, fname)),
        )
        path = _collect(fname)
        if path:
            size = os.path.getsize(path)
            log("    %-16s export via %-34s ok (%d bytes)"
                % (shot["label"], ok_name, size))
            st["done"].append("%s -> %s" % (shot["label"], path))
            st["frames"].append((shot["label"], path, size))
        else:
            log("    %-16s export via %-34s NO FILE (looked for %s and %s.png)"
                % (shot["label"], ok_name, fname, fname))
            st["failed"].append("%s (export)" % shot["label"])
        st["i"] += 1
        st["phase"] = "place"
        st["place_tries"] = 0
        return


def _tick(delta):
    st = STATE
    if st["phase"] == "closed":
        # Re-entrancy guard. Unregistering can fail, and without this the
        # completion branch would re-log its whole summary every frame until
        # the editor went down - making a clean finish look like a loop.
        return
    st["ticks"] += 1
    if st["ticks"] > TICK_BUDGET:
        log("    TICK BUDGET EXHAUSTED after %d ticks - stopping so the editor "
            "cannot linger" % st["ticks"])
        _finish("tick budget")
        return
    ok = True
    try:
        _body(delta)
    except Exception as exc:
        ok = False
        _on_tick_error(exc)
    if ok and not st["handed_over"]:
        # Disarm the watchdog only once the callback has been seen to complete
        # a tick. Calling it before the loop - which the first revision did -
        # disarms the only net that could catch "the callback never fires at
        # all", and this script's deadline is the callback, not the body.
        st["handed_over"] = True
        WFX.watchdog_handover()


log("")
log("--- rendering %d cameras, one per frame ---" % len(shots))
log("    first a warm-up: the target must contain an image before the shot "
    "list is spent")
STATE["t0"] = time.time()
STATE["handle"] = unreal.register_slate_post_tick_callback(_tick)
