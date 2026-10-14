"""
p41_api_map.py - read the API out of the engine instead of guessing it.

WHY THIS RUN EXISTS
    p40 tried to build a capture in the Play-In-Editor game world through

        unreal.GameplayStatics.begin_spawn_actor_from_class

    and got

        type object 'GameplayStatics' has no attribute 'begin_spawn_actor_from_class'

    That member never existed. Neither does SpawnActorFromClass on
    GameplayStatics. Both names were invented at the keyboard, and the run then
    spent its whole budget discovering it - because a missing attribute inside a
    spawn cascade looks exactly like "no world-aware spawn exists anywhere".

    Guessing a name is a coin flip that costs a minute of engine time and
    returns an ambiguous answer. dir() costs nothing and returns a fact. So this
    run reads the names first and uses them afterwards.

WHAT ELSE IT SETTLES
    Four runs have circled the tick question, and the last one turned up a
    number that contradicts the conclusion drawn from it:

        p36  the mesh and the material DO render (85320 px changed when the
             quads appeared); adding a Niagara actor changes 0 px
        p37  User.Lifetime forced to 5 s: five timed frames, luma spread 0.00
        p38  comp.is_active() False; tick.start_with_tick_enabled False;
             is_component_tick_enabled() False
        p39  every lever refused; b_tick_in_editor is not exposed to python;
             spawn_system_at_location yields an inactive component too
        p40  [editor] niagara actors=9  active=0  tick_enabled=2   <-- two ARE on

    Two of nine reporting a live tick function says the editor world is not
    refusing Niagara wholesale. So "the editor world will not tick a Niagara
    component" is at best half true, and the whole PIE detour rests on it.

    The cheap discriminator is is_active() read in BOTH worlds: once in the
    editor world, once on the same component after editor_play_simulate. If it
    flips to True only in the game world, the refusal is gated on world type and
    Play-In-Editor is the answer. If it stays False in both, the component is
    not the thing that is broken and the search moves into the graph.

    is_active() does not need a rasterizer, so --editor (and -nullrhi) is
    enough. That makes this run short.

OUTPUT
    exports/p41_api.txt
    render/apimap/_p41_game_probe.png   only if the PIE capture path works

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p41_api_map.py --editor
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

import swvfx as WFX  # noqa: E402

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p41_api.txt')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"

WFX.bind_log(EXPORT)
log = WFX.log

log("engine: %s" % unreal.SystemLibrary.get_engine_version())


# ---------------------------------------------------------------------------
# PART A - the names
#
# Two grades of dump. "hot" filters to the words any spawn/tick/capture answer
# would have to contain, which keeps the useful part readable; a few small
# classes get the full list, because the name that is missing from a filtered
# list is exactly the one that fails a run.
# ---------------------------------------------------------------------------
INTEREST = (
    "spawn", "tick", "activat", "particl", "instanc", "age", "emit", "render",
    "captur", "screenshot", "play", "slot", "cull", "bound", "reset", "visib",
    "asset", "sim", "world", "class", "transform", "attach",
)

HOT_ONLY = [
    "EditorActorSubsystem", "EditorLevelLibrary", "EditorSubsystemBlueprintLibrary",
    "LevelEditorSubsystem", "UnrealEditorSubsystem", "NiagaraComponent",
    "NiagaraActor", "SceneCapture2D", "SceneCaptureComponent2D", "World",
    "MoviePipelineQueueSubsystem",
]
FULL = [
    "GameplayStatics", "KismetSystemLibrary", "NiagaraFunctionLibrary",
    "AutomationLibrary", "RenderingLibrary", "SystemLibrary",
]

log("")
log("=" * 74)
log("PART A - the real API surface")
log("=" * 74)

for cname in FULL + HOT_ONLY:
    cls = getattr(unreal, cname, None)
    if cls is None:
        log("")
        log("### %-32s NOT PRESENT in this build" % cname)
        continue
    try:
        members = [m for m in dir(cls) if not m.startswith("_")]
    except Exception as exc:
        log("")
        log("### %-32s dir() raised: %s" % (cname, str(exc)[:90]))
        continue
    if cname in FULL:
        shown = sorted(members)
        log("")
        log("### %-32s ALL %d members" % (cname, len(shown)))
    else:
        shown = sorted(m for m in members if any(k in m.lower() for k in INTEREST))
        log("")
        log("### %-32s %d of %d, filtered"
            % (cname, len(shown), len(members)))
    for m in shown:
        log("      %s" % m)

# The spawn call needs an argument shape, and there is more than one collision
# handling enum in circulation. Read them too rather than guess which spelling.
log("")
log("### enums")
for ename in ("ESpawnActorCollisionHandlingMethod", "ESpawnActorScaleMethod",
              "ENiagaraComponentAgeUpdateMode", "EAttachmentRule",
              "EWorldType", "ENiagaraTickBehavior", "EComponentMobility"):
    e = getattr(unreal, ename, None)
    if e is None:
        log("      %-34s NOT PRESENT" % ename)
        continue
    try:
        vals = [v for v in dir(e) if not v.startswith("_")]
        log("      %-34s %s" % (ename, ", ".join(sorted(vals)[:14])))
    except Exception as exc:
        log("      %-34s dir() raised: %s" % (ename, str(exc)[:70]))


# ---------------------------------------------------------------------------
# PART B - the level, and what its nine components say about themselves
# ---------------------------------------------------------------------------
log("")
log("=" * 74)
log("PART B - the nine gallery components, as the editor world sees them")
log("=" * 74)

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
    log("ABORT: no level")
    raise SystemExit(0)


def editor_world():
    for holder, name in (("UnrealEditorSubsystem", "get_editor_world"),
                         ("EditorLevelLibrary", "get_editor_world")):
        try:
            w = getattr(getattr(unreal, holder)(), name)()
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


def world_name(w, how="path"):
    """The editor world and the PIE world are BOTH named L_SwordVFX_Lab.

    MEASURED in p40: `game world: L_SwordVFX_Lab` - the same get_name() as the
    editor world. So get_name() cannot tell the two apart and using it as an
    identity test would have silently compared a world with itself. The path
    name carries the UEDPIE_ prefix and is the one that can.
    """
    if w is None:
        return "None"
    if how == "path":
        try:
            return w.get_path_name()
        except Exception:
            pass
    try:
        return w.get_name()
    except Exception:
        return "?"


EW = editor_world()
log("")
log("editor world : %s" % world_name(EW))
log("  get_name() : %s" % world_name(EW, "name"))


def enumerate_actors(world=None):
    """Every actor, deduped.

    get_all_level_actors() returns each actor TWICE in this build - a known trap
    in this project - so anything that counts them has to dedupe first or every
    number it prints is double. Dedupe is by PATH NAME, not by label: two actors
    may legitimately share a label.
    """
    raw = []
    if world is not None:
        for getter in (
                lambda: unreal.GameplayStatics.get_all_actors_of_class(
                    world, unreal.Actor),
        ):
            try:
                got = getter()
                if got:
                    raw = list(got)
                    break
            except Exception as exc:
                log("        world enumeration via GameplayStatics failed: %s"
                    % str(exc)[:80])
    if not raw:
        for holder in ("EditorActorSubsystem", "EditorLevelLibrary"):
            try:
                raw = list(getattr(unreal, holder)().get_all_level_actors())
                break
            except Exception:
                continue
    out, seen = [], set()
    for a in raw:
        try:
            key = a.get_path_name()
        except Exception:
            key = str(id(a))
        if key in seen:
            continue
        seen.add(key)
        out.append(a)
    return out


def niagara_state(tag, world=None):
    """Per component: label, asset, active, tick, and the tick struct itself."""
    actors = enumerate_actors(world)
    log("    [%s] %d actors enumerated" % (tag, len(actors)))
    rows, tick_on, active_on = [], 0, 0
    for a in actors:
        try:
            if not isinstance(a, unreal.NiagaraActor):
                continue
            comp = a.get_component_by_class(unreal.NiagaraComponent)
            if comp is None:
                continue
        except Exception:
            continue
        label = "?"
        try:
            label = a.get_actor_label()
        except Exception:
            pass
        asset = "?"
        try:
            s = comp.get_editor_property("asset")
            asset = s.get_name() if s is not None else "None"
        except Exception as exc:
            asset = "<%s>" % str(exc)[:40]
        act = tick = "?"
        try:
            act = comp.is_active()
        except Exception:
            pass
        try:
            tick = comp.is_component_tick_enabled()
        except Exception:
            pass
        auto = "<unreadable>"
        try:
            auto = comp.get_editor_property("auto_activate")
        except Exception:
            pass
        rows.append((label, asset, act, tick, auto))
        if act is True:
            active_on += 1
        if tick is True:
            tick_on += 1
    for label, asset, act, tick, auto in sorted(rows):
        log("      %-22s asset=%-26s active=%-5s tick=%-5s auto_activate=%s"
            % (label, asset, act, tick, auto))
    log("    [%s] total=%d active=%d tick_enabled=%d"
        % (tag, len(rows), active_on, tick_on))
    return rows, active_on, tick_on


ROWS_E, ACT_E, TICK_E = niagara_state("editor world", None)

# The tick struct behind the flag. b_tick_in_editor is a real C++ field on
# FTickFunction (p39: "Failed to find property 'b_tick_in_editor'" when set by
# name) but the struct has to be looked at directly to know what IS reachable.
log("")
log("  --- primary_component_tick, one component in full ---")
for a in enumerate_actors(None):
    try:
        if not isinstance(a, unreal.NiagaraActor):
            continue
        comp = a.get_component_by_class(unreal.NiagaraComponent)
        t = comp.primary_component_tick
    except Exception:
        continue
    try:
        fields = [x for x in dir(t) if not x.startswith("_")]
    except Exception as exc:
        log("    dir(tick) raised: %s" % str(exc)[:80])
        break
    log("    fields: %s" % ", ".join(sorted(fields)))
    for f in sorted(fields):
        try:
            log("      %-34s = %s" % (f, getattr(t, f)))
        except Exception as exc:
            log("      %-34s <raised %s>" % (f, str(exc)[:36]))
    break


# ---------------------------------------------------------------------------
# PART C - the same components, read in a game world
#
# This is the discriminator. is_active() is a plain flag; if a component refuses
# to set it in one world type and sets it in the other, the refusal is about the
# world and Play-In-Editor is the fix. Anything measured here is independent of
# whether pixels get drawn, which is why this can run under -nullrhi.
# ---------------------------------------------------------------------------
PRISTINE = "<not measured>"
ST = {"handle": None, "ticks": 0, "phase": "settle", "wait": 45, "errors": 0,
      "started": time.time(), "gw": None, "entered": None, "rows_g": None,
      "after_activate": None}


def _finish(reason):
    if ST["phase"] == "done":
        return
    ST["phase"] = "done"
    log("")
    log("=" * 74)
    log("VERDICT")
    log("=" * 74)
    log("stop reason : %s" % reason)
    log("elapsed     : %.1f s over %d ticks" % (time.time() - ST["started"],
                                                ST["ticks"]))
    log("PIE entered : %s" % ST["entered"])
    log("tick errors : %d" % ST["errors"])
    log("")
    log("  editor world : active=%d tick_enabled=%d  of %d"
        % (ACT_E, TICK_E, len(ROWS_E)))
    if ST["rows_g"] is not None:
        g = ST["rows_g"]
        log("  game world   : active=%d tick_enabled=%d  of %d"
            % (g[1], g[2], len(g[0])))
    else:
        log("  game world   : %s" % PRISTINE)
    log("  after activate(True) in the game world: %s" % ST["after_activate"])
    log("")
    if ST["rows_g"] is None:
        log("NO GAME WORLD. Play-In-Editor did not produce one, so the world")
        log("type is not testable this way and the next lever is elsewhere.")
    elif ST["rows_g"][1] > ACT_E or (ST["after_activate"] or "").find("True") >= 0:
        log("=> THE FLAG FLIPS IN A GAME WORLD. The component refuses to")
        log("   activate in the editor world and activates in a PIE world, so")
        log("   the inert gallery is a world-type gate, not a broken graph.")
        log("   Everything downstream - review frames, the pass01 movie - has to")
        log("   be shot inside a game world.")
    else:
        log("=> THE FLAG DOES NOT FLIP. Both worlds leave every component at")
        log("   active=False, so world type is NOT the cause and the refusal is")
        log("   in the component or its asset. Play-In-Editor is a dead end and")
        log("   the next instrument is the graph.")
    log("P41 DONE")
    WFX.watchdog_handover()
    try:
        if ST["handle"] is not None:
            unreal.unregister_slate_post_tick_callback(ST["handle"])
    except Exception:
        pass
    for ender in ("editor_request_end_play",):
        try:
            fn = getattr(unreal.EditorLevelLibrary, ender, None)
            if fn is not None:
                fn()
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
    if time.time() - st["started"] > 420.0:
        _finish("budget exhausted")
        return
    try:
        if st["phase"] == "settle":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            log("")
            log("=" * 74)
            log("PART C - entering Play-In-Editor (simulate)")
            log("=" * 74)
            st["entered"] = _enter_pie()
            log("    _enter_pie -> %s" % st["entered"])
            st["wait"] = 60
            st["phase"] = "pie_wait"
            return

        if st["phase"] == "pie_wait":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            gw = game_world()
            log("")
            log("game world   : %s" % world_name(gw))
            log("  get_name() : %s" % world_name(gw, "name"))
            if gw is None:
                _finish("simulate did not produce a game world")
                return
            st["gw"] = gw
            st["rows_g"] = niagara_state("game world", gw)

            log("")
            log("  --- forcing activate(True) on every game-world component ---")
            flipped, refused = [], []
            for a in enumerate_actors(gw):
                try:
                    if not isinstance(a, unreal.NiagaraActor):
                        continue
                    comp = a.get_component_by_class(unreal.NiagaraComponent)
                    if comp is None:
                        continue
                    label = a.get_actor_label()
                except Exception:
                    continue
                before = comp.is_active()
                try:
                    comp.activate(True)
                except Exception as exc:
                    refused.append("%s(raise %s)" % (label, str(exc)[:30]))
                    continue
                after = comp.is_active()
                (flipped if after else refused).append(label)
                log("      %-22s before=%-5s after=%-5s" % (label, before, after))
            st["after_activate"] = ("flipped=%d [%s] refused=%d"
                                    % (len(flipped), ",".join(sorted(flipped)[:9]),
                                       len(refused)))
            log("    %s" % st["after_activate"])
            st["wait"] = 20
            st["phase"] = "after"
            return

        if st["phase"] == "after":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            # A readback 20 ticks later, because "it flipped" and "it STAYED
            # flipped" are different claims and p39 already caught one setting
            # that reverted silently.
            st["rows_g"] = niagara_state("game world, 20 ticks after activate",
                                         st["gw"])
            _finish("both worlds measured")
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:170]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 15:
            _finish("too many tick errors")


log("")
log("--- settle %d ticks, then Play-In-Editor ---" % ST["wait"])
WFX.install_watchdog(2400)
ST["handle"] = unreal.register_slate_post_tick_callback(tick)
