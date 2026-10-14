"""
p45_pie_true.py - the game world, enumerated CORRECTLY this time.

WHY p40 AND p41's GAME-WORLD RESULT IS VOID
    p40's `state_of(world, tag)` took a world argument and then ignored it:

        actors = unreal.EditorLevelLibrary.get_all_level_actors()

    `get_all_level_actors()` is an EDITOR-only call. It returns the actors of
    the world the editor is authoring in, regardless of which world you hand it.
    So when p40 printed

        [editor] niagara actors=9  active=0  tick_enabled=2
        [game]   niagara actors=0  active=0  tick_enabled=0

    the second line is not "the game world has no actors". It is "the game
    world has no actors *that this editor-only call can see*", and the honest
    reading is that the game world was never enumerated at all.

    p41 then drew a conclusion from exactly that hole - "in the game world a
    forced activate(True) still gives before=False after=False, nine for nine"
    - and the nine components it forced were the editor world's, because that
    is the only set the enumeration can return. The game world has never been
    tested. This re-tests it, and this time the test says out loud which world
    each actor belongs to.

THE DISCRIMINATOR
    Both worlds are named L_SwordVFX_Lab. `get_name()` cannot tell them apart;
    `get_path_name()` can, because the PIE world carries a UEDPIE_0_ prefix.
    Every actor row below prints its path for that reason.

THE ENUMERATION
    GameplayStatics.get_all_actors_of_class(world_context, actor_class) - the
    one world-aware enumeration this build actually has. p41's API dump lists
    it (GameplayStatics, 170 members). p40 used `spawn_actor_from_class` on
    GameplayStatics and found it missing, then assumed the whole class was
    crippled; it is not, it just has no spawn. Enumerating was available the
    whole time.

WHAT IT MEASURES
    1. the editor world's nine components - active / tick-enabled / path
    2. enter simulate
    3. the GAME world's components, by world-aware enumeration, with paths
    4. get_world_delta_seconds on both worlds (p38/p39 looked for
       SystemLibrary.get_world_delta_time, which does not exist, so "is the
       world advancing" has never been answered)
    5. force activate(True) on the GAME world's components and re-read
    6. shoot both worlds from the same pose and export both frames

OUTPUT
    render/pie/_p45_editor.png
    render/pie/_p45_game.png
    exports/p45_pie_true.txt

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p45_pie_true.py --render
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p45_pie_true.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/pie')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"

WIDTH = 1280
HEIGHT = 720

# 3 m in front of Lab_FX_EdgeTrail, the ribbon emitter. Same pose in both
# worlds so the only variable is which world is being looked at.
EDGE = "Lab_FX_EdgeTrail"
CAM = unreal.Vector(1200.0, -1200.0, 150.0)
CAM_ROT = unreal.Rotator(pitch=0.0, yaw=180.0, roll=0.0)

SETTLE_TICKS = 45
PIE_TICKS = 90
PIE_EXTRA_TICKS = 45
BUDGET_SECONDS = 600.0

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


# ---------------------------------------------------------------- world lookup
def _call(holder, name):
    try:
        obj = getattr(unreal, holder)()
        return getattr(obj, name)()
    except Exception:
        return None


def editor_world():
    for holder in ("UnrealEditorSubsystem", "EditorLevelLibrary"):
        w = _call(holder, "get_editor_world")
        if w is not None:
            return w
    return None


def game_world():
    for holder in ("UnrealEditorSubsystem", "EditorLevelLibrary"):
        w = _call(holder, "get_game_world")
        if w is not None:
            return w
    return None


def unpack(result):
    """UE python returns out-params as a tuple when there is more than one.

    GetAllActorsOfClass is void + one out-param, and whether that arrives as
    the array or as a 1-tuple of the array is not worth guessing: try both and
    say which shape came back.
    """
    if result is None:
        return [], "None"
    if isinstance(result, tuple):
        for x in result:
            if isinstance(x, (list, tuple)) or type(x).__name__ == "Array":
                return list(x), "tuple[%d]->array" % len(result)
        return [], "tuple[%d] with no array" % len(result)
    if isinstance(result, (list, tuple)) or type(result).__name__ == "Array":
        return list(result), "array"
    return [result], "scalar(%s)" % type(result).__name__


def actors_of_class(world, cls):
    if world is None:
        return [], "no world"
    try:
        raw = unreal.GameplayStatics.get_all_actors_of_class(world, cls)
    except Exception as exc:
        return [], "<%s>" % str(exc)[:80]
    return unpack(raw)


# ---------------------------------------------------------------- diagnostics
log("")
log("=" * 74)
log("PART A - the exact signature of the three calls that mattered")
log("=" * 74)
for owner, fname in (("GameplayStatics", "get_all_actors_of_class"),
                     ("GameplayStatics", "get_world_delta_seconds"),
                     ("AutomationLibrary", "take_high_res_screenshot")):
    fn = getattr(getattr(unreal, owner, None), fname, None)
    doc = (getattr(fn, "__doc__", "") or "").strip().splitlines()
    log("")
    log("  %s.%s" % (owner, fname))
    if fn is None:
        log("    NOT PRESENT")
        continue
    for line in doc[:8]:
        log("    %s" % line.strip()[:150])


# ---------------------------------------------------------------- load
loaded = False
for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
    try:
        getattr(unreal, how)().load_level(LVL)
        log("")
        log("level loaded via %s" % how)
        loaded = True
        break
    except Exception as exc:
        log("  %s failed: %s" % (how, str(exc)[:120]))
if not loaded:
    log("ABORT: no level")
    raise SystemExit(0)


EW = editor_world()
GW0 = game_world()
log("")
log("editor world path: %s" % (EW.get_path_name() if EW else "None"))
log("game   world path: %s" % (GW0.get_path_name() if GW0 else "None"))


def world_clock(world):
    try:
        return unreal.GameplayStatics.get_world_delta_seconds(world)
    except Exception as exc:
        return "<%s>" % str(exc)[:60]


def survey(world, tag, verbose=True):
    """Niagara components in ONE WORLD, with the world they are in spelled out.

    The path is printed because both worlds are called L_SwordVFX_Lab and a
    count without a path cannot prove which one was counted. Rows whose path
    has no UEDPIE_ prefix came from the editor world and are labelled as such,
    so a mis-enumerated row announces itself instead of joining the total.
    """
    actors, how = actors_of_class(world, unreal.NiagaraActor)
    rows = []
    for a in actors:
        try:
            comp = a.get_component_by_class(unreal.NiagaraComponent)
            if comp is None:
                continue
            path = a.get_path_name()
            rows.append({
                "label": a.get_actor_label(),
                "path": path,
                "pie": "UEDPIE" in path,
                "active": comp.is_active(),
                "tick": comp.is_component_tick_enabled(),
                "auto": comp.get_editor_property("auto_activate"),
            })
        except Exception:
            continue
    in_pie = sum(1 for r in rows if r["pie"])
    n_act = sum(1 for r in rows if r["active"])
    n_tick = sum(1 for r in rows if r["tick"])
    log("")
    log("  [%-14s] world=%s  via %s" % (tag, world.get_name() if world else "-", how))
    log("  %-16s %5s %6s %5s %5s  %s"
        % ("label", "active", "tick", "auto", "PIE", "path"))
    for r in rows:
        log("  %-16s %5s %6s %5s %5s  %s"
            % (r["label"], r["active"], r["tick"], r["auto"],
               "yes" if r["pie"] else "no", r["path"][-58:]))
    log("  -> %d actors · %d active · %d tick-enabled · %d from a PIE world"
        % (len(rows), n_act, n_tick, in_pie))
    if verbose and rows and in_pie == 0 and tag == "game":
        log("  !! NONE of these came from a PIE world. The enumeration did not")
        log("     reach the game world, so nothing below about it is measured.")
    return rows


log("")
log("=" * 74)
log("PART B - what each world says about its own components")
log("=" * 74)
log("world delta seconds  editor=%s  game=%s" % (world_clock(EW), world_clock(GW0)))
ED_ROWS = survey(EW, "editor")


# ---------------------------------------------------------------- capture
def existing_capture(world):
    actors, how = actors_of_class(world, unreal.SceneCapture2D)
    return (actors[0] if actors else None), "%s -> %d" % (how, len(actors))


def aim_capture(cap, loc, rot, tag):
    cc = cap.capture_component2d
    try:
        cc.set_editor_property("capture_every_frame", False)
    except Exception:
        pass
    v = getattr(unreal.SceneCaptureSource, "SCS_FINAL_COLOR_LDR", None)
    if v is not None:
        try:
            cc.set_editor_property("capture_source", v)
        except Exception:
            pass
    ok, why = swcap.place_capture(cc, cap, loc, rot, loc_tol=5.0, rot_tol=5.0)
    cl = cap.get_actor_location()
    log("    %s: placed=%s  at (%.0f, %.0f, %.0f)  via %s"
        % (tag, ok, cl.x, cl.y, cl.z, str(why)[:60]))
    return cc, ok


log("")
log("--- editor-world capture (the one p40 already proved can be placed) ---")
ERT = swcap.make_rt(EW, WIDTH, HEIGHT)
ECAP, how = existing_capture(EW)
if ECAP is None:
    log("  ABORT: no SceneCapture2D in the editor world")
    raise SystemExit(0)
log("  found: %s  (%s)" % (ECAP.get_actor_label(), how))
try:
    ECAP.capture_component2d.set_editor_property("texture_target", ERT)
except Exception as exc:
    log("  texture_target: %s" % str(exc)[:90])
ECC, _ = aim_capture(ECAP, CAM, CAM_ROT, "editor")

ST = {"handle": None, "started": time.time(), "ticks": 0, "phase": "settle",
      "wait": SETTLE_TICKS, "errors": 0, "lums": {}, "entered": None,
      "gw": None, "rt": None, "cc": None, "forced": None}


def shoot(world, rt, cc):
    swcap.clear_rt(world, rt)
    try:
        cc.capture_scene()
    except Exception as exc:
        log("    capture_scene raised: %s" % str(exc)[:110])


def export(world, rt, name):
    swcap.export_rt(world, rt, OUT_DIR, name)
    got = swimg.collect(OUT_DIR, name)
    st = swimg.png_stats(got) if got else None
    if st and st["mean_luma"] is not None:
        log("    %-16s luma=%.2f distinct=%s top=%s %.1f%%"
            % (name, st["mean_luma"], st["distinct_rgb"], st["top_rgb"],
               100.0 * st["top_rgb_frac"]))
        return st["mean_luma"]
    log("    %-16s NO FILE" % name)
    return None


def _finish(reason):
    if ST["phase"] == "done":
        return
    ST["phase"] = "done"
    log("")
    log("=" * 74)
    log("SUMMARY")
    log("=" * 74)
    log("stop reason : %s" % reason)
    log("elapsed     : %.1f s over %d ticks" % (time.time() - ST["started"],
                                                ST["ticks"]))
    log("PIE entered via: %s" % ST["entered"])
    log("tick errors : %d" % ST["errors"])
    log("")
    log("editor-world luma : %s" % ST["lums"].get("_p45_editor"))
    log("game-world  luma  : %s" % ST["lums"].get("_p45_game"))
    g = ST["forced"]
    log("")
    if g is None:
        log("=> THE GAME WORLD WAS NEVER ENUMERATED. Nothing about it was")
        log("   measured, and no conclusion may be drawn from this run.")
    else:
        n, act = g
        log("=> GAME WORLD: %d niagara actors found, %d active after a forced"
            % (n, act))
        log("   activate(True).")
        if n == 0:
            log("   Still zero - the world-aware call did not see them either.")
            log("   That is a fact about PIE actor duplication, not about the graph.")
        elif act > 0:
            log("   THE COMPONENT LIVES IN A GAME WORLD. This is the first time")
            log("   any of the nine has been measured running. Read the frames:")
            log("   if the game frame differs from the editor frame, the VFX")
            log("   pipeline is unblocked and the review frames can be shot here.")
        else:
            log("   Found but not active even after activate(True), in a game")
            log("   world, with the enumeration proven to reach it. That clears")
            log("   the session type and the world type together, and points at")
            log("   the system asset itself.")
    log("P45 DONE")
    try:
        if ST["handle"] is not None:
            unreal.unregister_slate_post_tick_callback(ST["handle"])
    except Exception:
        pass
    try:
        end = getattr(unreal.EditorLevelLibrary, "editor_request_end_play", None)
        if end is not None:
            end()
    except Exception:
        pass
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception as exc:
        log("quit_editor failed: %s" % str(exc)[:120])


def _enter_pie():
    for holder, name in (("LevelEditorSubsystem", "editor_play_simulate"),
                         ("EditorLevelLibrary", "editor_play_simulate")):
        try:
            getattr(getattr(unreal, holder)(), name)()
            return "%s.%s" % (holder, name)
        except Exception as exc:
            log("    %s.%s failed: %s" % (holder, name, str(exc)[:80]))
    return None


def tick(delta):
    st = ST
    if st["phase"] == "done":
        return
    st["ticks"] += 1
    if time.time() - st["started"] > BUDGET_SECONDS:
        _finish("budget exhausted")
        return
    try:
        if st["phase"] == "settle":
            st["wait"] -= 1
            if st["wait"] <= 0:
                log("")
                log("--- shot 1: EDITOR world, 3 m from %s ---" % EDGE)
                shoot(EW, ERT, ECC)
                st["wait"] = 2
                st["phase"] = "exp_e"
            return

        if st["phase"] == "exp_e":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            st["lums"]["_p45_editor"] = export(EW, ERT, "_p45_editor")
            log("")
            log("--- entering simulate ---")
            st["entered"] = _enter_pie()
            log("    _enter_pie -> %s" % st["entered"])
            st["wait"] = PIE_TICKS
            st["phase"] = "pie_wait"
            return

        if st["phase"] == "pie_wait":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            gw = game_world()
            log("")
            log("=" * 74)
            log("PART C - the game world, by world-aware enumeration")
            log("=" * 74)
            log("game world path: %s" % (gw.get_path_name() if gw else "None"))
            log("world delta seconds  editor=%s  game=%s"
                % (world_clock(EW), world_clock(gw)))
            if gw is None:
                _finish("no game world after simulate")
                return
            st["gw"] = gw
            survey(gw, "game")

            # A capture that exists in the game world. PIE duplicates the level,
            # so the editor-world capture should be here too - and if it is, its
            # component is the same one p38 measured as tick-enabled.
            cap, how = existing_capture(gw)
            if cap is None:
                log("")
                log("  no SceneCapture2D in the game world (%s). PIE did not")
                log("  duplicate the capture, so there is nothing to shoot with")
                log("  and the frame comparison cannot be made." % how)
                _finish("no capture in the game world")
                return
            log("")
            log("  capture in the game world: %s" % cap.get_actor_label())
            st["rt"] = swcap.make_rt(gw, WIDTH, HEIGHT)
            try:
                cap.capture_component2d.set_editor_property(
                    "texture_target", st["rt"])
            except Exception as exc:
                log("  texture_target: %s" % str(exc)[:90])
            st["cc"], _ = aim_capture(cap, CAM, CAM_ROT, "game")
            st["wait"] = PIE_EXTRA_TICKS
            st["phase"] = "pie_run"
            return

        if st["phase"] == "pie_run":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            gw = st["gw"]
            log("")
            log("--- forcing activate(True) on the GAME world's own components ---")
            actors, how = actors_of_class(gw, unreal.NiagaraActor)
            before = after = 0
            for a in actors:
                try:
                    comp = a.get_component_by_class(unreal.NiagaraComponent)
                    if comp is None or "UEDPIE" not in a.get_path_name():
                        continue
                    before += 1 if comp.is_active() else 0
                    comp.activate(True)
                    after += 1 if comp.is_active() else 0
                except Exception:
                    continue
            log("    %d PIE components: %d active before, %d after activate(True)"
                % (before, before, after))
            st["forced"] = (len(actors), after)
            st["wait"] = 30
            st["phase"] = "let_run"
            return

        if st["phase"] == "let_run":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            log("")
            log("--- shot 2: GAME world, same pose, 30 ticks after the force ---")
            shoot(st["gw"], st["rt"], st["cc"])
            st["wait"] = 2
            st["phase"] = "exp_g"
            return

        if st["phase"] == "exp_g":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            st["lums"]["_p45_game"] = export(st["gw"], st["rt"], "_p45_game")
            survey(st["gw"], "game (at shot)", verbose=False)
            _finish("both frames taken")
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:160]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 20:
            _finish("too many tick errors")


log("")
log("--- settle %d ticks ---" % SETTLE_TICKS)
ST["handle"] = unreal.register_slate_post_tick_callback(tick)
