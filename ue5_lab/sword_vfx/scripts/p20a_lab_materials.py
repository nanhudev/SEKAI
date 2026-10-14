"""SEKAI Sword VFX - P20a: the L_SwordVFX_Lab surface materials.

RUN AS A COMMANDLET (the default of run_ue.sh):

    ./run_ue.sh F:/SEKAI/ue5_lab/sword_vfx/scripts/p20a_lab_materials.py

WHY THE SURFACES ARE A SEPARATE, COMMANDLET STEP

Not because a commandlet is the only place material graphs can be authored -
that was the first theory and it was WRONG. The two sessions genuinely need
different things, and that is the honest reason:

    P20   must be an editor session. It needs ticks: the Niagara gallery has to
          register components and let the systems compile before the packages
          are saved. A commandlet has no ticks at all, so it cannot do that.
    P20a  needs no ticks and no Niagara compile. A commandlet is faster, has no
          editor loop to leak, and keeps P20's launch shorter and its failure
          modes single.

WHAT WENT WRONG THE FIRST TIME, BECAUSE IT IS THE POINT

While splitting these, `build()` passed the string "BASE_COLOR" where
`MaterialEditingLibrary.connect_material_property` wants the EMaterialProperty
enum:

    TypeError: NativizeEnumEntry: Cannot nativize 'str' as 'MaterialProperty'

Two engine launches were then spent on wrong root causes - first
"EditorAssetLibrary.save_asset hangs the editor", then "authoring a material
graph hangs in a -nullrhi editor session" - because the symptom was a process
that stayed alive with its own log stopping mid-sentence.

The actual behaviour, which is worth more than the fix: with
`-ExecCmds="py <file>"` an uncaught python exception is written to
Saved/Logs/SwordVFX_Lab.log and then SWALLOWED. The editor keeps running and
never reaches `quit_editor()`, so it looks exactly like a deadlock. The script's
own export file cannot see the traceback - only the engine log can. Two
consequences, both now in place:

  * `swmat.material_property()` resolves the name and prints the valid members
    when it does not exist, so a typo names itself instead of presenting as a
    hang.
  * `swvfx.install_watchdog()` makes every editor-mode script in this pipeline
    quit itself if its body never reaches its own finish path.

The lesson generalises past this file: in editor mode, an exception is a
liveness bug, not just an error. Check Saved/Logs before theorising about
native deadlocks.

The surfaces carry controlled albedo and nothing else. They are deliberately
NOT lit showcases: a near-white wall is what proves a white stroke still reads
(brief section 30), and a mid-grey ground is the neutral the contact family is
judged against.
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swmat as MAT  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p20a_lab_materials.txt')
LVL_DIR = "/Game/SEKAI/VFX/Sword/Lab"
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


def _mark(what):
    """Name the call before making it - see P20 for why."""
    log("        . %s" % what)


# name, base colour, roughness, metallic, emissive, why
SPECS = [
    ("M_Lab_BrightWall", (0.900, 0.905, 0.900), 0.42, 0.0, None,
     "near-white; A2's sheet and A3's marks are read against this"),
    ("M_Lab_DarkWall", (0.030, 0.030, 0.034), 0.60, 0.0, None,
     "the opposite check, behind the caster"),
    ("M_Lab_Stone", (0.320, 0.310, 0.300), 0.78, 0.0, None,
     "neutral-warm substrate; A1's cut lands here"),
    ("M_Lab_Grass", (0.145, 0.215, 0.115), 0.85, 0.0, None,
     "darker, saturated substrate; A2 rises over this half"),
    ("M_Lab_Dummy", (0.360, 0.330, 0.330), 0.62, 0.0, None,
     "the hit family's read: near, mid, far and surround"),
    ("M_Lab_GroundFar", (0.240, 0.245, 0.240), 0.80, 0.0, None,
     "the 60x60 m ground the split planes sit on"),
]


def build(name, color, roughness, metallic, emissive):
    """One flat opaque surface material."""
    _mark("%s: make_material" % name)
    mat = MAT.make_material(MAT_DIR, name)
    if mat is None:
        return None
    _mark("%s: graph" % name)
    base = MAT.const3(mat, color[0], color[1], color[2], -400, 0)
    MAT.to_property(base, "", "BASE_COLOR")
    r = MAT.const(mat, roughness, -400, 180)
    MAT.to_property(r, "", "ROUGHNESS")
    m = MAT.const(mat, metallic, -400, 300)
    MAT.to_property(m, "", "METALLIC")
    if emissive:
        e = MAT.const3(mat, emissive[0], emissive[1], emissive[2], -400, 420)
        MAT.to_property(e, "", "EMISSIVE_COLOR")
    MAT.set_prop(mat, "two_sided", False)
    MAT.set_prop(mat, "shading_model", unreal.MaterialShadingModel.MSM_DEFAULT_LIT)
    _mark("%s: recompile" % name)
    try:
        unreal.MaterialEditingLibrary.recompile_material(mat)
    except Exception as exc:
        log("        recompile warned: %s" % str(exc)[:120])
    _mark("%s: save" % name)
    full = "%s/%s" % (MAT_DIR, name)
    try:
        unreal.EditorAssetLibrary.save_loaded_asset(mat, only_if_is_dirty=False)
    except Exception as exc:
        log("        save warned: %s" % str(exc)[:120])
    return full


def disk_path(pkg):
    return (str(_SEKAI_ROOT / 'ue5_lab/SwordVFX_Lab/Content')
            + pkg[len("/Game"):] + ".uasset")


log("engine: " + unreal.SystemLibrary.get_engine_version())

# Refuse to run in an editor session. Without this guard, running this script
# with --editor reproduces exactly the silent hang this file exists to avoid,
# and it costs several minutes to discover. Read the command line rather than
# guessing from behaviour.
cmdline = ""
try:
    cmdline = unreal.SystemLibrary.get_command_line()
except Exception:
    pass
if "-run=pythonscript" not in cmdline:
    log("")
    log("REFUSING TO RUN: this script must be a commandlet, got:")
    log("    %s" % cmdline[:300])
    log("Use:  ./run_ue.sh <this file>        (no --editor)")
    log("P20A REFUSED")
    print("P20A REFUSED")
    raise SystemExit(0)

log("commandlet confirmed")
log("")
log("--- lab surface materials -> %s ---" % MAT_DIR)

results = []
for name, color, rough, metal, emis, why in SPECS:
    log("")
    log("    %s" % name)
    log("        %s" % why)
    full = build(name, color, rough, metal, emis)
    # `disk_path` is defined below in this file, not in swmat - it is only used
    # for the on-disk verification and has no business in the material library.
    results.append((name, full, disk_path(full) if full else None))

log("")
log("--- verification (by file on disk, not by a return code) ---")
ok = 0
for name, full, disk in results:
    exists = bool(disk) and os.path.exists(disk)
    size = os.path.getsize(disk) if exists else 0
    ok += 1 if (exists and size > 1000) else 0
    log("    %-20s %-8s %8d bytes   %s"
        % (name, "written" if exists else "MISSING", size,
           "pkg=%s" % full if full else "build FAILED"))

log("")
log("--- tally ---")
log("    materials written : %d / %d" % (ok, len(SPECS)))
log("    directory         : %s" % MAT_DIR)
log("")
log("    P20 consumes these; it does not author them. If any row above is")
log("    MISSING, run this script again before running P20.")
log("P20A DONE")
print("P20A DONE")
