"""SEKAI Sword VFX - P22: are the nine core systems actually valid?

WHY THIS EXISTS

    Two reasons, and neither is "nice to have".

    1. INDEPENDENT READ-BACK. Every claim about what the nine systems contain
       currently comes from P11's own report - the builder reporting on itself.
       That is the weakest possible evidence for a graph, because a builder that
       silently failed to attach a module would report the module it *meant* to
       attach. This asks the engine, through different tools, what is really
       there.

    2. THE ENGINE HAS NOW SAID SOMETHING, AND IT IS BAD. Running a render pass
       over the review level made UE compile the systems it contains, and the
       engine logged, verbatim:

           Ensure condition failed: !ModuleGroup.StartNodes.IsEmpty()
             [NiagaraStackGraphUtilities.cpp:906]
           ModuleGroup for .../NS_SW_Core_EdgeTrail...:NiagaraNodeFunctionCall_2
             has no StartNodes

       alongside 88 of

           Ensure condition failed:
             Pin->LinkedTo.Contains(ReferencingPin)
             || GEditor->Trans->IsObjectTransacting(Pin->GetOwningNode())
             [EdGraphPin.cpp:2036]

       and, for eight of the nine systems,

           无法找到通向类型为4的输出节点的任何连接！   (and type 5)

       Those three messages describe one condition: a module sits in a stack but
       is not wired into the execution chain ("has no StartNodes"), so its
       output pin has no connection, and the pin links are not reciprocal. If
       that is right, then section 35's IMPLEMENTED - "the Niagara graph really
       exists and RUNS" - has NOT been earned by these assets, and section 0's
       rule against claiming a graph is built applies directly to them.

    So this asks the engine the two questions that settle it:

        GetSystemCompileState   does the system compile, and to what state?
        GetStackIssues          what does Niagara itself say is wrong, with the
                                IssueId/FixId of any repair it can apply?

    It reports. It does not repair and it does not grade - the next step is
    chosen from its output, not from this script.

WHY A COMMANDLET

    Reading a compile state does not need ticks. More to the point, a commandlet
    never builds the Niagara editor's stack VIEW MODEL - which is the code that
    asserted and then hung the editor for five minutes at shutdown. So if this
    probe runs to completion over all nine systems, the graphs are at least
    enumerable, and the hang is about the editor's view of them.

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p22_stack_probe.py     (commandlet)
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

import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p22_stack_probe.txt')
JSON_OUT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p22_topology.json')

SYS_DIR = "/Game/SEKAI/VFX/Sword/Systems"

# Loaded by name, never discovered with list_assets(): the discovery call was a
# co-factor in an earlier engine crash inside the transaction system, and the
# nine names are known. A discovery API that can crash the editor to tell you
# something you already know is not worth using.
SYSTEMS = (
    ("NS_SW_Core_EdgeTrail", ("E_Trail",)),
    ("NS_SW_Core_Glint", ("E_Glint",)),
    ("NS_SW_Core_AirSlice", ("E_Slice",)),
    ("NS_SW_Core_Wave", ("E_Wave", "E_MistWake")),
    ("NS_SW_Core_SpatialScar", ("E_Scar", "E_ScarMist")),
    ("NS_SW_Core_MajorArc", ("E_Arc", "E_ArcMist")),
    ("NS_SW_Core_MistWake", ("E_Wisp",)),
    ("NS_SW_Core_PurpleMotes", ("E_Motes",)),
    ("NS_SW_Core_Hit", ("E_Hit",)),
)

LINES = []


def log(msg=""):
    msg = str(msg)
    LINES.append(msg)
    print(msg)
    with open(EXPORT, "a", encoding="utf-8") as fh:
        fh.write(msg + "\n")


open(EXPORT, "w", encoding="utf-8").close()
WFX.bind_log(EXPORT, truncate=False)


def sys_path(name):
    return "%s/%s.%s" % (SYS_DIR, name, name)


def module_names(topology):
    """Pull module names out of an emitter topology of unknown shape.

    The toolset documents the topology as "all four script stacks, all fields
    always populated" but not the key names, and P11 already lost time to an
    assumed shape (`AttributeError: 'list' object has no attribute 'get'`). So
    this walks whatever comes back and collects anything that looks like a
    module entry rather than indexing into an assumed structure.
    """
    out = []

    def walk(node, trail):
        if isinstance(node, dict):
            name = node.get("name")
            if isinstance(name, str) and name and "module" in trail.lower():
                out.append((trail, name))
            for k, v in node.items():
                walk(v, "%s.%s" % (trail, k))
        elif isinstance(node, list):
            for n in node:
                walk(n, trail + "[]")

    walk(topology, "topology")
    return out


def collect_issues(node, out, trail="issues"):
    """Collect anything shaped like a stack issue, plus any fixes it offers.

    Defensive on purpose: the shape is not documented, an assumed shape already
    cost time once in this project, and the whole point here is to find out what
    the engine says rather than to confirm what I expect it to say.
    """
    if isinstance(node, dict):
        keys = set(k.lower() for k in node.keys())
        looks_like_issue = ({"issueid"} & keys) or \
                           ({"severity", "message"} <= keys) or \
                           ({"message"} & keys and {"id"} & keys)
        if looks_like_issue:
            entry = {"trail": trail, "raw": node}
            for k, v in node.items():
                lk = k.lower()
                if lk in ("message", "description", "severity", "issueid",
                          "id", "enabled", "canbefixed", "fixes", "title",
                          "name"):
                    entry[k] = v
            out.append(entry)
            return
        for k, v in node.items():
            collect_issues(v, out, "%s.%s" % (trail, k))
    elif isinstance(node, list):
        for i, n in enumerate(node):
            collect_issues(n, out, "%s[%d]" % (trail, i))


def brief(value, limit=220):
    """One readable line for a value of unknown shape."""
    if isinstance(value, (dict, list)):
        try:
            text = json.dumps(value, ensure_ascii=False)
        except Exception:
            text = repr(value)
    else:
        text = str(value)
    text = " ".join(text.split())
    return text if len(text) <= limit else text[:limit] + " ..."


log("engine: " + unreal.SystemLibrary.get_engine_version())
log("mode  : commandlet (no ticks, no Niagara stack view model)")
log("")
log("Two questions per system:")
log("    GetSystemCompileState - does it compile, and to what?")
log("    GetStackIssues        - what does Niagara itself say is wrong?")
log("")

REPORT = {"systems": [], "errors": [], "summary": {}}
for name, emitters in SYSTEMS:
    path = sys_path(name)
    log("=" * 74)
    log("--- %s" % name)
    entry = {"name": name, "path": path, "emitters": [], "issues": []}

    asset = unreal.EditorAssetLibrary.load_asset(path)
    if asset is None:
        log("    LOAD FAILED - asset not on disk at %s" % path)
        entry["load"] = False
        REPORT["errors"].append("%s: load failed" % name)
        REPORT["systems"].append(entry)
        continue
    entry["load"] = True

    # --- compile state ---------------------------------------------------
    ok, res = WFX.call_quiet("GetSystemCompileState",
                             {"system": WFX.ref(path)})
    if ok:
        entry["compile_state"] = res
        log("    compile state : %s" % brief(res))
    else:
        entry["compile_state"] = None
        entry["compile_error"] = str(res)[:400]
        log("    compile state : FAILED - %s" % str(res)[:200])
        REPORT["errors"].append("%s: GetSystemCompileState: %s"
                                % (name, str(res)[:150]))

    # --- stack issues ----------------------------------------------------
    ok, res = WFX.call_quiet("GetStackIssues", {"system": WFX.ref(path)})
    issues = []
    if ok:
        collect_issues(res, issues)
        entry["stack_issues_raw"] = res
        entry["issues"] = issues
        log("    stack issues  : %d" % len(issues))
        for i, iss in enumerate(issues[:12]):
            log("        [%d] severity=%s  %s"
                % (i, brief(iss.get("severity"), 40),
                   brief(iss.get("message") or iss.get("description"), 160)))
            iid = iss.get("issueId") or iss.get("id")
            if iid:
                log("            issueId=%s" % brief(iid, 80))
            fixes = iss.get("fixes") or iss.get("fixesRaw")
            if fixes:
                log("            fixes  =%s" % brief(fixes, 180))
        if len(issues) > 12:
            log("        ... and %d more (all in the JSON)" % (len(issues) - 12))
    else:
        entry["stack_issues_raw"] = None
        log("    stack issues  : FAILED - %s" % str(res)[:200])
        REPORT["errors"].append("%s: GetStackIssues: %s" % (name, str(res)[:150]))

    # --- per-emitter topology (the module list, read back not remembered) --
    for em in emitters:
        em_entry = {"name": em, "stacks": {}, "error": ""}
        ok, res = WFX.call_quiet("GetEmitterTopology",
                                 {"emitterRef": WFX.stack_ref(path, emitter=em)})
        if not ok:
            log("    %-12s GetEmitterTopology FAILED: %s" % (em, str(res)[:160]))
            em_entry["error"] = str(res)[:400]
            REPORT["errors"].append("%s/%s: %s" % (name, em, str(res)[:150]))
            entry["emitters"].append(em_entry)
            continue
        found = module_names(res)
        if found:
            for trail, mod in found:
                em_entry["stacks"].setdefault(trail, []).append(mod)
            log("    %-12s modules read back: %d" % (em, len(found)))
            for trail, mod in found:
                log("        %-42s %s" % (trail[:42], mod))
        else:
            log("    %-12s topology returned, but no module entries matched the "
                "walk - raw shape in the JSON" % em)
            em_entry["raw_keys"] = (sorted(res.keys())
                                    if isinstance(res, dict)
                                    else type(res).__name__)
        em_entry["raw"] = res
        entry["emitters"].append(em_entry)

    REPORT["systems"].append(entry)

# --- tally ---------------------------------------------------------------
log("")
log("=" * 74)
log("--- tally ---")
loaded = [s for s in REPORT["systems"] if s.get("load")]
with_issues = [s for s in loaded if s.get("issues")]
compiled = [s for s in loaded if s.get("compile_state") is not None]
em_total = sum(len(s["emitters"]) for s in REPORT["systems"])
em_ok = sum(1 for s in REPORT["systems"] for e in s["emitters"]
            if not e.get("error"))
total_issues = sum(len(s.get("issues") or []) for s in loaded)
any_fixes = 0
for s in loaded:
    for i in (s.get("issues") or []):
        if i.get("fixes"):
            any_fixes += 1

log("    systems loaded        : %d / %d" % (len(loaded), len(SYSTEMS)))
log("    compile state read    : %d / %d" % (len(compiled), len(SYSTEMS)))
log("    emitters readable     : %d / %d" % (em_ok, em_total))
log("    systems with issues   : %d / %d" % (len(with_issues), len(loaded)))
log("    total stack issues    : %d" % total_issues)
log("    issues offering fixes : %d" % any_fixes)
log("    errors                : %d" % len(REPORT["errors"]))
for e in REPORT["errors"][:12]:
    log("      ! %s" % e)

REPORT["summary"] = {
    "loaded": len(loaded), "compile_state_read": len(compiled),
    "emitters_ok": em_ok, "emitters_total": em_total,
    "systems_with_issues": len(with_issues), "total_issues": total_issues,
    "issues_with_fixes": any_fixes, "errors": len(REPORT["errors"]),
}

log("")
log("--- what this does and does not establish ---")
log("    A system that reports ZERO stack issues and a clean compile state has")
log("    cleared the engine's own checks. That is the strongest evidence")
log("    available without opening the graph by hand.")
log("    A system that reports issues has NOT earned section 35's IMPLEMENTED,")
log("    whatever the builder reported - section 35 reads 'the Niagara graph")
log("    really exists and RUNS'.")
log("")
if total_issues:
    log("    => THE ENGINE REPORTS %d STACK ISSUE(S). These systems are not")
    log("       IMPLEMENTED in section 35's sense. The build sheets need the")
    log("       repair either applied via ApplyStackIssueFix where the engine")
    log("       offers a fix, or written up as MANUAL EDITOR STEPs where it")
    log("       does not." % total_issues)
elif compiled:
    log("    => no stack issues reported by any of the %d systems that answered."
        % len(compiled))
else:
    log("    => no compile state could be read, so nothing about validity is")
    log("       established either way.")

log("")
log("P22 VERDICT  : %d/%d loaded, %d issues, %d systems affected, %d fixable"
    % (len(loaded), len(SYSTEMS), total_issues, len(with_issues), any_fixes))
log("P22 DONE")

with open(JSON_OUT, "w", encoding="utf-8") as fh:
    json.dump(REPORT, fh, indent=1, ensure_ascii=False, default=str)
log("")
log("full read-back JSON -> %s" % JSON_OUT)
