"""SEKAI Sword VFX - toolset registry probe 2.

Goal: prove we can drive the Niagara Toolset from Python inside this project, and
capture the FULL tool contract (names + input JSON schema) for the build sheets.

Writes:
  F:/SEKAI/ue5_lab/sword_vfx/exports/p02_registry.txt
  F:/SEKAI/ue5_lab/sword_vfx/exports/p02_toolset_schemas.json
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json

import unreal

OUT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p02_registry.txt')
SCHEMAS = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p02_toolset_schemas.json')

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
    log("=" * 74)
    log("## " + s)
    log("=" * 74)


open(OUT, "w", encoding="utf-8").close()

log("engine: " + unreal.SystemLibrary.get_engine_version())

# ------------------------------------------------------------------ registry
head("1. UToolsetRegistry surface")
REG = getattr(unreal, "ToolsetRegistry", None)
log("unreal.ToolsetRegistry -> %r" % (REG,))
if REG is not None:
    for n in sorted(a for a in dir(REG) if not a.startswith("_")):
        log("    .%s" % n)

head("2. availability")
try:
    log("  is_available() = %r" % REG.is_available())
except Exception as exc:
    log("  is_available FAILED %s: %s" % (type(exc).__name__, exc))

for name in ("NiagaraToolset_System", "NiagaraToolset_Info",
             "NiagaraToolset_Assets", "NiagaraToolset_Component"):
    try:
        log("  is_toolset_registered(%-26s) = %r" % (name, REG.is_toolset_registered(name)))
    except Exception as exc:
        log("  is_toolset_registered(%s) FAILED %s" % (name, exc))

# ------------------------------------------------------------------- schemas
head("3. full tool contract")
all_schemas = None
try:
    all_schemas = REG.get_all_toolset_json_schemas()
    log("  get_all_toolset_json_schemas() -> %d chars" % len(all_schemas))
    with open(SCHEMAS, "w", encoding="utf-8") as f:
        f.write(all_schemas)
    log("  written -> %s" % SCHEMAS)
    try:
        parsed = json.loads(all_schemas)
        log("  top-level type: %s" % type(parsed).__name__)
        if isinstance(parsed, dict):
            for k in sorted(parsed.keys()):
                log("     toolset: %s" % k)
        elif isinstance(parsed, list):
            for item in parsed[:12]:
                if isinstance(item, dict):
                    log("     entry keys: %s" % sorted(item.keys()))
    except Exception as exc:
        log("  json parse failed: %s" % exc)
except Exception as exc:
    log("  get_all_toolset_json_schemas FAILED %s: %s" % (type(exc).__name__, exc))

# ------------------------------------------------------- sync-vs-async probe
head("4. synchronous completion probe")


def call(toolset, tool, payload, spin=400000):
    """Execute a tool and report whether the async result completes without ticking."""
    try:
        res = REG.execute_tool(toolset, tool, json.dumps(payload))
    except Exception as exc:
        log("  %s.%s -> execute_tool raised %s: %s" % (toolset, tool, type(exc).__name__, exc))
        return None
    if res is None:
        log("  %s.%s -> returned None" % (toolset, tool))
        return None
    log("  %s.%s -> result %r" % (toolset, tool, type(res)))
    try:
        log("      dir: %s" % sorted(a for a in dir(res) if not a.startswith("_"))[:40])
    except Exception:
        pass
    n = 0
    complete = False
    while n < spin:
        try:
            complete = bool(res.get_editor_property("is_complete"))
        except Exception:
            try:
                complete = bool(res.is_complete)
            except Exception as exc:
                log("      cannot read is_complete: %s" % exc)
                return res
        if complete:
            break
        n += 1
    log("      complete=%s after %d spins" % (complete, n))
    for prop in ("error", "value"):
        try:
            v = res.get_editor_property(prop)
        except Exception:
            try:
                v = getattr(res, prop)
            except Exception as exc:
                v = "<%s>" % exc
        log("      %s = %.600s" % (prop, v))
    return res


call("NiagaraToolset_System", "GetSystemSchema", {})
call("NiagaraToolset_System", "GetEmitterSchema", {})

head("DONE")
print("P02 WROTE")
