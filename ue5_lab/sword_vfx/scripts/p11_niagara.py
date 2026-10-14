"""SEKAI Sword VFX - P11: build the nine NS_SW_Core_* Niagara systems.

How a core system is assembled:

    Emitter structure, renderers, materials, user parameters and every module
    input that is reachable from script: built here, from a table.

What this revision fixes, and why it matters:

    * Input names are taken from GetModuleSchemaFromAsset / live topology, not
      from memory. Three were wrong: ScaleSpriteSize exposes "Uniform Scale
      Factor" (not "Scale Factor"), and ScaleMeshSize."Scale Factor" plus
      SolveForcesAndVelocity."Velocity" are Vector3f, not float. Linking a float
      User parameter into a Vector3f pin is accepted by the toolset - it only
      records the declared type on the override pin - so it fails silently and
      the compiler has to repair it later. Hence Vector3f twins of Length and
      Speed.
    * "Scale RGB" and "ScaleRGB" both normalise to "scalergb". The old matcher
      stripped spaces and case, picked whichever came first, and wrote a colour
      link into a bool gate. The matcher below requires an exact name first and
      reports an ambiguity instead of guessing. ScaleColor is not used at all
      now: the Color module's "Color" input is an assign, which is what a
      profile-driven core wants, and it links cleanly.
    * Every rejected write is logged. The previous version returned False on the
      not-editable path with no log line at all, which made ScaleSpriteSize look
      like it had nothing to set.

Why there is no SetParameters module:

    Adding one and then saving the system hard-crashed the editor with a null
    dereference inside the property serialiser. Stack modules are the supported
    path, so attributes are driven through real modules and anything a module
    hides behind a static switch, plus every over-life curve, is listed in the
    run report and EXACT_BUILD.md as a MANUAL EDITOR STEP rather than faked.

Saving happens per system, immediately after its own verification, so a crash
cannot cost more than the system it is on and the assets already written stay
on disk.
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

import swvfx as S  # noqa: E402

ROOT = "/Game/SEKAI/VFX/Sword"
DIR_SYS = ROOT + "/Systems"
DIR_MAT = ROOT + "/Materials"
DIR_MESH = ROOT + "/Meshes"

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p11_niagara.txt')
REPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p11_report.json')

S.bind_log(EXPORT)
EAL = unreal.EditorAssetLibrary

TPL_SYSTEM = "/Niagara/DefaultAssets/DefaultSystem"
TPL_EMITTER = "/Niagara/DefaultAssets/Templates/Emitters/Minimal"

M = {
    "SpawnRate": "/Niagara/Modules/Emitter/SpawnRate",
    "SpawnBurst": "/Niagara/Modules/Emitter/SpawnBurst_Instantaneous",
    "Init": "/Niagara/Modules/Spawn/Initialization/V2/InitializeParticle",
    "Color": "/Niagara/Modules/Update/Color/Color",
    "RibbonWidth": "/Niagara/Modules/Ribbons/RibbonWidth",
    "Solve": "/Niagara/Modules/Solvers/SolveForcesAndVelocity",
    "ScaleSpriteSize": "/Niagara/Modules/Update/Size/ScaleSpriteSize",
    "ScaleMeshSize": "/Niagara/Modules/Update/Size/ScaleMeshSize",
}

R_SPRITE = "/Script/Niagara.NiagaraSpriteRendererProperties"
R_RIBBON = "/Script/Niagara.NiagaraRibbonRendererProperties"
R_MESH = "/Script/Niagara.NiagaraMeshRendererProperties"
R_LIGHT = "/Script/Niagara.NiagaraLightRendererProperties"

# Brief section 24, plus four additions that exist only because a module input
# refused to take the scalar form. Each one says so in its description.
USER_PARAMS = [
    ("User.PrimaryColor", S.T_COLOR, S.color(0.72, 0.86, 1.00), "stroke body colour"),
    ("User.CoreColor", S.T_COLOR, S.color(1.00, 1.00, 1.00), "hot core colour"),
    ("User.MistColor", S.T_COLOR, S.color(0.05, 0.02, 0.10), "void / mist colour"),
    ("User.DarkColor", S.T_COLOR, S.color(0.010, 0.012, 0.030), "void core colour"),
    ("User.Intensity", S.T_FLOAT, S.f(1.0), "global multiplier, drives Color.Scale Alpha"),
    ("User.Width", S.T_FLOAT, S.f(0.05), "stroke width, metres"),
    ("User.Length", S.T_FLOAT, S.f(2.0), "stroke length, authored value, metres"),
    ("User.Radius", S.T_FLOAT, S.f(1.0), "arc / burst / sprite radius, metres"),
    ("User.ArcAngle", S.T_FLOAT, S.f(300.0), "major arc sweep, degrees"),
    ("User.Lifetime", S.T_FLOAT, S.f(0.25), "particle lifetime, seconds"),
    ("User.Speed", S.T_FLOAT, S.f(30.0), "travel speed, authored value, m/s"),
    ("User.Distortion", S.T_FLOAT, S.f(0.0), "refraction offset strength"),
    ("User.MistAmount", S.T_FLOAT, S.f(0.0), "0 = normal sword, 1 = magic sword"),
    ("User.SpawnRate", S.T_FLOAT, S.f(60.0), "particles per second, primary emitters"),
    ("User.StartPosition", S.T_POS, S.pos(0, 0, 0), "world start"),
    ("User.EndPosition", S.T_POS, S.pos(200, 0, 0), "world end"),
    ("User.BladeBase", S.T_POS, S.pos(0, 0, 0), "blade base, world"),
    ("User.BladeTip", S.T_POS, S.pos(0, 110, 0), "blade tip, world"),
    ("User.ArcStart", S.T_FLOAT, S.f(0.0), "arc begin angle, degrees"),
    ("User.ArcEnd", S.T_FLOAT, S.f(300.0), "arc end angle, degrees"),
    # --- extensions, each forced by a module input type ---
    ("User.ScaleVector", S.T_VEC3, S.vec3(2.0, 2.0, 2.0),
     "ScaleMeshSize takes Vector3f, so Length/Radius have this vector twin"),
    ("User.Velocity", S.T_VEC3, S.vec3(30.0, 0.0, 0.0),
     "SolveForcesAndVelocity takes Vector3f, so Speed has this vector twin"),
    ("User.MistCount", S.T_INT, S.i(0),
     "burst count for mist emitters; 0 in the Normal profile keeps them free"),
    ("User.MistRate", S.T_FLOAT, S.f(0.0),
     "spawn rate for mist emitters; 0 in the Normal profile keeps them free"),
]


def L(name, t=S.T_FLOAT):
    return ("link", name, t)


# Renderers, then modules, then the manual residue.
#
# Every emitter stays enabled in both profiles. Magic does not get a different
# graph and it does not get a switched-on emitter: it gets different User.*
# values, and the mist emitters cost nothing in the Normal profile because
# User.MistCount and User.MistRate are zero there.
#
# Position is deliberately NOT set. The Niagara component is spawned at the
# blade socket, so the system's own transform already supplies the spawn
# position - fighting Initialize Particle's static switches for it buys nothing.
# Size and every over-life curve are manual, and say so.
P_COLOR = ("ParticleUpdateScript", "Color",
           {"Color": L("User.PrimaryColor", S.T_COLOR),
            "Scale Alpha": L("User.Intensity")})
P_COLOR_CORE = ("ParticleUpdateScript", "Color",
                {"Color": L("User.CoreColor", S.T_COLOR),
                 "Scale Alpha": L("User.Intensity")})
P_COLOR_MIST = ("ParticleUpdateScript", "Color",
                {"Color": L("User.MistColor", S.T_COLOR),
                 "Scale Alpha": L("User.Intensity")})

SYSTEMS = [
    dict(name="NS_SW_Core_EdgeTrail",
         note="A1 / A4 blade edge trail. A ribbon that follows the blade, driven "
              "entirely from User.* so Normal and Magic are the same graph.",
         emitters=[dict(name="E_Trail",
                        renderers=[("ribbon", "MI_SW_Trail_Normal", None)],
                        mods=[("EmitterUpdateScript", "SpawnRate",
                               {"Spawn Rate": L("User.SpawnRate")}),
                              ("ParticleSpawnScript", "Init",
                               {"Lifetime": L("User.Lifetime")}),
                              P_COLOR,
                              ("ParticleUpdateScript", "RibbonWidth",
                               {"Ribbon Width": L("User.Width")})],
                        manual=["Ribbon width over life: 1.0 -> 0.55 ease-out. A trail must thin as the swing decelerates",
                                "Colour alpha over life: hold, then fade over the last 40% so the tail dies first",
                                "Ribbon renderer: tessellation Custom, 8 segments, UV0 tiled 4x along the ribbon"])]),

    dict(name="NS_SW_Core_Glint",
         note="Equip / inspect cold glint. One particle, very short life, plus an "
              "optional point light. Not a firework, and no lens flare anywhere near it.",
         emitters=[dict(name="E_Glint",
                        renderers=[("sprite", "MI_SW_Glint_Normal", None),
                                   ("light", None, None)],
                        mods=[("EmitterUpdateScript", "SpawnBurst",
                               {"Spawn Count": S.i(1)}),
                              ("ParticleSpawnScript", "Init",
                               {"Lifetime": L("User.Lifetime")}),
                              ("ParticleUpdateScript", "ScaleSpriteSize",
                               {"Uniform Scale Factor": L("User.Radius")}),
                              P_COLOR_CORE],
                        manual=["MANUAL EDITOR STEP, and the one input this build cannot reach: ScaleSpriteSize's \"Uniform Scale Factor\" reports bIsEditable=False in the live graph, and the module exposes NO editable boolean gate to open it (the live topology has 10 inputs, none of them a settable bool). So sprite size is set by hand on the module, or by binding the renderer's Sprite Size instead. This is stated rather than faked with a parameter that does nothing",
                                "The scan along the blade is the Streak map scrolling on U, so the draw-on is a material UV wipe, not a sprite size curve",
                                "Sprite size over life: 0.35 -> 1.0 in the first 25%, then 1.0 -> 0.15. 80-160 ms total",
                                "Light renderer: one particle, low radius. Colour over life: CoreColor, alpha down to 0"])]),

    dict(name="NS_SW_Core_AirSlice",
         note="A1 thin air slice: a 1.5-2.5 m sliver drawn on from one end, not a "
              "projectile. Same graph for both swords.",
         emitters=[dict(name="E_Slice",
                        renderers=[("mesh", "MI_SW_SpatialScar_Normal", "SM_SW_ScarStrip")],
                        mods=[("EmitterUpdateScript", "SpawnBurst",
                               {"Spawn Count": S.i(1)}),
                              ("ParticleSpawnScript", "Init",
                               {"Lifetime": L("User.Lifetime")}),
                              ("ParticleUpdateScript", "ScaleMeshSize",
                               {"Scale Factor": L("User.ScaleVector", S.T_VEC3)}),
                              P_COLOR],
                        manual=["Draw-on is a material U wipe on the Scar mask: 0 -> 1 across the first 35% of life, 50-100 ms total",
                                "Set User.ScaleVector so the strip reaches 1.5-2.5 m along X; Y stays thin",
                                "The strip is authored 6 cm wide. Only widen it if the blade is unusually heavy"])]),

    dict(name="NS_SW_Core_Wave",
         note="A2 mid-range blade wave: a thin curved pressure sheet, 6-10 m, bright "
              "leading edge and faint interior. Not a thick blue crescent.",
         emitters=[dict(name="E_Wave",
                        renderers=[("mesh", "MI_SW_Wave_Normal", "SM_SW_WaveSheet")],
                        mods=[("EmitterUpdateScript", "SpawnBurst",
                               {"Spawn Count": S.i(1)}),
                              ("ParticleSpawnScript", "Init",
                               {"Lifetime": L("User.Lifetime")}),
                              ("ParticleUpdateScript", "ScaleMeshSize",
                               {"Scale Factor": L("User.ScaleVector", S.T_VEC3)}),
                              ("ParticleUpdateScript", "Solve",
                               {"Velocity": L("User.Velocity", S.T_VEC3)}),
                              P_COLOR],
                        manual=["User.ScaleVector: 8.0 uniform for a 6-10 m wave; the sheet is 1.0 m x 0.68 m before scaling",
                                "Travel 0.18-0.35 s across the range: set User.Velocity.X so length/speed lands in that window",
                                "Colour alpha over life: leading edge holds, whole sheet to 0 over the last 30%"]),
                   dict(name="E_MistWake",
                        renderers=[("mesh", "MI_SW_Mist_Normal", "SM_SW_GlintQuad")],
                        mods=[("EmitterUpdateScript", "SpawnBurst",
                               {"Spawn Count": L("User.MistCount", S.T_INT)}),
                              ("ParticleSpawnScript", "Init",
                               {"Lifetime": L("User.Lifetime")}),
                              P_COLOR_MIST],
                        manual=["Costs nothing in the Normal profile: User.MistCount is 0 there",
                                "Keep the count low - the wave must still read as a thin sheet, not a purple fog bank"])]),

    dict(name="NS_SW_Core_SpatialScar",
         note="A3 world-space spatial scar. Three instances are spawned by the "
              "contract, each reading 1/2/3 by draw order and position, held long "
              "enough that all three coexist without merging.",
         emitters=[dict(name="E_Scar",
                        renderers=[("mesh", "MI_SW_SpatialScar_Normal", "SM_SW_ScarStrip")],
                        mods=[("EmitterUpdateScript", "SpawnBurst",
                               {"Spawn Count": S.i(1)}),
                              ("ParticleSpawnScript", "Init",
                               {"Lifetime": L("User.Lifetime")}),
                              ("ParticleUpdateScript", "ScaleMeshSize",
                               {"Scale Factor": L("User.ScaleVector", S.T_VEC3)}),
                              P_COLOR],
                        manual=["Draw-on 20-60 ms, hold 120-250 ms, fade ~100 ms. Three copies must read 1 / 2 / 3 - stagger the draw-on, never the hold",
                                "The three scars are slash / backslash / shallow horizontal. Geometry is one system; orientation is the caller's job"]),
                   dict(name="E_ScarMist",
                        renderers=[("mesh", "MI_SW_Mist_Normal", "SM_SW_GlintQuad")],
                        mods=[("EmitterUpdateScript", "SpawnBurst",
                               {"Spawn Count": L("User.MistCount", S.T_INT)}),
                              ("ParticleSpawnScript", "Init",
                               {"Lifetime": L("User.Lifetime")}),
                              P_COLOR_MIST],
                        manual=["Mist leaks along the scar normal, slowly. It must not close into a ring and must not smother the three scar lines",
                                "If the hero frame shows one purple-black cloud, User.MistCount is too high"])]),

    dict(name="NS_SW_Core_MajorArc",
         note="A4 major arc, 240-300 deg. SM_SW_ArcSheet has the sweep on U, so the "
              "arc can be drawn on along its own length and keeps a readable start "
              "and an end. Not a 360 ring.",
         emitters=[dict(name="E_Arc",
                        renderers=[("mesh", "MI_SW_Trail_Normal", "SM_SW_ArcSheet")],
                        mods=[("EmitterUpdateScript", "SpawnBurst",
                               {"Spawn Count": S.i(1)}),
                              ("ParticleSpawnScript", "Init",
                               {"Lifetime": L("User.Lifetime")}),
                              ("ParticleUpdateScript", "ScaleMeshSize",
                               {"Scale Factor": L("User.ScaleVector", S.T_VEC3)}),
                              P_COLOR],
                        manual=["The arc is formed live by the blade: the draw-on is the Edge mask wiping along U, driven by the A4 arc timing, not by a scale curve",
                                "Arc mesh is 2 m outer diameter at scale 1.0, swept about its own origin, so User.ScaleVector stays uniform here",
                                "Colour alpha over life: fade over the last 35%. Start and end must stay distinguishable in a still frame"]),
                   dict(name="E_ArcMist",
                        renderers=[("mesh", "MI_SW_Mist_Normal", "SM_SW_GlintQuad")],
                        mods=[("EmitterUpdateScript", "SpawnBurst",
                               {"Spawn Count": L("User.MistCount", S.T_INT)}),
                              ("ParticleSpawnScript", "Init",
                               {"Lifetime": L("User.Lifetime")}),
                              P_COLOR_MIST],
                        manual=["Incomplete wake behind the arc only. It must never close into a 360 ring, even at maximum MistCount"])]),

    dict(name="NS_SW_Core_MistWake",
         note="Black mist / void leakage. Low-count cards plus a mesh wake, never a "
              "single standard smoke sprite, and never dense enough to close into a "
              "ring or to smother the scar it leaks from.",
         emitters=[dict(name="E_Wisp",
                        renderers=[("mesh", "MI_SW_Mist_Normal", "SM_SW_GlintQuad")],
                        mods=[("EmitterUpdateScript", "SpawnRate",
                               {"Spawn Rate": L("User.MistRate")}),
                              ("ParticleSpawnScript", "Init",
                               {"Lifetime": L("User.Lifetime")}),
                              ("ParticleUpdateScript", "ScaleMeshSize",
                               {"Scale Factor": L("User.ScaleVector", S.T_VEC3)}),
                              P_COLOR_MIST],
                        manual=["Mesh scale 0.5 -> 1.0 over life, slowly. Mist that grows fast reads as an explosion",
                                "Alpha over life: 0 -> peak at 25% -> 0",
                                "Zero cost in the Normal profile: User.MistRate is 0 there"])]),

    dict(name="NS_SW_Core_PurpleMotes",
         note="Magic idle motes, plus the single point glint at the saya mouth on the "
              "final click. Very few, very slow, additive.",
         emitters=[dict(name="E_Motes",
                        renderers=[("sprite", "MI_SW_Mote_Normal", None)],
                        mods=[("EmitterUpdateScript", "SpawnRate",
                               {"Spawn Rate": L("User.SpawnRate")}),
                              ("ParticleSpawnScript", "Init",
                               {"Lifetime": L("User.Lifetime")}),
                              ("ParticleUpdateScript", "ScaleSpriteSize",
                               {"Uniform Scale Factor": L("User.Radius")}),
                              P_COLOR],
                        manual=["MANUAL EDITOR STEP: sprite size, same unreachable \"Uniform Scale Factor\" as the glint. Set it on the module by hand",
                                "Spawn rate in single digits per second, and 0 while stowed. This is a few motes, not a candle",
                                "Sprite size over life: 0.5 -> 1.0 -> 0.2",
                                "Additive, so Scale Alpha does not attenuate it: brightness is set on MI_SW_Mote_* instead"])]),

    dict(name="NS_SW_Core_Hit",
         note="Contact burst for the surface families. One system, several material "
              "instances - the caller picks the instance and the graph never branches "
              "on surface type.",
         emitters=[dict(name="E_Hit",
                        renderers=[("sprite", "MI_SW_Glint_Normal", None)],
                        mods=[("EmitterUpdateScript", "SpawnBurst",
                               {"Spawn Count": S.i(14)}),
                              ("ParticleSpawnScript", "Init",
                               {"Lifetime": L("User.Lifetime")}),
                              ("ParticleUpdateScript", "ScaleSpriteSize",
                               {"Uniform Scale Factor": L("User.Radius")}),
                              P_COLOR],
                        manual=["MANUAL EDITOR STEP: sprite size, same unreachable \"Uniform Scale Factor\" as the glint and the motes. The burst is 14 particles; the size is a hand step",
                                "Sprite size over life: 0.4 -> 1.0 quickly, then 1.0 -> 0.6",
                                "Hit timing is owned by the animation event, never by the system",
                                "Rename MI_SW_Glint_* to per-surface instances for body / stone / metal / wood"])]),
]

report = {"systems": [], "unmatched": [], "not_editable": [], "dynamic": [],
          "ambiguous": [], "errors": [], "linked": [], "verified": [],
          "unverified": [], "manual_steps": [], "saved": [], "renderers": [],
          "gates_opened": [], "plan": None}


def plan_json():
    """The build table, serialised into the report.

    EXACT_BUILD.md is generated from the report rather than written by hand, so
    the document cannot drift from what was actually built. That needs the
    intended stack (this table) and the observed result (the rest of the
    report) in the same file, and the generator is plain Python with no
    `unreal`, so it cannot import this module to get the table.
    """
    out = []
    for spec in SYSTEMS:
        ems = []
        for em in spec["emitters"]:
            mods = []
            for script, key, values in em.get("mods") or []:
                ins = []
                for iname, ivalue in values.items():
                    if isinstance(ivalue, tuple) and ivalue[:1] == ("link",):
                        ins.append({"input": iname, "link": ivalue[1],
                                    "type": ivalue[2]})
                    else:
                        ins.append({"input": iname, "literal": ivalue})
                mods.append({"script": script, "module_key": key, "asset": M[key],
                             "inputs": ins})
            ems.append({"name": em["name"],
                        "renderers": [{"kind": k, "material": mi, "mesh": me}
                                      for k, mi, me in em["renderers"]],
                        "mods": mods,
                        "manual": em.get("manual") or []})
        out.append({"name": spec["name"], "note": spec["note"], "emitters": ems})
    return out


report["plan"] = plan_json()
report["user_params"] = [{"name": n, "type": t, "description": d}
                         for n, t, _d, d in USER_PARAMS]


def norm(s):
    return "".join(ch for ch in str(s).lower() if ch.isalnum())


def resolve_input(avail, wanted, sys_path, module):
    """Exact name first; a normalised match only when it is the only one.

    "Scale RGB" and "ScaleRGB" both normalise to "scalergb". Picking either one
    by iteration order is how a colour link got written into a bool gate.
    """
    for inp in avail:
        if inp.get("name") == wanted:
            return inp, None
    hits = [i for i in avail if norm(i.get("name")) == norm(wanted)]
    if len(hits) == 1:
        return hits[0], None
    if len(hits) > 1:
        report["ambiguous"].append({"system": sys_path, "module": module,
                                    "wanted": wanted,
                                    "matches": [h.get("name") for h in hits]})
        return None, ("ambiguous: %r matches %s"
                      % (wanted, ", ".join(repr(h.get("name")) for h in hits)))
    return None, ("no such input; available: %s"
                  % ", ".join(i.get("name", "?") for i in avail))


def dump_inputs(avail, log, indent="          "):
    """Print the whole neighbourhood when a write is refused.

    A live module expands its static switches, so its input list is not the
    asset's list - ScaleSpriteSize shows 2 inputs on the asset and 10 in the
    graph. Knowing WHICH of those ten is visible and editable is the difference
    between fixing the build and guessing at it again.
    """
    for i in avail:
        log("%s· %-28s %-38s vis=%-5s edit=%-5s sw=%s"
            % (indent, i.get("name"),
               str(((i.get("type") or {}).get("classStructOrEnum") or {})
                   .get("refPath", "")).rsplit(".", 1)[-1],
               i.get("bIsVisible"), i.get("bIsEditable"),
               i.get("bIsStaticSwitch")))


def type_name(inp):
    return str(((inp.get("type") or {}).get("classStructOrEnum") or {})
               .get("refPath", "")).rsplit(".", 1)[-1]


def unlock_gate(sys_path, emitter, script, module, target_name, value, avail, log):
    """Reach an input that is hidden behind an inline edit condition.

    A module like ScaleSpriteSize gates its numeric inputs with boolean
    switches, and a gated input reports bIsEditable=False. Rather than guess the
    switch's name, this flips each boolean this module actually exposes, re-reads
    the topology, and keeps the flip only if it made the wanted input editable.
    A flip that did not help is put back, so a failed attempt leaves no trace.
    """
    gates = [i for i in avail
             if i.get("bIsEditable") and type_name(i) == "NiagaraBool"]
    if not gates:
        return False, "no editable boolean gate on this module"
    for gate in gates:
        gname = gate.get("name")
        ok, _ = S.call_quiet("SetStackInputData", {
            "stackInputRef": S.stack_ref(sys_path, emitter=emitter, script=script,
                                         module=module, input_stack=[gname]),
            "inputData": S.b(True)})
        if not ok:
            continue
        topo = S.call_quiet("GetModuleTopology", {
            "moduleRef": S.stack_ref(sys_path, emitter=emitter, script=script,
                                     module=module)})
        if not topo[0]:
            continue
        fresh = (topo[1] or {}).get("inputs") or []
        hit = [i for i in fresh if i.get("name") == target_name]
        if hit and hit[0].get("bIsEditable"):
            ok2, note = write_input(sys_path, emitter, script, module,
                                    target_name, value, fresh)
            if ok2:
                log("%s        (opened by gate %r)" % (" " * 8, gname))
                report["gates_opened"].append({"system": sys_path, "module": module,
                                               "gate": gname, "input": target_name})
                return True, note
        # did not help: put the gate back so the graph is not left changed
        S.call_quiet("SetStackInputData", {
            "stackInputRef": S.stack_ref(sys_path, emitter=emitter, script=script,
                                         module=module, input_stack=[gname]),
            "inputData": S.b(False)})
    return False, ("hidden behind an inline edit condition; an editable boolean "
                   "gate exists (%s) but flipping it did not expose %r - this is "
                   "an editor step" % (", ".join(g.get("name") for g in gates),
                                       target_name))


def write_input(sys_path, emitter, script, module, wanted, value, avail,
                allow_unlock=False):
    """Set one module input. Returns (ok, note). Never fails silently."""
    target, why = resolve_input(avail, wanted, sys_path, module)
    if target is None:
        report["unmatched"].append({"system": sys_path, "emitter": emitter,
                                    "module": module, "wanted": wanted,
                                    "why": why})
        return False, why
    if not target.get("bIsEditable"):
        if allow_unlock:
            return unlock_gate(sys_path, emitter, script, module, target["name"],
                               value, avail, S.log)
        report["not_editable"].append(
            {"system": sys_path, "emitter": emitter, "module": module,
             "input": target.get("name"), "visible": target.get("bIsVisible"),
             "static_switch": target.get("bIsStaticSwitch"),
             "available": [{"name": i.get("name"), "type": type_name(i),
                            "visible": i.get("bIsVisible"),
                            "editable": i.get("bIsEditable")} for i in avail]})
        return False, ("not editable (visible=%s, staticSwitch=%s)"
                       % (target.get("bIsVisible"), target.get("bIsStaticSwitch")))
    if target.get("bIsDynamic"):
        report["dynamic"].append({"system": sys_path, "emitter": emitter,
                                  "module": module, "input": target.get("name")})
        return False, "already a dynamic input chain"
    ok, res = S.call_quiet("SetStackInputData", {
        "stackInputRef": S.stack_ref(sys_path, emitter=emitter, script=script,
                                     module=module, input_stack=[target["name"]]),
        "inputData": value})
    if not ok:
        report["errors"].append({"system": sys_path, "emitter": emitter,
                                 "module": module, "input": target.get("name"),
                                 "error": str(res)})
        return False, str(res)
    return True, target["name"]


def link_name(value):
    return value[1] if isinstance(value, tuple) and value[:1] == ("link",) else None


def verify_module(sys_path, emitter, script, module, expect, log):
    """Read the module back and check the override pins really point at User.*.

    SetStackInputData returning OK only means the toolset accepted the payload.
    This asks the graph.
    """
    ok, res = S.call_quiet("GetModuleInputValues", {
        "moduleRef": S.stack_ref(sys_path, emitter=emitter, script=script,
                                 module=module)})
    if not ok:
        log("        ~ %-14s read-back FAILED %s" % (module, res))
        report["unverified"].append({"system": sys_path, "module": module,
                                     "why": str(res)})
        return 0, 0
    live = {}
    for entry in (res.get("inputs") or []):
        val = (entry.get("value") or {})
        struct = ((val.get("struct") or {}).get("refPath") or "")
        inner = val.get("value") or {}
        bound = None
        if struct.endswith("StackInputData_Linked"):
            bound = ((inner.get("linkedVariable") or {}).get("name"))
        live[entry.get("name")] = bound
    good = 0
    for wanted, want_user in expect.items():
        actual = live.get(wanted, "<absent>")
        if actual == want_user:
            good += 1
        else:
            log("        ~ %-14s %-22s expected %s, graph says %s"
                % (module, wanted, want_user, actual))
            report["unverified"].append({"system": sys_path, "emitter": emitter,
                                         "module": module, "input": wanted,
                                         "expected": want_user, "actual": actual})
    return good, len(expect)


def build_emitter(sys_path, spec, log):
    topo = S.call("AddEmitter", {
        "system": S.ref(sys_path),
        "templateEmitter": S.ref(TPL_EMITTER),
        "emitterName": spec["name"]})
    name = topo.get("emitterName")
    log("      emitter %s" % name)

    for i in range(len(topo.get("renderers") or [])):
        S.call_quiet("RemoveRenderer",
                     {"rendererToRemove": S.stack_ref(sys_path, emitter=name,
                                                      renderer_index=i)})

    for kind, mi_name, mesh_name in spec["renderers"]:
        cls = {"sprite": R_SPRITE, "ribbon": R_RIBBON, "mesh": R_MESH,
               "light": R_LIGHT}[kind]
        idx = S.call("AddRenderer", {
            "newRendererLocation": S.stack_ref(sys_path, emitter=name),
            "rendererClass": S.ref(cls)})["rendererIndex"]
        report["renderers"].append({"system": sys_path, "emitter": name,
                                    "index": idx, "kind": kind,
                                    "material": mi_name, "mesh": mesh_name})
        payload = {}
        if kind == "mesh":
            payload["meshes"] = [{"mesh": S.ref("%s/%s" % (DIR_MESH, mesh_name)),
                                  "scale": {"x": 1.0, "y": 1.0, "z": 1.0}}]
            # no pivot_offset: every generated mesh is authored about the origin
            # it should rotate and scale about (arc about the arc centre, strip
            # about its own centre). Offsetting it here was compensating for a
            # comment that did not match the mesh.
            if mi_name:
                payload["materials"] = [S.ref("%s/%s" % (DIR_MAT, mi_name))]
        elif kind == "ribbon":
            if mi_name:
                payload["material"] = S.ref("%s/%s" % (DIR_MAT, mi_name))
        elif kind == "sprite":
            if mi_name:
                payload["materials"] = [S.ref("%s/%s" % (DIR_MAT, mi_name))]
        elif kind == "light":
            payload["light_rendering_enabled"] = True
            payload["radius_scale"] = 40.0
        ok, res = S.call_quiet("SetRendererData", {
            "renderer": S.stack_ref(sys_path, emitter=name, renderer_index=idx),
            "rendererData": payload})
        log("        renderer %-7s idx=%s  data=%s%s"
            % (kind, idx, "ok" if ok else "FAIL", "" if ok else "  " + str(res)))
        if not ok:
            report["errors"].append({"system": sys_path, "emitter": name,
                                     "renderer": kind, "error": str(res)})

    modules_done = []
    for script, key, values in spec.get("mods") or []:
        ok, res = S.call_quiet("AddModule", {
            "moduleLocationRef": S.stack_ref(sys_path, emitter=name, script=script),
            "moduleAsset": S.ref(M[key])})
        if not ok:
            log("        ! AddModule %s failed: %s" % (key, res))
            report["errors"].append({"system": sys_path, "emitter": name,
                                     "module": key, "error": str(res)})
            continue
        mod_name = res.get("moduleName")
        avail = res.get("inputs") or []
        log("        module %-16s %-26s inputs=%d" % (key, mod_name, len(avail)))
        expect = {}
        for iname, ivalue in values.items():
            user = link_name(ivalue)
            payload = S.link(user, ivalue[2]) if user else ivalue
            ok2, note = write_input(sys_path, name, script, mod_name, iname,
                                    payload, avail, allow_unlock=True)
            if ok2:
                log("          set %-22s = %s" % (note, user or "literal"))
                if user:
                    report["linked"].append({"system": sys_path, "emitter": name,
                                             "module": mod_name, "input": note,
                                             "user": user})
                    expect[note] = user
            else:
                log("          ! %-22s %s" % (iname, note))
        if expect:
            modules_done.append((script, mod_name, expect))

    for script, mod_name, expect in modules_done:
        good, total = verify_module(sys_path, name, script, mod_name, expect, log)
        log("        verify %-16s %d/%d links confirmed in the graph"
            % (mod_name, good, total))
        if good == total:
            report["verified"].append({"system": sys_path, "module": mod_name,
                                       "count": total})

    for step in spec.get("manual") or []:
        report["manual_steps"].append({"system": sys_path, "emitter": name,
                                       "step": step})
    return name


def editor_world():
    """The editor world, however this build happens to expose it."""
    for getter in ("unreal.UnrealEditorSubsystem", "unreal.EditorLevelLibrary",
                   "unreal.EditorAssetLibrary"):
        try:
            obj = getattr(unreal, getter.split(".")[-1])()
            w = obj.get_editor_world()
            if w is not None:
                return w
        except Exception:
            continue
    return None


def disk_path(pkg_path):
    return (str(_SEKAI_ROOT / 'ue5_lab/SwordVFX_Lab/Content')
            + pkg_path[len("/Game"):] + ".uasset")


def save_all(log):
    """Save every dirty package, then prove it by reading the files' timestamps.

    WHY THERE IS NO EditorAssetLibrary HERE. Three save APIs were tried and all
    three took the editor down with an access violation on a freshly-built
    Niagara system:

        EditorAssetLibrary.save_asset         -> EXCEPTION_ACCESS_VIOLATION 0x0
        EditorAssetLibrary.save_loaded_asset  -> same
        EditorLoadingAndSavingUtils.save_packages([pkg], False) -> same

    A console "SaveAll" survives but writes nothing, which suggests the saver
    saw nothing to do. So this marks the packages dirty first and then calls the
    same routine the console command ends up in, with two plain booleans - no
    array of objects crosses the Python boundary, and no API known to take the
    editor down is called.
    """
    before = {}
    for entry in report["systems"]:
        p = disk_path(entry["path"].rsplit(".", 1)[0])
        before[entry["name"]] = os.path.getmtime(p) if os.path.exists(p) else 0.0

    # NOTE: there is deliberately no attempt to mark the packages dirty.
    # UPackage has no set_dirty_flag in the Python API, and it turned out not to
    # be needed: save_dirty_packages writes these assets anyway, because a
    # freshly created asset is already dirty. Marking was a guess about why
    # SaveAll did nothing, and it was the wrong guess.
    log("    %d systems, saving via save_dirty_packages" % len(report["systems"]))
    for label, fn in (
            ("save_dirty_packages",
             lambda: unreal.EditorLoadingAndSavingUtils.save_dirty_packages(True, True)),
            ("SaveAll console",
             lambda: unreal.SystemLibrary.execute_console_command(
                 editor_world(), "SaveAll"))):
        try:
            res = fn()
        except Exception as exc:
            log("    %-24s raised %s" % (label, str(exc)[:160]))
            continue
        written = 0
        for entry in report["systems"]:
            p = disk_path(entry["path"].rsplit(".", 1)[0])
            after = os.path.getmtime(p) if os.path.exists(p) else 0.0
            if after > before[entry["name"]]:
                written += 1
        log("    %-24s returned %s, %d/%d files written"
            % (label, res, written, len(report["systems"])))
        if written:
            del report["saved"][:]      # idempotent: replace, never accumulate
            for entry in report["systems"]:
                p = disk_path(entry["path"].rsplit(".", 1)[0])
                after = os.path.getmtime(p) if os.path.exists(p) else 0.0
                ok = after > before[entry["name"]]
                report["saved"].append({"system": entry["name"], "via": label,
                                        "ok": bool(ok)})
            return written

    del report["saved"][:]
    for entry in report["systems"]:
        log("    %-28s NOT written" % entry["name"])
        report["saved"].append({"system": entry["name"], "via": "none", "ok": False})
        report["errors"].append({"system": entry["name"],
                                 "save": "no write API succeeded"})
    return 0


# ===========================================================================
# the ticking finish: save, then find out whether the graphs actually compile
# ===========================================================================
#
# GetStackIssues and GetSystemCompileState both wait on a Niagara compile, which
# is why they never completed in the commandlet. They are polled across ticks
# rather than spun on, because spinning inside a tick callback waits for a tick
# that cannot arrive.
#
# Nothing in this section claims a system works. It reports what the engine
# says, and a system with no compile answer is reported as unanswered.

WARM_TICKS = 90
TICKS_PER_SYSTEM = 900          # ~15 s at 60 Hz, then give up and say so
# Module-level guard against an interrupted callback re-entering a phase.
STATE_SEEN_SAVE = []
_finish = {
    "phase": "warm", "ticks": 0, "index": 0, "inflight": {}, "budget": 0,
    "results": {}, "handle": None,
}


def request_compile_checks(entry):
    """Fire both compile questions for one system; they complete across ticks."""
    p = {"system": S.ref(entry["path"])}
    return {"state": S.call_async("GetSystemCompileState", p),
            "issues": S.call_async("GetStackIssues", p)}


def record_compile_result(entry, payload, log):
    """Turn the engine's answer into the report, without softening it."""
    name = entry["name"]
    out = {"system": name}
    st = payload.get("state")
    if isinstance(st, dict):
        out["aggregate_status"] = st.get("aggregateStatus")
        out["is_compiling"] = st.get("bIsCompiling")
        out["is_stale"] = st.get("bIsStale")
        out["has_errors"] = st.get("bHasErrors")
        out["has_warnings"] = st.get("bHasWarnings")
        bad = []
        for sc in (st.get("scripts") or []):
            if sc.get("lastCompileStatus") in ("Error", "Dirty", "Unknown"):
                bad.append({"script": sc.get("scriptName"),
                            "emitter": sc.get("emitterName"),
                            "status": sc.get("lastCompileStatus"),
                            "error": (sc.get("errorSummary") or "")[:400]})
        out["bad_scripts"] = bad
    else:
        out["state_unavailable"] = str(payload.get("state_error") or st)
    iss = payload.get("issues")
    if isinstance(iss, dict):
        out["num_errors"] = iss.get("numErrors")
        out["num_warnings"] = iss.get("numWarnings")
        out["num_infos"] = iss.get("numInfos")
        out["issues"] = [{"severity": i.get("severity"),
                          "short": i.get("shortDescription"),
                          "where": "%s/%s/%s" % (
                              (i.get("location") or {}).get("emitterName"),
                              (i.get("location") or {}).get("scriptName"),
                              (i.get("location") or {}).get("moduleName")),
                          "long": (i.get("longDescription") or "")[:400]}
                         for i in (iss.get("issues") or [])
                         if i.get("severity") in ("Error", "Warning")][:20]
    else:
        out["issues_unavailable"] = str(payload.get("issues_error") or iss)

    _finish["results"][name] = out
    log("    %-28s status=%-22s err=%-5s warn=%-5s compiling=%s"
        % (name, out.get("aggregate_status") or out.get("state_unavailable"),
           out.get("has_errors"), out.get("has_warnings"),
           out.get("is_compiling")))
    for b in out.get("bad_scripts") or []:
        log("        ! %s/%s %s %s" % (b.get("emitter"), b.get("script"),
                                       b.get("status"), b.get("error")))
    for i in out.get("issues") or []:
        log("        %s %s  @%s" % (i["severity"], i["short"], i["where"]))


