"""SEKAI Sword VFX - P29: the lighting recipe for L_SwordVFX_VLab, and why P27 lied.

WHAT P27 ESTABLISHED, AND WHAT IT GOT WRONG

    P27's own verdict line reads:

        => the fresh light WAS the cause. Setting properties on the
           pre-existing lights does not light this scene; P20 must build
           the light differently, not merely reconfigure it.

    THAT VERDICT IS NOT SUPPORTED BY P27's OWN NUMBERS, and the defect is a
    comparing-across-instruments error - the same class of mistake this project
    has already named and paid for.

    Read P27's rungs again, in order:

        [1] baseline, SCENE_COLOR_HDR                        BLACK  (0.00)
        [2] Lab_Sun light_color=white, intensity=100000      BLACK  (0.00)
            SCENE_COLOR_HDR
        [3] + fresh sun 100000, SCENE_COLOR_HDR              BLACK  (0.45)
        [4] MINUS-ONE: destroy fresh sun, SCENE_COLOR_HDR    BLACK  (0.00)
        [5] re-spawn fresh sun, FINAL_COLOR_LDR              GOOD   (78.56)
        [6] Lab_Sun intensity -> 3000, FINAL_COLOR_LDR       DIM    (6.50)
        [7] Lab_Sun intensity -> 300                         DIM    (1.46)
        [8] Lab_Sun intensity -> 30                          DIM    (0.59)
        [9] Lab_Sun intensity -> 3                           DIM    (0.39)
        [10] same state again                                DIM    (0.39)

    Rungs 6-9 change LAB_SUN's intensity and nothing else. The fresh sun was
    spawned at rung 5 and never destroyed again. And the image tracks LAB_SUN's
    intensity all the way down to 3 - which means the fresh sun was contributing
    essentially NOTHING, and LAB_SUN is the light that drives this frame after
    all. Rung 9 (fresh sun at 100000, Lab_Sun at 3) landing at 0.39 is the
    clean evidence: if the fresh sun were the source, that rung could not be
    black.

    So the MINUS-ONE rung - the one the verdict was built on - is worthless here,
    because it was measured on SCENE_COLOR_HDR while the conclusion was drawn
    about FINAL_COLOR_LDR. Comparing rung 4 (instrument A) with rung 5
    (instrument B) says nothing about the light.

    Rung 3's 0.45 is the tell that SCENE_COLOR_HDR is a bad instrument: a scene
    that FINAL_COLOR_LDR shows at mean 78 reads as 0.45 there. That source is
    near-useless as a brightness readout and must not be used as one.

THE ROOT CAUSE P27 WALKED PAST, AND WHY THIS PROBE IS SHAPED LIKE THIS

    p20_review_map.py builds its sun like this:

        sun = spawn(unreal.DirectionalLight, (0, 0, 800), (-42.0, 35.0, 0.0),
                    "Lab_Sun")

    and `spawn()` does:

        r = rot if isinstance(rot, unreal.Rotator) else unreal.Rotator(*rot)

    `unreal.Rotator(*t)` expands a tuple as (ROLL, PITCH, YAW). So the author's
    intent - the natural reading (pitch=-42, yaw=35, roll=0) - became
    ROLL=-42, PITCH=+35, YAW=0.

    PITCH=+35 points the light's forward vector UP AND BEHIND: the sun shines
    into the sky. THE GROUND IS NEVER LIT. That single sign is the whole
    "unlit lab".

    AND THE TRAP IS ALREADY DOCUMENTED IN THAT SAME FILE, four lines above the
    `spawn()` it defeats: "`unreal.Rotator(*t)` expands a tuple in (ROLL, PITCH,
    YAW) order - not the (pitch, yaw, roll) order the rest of this file reads
    naturally. The first version of `camera()` built the tuple as (pitch, yaw,
    roll), so every review camera came out rolled instead of turned". The
    docstring was written, `camera()` was fixed - and the sun, which passes a
    tuple to the very same helper on the very next screen, was not.

    P27 then spawned its fresh sun with `unreal.Rotator(0.0, 35.0, 20.0)` -
    also PITCH=+35, also pointing up - so its "fresh light" was aimed at the sky
    too, which is exactly why it contributed nothing while its intensity read
    back as 100000.0. The intensity readback was honest; the intensity was
    simply being radiated into space.

    Hence: THIS PROBE VARIES THE LIGHT'S ROTATION FIRST, on a fixed camera and a
    single instrument, and it measures the TOP and BOTTOM of the frame
    SEPARATELY. A global mean cannot tell "the sky got brighter" from "the
    ground got lit", and that difference is the entire question - section 30's
    bright-wall premise is about the surface behind the effect, not the sky.

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p29_light_recipe.py --render
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p29_lightrecipe.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/recipe')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
RT_W, RT_H = 512, 512
GREEN_RGB = (0, 255, 0)
WAIT = 10

# ONE instrument for every rung. P27's failure was mixing two.
INSTRUMENT = "SCS_FINAL_COLOR_LDR"

LINES = []


def log(msg=""):
    msg = str(msg)
    LINES.append(msg)
    print(msg)
    try:
        with open(EXPORT, "a", encoding="utf-8") as fh:
            fh.write(msg + "\n")
    except Exception:
        pass
    try:
        unreal.log("P29 " + msg)
    except Exception:
        pass


open(EXPORT, "w", encoding="utf-8").close()
WFX.bind_log(EXPORT, truncate=False)


def abort(msg):
    log("")
    log("    ABORTING: %s" % msg)
    log("P29 ABORTED")
    print("P29 ABORTED")
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


def spawn(cls, loc, rot, label=None):
    for name, obj in subsystems():
        if not hasattr(obj, "spawn_actor_from_class"):
            continue
        try:
            a = obj.spawn_actor_from_class(cls, loc, rot)
            if label and a is not None:
                try:
                    a.set_actor_label(label)
                except Exception:
                    pass
            return a
        except Exception:
            continue
    return None


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
    abort("no editor world")
os.makedirs(OUT_DIR, exist_ok=True)
ACTORS = all_actors()

# --- find the level's own lights ------------------------------------------
log("")
log("--- as-found lights: ROTATION IS THE WHOLE POINT ---")
SUN = SKY = None
for a in ACTORS:
    try:
        cls = a.get_class().get_name()
        label = a.get_actor_label()
    except Exception:
        continue
    if "Light" not in cls:
        continue
    comp = None
    for attr in ("light_component", "sky_light_component", "component"):
        try:
            comp = getattr(a, attr)
            break
        except Exception:
            continue
    if comp is None:
        continue
    loc = rot = None
    try:
        loc, rot = a.get_actor_location(), a.get_actor_rotation()
    except Exception:
        pass
    log("    %s (%s)" % (label, cls))
    if rot is not None:
        # Read the components EXPLICITLY: `unreal.Rotator` is not iterable, and
        # the tuple form is the trap being investigated.
        log("        actor rotation  pitch=%.2f  yaw=%.2f  roll=%.2f"
            % (rot.pitch, rot.yaw, rot.roll))
    if loc is not None:
        log("        loc             x=%.1f y=%.1f z=%.1f" % (loc.x, loc.y, loc.z))
    for p in ("mobility", "intensity", "light_color", "visible",
              "affects_world", "cast_shadows", "real_time_capture",
              "source_type"):
        ok, val = swcap.get_prop(comp, p)
        if ok:
            log("        %-20s = %s" % (p, val))
    if "DirectionalLight" in cls and SUN is None:
        SUN = {"actor": a, "comp": comp, "label": label}
    if "SkyLight" in cls and SKY is None:
        SKY = {"actor": a, "comp": comp, "label": label}

if SUN is None:
    # NOT an abort. If the level has no directional light, the recipe includes
    # making one - so the probe does it, in the KEYWORD form, and tests it.
    # Aborting here would refuse to answer the question this file exists for.
    log("")
    log("    NO DIRECTIONAL LIGHT IN THE LEVEL - spawning one as part of the")
    log("    recipe (this is also what P20 must do):")
    a = spawn(unreal.DirectionalLight, unreal.Vector(0, 0, 800),
              unreal.Rotator(pitch=-45.0, yaw=35.0, roll=0.0), "P29_Sun")
    if a is None:
        abort("no directional light, and could not spawn one")
    comp = a.light_component
    swcap.set_prop(comp, "mobility",
                   getattr(unreal.ComponentMobility, "MOVABLE", None))
    swcap.set_prop(comp, "cast_shadows", False)
    SUN = {"actor": a, "comp": comp, "label": "P29_Sun"}
    r = a.get_actor_rotation()
    log("    spawned P29_Sun  pitch=%.1f yaw=%.1f roll=%.1f  intensity=%s"
        % (r.pitch, r.yaw, r.roll, swcap.get_prop(comp, "intensity")[1]))
log("")
log("    sun in use: %s" % SUN["label"])
try:
    r = SUN["actor"].get_actor_rotation()
    log("    ITS PITCH IS %+.1f. A sun that lights the ground points DOWN." % r.pitch)
    if r.pitch > 0:
        log("    => POSITIVE PITCH: this sun is aimed at the SKY. The ground")
        log("       cannot be lit by it at any intensity. This is the bug.")
except Exception as exc:
    log("    rotation unreadable: %s" % str(exc)[:120])

# --- capture --------------------------------------------------------------
cam_loc = cam_rot = None
for a in ACTORS:
    try:
        if a.get_actor_label() == "Review_TP34":
            cam_loc, cam_rot = a.get_actor_location(), a.get_actor_rotation()
            break
    except Exception:
        continue
if cam_loc is None:
    # NOT an abort. A missing anchor is a fact about the level, not a reason to
    # refuse to answer a lighting question - and this probe's whole result set
    # would otherwise be traded away for a shot-list detail. So it reports and
    # uses a documented fallback: the FP pose the brief specifies.
    log("")
    log("    WARNING: Review_TP34 is not in the level. Falling back to the")
    log("    section-31 FP pose (0, 0, 170) looking along +X, and saying so.")
    cam_loc = unreal.Vector(0.0, 0.0, 170.0)
    cam_rot = unreal.Rotator(pitch=0.0, yaw=0.0, roll=0.0)

rt = swcap.make_rt(W, RT_W, RT_H)
cap = spawn(unreal.SceneCapture2D, unreal.Vector(0, 0, 200),
            unreal.Rotator(0, 0, 0), "P29_Capture")
if cap is None:
    abort("could not spawn a capture")
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
ok, why = swcap.place_capture(cc, cap, cam_loc, cam_rot)
if not ok:
    abort("the capture will not go where the shot is: %s" % why)
_src = getattr(unreal.SceneCaptureSource, INSTRUMENT, None)
swcap.set_prop(cc, "capture_source", _src)
log("")
log("capture at Review_TP34, instrument fixed at %s for EVERY rung"
    % INSTRUMENT)
swcap.clear_rt(W, rt)   # first clear never takes
swcap.clear_rt(W, rt)

MEASURED = {"n": 0}


def read_rows():
    """Sample horizontal rows of the target, to split sky from ground.

    A GLOBAL MEAN CANNOT ANSWER THIS PROBE'S QUESTION. "The sky got brighter"
    and "the ground got lit" both raise the mean, and section 30 asks about the
    SURFACE behind the effect. So this reads five rows - top of frame to bottom
    - and reports them separately, plus the top-third and bottom-third means.

    Uses read_render_target_pixel if this build has it. If it does not, the
    rows come back empty and the host-side PNG split (tools/split_luma.py) is
    the fallback; the probe says which happened rather than pretending.
    """
    fn = getattr(unreal.RenderingLibrary, "read_render_target_pixel", None)
    if fn is None:
        return None
    rows = []
    for frac in (0.10, 0.30, 0.50, 0.70, 0.90):
        y = int(RT_H * frac)
        acc, n = 0.0, 0
        try:
            for x in range(8, RT_W, 32):
                c = fn(W, rt, x, y)
                acc += (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b)
                n += 1
        except Exception:
            return None
        if n:
            rows.append((frac, acc / n))
    return rows


def measure(slug):
    """Clear -> capture -> export -> read. The order matters.

    The clear is what makes a stale frame impossible: if the capture writes
    nothing, the exported image is still the known clear colour and reads as
    such, instead of being the previous rung's frame wearing a new name.
    """
    MEASURED["n"] += 1
    name = "_p29_%02d_%s" % (MEASURED["n"], slug)
    swcap.clear_rt(W, rt)
    cap_err = ""
    try:
        cc.capture_scene()
    except Exception as exc:
        cap_err = " capture RAISED: %s" % str(exc)[:80]
    swcap.export_rt(W, rt, OUT_DIR, name)
    path = swimg.collect(OUT_DIR, name)
    if not path:
        log("        NO FILE%s" % cap_err)
        return {"slug": slug, "verdict": "NO FILE"}
    st = swimg.png_stats(path)
    if st is None or st["mean_luma"] is None:
        log("        unreadable%s" % cap_err)
        return {"slug": slug, "verdict": "UNREADABLE"}
    mean = st["mean_luma"] or 0.0
    cols = st["distinct_rgb"] or 0
    if cols <= 3 and mean < 2.0:
        verdict = "BLACK"
    elif mean > 225:
        verdict = "BLOWN"
    elif mean < 12:
        verdict = "DIM"
    else:
        verdict = "GOOD"
    rows = read_rows()
    log("        %-9s mean=%-7.2f colours=%-6d %s"
        % (verdict, mean, cols, path.rsplit("/", 1)[-1]))
    if rows:
        # rt row 0 is the TOP of the image in UE read_render_target_pixel
        # (upper-left origin), so frac 0.10 is sky and 0.90 is ground.
        txt = "  ".join("y%02d%%=%6.1f" % (int(f * 100), v) for f, v in rows)
        top = sum(v for f, v in rows if f <= 0.30) / 2.0
        bot = sum(v for f, v in rows if f >= 0.70) / 2.0
        log("        rows  %s" % txt)
        log("        SKY(top 1/3)=%-6.1f  GROUND(bottom 1/3)=%-6.1f  ratio=%s"
            % (top, bot, ("%.2f" % (bot / top)) if top > 0.01 else "inf"))
    else:
        log("        rows  (read_render_target_pixel unavailable or failed)")
    return {"slug": slug, "verdict": verdict, "mean": mean, "colours": cols,
            "rows": rows}


def set_sun(rot=None, colour=None, intensity=None):
    """Set the sun, and READ BACK every value that was set.

    P27's colour setter proof was vacuous: it set WHITE and read back WHITE, so
    the readback could not distinguish "applied" from "ignored". This logs the
    previous value too, so a change is visible as a change.
    """
    notes = []
    comp = SUN["comp"]
    if rot is not None:
        # KEYWORD FORM. `unreal.Rotator(pitch=, yaw=, roll=)` is the only form
        # that cannot be silently transposed - the positional form is
        # (ROLL, PITCH, YAW), which is the bug under investigation.
        before = SUN["actor"].get_actor_rotation()
        want = unreal.Rotator(pitch=float(rot[0]), yaw=float(rot[1]),
                              roll=float(rot[2]))
        try:
            SUN["actor"].set_actor_rotation(want, False)
        except Exception as exc:
            notes.append("rotation set RAISED: %s" % str(exc)[:80])
        got = SUN["actor"].get_actor_rotation()
        notes.append("rotation was(p=%.1f y=%.1f r=%.1f) want(p=%.1f y=%.1f "
                     "r=%.1f) readback(p=%.1f y=%.1f r=%.1f)"
                     % (before.pitch, before.yaw, before.roll,
                        rot[0], rot[1], rot[2],
                        got.pitch, got.yaw, got.roll))
    if colour is not None:
        had = swcap.get_prop(comp, "light_color")[1]
        ok = swcap.set_prop(comp, "light_color",
                            unreal.Color(int(colour[0]), int(colour[1]),
                                         int(colour[2]), 255))
        swcap.set_prop(comp, "use_temperature", False)
        now = swcap.get_prop(comp, "light_color")[1]
        notes.append("colour had=%s set=%s now=%s"
                     % (str(had)[-28:], ok, str(now)[-28:]))
    if intensity is not None:
        had = swcap.get_prop(comp, "intensity")[1]
        ok = swcap.set_prop(comp, "intensity", float(intensity))
        now = swcap.get_prop(comp, "intensity")[1]
        notes.append("intensity had=%s set=%s now=%s" % (had, ok, now))
    return "; ".join(notes)


def set_sky(real_time=None, intensity=None):
    if SKY is None:
        return "no sky light"
    notes = []
    if real_time is not None:
        had = swcap.get_prop(SKY["comp"], "real_time_capture")[1]
        ok = swcap.set_prop(SKY["comp"], "real_time_capture", bool(real_time))
        now = swcap.get_prop(SKY["comp"], "real_time_capture")[1]
        notes.append("real_time_capture had=%s set=%s now=%s" % (had, ok, now))
    if intensity is not None:
        had = swcap.get_prop(SKY["comp"], "intensity")[1]
        ok = swcap.set_prop(SKY["comp"], "intensity", float(intensity))
        notes.append("intensity had=%s set=%s now=%s"
                     % (had, ok, swcap.get_prop(SKY["comp"], "intensity")[1]))
    rec = getattr(SKY["comp"], "recapture_sky", None)
    if rec is not None:
        try:
            rec()
            notes.append("recapture_sky() called")
        except Exception as exc:
            notes.append("recapture_sky raised: %s" % str(exc)[:80])
    return "; ".join(notes)


# --------------------------------------------------------------------------
# PLAN - rotation first, one lever at a time, ONE instrument throughout.
# --------------------------------------------------------------------------
def rung(label, fn, slug, extra=None):
    """Run one lever, wait, measure. `extra` runs AFTER the lever."""
    log("")
    log("[%d] %s" % (len(ROW) + 1, label))
    if fn is not None:
        note = fn()
        if note:
            log("        " + note)
    exec_wait = WAIT
    globals()["_NEXT"] = {"slug": slug, "extra": extra, "left": exec_wait}


PLAN = [
    ("as found: sun pitch as built, intensity as built",
     None, "01_asfound"),
    ("sun rotation -> pitch=-45 yaw=35 (AIMED DOWN) intensity 100000",
     lambda: set_sun(rot=(-45.0, 35.0, 0.0), intensity=100000.0), "02_down_100k"),
    ("same aim, intensity 6.0 (the level's own default)",
     lambda: set_sun(intensity=6.0), "03_down_int6"),
    ("same aim, intensity 10.0 (UE default for a new light)",
     lambda: set_sun(intensity=10.0), "04_down_int10"),
    ("same aim, intensity 3000.0",
     lambda: set_sun(intensity=3000.0), "05_down_int3000"),
    ("sun colour -> warm (255,140,60): a NON-white colour, so the readback "
     "can prove the setter",
     lambda: set_sun(colour=(255, 140, 60)), "06_warm"),
    ("sun colour -> back to white",
     lambda: set_sun(colour=(255, 255, 255)), "07_white"),
    ("sky light -> real-time capture, intensity 1.0",
     lambda: set_sky(real_time=True, intensity=1.0), "08_skylight_rt"),
    ("sun rotation -> pitch=+35 again (BACK TO THE BUG), intensity 100000",
     lambda: set_sun(rot=(35.0, 35.0, 0.0), intensity=100000.0), "09_up_100k"),
    ("and back down: pitch=-45, intensity 100000  (determinism check)",
     lambda: set_sun(rot=(-45.0, 35.0, 0.0), intensity=100000.0), "10_down_again"),
]

log("")
log("--- p29: %d rungs, ONE instrument (%s), lever = sun ROTATION first ---"
    % (len(PLAN), INSTRUMENT))
log("    each rung is TWO ticks apart: apply the lever, let the world tick,")
log("    then capture. Applying and capturing in one tick would capture the")
log("    state BEFORE the lever, which is how a probe lies.")

STATE = {"handle": None, "t": 0, "wait": 0, "done": False, "i": 0,
         "results": [], "errors": 0, "handed": False, "phase": "lever"}
BUDGET = 700


def finish(st, reason):
    if STATE["done"]:
        return
    STATE["done"] = True
    log("")
    log("=" * 74)
    log("--- results ---")
    for r in st["results"]:
        rows = r.get("rows")
        extra = ""
        if rows:
            top = sum(v for f, v in rows if f <= 0.30) / 2.0
            bot = sum(v for f, v in rows if f >= 0.70) / 2.0
            extra = "  sky=%6.1f ground=%6.1f" % (top, bot)
        log("    %-26s %-8s mean=%-7s cols=%-6s%s"
            % (r["label"][:26], r.get("verdict", "?"),
               ("%.2f" % r["mean"]) if r.get("mean") is not None else "-",
               r.get("colours", "-"), extra))

    def get(slug):
        for r in st["results"]:
            if r.get("slug") == slug:
                return r
        return None

    base, down, again = get("01_asfound"), get("02_down_100k"), get("10_down_again")
    log("")
    log("--- what this decides ---")
    if down and base:
        bm = base.get("mean", 0) or 0
        dm = down.get("mean", 0) or 0
        log("    as-found mean=%.2f   aimed-down mean=%.2f" % (bm, dm))
        if dm > bm * 3 and dm > 20:
            log("    => ROTATION WAS THE CAUSE. Aiming the sun down lights the")
            log("       scene. P20 must pass the sun's rotation in the KEYWORD")
            log("       form (unreal.Rotator(pitch=, yaw=, roll=)) instead of a")
            log("       3-tuple into spawn(), which transposes it to")
            log("       (ROLL, PITCH, YAW) and aims the sun at the sky.")
        elif dm > 20:
            log("    => the aimed-down state is lit, and so was the as-found")
            log("       state; rotation is not the whole story. Read the rows.")
        else:
            log("    => aiming the sun down did NOT light the scene. Rotation is")
            log("       NOT the cause. Read the rows and the intensity sweep.")
    if again and down:
        log("")
        a_m, d_m = again.get("mean"), down.get("mean")
        if a_m is None or d_m is None:
            # Both readings missing is NOT agreement. Saying "IDENTICAL" here
            # would be the same defect as P27's verdict: a claim the numbers
            # cannot support.
            log("    determinism: NOT TESTABLE - a repeat rung produced no "
                "reading (down=%s, down_again=%s)" % (d_m, a_m))
        else:
            log("    determinism: down_100k mean=%.2f  down_again mean=%.2f  %s"
                % (d_m, a_m,
                   "IDENTICAL" if abs(d_m - a_m) < 0.01
                   else "DIFFERENT - captures are not deterministic, so no small"
                        " difference in this table means anything"))
    log("")
    log("    ticks: %d, errors: %d (reason: %s)" % (st["t"], st["errors"], reason))
    log("P29 VERDICT : " + ", ".join("%s=%s" % (r["label"][:18],
                                                r.get("verdict", "?"))
                                     for r in st["results"][:5]))
    log("P29 DONE")
    print("P29 DONE")
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
        finish(st, "tick budget exhausted")
        return
    if not st["handed"]:
        WFX.watchdog_handover()
        st["handed"] = True
    st["wait"] -= 1
    if st["wait"] > 0:
        return
    if st["phase"] == "lever":
        if st["i"] >= len(PLAN):
            finish(st, "all rungs complete")
            return
        label, fn, slug = PLAN[st["i"]]
        log("")
        log("[%d/%d] %s" % (st["i"] + 1, len(PLAN), label))
        if fn is not None:
            try:
                note = fn()
            except Exception as exc:
                st["errors"] += 1
                note = "LEVER RAISED: %s" % str(exc)[:200]
            if note:
                log("        " + note)
        # Let the world tick with the new state before anything is captured.
        st["phase"] = "measure"
        st["wait"] = WAIT
        return
    # phase == measure
    label, fn, slug = PLAN[st["i"]]
    res = measure(slug)
    res["label"] = label
    res["slug"] = slug
    st["results"].append(res)
    st["i"] += 1
    st["phase"] = "lever"
    st["wait"] = WAIT


STATE["wait"] = WAIT
log("")
log("--- starting the tick loop ---")
STATE["handle"] = unreal.register_slate_post_tick_callback(tick)
