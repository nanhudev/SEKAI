"""
p46_pie_live.py - the game world, measured properly, and never left hanging.

WHAT p45 GOT RIGHT AND WHERE IT STOPPED
    p45 was the first script to enumerate a world correctly:

        GameplayStatics.get_all_actors_of_class(world_context_object, actor_class)
            -> Array[Actor]

    and it returned all nine components with true paths, which is what makes a
    count provable:

        Lab_FX_EdgeTrail  ... NiagaraActor_0   active=False tick=False auto=True
        Lab_FX_Wave       ... NiagaraActor_3   active=False tick=True  auto=True

    TWO of the nine report tick-enabled and none report active. That is a real
    reading, taken with an instrument known to work.

    It then stopped on its own assumption: it looked for an EXISTING
    SceneCapture2D and there is none, because p40 *spawned* one into a session
    that was never saved. With nothing to shoot with it aborted, and the abort
    is what turned a 30-second probe into a 300-second hang.

WHY AN ABORT HANGS, AND THIS IS A TRAP WORTH KEEPING
    run_ue.sh passes exactly one command:

        -ExecCmds="py <script>"

    There is no trailing `quit_editor`. The script owns the exit. So a
    module-level `raise SystemExit(0)` ends the *python file* and leaves the
    editor running with nothing to do, forever, until the runner's timeout
    kills it. Nothing in the engine log says this happened. From outside it
    looks like the script hung.
    Every exit in this file therefore goes through the tick-driven `_finish`,
    including the failure exits, and the watchdog is armed with a seconds-based
    grace as a second net.

WHAT THIS MEASURES, IN ORDER OF WHAT IT IS WORTH
    1. get_world_delta_seconds on the editor world, then on the game world.
       MEASURED in p45: editor = 0.0. If the game world reports > 0 while the
       editor world reports 0, that is the cleanest possible statement that a
       game world advances and an editor world does not - and it is the
       precondition for anything ticking at all.
    2. whether the nine components come up ON THEIR OWN in the game world.
       auto_activate is True on all nine, so in a world that advances they must
       activate with no help from me. That is the measurement that separates
       "the graph is wrong" from "the world never ran it".
    3. the same enumeration again after a forced activate(True), to see whether
       the state persists in a game world (in the editor world it did not).
    4. a frame from each world, if a capture can be built, because a number
       about is_active() is not the same as pixels.

OUTPUT
    render/pie/_p46_editor.png
    render/pie/_p46_game.png
    exports/p46_pie_live.txt

Usage:
    cd sword_vfx/scripts && UE_TIMEOUT=280 ./run_ue.sh p46_pie_live.py --render
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p46_pie_live.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/pie')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"

WIDTH = 1280
HEIGHT = 720

EDGE = "Lab_FX_EdgeTrail"
CAM = unreal.Vector(1200.0, -1200.0, 150.0)
CAM_ROT = unreal.Rotator(pitch=0.0, yaw=180.0, roll=0.0)

SETTLE_TICKS = 20
PIE_TICKS = 40
RUN_TICKS = 25
BUDGET_SECONDS = 200.0

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
log("")
log("watchdog and finish path are both armed BEFORE anything risky, because")
log("nothing in this file is allowed to exit except the tick-driven _finish.")

ST = {"handle": None, "started": time.time(), "ticks": 0, "phase": "boot",
      "wait": 0, "errors": 0, "lums": {}, "lums_seen": {}, "entered": None,
      "gw": None, "ew": None, "ert": None, "rt": None, "ecc": None, "cc": None,
      "ecap": None, "gcap": None, "notes": [], "survey": {}}

WFX.install_watchdog(grace_seconds=BUDGET_SECONDS + 20.0)


# ---------------------------------------------------------------- world lookup
def _call(holder, name):
    try:
        return getattr(getattr(unreal, holder)(), name)()
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


def actors_of_class(world, cls):
    """The one world-aware enumeration this build has. Returns (list, how)."""
    if world is None:
        return [], "no world"
    try:
        raw = unreal.GameplayStatics.get_all_actors_of_class(world, cls)
    except Exception as exc:
        return [], "<%s>" % str(exc)[:80]
    if isinstance(raw, tuple):
        for x in raw:
            if isinstance(x, (list, tuple)) or type(x).__name__ == "Array":
                return list(x), "tuple->array"
        return [], "tuple, no array"
    if raw is None:
        return [], "None"
    if isinstance(raw, (list, tuple)) or type(raw).__name__ == "Array":
        return list(raw), "array"
    return [raw], "scalar"


def world_clock(world):
    if world is None:
        return None
    try:
        return unreal.GameplayStatics.get_world_delta_seconds(world)
    except Exception:
        return None


def survey(world, tag):
    """Niagara components in ONE world. The path is printed because both
    worlds are called L_SwordVFX_Lab and a bare count cannot prove which one
    was counted; a UEDPIE_ prefix is what makes a row provably a PIE row."""
    actors, how = actors_of_class(world, unreal.NiagaraActor)
    rows = []
    for a in actors:
        try:
            comp = a.get_component_by_class(unreal.NiagaraComponent)
            if comp is None:
                continue
            path = a.get_path_name()
            rows.append({
                "label": a.get_actor_label(), "path": path,
                "pie": "UEDPIE" in path,
                "active": comp.is_active(),
                "tick": comp.is_component_tick_enabled(),
                "auto": comp.get_editor_property("auto_activate"),
            })
        except Exception:
            continue
    n_act = sum(1 for r in rows if r["active"])
    n_tick = sum(1 for r in rows if r["tick"])
    n_pie = sum(1 for r in rows if r["pie"])
    log("")
    log("  [%s] world=%s delta=%s via %s"
        % (tag, world.get_name() if world else "-", world_clock(world), how))
    log("  %-20s %6s %5s %5s %4s  %s"
        % ("label", "active", "tick", "auto", "PIE", "path"))
    for r in rows:
        log("  %-20s %6s %5s %5s %4s  %s"
            % (r["label"], r["active"], r["tick"], r["auto"],
               "yes" if r["pie"] else "no", r["path"][-52:]))
    log("  -> %d actors · %d active · %d tick-enabled · %d in a PIE world"
        % (len(rows), n_act, n_tick, n_pie))
    return {"rows": rows, "n": len(rows), "active": n_act,
            "tick": n_tick, "pie": n_pie}


def spawn_capture_editor(world, loc, rot):
    """p40 proved this is the only spawn that works, and it is editor-only.

    GameplayStatics in this build has 170 members and not one of them spawns an
    actor; EditorActorSubsystem/EditorLevelLibrary take no world argument, so
    they can only reach the world the editor is authoring in. That is why the
    editor-world capture is the one to build: PIE duplicates the level, and if
    the duplicate carries into the game world it is a capture in a live world.
    """
    for label, fn in (
            ("EditorActorSubsystem.spawn_actor_from_class",
             lambda: unreal.EditorActorSubsystem().spawn_actor_from_class(
                 unreal.SceneCapture2D, loc, rot)),
            ("EditorLevelLibrary.spawn_actor_from_class",
             lambda: unreal.EditorLevelLibrary.spawn_actor_from_class(
                 unreal.SceneCapture2D, loc, rot)),
    ):
        try:
            a = fn()
            if a is not None:
                return a, label
        except Exception as exc:
            log("    %s failed: %s" % (label, str(exc)[:90]))
    return None, None


def aim(cap, loc, rot, tag):
    cc = cap.capture_component2d
    for prop, val in (("capture_every_frame", False),
                      ("capture_source",
                       getattr(unreal.SceneCaptureSource,
                               "SCS_FINAL_COLOR_LDR", None))):
        if val is None:
            continue
        try:
            cc.set_editor_property(prop, val)
        except Exception:
            pass
    ok, why = swcap.place_capture(cc, cap, loc, rot, loc_tol=5.0, rot_tol=5.0)
    cl = cap.get_actor_location()
    log("    %s: placed=%s at (%.0f, %.0f, %.0f) %s"
        % (tag, ok, cl.x, cl.y, cl.z, str(why)[:50]))
    return cc


def shoot(world, rt, cc, name):
    if rt is None or cc is None:
        log("    %s: no capture, skipped" % name)
        return
    swcap.clear_rt(world, rt)
    try:
        cc.capture_scene()
    except Exception as exc:
        log("    capture_scene raised: %s" % str(exc)[:110])


def export(world, rt, name):
    if rt is None:
        log("    %-16s NO CAPTURE" % name)
        return
    swcap.export_rt(world, rt, OUT_DIR, name)
    got = swimg.collect(OUT_DIR, name)
    st = swimg.png_stats(got) if got else None
    if st and st["mean_luma"] is not None:
        log("    %-16s luma=%.2f distinct=%s top=%s %.1f%%"
            % (name, st["mean_luma"], st["distinct_rgb"], st["top_rgb"],
               100.0 * st["top_rgb_frac"]))
        ST["lums"][name] = st["mean_luma"]
        return
    log("    %-16s NO FILE" % name)


# --------------------------------------------------------------------------
# boot: everything that can fail happens HERE, and a failure is a note rather
# than an exit, so the tick loop always runs and always owns the quit.
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

    ST["ew"] = editor_world()
    log("")
    log("editor world path: %s"
        % (ST["ew"].get_path_name() if ST["ew"] else "None"))
    log("game   world path: %s"
        % ((game_world().get_path_name()) if game_world() else "None  <- "
           "correct before simulate; PIE has not started"))

    log("")
    log("=" * 74)
    log("PART B - the editor world")
    log("=" * 74)
    ST["survey"]["editor"] = survey(ST["ew"], "editor")

    if ST["ew"] is None:
        ST["notes"].append("no editor world")
        return
    ST["ert"] = swcap.make_rt(ST["ew"], WIDTH, HEIGHT)
    cap, how = spawn_capture_editor(ST["ew"], CAM, CAM_ROT)
    if cap is None:
        ST["notes"].append("editor capture could not be spawned")
        log("  no editor-world capture: %s" % how)
        return
    ST["ecap"] = cap
    log("  capture spawned via %s: %s" % (how, cap.get_actor_label()))
    try:
        cap.capture_component2d.set_editor_property("texture_target", ST["ert"])
    except Exception as exc:
        log("  texture_target: %s" % str(exc)[:90])
    ST["ecc"] = aim(cap, CAM, CAM_ROT, "editor")


def force_activate(world, tag):
    """activate(True) on the components of THAT world, and only those rows."""
    actors, how = actors_of_class(world, unreal.NiagaraActor)
    before = after = 0
    pie_rows = 0
    for a in actors:
        try:
            comp = a.get_component_by_class(unreal.NiagaraComponent)
            if comp is None:
                continue
            if tag == "game" and "UEDPIE" not in a.get_path_name():
                continue
            pie_rows += 1
            if comp.is_active():
                before += 1
            comp.activate(True)
            if comp.is_active():
                after += 1
        except Exception:
            continue
    log("    %s: %d rows touched · active before=%d after=%d"
        % (tag, pie_rows, before, after))
    return pie_rows, before, after


def _finish(reason):
    if ST["phase"] == "done":
        return
    ST["phase"] = "done"
    log("")
    log("=" * 74)
    log("SUMMARY")
    log("=" * 74)
    log("stop reason : %s" % reason)
    log("notes       : %s"
        % ("; ".join(ST["notes"]) if ST["notes"] else "none"))
    log("elapsed     : %.1f s over %d ticks" % (time.time() - ST["started"],
                                                ST["ticks"]))
    log("PIE entered : %s" % ST["entered"])
    log("tick errors : %d" % ST["errors"])
    log("")
    log("editor-world luma : %s" % ST["lums"].get("_p46_editor"))
    log("game-world  luma  : %s" % ST["lums"].get("_p46_game"))
    log("")

    ed = ST["survey"].get("editor")
    gm = ST["survey"].get("game")
    log("editor world: %s" % ("%d actors, %d active"
                              % (ed["n"], ed["active"]) if ed else "not surveyed"))
    log("game   world: %s" % ("%d actors (%d in PIE), %d active"
                              % (gm["n"], gm["pie"], gm["active"]) if gm
                              else "not surveyed"))
    log("")

    if gm is None:
        log("=> THE GAME WORLD WAS NEVER SURVEYED. Nothing about it is measured.")
    elif gm["pie"] == 0:
        log("=> THE ENUMERATION DID NOT REACH A PIE WORLD. The %d rows above"
            % gm["n"])
        log("   came from the editor world, so this run says nothing about PIE.")
    elif gm["active"] > 0:
        log("=> THE COMPONENTS COME UP IN A GAME WORLD. First time any of the")
        log("   nine has been measured running. The review frames and the pass01")
        log("   movie can be shot here, and IMPLEMENTED becomes reachable.")
    else:
        log("=> %d PIE rows found and NONE became active, in a game world,"
            % gm["pie"])
        log("   enumerated by a call known to reach it, with auto_activate=True.")
        log("   Session type and world type are both cleared. What remains is")
        log("   the system asset: a Niagara system whose compile never completed")
        log("   cannot instantiate, and p11 read compiling=True for 8 of these 9.")
    log("P46 DONE")
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
        WFX.watchdog_handover()
    except Exception:
        pass
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception as exc:
        log("quit_editor failed: %s" % str(exc)[:120])


def _enter_pie():
    for holder in ("LevelEditorSubsystem", "EditorLevelLibrary"):
        try:
            getattr(getattr(unreal, holder)(), "editor_play_simulate")()
            return "%s.editor_play_simulate" % holder
        except Exception as exc:
            log("    %s.editor_play_simulate failed: %s"
                % (holder, str(exc)[:80]))
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
        if st["phase"] == "boot":
            boot()
            st["wait"] = SETTLE_TICKS
            st["phase"] = "settle"
            return

        if st["phase"] == "settle":
            st["wait"] -= 1
            if st["wait"] <= 0:
                log("")
                log("--- shot 1: EDITOR world, 3 m from %s ---" % EDGE)
                shoot(st["ew"], st["ert"], st["ecc"], "_p46_editor")
                st["wait"] = 2
                st["phase"] = "exp_e"
            return

        if st["phase"] == "exp_e":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            export(st["ew"], st["ert"], "_p46_editor")
            log("")
            log("--- entering simulate ---")
            st["entered"] = _enter_pie()
            log("    -> %s" % st["entered"])
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
            log("PART C - the game world")
            log("=" * 74)
            log("game world path: %s" % (gw.get_path_name() if gw else "None"))
            log("")
            log("delta seconds  editor=%s   game=%s"
                % (world_clock(st["ew"]), world_clock(gw)))
            if gw is None:
                st["notes"].append("no game world after simulate")
                _finish("simulate produced no world")
                return
            st["gw"] = gw
            st["survey"]["game"] = survey(gw, "game")

            gcap, how = None, "not tried"
            caps, how = actors_of_class(gw, unreal.SceneCapture2D)
            log("")
            log("  SceneCapture2D in the game world: %d (%s)" % (len(caps), how))
            if caps:
                gcap = caps[0]
                log("    PIE DID duplicate the capture: %s"
                    % gcap.get_actor_label())
                st["rt"] = swcap.make_rt(gw, WIDTH, HEIGHT)
                try:
                    gcap.capture_component2d.set_editor_property(
                        "texture_target", st["rt"])
                except Exception as exc:
                    log("    texture_target: %s" % str(exc)[:90])
                st["cc"] = aim(gcap, CAM, CAM_ROT, "game")
            else:
                log("    PIE did NOT carry the capture into the game world, so")
                log("    there is no way to shoot it from here. The component")
                log("    states below are still valid measurements.")
                st["notes"].append("no capture in the game world")
            st["gcap"] = gcap
            st["wait"] = RUN_TICKS
            st["phase"] = "let_run"
            return

        if st["phase"] == "let_run":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            log("")
            log("--- did anything come up ON ITS OWN? (auto_activate=True) ---")
            survey(st["gw"], "game (before force)")
            log("")
            log("--- forcing activate(True) on the game world's own components ---")
            st["forced"] = force_activate(st["gw"], "game")
            st["wait"] = RUN_TICKS
            st["phase"] = "after_force"
            return

        if st["phase"] == "after_force":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            log("")
            log("--- after the force, %d ticks later ---" % RUN_TICKS)
            st["survey"]["game"] = survey(st["gw"], "game (after force)")
            log("")
            log("--- shot 2: GAME world, same pose ---")
            shoot(st["gw"], st["rt"], st["cc"], "_p46_game")
            st["wait"] = 2
            st["phase"] = "exp_g"
            return

        if st["phase"] == "exp_g":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            export(st["gw"], st["rt"], "_p46_game")
            _finish("game world surveyed and shot")
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:160]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 15:
            _finish("too many tick errors")


ST["handle"] = unreal.register_slate_post_tick_callback(tick)
