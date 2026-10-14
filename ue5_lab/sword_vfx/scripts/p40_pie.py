"""
p40_pie.py - Play-In-Editor, because the editor world will not tick a Niagara component.

WHAT THE LAST FOUR SCRIPTS ESTABLISHED, AND WHY THIS IS THE NEXT STEP
    p36  the mesh and the material RENDER (85320 px changed when quads appeared)
    p37  Lifetime forced to 5 s, five frames at +3/+6/+12/+42 ticks identical
    p38  comp.is_active() False; tick.start_with_tick_enabled False;
         is_component_tick_enabled False - while the SceneCapture component in
         the SAME world reports start_with_tick_enabled True
    p39  b_tick_in_editor is not exposed; start_with_tick_enabled reads back
         True for an instant then False; set_component_tick_enabled(True) reads
         back True then False; spawn_system_at_location produces a component
         that is also inactive. Every lever refused.

    So the component is not being ticked, and it is not a property I can set.
    In an editor session there are two worlds: the one the editor authors in,
    where components are not obliged to tick, and the one a game runs in, where
    they are. Everything so far has been measured in the first one.

    This measures the second one.

WHAT PIE COSTS
    Entering simulate mode duplicates the level into a game world. The capture
    actor and the render target have to be created in THAT world, not the
    editor's, or the capture frames the wrong world (or nothing). So they are
    spawned through GameplayStatics with the game world as the context, and the
    row of targets is read out of the game world itself rather than assumed.

    The baseline is the same camera pose shot in the editor world first, so the
    two frames are a before/after on the only variable that changed: which
    world is being looked at.

OUTPUT
    render/pie/_p40_editor.png   baseline, editor world
    render/pie/_p40_game.png     after entering simulate, game world
    exports/p40_pie.txt

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p40_pie.py --render
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p40_pie.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/pie')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"

WIDTH = 1280
HEIGHT = 720

# The camera pose is deliberately the SAME in both worlds: 3 m in front of
# Lab_FX_EdgeTrail, which is a RIBBON emitter driven by User.SpawnRate = 60/s
# with Lifetime 0.25 s. A steady emitter is the right subject here: it needs no
# burst and no timing luck, so if the world ticks it, particles are present in
# every frame - unlike the one-shot burst emitters, which are only visible for a
# quarter of a second after activation.
EDGE_LOC = unreal.Vector(900.0, -1200.0, 150.0)
CAM = unreal.Vector(1200.0, -1200.0, 150.0)
CAM_ROT = unreal.Rotator(pitch=0.0, yaw=180.0, roll=0.0)

SETTLE_TICKS = 60
PIE_TICKS = 90
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

loaded = False
for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
    try:
        getattr(unreal, how)().load_level(LVL)
        log("level loaded via %s" % how)
        loaded = True
        break
    except Exception as exc:
        log("  %s failed: %s" % (how, str(exc)[:120]))
if not loaded:
    log("ABORT: no level")
    raise SystemExit(0)


def editor_world():
    for getter in ("UnrealEditorSubsystem", "EditorLevelLibrary"):
        try:
            w = getattr(unreal, getter)().get_editor_world()
            if w is not None:
                return w
        except Exception:
            continue
    return None


def game_world():
    for holder, name in (("UnrealEditorSubsystem", "get_game_world"),
                         ("EditorLevelLibrary", "get_game_world")):
        try:
            w = getattr(getattr(unreal, holder)(), name)()
            if w is not None:
                return w
        except Exception:
            continue
    return None


def spawn_in(world, cls, loc, rot):
    """Spawn into a specific world. EditorLevelLibrary has no world argument,
    so the game world needs GameplayStatics and the world as context."""
    for label, fn in (
            ("GameplayStatics.begin_spawn_actor_from_class",
             lambda: unreal.GameplayStatics.begin_spawn_actor_from_class(
                 world, cls, loc, rot)),
            ("GameplayStatics.spawn_actor_from_class",
             lambda: unreal.GameplayStatics.spawn_actor_from_class(
                 cls, loc, rot)),
            ("EditorLevelLibrary.spawn_actor_from_class",
             lambda: unreal.EditorLevelLibrary.spawn_actor_from_class(
                 cls, loc, rot)),
    ):
        try:
            a = fn()
            if a is not None:
                return a, label
        except Exception as exc:
            log("        %s failed: %s" % (label, str(exc)[:90]))
    return None, None


def setup_capture(world, tag):
    rt = swcap.make_rt(world, WIDTH, HEIGHT)
    if rt is None:
        log("    %s: could not make a render target" % tag)
        return None, None, None
    cap, how = spawn_in(world, unreal.SceneCapture2D, CAM, CAM_ROT)
    if cap is None:
        log("    %s: could not spawn the capture (%s)" % (tag, how))
        return None, None, None
    cc = cap.capture_component2d
    try:
        cc.set_editor_property("texture_target", rt)
    except Exception as exc:
        log("    %s: texture_target %s" % (tag, str(exc)[:90]))
    v = getattr(unreal.SceneCaptureSource, "SCS_FINAL_COLOR_LDR", None)
    if v is not None:
        try:
            cc.set_editor_property("capture_source", v)
        except Exception:
            pass
    try:
        cc.set_editor_property("capture_every_frame", False)
    except Exception:
        pass
    ok, why = swcap.place_capture(cc, cap, CAM, CAM_ROT, loc_tol=5.0, rot_tol=5.0)
    cl = cap.get_actor_location()
    log("    %s: capture via %s placed=%s at (%.0f, %.0f, %.0f)"
        % (tag, how, ok, cl.x, cl.y, cl.z))
    return rt, cc, cap


def shoot(world, rt, cc, name):
    swcap.clear_rt(world, rt)
    try:
        cc.capture_scene()
    except Exception as exc:
        log("    capture_scene raised: %s" % str(exc)[:110])
    return name


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


# ------------------------------------------------------------------ editor world baseline
EW = editor_world()
if EW is None:
    log("ABORT: no editor world")
    raise SystemExit(0)
log("")
log("--- editor world baseline ---")
ert, ecc, ecap = setup_capture(EW, "editor")
if ert is None:
    log("ABORT: baseline capture unavailable")
    raise SystemExit(0)


def state_of(world, tag):
    """What the world says about the Niagara actors inside it."""
    log("    [%s] world=%s" % (tag, world.get_name() if world else "None"))
    try:
        actors = unreal.EditorLevelLibrary.get_all_level_actors()
    except Exception:
        actors = []
    seen = {}
    for a in actors or []:
        try:
            if not isinstance(a, unreal.NiagaraActor):
                continue
            comp = a.get_component_by_class(unreal.NiagaraComponent)
            if comp is None:
                continue
            seen[a.get_actor_label()] = (
                comp.is_active(), comp.is_component_tick_enabled())
        except Exception:
            continue
    n_act = sum(1 for v in seen.values() if v[0])
    n_tick = sum(1 for v in seen.values() if v[1])
    log("        niagara actors=%d  active=%d  tick_enabled=%d"
        % (len(seen), n_act, n_tick))
    return len(seen), n_act, n_tick


state_of(EW, "editor")

ST = {"handle": None, "started": time.time(), "ticks": 0, "phase": "settle",
      "wait": SETTLE_TICKS, "errors": 0, "lums": {}, "entered": None,
      "gw": None, "rt": None, "cc": None}


def _finish(reason):
    if ST["phase"] == "done":
        return
    ST["phase"] = "done"
    log("")
    log("--- summary ---")
    log("stop reason : %s" % reason)
    log("elapsed     : %.1f s over %d ticks" % (time.time() - ST["started"],
                                                ST["ticks"]))
    log("PIE entered via: %s" % ST["entered"])
    log("tick errors : %d" % ST["errors"])
    log("")
    log("editor-world luma : %s" % ST["lums"].get("_p40_editor"))
    log("game-world  luma  : %s" % ST["lums"].get("_p40_game"))
    e, g = ST["lums"].get("_p40_editor"), ST["lums"].get("_p40_game")
    if e is None or g is None:
        log("one of the two frames is missing - no comparison is possible")
    elif abs(g - e) < 0.5:
        log("=> THE TWO WORLDS LOOK THE SAME. Play-In-Editor did not change it,")
        log("   so the component's inactivity is not about which world it is in.")
        log("   The next suspect is the graph itself.")
    else:
        log("=> THE FRAMES DIFFER, so something rendered in one world and not the")
        log("   other. Compare the two images and the bounding box of the")
        log("   difference before concluding which way round it is.")
    log("P40 DONE")
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
                         ("EditorLevelLibrary", "editor_play_simulate"),
                         ("LevelEditorSubsystem", "editor_play"),
                         ("EditorLevelLibrary", "editor_play")):
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
                log("--- shot 1: editor world, camera 3 m from Lab_FX_EdgeTrail ---")
                shoot(EW, ert, ecc, "_p40_editor")
                st["wait"] = 2
                st["phase"] = "exp_e"
            return

        if st["phase"] == "exp_e":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            st["lums"]["_p40_editor"] = export(EW, ert, "_p40_editor")
            log("")
            log("--- entering simulate (Play-In-Editor) ---")
            st["entered"] = _enter_pie()
            log("    _enter_pie -> %s" % ST["entered"])
            st["wait"] = PIE_TICKS
            st["phase"] = "pie_wait"
            return

        if st["phase"] == "pie_wait":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            gw = game_world()
            log("    game world: %s" % (gw.get_name() if gw else "None"))
            if gw is None:
                log("    NO GAME WORLD - simulate mode did not start a runnable world")
                state_of(EW, "editor (again)")
                _finish("no game world after simulate")
                return
            st["gw"] = gw
            state_of(gw, "game")
            rt, cc, cap = setup_capture(gw, "game")
            if rt is None:
                _finish("could not build a capture in the game world")
                return
            st["rt"], st["cc"] = rt, cc
            st["wait"] = 40
            st["phase"] = "let_particles"
            return

        if st["phase"] == "let_particles":
            st["wait"] -= 1
            if st["wait"] <= 0:
                log("")
                log("--- shot 2: game world, same pose, 40 ticks of simulation ---")
                shoot(st["gw"], st["rt"], st["cc"], "_p40_game")
                st["wait"] = 2
                st["phase"] = "exp_g"
            return

        if st["phase"] == "exp_g":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            st["lums"]["_p40_game"] = export(st["gw"], st["rt"], "_p40_game")
            state_of(st["gw"], "game (at shot)")
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
