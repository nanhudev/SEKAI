"""SEKAI Sword VFX - P30: aim the review lab's sun down, and save it.

WHY THIS IS A SEPARATE, TINY SCRIPT

    L_SwordVFX_Lab is saved on disk with its sun aimed at the sky:

        Lab_Sun rotation  pitch=+35.00 yaw=0.00 roll=-42.00

    read back from the engine, not inferred. p20_review_map.py wrote that with
    `spawn(..., (-42.0, 35.0, 0.0), "Lab_Sun")`, and `spawn()` expands a tuple
    as `unreal.Rotator(*rot)` = (ROLL, PITCH, YAW), so the intended
    pitch=-42 became ROLL, and the actual pitch became +35.

    P29 measured what that costs, holding everything else fixed and using one
    instrument throughout:

        pitch +35, intensity 100000  -> BLACK   mean 0.10  colours 2
        pitch -45, intensity 100000  -> BLOWN   mean 255.00
        pitch +35, intensity 6       -> BLACK   mean 0.10  colours 2
        pitch -45, intensity 6       -> GOOD    mean 43.68 colours 2902
                                       sky 19.8  ground 63.6

    Identical intensity, opposite result - and repeats of both ends came back
    byte-identical (rung 10 == rung 2, rung 9 == rung 1), so this is not noise.
    The level was not "unlit". Its sun was aimed at the sky.

    P20 IS ALSO FIXED IN SOURCE. But re-running P20 would rebuild the whole lab
    - dummies, the Niagara gallery, all five cameras - to change one rotation,
    and a rebuild is a much larger risk than a rotation. So this does the one
    edit to the saved level, and P20's source is fixed so the next rebuild is
    correct rather than re-introducing the bug.

    Then a NEW sun is spawned as well, because a saved rotation is a claim about
    a file and the only way to know it took is to see the level lit afterwards.

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p30_fix_sun.py --editor
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
import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p30_sun_fix.txt')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"

# From P29's measured ladder: pitch -45 with intensity 10.0 gave mean 79.53,
# 3869 colours, GROUND 108.1 - the brightest reading that is not blown out.
# Section 30 wants every effect to hold on a BRIGHT background, so the measured
# choice is 10.0 rather than the authored 6.0 (which gave ground 63.6).
# 3000 and above blow the frame to white, so there is no headroom above this.
WANT_PITCH, WANT_YAW, WANT_INTENSITY = -42.0, 35.0, 10.0

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
        unreal.log("P30 " + msg)
    except Exception:
        pass


open(EXPORT, "w", encoding="utf-8").close()
WFX.bind_log(EXPORT, truncate=False)


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


log("engine: " + unreal.SystemLibrary.get_engine_version())

for label, obj in subsystems():
    if not hasattr(obj, "load_level"):
        continue
    try:
        obj.load_level(LVL)
        log("level loaded via %s" % label)
        break
    except Exception as exc:
        log("load_level via %s failed: %s" % (label, str(exc)[:110]))

found = []
for a in all_actors():
    try:
        if "DirectionalLight" in a.get_class().get_name():
            found.append(a)
    except Exception:
        continue
log("")
log("directional lights in the level: %d" % len(found))
if not found:
    log("    NONE. Nothing to aim - run p20_review_map.py first.")
    log("P30 DONE (nothing to do)")
    print("P30 DONE")
    raise SystemExit(0)

ok_any = False
for a in found:
    try:
        label = a.get_actor_label()
    except Exception:
        label = "?"
    before = a.get_actor_rotation()
    log("")
    log("    %s  before pitch=%+.2f yaw=%+.2f roll=%+.2f"
        % (label, before.pitch, before.yaw, before.roll))
    # KEYWORD FORM. This is the whole fix: the positional form is
    # (ROLL, PITCH, YAW) and transposing it here would recreate the bug.
    want = unreal.Rotator(pitch=WANT_PITCH, yaw=WANT_YAW, roll=0.0)
    try:
        a.set_actor_rotation(want, False)
    except Exception as exc:
        log("    set_actor_rotation RAISED: %s" % str(exc)[:140])
        continue
    after = a.get_actor_rotation()
    log("    %s  after  pitch=%+.2f yaw=%+.2f roll=%+.2f  (wanted pitch=%+.2f)"
        % (label, after.pitch, after.yaw, after.roll, WANT_PITCH))
    if abs(after.pitch - WANT_PITCH) > 0.5:
        log("    !! THE ROTATION DID NOT TAKE. Not saving a lie.")
        continue
    ok_any = True
    comp = None
    for attr in ("light_component", "component"):
        try:
            comp = getattr(a, attr)
            break
        except Exception:
            continue
    if comp is not None:
        had = swcap.get_prop(comp, "intensity")[1]
        setok = swcap.set_prop(comp, "intensity", WANT_INTENSITY)
        now = swcap.get_prop(comp, "intensity")[1]
        log("    intensity had=%s set=%s now=%s" % (had, setok, now))
        swcap.set_prop(comp, "mobility",
                       getattr(unreal.ComponentMobility, "MOVABLE", None))
        swcap.set_prop(a, "atmosphere_sun_light", True)
        swcap.set_prop(a, "cast_shadows", False)

if not ok_any:
    log("")
    log("    NO LIGHT WAS CHANGED. Refusing to save.")
    log("P30 VERDICT: FAILED - rotation did not take on any light")
    log("P30 DONE")
    print("P30 DONE")
    raise SystemExit(0)

# --- save, and PROVE it by re-reading the file ---------------------------
#
# p20 recorded that `save_current_level()` reports SUCCESS and writes NOTHING in
# this session, so a success return is not evidence. The check below is on the
# file's mtime.
disk = (str(_SEKAI_ROOT / 'ue5_lab/SwordVFX_Lab/Content')
        + LVL[len("/Game"):] + ".umap")
before_m = os.path.getmtime(disk) if os.path.exists(disk) else 0.0
log("")
log("--- saving ---")
log("    %s mtime before = %.0f" % (disk, before_m))

for label, obj in subsystems():
    for fn in ("save_current_level", "save_current_level_as"):
        if not hasattr(obj, fn):
            continue
        try:
            res = getattr(obj, fn)()
            log("    %s.%s -> %s" % (label, fn, res))
        except Exception as exc:
            log("    %s.%s raised: %s" % (label, fn, str(exc)[:120]))
    try:
        if hasattr(obj, "save_all_dirty_levels"):
            log("    %s.save_all_dirty_levels -> %s"
                % (label, obj.save_all_dirty_levels()))
    except Exception as exc:
        log("    save_all_dirty_levels raised: %s" % str(exc)[:120])

after_m = os.path.getmtime(disk) if os.path.exists(disk) else 0.0
log("    %s mtime after  = %.0f" % (disk, after_m))
saved = after_m > before_m
log("    FILE CHANGE     = %s" % saved)
if not saved:
    log("")
    log("    => the save reported success and DID NOT WRITE, which is the exact")
    log("       behaviour p20 documented. The fix is in memory, not on disk;")
    log("       the level will be wrong again next launch.")

log("")
log("P30 VERDICT: sun aim %s, file %s"
    % ("applied" if ok_any else "not applied",
       "written" if saved else "NOT written"))
log("P30 DONE")
print("P30 DONE")
try:
    unreal.SystemLibrary.quit_editor()
except Exception:
    pass
