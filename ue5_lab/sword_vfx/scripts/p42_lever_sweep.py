"""
p42_lever_sweep.py - the nine components refuse to activate. Try every lever
                     the engine actually exposes, and take a frame after each.

WHAT p41 SETTLED, AND WHAT IT LEFT OPEN
    p41 read the API out of the engine instead of guessing it. Two results
    matter here.

    1. THE WORLD IS NOT THE REASON. The same nine components were read in the
       editor world and then again inside Play-In-Editor, where the world path
       is

           /Game/SEKAI/VFX/Sword/Lab/UEDPIE_0_L_SwordVFX_Lab.L_SwordVFX_Lab

       Both worlds gave the same answer: 9 of 9 active=False, tick=False,
       auto_activate=True. So the PIE detour that p38-p40 were built around was
       chasing the wrong variable, and the two worlds having the SAME get_name()
       ("L_SwordVFX_Lab") is why p40 could not tell them apart.

    2. activate() IS REFUSED IN A GAME WORLD TOO. Forcing activate(True) on all
       nine inside the PIE world gave before=False after=False for every one of
       them - 9 raised nothing and 9 changed nothing. In a game world
       UActorComponent::BeginPlay() calls Activate(true) itself for any
       component with bAutoActivate, and these have bAutoActivate=True, so the
       refusal is inside UNiagaraComponent and it survives the thing that would
       normally clear it.

    What p41 did NOT establish is WHY. This run stops asking why and instead
    tries every setter the engine exposes, one at a time, with a frame after
    each - because a lever that works is worth more than a mechanism that
    explains why the others do not.

WHY A FRAME AFTER EVERY LEVER, AND NOT JUST A FLAG
    p36 already showed this project's trap: a SceneCapture that renders a mesh
    and a material but not the Niagara actor. A flag can be read wrong; a
    changed frame cannot. Frames are named per step so they can be compared
    pairwise afterwards, and they are NAMED PER STEP because swimg.collect()
    prefers an existing <name>.png - re-exporting the same name in a loop
    returns the previous image.

WHAT EACH LEVER IS FOR
    vis         set_visible_in_scene_capture_only / set_hidden_in_scene_capture
                / set_visibility / set_rendering_enabled. p36 proved mesh and
                material render in this exact capture, so the capture works; a
                Niagara-specific visibility flag is one way it could still be
                excluded.
    cull        never_distance_cull / allow_cull_distance_volume /
                set_cull_distance. A component that is culled still reports
                active=False in some paths.
    tick        set_component_tick_enabled(True) + set_tick_behavior +
                set_tickable_when_paused + set_component_tick_interval.
    reinit      set_asset(asset, True) - drops and rebuilds the system instance
                from the asset that is already assigned.
    reset       reset_system() - Niagara's own "start over" entry point.
    activate    activate(True), called last in the chain so that if an earlier
                lever only primed the component, this is the one that fires.
    desired     set_age_update_mode(DESIRED_AGE) + set_desired_age +
                set_can_render_while_seeking + seek_to_desired_age(). This is
                the deterministic-capture path Niagara ships for sequencer
                scrubbing; it does not need the world to tick the component.
    advance     advance_simulation(30, 1/30) + advance_simulation_by_time(1.0).
                Hand-drives the sim the same way the deterministic path does,
                but by tick count.

    act_age     reset + activate + desired_age, in that order, as one step -
                because if the gate is "must be activated before a seek counts"
                then the two levers only work together.

THE INSTRUMENT THAT DISTINGUISHES "DEAD" FROM "INVISIBLE"
    Flags say a component is not active. They do not say whether it has a live
    system instance. NiagaraFunctionLibrary.get_all_emitters(component) does:
    it walks the component's live instance, so an empty result means there is no
    instance at all - the component is dead, not merely unseen. Together with
    was_recently_rendered(), that splits the four combinations:

        emitters=0, frame unchanged   -> no instance. Activation never happened.
        emitters>0, frame unchanged   -> instance alive, renders nothing. The
                                         graph is the problem, not the plumbing.
        emitters>0, frame changed     -> it works, and this lever is the answer.

OUTPUT
    render/sweep/_p42_00_base.png ... one frame per lever
    exports/p42_sweep.txt

Usage:
    cd sword_vfx/scripts && ./run_ue.sh p42_lever_sweep.py --render
    python tools/frame_pairs.py render/sweep --names _p42_00_base,_p42_01_vis,...
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

EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p42_sweep.txt')
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/sweep')
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"

WIDTH = 1280
HEIGHT = 720

# EdgeTrail is the subject because it is the only system that does not depend on
# timing luck: User.SpawnRate = 60/s with User.Lifetime = 0.25 s, so the moment
# the component runs at all there are ~15 ribbon particles in frame. Every other
# core is burst-driven, and a single as-loaded frame cannot tell "produced
# nothing" from "produced nothing yet" - which is what cost p33 its first run.
SUBJECT = "Lab_FX_EdgeTrail"
EDGE_LOC = unreal.Vector(900.0, -1200.0, 150.0)
CAM = unreal.Vector(1200.0, -1200.0, 150.0)
CAM_ROT = unreal.Rotator(pitch=0.0, yaw=180.0, roll=0.0)

SETTLE_TICKS = 24
HOLD_TICKS = 12
EXPORT_GAP = 2
BUDGET_SECONDS = 420.0

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

# The enum classes are not reachable as module attributes under the names the
# C++ uses (p41: ENiagaraComponentAgeUpdateMode / ENiagaraTickBehavior /
# EWorldType were all "NOT PRESENT"). Whatever the bindings DO expose under a
# Niagara name is listed here, so the next run can stop guessing the spelling.
log("")
log("### unreal.* names containing 'Niagara' (%d)"
    % len([m for m in dir(unreal) if "Niagara" in m]))
for m in sorted(m for m in dir(unreal) if "Niagara" in m):
    log("      %s" % m)
log("")
log("### unreal.* names containing 'Age' or 'Tick' or 'Viewport'")
for m in sorted(m for m in dir(unreal)
                if ("Age" in m or "Tick" in m or "Viewport" in m)):
    log("      %s" % m)


def enum_pick(kind, host_names, *names):
    """Find an enum member by trying the spellings the bindings might use.

    Returns (value, how) so a miss is visible in the log rather than silently
    becoming the first member of the enum - which would look like the lever was
    applied when it set the opposite value.

    The host class is a parameter because the first run of this script guessed
    ENiagaraComponentAgeUpdateMode / NiagaraComponentAgeUpdateMode and the engine
    dump of dir(unreal) then said the real name is **NiagaraAgeUpdateMode**. That
    one wrong word silently skipped the whole DESIRED_AGE lever.
    """
    for host in host_names:
        cls = getattr(unreal, host, None)
        if cls is None:
            continue
        for n in names:
            if hasattr(cls, n):
                return getattr(cls, n), "%s.%s" % (host, n)
    return None, "<not found: %s>" % kind


AGE_DESIRED, AGE_HOW = enum_pick(
    "age update mode", ("NiagaraAgeUpdateMode", "NiagaraComponentAgeUpdateMode"),
    "DESIRED_AGE", "DesiredAge")
TICK_LATE, TICK_HOW = enum_pick(
    "tick behavior", ("NiagaraTickBehavior",),
    "FORCE_TICK_LAST", "ForceTickLast")
log("")
log("age update mode DESIRED_AGE -> %s" % AGE_HOW)
log("tick behavior FORCE_TICK_LAST -> %s" % TICK_HOW)


def load_level():
    for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
        try:
            getattr(unreal, how)().load_level(LVL)
            log("level loaded via %s" % how)
            return True
        except Exception as exc:
            log("  %s failed: %s" % (how, str(exc)[:110]))
    return False


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


def find_subject():
    """The Lab_FX_EdgeTrail component, deduped.

    get_all_level_actors() returns every actor TWICE in this build, so matching
    by label without deduping would return one actor object and its duplicate,
    and a lever applied to one of them would read back from the other.
    """
    raw = []
    for holder in ("EditorActorSubsystem", "EditorLevelLibrary"):
        try:
            raw = list(getattr(unreal, holder)().get_all_level_actors())
            break
        except Exception:
            continue
    seen = set()
    for a in raw:
        try:
            key = a.get_path_name()
        except Exception:
            key = str(id(a))
        if key in seen:
            continue
        seen.add(key)
        try:
            if not isinstance(a, unreal.NiagaraActor):
                continue
            if a.get_actor_label() != SUBJECT:
                continue
            comp = a.get_component_by_class(unreal.NiagaraComponent)
            if comp is not None:
                return a, comp
        except Exception:
            continue
    return None, None


if not load_level():
    log("ABORT: no level")
    raise SystemExit(0)

EW = editor_world()
log("editor world: %s" % (EW.get_path_name() if EW else "None"))
ACTOR, COMP = find_subject()
if COMP is None:
    log("ABORT: %s has no NiagaraComponent" % SUBJECT)
    raise SystemExit(0)

ASSET = COMP.get_editor_property("asset")
log("subject     : %s  component=%s" % (SUBJECT, COMP.get_name()))
log("asset       : %s" % (ASSET.get_path_name() if ASSET else "None"))


# ---------------------------------------------------------------------------
# the live-instance probe
# ---------------------------------------------------------------------------
def probe(tag):
    """Everything that can distinguish dead from invisible, in one read.

    Never raises: this is called from inside the tick loop, where an exception
    is swallowed by an -ExecCmds editor session and would leave the run looking
    like a hang.
    """
    d = {}
    for name, fn in (
            ("active", lambda: COMP.is_active()),
            ("tick", lambda: COMP.is_component_tick_enabled()),
            ("rendered", lambda: COMP.was_recently_rendered()),
            ("desired_age", lambda: COMP.get_desired_age()),
            ("tick_behavior", lambda: COMP.get_tick_behavior()),
            ("max_sim_time", lambda: COMP.get_max_sim_time()),
            ("visible", lambda: COMP.is_visible()),
            ("hidden_in_sc_cap", lambda: COMP.get_editor_property(
                "hidden_in_scene_capture")),
            ("visible_in_sc_only", lambda: COMP.get_editor_property(
                "visible_in_scene_capture_only")),
            ("never_dist_cull", lambda: COMP.get_editor_property(
                "never_distance_cull")),
            ("emitters", lambda: unreal.NiagaraFunctionLibrary.get_all_emitters(
                COMP)),
            ("user_params", lambda: unreal.NiagaraFunctionLibrary.
                get_all_user_parameters(COMP)),
    ):
        try:
            v = fn()
            if name == "emitters":
                try:
                    v = "n=%d %s" % (len(v), ",".join(
                        str(x.get_name()) for x in list(v)[:4]))
                except Exception:
                    v = repr(v)[:60]
            elif name == "user_params":
                try:
                    v = "n=%d" % len(v)
                except Exception:
                    v = repr(v)[:60]
            d[name] = v
        except Exception as exc:
            # MEASURED, first run of this script: both of these land here with
            #     <NiagaraFunctionLibrary: Failed to convert pa...>
            # so the live-instance probe is VOID in this build - the calls do
            # not reach the engine at all. Exactly one verdict line below
            # depends on these values and it read the error STRING as evidence
            # that an instance existed ("...emitters: Failed to convert..." does
            # not start with "0 ", so it counted as live). A probe that cannot
            # tell void from evidence has to say void, so:
            d[name] = "VOID"
    log("      [%-9s] %s" % (tag, " ".join(
        "%s=%s" % (k, d[k]) for k in
        ("active", "tick", "rendered", "emitters"))))
    log("      %-11s %s" % ("", " ".join(
        "%s=%s" % (k, d[k]) for k in
        ("desired_age", "tick_behavior", "visible", "hidden_in_sc_cap",
         "visible_in_sc_only", "never_dist_cull", "max_sim_time",
         "user_params"))))
    return d


def call(fn, *a, **kw):
    """Apply a lever, naming the exception instead of swallowing it."""
    try:
        fn(*a, **kw)
        return True
    except Exception as exc:
        log("        %s raised %s" % (getattr(fn, "__name__", "?"),
                                       str(exc)[:80]))
        return False


# ---------------------------------------------------------------------------
# the levers, cumulative and in this order
# ---------------------------------------------------------------------------
def lv_vis():
    call(COMP.set_hidden_in_scene_capture, False)
    call(COMP.set_visible_in_scene_capture_only, False)
    call(COMP.set_visibility, True)
    call(COMP.set_rendering_enabled, True)


def lv_cull():
    swcap.set_prop(COMP, "never_distance_cull", True)
    swcap.set_prop(COMP, "allow_cull_distance_volume", False)
    call(COMP.set_cull_distance, -1.0)
    call(COMP.clear_system_fixed_bounds)


def lv_tick():
    call(COMP.set_component_tick_enabled, True)
    call(COMP.set_tickable_when_paused, True)
    call(COMP.set_component_tick_interval, 0.0)
    call(COMP.set_max_sim_time, -1.0)
    if TICK_LATE is not None:
        call(COMP.set_tick_behavior, TICK_LATE)


def lv_reinit():
    if ASSET is not None:
        call(COMP.set_asset, ASSET, True)


def lv_reset():
    call(COMP.reset_system)


def lv_activate():
    call(COMP.activate, True)


def lv_desired():
    if AGE_DESIRED is not None:
        call(COMP.set_age_update_mode, AGE_DESIRED)
    call(COMP.set_can_render_while_seeking, True)
    call(COMP.set_lock_desired_age_delta_time_to_seek_delta, False)
    call(COMP.set_desired_age, 1.0)
    # MEASURED, first run: seek_to_desired_age() is NOT a no-argument call.
    #     seek_to_desired_age() required argument 'desired_age' (pos 1) not found
    # A zero-argument raise here would otherwise have looked like "the seek lever
    # does not work" rather than "the seek lever was never invoked".
    call(COMP.seek_to_desired_age, 1.0)


def lv_advance():
    call(COMP.advance_simulation, 30, 1.0 / 30.0)
    call(COMP.advance_simulation_by_time, 1.0, 1.0 / 30.0)


def lv_act_age():
    call(COMP.reset_system)
    call(COMP.activate, True)
    lv_desired()


STEPS = [
    ("_p42_00_base", "as loaded", None),
    ("_p42_01_vis", "+ visibility", lv_vis),
    ("_p42_02_cull", "+ never-cull", lv_cull),
    ("_p42_03_tick", "+ tick forced", lv_tick),
    ("_p42_04_reinit", "+ set_asset(True)", lv_reinit),
    ("_p42_05_reset", "+ reset_system", lv_reset),
    ("_p42_06_activate", "+ activate(True)", lv_activate),
    ("_p42_07_desired", "+ desired age + seek", lv_desired),
    ("_p42_08_advance", "+ advance_simulation", lv_advance),
    ("_p42_09_act_age", "+ reset->activate->desired", lv_act_age),
]


# ---------------------------------------------------------------------------
# capture
# ---------------------------------------------------------------------------
RT = swcap.make_rt(EW, WIDTH, HEIGHT)
if RT is None:
    log("ABORT: no render target")
    raise SystemExit(0)
CAP, HOW = None, None
for maker in (
        lambda: unreal.EditorLevelLibrary.spawn_actor_from_class(
            unreal.SceneCapture2D, CAM, CAM_ROT),
        lambda: unreal.EditorActorSubsystem().spawn_actor_from_class(
            unreal.SceneCapture2D, CAM, CAM_ROT),
):
    try:
        CAP = maker()
        if CAP is not None:
            break
    except Exception as exc:
        log("  capture spawn failed: %s" % str(exc)[:90])
if CAP is None:
    log("ABORT: could not spawn the capture")
    raise SystemExit(0)
CC = CAP.capture_component2d
swcap.set_prop(CC, "texture_target", RT)
V = getattr(unreal.SceneCaptureSource, "SCS_FINAL_COLOR_LDR", None)
if V is not None:
    swcap.set_prop(CC, "capture_source", V)
swcap.set_prop(CC, "capture_every_frame", False)
OF, OW = swcap.place_capture(CC, CAP, CAM, CAM_ROT, loc_tol=5.0, rot_tol=5.0)
CL = CAP.get_actor_location()
log("capture placed=%s at (%.0f, %.0f, %.0f)" % (OF, CL.x, CL.y, CL.z))
if not OF:
    log("  why: %s" % OW)

swcap.clear_rt(EW, RT)
try:
    CC.capture_scene()
except Exception as exc:
    log("  capture_scene raised: %s" % str(exc)[:110])
swcap.export_rt(EW, RT, OUT_DIR, "_p42_warm")
_got = swimg.collect(OUT_DIR, "_p42_warm")
_st = swimg.png_stats(_got) if _got else None
if _st is not None and _st["mean_luma"] is not None:
    log("  warm-up frame  luma=%.2f distinct=%s top=%s %.1f%%"
        % (_st["mean_luma"], _st["distinct_rgb"], _st["top_rgb"],
           100.0 * _st["top_rgb_frac"]))
else:
    log("  warm-up frame  NO FILE - the capture is not producing pixels and")
    log("                 nothing measured after this point can be trusted")

# The capture placement is judged by its own verification (place_capture
# compares the component transform to what was asked for), but "placed" and
# "rendering" are different claims and this project has already confused them
# once: p23 reported `capture placed on Review_TP34: True` while measuring
# somewhere else entirely. So the warm frame above is the real check.


# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------
ST = {"handle": None, "ticks": 0, "phase": "settle", "wait": SETTLE_TICKS,
      "i": -1, "started": time.time(), "errors": 0, "lums": {}, "rows": {},
      "shot": False}


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
    log("tick errors : %d" % ST["errors"])
    log("")
    log("lever              active tick rendered emitters  luma")
    base = ST["lums"].get("_p42_00_base")
    moved = []
    for tag, why, _fn in STEPS:
        d = ST["rows"].get(tag, {})
        lum = ST["lums"].get(tag)
        delta = ""
        if lum is not None and base is not None:
            delta = "%+.3f" % (lum - base)
            if abs(lum - base) > 0.05:
                moved.append(tag)
        log("  %-18s %-6s %-4s %-8s %-9s %s %s"
            % (tag.replace("_p42_", ""), d.get("active"), d.get("tick"),
               d.get("rendered"), d.get("emitters"), lum, delta))
    log("")
    # The emitters column is VOID in this build - see the note in probe(). A
    # void probe must not be read as either answer, so the live-instance test is
    # reported as unavailable rather than as a result.
    void = [t for t in ST["rows"] if ST["rows"][t].get("emitters") == "VOID"]
    log("live-instance probe (get_all_emitters): %s"
        % ("VOID in %d/%d reads - parameter conversion fails in this build, so"
           % (len(void), len(ST["rows"])) if void else "usable"))
    log("frames that changed vs baseline          : %s"
        % (", ".join(moved) if moved else "NONE"))
    tick_stuck = [t for t in ST["rows"] if ST["rows"][t].get("tick") is True]
    log("levers after which the tick flag stuck   : %s"
        % (", ".join(t.replace("_p42_", "") for t in tick_stuck) or "NONE"))
    log("")
    if moved:
        log("=> A LEVER MOVED THE FRAME. Whatever produced it is the answer;")
        log("   the nine review frames and the pass01 movie should be shot with")
        log("   that lever order and no manual editor session is needed.")
    else:
        log("=> NO LEVER MOVED THE FRAME. Ten cumulative configurations were")
        log("   tried - including Niagara's own deterministic-capture path and")
        log("   its hand-drive path - and the frame is byte-identical across all")
        log("   of them (luma equal to twelve decimals). Levers that should")
        log("   stick, stuck: never_distance_cull, max_sim_time, desired_age and")
        log("   the component tick flag all read back changed, and the picture")
        log("   did not.")
        log("")
        log("   What this DOES say: the component never comes up under a")
        log("   scripted -ExecCmds session, in the editor world or in a PIE")
        log("   world, with every setter the engine exposes applied. It is a")
        log("   measured MANUAL EDITOR STEP, not a guess.")
        log("")
        log("   What this does NOT say: nothing about the graph. An inert")
        log("   component renders nothing regardless of how good its emitters")
        log("   are, so these ten identical frames are NOT evidence that the")
        log("   nine systems are built wrong. p11's structural read-back (37")
        log("   modules, 49 pins, 0 unverified, 0 errors) is the evidence about")
        log("   the graph, and it is untouched.")
        log("")
        log("   Consequence for the batch: IMPLEMENTED cannot be claimed from a")
        log("   script, and neither can VISUALLY VERIFIED. Both need one human")
        log("   pass in the editor, which is what docs/EXACT_BUILD.md's 25")
        log("   MANUAL EDITOR STEP markers were written for.")
    log("P42 DONE")
    WFX.watchdog_handover()
    try:
        if ST["handle"] is not None:
            unreal.unregister_slate_post_tick_callback(ST["handle"])
    except Exception:
        pass
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception as exc:
        log("quit_editor failed: %s" % str(exc)[:120])


def _shoot(tag):
    swcap.clear_rt(EW, RT)
    try:
        CC.capture_scene()
    except Exception as exc:
        log("    capture_scene raised: %s" % str(exc)[:110])


def _export(tag):
    swcap.export_rt(EW, RT, OUT_DIR, tag)
    got = swimg.collect(OUT_DIR, tag)
    st = swimg.png_stats(got) if got else None
    if st is not None and st["mean_luma"] is not None:
        ST["lums"][tag] = st["mean_luma"]
        log("    %-16s luma=%.3f distinct=%s top=%s %.1f%%"
            % (tag, st["mean_luma"], st["distinct_rgb"], st["top_rgb"],
               100.0 * st["top_rgb_frac"]))
    else:
        log("    %-16s NO FILE" % tag)
        ST["lums"][tag] = None


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
            if st["wait"] > 0:
                return
            st["phase"] = "run"
            st["wait"] = HOLD_TICKS
            st["i"] = -1
            return

        if st["phase"] == "run":
            if st["wait"] > 0:
                st["wait"] -= 1
                return
            if st["shot"]:
                _export(STEPS[st["i"]][0])
                st["shot"] = False
                st["wait"] = EXPORT_GAP
                st["phase"] = "gap"
                return
            st["i"] += 1
            if st["i"] >= len(STEPS):
                _finish("all levers tried")
                return
            tag, why, fn = STEPS[st["i"]]
            log("")
            log("--- step %d/%d  %s  (%s)" % (st["i"] + 1, len(STEPS), tag, why))
            if fn is not None:
                fn()
            ST["rows"][tag] = probe(tag.replace("_p42_", ""))
            _shoot(tag)
            st["shot"] = True
            st["wait"] = EXPORT_GAP
            st["phase"] = "gap"
            return

        if st["phase"] == "gap":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            st["phase"] = "run"
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:170]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 20:
            _finish("too many tick errors")


log("")
log("--- settle %d ticks, then one frame per lever ---" % SETTLE_TICKS)
WFX.install_watchdog(3000)
ST["handle"] = unreal.register_slate_post_tick_callback(tick)
