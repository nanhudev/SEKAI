"""
p34_asset_readback.py - read the assets themselves, because the frames say zero.

WHAT IS KNOWN
    p33 shot every gallery system twice from 3 m. All nine A/B pairs are
    byte-identical: 0 differing pixels, max channel delta 0. A forced
    `activate(reset=True)` changed nothing on screen.

    That has several possible causes and they are NOT the same bug:
        * the particles are produced but are sub-pixel / zero-sized
        * the particles are produced but render through a material that shows
          nothing (alpha 0, opaque black under a dark tonemap, unlit additive
          that never got its emissive set)
        * the particles are never produced (spawn count 0, GPU sim with no sim
          running, emitter disabled)
        * the particles are produced somewhere off-camera

    p10's lesson on this project is that a mesh measured in the wrong unit is
    an invisible mesh - the review dummies came out 100x too small because a
    metre value was divided by a centimetre baseline. So the FIRST thing to read
    is the mesh bounds, in centimetres as the engine stores them.

WHY THIS DOES NOT USE THE NIAGARA TOOLSET
    MEASURED: GetSystemCompileState / GetStackIssues never resolve once a level
    has instantiated the systems, and touching Niagara through a commandlet
    access-violates. Everything below is `get_editor_property` on loaded
    assets - plain UObject reads - so it cannot take the editor down and it does
    not need a level, a rasterizer, or a tick.

OUTPUT
    exports/p34_assets.txt

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p34_asset_readback.py --editor
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p34_assets.txt')
ROOT = "/Game/SEKAI/VFX/Sword"

MESHES = ("SM_SW_ArcSheet", "SM_SW_GlintQuad", "SM_SW_ScarStrip", "SM_SW_WaveSheet")
MASTERS = ("M_SW_Trail", "M_SW_Glint", "M_SW_Wave", "M_SW_SpatialScar",
           "M_SW_Mist", "M_SW_Mote")
INSTANCES = ("MI_SW_Trail_Normal", "MI_SW_Trail_Magic",
             "MI_SW_Glint_Normal", "MI_SW_Glint_Magic",
             "MI_SW_Wave_Normal", "MI_SW_Wave_Magic",
             "MI_SW_SpatialScar_Normal", "MI_SW_SpatialScar_Magic",
             "MI_SW_Mist_Normal", "MI_SW_Mist_Magic",
             "MI_SW_Mote_Normal", "MI_SW_Mote_Magic")
SYSTEMS = ("NS_SW_Core_EdgeTrail", "NS_SW_Core_Glint", "NS_SW_Core_AirSlice",
           "NS_SW_Core_Wave", "NS_SW_Core_SpatialScar", "NS_SW_Core_MajorArc",
           "NS_SW_Core_MistWake", "NS_SW_Core_PurpleMotes", "NS_SW_Core_Hit")

WFX.bind_log(EXPORT)
log = WFX.log

MAT_PROPS = ("blend_mode", "shading_model", "two_sided", "opacity",
             "opacity_mask_clip_value", "dithered_opacity_mask",
             "b_used_with_particle_sprites", "b_used_with_niagara_mesh_particles",
             "b_used_with_niagara_ribbons", "b_used_with_niagara_sprites",
             "b_used_with_niagara_lights", "translucency_lighting_mode",
             "b_output_translucent_velocity", "wireframe", "b_disable_depth_test")


def read_props(obj, names, indent="      "):
    got = {}
    for n in names:
        try:
            v = obj.get_editor_property(n)
            got[n] = v
            log("%s%-38s %s" % (indent, n, str(v)[:90]))
        except Exception as exc:
            log("%s%-38s <raised %s>" % (indent, n, str(exc)[:70]))
    return got


def full(path):
    return "%s.%s" % (path, path.rsplit("/", 1)[-1])


def load(path):
    try:
        return unreal.EditorAssetLibrary.load_asset(full(path))
    except Exception as exc:
        log("    load failed: %s" % str(exc)[:120])
        return None


log("engine: %s" % unreal.SystemLibrary.get_engine_version())

# ------------------------------------------------------------------ meshes
#
# The unit check. UE stores mesh geometry in centimetres, so a sheet meant to be
# 2 m across must report a box extent near 100, not near 1. A value near 1 means
# somebody authored it in metres and the renderer will draw a 1 cm sliver at any
# realistic camera distance.
log("")
log("=" * 74)
log("MESHES  (UE units are centimetres; 1.0 == 1 cm)")
log("=" * 74)
for name in MESHES:
    m = load("%s/Meshes/%s" % (ROOT, name))
    log("")
    log("--- %s  %s" % (name, "LOADED" if m else "MISSING"))
    if m is None:
        continue
    try:
        log("    class: %s" % m.get_class().get_name())
    except Exception:
        pass
    for prop in ("extended_bounds", "bounds"):
        try:
            b = m.get_editor_property(prop)
            log("    %-20s %s" % (prop, str(b)[:160]))
            for sub in ("box_extent", "sphere_radius", "origin"):
                try:
                    log("        %-16s %s" % (sub, getattr(b, sub)))
                except Exception:
                    pass
        except Exception as exc:
            log("    %-20s <raised %s>" % (prop, str(exc)[:70]))
    # Which materials are bound to it. An unbound slot draws the default grey -
    # visible, so not our bug - but a slot bound to a transparent material with
    # no emissive is exactly our bug.
    try:
        for i, mi in enumerate(m.get_editor_property("static_materials") or []):
            try:
                mp = mi.get_editor_property("material_interface")
                log("    slot %d: %s" % (i, mp.get_path_name() if mp else "None"))
            except Exception as exc:
                log("    slot %d: <raised %s>" % (i, str(exc)[:70]))
    except Exception as exc:
        log("    static_materials: <raised %s>" % str(exc)[:80])

# ------------------------------------------------------------------ materials
log("")
log("=" * 74)
log("MATERIALS")
log("=" * 74)
for name in MASTERS + INSTANCES:
    is_mi = name.startswith("MI_")
    m = load("%s/Materials/%s" % (ROOT, name))
    log("")
    log("--- %s  %s" % (name, "LOADED" if m else "MISSING"))
    if m is None:
        continue
    if is_mi:
        try:
            par = m.get_editor_property("parent")
            log("    parent: %s" % (par.get_path_name() if par else "None"))
        except Exception as exc:
            log("    parent: <raised %s>" % str(exc)[:70])
        # Read the base properties through the instance too: an instance can
        # override blend mode, and the renderer uses the instance.
    read_props(m, MAT_PROPS, "    ")

# ------------------------------------------------------------------ systems
log("")
log("=" * 74)
log("SYSTEMS  (user parameters, then emitter identity)")
log("=" * 74)
for name in SYSTEMS:
    s = load("%s/Systems/%s" % (ROOT, name))
    log("")
    log("--- %s  %s" % (name, "LOADED" if s else "MISSING"))
    if s is None:
        continue

    # User parameter DEFAULT VALUES. These are the numbers the graph evaluates
    # when the component does not override them, so a zero here is a system that
    # provably emits nothing regardless of material.
    try:
        store = s.get_editor_property("exposed_parameters")
        names = None
        for attr in ("parameter_names", "ParameterNames"):
            try:
                names = getattr(store, attr)
                break
            except Exception:
                continue
        if names is None:
            try:
                names = store.get_editor_property("parameter_names")
            except Exception as exc:
                log("    parameter_names unavailable: %s" % str(exc)[:80])
        if names:
            for pn in list(names)[:40]:
                try:
                    v = store.get_parameter_value(str(pn))
                    log("    User %-26s = %s" % (pn, str(v)[:70]))
                except Exception:
                    log("    User %-26s <unreadable>" % pn)
    except Exception as exc:
        log("    exposed_parameters: <raised %s>" % str(exc)[:100])

    # Emitter handles: name + simulated target. A GPU emitter with no sim
    # running emits nothing, and CPU/GPU is not something the frame can show.
    try:
        handles = s.get_editor_property("emitter_handles")
        log("    emitter handles: %d" % len(handles or []))
        for h in handles or []:
            try:
                hn = h.get_editor_property("name")
            except Exception:
                hn = "?"
            tgt = "?"
            try:
                em = h.get_instance()
                tgt = em.get_editor_property("sim_target")
            except Exception as exc:
                tgt = "<%s>" % str(exc)[:50]
            log("      %-24s sim_target=%s" % (hn, tgt))
    except Exception as exc:
        log("    emitter_handles: <raised %s>" % str(exc)[:100])

    # Does the system have ANY renderer enabled? An emitter with every renderer
    # disabled emits into nothing, which is indistinguishable from broken.
    try:
        log("    renderer count: %s"
            % len(s.get_editor_property("renderer_properties") or []))
    except Exception as exc:
        log("    renderer count: <raised %s>" % str(exc)[:80])

log("")
log("--- reading done ---")
log("")
log("HOW TO READ THIS")
log("  1. mesh box_extent near 0.5-2.0 instead of 50-200  -> the meshes are in")
log("     metres and draw 100x too small. Same bug class as the review dummies.")
log("  2. blend_mode == Translucent with opacity 0, or an unlit additive with")
log("     no emissive connection -> the particles render as nothing.")
log("  3. a User parameter that drives spawn count or rate reading 0 -> the")
log("     system emits nothing, and no material change can fix it.")
log("  4. sim_target == GPU -> a GPU emitter whose simulation never ran.")
log("P34 DONE")
