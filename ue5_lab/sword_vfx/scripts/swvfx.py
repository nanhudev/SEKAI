"""SEKAI UE5 Sword VFX - shared Niagara toolset driver.

Wraps unreal.ToolsetRegistry so the production scripts can talk to the Niagara
Toolset by plain function call. Every tool call is logged so a failed build
leaves a readable trace instead of a silent no-op.

Toolset used:  NiagaraToolsets.NiagaraToolset_System  (46 tools, UE 5.8)
"""
import json
import time as _time

import unreal

TOOLSET = "NiagaraToolsets.NiagaraToolset_System"

# The registry is keyed by TOOLSET, so a tool that lives in a different toolset
# is not "unknown work", it is "asked of the wrong desk". MEASURED: p43 called
# ConstructNiagaraBPWrapperFromSystem through the _System toolset and got
#     ConstructNiagaraBPWrapperFromSystem: Unknown tool ...
# which reads as a missing feature. It exists - in NiagaraToolset_Blueprint.
BLUEPRINT_TOOLSET = "NiagaraToolsets.NiagaraToolset_Blueprint"
COMPONENT_TOOLSET = "NiagaraToolsets.NiagaraToolset_Component"

_LOG_PATH = None
_LOG_LINES = []


def bind_log(path, truncate=True):
    """Point the driver's log at a file for this run.

    `truncate=False` appends instead of starting a fresh file, so a script that
    keeps its own log (P20 does) can share one output file with this module -
    otherwise the watchdog's last words would go somewhere the reader is not
    looking, which is the whole failure mode it exists to prevent.
    """
    global _LOG_PATH, _LOG_LINES
    _LOG_PATH = path
    _LOG_LINES = []
    if truncate:
        try:
            open(path, "w", encoding="utf-8").close()
        except Exception:
            pass


def log(msg=""):
    msg = str(msg)
    _LOG_LINES.append(msg)
    print(msg)
    if _LOG_PATH:
        try:
            with open(_LOG_PATH, "a", encoding="utf-8") as fh:
                fh.write(msg + "\n")
        except Exception:
            pass


# --------------------------------------------------------------------------
# watchdog
#
# MEASURED BEHAVIOUR, and the reason this exists: with
#     UnrealEditor-Cmd.exe <project> -ExecCmds="py script.py"
# an uncaught python exception is written to Saved/Logs/<project>.log and then
# SWALLOWED. The editor keeps running. The script's own export log simply stops
# mid-sentence, so the failure is indistinguishable from a deadlock inside a
# native call - and the process has to be killed by hand.
#
# That is not a theory. P20's material section passed the string "BASE_COLOR"
# where `connect_material_property` wants the EMaterialProperty enum. Two engine
# launches were spent on a wrong root cause (first "save_asset hangs", then
# "material graph authoring hangs in a nullrhi editor") because the editor just
# sat there, alive, with the reference to the real traceback sitting unread in
# Saved/Logs.
#
# The fix is not "be more careful". It is: never let an editor session outlive
# the script that owns it. The script body runs synchronously before the first
# tick, so by the time the grace window elapses the body has either finished and
# handed over to its own state machine, or it raised. The watchdog only fires in
# the second case.
# --------------------------------------------------------------------------

_WATCH = {"handle": None, "ticks": 0, "handover": False, "grace": 0,
          "fired": False, "started": 0.0, "grace_seconds": 0.0}


def _watch_tick(delta):
    if _WATCH["fired"]:
        return
    _WATCH["ticks"] += 1
    if _WATCH["handover"]:
        # The script's own finish path is live and owns the exit. Stop watching
        # rather than quitting underneath it.
        _WATCH["fired"] = True
        return
    if _WATCH["ticks"] < _WATCH["grace"]:
        return
    # MEASURED, and it cost a run: the grace is in TICKS but everything a script
    # actually bounds - a poll deadline, a wait for a compile - is in SECONDS,
    # and the tick rate here is not a constant. It was ~71 ticks/s in a
    # --editor session with no level loaded and ~3 ticks/s in --render, so
    #     install_watchdog(4000) ... poll deadline 200 s
    # meant the watchdog fired 56 s in and killed a healthy wait. Nothing in the
    # log said "you set the wrong unit"; it said the script body never reached
    # its finish path, which reads as a hang in the script.
    #
    # grace_seconds is the fix: pass both, and whichever runs out first wins.
    if _WATCH["grace_seconds"] > 0.0 and _WATCH["started"] > 0.0:
        waited = _time.time() - _WATCH["started"]
        if waited < _WATCH["grace_seconds"]:
            return
    _WATCH["fired"] = True
    log("")
    log("WATCHDOG: the script body never reached its finish path (%d ticks,"
        % _WATCH["ticks"])
    log("WATCHDOG: %.1f s)."
        % ((_time.time() - _WATCH["started"]) if _WATCH["started"] else -1.0))
    log("WATCHDOG: an uncaught python error in -ExecCmds mode is logged to")
    log("WATCHDOG: Saved/Logs/<project>.log and then swallowed, so the editor")
    log("WATCHDOG: would otherwise stay open forever and this script's own log")
    log("WATCHDOG: cannot show you why. Read the engine log for the traceback.")
    log("WATCHDOG: quitting so the process cannot linger.")
    try:
        if _WATCH["handle"] is not None:
            unreal.unregister_slate_post_tick_callback(_WATCH["handle"])
    except Exception:
        pass
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception:
        pass