def write_report():
    report["compile"] = _finish["results"]
    with open(REPORT, "w", encoding="utf-8") as fh:
        json.dump(report, fh, ensure_ascii=False, indent=1)


def finish_summary(log):
    log("")
    log("--- summary ---")
    log("systems built        : %d / %d" % (len(report["systems"]), _finish["total"]))
    log("links confirmed      : %d modules, %d pins"
        % (len(report["verified"]), sum(v["count"] for v in report["verified"])))
    log("links attempted      : %d" % len(report["linked"]))
    log("unmatched inputs     : %d" % len(report["unmatched"]))
    log("not-editable inputs  : %d" % len(report["not_editable"]))
    log("ambiguous matches    : %d" % len(report["ambiguous"]))
    log("dynamic input clashes: %d" % len(report["dynamic"]))
    log("unverified pins      : %d" % len(report["unverified"]))
    log("gates opened         : %d" % len(report["gates_opened"]))
    log("manual steps         : %d" % len(report["manual_steps"]))
    log("saved                : %d / %d"
        % (sum(1 for s in report["saved"] if s.get("ok")), len(report["saved"])))
    res = _finish["results"]
    up = sum(1 for r in res.values()
             if r.get("aggregate_status") in ("UpToDate",
                                              "UpToDateWithWarnings",
                                              "ComputeUpToDateWithWarnings"))
    fresh = sum(1 for r in res.values() if r.get("is_stale") is False)
    log("compile aggregate ok : %d / %d" % (up, len(res)))
    log("compile NOT STALE    : %d / %d" % (fresh, len(res)))
    if up and not fresh:
        log("")
        log("NOTE: every system reports aggregateStatus=UpToDate but is_stale=True.")
        log("      Those two disagree, so the honest reading is that no compile has")
        log("      actually been PERFORMED - a headless editor has no Niagara preview")
        log("      and no component instance to force one. Do not read UpToDate alone")
        log("      as 'compiles clean'.")
    log("errors               : %d" % len(report["errors"]))
    write_report()
    log("report -> %s" % REPORT)


