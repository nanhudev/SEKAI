"""SEKAI Sword VFX - P31: what is actually IN L_SwordVFX_Lab?

WHY

    P21's five QA frames were the first this lab ever produced, and they show a
    LIT but essentially EMPTY pad: ground, a bright wall, sky - and no dummies,
    no Niagara gallery.

    p20_review_map.py's own report claims otherwise:

        ground 60x60 m, bright wall at +20 m, dark wall at -20 m
        dummies (1.80 m tall, 0.30 m radius)
        8 ring dummies at 4 m, 45 degrees apart
        NS_SW_Core_AirSlice  placed at y=-1200.0   ... 9 systems placed
        actors : 34

    Two possibilities, and they need completely different responses:

        (a) the actors ARE in the saved level and the QA cameras simply do not
            point at them - a framing bug, fixed by moving cameras;
        (b) the actors were spawned into a session and NEVER SAVED, so the level
            on disk is a much older, emptier build - an authoring/save bug.

    p20's own docstring warns about exactly (b): "`save_current_level()` reports
    SUCCESS and writes NOTHING in this session - measured: it logged
    'save_current_level via LevelEditorSubsystem' while the file ...". A claim
    of placement is not evidence of persistence, and five frames that show an
    empty pad are evidence that SOMETHING disagrees.

    This reads the level and counts what is there, by label. It does not repair.

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p31_audit_level.py --editor
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p31_level_audit.txt')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
UMAP = (str(_SEKAI_ROOT / 'ue5_lab/SwordVFX_Lab/Content')
        + LVL[len("/Game"):] + ".umap")

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
        unreal.log("P31 " + msg)
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


log("engine: " + unreal.SystemLibrary.get_engine_version())
if os.path.exists(UMAP):
    st = os.stat(UMAP)
    import time as _t
    log("level file : %s" % UMAP)
    log("             %d bytes, mtime %s"
        % (st.st_size, _t.strftime("%Y-%m-%d %H:%M:%S",
                                   _t.localtime(st.st_mtime))))
else:
    log("level file : MISSING at %s" % UMAP)

for label, obj in subsystems():
    if not hasattr(obj, "load_level"):
        continue
    try:
        obj.load_level(LVL)
        log("level loaded via %s" % label)
        break
    except Exception as exc:
        log("load_level via %s failed: %s" % (label, str(exc)[:110]))

raw = []
for label, obj in subsystems():
    if not hasattr(obj, "get_all_level_actors"):
        continue
    try:
        raw = obj.get_all_level_actors()
        break
    except Exception:
        continue

seen = {}
for a in raw:
    try:
        key = a.get_path_name()
    except Exception:
        key = str(id(a))
    if key in seen:
        continue
    try:
        label = a.get_actor_label()
        cls = a.get_class().get_name()
    except Exception:
        label, cls = "?", "?"
    seen[key] = (label, cls)

log("")
log("actors in the level: %d (deduped from %d)" % (len(seen), len(raw)))

# group by class, and by whether the label matches the expected families
by_class = {}
for label, cls in seen.values():
    by_class.setdefault(cls, []).append(label)
log("")
log("--- by class ---")
for cls in sorted(by_class, key=lambda c: -len(by_class[c])):
    log("    %-34s %3d   %s" % (cls, len(by_class[cls]),
                                ", ".join(sorted(by_class[cls])[:4])))

FAMILIES = {
    "cameras  (Review_*)": lambda l: l.startswith("Review_"),
    "dummies  (Lab_Dummy*)": lambda l: "Dummy" in l,
    "niagara gallery": lambda l: l.startswith("NS_") or "Niagara" in l,
    "walls    (Lab_Wall*)": lambda l: "Wall" in l,
    "ground   (Lab_Ground*)": lambda l: "Ground" in l or "Floor" in l,
    "lights   (*Light*)": lambda l: "Light" in l or "Sun" in l,
    "capture  (probe)": lambda l: "Capture" in l,
}
log("")
log("--- the families section 30/31 need ---")
missing = []
for name, pred in FAMILIES.items():
    hits = sorted(l for l in (v[0] for v in seen.values()) if pred(l))
    log("    %-24s %3d   %s" % (name, len(hits), ", ".join(hits[:6])))
    if not hits:
        missing.append(name)

log("")
log("--- reading ---")
n_dummy = len([1 for l in (v[0] for v in seen.values()) if "Dummy" in l])
n_gallery = len([1 for l in (v[0] for v in seen.values())
                 if l.startswith("NS_")])
n_cam = len([1 for l in (v[0] for v in seen.values())
             if l.startswith("Review_")])
if n_cam == 0:
    log("    NO CAMERAS in the saved level, yet p21 rendered five named shots.")
    log("    => p21's cameras come from somewhere else, so p21 is NOT reading")
    log("       this level. That is the thing to fix first.")
elif n_gallery == 0 and n_dummy == 0:
    log("    The cameras are here but the DUMMIES and the GALLERY are not.")
    log("    => these were spawned in a session and never saved. The five QA")
    log("       frames are of the level's ground and walls only. What p20's")
    log("       report calls 'placed' is placement in memory, which is why")
    log("       p30's mtime check on the .umap exists.")
elif n_dummy == 0 or n_gallery == 0:
    log("    PARTIAL: dummies=%d gallery=%d. See the family counts above." %
        (n_dummy, n_gallery))
else:
    log("    Dummies (%d) and gallery (%d) ARE in the saved level, with %d"
        % (n_dummy, n_gallery, n_cam))
    log("    cameras. So the empty-looking QA frames are a FRAMING problem, not")
    log("    a persistence problem: the cameras do not point at the content.")
    log("    Check the gallery's y-extent against the camera directions - the")
    log("    gallery is spread along Y from -1200 to +1200 cm while the QA")
    log("    cameras look along +X, which would put it past the frame edge.")

log("")
log("P31 VERDICT: %d actors, %d cameras, %d dummies, %d gallery"
    % (len(seen), n_cam, n_dummy, n_gallery))
log("P31 DONE")
print("P31 DONE")
try:
    unreal.SystemLibrary.quit_editor()
except Exception:
    pass
