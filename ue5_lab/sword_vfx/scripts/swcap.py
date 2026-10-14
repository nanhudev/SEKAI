"""SEKAI Sword VFX - shared scene-capture helpers.

WHY THIS MODULE EXISTS (and it is not tidiness)

    P23 hand-rolled its own capture-move cascade - one lambda per call shape,
    "did it raise" as the success test - and reported

        capture placed on Review_TP34: True
        capture world loc: (0.0,0.0,200.0)  camera loc: (-520.0,300.0,235.0)

    A false positive, printed as success. The probe then measured the wrong
    place and I read the result as evidence about the world.

    P21 already had this right: a nine-attempt cascade followed by a READBACK
    VERIFICATION against the target transform. Two implementations of the same
    thing, one of them wrong, and the wrong one was the new one. That is the
    normal failure mode of copied code, so the code lives here once and both
    scripts import it.

WHAT IS IN HERE

    set_prop        try/set, never raises
    vdist / adiff   hand-rolled, because the verification path must not raise
    clear_rt        clear a render target to a KNOWN colour
    move_capture    nine-attempt cascade -> (ok, how, why)
    verify_move     readback comparison -> ((dl, dr), "") or (None, why)
    place_capture   move + verify in one call -> (ok, why)

THE GREEN-CLEAR TRICK, which is the most useful thing in this file

    A render target that was never rendered into and a render target showing a
    black scene both export as "a black PNG" and both fail a brightness gate.
    MEASURED on the archived first pass: five byte-identical frames, alpha 255,
    RGB (0,0,0) for 89.81% of pixels and (1,1,1) for the rest - which is
    create_render_target2d's clear colour and its export dither, not a scene.

    So never ask "is it dark?". Clear the target to a colour no scene would
    contain (bright green), wait, then read it:

        still green  -> nothing rendered into it. Unambiguous.
        anything else-> something rendered, and now you can look at WHAT.

    That converts the central question from a judgement call into a bit.
"""
import unreal


# --------------------------------------------------------------------------
# basics
# --------------------------------------------------------------------------
def set_prop(obj, name, value):
    """set_editor_property, never raising. Returns whether it applied."""
    try:
        obj.set_editor_property(name, value)
        return True
    except Exception:
        return False


def get_prop(obj, name):
    """get_editor_property, never raising. Returns (ok, value)."""
    try:
        return True, obj.get_editor_property(name)
    except Exception as exc:
        return False, str(exc)[:90]


def vdist(a, b):
    """Euclidean distance, hand-rolled.

    Not `unreal.Vector.distance()`: this build has moved that method more than
    once, and a wrong guess raises inside the verification path - the one place
    that must not raise, because its whole job is to report whether something
    else worked.
    """
    return ((a.x - b.x) ** 2 + (a.y - b.y) ** 2 + (a.z - b.z) ** 2) ** 0.5


def adiff(a, b):
    """Smallest absolute angle between two headings, degrees, wrap-aware.

    Without the modulo a camera at yaw 179 and one at -179 read as 358 degrees
    apart, failing a shot that is in fact correctly placed.
    """
    return abs((a - b + 180.0) % 360.0 - 180.0)


# --------------------------------------------------------------------------
# render targets
# --------------------------------------------------------------------------
GREEN = (0.0, 1.0, 0.0, 1.0)


def make_rt(world, width, height,
            fmt_name="RTF_RGBA8"):
    """Create a render target for capture. Returns the asset or None."""
    fmt = getattr(unreal.TextureRenderTargetFormat, fmt_name, None)
    if fmt is None:
        return None
    try:
        return unreal.RenderingLibrary.create_render_target2d(world, width,
                                                              height, fmt)
    except Exception:
        return None


def clear_rt(world, rt, colour=GREEN):
    """Clear a render target to a known colour. Returns whether it applied."""
    try:
        unreal.RenderingLibrary.clear_render_target2d(
            world, rt, unreal.LinearColor(*colour))
        return True
    except Exception:
        return False


def export_rt(world, rt, out_dir, name):
    """Export a render target and return the path, or None.

    NOTE: the engine writes `out_dir/name` with NO extension. swimg.collect()
    is what normalises that; this only performs the export.
    """
    try:
        unreal.RenderingLibrary.export_render_target(world, rt, out_dir, name)
    except Exception:
        return None
    return None