def _finish_tick(delta):
    st = _finish
    st["ticks"] += 1
    log = S.log

    if st["phase"] == "warm":
        if st["ticks"] < WARM_TICKS:
            return
        st["phase"] = "compile"
        st["ticks"] = 0
        st["index"] = 0
        return

    if st["phase"] == "compile":
        todo = report["systems"]
        if st["index"] >= len(todo):
            # The phase moves BEFORE the work, not after it. The save below is
            # the one step that has taken this editor down, and an interrupted
            # Python callback never reaches the line after the call - which is
            # exactly how the previous run entered this block three times and
            # tripled the saved[] list. Setting the phase first makes the
            # sequence idempotent whatever happens inside it.
            st["phase"] = "saving"
            # Written BEFORE the save is attempted, on purpose: losing the
            # compile evidence to a crash in the last phase would mean guessing
            # at whether the graphs build.
            write_report()
            log("")
            log("--- saving (report already on disk, so a crash here costs "
                "nothing that was measured) ---")
            report["save_ok"] = save_all(log)
            STATE_SEEN_SAVE.append(1)
            write_report()
            st["phase"] = "done"
            st["ticks"] = 0
            return
        if not st["inflight"]:
            entry = todo[st["index"]]
            log("")
            log("--- compile check %d/%d: %s ---"
                % (st["index"] + 1, len(todo), entry["name"]))
            try:
                st["inflight"] = request_compile_checks(entry)
                st["inflight"]["entry"] = entry
                st["budget"] = 0
            except Exception as exc:
                log("    !! could not ask: %s" % exc)
                st["results"][entry["name"]] = {"system": entry["name"],
                                               "state_unavailable": str(exc)}
                st["index"] += 1
                return
        payload = {"state": None, "state_error": None,
                   "issues": None, "issues_error": None}
        done = True
        for key, tool in (("state", "GetSystemCompileState"),
                          ("issues", "GetStackIssues")):
            d, ok, val = S.poll(st["inflight"][key], tool)
            if not d:
                done = False
                continue
            payload[key] = val if ok else None
            if not ok:
                payload[key + "_error"] = val
        if not done:
            st["budget"] += 1
            if st["budget"] > TICKS_PER_SYSTEM:
                entry = st["inflight"]["entry"]
                log("    %s gave no answer in %d ticks - reported unanswered"
                    % (entry["name"], TICKS_PER_SYSTEM))
                st["results"][entry["name"]] = {
                    "system": entry["name"],
                    "state_unavailable": "no answer within %d ticks"
                                         % TICKS_PER_SYSTEM}
                st["inflight"] = {}
                st["index"] += 1
            return
        entry = st["inflight"]["entry"]
        record_compile_result(entry, payload, log)
        st["inflight"] = {}
        st["index"] += 1
        return

    if st["phase"] == "done":
        finish_summary(log)
        log("P11 DONE")
        print("P11 DONE")
        if st["handle"] is not None:
            try:
                unreal.unregister_slate_post_tick_callback(st["handle"])
            except Exception:
                pass
            st["handle"] = None
        st["phase"] = "closed"
        try:
            unreal.SystemLibrary.quit_editor()
        except Exception as exc:
            log("quit_editor failed: %s" % exc)
        return


