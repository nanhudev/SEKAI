"""Generate docs/SWORD_VISUAL_PROFILE.md from the profile spec + the build report.

    python tools/gen_profile_doc.py

Two sources, deliberately:

    source/sword_visual_profile.json   what the profiles ARE (authored)
    exports/p11_report.json            what the systems really have (measured)

The second one is why this is generated rather than written. A hand-written
profile document drifts the moment a pin is retyped in the graph, and the drift
is invisible - the document keeps describing a parameter that the system no
longer exposes. Reading the built systems back is the only way the "parameter
namespace" section can be trusted.

The document also DERIVES one claim rather than asserting it: which core systems
are currently hard-wired to a _Normal material instance. That matters because a
system whose renderer names a single material instance cannot serve both swords,
and the brief's section 5 ("only the VFX profile swaps") is not satisfiable while
that is true. Deriving it means the document cannot quietly go stale after the
graph is fixed.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SPEC = os.path.join(ROOT, "source", "sword_visual_profile.json")
REPORT = os.path.join(ROOT, "exports", "p11_report.json")
OUT = os.path.join(ROOT, "docs", "SWORD_VISUAL_PROFILE.md")


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def renderer_materials(plan):
    """system name -> sorted list of material instance names on its renderers."""
    out = {}
    for sysd in plan:
        name = sysd.get("name")
        mats = set()
        for em in sysd.get("emitters", []):
            for r in em.get("renderers", []):
                m = r.get("material")
                if m:
                    mats.add(str(m).split(".")[-1])
        out[name] = sorted(mats)
    return out


def main():
    spec = load(SPEC)
    report = load(REPORT)
    profiles = spec["profiles"]
    slot_map = spec["slot_map"]
    slot_notes = spec.get("slot_notes", {})
    mats = renderer_materials(report.get("plan", []))

    slots = [k for k in slot_map if not k.startswith("_")]

    L = []
    A = L.append

    A("# SWORD VISUAL PROFILE - specification and current status")
    A("")
    A("> **GENERATED** by `tools/gen_profile_doc.py` from "
      "`source/sword_visual_profile.json` and `exports/p11_report.json`.")
    A("> Do not hand-edit: change the spec and regenerate, or the two will "
      "disagree and the disagreement will not be visible.")
    A("")
    A("Batch: **SWORD PRESENTATION V3 + MAGIC SWORD VFX V1**. "
      "Folder: `/Game/SEKAI/VFX/Sword/`.")
    A("")

    # ---------------------------------------------------------------- rule
    A("## 1. The rule this document exists to enforce")
    A("")
    A("> " + spec["profile_rule"])
    A("")
    A("A profile is **only** a set of slot bindings: which core system realises "
      "the slot, which material instance it wears, and the `User.*` values that "
      "drive it. It owns no animation, no timing and no geometry of its own.")
    A("")
    A("Timing never lives here. It arrives as events from the Sword line - see "
      "`docs/sword_vfx_event_contract.json`, which is generated from the Godot "
      "source of truth. A profile that appears to know about time is a bug.")
    A("")

    # ------------------------------------------------------------ namespace
    A("## 2. The parameter namespace (what a profile may change)")
    A("")
    A("Read back from the nine built systems, not copied from a plan - so a "
      "parameter listed here is one the graph really exposes.")
    A("")
    A("| # | Parameter | Type | Purpose |")
    A("|---|-----------|------|---------|")
    ups = report.get("user_params", [])
    for i, p in enumerate(ups, 1):
        t = str(p.get("type", "")).split(".")[-1]
        A("| %d | `%s` | `%s` | %s |"
          % (i, p.get("name"), t, p.get("description", "")))
    A("")
    A("`User.DarkColor`, `User.ArcStart`, `User.ArcEnd`, `User.ScaleVector`, "
      "`User.Velocity`, `User.MistCount` and `User.MistRate` are documented "
      "extensions beyond the brief's section 24 list. `ArcStart`/`ArcEnd` exist "
      "so a 300-degree arc cannot silently close into a 360-degree ring; "
      "`ScaleVector` and `Velocity` exist because `ScaleMeshSize.Scale Factor` "
      "and `SolveForcesAndVelocity.Velocity` are `Vector3f`, not `float`, and "
      "linking a float into them makes the compiler repair the graph.")
    A("")

    # ------------------------------------------------------------- slots
    A("## 3. Slot map (shared by both swords)")
    A("")
    A("Changing this map changes **both** swords. That is why it is not inside "
      "either profile.")
    A("")
    A("| Slot | Realised by | What it is for |")
    A("|------|-------------|----------------|")
    for s in slots:
        A("| `%s` | %s | %s |"
          % (s,
             ", ".join("`%s`" % x for x in slot_map[s]),
             slot_notes.get(s, "")))
    A("")

    # ----------------------------------------------------------- profiles
    for i, (pname, prof) in enumerate(profiles.items(), start=4):
        A("## %d. `%s`" % (i, pname))
        A("")
        A("**Identity:** " + ", ".join(prof["identity"]))
        A("")
        A("**Keywords:** " + ", ".join(prof["keywords"]))
        A("")
        if prof.get("implies"):
            A("> " + prof["implies"])
            A("")
        A("| Slot | System | Material instance | Profile values |")
        A("|------|--------|-------------------|----------------|")
        for s in slots:
            cfg = prof["slots"].get(s)
            if not cfg:
                A("| `%s` | *not bound* | - | - |" % s)
                continue
            params = cfg.get("params", {})
            pv = ", ".join("`%s`=%s" % (k, v) for k, v in params.items()) or "-"
            A("| `%s` | `%s` | `%s` | %s |"
              % (s, cfg.get("system", "-"), cfg.get("mi", "-"), pv))
        A("")
        A("Per-slot reasoning:")
        A("")
        for s in slots:
            cfg = prof["slots"].get(s)
            if cfg and cfg.get("why"):
                A("- **`%s`** - %s" % (s, cfg["why"]))
        A("")
        A("")

    # -------------------------------------------------- slot binding check
    A("## 6. Slot-binding check (derived, not declared)")
    A("")
    A("Every slot above names a material instance. This section checks that "
      "claim against the material actually sitting on that system's renderers, "
      "and sorts the result into three kinds - because lumping them together "
      "would drown a real error in a known gap:")
    A("")
    A("- **exact** - the instance the slot names is on the system right now.")
    A("- **blocked** - the slot names the *other* profile's instance (same "
      "material family, only the `_Normal`/`_Magic` suffix differs). Correct as "
      "written, but undeliverable until the section 7 fix lands: the system "
      "carries one instance and cannot wear both.")
    A("- **mismatch** - a different material family entirely. That is a real "
      "disagreement between this spec and the built system, and this check has "
      "already found one: the A1 slice was documented as wearing the trail "
      "material while the built system wears the scar material, because the "
      "slice is a drawn-on strip mesh, not a ribbon.")
    A("")

    def family(mi):
        """MI_SW_Mote_Magic -> MI_SW_Mote, i.e. which core material this is."""
        for suf in ("_Normal", "_Magic"):
            if mi.endswith(suf):
                return mi[: -len(suf)]
        return mi

    exact, blocked, mismatch = [], [], []
    total = 0
    for pname, prof in profiles.items():
        for s in slots:
            cfg = prof["slots"].get(s)
            if not cfg:
                continue
            total += 1
            sysname = cfg.get("system")
            mi = cfg.get("mi")
            actual = mats.get(sysname) or []
            if mi in actual:
                exact.append((pname, s, sysname, mi))
            elif family(mi) in {family(a) for a in actual}:
                blocked.append((pname, s, sysname, mi, actual))
            else:
                mismatch.append((pname, s, sysname, mi, actual))

    A("| Result | Slots |")
    A("|--------|-------|")
    A("| exact | **%d** / %d |" % (len(exact), total))
    A("| blocked by the section 7 gap | **%d** / %d |"
      % (len(blocked), total))
    A("| mismatch - spec disagrees with the build | **%d** / %d |"
      % (len(mismatch), total))
    A("")
    if mismatch:
        A("Mismatches, which are the ones worth acting on:")
        A("")
        A("| Profile | Slot | System | Declared | System actually wears |")
        A("|---------|------|--------|----------|-----------------------|")
        for pname, s, sysname, mi, actual in mismatch:
            A("| `%s` | `%s` | `%s` | `%s` | %s |"
              % (pname, s, sysname, mi,
                 ", ".join("`%s`" % m for m in actual) or "-"))
        A("")
        hits = sorted({s for _, s, _, _, _ in mismatch if s.startswith("Hit")})
        if hits:
            A("The **%s** family is a different kind of failure from the rest "
              "and is worth separating: `NS_SW_Core_Hit` has a single renderer, "
              "so it cannot wear four different instances at once no matter what "
              "the profile says. Either the hit core gets one renderer per "
              "substrate, or the four slots share one instance and the "
              "substrate difference lives in `User.*` alone. That is a design "
              "decision, not a typo, and it is left visible rather than quietly "
              "resolved in the spec." % ", ".join("`%s`" % h for h in hits))
            A("")
    if blocked:
        A("Blocked slots are `%d` of `%d` and are all the same sentence: the "
          "profile asks for the other sword's material and the graph has not "
          "been parameterised yet. They are listed here as a count rather than "
          "a table because the remedy is one change - `User.Material` on the "
          "renderers - not %d edits."
          % (len(blocked), total, len(blocked)))
        A("")
    A("")

    # ---------------------------------------------------------------- gap
    A("## 7. Shared vs different (the honest accounting)")
    A("")
    A("Shared, and this is not a compromise:")
    A("")
    A("- **Animation.** Every beat is the same beat. Magic does not get a "
      "second Iaido, a second A3, or a longer A4.")
    A("- **The Sword Move.** Magic calls the same move through the same "
      "controller. `MagicSwordAttackA1()` / `MagicSwordAttackA2()` are "
      "forbidden - brief section 5.")
    A("- **The nine core systems.** One graph each, composited through "
      "`User.*`. Section 23 forbids a second set for Magic.")
    A("- **Geometry.** A2's sheet, A3's three scar traces and A4's arc are the "
      "same shapes. Section 17-21 require this explicitly.")
    A("")
    A("Different, and this is the entire observable difference between the two "
      "swords:")
    A("")
    A("- **The material instance** worn by each renderer.")
    A("- **The `User.*` values**, chiefly the four colours "
      "(`PrimaryColor` / `CoreColor` / `MistColor` / `DarkColor`) and "
      "`MistAmount`.")
    A("")
    A("### Known gap: the renderer material is currently hard-wired")
    A("")
    A("Derived from the build report, not asserted. A core system whose "
      "renderers name one material instance cannot serve both swords, so while "
      "this holds, Magic needs a second copy of the graph and section 5 is not "
      "satisfiable.")
    A("")
    A("| System | Material on its renderers | Serves both? |")
    A("|--------|---------------------------|--------------|")
    hard = []
    for name in sorted(mats):
        ml = mats[name]
        both = len({m.split("_")[-1] for m in ml}) > 1
        if not both:
            hard.append(name)
        A("| `%s` | %s | %s |"
          % (name, ", ".join("`%s`" % m for m in ml) or "-",
             "yes" if both else "**no - one instance only**"))
    A("")
    A("**%d of %d** systems are single-instance." % (len(hard), len(mats)))
    A("")
    A("**Fix (design, `SPEC READY`):** drive the renderer material from a "
      "`User.Material` parameter of type `MaterialInterface`, and let the "
      "profile assign `MI_SW_*_Normal` or `MI_SW_*_Magic`. Then the profile "
      "swap is literally one parameter write, no duplicate graph exists, and "
      "the table above becomes yes / yes / yes.")
    A("")
    A("Until that lands, the two material instances per core are both built and "
      "present, so the visual comparison this batch is for can still be done by "
      "swapping the material on the renderer by hand - marked below as a "
      "`MANUAL EDITOR STEP`. Both statements are true at once and neither is "
      "hidden.")
    A("")

    # ------------------------------------------------------------ status
    A("## 8. Status")
    A("")
    A("| Item | State | Evidence |")
    A("|------|-------|----------|")
    A("| Profile spec (15 brief slots, 2 profiles) | `SPEC READY` | "
      "`source/sword_visual_profile.json` |")
    A("| 24 user parameters on the built systems | `ASSET READY` | "
      "`exports/p11_report.json` |")
    A("| 9 core systems | `IMPLEMENTED` | 9/9 built, 49 pins linked, saved 9/9 |")
    A("| 12 material instances (Normal + Magic) | `ASSET READY` | "
      "`exports/p10_assets.txt` |")
    A("| Renderer material parameterised (`User.Material`) | `SPEC READY` | "
      "gap in section 7 |")
    A("| Profile as a UE Data Asset | *not built* | needs a `UDataAsset` "
      "subclass; see section 9 |")
    A("| Visual profile verified in engine | *not verified* | requires looking "
      "at a render |")
    A("")
    A("Per brief section 35, nothing on this page is `VISUALLY VERIFIED` yet. "
      "`IMPLEMENTED` means the graph exists and runs, not that it looks right.")
    A("")

    A("## 9. Why there is no `DA_SwordVisualProfile` asset yet")
    A("")
    A("A UE Data Asset needs a `UDataAsset` subclass with `UPROPERTY` fields. "
      "This project is Blueprint-only - there is no `Source/` module - and "
      "neither a `USTRUCT` nor a `UCLASS` can be declared from Python. Checked "
      "against the engine:")
    A("")
    A("- `unreal.DataAssetFactory` is present, but it takes a `DataAssetClass` "
      "(`TSubclassOf<UDataAsset>`) and no engine subclass has these fields.")
    A("- `unreal.UserDefinedStructFactory` and `unreal.PrimaryDataAssetFactory` "
      "are **not exposed to Python** in 5.8.3 - probed, not assumed.")
    A("")
    A("So the profile ships as a versioned, machine-readable spec plus this "
      "generated document, which is what the VFX and gameplay code can actually "
      "read today. Turning it into a real Data Asset is either a one-file C++ "
      "module or a short editor session, and is marked accordingly rather than "
      "faked with an empty asset. An empty `DA_SwordVisualProfile` would be "
      "worse than none: it would look like the dependency was resolved.")
    A("")

    text = "\n".join(L) + "\n"
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)

    print("wrote %s" % OUT)
    print("  profiles          : %d" % len(profiles))
    print("  slots             : %d" % len(slots))
    print("  user params       : %d" % len(ups))
    print("  slot bindings     : %d exact, %d blocked, %d mismatch"
          % (len(exact), len(blocked), len(mismatch)))
    for pname, s, sysname, mi, actual in mismatch:
        print("      MISMATCH %s %s: spec %s vs build %s"
              % (pname, s, mi, ", ".join(actual) or "-"))
    print("  systems single-MI : %d / %d" % (len(hard), len(mats)))
    for h in hard:
        print("      %s -> %s" % (h, ", ".join(mats[h])))


if __name__ == "__main__":
    main()