# --------------------------------------------------------------------------
# moving a SceneCapture2D
# --------------------------------------------------------------------------
def move_capture(cc, cap, loc, rot):
    """Put the capture at a transform. Returns (ok, how, why).

    The arity of these setters is NOT uniform in this build. Measured, verbatim:

        TypeError: set_world_location_and_rotation() required argument
                   'sweep' (pos 3) not found

    so `sweep` is a REQUIRED positional and the natural two-argument call
    raises instead of defaulting. Guessing one call shape is what broke the
    first run, and that failure was expensive in a shape that deserves
    remembering: the exception came from inside the TICK CALLBACK, so it fired
    once per frame for 954 frames and the editor never went down.

    The ACTOR is tried first because the capture component IS the SceneCapture2D's
    root, so moving either moves the same transform - and the caller verifies
    against the actor either way. MEASURED: the actor path is the one that
    actually applies in this build.
    """
    attempts = (
        ("actor loc(1)+rot(2)",
         lambda: (cap.set_actor_location(loc),
                  cap.set_actor_rotation(rot, False))),
        ("actor loc(2)+rot(2)",
         lambda: (cap.set_actor_location(loc, False),
                  cap.set_actor_rotation(rot, False))),
        ("actor loc(3)+rot(2)",
         lambda: (cap.set_actor_location(loc, False, False),
                  cap.set_actor_rotation(rot, False))),
        ("comp loc+rot 4-arg",
         lambda: cc.set_world_location_and_rotation(loc, rot, False, False)),
        ("comp loc+rot 3-arg",
         lambda: cc.set_world_location_and_rotation(loc, rot, False)),
        ("comp loc+rot 2-arg",
         lambda: cc.set_world_location_and_rotation(loc, rot)),
        ("comp split(1)",
         lambda: (cc.set_world_location(loc), cc.set_world_rotation(rot))),
        ("comp split(2)",
         lambda: (cc.set_world_location(loc, False),
                  cc.set_world_rotation(rot, False))),
        ("comp split(3)",
         lambda: (cc.set_world_location(loc, False, False),
                  cc.set_world_rotation(rot, False, False))),
    )
    errs = []
    for how, fn in attempts:
        try:
            fn()
        except Exception as exc:
            errs.append("%s -> %s" % (how, str(exc)[:60]))
            continue
        return True, how, ""
    return False, "", " | ".join(errs)


def verify_move(cap, loc, rot):
    """Read the capture ACTOR back and compare with the target.

    Returns ((dloc_cm, drot_deg), "") or (None, why) if the readback is
    unavailable - which is reported, never treated as a pass.

    This is the check that stops a probe from lying. A move that returns
    without applying leaves the capture where it was, and then every "shot"
    measures the same place under a different name.
    """
    try:
        gl = cap.get_actor_location()
        gr = cap.get_actor_rotation()
    except Exception as exc:
        return None, str(exc)[:100]
    dl = vdist(gl, loc)
    dr = max(adiff(gr.pitch, rot.pitch),
             adiff(gr.yaw, rot.yaw),
             adiff(gr.roll, rot.roll))
    return (dl, dr), ""


def place_capture(cc, cap, loc, rot, loc_tol=1.0, rot_tol=0.5):
    """Move AND verify. Returns (ok, why).

    verifying is not optional: `move_capture` returning True only means no
    exception was raised.
    """
    ok, how, why = move_capture(cc, cap, loc, rot)
    if not ok:
        return False, "every call shape failed: %s" % why
    measured, verr = verify_move(cap, loc, rot)
    if measured is None:
        return False, "moved via %s but the readback failed: %s" % (how, verr)
    dl, dr = measured
    if dl > loc_tol or dr > rot_tol:
        return False, ("moved via %s but readback disagrees: off by "
                       "%.2f cm / %.2f deg" % (how, dl, dr))
    return True, how


# --------------------------------------------------------------------------
# scene queries, for ruling out the trivial explanation
# --------------------------------------------------------------------------
def actors_near(actors, centre, radius_cm, limit=12):
    """Labels of actors within radius_cm of centre, nearest first.

    Exists to rule out "the frame is black because there is nothing in front of
    the camera". That is the dullest possible cause and it should be excluded
    by measurement rather than by assumption.
    """
    found = []
    for a in actors:
        try:
            loc = a.get_actor_location()
        except Exception:
            continue
        d = vdist(loc, centre)
        if d <= radius_cm:
            try:
                lbl = a.get_actor_label()
            except Exception:
                lbl = a.get_name()
            found.append((d, lbl))
    found.sort()
    return found[:limit]


