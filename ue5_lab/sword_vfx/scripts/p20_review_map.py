"""SEKAI Sword VFX - P20: build L_SwordVFX_Lab, the VFX review map.

The brief (section 30) requires every effect to hold on a BRIGHT background, and
(section 31) requires a fixed set of QA cameras, with A4 read from the Top and
A2/A3 read from Long range. A review map that is not fixed is not a review map:
if the reviewer can wander, two passes cannot be compared.

THE STAGE, and why it is laid out this way:

    The caster stands at the origin facing +X.

      +X, 20 m   BRIGHT wall (near-white), facing back at the caster
      -X, 20 m   DARK wall (near-black), behind the caster
      +X         this is DOWNRANGE - which is where A2 (8.4 m) and A3 (14-18 m)
                 actually happen, so the bright wall is behind the marks rather
                 than beside them. A bright wall on the left would test nothing.

    The ground is split: STONE on the right of the centre line, GRASS on the
    left. A1 cuts right and A2 rises to the left, so the two beats land on
    different surfaces without anyone moving the camera, and the contact family
    can be compared on two substrates in one pass.

Dummies are at 3 m / 8 m / 16 m on the centre line plus a ring of eight at 4 m,
so near, mid, far and surround all have something to hit.

Surfaces use plain opaque materials with controlled albedo. They are NOT lit
showcases: the point is a known, flat value behind the effect, so a stroke that
disappears can be attributed to the stroke and not to a busy texture.
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swmat as MAT  # noqa: E402
import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p20_review_map.txt')
LVL_DIR = "/Game/SEKAI/VFX/Sword/Lab"
LVL_NAME = "L_SwordVFX_Lab"
LVL = "%s/%s" % (LVL_DIR, LVL_NAME)
MAT_DIR = LVL_DIR + "/Materials"

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


# Armed before anything risky. If this script raises anywhere below, the editor
# would otherwise sit open forever with no script attached - which is what made
# a one-line TypeError look like a deadlock for two runs. See swvfx's watchdog
# section for the measured behaviour behind it. The driver shares THIS log file
# rather than opening its own, so the watchdog's last words land where the
# reader is already looking.
WFX.bind_log(EXPORT, truncate=False)
WFX.install_watchdog(300)


def spawn(cls, loc, rot=(0.0, 0.0, 0.0), label=None):
    """Spawn an actor, whichever subsystem this build exposes.

    `rot` may be a Rotator or a 3-tuple, and a Rotator is passed through
    UNCHANGED. That matters more than it looks: `unreal.Rotator(*t)` expands a
    tuple in (ROLL, PITCH, YAW) order - not the (pitch, yaw, roll) order the
    rest of this file reads naturally. The first version of `camera()` built the
    tuple as (pitch, yaw, roll), so every review camera came out rolled instead
    of turned, and the Top camera - the one the brief says A4's 270-degree sweep
    is "only countable from" - ended up rolled 90 degrees and still looking at
    the horizon.

    It was invisible in the build log, which printed the values this file INTENDED
    (pitch=-90.0 for Review_Top) rather than what the engine stored. The render
    pass caught it by reading the rotation back and getting pitch=0.0.
    """
    r = rot if isinstance(rot, unreal.Rotator) else unreal.Rotator(*rot)
    for getter in ("EditorActorSubsystem", "EditorLevelLibrary"):
        try:
            sub = getattr(unreal, getter)()
            a = sub.spawn_actor_from_class(cls, unreal.Vector(*loc), r)
            if a is not None:
                if label:
                    try:
                        a.set_actor_label(label)
                    except Exception:
                        pass
                return a
        except Exception:
            continue
    raise RuntimeError("could not spawn %s" % cls)


def mesh_actor(shape, loc, scale, material, label, rot=(0.0, 0.0, 0.0)):
    a = spawn(unreal.StaticMeshActor, loc, rot, label)
    comp = a.static_mesh_component
    comp.set_static_mesh(unreal.EditorAssetLibrary.load_asset(
        "/Engine/BasicShapes/%s.%s" % (shape, shape)))
    a.set_actor_scale3d(unreal.Vector(*scale))
    comp.set_mobility(unreal.ComponentMobility.STATIC)
    if material is not None:
        comp.set_material(0, material)
    return a


def _mark(what):
    """Name the call we are about to make, BEFORE making it.

    A hang inside the asset or material-graph API leaves no trace whatsoever:
    the log simply stops mid-section and the only way to find the culprit is to
    bisect by editing the script and paying another engine launch. Printing the
    call name first turns that into a last-known-position - one line, and the
    next run names its own hang.
    """
    log("        . %s" % what)


def simple_material(name, color, roughness=0.55, metallic=0.0, emissive=None):
    """REMOVED - kept only as a signpost.

    This function used to author the six lab surfaces in this session. It raised
    a TypeError every time: it passed the string "BASE_COLOR" where
    `connect_material_property` wants the EMaterialProperty enum. Because an
    uncaught error in -ExecCmds mode is logged and then swallowed, the editor
    stayed open and the failure presented as a hang inside the graph - which is
    why it is worth leaving this signpost rather than deleting it.

    The surfaces now come from p20a_lab_materials.py, a commandlet that needs no
    ticks. See that file's header for the corrected story, and
    `swmat.material_property` / `swvfx.install_watchdog` for the two fixes that
    stop this class of failure from ever looking like a deadlock again.
    """
    raise RuntimeError("surfaces are built by p20a_lab_materials.py")


def abort(msg):
    """Stop without leaving a headless editor running forever.

    Raising straight out of an -ExecCmds python run leaves the editor alive with
    no script attached, which looks identical to a hang and needs a manual kill.
    """
    log("")
    log("    ABORTING: %s" % msg)
    log("P20 ABORTED")
    print("P20 ABORTED")
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception:
        pass
    raise SystemExit(0)


def world():
    """The editor world, however this build exposes it."""
    for cls in ("UnrealEditorSubsystem", "EditorLevelLibrary"):
        try:
            w = getattr(unreal, cls)().get_editor_world()
            if w is not None:
                return w
        except Exception:
            continue
    return None


def actor_label(a):
    try:
        return a.get_actor_label()
    except Exception:
        try:
            return a.get_name()
        except Exception:
            return ""


def all_level_actors():
    for getter in ("EditorActorSubsystem", "EditorLevelLibrary"):
        try:
            return getattr(unreal, getter)().get_all_level_actors()
        except Exception:
            continue
    return []


def dedupe_by_path(actors):
    """Drop the repeated references `get_all_level_actors()` hands back.

    MEASURED: this build returns every actor TWICE. P21's shot list came back
    with ten entries for five cameras, at identical positions - which is how it
    was found.

    Left in, it doubles every census, and it did: P20's tally read "actors: 68"
    for a level holding 34, and "actors: 136" for one holding 68. The count was
    never wrong in a way that looked wrong - it was consistently double, which
    is exactly the kind of error that survives review, and it is why the tally
    below now prints a deduped number and says so.
    """
    seen, out = set(), []
    for a in actors or []:
        try:
            key = str(a.get_path_name())
        except Exception:
            key = "id:%d" % id(a)
        if key in seen:
            continue
        seen.add(key)
        out.append(a)
    return out


def look(from_xyz, at_xyz):
    return unreal.MathLibrary.find_look_at_rotation(
        unreal.Vector(*from_xyz), unreal.Vector(*at_xyz))


def camera(label, loc, target):
    rot = look(loc, target)
    # `rot` is a Rotator and is passed straight through - see spawn(). Building
    # a tuple here is what silently rolled every camera.
    a = spawn(unreal.CameraActor, loc, rot, label)
    comp = a.camera_component
    # A review camera must not re-frame itself between passes. Auto exposure is
    # already off project-wide; these three are the rest of what could move.
    for prop, val in (("field_of_view", 60.0), ("post_process_blend_weight", 1.0),
                      ("override_auto_exposure_min_brightness", True),
                      ("override_auto_exposure_max_brightness", True),
                      ("auto_exposure_min_brightness", 1.0),
                      ("auto_exposure_max_brightness", 1.0)):
        MAT.set_prop(comp, prop, val)
    log("    camera %-16s loc=(%7.1f,%7.1f,%7.1f)  pitch=%6.1f yaw=%6.1f"
        % (label, loc[0], loc[1], loc[2], rot.pitch, rot.yaw))
    return a


log("engine: " + unreal.SystemLibrary.get_engine_version())
log("building %s" % LVL)

# ------------------------------------------------------- get onto the target level
#
# THE FIRST REVISION OF THIS SECTION WAS WRONG, and the story is worth keeping
# because the wrongness was invisible for two runs.
#
# It tried to make the build idempotent by DELETING the level asset and then
# asking for a fresh one. Measured on the next run:
#
#     delete_asset  -> False
#     still exists  -> True
#
# `delete_asset` refuses here, so `new_level` declined to replace the level that
# was still there, `load_level` re-opened it, and every actor was then spawned
# ON TOP of the existing set. The map went from 34 real actors to 68 and the
# .umap from 251,875 to 487,077 bytes - a lab with two bright walls z-fighting
# and 22 dummies, which the render pass was about to be judged on.
#
# Deleting is the wrong lever. What this script needs is not a NEW level, it is
# an EMPTY one - and the eviction step below produces exactly that from any
# starting point. So neither path here depends on a delete that may refuse:
#
#     level exists  -> load it, then evict
#     level missing -> create it
#
# Only the LEVEL is touched. The M_Lab_* surfaces share the folder but belong to
# p20a, and a re-run of this script must not delete the assets it is about to
# load.
EAL = unreal.EditorAssetLibrary
made = False
level_existed = EAL.does_asset_exist(LVL)
if level_existed:
    log("    %s already exists: loading it, then evicting its actors"
        % LVL_NAME)
    for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
        try:
            getattr(unreal, how)().load_level(LVL)
            made = True
            break
        except Exception as exc:
            log("    load_level via %s failed: %s" % (how, str(exc)[:140]))
else:
    log("    %s does not exist: creating it" % LVL_NAME)
    for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
        try:
            sub = getattr(unreal, how)()
            res = sub.new_level(LVL)
            log("    new_level via %s -> %s" % (how, res))
            if res is False:
                # Not fatal, because the world check plus the eviction below
                # deal with whatever we end up in - but it must not read as
                # success. This is the return value that used to be logged and
                # then ignored while `made` was set True regardless.
                log("      returned FALSE: no fresh level was created.")
            made = True
            break
        except Exception as exc:
            log("    new_level via %s failed: %s" % (how, str(exc)[:160]))
if not made:
    abort("could not get onto %s" % LVL)

# MAKE THE NEW LEVEL THE CURRENT ONE, AND PROVE IT.
#
# `new_level` creates the asset and can still leave the editor sitting in a
# temporary world. Measured, from the engine log: every actor was spawned into
# `/Temp/Untitled_1.Untitled:PersistentLevel.CameraActor_3`, not into the level
# we had just made - so the map held all 34 actors in memory, saved none of
# them, and the render pass had nothing on disk to load. `new_level` reports
# this by RETURNING FALSE rather than by raising, and the return value was not
# being checked, so the whole failure was silent.
#
# Hence: create, then explicitly load, then check the world's path NAME. The
# world's identity is the thing that matters - everything downstream spawns into
# it, and a temp world looks exactly like a real one until you try to save.
W = world()
if W is None or LVL_NAME not in str(W.get_path_name()):
    for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
        try:
            getattr(unreal, how)().load_level(LVL)
            W = world()
            if W is not None and LVL_NAME in str(W.get_path_name()):
                log("    load_level via %s made it current" % how)
                break
        except Exception as exc:
            log("    load_level via %s failed: %s" % (how, str(exc)[:140]))

log("    editor world: %s" % (W.get_path_name() if W is not None else "NONE"))
if W is None or LVL_NAME not in str(W.get_path_name()):
    abort("the editor world is not %s. Every actor would be spawned into a "
          "temporary level and nothing would reach disk, so the render pass "
          "would load an empty map." % LVL_NAME)

# ---------------------------------------------------- evict whatever is here
#
# MEASURED, and the most expensive bug on this stage: after a re-run the level
# held TWO complete copies of the lab - 68 real actors instead of 34, and the
# .umap had grown 251,875 -> 487,077 bytes. Two bright walls z-fighting, 22
# dummies, and a render pass about to be judged on it.
#
# The chain was silent at every step:
#     delete_asset(LVL)   return value discarded
#     new_level(LVL)      returns False when it refuses; `res` was logged, then
#                         ignored, and the code carried on regardless
#     load_level(LVL)     so it re-opened the level that had not been removed
#     ...and then every actor was spawned ON TOP of the existing set
#
# So the fix is not another return-value check. It is to stop depending on
# new_level to hand back an empty world: whatever world we are in, empty it
# explicitly, then assert the result. A build that compounds on every re-run is
# worse than one that fails outright, because the second run still looks
# plausible and the third still renders.
_evicted, _kept = 0, []
for _a in dedupe_by_path(all_level_actors()):
    _cls = ""
    try:
        _cls = _a.get_class().get_name()
    except Exception:
        pass
    if "WorldSettings" in _cls:
        # The world's own settings object is not a spawned actor, and
        # destroying it would damage the level rather than clear it.
        _kept.append(_cls)
        continue
    for _getter in ("EditorActorSubsystem", "EditorLevelLibrary"):
        try:
            getattr(unreal, _getter)().destroy_actor(_a)
            _evicted += 1
            break
        except Exception:
            continue
_remaining = dedupe_by_path(all_level_actors())
log("")
log("--- eviction (this is what makes a re-run safe) ---")
log("    actors destroyed before build : %d" % _evicted)
if _kept:
    log("    kept (world infrastructure)   : %s" % ", ".join(sorted(set(_kept))))
log("    actors remaining              : %d" % len(_remaining))
if _evicted == 0 and len(_remaining) > len(_kept):
    abort("the level already contains %d actor(s) and none could be destroyed. "
          "Spawning now would append a second copy of the lab rather than "
          "replace it." % len(_remaining))
for _a in _remaining:
    try:
        _name = _a.get_class().get_name()
    except Exception:
        _name = "?"
    if "WorldSettings" not in _name:
        log("    UNEXPECTED SURVIVOR: %s (%s)" % (actor_label(_a), _name))

# ---------------------------------------------------------------- surfaces
#
# Built by p20a_lab_materials.py in a commandlet; loaded here, never authored.
# This session needs ticks for the Niagara gallery and the save, so it is the
# slow, failure-prone one; keeping graph authoring out of it keeps its launch
# shorter and its failure modes single. See p20a's header for why the split was
# made and what it originally, wrongly, looked like.
#
# The load is checked rather than assumed. A review map whose walls silently
# fell back to the engine default material would still render, still look
# plausible, and would quietly invalidate every answer to the brief's section 30
# ("every effect must hold on a BRIGHT background") - which is the one question
# this stage exists to answer. So a missing surface stops the build.
log("")
log("--- surfaces (authored by p20a; loaded here) ---")
SURFACES = [("bright", "M_Lab_BrightWall"), ("dark", "M_Lab_DarkWall"),
            ("stone", "M_Lab_Stone"), ("grass", "M_Lab_Grass"),
            ("dummy", "M_Lab_Dummy"), ("ground", "M_Lab_GroundFar")]
LOADED = {}
missing = []
for slot, name in SURFACES:
    mat = EAL.load_asset("%s/%s" % (MAT_DIR, name))
    if mat is None:
        missing.append(name)
        log("    %-8s %-20s MISSING" % (slot, name))
    else:
        LOADED[slot] = mat
        log("    %-8s %-20s loaded" % (slot, name))
if missing:
    abort("%d surface material(s) absent: %s\n"
          "    run first:  ./run_ue.sh "
          "F:/SEKAI/ue5_lab/sword_vfx/scripts/p20a_lab_materials.py"
          % (len(missing), ", ".join(missing)))
M_BRIGHT, M_DARK = LOADED["bright"], LOADED["dark"]
M_STONE, M_GRASS = LOADED["stone"], LOADED["grass"]
M_DUMMY, M_GROUND = LOADED["dummy"], LOADED["ground"]

# ------------------------------------------------------------- geometry
# Engine primitives are 100 cm, so a scale of 1.0 is 1 m.
log("")
log("--- geometry ---")
mesh_actor("Plane", (0, 0, 0), (60.0, 60.0, 1.0), M_GROUND, "Lab_Ground")

# +X is downrange: this is what A2's sheet and A3's three marks are drawn on.
#
# The walls are thin CUBES, not rotated Planes. A Plane is authored in the XY
# plane facing +Z, so standing one up needs Roll and then Yaw - and getting that
# wrong leaves the "wall" lying flat on the ground, which is exactly what a
# matte wall and a matte floor look like from a distance in a screenshot. A cube
# scaled (24, 0.2, 8) is 24 m wide, 0.2 m thick and 8 m tall with no rotation at
# all, and the only thing that can be wrong about it is a number.
mesh_actor("Cube", (2000, 0, 400), (24.0, 0.2, 8.0), M_BRIGHT, "Lab_BrightWall")
mesh_actor("Cube", (-2000, 0, 400), (24.0, 0.2, 8.0), M_DARK, "Lab_DarkWall")

# Ground split on the centre line: stone right, grass left. A1 cuts right,
# A2 rises left, so both beats get a different substrate without moving.
mesh_actor("Plane", (1600, 600, 2), (32.0, 12.0, 1.0), M_STONE, "Lab_Stone")
mesh_actor("Plane", (1600, -600, 2), (32.0, 12.0, 1.0), M_GRASS, "Lab_Grass")
log("    ground 60x60 m, bright wall at +20 m, dark wall at -20 m")
log("    stone half at +Y, grass half at -Y, both 32x12 m")

# ----------------------------------------------------------------- dummies
log("")
log("--- dummies (1.80 m tall, 0.30 m radius) ---")
DUMMY_H = 1.80          # metres. The LOCATION below already uses cm.

# THE SCALE WAS 100x TOO SMALL, AND THAT IS WHY THE LAB LOOKED EMPTY.
#
# `/Engine/BasicShapes/Cylinder` is a unit cylinder in CENTIMETRES: radius
# 50 cm, height 100 cm. To get a 30 cm radius you scale by 30/50 = 0.6, and to
# get 180 cm of height you scale by 180/100 = 1.8.
#
# This line used to be (0.30/50.0, 0.30/50.0, DUMMY_H/100.0) = (0.006, 0.006,
# 0.018) - a METRE value divided by a CENTIMETRE base. The result was a dummy
# 0.6 cm wide and 1.8 cm tall. Eleven of them were spawned, correctly labelled,
# correctly counted, and completely invisible.
#
# MEASURED, and it is what exposed this: p31's audit found the saved level
# contains 34 actors - 11 dummies, 9 Niagara gallery actors, 2 walls, ground,
# 5 cameras - while p21's five QA frames showed a bare pad. Content that exists
# and content that is VISIBLE are different claims, and only the second one is
# what a review map is for.
#
# NOTE the inconsistency that gave it away: the location line uses
# `DUMMY_H * 50.0` = 90 cm, i.e. half of 180 cm - the correct cm convention.
# The scale line next to it did not. One line was written in centimetres and its
# neighbour in metres, and nothing in the log could tell them apart, because
# both "placed" successfully.
DUMMY_RADIUS_CM = 30.0
DUMMY_HEIGHT_CM = DUMMY_H * 100.0     # 1.80 m -> 180 cm
CYL_BASE_RADIUS_CM = 50.0             # BasicShapes/Cylinder
CYL_BASE_HEIGHT_CM = 100.0
DUMMY_SCALE = (DUMMY_RADIUS_CM / CYL_BASE_RADIUS_CM,
               DUMMY_RADIUS_CM / CYL_BASE_RADIUS_CM,
               DUMMY_HEIGHT_CM / CYL_BASE_HEIGHT_CM)
log("    cylinder base 50 cm radius / 100 cm tall -> scale %s"
    % (tuple(round(v, 3) for v in DUMMY_SCALE),))
log("    so a dummy measures %.0f cm across and %.0f cm tall"
    % (2 * DUMMY_RADIUS_CM, DUMMY_HEIGHT_CM))

for label, x in (("Close", 300.0), ("Mid", 800.0), ("Far", 1600.0)):
    mesh_actor("Cylinder", (x, 0, DUMMY_HEIGHT_CM / 2.0), DUMMY_SCALE, M_DUMMY,
               "Lab_Dummy_%s" % label)
    log("    Lab_Dummy_%-6s at x=%6.1f cm" % (label, x))

import math
for i in range(8):
    ang = math.radians(i * 45.0)
    r = 400.0
    mesh_actor("Cylinder", (r * math.cos(ang), r * math.sin(ang),
                            DUMMY_HEIGHT_CM / 2.0), DUMMY_SCALE, M_DUMMY,
               "Lab_Dummy_Ring%02d" % i)
log("    8 ring dummies at 4 m, 45 degrees apart")

# ------------------------------------------------------------------ lights
log("")
log("--- lighting (one directional light + sky ambient) ---")
# THE ROTATION IS PASSED AS A Rotator, NOT AS A TUPLE, AND THAT IS THE FIX.
#
# This line used to be `spawn(..., (-42.0, 35.0, 0.0), "Lab_Sun")`, and
# `spawn()` does `unreal.Rotator(*rot)` for a tuple - which expands in
# (ROLL, PITCH, YAW) order. So the intended pitch of -42, which puts the sun
# above the horizon shining down, became ROLL=-42 with PITCH=+35: the sun was
# aimed UP INTO THE SKY and the ground was never lit by it, at any intensity.
#
# MEASURED, and this is exactly the trap the `spawn()` docstring above already
# describes: it was written for `camera()`, `camera()` was fixed, and this line
# - which passes a tuple to the same helper on the next screen - was not.
#
# The symptom was misread for two sessions as "the lab has no lighting", and
# two probes concluded that a brand-new spawned light was the cure. It was not:
# MEASURED with tools/split_luma.py over P27's own frames, the rung it called
# GOOD reads SKY=90.3 / MID=124.1 / GROUND=22.6 - bright sky, dark ground, which
# is the fingerprint of a light aimed the wrong way, not of an unlit level.
#
# Every rotation in this file that is not already a Rotator must therefore be
# built with the KEYWORD form, which cannot be silently transposed.
SUN_PITCH, SUN_YAW = -42.0, 35.0
sun = spawn(unreal.DirectionalLight, (0, 0, 800),
            unreal.Rotator(pitch=SUN_PITCH, yaw=SUN_YAW, roll=0.0), "Lab_Sun")
# INTENSITY 10.0, CHOSEN FROM A MEASUREMENT, NOT FROM TASTE.
#
# P29 swept this once the aim was fixed, on one instrument (FINAL_COLOR_LDR):
#
#     pitch -45, intensity    6.0 -> mean 43.68, 2902 colours, ground  63.6
#     pitch -45, intensity   10.0 -> mean 79.53, 3869 colours, ground 108.1
#     pitch -45, intensity 3000.0 -> mean 251.89, 886 colours, BLOWN
#
# Section 30 requires every effect to hold on a BRIGHT background, and 10.0 is
# the brightest setting that is not blown. Above it there is no headroom: 3000
# is white across the whole frame.
sun.light_component.set_intensity(10.0)
# READ THE ROTATION BACK. A setter that returns without applying, reported as
# success, is the failure this project has paid for most often.
try:
    _r = sun.get_actor_rotation()
    if _r.pitch > 0.0:
        log("    !! Lab_Sun reads pitch=%+.1f - it is aimed at the SKY and will"
            % _r.pitch)
        log("    !! not light the ground. Expected pitch=%+.1f." % SUN_PITCH)
    else:
        log("    sun rotation verified: pitch=%+.1f yaw=%+.1f (aimed down)"
            % (_r.pitch, _r.yaw))
except Exception as exc:
    log("    COULD NOT VERIFY the sun's rotation: %s" % str(exc)[:120])
MAT.set_prop(sun.light_component, "mobility", unreal.ComponentMobility.MOVABLE)
MAT.set_prop(sun, "atmosphere_sun_light", True)
MAT.set_prop(sun, "cast_shadows", False)


sky = spawn(unreal.SkyLight, (0, 0, 400), label="Lab_SkyLight")
MAT.set_prop(sky.light_component, "mobility", unreal.ComponentMobility.MOVABLE)
MAT.set_prop(sky.light_component, "intensity", 1.0)

spawn(unreal.SkyAtmosphere, (0, 0, 0), label="Lab_SkyAtmosphere")
spawn(unreal.ExponentialHeightFog, (0, 0, 0), label="Lab_Fog")
log("    one directional light (intensity 6.0, no shadow) + SkyLight + "
    "SkyAtmosphere + fog")

# ----------------------------------------------------------------- cameras
log("")
log("--- QA cameras (section 31) ---")
log("    the caster faces +X; ground is z=0; a body is 1.80 m")
cameras = [
    ("Review_FP", (0.0, 0.0, 170.0), (2000.0, 0.0, 140.0),
     "first person, eye height, the shipping view"),
    ("Review_TP34", (-520.0, 300.0, 235.0), (700.0, 0.0, 140.0),
     "third person front three-quarter; equip / inspect / A1"),
    ("Review_Side", (-120.0, -760.0, 200.0), (700.0, 0.0, 150.0),
     "side on; reads the arc's band width and the scar's edge weight"),
    ("Review_Top", (400.0, 0.0, 1500.0), (400.0, 0.0, 0.0),
     "top down; A4's 270 degree sweep is only countable from here"),
    ("Review_Long", (-900.0, -200.0, 300.0), (1700.0, 0.0, 160.0),
     "long range; A2's 8.4 m sheet and A3's 14-18 m marks"),
]
for name, loc, target, why in cameras:
    camera(name, loc, target)
    log("        %s" % why)

# ------------------------------------------------------- Niagara gallery
#
# This section is not decoration. A headless editor never compiles a Niagara
# system: there is no Niagara preview and nothing instantiates the system, so
# `GetSystemCompileState` reports aggregateStatus=UpToDate while is_stale=True -
# the two disagree and the honest reading is "no compile was performed". Putting
# a Niagara component in a level dispatches a component registration, which
# instantiates the system, which is what actually makes the compiler run.
#
# It also gives the cameras something to look at, which is the only way the
# brief's section 30 requirement - that every effect holds on a BRIGHT
# background - can be answered at all.
log("")
log("--- Niagara gallery (this is what forces a real compile) ---")
SYS_DIR = "/Game/SEKAI/VFX/Sword/Systems"


def niagara_component(actor):
    """The system component off a freshly spawned NiagaraActor.

    `get_niagara_component()` DOES NOT EXIST in this build's python bindings -
    it is a C++ accessor with no BlueprintCallable twin, so the first version of
    this gallery raised AttributeError on every system and placed nine EMPTY
    actors. The UPROPERTY is what is exposed, so that is what is read.

    This is worth a comment because the failure is silent by construction: the
    actor still spawns, still gets a label, still counts as "placed", and still
    renders nothing. The gallery would then appear to work while doing exactly
    none of its job - which is to instantiate the systems so the compiler runs.
    The caller therefore treats "no component" as a failure, not a warning.
    """
    for how in (lambda: actor.get_editor_property("niagara_component"),
                lambda: actor.niagara_component,
                lambda: actor.get_component_by_class(unreal.NiagaraComponent)):
        try:
            comp = how()
            if comp is not None:
                return comp
        except Exception:
            continue
    return None


gallery = []

# The nine systems are NAMED, not discovered.
#
# The previous revision called `EditorAssetLibrary.list_assets` here, and the
# engine hard-crashed inside this block with
#     Ensure condition failed: !ModuleGroup.StartNodes.IsEmpty()
#     [NiagaraStackGraphUtilities.cpp:906]  -> EXCEPTION_ACCESS_VIOLATION
# and, on a different run, `Ensure condition failed: CurrentTransaction
# [EditorTransaction.cpp:1807]` with a call stack through EditorAssetLibrary.
# Discovery was the likely co-factor. An API that can take the editor down in
# order to tell us something we already know is not worth using - and naming
# them makes the gallery's count mean something fixed, so a system that fails
# to place shows up as 8 where 9 was intended.
#
# The path needs the object name appended: "/Game/A/B" alone loads nothing.
SYSTEM_NAMES = (
    "NS_SW_Core_EdgeTrail", "NS_SW_Core_Glint", "NS_SW_Core_AirSlice",
    "NS_SW_Core_Wave", "NS_SW_Core_SpatialScar", "NS_SW_Core_MajorArc",
    "NS_SW_Core_MistWake", "NS_SW_Core_PurpleMotes", "NS_SW_Core_Hit",
)
unplaced = []
for i, name in enumerate(SYSTEM_NAMES):
    asset = unreal.EditorAssetLibrary.load_asset("%s/%s.%s"
                                                 % (SYS_DIR, name, name))
    if asset is None:
        log("    %-28s could not load" % name)
        unplaced.append(name)
        continue
    loc = (900.0, -1200.0 + i * 300.0, 150.0)
    # `name[10:]` produced "Lab_FX__EdgeTrail" - a double underscore, because
    # "NS_SW_Core_" is eleven characters. Harmless but it reads as a typo in the
    # outliner, and a review stage is something people browse by label.
    a = spawn(unreal.NiagaraActor, loc,
              label="Lab_FX_%s" % name[len("NS_SW_Core_"):])
    comp = niagara_component(a) if a is not None else None
    if comp is None:
        log("    %-28s NO COMPONENT - nothing to compile, not counted" % name)
        unplaced.append(name)
        continue
    try:
        comp.set_asset(asset)
        # Auto-activate: without this the component sits idle and nothing
        # compiles. Preview-only, so the level's cost is a review concern.
        MAT.set_prop(comp, "auto_activate", True)
        gallery.append(name)
        log("    %-28s placed at y=%7.1f" % (name, loc[1]))
    except Exception as exc:
        log("    %-28s component failed: %s" % (name, str(exc)[:140]))
        unplaced.append(name)
log("    %d systems placed" % len(gallery))
if unplaced:
    # Named rather than counted: "8 systems placed" is not actionable on its
    # own, and which one is missing is the only thing that matters.
    log("    NOT PLACED (%d): %s" % (len(unplaced), ", ".join(unplaced)))
    log("    an unplaced system is never instantiated, so nothing forces it to "
        "compile and it stays unverified")

# -------------------------------------------------------------------- save
#
# The save happens on a tick, not here, and the phases run SETTLE -> SAVE ->
# PROBE.
#
# WHY SAVE COMES BEFORE THE COMPILE PROBE, having tried it the other way. The
# gallery exists to make the compiler run by instantiating the systems, and the
# first version of this file therefore refused to save until the engine had
# answered `GetSystemCompileState` for all nine. Measured: it never answered. All
# nine came back "no answer within 25s", so the phase burned 225 s and then saved
# anyway - the gate cost four minutes and bought nothing.
#
# The reason is consistent with what P11 recorded from the other direction:
# `GetSystemCompileState` waits on a completion that needs a Niagara-world tick,
# and asking it while the systems are actively compiling is the one moment it
# will not return. So the probe is a DIAGNOSTIC, run after the artifacts are on
# disk, with a short budget, and it does not gate anything.
#
# This is also the safer order for a different reason: the map, the surfaces and
# the camera anchors are what this script exists to produce. Anything that can
# stop them being written should run last, not first.
log("")
log("--- handing over to the tick phase ---")
log("    settle, save the level + systems, then probe the compile state.")

GALLERY = gallery
WARM_TICKS = 60
WARM_SECONDS = 3.0
PROBE_SECONDS = 8.0             # per system, best-effort diagnostic

STATE = {"handle": None, "ticks": 0, "seconds": 0.0, "phase": "warm",
         "phase_at": 0.0, "busy": False, "closed": False,
         "next": 0, "current": None, "compile": {},
         "written": None, "saved_level": None}


def _system_disk(name):
    p = "%s/%s" % (SYS_DIR, name)
    return (str(_SEKAI_ROOT / 'ue5_lab/SwordVFX_Lab/Content')
            + p[len("/Game"):] + ".uasset")


def _system_pkg(name):
    return "%s/%s" % (SYS_DIR, name)


def _level_disk():
    return (str(_SEKAI_ROOT / 'ue5_lab/SwordVFX_Lab/Content')
            + LVL[len("/Game"):] + ".umap")


def _mtime(p):
    return os.path.getmtime(p) if os.path.exists(p) else 0.0


def _enter(st, phase):
    st["phase"] = phase
    st["phase_at"] = st["seconds"]


def _do_save(st):
    """Everything after the compile answers are in, including the risky calls.

    Called with `busy` set, because `save_dirty_packages` PUMPS THE SLATE TICK:
    this callback runs again while the save is still on the stack. Measured, on
    the run that placed the gallery: the tally printed underneath the save, and
    the level was reported as `saved=None` before `save_current_level` had even
    been called. Guarding only on `phase` is not enough for that - the later
    phase ran *while* the earlier one was still executing.
    """
    before = {name: _mtime(_system_disk(name)) for name in GALLERY}
    lvl_before = _mtime(_level_disk())
    log("")
    log("--- save_dirty_packages (level + systems) ---")
    _mark("save_dirty_packages")
    try:
        res = unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True)
        log("    returned %s" % res)
    except Exception as exc:
        log("    raised %s" % str(exc)[:200])

    written = 0
    for name in GALLERY:
        ok = _mtime(_system_disk(name)) > before[name]
        written += 1 if ok else 0
        log("    %-28s %s" % (name, "written" if ok else "NOT rewritten"))
    log("    systems written: %d / %d" % (written, len(GALLERY)))
    if not written:
        log("    (a system that was already saved and not modified is NOT")
        log("     dirty, so 'not rewritten' is the expected answer here. It is")
        log("     only a problem if you expected this run to have rebuilt it.)")
    st["written"] = written

    # ---- the LEVEL, which is the one artifact p21 depends on
    #
    # `save_current_level()` reports SUCCESS and writes NOTHING in this session -
    # measured: it logged "save_current_level via LevelEditorSubsystem" while the
    # .umap on disk kept its old mtime and its old size, so the map with its 34
    # actors and 5 cameras existed only in memory and the render pass would have
    # loaded an empty level and found no Review_* anchors at all.
    #
    # Hence three APIs tried in order, every return value logged, and the verdict
    # taken from the FILE. A return code is not evidence - the same rule that
    # caught this on the systems would have caught it here if it had been
    # applied here in the first place.
    log("")
    log("--- the level ---")
    log("    file: %s" % _level_disk())
    saved_level = False
    attempts = (
        ("EditorLoadingAndSavingUtils.save_map",
         lambda: unreal.EditorLoadingAndSavingUtils.save_map(W, LVL)),
        ("LevelEditorSubsystem.save_current_level",
         lambda: unreal.LevelEditorSubsystem().save_current_level()),
        ("EditorLevelLibrary.save_current_level",
         lambda: unreal.EditorLevelLibrary().save_current_level()),
    )
    for how, fn in attempts:
        try:
            _mark(how)
            res = fn()
            log("    %-46s -> %s" % (how, res))
            if res:
                saved_level = True
                break
        except Exception as exc:
            log("    %-46s raised %s" % (how, str(exc)[:120]))

    now = _mtime(_level_disk())
    wrote = now > lvl_before
    size = os.path.getsize(_level_disk()) if os.path.exists(_level_disk()) else 0
    log("    %-46s %s (%d bytes, mtime %s)"
        % ("level file on disk",
           "WRITTEN" if wrote else "NOT WRITTEN", size,
           "advanced" if wrote else "unchanged"))
    if not wrote:
        log("")
        log("    !! The level was NOT persisted. P21 loads the level from disk,")
        log("    !! so it would render an EMPTY map and find no camera anchors.")
        log("    !! Do not run the render pass until this says WRITTEN.")
    st["saved_level"] = saved_level and wrote
    st["level_written"] = wrote

    log("")
    log("--- compile state (diagnostic; the gallery above is what triggers it) ---")
    log("    a system with no answer here has NOT been shown to compile.")


def _tick(delta):
    st = STATE
    if st["closed"]:
        return
    if st["busy"]:
        # RE-ENTRANCY. Long native editor calls pump the slate tick, so this
        # callback fires again while the previous one is still on the stack.
        # Without this guard the later phases execute underneath the earlier
        # ones - the observed symptom was a tally that printed before the save
        # it was summarising, and reported the level as unsaved.
        return

    st["ticks"] += 1
    try:
        st["seconds"] += float(delta)
    except Exception:
        pass

    if st["phase"] == "warm":
        # Enough for the component registration to settle before anything is
        # written. Deliberately short: the real work is the save below, and the
        # compile probe afterwards is a diagnostic, not a gate.
        if st["ticks"] < WARM_TICKS or st["seconds"] < WARM_SECONDS:
            return
        _enter(st, "save")
        return

    if st["phase"] == "save":
        # Advance the phase BEFORE the risky call. A python callback that is
        # interrupted inside a long native call never reaches the line after it,
        # so leaving the phase put would re-enter this block on the next tick.
        _enter(st, "probe")
        st["busy"] = True
        try:
            _do_save(st)
        finally:
            st["busy"] = False
        return

    if st["phase"] == "probe":
        if st["next"] >= len(GALLERY):
            _enter(st, "done")
            return
        name = GALLERY[st["next"]]
        if st["current"] is None:
            try:
                st["current"] = WFX.call_async(
                    "GetSystemCompileState",
                    {"system": WFX.ref(_system_pkg(name))})
            except Exception as exc:
                st["compile"][name] = {"error": str(exc)[:120]}
                log("    %-28s no answer (%s)" % (name, str(exc)[:80]))
                st["next"] += 1
            return
        done, ok, val = WFX.poll(st["current"], "GetSystemCompileState")
        if not done:
            if st["seconds"] - st["phase_at"] > PROBE_SECONDS:
                st["compile"][name] = {"error": "no answer within %.0fs"
                                                % PROBE_SECONDS}
                log("    %-28s no answer within %.0fs - reported as unanswered"
                    % (name, PROBE_SECONDS))
                st["current"] = None
                st["next"] += 1
                _enter(st, "probe")
            return
        st["compile"][name] = val if ok else {"error": str(val)[:120]}
        info = st["compile"][name] if isinstance(st["compile"][name], dict) else {}
        log("    %-28s status=%-22s stale=%-5s compiling=%s"
            % (name, info.get("aggregateStatus", info.get("error", "?")),
               info.get("bIsStale"), info.get("bIsCompiling")))
        st["current"] = None
        st["next"] += 1
        _enter(st, "probe")
        return

    if st["phase"] == "done":
        st["busy"] = True
        try:
            actors = dedupe_by_path(all_level_actors())

            # THE DUPLICATE CENSUS.
            #
            # The check that would have caught the doubling on the run that
            # introduced it, and the reason it lives here rather than in a
            # comment: the doubling is invisible in every other signal this
            # script produces. `level written`, `P20 DONE`, a growing .umap and
            # even a correct-looking camera list are all consistent with two
            # copies of the lab. Only a label census says "there are two of
            # everything" - and a lab with two bright walls z-fighting is a
            # render pass whose every frame is unjudgeable.
            #
            # Labels are the right key: UE allows two actors to share a label
            # while their object paths differ, so a dedupe by path (above)
            # keeps both and this count sees 2.
            census = {}
            for a in actors:
                lbl = actor_label(a)
                if lbl:
                    census[lbl] = census.get(lbl, 0) + 1
            dupes = sorted(k for k, v in census.items() if v > 1)

            answered = [n for n in GALLERY
                        if "error" not in (st["compile"].get(n) or {})]
            not_stale = [n for n in answered
                         if not (st["compile"].get(n) or {}).get("bIsStale")]

            log("")
            log("--- tally ---")
            log("    level        : %s" % LVL)
            log("    level saved  : %s (file %s)"
                % (st.get("saved_level"),
                   "written" if st.get("level_written") else "NOT written"))
            log("    actors       : %d   (deduped; get_all_level_actors() "
                "returns each one twice)" % len(actors))
            log("    unique labels: %d" % len(census))
            if dupes:
                log("    DUPLICATES   : %d label(s) appear more than once"
                    % len(dupes))
                for d in dupes[:8]:
                    log("        x%d  %s" % (census[d], d))
                if len(dupes) > 8:
                    log("        ... and %d more" % (len(dupes) - 8))
            else:
                log("    DUPLICATES   : none")
            log("    materials    : 6 in %s" % MAT_DIR)
            log("    cameras      : %d" % len(cameras))
            log("    FX placed    : %d systems" % len(GALLERY))
            log("    systems saved: %s / %d"
                % (st.get("written"), len(GALLERY)))
            log("    compile      : %d/%d answered, %d of those not stale"
                % (len(answered), len(GALLERY), len(not_stale)))

            # One machine-readable verdict, because build_review.sh must be able
            # to refuse to run the render pass against a map that was never
            # written, or against a doubled one. Grepping a sentence is fragile;
            # this line is not.
            #
            # NOTE the duplicate verdict deliberately does NOT contain the
            # string "LEVEL WRITTEN": build_review.sh greps for that as a
            # substring, so a verdict like "LEVEL WRITTEN BUT DUPLICATED" would
            # have satisfied the gate while meaning the opposite.
            verdict = "LEVEL WRITTEN"
            if dupes:
                verdict = ("DUPLICATED BUILD - %d label(s) appear twice, "
                           "do not render" % len(dupes))
            elif not st.get("level_written"):
                verdict = "LEVEL NOT WRITTEN"
            log("    P20 VERDICT  : %s" % verdict)
            if len(not_stale) < len(GALLERY):
                log("")
                log("    NOTE: 'not stale' below 9/9 means the compiler had not")
                log("    finished with every system. That is reported, not")
                log("    smoothed over: a system still stale has NOT been shown")
                log("    to compile, so nothing about it is verified.")
            log("P20 DONE")
            print("P20 DONE")
        finally:
            st["busy"] = False

        st["closed"] = True
        if st["handle"] is not None:
            try:
                unreal.unregister_slate_post_tick_callback(st["handle"])
            except Exception:
                pass
        try:
            unreal.SystemLibrary.quit_editor()
        except Exception as exc:
            log("quit_editor failed: %s" % exc)
        return


try:
    STATE["handle"] = unreal.register_slate_post_tick_callback(_tick)
    # The script's own finish path is live now, so it owns the exit from here.
    WFX.watchdog_handover()
except Exception as exc:
    log("post-tick callback unavailable: %s" % exc)
    log("P20 STOPPED before save: this script needs an editor session (--editor).")
    print("P20 STOPPED")