def install_watchdog(grace_ticks=300, grace_seconds=0.0):
    """Arm the watchdog. Call this BEFORE any risky work in an editor session.

    Installing it early is the whole point: a watchdog armed after the risky
    calls would not cover the failures that matter.

    grace_seconds exists because grace_ticks is a different unit from every
    deadline a script actually cares about, and the tick rate is not a constant
    (measured ~71 ticks/s in --editor with no level loaded, ~3 ticks/s in
    --render). Pass a grace in seconds when the bound you are protecting is in
    seconds; whichever runs out first fires. See the note in _watch_tick for the
    run this cost.
    """
    _WATCH["grace"] = int(grace_ticks)
    _WATCH["grace_seconds"] = float(grace_seconds)
    _WATCH["started"] = _time.time()
    _WATCH["ticks"] = 0
    _WATCH["fired"] = False
    _WATCH["handover"] = False
    try:
        _WATCH["handle"] = unreal.register_slate_post_tick_callback(_watch_tick)
        log("watchdog armed (%d ticks%s)"
            % (grace_ticks,
               ", %.0f s" % grace_seconds if grace_seconds > 0.0 else ""))
    except Exception as exc:
        # A commandlet has no ticks, so this is expected there and harmless.
        log("watchdog unavailable in this session: %s" % str(exc)[:120])


def watchdog_handover():
    """Hand the exit over to the script's own finish path."""
    _WATCH["handover"] = True


def watchdog_fired():
    """True once the watchdog has given up on the script."""
    return bool(_WATCH["fired"])


# --------------------------------------------------------------------------
# JSON value builders - the shapes come from the toolset's own JSON schema
# --------------------------------------------------------------------------

def ref(path):
    """UObject / class / struct reference.

    Accepts either a full object path ("/Game/A/B.B") or a package path
    ("/Game/A/B"), and completes the latter to the object path the toolset's
    property resolver requires.
    """
    p = str(path)
    if not p.startswith("/Script/") and "." not in p.rsplit("/", 1)[-1]:
        p = "%s.%s" % (p, p.rsplit("/", 1)[-1])
    return {"refPath": p}


def typedef(struct_path):
    """ToolsetNiagaraTypeDefinition wrapper."""
    return {"classStructOrEnum": ref(struct_path)}


T_FLOAT = "/Script/Niagara.NiagaraFloat"
T_BOOL = "/Script/Niagara.NiagaraBool"
T_INT = "/Script/Niagara.NiagaraInt32"
T_POS = "/Script/Niagara.NiagaraPosition"
T_VEC = "/Script/CoreUObject.Vector"
T_VEC3 = "/Script/CoreUObject.Vector3f"
T_VEC4 = "/Script/CoreUObject.Vector4"
T_COLOR = "/Script/CoreUObject.LinearColor"
T_ROTATOR = "/Script/CoreUObject.Rotator"


def f(value):
    return {"struct": ref(T_FLOAT), "value": {"value": float(value)}}


def b(value):
    return {"struct": ref(T_BOOL), "value": {"value": bool(value)}}


def i(value):
    return {"struct": ref(T_INT), "value": {"value": int(value)}}


def pos(x, y, z):
    return {"struct": ref(T_POS), "value": {"x": float(x), "y": float(y), "z": float(z)}}


def vec4(x, y, z, w):
    return {"struct": ref(T_VEC4), "value": {"x": float(x), "y": float(y),
                                             "z": float(z), "w": float(w)}}


def vec3(x, y, z):
    """Vector3f - the type ScaleMeshSize / SolveForcesAndVelocity actually take.

    These module inputs are Vector3f, not NiagaraFloat: linking a float User
    parameter into them is accepted by the toolset (it only stores the declared
    type on the override pin) but is a lie the compiler then has to repair.
    """
    return {"struct": ref(T_VEC3), "value": {"x": float(x), "y": float(y),
                                             "z": float(z)}}


def color(r, g, b_, a=1.0):
    return {"struct": ref(T_COLOR),
            "value": {"r": float(r), "g": float(g), "b": float(b_), "a": float(a)}}


def rotator(pitch=0.0, yaw=0.0, roll=0.0):
    return {"struct": ref(T_ROTATOR),
            "value": {"pitch": float(pitch), "yaw": float(yaw), "roll": float(roll)}}


