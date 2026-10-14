"""
p50_topology_control.py - prove the topology reader, on a system that works.

WHY THIS RUN EXISTS AT ALL
    p49 answered all eleven emitters with:

        Emitter Spawn     0 modules: (none)
        Emitter Update    0 modules: (none)
        Particle Spawn    0 modules: (none)
        Particle Update   0 modules: (none)

    and that single reading explains every symptom measured all session:
        - the compile warning "no connection to the output node of type 4/5"
          (nothing feeds the Output node, because there are no modules)
        - p48's activation refusal (a system that is not ready to run will not
          activate)
        - zero pixels in every frame

    Which makes it the most load-bearing number in the whole investigation, and
    reading an empty list is exactly the shape of result that has been wrong
    twice already this session - once from a probe that could not distinguish
    "empty" from "failed", once from a log transcribed into a comment.

    So it gets the same treatment as everything else: a control. Run
    GetEmitterTopology on a stock engine system that is KNOWN to run - p48
    measured FountainLightweight activating and staying active - and see what
    the tool reports for a healthy emitter. If a healthy emitter shows modules
    and ours shows none, the instrument is proven and the nine are empty. If the
    tool shows none for a healthy emitter too, then "0 modules" means "this tool
    cannot see modules in this session", and p49 must not be used as evidence.

    The raw JSON of one stack from each subject is dumped as well, so the shape
    is on the record rather than only the count. A count is an interpretation;
    the JSON is not.

    GetStackIssues is also asked once per subject, because it is the tool that
    yields IssueId/FixId pairs for ApplyStackIssueFix. It waits on a compile, so
    a stock system - which does compile - is the one place it might answer.

OUTPUT
    exports/p50_topology.txt

Usage:
    cd sword_vfx/scripts && UE_TIMEOUT=240 ./run_ue.sh p50_topology_control.py --editor
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import json
import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p50_topology.txt')
SYS_DIR = "/Game/SEKAI/VFX/Sword/Systems"

SUBJECTS = (
    ("stock/Fountain", "/Niagara/DefaultAssets/Templates/Systems/FountainLightweight"),
    ("stock/RadialBurst", "/Niagara/DefaultAssets/Templates/Systems/RadialBurst"),
    ("stock/Explosion", "/Niagara/DefaultAssets/Templates/Systems/SimpleExplosion"),
    ("ours/EdgeTrail", "%s/NS_SW_Core_EdgeTrail" % SYS_DIR),
)

DEADLINE = 25.0
BUDGET_SECONDS = 200.0

WFX.bind_log(EXPORT)
log = WFX.log

log("engine: %s" % unreal.SystemLibrary.get_engine_version())
log("")
log("The question is not whether our systems are empty. It is whether this")
log("tool can see modules AT ALL in this session. A stock system that p48")
log("measured running is the control.")

ST = {"handle": None, "started": time.time(), "ticks": 0, "phase": "fire",
      "errors": 0, "pending": [], "results": {}, "emitters": {}, "order": []}

WFX.install_watchdog(grace_seconds=BUDGET_SECONDS + 25.0)


def fire(tag, tool, payload):
    try:
        raw = WFX.call_async(tool, payload)
    except Exception as exc:
        ST["results"][tag] = {"ok": False, "why": "fire failed: %s"
                              % str(exc)[:110]}
        log("  %-24s FIRE FAILED  %s" % (tag, str(exc)[:80]))
        return
    ST["pending"].append({"tag": tag, "tool": tool, "raw": raw,
                          "deadline": time.time() + DEADLINE})
    ST["order"].append(tag)


def drain():
    still = []
    for p in ST["pending"]:
        try:
            done, ok, value = WFX.poll(p["raw"], p["tool"])
        except Exception as exc:
            ST["results"][p["tag"]] = {"ok": False,
                                       "why": "poll raised %s" % str(exc)[:90]}
            continue
        if done:
            ST["results"][p["tag"]] = {"ok": bool(ok), "value": value}
        elif time.time() > p["deadline"]:
            ST["results"][p["tag"]] = {"ok": False,
                                       "why": "unanswered within %.0f s"
                                              % DEADLINE}
        else:
            still.append(p)
    ST["pending"] = still
    return len(still)


def emitter_names(value):
    out = []
    if isinstance(value, dict):
        lst = value.get("emitters")
        if isinstance(lst, (list, tuple)):
            for e in lst:
                if isinstance(e, dict):
                    nm = e.get("name") or e.get("emitterName")
                    if nm:
                        out.append(str(nm))
    return out


def stack_modules(stack):
    """(found_key, list). Returns the key it used so an unexpected shape is
    visible rather than being read as zero modules."""
    if not isinstance(stack, dict):
        return None, None
    for key in ("modules", "Modules", "moduleTopologies"):
        if isinstance(stack.get(key), (list, tuple)):
            return key, list(stack[key])
    return None, None


def report(tag, value):
    if not isinstance(value, dict):
        log("    %s -> %s" % (tag, str(value)[:160]))
        return
    log("    %s  keys: %s"
        % (tag, ", ".join(sorted(value)[:14])))
    total = 0
    for label, key in (("Emitter Spawn", "emitterSpawnScript"),
                       ("Emitter Update", "emitterUpdateScript"),
                       ("Particle Spawn", "particleSpawnScript"),
                       ("Particle Update", "particleUpdateScript")):
        if key not in value:
            log("      %-18s <key absent>" % label)
            continue
        used, mods = stack_modules(value[key])
        if used is None:
            log("      %-18s NO MODULE KEY; stack keys = %s"
                % (label, ", ".join(sorted(value[key])[:8])
                   if isinstance(value[key], dict) else type(value[key]).__name__))
            continue
        total += len(mods)
        names = []
        for m in mods:
            if isinstance(m, dict):
                nm = (m.get("name") or m.get("moduleName") or m.get("Name")
                      or "?")
                ins = m.get("inputs")
                names.append("%s(%s)" % (nm,
                                         len(ins) if isinstance(ins, (list, tuple))
                                         else "?"))
            else:
                names.append(str(m)[:24])
        log("      %-18s %-16s %2d modules: %s"
            % (label, "[key %r]" % used, len(mods),
               ", ".join(names) if names else "(none)"))
    log("      TOTAL MODULES ACROSS ALL FOUR STACKS: %d" % total)
    return total


def tick(delta):
    st = ST
    st["ticks"] += 1
    if time.time() - st["started"] > BUDGET_SECONDS:
        _finish("budget exhausted")
        return
    try:
        if st["phase"] == "fire":
            log("")
            log("=" * 74)
            log("ROUND 1 - emitter names")
            log("=" * 74)
            for tag, path in SUBJECTS:
                fire("sum/%s" % tag, "GetSystemSummary",
                     {"system": WFX.ref(path)})
            st["phase"] = "poll_sum"
            return

        if st["phase"] == "poll_sum":
            if drain():
                return
            log("")
            for tag, path in SUBJECTS:
                r = st["results"].get("sum/%s" % tag) or {}
                if not r.get("ok"):
                    log("  %-16s NO ANSWER  %s"
                        % (tag, str(r.get("why"))[:80]))
                    continue
                ems = emitter_names(r.get("value"))
                st["emitters"][tag] = ems
                log("  %-16s %d emitter(s): %s"
                    % (tag, len(ems), ", ".join(ems) if ems else "-"))
            log("")
            log("=" * 74)
            log("ROUND 2 - GetEmitterTopology, the control")
            log("=" * 74)
            n = 0
            for tag, path in SUBJECTS:
                for em in st["emitters"].get(tag, []):
                    fire("topo/%s/%s" % (tag, em), "GetEmitterTopology",
                         {"emitterRef": WFX.stack_ref(path, emitter=em)})
                    n += 1
            if n == 0:
                _finish("no emitter names recovered")
                return
            log("  %d topology questions fired" % n)
            st["phase"] = "poll_topo"
            return

        if st["phase"] == "poll_topo":
            if drain():
                return
            log("")
            st["totals"] = {}
            for tag, path in SUBJECTS:
                for em in st["emitters"].get(tag, []):
                    r = st["results"].get("topo/%s/%s" % (tag, em)) or {}
                    log("")
                    log("  --- %s / %s ---" % (tag, em))
                    if not r.get("ok"):
                        log("      NO ANSWER  %s" % str(r.get("why"))[:100])
                        continue
                    t = report(tag, r.get("value")) or 0
                    st["totals"][tag] = st["totals"].get(tag, 0) + t
            log("")
            log("=" * 74)
            log("ROUND 3 - the raw shape of ONE stack, from each subject")
            log("=" * 74)
            for tag, path in SUBJECTS:
                ems = st["emitters"].get(tag, [])
                if not ems:
                    continue
                r = st["results"].get("topo/%s/%s" % (tag, ems[0])) or {}
                if not r.get("ok"):
                    continue
                log("")
                log("  --- %s / %s : particleSpawnScript verbatim ---" % (tag, ems[0]))
                try:
                    blob = json.dumps(r["value"].get("particleSpawnScript"),
                                      ensure_ascii=False, indent=1, default=str)
                except Exception as exc:
                    blob = "<not serialisable: %s>" % str(exc)[:60]
                for line in blob.splitlines()[:40]:
                    log("    %s" % line)
            log("")
            log("=" * 74)
            log("ROUND 4 - GetStackIssues, once per subject")
            log("=" * 74)
            log("  this is the only tool that yields IssueId/FixId pairs, and it")
            log("  waits on a compile - so a stock system is the one place it")
            log("  has any chance of answering.")
            for tag, path in SUBJECTS:
                fire("issues/%s" % tag, "GetStackIssues",
                     {"system": WFX.ref(path)})
            st["phase"] = "poll_issues"
            return

        if st["phase"] == "poll_issues":
            if drain():
                return
            log("")
            for tag, path in SUBJECTS:
                r = st["results"].get("issues/%s" % tag) or {}
                if r.get("ok"):
                    log("  %-16s ANSWER: %s" % (tag, str(r.get("value"))[:2500]))
                else:
                    log("  %-16s NO ANSWER: %s"
                        % (tag, str(r.get("why"))[:100]))
            _finish("control readback complete")
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:170]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 12:
            _finish("too many tick errors")


def _finish(reason):
    if ST.get("phase") == "done":
        return
    ST["phase"] = "done"
    log("")
    log("=" * 74)
    log("SUMMARY")
    log("=" * 74)
    log("stop reason : %s" % reason)
    log("elapsed     : %.1f s over %d ticks" % (time.time() - ST["started"],
                                                ST["ticks"]))
    log("tick errors : %d" % ST["errors"])
    tots = ST.get("totals") or {}
    log("")
    for tag, _p in SUBJECTS:
        log("  %-16s total modules across all stacks: %s"
            % (tag, tots.get(tag, "no answer")))
    log("")
    stock_tot = [tots.get(t) for t, _p in SUBJECTS if t.startswith("stock/")]
    ours_tot = tots.get("ours/EdgeTrail")
    have_stock = [v for v in stock_tot if isinstance(v, int)]
    if not have_stock or ours_tot is None:
        log("=> THE CONTROL DID NOT ANSWER, so p49's '0 modules' cannot be")
        log("   confirmed or refuted by this run. Do not treat it as evidence.")
    elif max(have_stock) > 0 and ours_tot == 0:
        log("=> THE READER IS PROVEN. A stock engine system reports modules")
        log("   through the same call, and ours reports none, so '0 modules' is")
        log("   a measurement about the nine assets and not about the tool.")
        log("   The nine systems are EMPTY SHELLS: right names, right emitters,")
        log("   right renderers, and nothing in any script stack.")
    elif max(have_stock) == 0 and ours_tot == 0:
        log("=> THE TOOL REPORTS ZERO MODULES FOR A HEALTHY SYSTEM TOO, so p49's")
        log("   reading means 'this call cannot see modules in this session' and")
        log("   must not be quoted as evidence that the systems are empty.")
    else:
        log("=> OURS REPORTED MODULES AND THE STOCK DID NOT - read the raw")
        log("   stacks above before drawing anything from this.")
    log("P50 DONE")
    try:
        if ST["handle"] is not None:
            unreal.unregister_slate_post_tick_callback(ST["handle"])
    except Exception:
        pass
    try:
        WFX.watchdog_handover()
    except Exception:
        pass
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception as exc:
        log("quit_editor failed: %s" % str(exc)[:120])


ST["handle"] = unreal.register_slate_post_tick_callback(tick)
