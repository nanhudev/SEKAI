"""SEKAI Sword VFX - P27: why is Lab_Sun inert, and what is the right light?

WHAT P26 FOUND

    Ten rungs against `SCS_SCENE_COLOR_HDR` (the lit scene colour). Everything
    that touched the EXISTING lights changed nothing:

        baseline                                       BLACK
        WorldSettings.force_no_precomputed_lighting    BLACK
        existing lights' mobility -> MOVABLE (readback
          confirmed MOVABLE)                           BLACK
        Lab_Sun intensity 6 -> 100000 (readback
          confirmed 100000.0)                          BLACK
        Lab_SkyLight -> real_time_capture, recaptured  BLACK

    and then, without touching any of them:

        spawn a brand-new Movable DirectionalLight     LIT   mean luma 126.21
        switch that state to SCS_FINAL_COLOR_LDR       LIT   mean luma 243.52
                                                             distinct_rgb 1790

    1790 distinct colours. That is the first real image this lab has ever
    rendered, and it settles the big question: the SceneCapture2D path works and
    always did. The lab was simply unlit.

    But it leaves a contradiction that has to be resolved before P20 is changed,
    because the two explanations need different edits:

        (a) Lab_Sun is misconfigured in a way that makes it emit nothing. Read
            the properties that were never read - `light_color` above all. A
            light with a BLACK colour emits nothing at ANY intensity, which
            would explain "100000.0 and still exactly zero" precisely.
        (b) The intensity change did take, but the scene's lighting was not
            flushed, and spawning an actor is what flushed it.

    The difference matters: (a) means P20 must set the light correctly; (b)
    means P20 must force a lighting update after configuring lights.

    And there is a third thing P26 cannot distinguish: the sun was swung from
    6 to 100000 in one step and finished at 243 (blown out), so nothing about
    the right intensity is known.

HOW THIS RESOLVES IT

    * Reads the light properties P26 omitted, and sets `light_color` to white
      before anything else, so hypothesis (a) can be confirmed or killed on its
      own rung.
    * A MINUS-ONE test: with the scene lit, destroy the fresh sun and measure
      again. If it goes back to black, the fresh light really was the cause and
      (b) is dead. If it stays lit, (b) is alive and the earlier setters did
      take effect after all.
    * An intensity sweep on `SCS_FINAL_COLOR_LDR`, so the value that P20 should
      use is chosen from measurements rather than from a plausible number.

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p27_light_fix.py --render
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p27_lightfix.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/lightfix')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
RT_W, RT_H = 512, 512
WAIT = 6
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
    log("P27 ABORTED")
    print("P27 ABORTED")
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


def destroy(actor):
    for name, obj in subsystems():
        if not hasattr(obj, "destroy_actor"):
            continue
        try:
            obj.destroy_actor(actor)
            return True
        except Exception:
            continue
    return False


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

# --- the properties P26 never read. light_color is the whole point here. ----
log("")
log("--- light properties, including the ones P26 omitted ---")
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
    log("    %s (%s)" % (label, cls))
    for p in ("mobility", "intensity", "intensity_units", "light_color",
              "use_temperature", "temperature", "visible", "affects_world",
              "cast_shadows", "specular_scale", "indirect_lighting_intensity",
              "source_type", "real_time_capture"):
        ok, val = swcap.get_prop(comp, p)
        if ok:
            log("        %-28s = %s" % (p, val))
    if "DirectionalLight" in cls and SUN is None:
        SUN = {"actor": a, "comp": comp, "label": label}
    if "SkyLight" in cls and SKY is None:
        SKY = {"actor": a, "comp": comp, "label": label}

# --- capture -------------------------------------------------------------
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
cap = spawn(unreal.SceneCapture2D, unreal.Vector(0, 0, 200),
            unreal.Rotator(0, 0, 0), "P27_Capture")
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
log("")
log("capture at TP34, wire verified")
swcap.clear_rt(W, rt)   # discard the first clear; it never takes

MEASURED = {"n": 0}


def measure(note="after"):
    MEASURED["n"] += 1
    name = "_p27_%02d" % MEASURED["n"]
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
    mean = st["mean_luma"] or 0.0
    if green:
        verdict = "GREEN"
    elif (st["distinct_rgb"] or 0) <= 3 and mean < 2.0:
        verdict = "BLACK"
    elif mean > 225:
        verdict = "BLOWN"
    elif mean < 12:
        verdict = "DIM"
    else:
        verdict = "GOOD"
    log("        %-7s %-5s top=%-15s %5.1f%%  mean_luma=%-7.2f colours=%s"
        % (note, verdict, str(top), 100.0 * frac, mean, st["distinct_rgb"]))
    return verdict


def shoot(src_name):
    val = getattr(unreal.SceneCaptureSource, src_name, None)
    swcap.set_prop(cc, "capture_source", val)
    swcap.clear_rt(W, rt)
    try:
        cc.capture_scene()
    except Exception as exc:
        return "capture FAILED: %s" % str(exc)[:80]
    return "captured (%s)" % src_name


def set_sun(colour=None, intensity=None):
    if SUN is None:
        return "no directional light"
    notes = []
    if colour is not None:
        ok = swcap.set_prop(SUN["comp"], "light_color",
                            unreal.Color(int(colour[0]), int(colour[1]),
                                         int(colour[2]), 255))
        swcap.set_prop(SUN["comp"], "use_temperature", False)
        notes.append("light_color set=%s readback=%s"
                     % (ok, swcap.get_prop(SUN["comp"], "light_color")[1]))
    if intensity is not None:
        ok = swcap.set_prop(SUN["comp"], "intensity", float(intensity))
        notes.append("intensity set=%s readback=%s"
                     % (ok, swcap.get_prop(SUN["comp"], "intensity")[1]))
    return "; ".join(notes)


FRESH = {"actor": None, "intensity": None}


def spawn_fresh(intensity):
    a = spawn(unreal.DirectionalLight, unreal.Vector(0, 0, 900),
              unreal.Rotator(0.0, 35.0, 20.0), "P27_FreshSun")
    if a is None:
        return "could not spawn a fresh sun"
    comp = a.light_component
    swcap.set_prop(comp, "mobility",
                   getattr(unreal.ComponentMobility, "MOVABLE", None))
    swcap.set_prop(comp, "intensity", float(intensity))
    FRESH["actor"], FRESH["intensity"] = a, intensity
    return ("spawned fresh sun intensity=%s mobility=%s"
            % (swcap.get_prop(comp, "intensity")[1],
               swcap.get_prop(comp, "mobility")[1]))


def pre(src, extra=None):
    def run():
        if extra:
            log("        " + extra())
        log("        " + shoot(src))
    return run


# Order matters and is deliberate: confirm the light's colour FIRST (so
# hypothesis (a) is answered on its own), reproduce the fresh-sun result SECOND,
# then remove the fresh sun to see whether the earlier changes held.
PLAN = [
    {"label": "reproduce P26 rung 1: SCENE_COLOR_HDR, nothing changed",
     "pre": pre("SCS_SCENE_COLOR_HDR"), "post": measure},
    {"label": "Lab_Sun: light_color -> WHITE, temp off, intensity 100000",
     "pre": pre("SCS_SCENE_COLOR_HDR",
                lambda: set_sun(colour=(255, 255, 255), intensity=100000)),
     "post": measure},
    {"label": "spawn a fresh Movable sun at 100000 (the P26 winner)",
     "pre": pre("SCS_SCENE_COLOR_HDR", lambda: spawn_fresh(100000)),
     "post": measure},
    {"label": "MINUS-ONE: destroy the fresh sun, keep everything else",
     "pre": pre("SCS_SCENE_COLOR_HDR",
                lambda: "destroyed fresh sun: %s" % destroy(FRESH["actor"])
                if FRESH["actor"] else "no fresh sun to destroy"),
     "post": measure},
    {"label": "re-spawn fresh sun 100000, FINAL_COLOR_LDR",
     "pre": pre("SCS_FINAL_COLOR_LDR", lambda: spawn_fresh(100000)),
     "post": measure},
    {"label": "sun intensity sweep: 3000",
     "pre": pre("SCS_FINAL_COLOR_LDR",
                lambda: set_sun(colour=(255, 255, 255), intensity=3000)),
     "post": measure},
    {"label": "sun intensity sweep: 300",
     "pre": pre("SCS_FINAL_COLOR_LDR",
                lambda: set_sun(intensity=300)), "post": measure},
    {"label": "sun intensity sweep: 30",
     "pre": pre("SCS_FINAL_COLOR_LDR", lambda: set_sun(intensity=30)),
     "post": measure},
    {"label": "sun intensity sweep: 3",
     "pre": pre("SCS_FINAL_COLOR_LDR", lambda: set_sun(intensity=3)),
     "post": measure},
    {"label": "determinism: same state, capture again, no changes",
     "pre": pre("SCS_FINAL_COLOR_LDR"), "post": measure},
]

STATE = {"done": False}


def finish(st, reason):
    if STATE["done"]:
        return
    STATE["done"] = True
    log("")
    log("--- table ---")
    for label, verdict in st["results"]:
        log("    %-58s %s" % (label[:58], verdict))

    res = dict(st["results"])
    log("")
    log("--- readings ---")
    for key, val in res.items():
        if "light_color" in key:
            log("    light_color fix alone          : %s" % val)
        if "fresh Movable sun" in key and "MINUS" not in key:
            log("    fresh sun                      : %s" % val)
        if "MINUS-ONE" in key:
            log("    fresh sun destroyed (minus-one): %s" % val)
    sweep = [(k, v) for k, v in st["results"] if "sweep" in k]
    if sweep:
        log("    intensity sweep:")
        for k, v in sweep:
            log("        %-40s %s" % (k.split(":")[-1].strip(), v))
    log("")
    minus = [v for k, v in st["results"] if "MINUS-ONE" in k]
    if minus:
        if minus[0] in ("BLACK",):
            log("    => the fresh light WAS the cause. Setting properties on the")
            log("       pre-existing lights does not light this scene; P20 must")
            log("       build the light differently, not merely reconfigure it.")
        else:
            log("    => the scene stayed lit after the fresh sun was destroyed, so")
            log("       the earlier property changes DID take effect and only needed")
            log("       a lighting update to show. P20 must force that update.")
    log("")
    log("    ticks: %d, pre-raised errors: %d (reason: %s)"
        % (st["t"], st["errors"], reason))
    log("P27 VERDICT : " + ", ".join("%s=%s" % (k[:26], v)
                                     for k, v in st["results"][:4]))
    log("P27 DONE")
    print("P27 DONE")
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception:
        pass


log("")
log("--- p27: %d rungs ---" % len(PLAN))
swcap.Ladder(PLAN, log, wait=WAIT, budget=600, name="P27").start(
    on_done=finish, handover=lambda: WFX.watchdog_handover())