def component_transform(cc):
    """(loc, fwd) for a capture COMPONENT, or (None, None).

    Worth asking separately from the actor, because the two are not
    interchangeable evidence: P23 moved the component through a cascade that
    reported success and left it at the world origin, while the actor it read
    back looked fine. What determines what the capture SEES is the component's
    own world transform, so a probe that only verifies the actor can still be
    pointing the camera at nothing.
    """
    loc = fwd = None
    try:
        loc = cc.get_world_location()
    except Exception:
        pass
    try:
        fwd = cc.get_forward_vector()
    except Exception:
        pass
    return loc, fwd


# --------------------------------------------------------------------------
# the ladder harness
# --------------------------------------------------------------------------
class Ladder:
    """Run a list of steps on the editor's slate post-tick callback.

    A step is a dict:

        {"label": str,            # what this rung tests, printed as a header
         "pre":   callable,       # runs first; apply the lever here
         "post":  callable,       # runs after the wait; read the result here
         "wait":  int}            # optional, ticks between pre and post

    WHY IT IS A CLASS AND NOT COPIED PER PROBE

        P23 hand-rolled its own cascade-and-wait and got the success test wrong
        (it treated "the call did not raise" as "the call applied"). P24 then
        hand-rolled a different one that worked. Two scripts with two harnesses
        is one harness that drifts, and the drift is silent. So the tick state
        machine lives here once.

    TWO THINGS THIS GETS RIGHT THAT ARE EASY TO GET WRONG

    1. A `pre` that raises does NOT abort the run, but it DOES invalidate the
       rung: the lever never applied, so "nothing changed" is not evidence.
       Those counts are reported separately from real readings.

    2. The watchdog is handed over only after the callback has completed a tick.
       Handing over before the loop throws away the only net that catches "the
       callback never ran at all" - which is a real way for these probes to sit
       forever doing nothing.
    """

    def __init__(self, plan, log, wait=10, budget=900, name="LADDER"):
        self.plan = list(plan)
        self.log = log
        self.wait_default = wait
        self.budget = budget
        self.name = name
        self.state = {"idx": 0, "stage": "pre", "wait": 0, "errors": 0,
                      "t": 0, "done": False, "results": [], "handed": False,
                      "handle": None}
        self.on_done = None
        self.handover = None

    # -- execution --------------------------------------------------------
    def start(self, on_done=None, handover=None):
        self.on_done = on_done
        self.handover = handover
        self.state["handle"] = unreal.register_slate_post_tick_callback(
            self._tick)
        return self

    def _call(self, fn, where):
        try:
            return fn()
        except Exception as exc:
            self.state["errors"] += 1
            self.log("        %s raised: %s: %s"
                     % (where, type(exc).__name__, str(exc)[:140]))
            return None

    def _tick(self, delta):
        st = self.state
        if st["done"]:
            return
        st["t"] += 1
        if st["t"] > self.budget:
            self._finish("tick budget exhausted")
            return
        st["wait"] -= 1
        if st["wait"] > 0:
            return
        if st["idx"] >= len(self.plan):
            self._finish("complete")
            return
        step = self.plan[st["idx"]]
        if st["stage"] == "pre":
            self.log("")
            self.log("[%d/%d] %s" % (st["idx"] + 1, len(self.plan),
                                     step["label"]))
            self._call(step.get("pre"), "pre")
            st["stage"] = "post"
            st["wait"] = step.get("wait", self.wait_default)
            if not st["handed"]:
                if self.handover is not None:
                    self._call(self.handover, "handover")
                st["handed"] = True
        else:
            st["results"].append((step["label"], self._call(step.get("post"),
                                                            "post")))
            st["idx"] += 1
            st["stage"] = "pre"

    def _finish(self, reason):
        st = self.state
        if st["done"]:
            return
        st["done"] = True
        try:
            if self.on_done is not None:
                self.on_done(st, reason)
        finally:
            try:
                unreal.unregister_slate_post_tick_callback(st["handle"])
            except Exception:
                pass

    # -- reading ----------------------------------------------------------
    def green_rungs(self):
        return [l for l, v in self.state["results"] if v == "GREEN"]

    def changed_rungs(self):
        return [l for l, v in self.state["results"] if v == "CHANGED"]

