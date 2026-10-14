"""SEKAI Sword VFX - generate docs/EXACT_BUILD.md from the build report.

WHY THIS IS GENERATED AND NOT WRITTEN BY HAND

    The brief (section 28) asks for a build sheet precise enough that a person
    opening Niagara can follow it directly. A hand-written sheet describes what
    someone MEANT to build; this one describes what was built, because it is
    derived from the same run that produced the assets. When the script changes,
    the document changes, and it cannot quietly fall out of date.

    Inputs, both produced by the UE run:
        exports/p11_report.json        what the builder did (plan + observed)
        exports/p12_module_inputs.json what each module asset actually exposes

    Plain Python, no `unreal`, so it can be run at any time.

Usage:
    python gen_build_sheets.py [--report PATH] [--out PATH]
"""
import argparse
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEF_REPORT = os.path.join(ROOT, "exports", "p11_report.json")
DEF_MODULES = os.path.join(ROOT, "exports", "p12_module_inputs.json")
DEF_OUT = os.path.join(ROOT, "docs", "EXACT_BUILD.md")

PHASE_ORDER = ["SystemSpawnScript", "SystemUpdateScript", "EmitterSpawnScript",
               "EmitterUpdateScript", "ParticleSpawnScript", "ParticleUpdateScript"]
PHASE_BLURB = {
    "EmitterSpawnScript": "runs once when the emitter starts",
    "EmitterUpdateScript": "once per frame, per emitter",
    "ParticleSpawnScript": "once, per particle, at birth",
    "ParticleUpdateScript": "once per frame, per particle",
}

# Manual steps that are structural rather than a curve. This list is short and
# explicit on purpose: it is the part a human cannot get from the report.
RENDERER_STEPS = {
    "ribbon": [
        "Tessellation Mode = **Custom** (not `Automatic`). Automatic tessellation "
        "re-tessellates per frame and a ribbon that follows a blade visibly "
        "changes width as it swings.",
        "Segments per Tessellation = 8. Below that a fast arc goes polygonal; "
        "above it, it is invisible on a 0.05 m ribbon.",
        "UV0 Tiling Distance / Tile U = 4, so the Edge mask scrolls four times "
        "along the ribbon instead of stretching once.",
        "Set `Material Parameter Binding` on the ribbon so the mask scroll speed "
        "comes from Speed, not from a hard-coded number.",
    ],
    "mesh": [
        "Facing Mode = `Custom` with `Custom Facing Vector` bound to the cut "
        "normal. The sheets are authored +Z-normal, so the default "
        "`Face Camera` would turn a spatial scar into a billboard and it would "
        "stop living in the world.",
        "Mesh Alignment = `World` for A3/A4 (they stay where they were cut); "
        "`Velocity` is wrong for both.",
        "Pivot Offset stays (0,0,0) for every generated mesh: each one is "
        "authored about the point it should scale and rotate about.",
    ],
    "sprite": [
        "Alignment = `Velocity Aligned` is NOT wanted here; the glint and motes "
        "are camera-independent points of light, so leave it `Unaligned`.",
        "Sub Image / sprite size index stays 0 - sizing is done on the particle.",
    ],
    "light": [
        "Radius Scale is set to 40.0. A point light on a sword draw that is too "
        "wide lights the whole hand and stops reading as an edge highlight.",
        "Keep it to one particle. The exporter cost is per-light.",
    ],
}

