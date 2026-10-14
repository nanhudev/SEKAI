"""SEKAI Sword VFX - decisive Niagara authoring probe.

Question this run must answer:
  Can UE 5.8 build a Niagara system (system + emitter + renderer + modules +
  user parameters) from Python, and can it report back whether the graph compiled?

Writes F:/SEKAI/ue5_lab/sword_vfx/exports/p01_toolset_probe.txt
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import traceback

import unreal

OUT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p01_toolset_probe.txt')

_BUF = []


def log(s=""):
    s = str(s)
    _BUF.append(s)
    try:
        with open(OUT, "a", encoding="utf-8") as f:
            f.write(s + "\n")
    except Exception:
        pass


def head(s):
    log("")
    log("=" * 72)
    log("## " + s)
    log("=" * 72)


def step(label, fn):
    """Run fn(), log OK/FAIL, return value or None."""
    try:
        v = fn()
        log("  OK    %-46s -> %r" % (label, v))
        return v
    except Exception as exc:
        log("  FAIL  %-46s !! %s: %s" % (label, type(exc).__name__, exc))
        return None


try:
    open(OUT, "w", encoding="utf-8").close()
except Exception:
    pass

log("=== engine ===")
log(unreal.SystemLibrary.get_engine_version())

# ---------------------------------------------------------------- 1. toolset
head("1. Niagara Toolset availability")

TS = getattr(unreal, "NiagaraToolset_System", None)
log("unreal.NiagaraToolset_System -> %r" % (TS,))
if TS is not None:
    for n in sorted(a for a in dir(TS) if not a.startswith("_")):
        log("    .%s" % n)

for extra in ("NiagaraToolset_Info", "NiagaraToolset_Assets", "NiagaraToolset_Component",
              "NiagaraToolset_Blueprint"):
    log("unreal.%s -> %r" % (extra, getattr(unreal, extra, None)))

# ------------------------------------------------------- 2. struct field names
head("2. struct field discovery (to_dict on a default instance)")


def fields(struct_name):
    cls = getattr(unreal, struct_name, None)
    if cls is None:
        log("  %-42s MISSING" % struct_name)
        return None
    for maker in ("instance",):
        pass
    try:
        inst = cls()
    except Exception as exc:
        log("  %-42s cannot instantiate: %s" % (struct_name, exc))
        return None
    try:
        d = inst.to_dict()
        log("  %-42s %s" % (struct_name, sorted(d.keys()) if isinstance(d, dict) else repr(d)))
        return d
    except Exception as exc:
        log("  %-42s to_dict FAILED %s" % (struct_name, exc))
    return None


for s in ("NiagaraExt_StackItemReference", "NiagaraExt_EmitterTopology",
          "NiagaraExt_ModuleTopology", "NiagaraExt_UserVariable",
          "NiagaraExt_Variable", "NiagaraExt_SetParameterEntry",
          "NiagaraExt_RendererRef", "NiagaraExt_SystemSummary",
          "NiagaraExt_EmitterSummary", "NiagaraExt_StackInputValue",
          "NiagaraExt_SystemData", "NiagaraExt_EmitterData"):
    fields(s)

head("2b. NiagaraTypeDefinition construction")


def probe_typedef():
    cls = getattr(unreal, "NiagaraTypeDefinition", None)
    log("  class -> %r" % (cls,))
    if cls is None:
        return
    log("  dir -> %s" % sorted(a for a in dir(cls) if not a.startswith("_")))
    for candidate_name in ("NiagaraFloat", "NiagaraInt32", "NiagaraBool",
                           "NiagaraPosition", "LinearColor"):
        t = getattr(unreal, candidate_name, None)
        log("  unreal.%-20s -> %r" % (candidate_name, t))
    # try common constructions
    for expr in ("cls(unreal.NiagaraFloat)",
                 "cls(unreal.NiagaraFloat.static_struct())",
                 "cls.get_editor_property" ):
        try:
            v = eval(expr)
            log("  construct %-46s -> %r" % (expr, v))
        except Exception as exc:
            log("  construct %-46s !! %s: %s" % (expr, type(exc).__name__, exc))


step("NiagaraTypeDefinition probe", probe_typedef)

# ------------------------------------------------------------ 3. asset search
head("3. Niagara engine content visibility")

ar = unreal.AssetRegistryHelpers.get_asset_registry()


def search(root, recursive=True, limit=400):
    out = []
    try:
        assets = ar.get_assets_by_path(root, recursive=recursive)
        for a in assets:
            out.append(a)
            if len(out) >= limit:
                break
    except Exception as exc:
        log("  get_assets_by_path(%s) FAILED %s" % (root, exc))
    return out


for root in ("/Niagara", "/NiagaraToolsets", "/Niagara/Modules", "/Niagara/DefaultAssets"):
    got = search(root)
    log("  %-30s n=%d" % (root, len(got)))

systems, emitters, modules, dyninputs = [], [], [], []
for a in search("/Niagara", limit=20000):
    cn = str(a.asset_class_path.asset_name) if hasattr(a, "asset_class_path") else str(a.asset_class)
    p = str(a.package_name)
    if cn == "NiagaraSystem":
        systems.append(p)
    elif cn == "NiagaraEmitter":
        emitters.append(p)
    elif cn == "NiagaraScript":
        modules.append(p)
    elif cn == "NiagaraScriptSource":
        dyninputs.append(p)

log("")
log("  NiagaraSystem : %d" % len(systems))
for p in systems[:30]:
    log("      %s" % p)
log("  NiagaraEmitter: %d" % len(emitters))
for p in emitters[:30]:
    log("      %s" % p)
log("  NiagaraScript : %d" % len(modules))
for p in modules[:60]:
    log("      %s" % p)

# ------------------------------------------------- 4. recipes / templates path
head("4. plugin template folders on disk (via asset registry, other roots)")
for root in ("/Niagara", "/Niagara/DefaultAssets", "/Niagara/Modules"):
    try:
        folders = unreal.EditorAssetLibrary.list_assets(root, recursive=True,
                                                        include_folder=True)
        log("  %-26s list_assets n=%s" % (root, "None" if folders is None else len(folders)))
    except Exception as exc:
        log("  %-26s FAILED %s" % (root, exc))

# --------------------------------------------------------- 5. live build test
head("5. LIVE BUILD TEST")

TARGET_DIR = "/Game/SEKAI/VFX/Sword/Probe"
SYS_NAME = "NS_PROBE_Toolset_01"

probe_system = None

if TS is None:
    log("  NiagaraToolset_System not exposed - cannot run live build test.")
else:
    log("  system schema:")
    sch = step("GetSystemSchema()", lambda: TS.get_system_schema())
    if sch is not None:
        try:
            log("      %r" % sch.to_dict())
        except Exception as exc:
            log("      to_dict failed %s" % exc)

    log("  emitter schema:")
    esch = step("GetEmitterSchema()", lambda: TS.get_emitter_schema())
    if esch is not None:
        try:
            log("      %r" % esch.to_dict())
        except Exception as exc:
            log("      to_dict failed %s" % exc)

    log("  renderer schema (sprite):")
    rsch = step("GetRendererSchema(sprite)",
                lambda: TS.get_renderer_schema(unreal.NiagaraSpriteRendererProperties))
    if rsch is not None:
        try:
            log("      %r" % rsch.to_dict())
        except Exception as exc:
            log("      to_dict failed %s" % exc)

    # --- create system from a template
    if systems:
        tpl = systems[0]
        log("")
        log("  using template system: %s" % tpl)
        tpl_obj = step("load template system", lambda: unreal.EditorAssetLibrary.load_asset(tpl))
        probe_system = step(
            "CreateNiagaraSystem()",
            lambda: TS.create_niagara_system(SYS_NAME, TARGET_DIR, tpl_obj))
    else:
        log("")
        log("  NO template NiagaraSystem found - CreateNiagaraSystem needs one.")

    # --- add emitter
    if probe_system is not None and emitters:
        tpl_e = emitters[0]
        log("  using template emitter: %s" % tpl_e)
        tpl_e_obj = step("load template emitter", lambda: unreal.EditorAssetLibrary.load_asset(tpl_e))
        topo = step("AddEmitter()",
                    lambda: TS.add_emitter(probe_system, tpl_e_obj, "E_Probe"))
        if topo is not None:
            try:
                d = topo.to_dict()
                log("      emitter topology keys: %s" % sorted(d.keys()))
                log("      %r" % d)
            except Exception as exc:
                log("      to_dict failed %s" % exc)

        # --- add renderer
        eref = step("build emitter ref",
                    lambda: None)
        try:
            ref = unreal.NiagaraExt_StackItemReference()
            log("      ref fields: %s" % (sorted(ref.to_dict().keys()) if hasattr(ref, "to_dict") else "?"))
            ref.set_editor_property("system", probe_system)
            ref.set_editor_property("emitter_name", "E_Probe")
            log("      emitter ref = %r" % ref)
            step("AddRenderer(ribbon)",
                 lambda: TS.add_renderer(ref, unreal.NiagaraRibbonRendererProperties))
            step("AddRenderer(sprite)",
                 lambda: TS.add_renderer(ref, unreal.NiagaraSpriteRendererProperties))
        except Exception as exc:
            log("      emitter ref FAILED %s: %s" % (type(exc).__name__, exc))

        # --- user variables
        try:
            log("")
            log("  user variables:")
            for vname, tdef in (("User_PROBE_Float", "NiagaraFloat"),
                                ("User_PROBE_Color", "LinearColor")):
                uv = unreal.NiagaraExt_UserVariable()
                log("      uv fields: %s" % sorted(uv.to_dict().keys()))
                break
        except Exception as exc:
            log("      user var probe FAILED %s: %s" % (type(exc).__name__, exc))

        # --- module add
        try:
            log("")
            log("  module add attempt:")
            ref2 = unreal.NiagaraExt_StackItemReference()
            ref2.set_editor_property("system", probe_system)
            ref2.set_editor_property("emitter_name", "E_Probe")
            ref2.set_editor_property("script_name", "ParticleSpawnScript")
            found_module = None
            for p in modules:
                if any(k in p for k in ("InitializeParticle", "Initialize_Particle",
                                        "SpawnRate", "AddVelocity")):
                    found_module = p
                    break
            log("      candidate module: %r" % found_module)
            if found_module:
                mobj = unreal.EditorAssetLibrary.load_asset(found_module)
                mt = step("AddModule()", lambda: TS.add_module(ref2, mobj))
                if mt is not None:
                    try:
                        log("      module topology: %r" % mt.to_dict())
                    except Exception as exc:
                        log("      to_dict failed %s" % exc)
        except Exception as exc:
            log("      module add FAILED %s: %s" % (type(exc).__name__, exc))

        # --- summary + issues + compile state
        log("")
        s = step("GetSystemSummary()", lambda: TS.get_system_summary(probe_system))
        if s is not None:
            try:
                log("      %r" % s.to_dict())
            except Exception as exc:
                log("      to_dict failed %s" % exc)

        iss = step("GetStackIssues()", lambda: TS.get_stack_issues(probe_system))
        if iss is not None:
            log("      type=%s dir=%s" % (type(iss), sorted(a for a in dir(iss) if not a.startswith("_"))[:40]))
            try:
                log("      Value=%r" % (iss.get_editor_property("value"),))
            except Exception as exc:
                log("      Value read failed %s" % exc)

        cs = step("GetSystemCompileState()", lambda: TS.get_system_compile_state(probe_system))
        if cs is not None:
            try:
                log("      Value=%r" % (cs.get_editor_property("value"),))
            except Exception as exc:
                log("      Value read failed %s" % exc)

    # --- save
    if probe_system is not None:
        step("save_loaded_asset()",
             lambda: unreal.EditorAssetLibrary.save_loaded_asset(
                 probe_system, only_if_is_dirty=False))
        step("does_asset_exist()",
             lambda: unreal.EditorAssetLibrary.does_asset_exist(
                 TARGET_DIR + "/" + SYS_NAME))

head("DONE")
log("")
print("P01 PROBE WROTE " + OUT)