def enum_value(enum_path, enum_name):
    return {"struct": ref(enum_path),
            "value": {"enum": ref(enum_path), "enumName": enum_name,
                      "displayName": enum_name}}


T_LINKED = "/Script/NiagaraEditor.NiagaraExt_StackInputData_Linked"


def link(parameter_name, type_path=T_FLOAT):
    """Bind a module input to a linked parameter.

    This is how a core system is driven from the outside: every appearance and
    timing input on the core systems is linked to a User.* parameter so Normal
    and Magic are the same graph with a different profile, per the brief.
    """
    return {"struct": ref(T_LINKED),
            "value": {"linkedVariable": {"name": parameter_name,
                                         "type": typedef(type_path)}}}


def object_value(class_path, object_path):
    return {"struct": ref("/Script/NiagaraEditor.NiagaraExt_VariableValue_Object"),
            "value": {"objectClass": ref(class_path), "object": ref(object_path)}}


# --------------------------------------------------------------------------
# stack references
# --------------------------------------------------------------------------

SCRIPT_STACKS = (
    "SystemSpawnScript",
    "SystemUpdateScript",
    "EmitterSpawnScript",
    "EmitterUpdateScript",
    "ParticleSpawnScript",
    "ParticleUpdateScript",
)


def stack_ref(system_path, emitter=None, script=None, module=None,
              renderer_index=-1, input_stack=None):
    out = {
        "system": ref(system_path),
        "emitterName": emitter or "",
        "scriptName": script or "",
        "moduleName": module or "",
        "rendererIndex": renderer_index,
        "inputNameStack": list(input_stack or []),
    }
    return out


# --------------------------------------------------------------------------
# the call
# --------------------------------------------------------------------------

class ToolError(RuntimeError):
    pass


_CALL_LOG = []


def call(tool, payload, toolset=None):
    """Execute one Niagara toolset tool. Returns the tool's `returnValue` payload.

    The async result completes synchronously for this toolset, so no editor tick
    is required. If it ever does not complete, we fail loudly rather than hang.

    `toolset` defaults to the System toolset because 46 of the 56 tools live
    there. Pass BLUEPRINT_TOOLSET for ConstructNiagaraBPWrapperFrom*, and
    COMPONENT_TOOLSET for SetSystem/SetVariable/GetVariable/GetUserVariables.
    """
    raw = unreal.ToolsetRegistry.execute_tool(toolset or TOOLSET, tool,
                                              json.dumps(payload))
    if raw is None:
        raise ToolError("%s: registry returned no result object" % tool)

    spins = 0
    while not raw.get_editor_property("is_complete"):
        spins += 1
        if spins > 20000000:
            raise ToolError("%s: async result never completed" % tool)

    err = raw.get_editor_property("error")
    if err:
        _CALL_LOG.append((tool, "ERROR", err))
        raise ToolError("%s: %s" % (tool, err))

    blob = raw.get_editor_property("value")
    _CALL_LOG.append((tool, "OK", ""))
    if blob is None or blob == "":
        return None
    try:
        parsed = json.loads(blob)
    except Exception as exc:
        raise ToolError("%s: return value is not JSON (%s)" % (tool, exc))
    if isinstance(parsed, dict) and "returnValue" in parsed:
        return parsed["returnValue"]
    return parsed


def call_quiet(tool, payload, toolset=None):
    """Same as call() but returns (ok, result_or_error)."""
    try:
        return True, call(tool, payload, toolset)
    except ToolError as exc:
        return False, str(exc)


# --------------------------------------------------------------------------
# latent calls - for tools that only complete on an editor tick
# --------------------------------------------------------------------------

def call_async(tool, payload, toolset=None):
    """Fire a tool and hand back the unfinished result object.

    call() spins until is_complete. That is fine for the authoring tools, which
    complete synchronously, but it deadlocks for anything that genuinely waits
    on a tick (GetStackIssues and GetSystemCompileState both wait on a Niagara
    compile). Inside a tick callback, spinning for a tick that will not arrive
    is a hang, so those two get polled across ticks instead.
    """
    raw = unreal.ToolsetRegistry.execute_tool(toolset or TOOLSET, tool,
                                              json.dumps(payload))
    if raw is None:
        raise ToolError("%s: registry returned no result object" % tool)
    return raw


def poll(raw, tool="?"):
    """Read an in-flight result. Returns (done, ok, value_or_error)."""
    if not raw.get_editor_property("is_complete"):
        return False, None, None
    err = raw.get_editor_property("error")
    if err:
        return True, False, str(err)
    blob = raw.get_editor_property("value")
    if blob is None or blob == "":
        return True, True, None
    try:
        parsed = json.loads(blob)
    except Exception as exc:
        return True, False, "%s: return value is not JSON (%s)" % (tool, exc)
    if isinstance(parsed, dict) and "returnValue" in parsed:
        return True, True, parsed["returnValue"]
    return True, True, parsed


def call_log():
    return list(_CALL_LOG)