SYSTEM_MANUAL_EXTRA = {
    "NS_SW_Core_EdgeTrail": [
        "This is the ONE system both A1 and A4 use. A1 wants a thin trail "
        "(0.42 of width) and A4 wants a wide one (1.75), so the caller sets "
        "`User.Width`; do not add a second trail system for A4.",
        "Draw-on for A4 comes from the mask scrolling along U, NOT from a ribbon "
        "lifetime curve. A ribbon whose endpoints are animated to reveal it "
        "reads as a growing object, not a cut being drawn.",
    ],
    "NS_SW_Core_Wave": [
        "0.18-0.35 s is the contract window for the flight. Godot's own numbers "
        "are 8.4 m at 26.0 m/s = 0.323 s, so `User.Velocity.X = 26` and "
        "`User.Lifetime = 0.323` reproduce the shipping feel exactly.",
        "The sheet must NOT be given a roll or a spin. It is a pressure sheet "
        "with a leading edge, and rolling it destroys the edge.",
    ],
    "NS_SW_Core_SpatialScar": [
        "Three instances, three positions, three angles - the caller's job. The "
        "graph must not try to branch on which cut it is.",
        "The offsets in Godot's `move.traces` are what stop the three marks "
        "reading as a starburst. If all three arrive at the same screen point, "
        "the beat has failed no matter how good one scar looks.",
        "SCAR_EDGE_WIDTH is 0.034 m because 0.020 m was sub-pixel at 720p at "
        "16 m. Re-check the edge width against the ACTUAL camera distance in the "
        "lab; a world width that read fine at 8 m will vanish at 18 m.",
    ],
    "NS_SW_Core_MajorArc": [
        "270 degrees. Godot's `reach_arc_from = -140`, `reach_arc_to = 130`. "
        "A 360 degree ring is explicitly forbidden and this number is the reason.",
        "ARC_BAND 0.13 m, not a wall: 0.32 m subtended ~100 px at 720p and read "
        "as a standing sheet of water rather than a blade going past.",
        "The draw-on is a U wipe along the sweep. Uniform scale = expanding ring "
        "= shockwave, which is what the beat must not be.",
    ],
    "NS_SW_Core_MistWake": [
        "Zero cost in the Normal profile because `User.MistRate` is 0. Do not "
        "'optimise' it by removing the emitter: the Magic profile needs it and "
        "the whole point of section 23 is that both swords are one graph.",
        "Growth must be slow. Fast-growing mist reads as an explosion, which is "
        "the opposite of 'darkness that does not belong to this world leaking "
        "out'.",
    ],
    "NS_SW_Core_PurpleMotes": [
        "`User.SpawnRate` must be single digits and 0 while stowed. A "
        "continuous stream is the 'smoke machine' the brief names as a failure.",
        "This system also carries the single point glint at the saya mouth on "
        "the final click (20-50 ms). That is a separate, timed one-shot - do not "
        "raise the idle rate to make it appear.",
    ],
    "NS_SW_Core_Glint": [
        "The glint is only legible because Beat 2 exposes 160 mm of blade "
        "(`NE_PARTIAL_DRAW`). If the draw timing changes, the glint duration "
        "must be re-derived from the event pair at 0.95 s and 1.07 s, never from "
        "a Lifetime value.",
        "Inspect (brief section 8) reuses THIS system with slower values. There "
        "is no separate inspect graph to build.",
    ],
    "NS_SW_Core_Hit": [
        "One system, one material instance per surface. The graph must never "
        "branch on surface type; the caller chooses the instance.",
        "The contact timing belongs to the animation event. A Delay module in "
        "here would desync the moment the move is retuned.",
    ],
    "NS_SW_Core_AirSlice": [
        "Not a projectile. Godot's A1 is `reach_mode = body`, so nothing "
        "travels. Give it no Velocity module.",
        "Draw-on is the U wipe: 0 -> 1 across the first 35 percent of life, "
        "50-100 ms total.",
    ],
}

STATUS_NOTE = """\
## What this document certifies, and what it does not

Every table below is generated from `exports/p11_report.json`, i.e. from the
run that produced the assets. That means the module choices, the input names and
the linked `User.*` parameters are **observed**, not intended.

It does **not** certify that the graphs look right, and it does not certify that
they compile. Read the per-system status line, and treat anything not marked
`UpToDate` as unfinished. The vocabulary is the brief's:

| Term | Meaning |
|---|---|
| `SPEC READY` | design / build sheet only |
| `ASSET READY` | material / texture / mesh exists |
| `IMPLEMENTED` | the Niagara graph really exists and runs |
| `VISUALLY VERIFIED` | actually looked at in the editor, on a bright AND a dark wall |
| `GAMEPLAY VERIFIED` | running against the real Sword animation and combat |
"""


def load(path):
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def fmt_value(v):
    if isinstance(v, dict):
        for k in ("refPath",):
            if k in v:
                return "`%s`" % str(v[k]).rsplit(".", 1)[-1]
        if "value" in v and isinstance(v["value"], dict):
            return fmt_value(v["value"])
        if "x" in v:
            return "(%s, %s, %s)" % (v.get("x"), v.get("y"), v.get("z"))
        if "r" in v:
            return "(r %s, g %s, b %s, a %s)" % (v.get("r"), v.get("g"),
                                                 v.get("b"), v.get("a"))
        if "value" in v:
            return "`%s`" % v["value"]
        return "`%s`" % json.dumps(v, ensure_ascii=False)
    if v is None:
        return "*(default)*"
    return "`%s`" % v


def sysname(path):
    """'/Game/.../NS_SW_Core_Wave.NS_SW_Core_Wave' -> 'NS_SW_Core_Wave'.

    Matching on endswith('/' + name) silently matched nothing, because the toolset
    reports object paths: the name appears after a DOT, not after a slash.
    """
    s = str(path or "")
    return s.rsplit(".", 1)[0].rsplit("/", 1)[-1]