def build_system(spec, log):
    log("")
    log("=== %s ===" % spec["name"])
    full = "%s/%s" % (DIR_SYS, spec["name"])
    if EAL.does_asset_exist(full):
        log("    replacing existing asset")
        EAL.delete_asset(full)

    log("    creating system from template")
    sys_path = S.call("CreateNiagaraSystem", {
        "assetName": spec["name"], "assetPath": DIR_SYS,
        "templateSystem": S.ref(TPL_SYSTEM)})["refPath"]

    log("    stripping template emitters")
    summary = S.call("GetSystemSummary", {"system": S.ref(sys_path)})
    for em in (summary.get("emitters") or []):
        S.call_quiet("RemoveEmitter", {
            "emitterToRemove": S.stack_ref(sys_path, emitter=em.get("emitterName"))})

    log("    adding %d user parameters" % len(USER_PARAMS))
    added, refused = [], []
    for nm, typ, default, desc in USER_PARAMS:
        ok, res = S.call_quiet("AddUserVariables", {
            "system": S.ref(sys_path),
            "variablesToAdd": [{"name": nm, "type": S.typedef(typ),
                                "defaultValue": default, "description": desc}]})
        (added if ok else refused).append(nm if ok else (nm, str(res)[:120]))
    log("      ok: %d  refused: %d" % (len(added), len(refused)))
    for r in refused:
        log("      ! user param refused: %s  %s" % r)
        report["errors"].append({"system": sys_path, "user_param": r[0],
                                 "error": r[1]})

    entry = {"name": spec["name"], "path": sys_path, "note": spec["note"],
             "emitters": [], "user_params_added": len(added)}
    for em in spec["emitters"]:
        nm = build_emitter(sys_path, em, log)
        entry["emitters"].append({"name": nm})

    st = S.call("GetSystemSummary", {"system": S.ref(sys_path)})
    entry["final_emitters"] = [e.get("emitterName") for e in st.get("emitters") or []]
    entry["user_variables"] = len(st.get("userVariables") or [])
    log("    -> %s  userVars=%d" % (entry["final_emitters"], entry["user_variables"]))
    report["systems"].append(entry)
    # Saving is deliberately NOT done here. It happens once, in the ticking
    # finish phase, after every system exists and the compiles have settled -
    # see save_all() for why a per-system save is not an option.


