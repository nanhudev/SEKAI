"""
p47_stock_control.py - is it OUR build, or can this session not run ANY Niagara?

WHY THIS IS THE RIGHT NEXT QUESTION
    p46 cleared the session type and the world type:

        game world /Game/.../UEDPIE_0_L_SwordVFX_Lab
        9 PIE rows, 9 in a PIE world, activate(True) -> before=0 after=0
        _p46_game luma = 102.21387833723654 = _p46_editor, to the last digit

    and the engine log from that same session says the compiles DID run:

        LogNiagara: Compiling System ...NS_SW_Core_EdgeTrail took 6.7341 s   (x9)

    So the systems compile and the components still never come up. There are
    exactly two families of cause left, and they need different work:

        (a) the nine ASSETS are wrong - something in how p11 built them
        (b) this session cannot bring up a Niagara component AT ALL

    Every argument about which one it is has been an argument about an asset
    nobody has ever seen run. The control is trivial and has never been run:
    put a STOCK, never-touched engine system through the identical code path, in
    the same session, and see whether IT comes up.
        stock runs, ours does not  -> (a), and the fix is in the build
        neither runs               -> (b), and no rebuild can help

WHAT ELSE IS MEASURED HERE, AND IT SHOULD HAVE BEEN MEASURED FIRST
    `comp.get_asset()` - the asset each component actually still points at.
    p11 reported assigning assets and p20 reported assigning them again, and the
    only thing ever read back was `auto_activate`, which is a different property
    on the same component. If a component in the saved level points at nothing,
    then "no asset" and "no particles" look identical from every probe run so
    far, and that is a one-line answer nobody has asked for.

    Asset discovery here uses the ASSET REGISTRY rather than
    `EditorAssetLibrary.list_assets`, because p20 recorded that list_assets took
    the editor down inside this project
        Ensure condition failed: !ModuleGroup.StartNodes.IsEmpty()
        [NiagaraStackGraphUtilities.cpp:906] -> EXCEPTION_ACCESS_VIOLATION
    The registry reads metadata without loading assets, which is both faster and
    the reason it cannot trigger a Niagara stack build.

OUTPUT
    render/pie/_p47_stock.png
    render/pie/_p47_ours.png
    exports/p47_control.txt

Usage:
    cd sword_vfx/scripts && UE_TIMEOUT=280 ./run_ue.sh p47_stock_control.py --render
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swcap  # noqa: E402
import swimg  # noqa: E402
import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p47_control.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/pie')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
SYS_DIR = "/Game/SEKAI/VFX/Sword/Systems"

WIDTH = 1280
HEIGHT = 720

CAM = unreal.Vector(1200.0, -1200.0, 150.0)
CAM_ROT = unreal.Rotator(pitch=0.0, yaw=180.0, roll=0.0)

OURS = "NS_SW_Core_EdgeTrail"
OURS_LOC = unreal.Vector(900.0, -1200.0, 150.0)

BUDGET_SECONDS = 210.0

WFX.bind_log(EXPORT)
log = WFX.log

os.makedirs(OUT_DIR, exist_ok=True)
if os.path.isdir(OUT_DIR):
    for _f in os.listdir(OUT_DIR):
        try:
            os.remove(os.path.join(OUT_DIR, _f))
        except Exception:
            pass

log("engine: %s" % unreal.SystemLibrary.get_engine_version())

ST = {"handle": None, "started": time.time(), "ticks": 0, "phase": "boot",
      "wait": 0, "errors": 0, "lums": {}, "notes": [], "ew": None, "ert": None,
      "ecc": None, "stock": None, "stock_sys": None, "stock_act": None,
      "ours_act": None, "our_assets": []}

WFX.install_watchdog(grace_seconds=BUDGET_SECONDS + 20.0)


def _call(holder, name):
    try:
        return getattr(getattr(unreal, holder)(), name)()
    except Exception:
        return None


def actors_of_class(world, cls):
    if world is None:
        return []
    try:
        raw = unreal.GameplayStatics.get_all_actors_of_class(world, cls)
    except Exception as exc:
        log("    get_all_actors_of_class raised: %s" % str(exc)[:90])
        return []
    if isinstance(raw, tuple):
        for x in raw:
            if isinstance(x, (list, tuple)) or type(x).__name__ == "Array":
                return list(x)
        return []
    if raw is None:
        return []
    if isinstance(raw, (list, tuple)) or type(raw).__name__ == "Array":
        return list(raw)
    return [raw]


def asset_path_of(comp):
    """What the component actually points at. Two accessors, both logged."""
    out = {}
    for name in ("get_asset", "get_fx_system_asset"):
        fn = getattr(comp, name, None)
        if fn is None:
            out[name] = "<no such method>"
            continue
        try:
            a = fn()
            out[name] = a.get_path_name() if a is not None else None
        except Exception as exc:
            out[name] = "<%s>" % str(exc)[:60]
    return out


def spawn_named(world, cls, loc, rot, label):
    for how, fn in (
            ("EditorActorSubsystem",
             lambda: unreal.EditorActorSubsystem().spawn_actor_from_class(
                 cls, loc, rot)),
            ("EditorLevelLibrary",
             lambda: unreal.EditorLevelLibrary.spawn_actor_from_class(
                 cls, loc, rot)),
    ):
        try:
            a = fn()
            if a is None:
                continue
            try:
                a.set_actor_label(label)
            except Exception:
                pass
            return a, how
        except Exception as exc:
            log("    %s failed: %s" % (how, str(exc)[:80]))
    return None, None


def read_comp(comp):
    d = {}
    for name, fn in (("active", lambda: comp.is_active()),
                     ("tick", lambda: comp.is_component_tick_enabled()),
                     ("auto", lambda: comp.get_editor_property("auto_activate"))):
        try:
            d[name] = fn()
        except Exception as exc:
            d[name] = "<%s>" % str(exc)[:40]
    d.update(asset_path_of(comp))
    return d


# --------------------------------------------------------------------------
def boot():
    loaded = False
    for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
        try:
            getattr(unreal, how)().load_level(LVL)
            log("level loaded via %s" % how)
            loaded = True
            break
        except Exception as exc:
            log("  %s failed: %s" % (how, str(exc)[:110]))
    if not loaded:
        ST["notes"].append("no level")
        return

    ST["ew"] = _call("UnrealEditorSubsystem", "get_editor_world") \
        or _call("EditorLevelLibrary", "get_editor_world")
    if ST["ew"] is None:
        ST["notes"].append("no editor world")
        return

    log("")
    log("=" * 74)
    log("PART A - what the nine components in the saved level actually point at")
    log("=" * 74)
    log("  %-22s %-6s %-5s  %s" % ("label", "active", "tick", "get_asset()"))
    n_have = 0
    for a in actors_of_class(ST["ew"], unreal.NiagaraActor):
        try:
            comp = a.get_component_by_class(unreal.NiagaraComponent)
            if comp is None:
                continue
            d = read_comp(comp)
            ap = d.get("get_asset")
            have = bool(ap) and str(ap) not in ("None", "<no such method>")
            n_have += 1 if have else 0
            short = "MISSING" if not have else str(ap).rsplit(".", 1)[-1]
            log("  %-22s %-6s %-5s  %s"
                % (a.get_actor_label(), d["active"], d["tick"], short))
            ST["our_assets"].append((a.get_actor_label(), d))
        except Exception:
            continue
    log("  -> %d of 9 point at a system asset" % n_have)
    if n_have == 0:
        log("  !! NOT ONE COMPONENT HOLDS AN ASSET. A component with no system")
        log("     cannot activate, cannot tick, and draws nothing - and that is")
        log("     indistinguishable, from every probe run so far, from a graph")
        log("     that emits nothing. The whole build question is downstream of")
        log("     this line.")

    # ---------------------------------------------------------------- stock
    log("")
    log("=" * 74)
    log("PART B - a stock engine system to compare against")
    log("=" * 74)
    cands = []
    try:
        reg = unreal.AssetRegistryHelpers.get_asset_registry()
        found = reg.get_assets_by_path("/Niagara", recursive=True) or []
        for ad in found:
            try:
                cls_name = str(ad.asset_class_path.asset_name)
            except Exception:
                cls_name = ""
            if "NiagaraSystem" not in cls_name:
                continue
            cands.append(str(ad.package_name).split(".")[0])
    except Exception as exc:
        log("  AssetRegistry discovery raised: %s" % str(exc)[:120])
    cands = sorted(set(cands))
    log("  %d stock NiagaraSystem assets registered under /Niagara" % len(cands))
    for c in cands[:30]:
        log("    %s" % c)
    if len(cands) > 30:
        log("    ... %d more" % (len(cands) - 30))

    # Prefer something that is obviously a working emitter rather than an
    # abstract template. Keyed on name, and the choice is logged either way.
    def score(p):
        s = 0
        low = p.lower()
        for kw, w in (("fountain", 5), ("simple", 4), ("smoke", 3),
                      ("embers", 2), ("sparks", 2), ("templates", 1)):
            if kw in low:
                s += w
        if "minimal" in low:
            s -= 4
        return s

    picked = None
    for c in sorted(cands, key=lambda p: (-score(p), p)):
        if score(c) <= 0:
            continue
        picked = c
        break
    if picked is None:
        for c in cands:
            if "DefaultSystem" not in c:
                picked = c
                break
    log("  picked: %s" % picked)

    if picked is None:
        ST["notes"].append("no stock system found; control not run")
        return
    stock = unreal.EditorAssetLibrary.load_asset("%s.%s"
                                                 % (picked, picked.rsplit("/", 1)[-1]))
    if stock is None:
        ST["notes"].append("stock system failed to load")
        return
    ST["stock_sys"] = picked
    log("  loaded: %s" % stock.get_path_name())

    a, how = spawn_named(ST["ew"], unreal.NiagaraActor,
                         unreal.Vector(900.0, -1200.0, 150.0), unreal.Rotator(),
                         "P47_Stock")
    if a is None:
        ST["notes"].append("could not spawn the stock actor")
        return
    comp = a.get_component_by_class(unreal.NiagaraComponent)
    try:
        comp.set_asset(stock)
        comp.set_editor_property("auto_activate", True)
    except Exception as exc:
        log("  set_asset raised: %s" % str(exc)[:100])
    ST["stock"] = comp
    log("  stock actor via %s -> %s" % (how, read_comp(comp)))

    # And one of OURS, spawned through the identical path in the SAME session,
    # so the comparison is not across runs or across code.
    ours = unreal.EditorAssetLibrary.load_asset("%s/%s.%s"
                                                % (SYS_DIR, OURS, OURS))
    b, how = spawn_named(ST["ew"], unreal.NiagaraActor,
                         unreal.Vector(900.0, -1500.0, 150.0), unreal.Rotator(),
                         "P47_Ours")
    if b is not None and ours is not None:
        oc = b.get_component_by_class(unreal.NiagaraComponent)
        try:
            oc.set_asset(ours)
            oc.set_editor_property("auto_activate", True)
        except Exception as exc:
            log("  ours set_asset raised: %s" % str(exc)[:100])
        ST["ours"] = oc
        log("  ours  actor via %s -> %s" % (how, read_comp(oc)))
    else:
        ST["notes"].append("could not spawn our own actor for the pairing")

    ST["ert"] = swcap.make_rt(ST["ew"], WIDTH, HEIGHT)
    cap, how = spawn_named(ST["ew"], unreal.SceneCapture2D, CAM, CAM_ROT,
                           "P47_Capture")
    if cap is None:
        ST["notes"].append("no capture")
        return
    try:
        cap.capture_component2d.set_editor_property("texture_target", ST["ert"])
        cap.capture_component2d.set_editor_property(
            "capture_source",
            getattr(unreal.SceneCaptureSource, "SCS_FINAL_COLOR_LDR", None))
        cap.capture_component2d.set_editor_property("capture_every_frame", False)
    except Exception as exc:
        log("  capture props: %s" % str(exc)[:90])
    ST["ecc"] = cap.capture_component2d
    ST["ecap"] = cap


def aim_at(loc):
    """Camera 3 m on +X from the subject, looking -X at it."""
    cam = unreal.Vector(loc.x + 300.0, loc.y, loc.z)
    ok, why = swcap.place_capture(ST["ecc"], ST["ecap"], cam, CAM_ROT,
                                  loc_tol=5.0, rot_tol=5.0)
    return cam, ok


def shoot(name):
    if ST["ert"] is None:
        return
    swcap.clear_rt(ST["ew"], ST["ert"])
    try:
        ST["ecc"].capture_scene()
    except Exception as exc:
        log("    capture_scene raised: %s" % str(exc)[:100])


def export(name):
    swcap.export_rt(ST["ew"], ST["ert"], OUT_DIR, name)
    got = swimg.collect(OUT_DIR, name)
    st = swimg.png_stats(got) if got else None
    if st and st["mean_luma"] is not None:
        log("    %-14s luma=%.2f distinct=%s top=%s %.1f%%"
            % (name, st["mean_luma"], st["distinct_rgb"], st["top_rgb"],
               100.0 * st["top_rgb_frac"]))
        ST["lums"][name] = st["mean_luma"]
        return
    log("    %-14s NO FILE" % name)


def _finish(reason):
    if ST["phase"] == "done":
        return
    ST["phase"] = "done"
    log("")
    log("=" * 74)
    log("SUMMARY")
    log("=" * 74)
    log("stop reason : %s" % reason)
    log("notes       : %s" % ("; ".join(ST["notes"]) if ST["notes"] else "none"))
    log("elapsed     : %.1f s over %d ticks"
        % (time.time() - ST["started"], ST["ticks"]))
    log("tick errors : %d" % ST["errors"])
    log("stock system: %s" % ST["stock_sys"])
    log("")
    log("stock component : %s" % ST["stock_act"])
    log("ours  component : %s" % ST["ours_act"])
    log("")
    log("luma  empty=%s  stock=%s  ours=%s"
        % (ST["lums"].get("_p47_empty"), ST["lums"].get("_p47_stock"),
           ST["lums"].get("_p47_ours")))
    log("")

    sa = (ST["stock_act"] or {}).get("active")
    oa = (ST["ours_act"] or {}).get("active")
    if sa is None or oa is None:
        log("=> THE CONTROL DID NOT RUN. One of the two components was never")
        log("   built, so nothing has been compared and no conclusion follows.")
    elif sa is True and oa is False:
        log("=> STOCK COMES UP AND OURS DOES NOT, through identical code in one")
        log("   session. The session is fine; the nine ASSETS are the defect.")
        log("   That is a build problem with a build fix, and it retires the")
        log("   'needs a human in the editor' answer for the nine cores.")
    elif sa is True and oa is True:
        log("=> BOTH COME UP. Then the components were never the problem, and")
        log("   what p33/p36/p42 measured as 'nothing on screen' must be read as")
        log("   'nothing visible from these cameras' - a framing or scale")
        log("   question, not a wiring one.")
    else:
        log("=> STOCK DOES NOT COME UP EITHER. A system nobody has edited, in")
        log("   the same session, refuses in exactly the same way, so this is")
        log("   not a property of our assets. No rebuild can fix it; the nine")
        log("   frames and the pass01 movie need a real editor session.")
    log("P47 DONE")
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


def tick(delta):
    st = ST
    if st["phase"] == "done":
        return
    st["ticks"] += 1
    if time.time() - st["started"] > BUDGET_SECONDS:
        _finish("budget exhausted")
        return
    try:
        if st["phase"] == "boot":
            boot()
            st["wait"] = 10
            st["phase"] = "settle"
            return

        if st["phase"] == "settle":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            log("")
            log("--- baseline frame: the empty camera pose ---")
            aim_at(unreal.Vector(900.0, -1200.0, 150.0))
            shoot("_p47_empty")
            st["wait"] = 2
            st["phase"] = "exp_empty"
            return

        if st["phase"] == "exp_empty":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            export("_p47_empty")
            log("")
            log("--- STOCK: force activate, then read it back ---")
            if st["stock"] is not None:
                try:
                    st["stock"].activate(True)
                except Exception as exc:
                    log("    stock activate raised: %s" % str(exc)[:90])
                st["stock_act"] = read_comp(st["stock"])
                log("    stock -> %s" % st["stock_act"])
            st["wait"] = 20
            st["phase"] = "stock_run"
            return

        if st["phase"] == "stock_run":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            if st["stock"] is not None:
                st["stock_act"] = read_comp(st["stock"])
                log("    stock after 20 ticks -> %s" % st["stock_act"])
            aim_at(unreal.Vector(900.0, -1200.0, 150.0))
            shoot("_p47_stock")
            st["wait"] = 2
            st["phase"] = "exp_stock"
            return

        if st["phase"] == "exp_stock":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            export("_p47_stock")
            log("")
            log("--- OURS: identical treatment ---")
            if st.get("ours") is not None:
                try:
                    st["ours"].activate(True)
                except Exception as exc:
                    log("    ours activate raised: %s" % str(exc)[:90])
                st["ours_act"] = read_comp(st["ours"])
                log("    ours -> %s" % st["ours_act"])
            st["wait"] = 20
            st["phase"] = "ours_run"
            return

        if st["phase"] == "ours_run":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            if st.get("ours") is not None:
                st["ours_act"] = read_comp(st["ours"])
                log("    ours after 20 ticks -> %s" % st["ours_act"])
            aim_at(unreal.Vector(900.0, -1500.0, 150.0))
            shoot("_p47_ours")
            st["wait"] = 2
            st["phase"] = "exp_ours"
            return

        if st["phase"] == "exp_ours":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            export("_p47_ours")
            _finish("control run complete")
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:160]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 15:
            _finish("too many tick errors")


ST["handle"] = unreal.register_slate_post_tick_callback(tick)