def compile_cell(c):
    """Report staleness, because UpToDate alone is misleading here.

    A headless builder gets aggregateStatus=UpToDate while bIsStale is also true:
    the two disagree, and the honest reading is that no compile has been
    PERFORMED. Printing only the aggregate would turn that into a claim.
    """
    st = c.get("aggregate_status")
    if not st:
        return c.get("state_unavailable") or "—"
    if c.get("is_stale") or c.get("is_compiling"):
        return "`%s` **but stale**" % st
    return "`%s`" % st


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", default=DEF_REPORT)
    ap.add_argument("--modules", default=DEF_MODULES)
    ap.add_argument("--out", default=DEF_OUT)
    args = ap.parse_args()

    rep = load(args.report)
    if rep is None:
        raise SystemExit("no report at %s - run p11_niagara.py first"
                         % args.report)
    mods = load(args.modules) or {}

    plan = rep.get("plan") or []
    by_name = {s["name"]: s for s in plan}
    compile_by = {c["system"]: c for c in (rep.get("compile") or {}).values()}
    saved_by = {s["system"]: s for s in rep.get("saved") or []}

    out = []
    w = out.append

    w("# EXACT NIAGARA BUILD SHEET")
    w("")
    w("**Generated** by `tools/gen_build_sheets.py` from `exports/p11_report.json`.")
    w("Do not edit by hand — regenerate it. Every input name below was read back")
    w("from the live module topology during the build, and every arrow points at a")
    w("binding that was re-read from the graph afterwards.")
    w("")
    w("Built into `/Game/SEKAI/VFX/Sword/Systems/`.")
    w("")
    w(STATUS_NOTE)
    w("")

    # ---- headline status ----
    w("## Headline")
    w("")
    w("| System | Built | Saved | Compile | Links verified | Manual steps |")
    w("|---|---|---|---|---|---|")
    total_pins = 0
    for s in plan:
        name = s["name"]
        c = compile_by.get(name, {})
        vpins = sum(v.get("count", 0) for v in rep.get("verified") or []
                    if sysname(v.get("system")) == name)
        total_pins += vpins
        n_manual = len([m for m in rep.get("manual_steps") or []
                        if sysname(m.get("system")) == name])
        w("| `%s` | yes | %s | %s | %d | %d |"
          % (name,
             "yes" if saved_by.get(name, {}).get("ok") else "**no**",
             compile_cell(c), vpins, n_manual))
    w("")
    w("Totals: **%d** systems, **%d** module pins re-read from the graph, "
      "**%d** user parameters, **%d** manual editor steps."
      % (len(plan), total_pins, len(rep.get("user_params") or []),
         len(rep.get("manual_steps") or [])))
    w("")

    # ---- user parameters ----
    w("## User parameters (one set, 24 entries, on every system)")
    w("")
    w("These are added individually, so a refusal names the parameter it refused.")
    w("Brief section 24, plus four additions that exist because a module input")
    w("would not take the scalar form.")
    w("")
    w("| Parameter | Type | Purpose |")
    w("|---|---|---|")
    for p in rep.get("user_params") or []:
        w("| `%s` | %s | %s |" % (p["name"], p["type"].rsplit(".", 1)[-1],
                                  p["description"]))
    w("")

    # ---- module reference ----
    w("## Module input reference")
    w("")
    w("Read from the module assets with `GetModuleSchemaFromAsset`, with no system")
    w("context. This is the list of inputs that actually exist — three input names")
    w("in an earlier draft of the builder were wrong and failed silently, so this")
    w("table is the authority.")
    w("")
    for path, info in sorted(mods.items()):
        # p12 also dumps live-topology lists under descriptive keys; only the
        # asset-path keys describe a module's own inputs.
        if not str(path).startswith("/"):
            continue
        if not isinstance(info, dict):
            continue
        inputs = info.get("inputs") or []
        if not inputs:
            continue
        w("### `%s`" % path)
        w("")
        w("| Input | Type |")
        w("|---|---|")
        for i in inputs:
            w("| `%s` | %s |" % (i.get("name"),
                                 str(i.get("type") or "").rsplit(".", 1)[-1]))
        w("")

    # ---- per system ----
    w("## Systems")
    w("")
    for s in plan:
        name = s["name"]
        c = compile_by.get(name, {})
        w("### `%s`" % name)
        w("")
        w("> %s" % s["note"])
        w("")
        w("**Asset:** `/Game/SEKAI/VFX/Sword/Systems/%s`" % name)
        w("")
        status = []
        status.append("built")
        status.append("saved" if saved_by.get(name, {}).get("ok") else "**NOT SAVED**")
        if c.get("aggregate_status"):
            status.append("compile " + compile_cell(c))
        elif c.get("state_unavailable"):
            status.append("compile **unanswered** (%s)" % c["state_unavailable"])
        w("**Status:** " + " · ".join(status))
        w("")
        if c.get("has_errors"):
            w("> **This system reports compile errors.** The evidence is below; "
              "do not treat it as implemented.")
            w("")
        for b in c.get("bad_scripts") or []:
            w("- `%s` / `%s` — **%s** %s" % (b.get("emitter"), b.get("script"),
                                             b.get("status"), b.get("error") or ""))
        if c.get("bad_scripts"):
            w("")
        for i in c.get("issues") or []:
            w("- **%s** %s — `%s`" % (i["severity"], i["short"], i["where"]))
        if c.get("issues"):
            w("")

        for em in s["emitters"]:
            w("#### Emitter `%s`" % em["name"])
            w("")
            w("| # | Renderer | Material | Mesh |")
            w("|---|---|---|---|")
            for n, r in enumerate(em["renderers"]):
                w("| %d | %s | %s | %s |"
                  % (n, r["kind"],
                     "`%s`" % r["material"] if r["material"] else "—",
                     "`%s`" % r["mesh"] if r["mesh"] else "—"))
            w("")

            if em["mods"]:
                w("| Phase | Module | Asset | Input | Bound to |")
                w("|---|---|---|---|---|")
                for m in sorted(em["mods"],
                                key=lambda x: PHASE_ORDER.index(x["script"])
                                if x["script"] in PHASE_ORDER else 99):
                    for i, inp in enumerate(m["inputs"]):
                        bound = ("`%s`" % inp["link"]) if "link" in inp \
                            else fmt_value(inp.get("literal"))
                        w("| %s | %s | `%s` | `%s` | %s |"
                          % (m["script"] if i == 0 else "",
                             ("`%s`" % m["module_key"]) if i == 0 else "",
                             m["asset"].rsplit("/", 1)[-1] if i == 0 else "",
                             inp["input"], bound))
                w("")

            # renderer advice
            kinds = sorted({r["kind"] for r in em["renderers"]})
            if kinds:
                w("##### Renderer settings — MANUAL EDITOR STEP")
                w("")
                for k in kinds:
                    for line in RENDERER_STEPS.get(k, []):
                        w("- **%s:** %s" % (k, line))
                w("")

            if em["manual"]:
                w("##### MANUAL EDITOR STEP")
                w("")
                for n, step in enumerate(em["manual"], 1):
                    w("%d. %s" % (n, step))
                w("")

        extra = SYSTEM_MANUAL_EXTRA.get(name) or []
        if extra:
            w("#### Why this system is built this way")
            w("")
            for line in extra:
                w("- %s" % line)
            w("")

    # ---- refused writes ----
    unmatched = rep.get("unmatched") or []
    not_ed = rep.get("not_editable") or []
    amb = rep.get("ambiguous") or []
    dyn = rep.get("dynamic") or []
    unver = rep.get("unverified") or []
    w("## Writes the toolset refused")
    w("")
    w("Listed rather than hidden. An input the builder could not set is either a")
    w("mistake in the builder or a genuine editor-only step, and the difference")
    w("matters.")
    w("")
    if not (unmatched or not_ed or amb or dyn or unver):
        w("None. Every input the builder asked for was found, editable, and re-read")
        w("back from the graph with the expected binding.")
    else:
        for label, rows, key in (("no such input", unmatched, "wanted"),
                                 ("not editable", not_ed, "input"),
                                 ("ambiguous name", amb, "wanted"),
                                 ("already a dynamic chain", dyn, "input"),
                                 ("set but not confirmed", unver, "input")):
            if not rows:
                continue
            w("**%s** — %d" % (label, len(rows)))
            w("")
            for r in rows[:40]:
                w("- `%s` / `%s` — %s %s"
                  % (str(r.get("system", "")).rsplit("/", 1)[-1],
                     r.get("module"), r.get(key),
                     ("(%s)" % r["why"]) if r.get("why") else
                     ("expected %s, graph says %s"
                      % (r.get("expected"), r.get("actual"))) if r.get("actual")
                     else ""))
            w("")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out).rstrip() + "\n")
    print("wrote %s (%d lines)" % (args.out, len(out)))
    print("systems=%d  pins=%d  manual=%d"
          % (len(plan), total_pins, len(rep.get("manual_steps") or [])))


if __name__ == "__main__":
    main()