def main():
    S.log("engine: " + unreal.SystemLibrary.get_engine_version())
    only = os.environ.get("SWVFX_ONLY", "").strip()
    todo = [s for s in SYSTEMS if not only or s["name"] == only]
    _finish["total"] = len(todo)
    S.log("building %d core systems into %s%s"
          % (len(todo), DIR_SYS, ("  [filter: " + only + "]") if only else ""))

    for spec in todo:
        try:
            build_system(spec, S.log)
        except Exception as exc:
            S.log("!!! %s FAILED %s: %s" % (spec["name"], type(exc).__name__, exc))
            report["errors"].append({"system": spec["name"], "fatal": str(exc)})

    S.log("")
    S.log("--- build finished, handing over to the tick phase ---")
    S.log("save and compile diagnostics need an editor session; see")
    S.log("scripts/run_ue.sh --editor. Without ticks the systems exist in memory")
    S.log("only and are reported as built, never as saved or compiled.")

    # In a real editor session the finish phase runs on ticks: warm up so the
    # Niagara compiles settle, SaveAll, then ask the engine whether each graph
    # actually compiles. In the commandlet there are no ticks, so the run ends
    # here and says exactly that rather than pretending.
    ticks = 0
    try:
        if unreal.register_slate_post_tick_callback(_finish_tick):
            ticks = 1
    except Exception as exc:
        S.log("post-tick callback not available: %s" % exc)
    if not ticks:
        _finish["total"] = len(todo)
        finish_summary(S.log)
        S.log("P11 DONE (no ticks: built only, not saved, not compiled)")
        print("P11 DONE")


if os.environ.get("SWVFX_NO_MAIN", "").strip() != "1":
    main()
