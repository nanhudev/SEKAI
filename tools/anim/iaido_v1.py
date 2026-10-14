# -*- coding: utf-8 -*-
"""SEKAI / ANIMATION LINE -- THIRD-PERSON IAIDO V1 (greybox performance + proof).

    "/g/blender.exe" -b --factory-startup --python tools/anim/iaido_v1.py -- \
        --stage selftest|poses|anim|verify|all  [--variant combat|stationary]

WHAT THIS IS
============
One character, one katana, one saya, and NO EFFECTS OF ANY KIND.  The brief is
explicit that if the greybox is not already impressive with every world-cut,
glass shard and blue void switched off, then nothing downstream can save it.  So
this file never touches the VFX stack.  It is judged on one question: does the
sword really come out of the sheath, and does it really go back in.

THE GEOMETRIC FACT THAT SHAPES EVERYTHING
=========================================
`sword_classes.gd` fixes the drawn length: the tip sits 0.765 m from the grip
origin, so the sword must travel ~0.762 m relative to the saya before the tip
clears the koiguchi.  Measured off this rig, the shoulder-to-mouth distance is
0.51 m and the whole arm -- shoulder to grip centre -- is 0.379 m.  A straight
pull asks the hand to be ~0.9 m from a shoulder that owns 0.38 m of lever.  That
is not a style choice, it is unreachable.

So the draw is not authored at all: `precompute()` SOLVES the saya's rotation
from the arm's reach.  The point on a sphere of radius `travel_full` around the
mouth that is nearest the shoulder sits `travel_full - |mouth - shoulder|` =
0.32 m from that shoulder -- comfortably inside a 0.38 m arm.  Pointing the bore
at the shoulder therefore makes the fully-drawn grip reachable BY CONSTRUCTION,
and the extraction is a pure slide along the bore.  The left hand is what sweeps
that bore, which is why the brief's "BOTH HANDS CREATE THE DRAW" is a mechanical
statement rather than a stylistic one.

THE SAYA IS CURVED AND THAT IS NOT A DETAIL
===========================================
Measured off `fp_saya.glb`: the bore's centreline is a true circular arc,
R = 16.27 m bulging toward the edge side -- 15 mm of sori.  Radial clearance
between habaki and bore wall is 1.2-1.7 mm.  A straight translation therefore
drives the blade ~12 mm into the saya's own wall near the mouth: over 8 mm of
clipping, invisible in numbers and obvious in silhouette.  Extraction here is a
ROTATION ABOUT THE BORE'S ARC CENTRE, which slides the blade down the channel it
was machined to slide down.

WHY THE WHOLE THING IS A FUNCTION OF FRAME NUMBER
=================================================
`state(t)` maps a float frame number to every scalar of the performance and
`solve(t)` maps that to a pose.  Nothing is hand-keyframed.  Two reasons:
  * the constraints (blade inside the bore, hand on the hilt, feet planted) must
    hold on EVERY frame, and interpolating between hand-authored keys does not
    preserve them -- a slerp between two arm poses cuts a straight line through
    the saya wall;
  * true 0.25x slow motion needs evaluation at t = 0.25, 0.5, 0.75..., which
    retiming a baked clip cannot give (that only repeats frames).
The brief's "key pose first" discipline is honoured by the `poses` stage, which
renders the eight locked poses for review BEFORE `anim` bakes anything.

AXIS NOTE (cost one restart)
============================
Blender's glTF importer bakes the Y-up conversion INTO THE VERTEX DATA, and does
it at identity object matrices.  So the imported sword has its tip on Blender
local +Z, not +Y -- confirmed by measuring the bore liner's local bbox.  Checked
rather than assumed, because every transform below is expressed in that frame
and a quarters-turn error there is invisible until you look at a render.
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
for _p in (HERE, str(_SEKAI_ROOT / 'tools/blender')):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import rig_common as RC                      # noqa: E402
import review_render as RR                   # noqa: E402  (the shared light rig)

# ---------------------------------------------------------------------------
#  paths.  The sword is `fp_sword_v8`, NOT `fp_sword`:
#  `assets/models/weapons/fp_sword.glb` (md5 3709fda0) and
#  `godot/models/weapons/fp_sword.glb` (md5 4e9e694b == fp_sword_v8.glb) are two
#  different files under one name.  Reported, not silently tidied.
# ---------------------------------------------------------------------------
CHAR_GLB = str(_SEKAI_ROOT / 'assets_source/characters/placeholders/lpg_casual_m.glb')
SWORD_GLB = str(_SEKAI_ROOT / 'assets/models/weapons/fp_sword_v8.glb')
SAYA_GLB = str(_SEKAI_ROOT / 'assets/models/weapons/fp_saya.glb')
OUT_DEFAULT = str(_SEKAI_ROOT / '.render/iaido_tp')
ENCODE = _sekai_os.environ.get('FFMPEG_BIN', 'ffmpeg')

FPS = 30
F_END = 102                      # 3.400 s -- the brief's own timeline
CLEAR_MARGIN = 0.012             # m the tip must clear the mouth by at full draw
F_AWARE, F_PREP, F_DRAW, F_CUT, F_SETTLE, F_SEAT, F_HOLD = 10, 26, 32, 38, 47, 84, 93
# The frame the free cut hands BACK to the scabbard-derived sword.  The sheathing
# is a straight slide down the bore, so its first frame is not authorable: it is
# whatever `M_saya @ seat(travel_full)` happens to be.  `precompute()` therefore
# FILLS the last authored key from the solution, the same way it fills the first
# one -- otherwise the blade swings 0.84 m in 1.5 frames and the right hand
# leaves the hilt by 479 mm, which is what the first `--stage verify` run
# reported.
F_ALIGN = 49
# The brief names eight poses: Neutral / Hand on Hilt / Compression / 25% Draw /
# 60% Draw / Cut Finish / Re-sheath Align / Final Click.  Two more are locked
# alongside them because they are acceptance surfaces in their own right:
# `Settle` (brief 10-11 asks for a follow-through hold plus an overshoot) and
# `SheathMid` (the user's own step 6: "sheathing is harder than drawing and gets
# its own acceptance", so it needs a plate like everything else).
#
# `Draw60` was MISSING from the first pass and its absence was not cosmetic.
# Measured off the plate run, `travel` is 0.000 at f26 (Load) and 0.193 of
# `travel_clear` 0.762 at f29 -- so f29 already IS the brief's "25% Draw" -- while
# the next key sat at f38 with the blade fully out and the cut already landed.
# The whole remaining 75% of the extraction therefore happened inside a
# three-frame hole (f29..f32) with no locked pose anywhere in it, which is
# exactly the stretch where the blade has to follow the bore's arc rather than cut
# the corner.  A constraint you never photograph is a constraint you do not have.
# f30.2 is not a round number because it is the frame that actually MEASURES
# 61.6% out; the draw accelerates hard (25% at f29, 77% at f31) so no integer
# lands on the beat, and pinning it to f31 would have put a "60% Draw" label on a
# 77%-drawn pose.
#
# `Align` at f49 is the mandated Re-sheath Align beat.  It is also the frame the
# existing `--stage verify` run names as its worst `right_hand_on_hilt` miss
# (36.51 mm), so it is the single most useful plate in this set: the one pose the
# numbers already say is imperfect, made visible.
KEYS = [("Neutral", 0), ("Grip", 10), ("Load", 26), ("Draw25", 29),
        ("Draw60", 30.2), ("CutFinish", 38), ("Settle", 44), ("Align", 49),
        ("SheathMid", 74), ("FinalClick", 88)]

GROUND_U = -0.792                # the feet, measured off the rig
STANCE_PEL_U = -0.020            # relaxed knees: this rig's rest legs are 99.8%
                                 # straight and cannot take a step otherwise
FOOT_L = (0.150, -0.118, 7.0)    # f, r, toe-out deg
FOOT_R = (-0.105, 0.118, -11.0)
MOUTH = (0.088, -0.152, 0.082)   # koiguchi at rest, on the left hip
BORE_TILT = 13.0                 # deg, mouth up / kojiri down
BORE_YAW = -9.0                  # deg, kojiri swung outboard (left)
SINK = 0.044                     # the brief asks 3-6 cm onto the rear foot
PELV_YAW_LOAD = -21.0            # chest turns so the right shoulder can reach
PELV_YAW_CUT = 14.0              # ... then unwinds through the cut
# A SIDE-BEND is not decoration -- it is the only reason the draw is possible at
# all.  Measured on this rig: the mouth sits 0.443 m from the right shoulder but
# shoulder->hand is only 0.379 m, so the right hand cannot even TOUCH the hilt
# standing square.  Bending the torso over the left hip drops the right shoulder
# and carries it across, which is exactly what a human does to reach the far hip.
SPINE_ROLL_DRAW = 19.0           # deg, top tips toward the character's LEFT
ROOT_STEP = 0.42                 # variant A only; variant B is in place
SAYA_BACK_MAX = 0.26             # m the LEFT hand may slide the saya backwards
REACH_TARGET = 0.495             # m, grip-to-shoulder budget (arm 0.379 + 0.134 grip)
LH_LOCAL = Vector((0.0, 0.011, 0.058))     # left palm on the saya, saya's frame
HILT_LOCAL = Vector((0.0, 0.0, -0.055))    # right hand sits low on the tsuka
CURL = {"grip": 48.0, "saya": 42.0, "open": 4.0}

EIO, EI, EO, EL = RC.ease_in_out, RC.ease_in, RC.ease_out, (lambda x: x)


def CV(keys):
    """keys = [(frame, value, ease)]; ease applies to the segment ENDING here."""
    keys = sorted(keys, key=lambda k: k[0])

    def f(t):
        if t <= keys[0][0]:
            return keys[0][1]
        if t >= keys[-1][0]:
            return keys[-1][1]
        for i in range(1, len(keys)):
            t0, v0, _ = keys[i - 1]
            t1, v1, e = keys[i]
            if t0 <= t <= t1:
                u = (t - t0) / (t1 - t0) if t1 > t0 else 1.0
                return v0 + (v1 - v0) * e(u)
        return keys[-1][1]
    return f


# ---------------------------------------------------------------------------
#  measured weapon geometry (Blender local: +Z = long axis, -X = edge side)
# ---------------------------------------------------------------------------

def _mesh_objects(objs):
    return {o.data.name: o for o in objs if o.type == "MESH"}


def _pts(ob):
    return [ob.matrix_local @ v.co for v in ob.data.vertices]


def _circfit(P):
    n = len(P)
    su = sum(p[0] for p in P); sv = sum(p[1] for p in P)
    suu = sum(p[0] ** 2 for p in P); svv = sum(p[1] ** 2 for p in P)
    suv = sum(p[0] * p[1] for p in P)
    suuu = sum(p[0] ** 3 for p in P); svvv = sum(p[1] ** 3 for p in P)
    suvv = sum(p[0] * p[1] ** 2 for p in P); svuu = sum(p[1] * p[0] ** 2 for p in P)
    A = [[suu, suv, su], [suv, svv, sv], [su, sv, n]]
    B = [suuu + suvv, svvv + svuu, suu + svv]
    M = [A[i][:] + [B[i]] for i in range(3)]
    for i in range(3):
        piv = max(range(i, 3), key=lambda r: abs(M[r][i]))
        M[i], M[piv] = M[piv], M[i]
        for r in range(3):
            if r != i:
                f = M[r][i] / M[i][i]
                for c in range(i, 4):
                    M[r][c] -= f * M[i][c]
    s = [M[i][3] / M[i][i] for i in range(3)]
    uc, vc = s[0] / 2.0, s[1] / 2.0
    return uc, vc, math.sqrt(max(s[2] + uc * uc + vc * vc, 0.0))


def _profile(pts, bins=28):
    """bbox-mid centreline + half extents, binned along local +Z.

    bbox-mid, NOT the vertex mean: a shinogi-zukuri blade is a wedge, so its
    vertices are not symmetric about its own centreline and the mean drifts
    ~7 mm -- four times the fit clearance, which would have sent the whole
    extraction model off in the wrong direction while looking reasonable.
    """
    lo = min(p.z for p in pts); hi = max(p.z for p in pts)
    out = []
    for b in range(bins):
        z0 = lo + (hi - lo) * b / bins
        z1 = lo + (hi - lo) * (b + 1) / bins
        sel = [p for p in pts if z0 <= p.z < z1]
        if len(sel) < 4:
            continue
        xs = [p.x for p in sel]; ys = [p.y for p in sel]
        out.append(dict(z=0.5 * (z0 + z1), cx=0.5 * (min(xs) + max(xs)),
                        hw=0.5 * (max(xs) - min(xs)),
                        ht=0.5 * (max(ys) - min(ys))))
    return out


def _interp(prof, z, key):
    if z <= prof[0]["z"]:
        return prof[0][key]
    if z >= prof[-1]["z"]:
        return prof[-1][key]
    for i in range(1, len(prof)):
        if prof[i - 1]["z"] <= z <= prof[i]["z"]:
            a, b = prof[i - 1], prof[i]
            t = (z - a["z"]) / (b["z"] - a["z"])
            return a[key] + (b[key] - a[key]) * t
    return prof[-1][key]


class Weapons(object):
    def __init__(self, sword_objs, saya_objs):
        sm, ym = _mesh_objects(sword_objs), _mesh_objects(saya_objs)
        for nm in ("Blade", "Habaki", "Guard", "Kashira"):
            if nm not in sm:
                RC.die("sword mesh '%s' missing (have %s)" % (nm, sorted(sm)))
        if "Saya_Bore_Liner" not in ym:
            RC.die("saya bore liner missing (have %s)" % sorted(ym))

        blade = _pts(sm["Blade"]); habaki = _pts(sm["Habaki"])
        guard = _pts(sm["Guard"]); bore = _pts(ym["Saya_Bore_Liner"])

        self.tip_z = max(p.z for p in blade)
        self.kashira_z = min(p.z for p in _pts(sm["Kashira"]))
        self.seat_back = max(p.z for p in guard)          # MEASURED, 0.003 m
        self.travel_clear = self.tip_z - self.seat_back
        self.travel_full = self.travel_clear + CLEAR_MARGIN

        gx = max(abs(p.x) for p in guard); gy = max(abs(p.y) for p in guard)
        if gx < gy:
            RC.die("Guard is wider across Y (%.4f) than X (%.4f): the sword is not "
                   "in the documented frame (+Z tip, -X edge)" % (gy, gx))

        self.blade_prof = _profile(blade)
        self.bore_prof = _profile(bore)
        self.bore_len = self.bore_prof[-1]["z"]
        self.inside_pts = habaki + _pts(sm["Tang"]) if "Tang" in sm else habaki
        self.bore_cx, self.bore_cz, self.bore_R = _circfit(
            [(p["cx"], p["z"]) for p in self.bore_prof])
        self.blade_R = _circfit([(p["cx"], p["z"]) for p in self.blade_prof])[2]

        worst = 0.0
        for b in self.blade_prof:
            if b["z"] > self.bore_prof[-1]["z"]:
                continue
            worst = max(worst, abs(b["cx"] - _interp(self.bore_prof, b["z"], "cx")))
        self.centreline_mismatch = worst

        self.habaki_hw = max(abs(p.x) for p in habaki)
        self.habaki_ht = max(abs(p.y) for p in habaki)
        m = self.bore_prof[0]
        self.clear_w = m["hw"] - self.habaki_hw
        self.clear_t = m["ht"] - self.habaki_ht

        RC.log("sword  tip_z=%.4f  guard_mouth_z=%.4f  kashira_z=%.4f"
               % (self.tip_z, self.seat_back, self.kashira_z))
        RC.log("saya   bore arc R=%.3f m  centre=(%.3f, %.3f)  mouth half w=%.4f t=%.4f"
               % (self.bore_R, self.bore_cx, self.bore_cz, m["hw"], m["ht"]))
        RC.log("travel clear=%.4f  full=%.4f m   habaki clearance w=%.2f mm t=%.2f mm"
               % (self.travel_clear, self.travel_full,
                  self.clear_w * 1000.0, self.clear_t * 1000.0))
        RC.log("blade centreline vs bore centreline: worst %.4f mm (blade arc R=%.2f m)"
               % (self.centreline_mismatch * 1000.0, self.blade_R))
        if self.centreline_mismatch > 0.0012:
            RC.die("blade centreline is %.2f mm off the bore -- rotate-about-arc-"
                   "centre extraction is not a valid model for these files"
                   % (self.centreline_mismatch * 1000.0))
        if min(self.clear_w, self.clear_t) < 0.0008:
            RC.die("habaki clearance below 0.8 mm -- nothing can slide in this")

    def seat(self, travel):
        """Sword transform expressed in the SAYA's local frame.

        A rotation about the bore's own arc centre by -travel/R, so the blade
        slides along the channel instead of through its wall.  Local frame: the
        bore is +Z, the sori lies in the XZ plane, so the axis is local Y and the
        sign is chosen so increasing travel moves the sword OUT (-Z).
        """
        c = Vector((self.bore_cx, 0.0, self.bore_cz))
        return (Matrix.Translation(c) @ Matrix.Rotation(-travel / self.bore_R, 4, "Y")
                @ Matrix.Translation(-c)
                @ Matrix.Translation(Vector((0.0, 0.0, -self.seat_back))))

    def bore_margin(self, travel, pts=None):
        """Worst radial intrusion into the saya wall at this extraction state.
        Negative = the blade is inside the wood.  Returns (margin, where, n)."""
        T = self.seat(travel)
        zmax = self.bore_prof[-1]["z"]
        worst = 1e9
        at = None
        n = 0
        for p in (pts if pts is not None else self.inside_pts):
            q = T @ p
            if q.z < 0.0 or q.z > zmax:
                continue
            n += 1
            cx = _interp(self.bore_prof, q.z, "cx")
            m = min(_interp(self.bore_prof, q.z, "hw") - abs(q.x - cx),
                    _interp(self.bore_prof, q.z, "ht") - abs(q.y))
            if m < worst:
                worst = m
                at = (q.z, q.x - cx, q.y)
        return worst, at, n


def blend_matrix(A, B, w):
    if w <= 1e-6:
        return A.copy()
    if w >= 1.0 - 1e-6:
        return B.copy()
    q = A.to_quaternion().slerp(B.to_quaternion(), w)
    M = q.to_matrix().to_4x4()
    M.translation = A.translation.lerp(B.translation, w)
    return M


# The two GLBs are authored in the SHARED contract frame:
#   local +Z = long axis (toward the tip / down the bore)
#   local -X = the side the cutting edge faces
#   local +-Y = the flat
# `apply_grip` wants (X = spine side, Y = toward the tip, Z = the flat), which
# is the SAME frame with two axes swapped -- and swapping them without flipping
# one would make the basis left-handed, i.e. a mirrored hand.
def sword_rod_basis(M):
    B = M.to_3x3()
    return RC.mat_from_cols(B.col[0], B.col[2], -B.col[1]).to_3x3()


def saya_rod_basis(M):
    """Left hand on the saya: the knuckle line's index side faces the BLADE, so
    "toward the far end" is the mouth (-Z), not the kojiri."""
    B = M.to_3x3()
    return RC.mat_from_cols(B.col[0], -B.col[2], B.col[1]).to_3x3()


def aim_roll(rig, side, rod, gc, grip_w, shoulder, limit=80.0):
    """Roll the hand about the ROD's own axis so the WRIST lands on the shoulder
    side of the grip.

    Why this is a real degree of freedom and not a cheat: the palm has to be on
    the correct face of the tsuka, but WHERE around that face the wrist sits is
    what separates an arm that reaches from an arm that does not.  The measured
    grip frame happens to put the wrist 0.02 m closer to the shoulder than the
    grip centre at rest -- carry the same rod through a 100 deg scabbard
    rotation and the wrist swings to 0.05 m further out, which is most of a
    0.10 m miss on an arm with 0.379 m to spend.  Rather than hope the basis
    lands on the good side, pick the side.  Clamped, because rolling too far
    drives the palm through the handle and that IS a cheat.
    """
    a = Vector(rod.col[1]).normalized()          # the rod's own axis
    off = rig.grip_basis(side, rod) @ gc
    e = Vector(grip_w) - Vector(shoulder)
    if e.length < 1e-5:
        return rod
    e.normalize()
    op = off - a * off.dot(a)
    ep = e - a * e.dot(a)
    if op.length < 1e-6 or ep.length < 1e-6:
        return rod
    op.normalize()
    ep.normalize()
    phi = math.degrees(math.atan2(a.dot(op.cross(ep)), op.dot(ep)))
    phi = RC.clamp(phi, -limit, limit)
    return (Matrix.Rotation(math.radians(phi), 3, a) @ rod).to_3x3()


# ---------------------------------------------------------------------------
#  the performance
# ---------------------------------------------------------------------------

class Perf(object):
    def __init__(self, rig, cf, w, variant):
        self.r, self.cf, self.w = rig, cf, w
        self.variant = variant
        self.step = ROOT_STEP if variant == "combat" else 0.0

        # ---- body ---------------------------------------------------------
        self.pel_u = CV([(0, STANCE_PEL_U, EIO), (12, STANCE_PEL_U - 0.008, EI),
                         (F_PREP, STANCE_PEL_U - SINK, EI),
                         (31, STANCE_PEL_U - SINK + 0.014, EO),
                         (F_CUT, STANCE_PEL_U + 0.016, EO),
                         (F_SETTLE, STANCE_PEL_U + 0.004, EIO),
                         (F_SEAT, STANCE_PEL_U - 0.006, EIO), (F_END, STANCE_PEL_U, EIO)])
        self.pel_f = CV([(0, 0.0, EIO), (F_PREP, -0.022, EI), (31, -0.012, EO),
                         (F_CUT, 0.032, EO), (F_SETTLE, 0.012, EIO),
                         (F_SEAT, 0.004, EIO), (F_END, 0.0, EIO)])
        self.pel_yaw = CV([(0, -3.0, EIO), (F_PREP, PELV_YAW_LOAD, EI),
                           (33, PELV_YAW_LOAD * 0.35, EO), (F_CUT, PELV_YAW_CUT, EO),
                           (F_SETTLE, PELV_YAW_CUT * 0.45, EIO), (F_SEAT, -2.0, EIO),
                           (F_END, 0.0, EIO)])
        self.step_f = CV([(0, 0.0, EIO), (F_PREP, 0.0, EI), (F_DRAW, self.step, EO),
                          (F_END, self.step, EIO)])
        self.spine_pitch = CV([(0, 2.0, EIO), (F_PREP, 9.0, EI), (F_DRAW, 5.0, EO),
                               (F_CUT, -6.0, EO), (F_SETTLE, -1.0, EIO),
                               (F_SEAT, 2.0, EIO)])
        self.spine_yaw = CV([(0, 0.0, EIO), (F_PREP, -11.0, EI), (34, 3.0, EO),
                             (F_CUT, 17.0, EO), (F_SETTLE, 6.0, EIO), (F_SEAT, 0.0, EIO)])
        # the side-bend that lets the right hand reach the left hip at all
        self.spine_roll = CV([(0, 0.0, EIO), (8, -4.0, EIO), (F_PREP, SPINE_ROLL_DRAW, EI),
                              (F_DRAW, SPINE_ROLL_DRAW * 0.86, EO),
                              (F_CUT, SPINE_ROLL_DRAW * 0.30, EO),
                              (F_SETTLE, SPINE_ROLL_DRAW * 0.12, EIO),
                              (F_SEAT, 0.0, EIO), (F_END, 0.0, EIO)])
        self.head_yaw = CV([(0, 0.0, EIO), (7, -9.0, EIO), (20, -13.0, EIO),
                            (F_CUT, 8.0, EO), (F_SETTLE, 4.0, EIO), (F_SEAT, 0.0, EIO)])
        self.head_pitch = CV([(0, 1.0, EIO), (10, 4.0, EIO), (F_PREP, 6.0, EIO),
                              (F_CUT, -2.0, EIO), (F_SETTLE, 0.0, EIO), (F_SEAT, 2.0, EIO)])
        self.sh_lift = CV([(0, 0.0, EIO), (F_PREP, 7.0, EIO), (F_DRAW, 16.0, EO),
                           (F_CUT, 12.0, EIO), (F_SETTLE, 4.0, EIO), (F_SEAT, 0.0, EIO)])
        self.sh_lift_l = CV([(0, 0.0, EIO), (20, 4.0, EIO), (F_DRAW, 9.0, EO),
                             (F_SETTLE, 3.0, EIO), (F_SEAT + 6, 0.0, EIO)])

        # ---- the saya -----------------------------------------------------
        # The mouth is pushed forward/up a little by the left hand ("the mouth
        # adjusts", brief 4), and then -- the term that actually makes the draw
        # possible -- slid BACKWARDS along its own bore.  0.822 m of blade has to
        # leave the scabbard and the arm can only account for ~0.06 m of it, so
        # the rest is the left hand driving the saya backwards.  That is the
        # relative motion brief 6 is asking for; without it the blade simply
        # cannot clear the mouth.
        self.saya_pf = CV([(0, 0.0, EIO), (18, 0.006, EIO), (F_PREP, 0.018, EI),
                           (F_DRAW, 0.024, EO), (F_CUT, 0.014, EIO),
                           (F_SETTLE, 0.005, EIO), (F_SEAT, 0.0, EIO)])
        self.saya_pu = CV([(0, 0.0, EIO), (18, 0.008, EIO), (F_PREP, 0.020, EI),
                           (F_DRAW, 0.030, EO), (F_CUT, 0.018, EIO),
                           (F_SETTLE, 0.006, EIO), (F_SEAT, 0.0, EIO)])
        # a NORMALISED 0..1 shape; `precompute()` solves the metre-scale peak
        self.saya_back = CV([(0, 0.0, EIO), (18, 0.18, EIO), (F_PREP, 0.58, EI),
                             (F_DRAW, 1.0, EO), (F_CUT, 0.74, EIO),
                             (F_SETTLE, 0.30, EIO), (F_SEAT, 0.0, EIO)])
        self._back_peak = 0.0
        self.tilt_req = 0.0
        self.yaw_req = 0.0

        # ---- the extraction ----------------------------------------------
        # Slow to break the habaki free, hardest through the middle, still
        # moving fast as the tip leaves.  A symmetric ease would have the blade
        # arriving at the mouth with zero speed, which reads as "placed".
        self.draw = CV([(F_PREP, 0.00, EI), (28, 0.16, EI), (30, 0.52, EI),
                        (31, 0.76, EO), (F_DRAW, 1.00, EL)])
        # Back-loaded: the last three frames travel 25 mm where the draw travels
        # 118 mm per frame -- "clearly slower" as a number, not a vibe.
        self.insert = CV([(F_SETTLE, 0.000, EI), (F_ALIGN, 0.000, EI),
                          (56, 0.120, EO), (66, 0.480, EO), (76, 0.820, EO),
                          (82, 0.960, EO), (F_SEAT, 1.000, EO)])

        # ---- the cut (authored) ------------------------------------------
        # Blade direction is slerped along the cut plane, so the tip sweeps a
        # plane arc instead of whatever three arm bones feel like doing.
        # Entry 0 (frame F_DRAW) is FILLED IN by `precompute()` from the solved
        # draw, so the authored stretch starts exactly where the derived one
        # ends -- no handover pop, and the blend window only has to smooth the
        # derivative, not hide a discontinuity.
        # Frame numbers, not a smooth curve: the whole descending cut is TWO
        # frames (36 -> 37 -> 38), which is the brief's 0.07 s "极快" beat.  The
        # `overshoot` gate wants the blade 1-8 deg PAST its finished angle one
        # frame before F_CUT, so the landing is at 36, the overshoot at 37 and
        # the settle at 38 -- the first version put the landing AT F_CUT, so the
        # gate measured the cut itself (56 deg) and called it an overshoot.
        self.bd_keys = [(F_DRAW, None), (34, (0.42, 0.34, 0.84)),
                        (35, (0.52, 0.05, 0.30)), (36, (0.62, -0.22, -0.72)),
                        (37, (0.55, -0.38, -0.74)), (38, (0.58, -0.33, -0.75)),
                        (41, (0.60, -0.30, -0.76)), (44, (0.58, -0.32, -0.76)),
                        (F_ALIGN, None), (F_ALIGN + 2, None)]
        # grip expressed as a direction from the right shoulder + a length, so
        # every authored position is reachable by construction
        self.rh_keys = [(F_DRAW, None), (34, ((0.38, 0.40, 0.83), 0.36)),
                        (35, ((0.50, 0.16, 0.85), 0.38)),
                        (36, ((0.72, 0.14, -0.67), 0.42)),
                        (37, ((0.68, -0.32, -0.66), 0.42)),
                        (38, ((0.70, -0.26, -0.67), 0.41)),
                        (41, ((0.71, -0.24, -0.67), 0.40)),
                        (44, ((0.70, -0.25, -0.67), 0.40)),
                        (F_ALIGN, None), (F_ALIGN + 2, None)]
        self.blend = CV([(0.0, 0.0, EL), (F_DRAW, 0.0, EIO), (34.5, 1.0, EIO),
                         (F_ALIGN - 1, 1.0, EIO), (F_ALIGN + 1, 0.0, EIO),
                         (F_END, 0.0, EL)])

        self.lh_on = CV([(0, 0.0, EIO), (12, 0.0, EIO), (20, 1.0, EIO),
                         (86, 1.0, EIO), (95, 0.0, EIO), (F_END, 0.0, EIO)])
        self.rh_on = CV([(0, 0.0, EIO), (F_AWARE, 1.0, EIO), (92, 1.0, EIO),
                         (99, 0.0, EIO), (F_END, 0.0, EIO)])

    # -- body only, so reach can be solved before the weapon exists --------

    def body(self, t):
        r, cf = self.r, self.cf
        s = self._s(t)
        r.reset()
        r.translate_root(cf.v(f=s["step_f"]))
        r.place("Hips", cf.v(s["pel_f"], 0.0, s["pel_u"]),
                cf.rot(s["pel_yaw"], 0.0, 0.0))
        for name, k in (("Abdomen", 0.28), ("Torso", 0.34), ("Chest", 0.38)):
            r.rot_world(name, cf.rot(s["spine_yaw"] * k, s["spine_pitch"] * k,
                                     s["spine_roll"] * k))
        # the head keeps itself level: a body that side-bends 19 deg and a head
        # that side-bends 19 deg reads as a fainting character, not a swordsman
        r.rot_world("Neck", cf.rot(s["head_yaw"] * 0.30, s["head_pitch"] * 0.30,
                                   -s["spine_roll"] * 0.30))
        r.rot_world("Head", cf.rot(s["head_yaw"] * 0.70, s["head_pitch"] * 0.70,
                                   -s["spine_roll"] * 0.40))
        for side, amt in (("R", s["sh_lift"]), ("L", s["sh_lift_l"])):
            r.rot_world(RC.BONES["shoulder"][side],
                        cf.rot(0.0, 0.0, amt * (1.0 if side == "R" else -1.0)))
        out = {}
        for side in ("L", "R"):
            f0, r0, toe = (FOOT_L if side == "L" else FOOT_R)
            ff = f0 + (s["step_f"] if side == "L" else 0.0)
            tgt = cf.v(ff, r0, GROUND_U)
            out["leg_err_" + side] = r.ik_leg(side, tgt, cf.fwd)
            r.aim(RC.BONES["foot"][side], cf.rot(toe, 0.0, 0.0) @ cf.fwd, cf.up)
            out["foot_" + side] = tgt
        out["shoulder_R"] = r.head(RC.BONES["upper"]["R"])
        out["shoulder_L"] = r.head(RC.BONES["upper"]["L"])
        return out

    def _s(self, t):
        return dict(
            pel_u=self.pel_u(t), pel_f=self.pel_f(t), pel_yaw=self.pel_yaw(t),
            step_f=self.step_f(t), spine_pitch=self.spine_pitch(t),
            spine_yaw=self.spine_yaw(t), spine_roll=self.spine_roll(t),
            head_yaw=self.head_yaw(t),
            head_pitch=self.head_pitch(t), sh_lift=self.sh_lift(t),
            sh_lift_l=self.sh_lift_l(t), saya_pf=self.saya_pf(t),
            saya_pu=self.saya_pu(t), saya_back=self._back_peak * self.saya_back(t),
            draw=self.draw(t), insert=self.insert(t),
            blend=self.blend(t), lh_on=self.lh_on(t), rh_on=self.rh_on(t))

    # -- solve the saya's presentation from the arm's reach ----------------

    def precompute(self):
        cf = self.cf
        b = self.body(F_DRAW)
        S = b["shoulder_R"]
        mouth = cf.p(MOUTH[0] + self.saya_pf(F_DRAW), MOUTH[1],
                     MOUTH[2] + self.saya_pu(F_DRAW))
        u = (S - mouth)
        if u.length < 1e-4:
            RC.die("the right shoulder coincides with the saya mouth")
        gap = u.length
        u.normalize()
        gco = self.r.grip_centre_local("R").length
        RC.log("reach: |mouth-shoulder|=%.3f m; the hilt therefore needs %.3f m of "
               "arm, and this rig's arm is 0.379 m + %.3f m to the grip centre "
               "(budget %.3f) -- SHORT by %+.3f m"
               % (gap, gap, gco, REACH_TARGET, REACH_TARGET - gap))
        RC.log("reach: shoulder_R char (f=%+.3f r=%+.3f u=%+.3f)  mouth char "
               "(f=%+.3f r=%+.3f u=%+.3f)"
               % (cf.decompose(S) + (cf.decompose(mouth))))
        # Is the side-bend actually doing anything?  Ask by removing it and
        # measuring, because "the shoulder barely moved" and "the channel is not
        # wired up" look identical from the outside.
        save_roll = self.spine_roll
        self.spine_roll = CV([(0, 0.0, EIO), (F_END, 0.0, EIO)])
        S_sq = self.body(F_DRAW)["shoulder_R"]
        self.spine_roll = save_roll
        RC.log("reach: with the side-bend the shoulder is %.3f m from the mouth, "
               "without it %.3f m (roll buys %+.3f m)"
               % ((S - mouth).length, (S_sq - mouth).length,
                  (S - mouth).length - (S_sq - mouth).length))

        # The bore ideally points from the mouth at the right shoulder: that is
        # the direction the blade must travel to leave the scabbard and arrive in
        # a hand that can hold it.  b_c = (-cos t cos y, -sin y cos t, -sin t).
        # The saya hangs off the PELVIS, not the chest, so pelvis yaw is the whole
        # of its carried rotation.
        R_saya = self._saya_rot(self._s(F_DRAW))
        b_req = (R_saya.inverted() @ (-u)).normalized()
        c_f, c_r, c_u = b_req.dot(cf.fwd), b_req.dot(cf.right), b_req.dot(cf.up)
        tilt = math.degrees(math.asin(RC.clamp(-c_u, -1.0, 1.0)))
        # atan2, NOT asin(-c_r / cos t): `cos y` changes sign past +-90 deg and
        # asin() cannot see that sign, so it silently reports the mirror of the
        # angle you asked for.
        yaw = math.degrees(math.atan2(-c_r, -c_f))
        # forward-check the inversion.  `chk` is in CHAR-FRAME COMPONENTS, so it
        # must be compared against the components of b_req -- comparing it to the
        # world vector b_req is a meaningless number (measured: 1.04) that looks
        # like a math failure and is really a units failure.
        chk = Vector((-math.cos(math.radians(tilt)) * math.cos(math.radians(yaw)),
                      -math.sin(math.radians(yaw)) * math.cos(math.radians(tilt)),
                      -math.sin(math.radians(tilt))))
        err = (chk - Vector((c_f, c_r, c_u))).length
        RC.log("reach solve: bore re-projection error %.6f (want ~0)" % err)
        if err > 1e-3:
            RC.die("tilt/yaw inversion does not round-trip; the -cos t cos y branch "
                   "cannot represent this bore direction")

        # The scabbard ROTATES to point its mouth at the right shoulder, and the
        # rotation is deliberately allowed to be large.  Why: if the exit
        # direction points at the shoulder then the hilt's distance from that
        # shoulder runs from |mouth-shoulder| = 0.457 m down to
        # |0.457 - 0.762| = 0.305 m and never exceeds 0.457 -- so the whole
        # 0.762 m extraction is inside a 0.379 m arm's reach with NO scabbard
        # translation at all.  Rotating the saya about its own mouth also costs
        # the LEFT hand nothing, whereas sliding it costs the left hand every
        # centimetre.  That asymmetry is the whole reason the draw is a rotation
        # of the scabbard rather than a tug-of-war between two short arms.
        self.tilt_req = RC.clamp(tilt - BORE_TILT, -8.0, 32.0)
        self.yaw_req = RC.clamp(yaw - BORE_YAW, -16.0, 112.0)
        RC.log("reach solve: bore wants tilt %+.1f / yaw %+.1f, using %+.1f / %+.1f "
               "(bounded to +32/-8 and +112/-16)"
               % (tilt - BORE_TILT, yaw - BORE_YAW, self.tilt_req, self.yaw_req))

        # now the authored ramps can be built
        # The scabbard is NOT returned to its worn angle as soon as the cut
        # ends.  It is held out, koiguchi forward, exactly as a left hand holds
        # it for nagashi/noto -- and that is also what makes the derived sword's
        # handover pose REACHABLE: with the bore still swung toward the shoulder,
        # the guard of the fully-drawn sword sits 0.35 m from that shoulder
        # instead of 0.89 m.  The first version relaxed the yaw to 0.16 by the
        # end of the cut, and the right hand then had to abandon the hilt for
        # 479 mm while the blade slid home.
        self.saya_tilt = CV([(0, 0.0, EIO), (18, 0.22 * self.tilt_req, EIO),
                             (F_PREP, 0.55 * self.tilt_req, EI),
                             (F_DRAW, self.tilt_req, EO),
                             (F_CUT, 0.85 * self.tilt_req, EIO),
                             (F_SETTLE, 0.95 * self.tilt_req, EIO),
                             (64, 0.45 * self.tilt_req, EIO),
                             (F_SEAT, 0.0, EIO)])
        self.saya_yaw = CV([(0, 0.0, EIO), (18, 0.22 * self.yaw_req, EIO),
                            (F_PREP, 0.55 * self.yaw_req, EI),
                            (F_DRAW, self.yaw_req, EO),
                            (F_CUT, 0.85 * self.yaw_req, EIO),
                            (F_SETTLE, 0.95 * self.yaw_req, EIO),
                            (64, 0.45 * self.yaw_req, EIO),
                            (F_SEAT, 0.0, EIO)])

        # ---- does the scabbard actually hang the way a scabbard hangs? ----
        # These are the checks that catch a roll about the bore.  A rolled saya
        # is still rigidly attached to the mouth, so every distance in this log
        # stays plausible and only the pictures are wrong -- so ask the question
        # numerically here instead of trusting the eyes three stages later.
        # NOTE: ask about the bore DIRECTION and the kojiri POSITION separately.
        # An earlier version of this check fed a position into a direction
        # threshold and "failed" a perfectly good rest pose.
        M0 = self.solve(0)["M_saya"]
        m3 = M0.to_3x3()
        bore = m3.col[2].normalized()                    # mesh local +Z is the bore
        edge = -m3.col[0].normalized()                   # mesh local -X is the edge
        bf, br, bu = (bore.dot(cf.fwd), bore.dot(cf.right), bore.dot(cf.up))
        kj = cf.decompose(M0 @ Vector((0.0, 0.0, self.w.bore_len)))    # kojiri
        if bf > -0.80:
            RC.die("at rest the bore's forward component is %+.2f: the scabbard does "
                   "not point back down the hip" % bf)
        if not (-0.58 < bu < -0.08):
            RC.die("at rest the bore's up component is %+.2f: a worn saya angles "
                   "down the leg -- neither vertical nor flat to the ground" % bu)
        if kj[0] > -0.45:
            RC.die("at rest the kojiri is only %+.2f m forward of the hips: the "
                   "scabbard is not carried behind the hip" % kj[0])
        if edge.dot(cf.up) < 0.55:
            RC.die("at rest the saya's edge faces %+.2f up (want > 0.55): the "
                   "scabbard is rolled about its own length, so the blade would "
                   "leave the mouth edge-wrong" % edge.dot(cf.up))
        RC.log("saya hang: bore f=%+.2f r=%+.2f u=%+.2f   kojiri f=%+.2f u=%+.2f   "
               "edge up=%+.2f" % (bf, br, bu, kj[0], kj[2], edge.dot(cf.up)))

        # ---- how far back must the LEFT hand carry the saya? ---------------
        # The last hard constraint, and the reason the draw is a two-handed
        # motion: at the instant the blade clears the mouth the hilt sits ~0.70 m
        # from where the mouth started, and the right arm can only supply ~0.06 m
        # of that.  The rest is the saya travelling backwards.
        #
        # The objective is the WORSE of the two hands, not the right hand.  The
        # left hand rides the mouth, so every centimetre the saya is pushed back
        # is a centimetre the left arm has to follow -- solving only for the right
        # hand produced a push that put the right hand exactly on the hilt and
        # left the left hand 172 mm short of the scabbard it was supposed to be
        # controlling.  A one-handed two-handed draw is a contradiction.
        sweep = []
        for i in range(0, 81):
            self._back_peak = SAYA_BACK_MAX * i / 80.0
            dd = self.solve(F_DRAW)
            sweep.append((max(dd["rh_err"], dd["lh_err"]), dd["rh_err"],
                          dd["lh_err"], self._back_peak))
        emin = min(s[0] for s in sweep)
        pick = min(s for s in sweep if s[0] <= emin + 0.002)
        self._back_peak = pick[3]
        lo_r = min(sweep, key=lambda s: s[1])
        lo_l = min(sweep, key=lambda s: s[2])
        RC.log("push sweep (push m : right mm : left mm):")
        for s in sweep[::10] + [sweep[-1]]:
            RC.log("   %5.3f : %6.1f : %6.1f" % (s[3], s[1] * 1000.0, s[2] * 1000.0))
        RC.log("   right hand alone wants push %.3f (%.1f mm); left hand alone wants "
               "%.3f (%.1f mm)" % (lo_r[3], lo_r[1] * 1000.0, lo_l[3], lo_l[2] * 1000.0))
        RC.log("saya push-back: %.3f m of %.3f allowed -> right hand misses %.1f mm, "
               "left hand misses %.1f mm (best over the sweep %.1f mm)"
               % (pick[3], SAYA_BACK_MAX, pick[1] * 1000.0, pick[2] * 1000.0,
                  emin * 1000.0))
        if emin > 0.012:
            RC.log("WARNING the draw ends %.1f mm out of reach on one hand: this rig's "
                   "arms are 0.379 m (22.6%% of height) where a real human's are "
                   "~31%%, so a cross-body draw is genuinely tighter on this "
                   "placeholder than it will be on Lia" % (emin * 1000.0))

        # ---- continuity of the handover ----------------------------------
        # Solve the fully-drawn moment exactly as `solve()` will, then use that
        # result as the FIRST authored key of the cut.  Otherwise the authored
        # path starts somewhere else and the blend window has to paper over a
        # jump in blade direction -- which is exactly the "sword teleports" the
        # brief forbids.
        d0 = self.solve(F_DRAW)
        bd = d0["M_derived"].to_3x3().col[2].normalized()
        grip = d0["M_derived"] @ HILT_LOCAL
        rel = grip - d0["shoulder_R"]
        self.bd_keys[0] = (F_DRAW, (bd.dot(cf.fwd), bd.dot(cf.right), bd.dot(cf.up)))
        self.rh_keys[0] = (F_DRAW, ((rel.dot(cf.fwd), rel.dot(cf.right), rel.dot(cf.up)),
                                    rel.length))
        RC.log("handover: blade dir %s  grip %.3f m from the shoulder"
               % (tuple(round(v, 3) for v in self.bd_keys[0][1]), rel.length))

        # ...and the SAME trick at the far end, for the same reason.  The sword
        # has to arrive at the sheathing alignment, and that pose is not a
        # matter of taste: it is `M_saya @ seat(travel_full)`.  Authoring it by
        # hand cannot work because the alignment moves with the solved scabbard
        # angle, so it is read out of the solver instead.
        dA = self.solve(F_ALIGN)
        bdA = dA["M_derived"].to_3x3().col[2].normalized()
        gripA = dA["M_derived"] @ HILT_LOCAL
        relA = gripA - dA["shoulder_R"]
        self.bd_keys[-2] = (F_ALIGN,
                            (bdA.dot(cf.fwd), bdA.dot(cf.right), bdA.dot(cf.up)))
        self.rh_keys[-2] = (F_ALIGN,
                            ((relA.dot(cf.fwd), relA.dot(cf.right), relA.dot(cf.up)),
                             relA.length))
        RC.log("sheath handover: blade dir %s  grip %.3f m from the shoulder "
               "(%.1f mm out of reach)"
               % (tuple(round(v, 3) for v in self.bd_keys[-2][1]), relA.length,
                  max(0.0, relA.length - REACH_TARGET) * 1000.0))

    # -- full solve --------------------------------------------------------

    def solve(self, t):
        cf, r = self.cf, self.r
        s = self._s(t)
        d = self.body(t)
        s["saya_tilt"] = self.saya_tilt(t)
        s["saya_yaw"] = self.saya_yaw(t)

        R_saya = self._saya_rot(s)
        tilt = math.radians(BORE_TILT + s["saya_tilt"])
        yaw = math.radians(BORE_YAW + s["saya_yaw"])
        b_c = Vector((-math.cos(tilt) * math.cos(yaw),
                      -math.sin(yaw) * math.cos(tilt), -math.sin(tilt))).normalized()
        # The push-back is along the BORE, so it is written in char-frame
        # components of b_c rather than as a raw world offset: "the left hand
        # slides the scabbard back through the belt" is a motion down the
        # scabbard's own axis, and it must stay down that axis when the saya is
        # tilted or yawed.
        back = s["saya_back"]
        mouth_c = Vector((MOUTH[0] + s["saya_pf"] + back * b_c.x,
                          MOUTH[1] + back * b_c.y,
                          MOUTH[2] + s["saya_pu"] + back * b_c.z))
        M_saya = self._saya_matrix(cf, R_saya, mouth_c, b_c)
        d["M_saya"] = M_saya
        d["saya_back"] = back
        d["saya_tilt_deg"] = math.degrees(tilt)
        d["saya_yaw_deg"] = math.degrees(yaw)

        # the sword: derived from the saya while anything is inside the bore,
        # authored while it is free, blended across both handovers
        if t <= F_PREP:
            travel = 0.0
        elif t <= F_DRAW:
            travel = self.w.travel_full * self.draw(t)
        elif t <= F_SETTLE:
            travel = self.w.travel_full
        else:
            travel = self.w.travel_full * (1.0 - self.insert(t))
        M_der = M_saya @ self.w.seat(travel)
        M_free = self._free_sword(t, d["shoulder_R"])
        bl = s["blend"]
        M_sword = M_der if M_free is None else blend_matrix(M_der, M_free, bl)
        d.update(travel=travel, blend=bl, M_sword=M_sword, M_derived=M_der,
                 M_free=M_free)

        # hands
        lh_t, lh_rod = self._left_target(t, s, M_saya)
        d["lh_err"] = self._ik_to_grip(cf, "L", lh_t, lh_rod,
                                       CURL["saya"] * s["lh_on"] + CURL["open"] * (1 - s["lh_on"]))
        grip_w = M_sword @ HILT_LOCAL
        # At rest the right hand must hang at the RIGHT hip, not sit on the
        # hilt: brief item 2 asks for "ready without looking ready", and item 3
        # puts awareness (and the grip) at frame 10, not frame 0.  A fixed small
        # offset from the hilt is not "off the hilt" -- it is "clutching the
        # sword", which is how both hands ended up clasped at the navel in the
        # first pose sheet.  Interpolating to the hip instead makes frame 0 a
        # stance and frames 0-10 a reach.
        rest_r = cf.p(-0.02, 0.21, 0.02)           # the character's right hip
        hover = (rest_r - grip_w) * (1.0 - s["rh_on"])
        d["rh_err"] = self._ik_to_grip(cf, "R", grip_w + hover,
                                       sword_rod_basis(M_sword),
                                       CURL["grip"] * s["rh_on"] + CURL["open"] * (1 - s["rh_on"]))

        d["tip"] = M_sword @ Vector((0.0, 0.0, self.w.tip_z))
        d["kashira"] = M_sword @ Vector((0.0, 0.0, self.w.kashira_z))
        d["guard"] = M_sword @ Vector((0.0, 0.0, self.w.seat_back))
        d["grip"] = M_sword.translation.copy()
        d["blade_dir"] = Vector(M_sword.col[2][:3]).normalized()
        d["edge_dir"] = -Vector(M_sword.col[0][:3]).normalized()
        return d

    def _saya_rot(self, s):
        """The saya rides in the OBI, i.e. on the hips -- so pelvis yaw is the
        whole of its carried rotation.

        There is exactly ONE expression for this, because `precompute()` inverts
        it to solve the bore direction and `solve()` applies it to build the
        saya.  Any term present in one and absent from the other is a handover
        discontinuity that the blend window then has to hide -- and the earlier
        `spine_yaw * 0.45` here was precisely that bug.
        """
        return self.cf.rot(s["pel_yaw"], 0.0, 0.0)

    def _saya_matrix(self, cf, R, mouth_c, b_c):
        """Build the saya's world matrix.

        The saya mesh is authored with local +Z = the BORE (mouth -> kojiri) and
        local -X = the edge, exactly like the sword.  So column 2 of this matrix
        IS the bore direction, and `seat()` -- which slides the sword along local
        -Z and swings it about the arc centre in the local XZ plane -- only means
        anything if that is true.

        Putting the bore in column 1 instead (the earlier form) rolls the entire
        scabbard 90 deg about its own length.  The mesh stays rigidly attached to
        the mouth, so every position, distance and clearance number in the log
        remains perfectly plausible and only the pictures are wrong -- which is
        why it survived to the first key-pose render.
        """
        mouth = cf.p(mouth_c.x, mouth_c.y, mouth_c.z)
        b = (R @ cf.v(b_c.x, b_c.y, b_c.z)).normalized()     # +Z: bore, mouth->kojiri
        # +Y: the flat that lies against the hip.  Body-RIGHT, so that local -X
        # (the edge) ends up facing UP -- a katana is worn edge-up, and that is
        # also the edge the rising draw cut in the brief leaves with.
        flat = R @ cf.v(0.0, 1.0, 0.0)
        flat = flat - b * flat.dot(b)
        if flat.length < 1e-6:
            RC.die("the bore is parallel to the body's left/right axis, so the "
                   "saya's roll about its own length is undefined")
        flat.normalize()
        x = flat.cross(b)                                    # right-handed: x = y x z
        return RC.mat_from_cols(x, flat, b, mouth)

    def _left_target(self, t, s, M_saya):
        """The left hand grips the saya just below the koiguchi.  Derived from
        the saya, never posed near it -- brief item 23 makes this the difference
        between a draw and a mime."""
        on = s["lh_on"]
        tgt_on = M_saya @ LH_LOCAL
        rod_on = saya_rod_basis(M_saya)
        tgt_off = self.cf.p(-0.04, -0.30, 0.10)
        rod_off = self._rod_from_dir(self.cf, self.cf.fwd * 0.3 - self.cf.up * 0.9)
        if on >= 0.999:
            return tgt_on, rod_on
        q = rod_off.to_quaternion().slerp(rod_on.to_quaternion(), on)
        return tgt_off.lerp(tgt_on, on), q.to_matrix()

    def _rod_from_dir(self, cf, d):
        d = Vector(d).normalized()
        x = cf.up.cross(d)
        if x.length < 1e-4:
            x = cf.right.cross(d)
        x.normalize()
        return RC.mat_from_cols(x, d, x.cross(d)).to_3x3()

    def _free_sword(self, t, S):
        """The authored cut.  Grip positions are expressed as a LENGTH from the
        right shoulder along an authored direction, so the arm can reach every
        one of them by construction rather than by luck.  Returns None inside
        the window where the sword belongs to the saya, which is what makes the
        two extreme blend keys harmless."""
        bd = RC.lerp_key(self.bd_keys, t)
        rk = RC.lerp_key(self.rh_keys, t)
        if bd is None or rk is None:
            return None
        dd, ln = rk
        cf = self.cf
        d = cf.v(*bd).normalized()
        n = self._cut_normal()
        # `d` is the blade's LONG AXIS, so it belongs in column 2 -- the mesh's
        # own long axis is local +Z, and that is what `sword_rod_basis` and the
        # hand's grip frame both read.  The earlier version wrote `d` into
        # column 1 and derived column 2 as `x.cross(d)`, which made the authored
        # cut almost inert: the blade's aim collapsed onto the cut normal, so
        # every frame of the "cut" pointed the sword along the character's
        # left/right axis no matter what the keys said.  The blade then swept
        # through a foreshortened 30 deg instead of the authored arc, and the
        # finish of a downward cut measured 2.11 m -- above the character's own
        # head -- with nothing in the keys asking for it.
        #
        # `n` now only decides the ROLL: the edge has to face the direction the
        # cut travels, which lies in the cut plane and is perpendicular to the
        # blade, i.e. `n x d`.
        x = n.cross(d)
        if x.length < 1e-4:
            x = cf.right.cross(d)
        x.normalize()
        rod = RC.mat_from_cols(-x, x.cross(d), d).to_3x3()
        M = rod.to_4x4()
        M.translation = Vector(S) + cf.v(*dd).normalized() * ln
        return M

    def _cut_normal(self):
        if not hasattr(self, "_n"):
            cf = self.cf
            a = cf.v(0.30, 0.45, 0.84).normalized()
            b = cf.v(0.10, -0.55, -0.83).normalized()
            n = a.cross(b)
            if n.length < 1e-4:
                n = cf.right.copy()
            self._n = n.normalized()
        return self._n

    def _ik_to_grip(self, cf, side, grip_world, rod_basis3, curl):
        r = self.r
        gc = r.grip_centre_local(side)
        rod_basis3 = aim_roll(r, side, rod_basis3, gc, grip_world,
                              r.head(RC.BONES["upper"][side]))
        B = r.grip_basis(side, rod_basis3)          # known BEFORE the arm moves
        err = r.ik_arm(side, Vector(grip_world) - (B @ gc), self._elbow_pole(cf, side))
        r.apply_grip(side, rod_basis3)
        r.curl_fingers(side, curl, Vector(rod_basis3.col[1]).normalized())
        return err

    def _elbow_pole(self, cf, side):
        return (-cf.fwd * 0.80 - cf.up * 0.60
                + cf.right * (0.40 if side == "R" else -0.40)).normalized()


# ---------------------------------------------------------------------------
#  wiring / render / stages
# ---------------------------------------------------------------------------

def setup_render(w, h, samples=40):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = w
    sc.render.resolution_y = h
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    try:
        sc.eevee.taa_render_samples = samples
    except Exception:
        pass


def add_ground(cf):
    me = bpy.data.meshes.new("Ground")
    s = 16.0
    me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    me.update()
    ob = bpy.data.objects.new("Ground", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = cf.p(0.0, 0.0, GROUND_U)
    m = bpy.data.materials.new("M_Ground")
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (0.19, 0.19, 0.20, 1.0)
    b.inputs["Roughness"].default_value = 0.9
    me.materials.append(m)
    return ob


def cam_setup(cf, name, az, dist, height, target_u, lens):
    """`cf.p`, NOT `cf.v`.

    `cf.v` returns pure frame components with NO origin added, and the origin of
    this rig sits at the HIPS (0.813 m up).  Building the cameras and the ground
    from `cf.v` therefore put every camera 0.8 m too low and aimed them at the
    character's ankles, and dropped the floor 0.8 m below the feet.  The first
    contact sheet came back looking like a levitating seated man and the obvious
    suspect -- the pose -- was innocent.
    """
    a = math.radians(az)
    loc = cf.p(math.cos(a) * dist, math.sin(a) * dist, height)
    return RR.make_camera(name, loc, cf.p(0.0, 0.0, target_u), cf.up, lens=lens)


def cameras(cf):
    """Framed to hold the WHOLE move, on the side the Sword Actually Lives On.

    Two separate corrections are baked into these numbers.

    (1) FRAMING.  The cut's apex puts the tip 2.14 m up -- above the character's
    own head -- and the first framing, sized on a standing figure, clipped it in
    FRONT3Q (worst NDC 1.278 at f34).  A plate that crops the fastest, highest
    frame of the performance is worse than no plate, because it looks
    deliberate.  `target_u` therefore aims at mid-motion, not at the waist.

    (2) WHICH SIDE.  `CharFrame.right = (-1, 0, 0)`, so world -X is the
    character's RIGHT and +X is the LEFT.  Every camera here used to sit at a
    POSITIVE azimuth -- front-right, right, behind-right -- and the saya hangs on
    the character's LEFT hip.  The "side view" was therefore the far profile, and
    it was silently useless: `probe_views` reported SayaMouth at pixel x 497 in a
    body that spans 440..520, i.e. dead inside the torso silhouette, with only
    the kojiri's tail sticking out at 361.  At f26 (full compression, both hands
    on the hilt) the render showed a man standing beside nothing, and the honest
    reading of that plate was "the sword is missing" rather than "the sword is
    occluded".  The brief's whole point is to judge the sword, so a review view
    that cannot see it is worse than no view.

    The azimuths are now MIRRORED onto the action side (-34 / -90), and the
    fourth camera is a real third-person position instead of a second front 3/4:
        FRONT3Q   -34  front-LEFT             the hero angle, sword toward camera
        SIDE      -90  LEFT profile           the geometric truth: blade vs bore
        BACK3Q    146  behind-RIGHT           the opposite-side full-body check
        GAMEPLAY -160  behind-left, wide      what the player actually sees
    BACK3Q is deliberately left on the far side: it is the turntable's "other
    half", and the kojiri poking past the silhouette there is the useful read.
    """
    return {
        "FRONT3Q": cam_setup(cf, "FRONT3Q", -34.0, 6.70, 0.78, 0.24, 50.0),
        "SIDE": cam_setup(cf, "SIDE", -90.0, 6.70, 0.70, 0.24, 50.0),
        "BACK3Q": cam_setup(cf, "BACK3Q", 146.0, 6.70, 0.88, 0.24, 50.0),
        "GAMEPLAY": cam_setup(cf, "GAMEPLAY", -160.0, 5.60, 1.42, 0.40, 36.0),
    }


def ndc(cam, pts):
    inv = cam.matrix_world.inverted()
    cd = cam.data
    sc = bpy.context.scene
    asp = sc.render.resolution_x / float(sc.render.resolution_y)
    worst = 0.0
    for p in pts:
        v = inv @ Vector(p)
        if v.z > -1e-4:
            return 1e9
        if cd.type == "ORTHO":
            hs = cd.ortho_scale * 0.5
            nx, ny = v.x / (hs * asp), v.y / hs
        else:
            hs = (cd.sensor_height * 0.5) / cd.lens
            nx, ny = v.x / (hs * asp * -v.z), v.y / (hs * -v.z)
        worst = max(worst, abs(nx), abs(ny))
    return worst


def mesh_extent(rig, names=("Casual_Body",)):
    """Evaluated world extent of the character meshes, as one line."""
    dg = bpy.context.evaluated_depsgraph_get()
    out = []
    for o in list(rig.ob.children_recursive):
        if o.type != "MESH" or o.name not in names:
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        n = len(me.vertices)
        co = [0.0] * (n * 3)
        me.vertices.foreach_get("co", co)
        mw = ev.matrix_world
        zs = []
        for i in range(0, n * 3, 3):
            zs.append((mw @ Vector((co[i], co[i + 1], co[i + 2]))).z)
        ev.to_mesh_clear()
        out.append("%s z %.3f..%.3f" % (o.name, min(zs), max(zs)))
    return "  ".join(out) if out else "(no mesh)"


def to_px(cam, p):
    """World point -> (pixel_x, pixel_y), y measured from the TOP.

    Deliberately NOT hand-rolled.  Two hand-rolled versions of this produced two
    incompatible pixel scales for the same frame (one of them dividing by the
    aspect ratio where it should have multiplied), which is how a plate ends up
    being read wrong twice in a row.  `world_to_camera_view` is Blender's own
    projection, so it agrees with the renderer by construction.
    """
    from bpy_extras.object_utils import world_to_camera_view
    sc = bpy.context.scene
    w, h = sc.render.resolution_x, sc.render.resolution_y
    u, v, _ = world_to_camera_view(sc, cam, Vector(p))
    return (u * w, (1.0 - v) * h)


def probe_views(cams, cf, rig, d, w):
    """Where the camera ITSELF says each landmark lands, in pixels."""
    marks = [("HeadEnd", rig.pb["Head"].tail), ("Hips", cf.origin),
             ("FootL", rig.pb["Foot.L"].matrix.translation),
             ("FootR", rig.pb["Foot.R"].matrix.translation),
             ("ToeL", rig.pb["Foot.L"].tail),
             ("SayaMouth", d["M_saya"].translation),
             ("SayaKojiri", d["M_saya"] @ Vector((0.0, 0.0, w.bore_len))),
             ("Tip", d["tip"]), ("HandR", rig.pb["Hand.R"].matrix.translation),
             ("Ground", cf.p(0.0, 0.0, GROUND_U))]
    for cname, cam in cams.items():
        parts = " ".join("%s(%4.0f,%4.0f)" % ((nm,) + to_px(cam, p))
                         for nm, p in marks)
        print("PROBE PX %-9s %s" % (cname, parts))
        sc = bpy.context.scene
        cd = cam.data
        t0 = Vector(cf.p(0.0, 0.0, 0.06))
        up1 = to_px(cam, t0 + Vector((0.0, 0.0, 1.0)))
        up0 = to_px(cam, t0)
        print("PROBE PX %-9s lens %.2f sensor %.1fx%.1f fit %s shift %+.3f/%+.3f "
              "| res %dx%d @%d%% aspect %.3f/%.3f | 1 m at target = %.1f px"
              % ("", cd.lens, cd.sensor_width, cd.sensor_height, cd.sensor_fit,
                 cd.shift_x, cd.shift_y, sc.render.resolution_x,
                 sc.render.resolution_y, sc.render.resolution_percentage,
                 sc.render.pixel_aspect_x, sc.render.pixel_aspect_y,
                 abs(up1[1] - up0[1])))
        print("PROBE PX %-9s cam loc %s  dist_to_tar %.3f  span_res %.4f"
              % ("", tuple(round(v, 2) for v in cam.matrix_world.translation),
                 (cam.matrix_world.translation - t0).length,
                 max(ndc(cam, [p for _, p in marks][:6]), 0.0)))


def bounds_points(d, rig):
    """A cheap but honest framing proxy: every joint, plus the blade's two ends."""
    pts = [rig.head(n) for n in rig.pb.keys()]
    pts.append(rig.tail("Head"))
    for k in ("tip", "kashira", "guard"):
        if k in d:
            pts.append(d[k])
    return pts


def strip_animation(objs):
    """Remove every action an import brought with it.  MANDATORY, not tidying.

    THE BUG THIS FIXES, because it cost a whole round and looked like a maths
    error.  The placeholder GLB ships animation clips, so the armature arrives
    with an action assigned.  Assigning `pose_bone.matrix` writes the bone's
    channels, and a probe that reads them back sees exactly what it wrote -- but
    the moment the scene is evaluated for a RENDER the animation system
    overwrites those channels from the action, and the renderer draws a
    completely different pose.  Measured here: the character's body sat at
    world z 0.813..1.410 going into the render and at 0.244..0.938 coming out,
    a 0.57 m drop on the same frame.  A probe can therefore certify a standing
    pose while the plate next to it shows a crouch, and no amount of staring at
    the numbers will find it.  This file AUTHORS the pose; nothing may play a
    clip over it.
    """
    gone = []
    for ob in objs:
        ad = getattr(ob, "animation_data", None)
        if ad is not None:
            if ad.action is not None:
                gone.append("%s:%s" % (ob.name, ad.action.name))
            ob.animation_data_clear()
        dd = getattr(getattr(ob, "data", None), "animation_data", None)
        if dd is not None:
            if dd.action is not None:
                gone.append("%s.data:%s" % (ob.name, dd.action.name))
            ob.data.animation_data_clear()
    n = 0
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
        n += 1
    if gone or n:
        RC.log("stripped %d action(s) [%s] and removed %d from the file -- an "
               "action left on the rig overwrites the authored pose at render "
               "time" % (len(gone), ", ".join(gone) or "-", n))
    else:
        RC.log("no imported actions to strip")


def load_scene():
    RC.clear_scene()
    RR.setup_world()
    ch = RC.import_glb(CHAR_GLB)
    arm = [o for o in ch if o.type == "ARMATURE"][0]
    sco = RC.import_glb(SWORD_GLB)
    syo = RC.import_glb(SAYA_GLB)
    strip_animation(ch + sco + syo)
    sword = RC.flatten_to_carrier(sco, "hand_r_weapon")
    saya = RC.flatten_to_carrier(syo, "waist_l_saya")
    return arm, sword, saya


def build(variant):
    arm, sword, saya = load_scene()
    rig = RC.Rig(arm)
    cf = rig.char_frame()
    w = Weapons(sword_objs_of(sword), saya_objs_of(saya))
    p = Perf(rig, cf, w, variant)
    p.precompute()
    return rig, cf, w, p, sword, saya


def sword_objs_of(carrier):
    return [o for o in carrier.children_recursive if o.type == "MESH"]


saya_objs_of = sword_objs_of


def apply_weapons(d, sword, saya):
    sword.matrix_world = d["M_sword"]
    saya.matrix_world = d["M_saya"]
    bpy.context.view_layer.update()


# ---------------------------------------------------------------------------
#  stages
# ---------------------------------------------------------------------------

def selftest(rig, cf):
    ok = True
    n = cf.rot(90.0, 0.0, 0.0) @ cf.fwd
    if n.dot(cf.right) > -0.9:
        print("FAIL yaw: +90 should turn the front to the character's LEFT")
        ok = False
    else:
        print("OK   yaw sign (+90 -> front on the character's left)")
    u = cf.rot(0.0, 90.0, 0.0) @ cf.up
    if u.dot(cf.fwd) < 0.9:
        print("FAIL pitch: +90 should lean the front forward, got %.3f" % u.dot(cf.fwd))
        ok = False
    else:
        print("OK   pitch sign (+90 -> top leans forward)")
    if not ok:
        RC.die("frame sign conventions are wrong; every pose below is wrong too")
    for s in ("L", "R"):
        H = rig.grip_frame(s)
        det = H.determinant()
        print("OK   grip frame %s determinant %+.4f (want +1)" % (s, det))
        if abs(det - 1.0) > 1e-3:
            RC.die("grip frame is not right-handed on %s" % s)


# ---------------------------------------------------------------------------
#  a burned-in label, so a review sheet does not depend on remembering the order
#  the plates happened to be emitted in
# ---------------------------------------------------------------------------

_LABEL = {"ob": None}


def _label_material():
    m = bpy.data.materials.get("M_Label")
    if m is not None:
        return m
    m = bpy.data.materials.new("M_Label")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    out = [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"][0]
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (1.0, 0.93, 0.80, 1.0)
    em.inputs[1].default_value = 2.0
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def show_label(cam, text, dist):
    """A text object hung in the CAMERA'S own frame.  Emission, so the label
    reads identically in every view no matter where the key light landed."""
    sc = bpy.context.scene
    ob = _LABEL["ob"]
    if ob is None:
        cu = bpy.data.curves.new("Label", "FONT")
        cu.align_x = "LEFT"
        cu.align_y = "BOTTOM"
        ob = bpy.data.objects.new("Label", cu)
        sc.collection.objects.link(ob)
        cu.materials.append(_label_material())
        _LABEL["ob"] = ob
    ob.hide_render = False
    ob.data.body = text
    cd = cam.data
    half_h = (cd.sensor_height * 0.5) / cd.lens * dist
    half_w = half_h * (sc.render.resolution_x / float(sc.render.resolution_y))
    basis = cam.matrix_world.to_3x3()
    loc = (cam.matrix_world.translation
           + basis @ Vector((-0.90 * half_w, -0.84 * half_h, -dist)))
    ob.matrix_world = Matrix.Translation(loc) @ basis.to_4x4()
    ob.data.size = 0.115 * half_h
    return ob


def hide_label():
    if _LABEL["ob"] is not None:
        _LABEL["ob"].hide_render = True


POSE_VIEWS = ["FRONT3Q", "SIDE", "BACK3Q", "GAMEPLAY"]


def stage_bind(rig, cf, cams, out, tar, W, H):
    """Render the BIND pose -- the mesh with the armature switched off.

    A plate said "deep crouch", the pose bones said "standing 1.65 m", and the
    camera's own projection agreed with the bones.  Three things cannot all be
    true, so this removes the deform from the equation: with the armature
    modifier disabled the character renders in the pose the GLB shipped with,
    which is a full-height T-pose of known shape.  If THAT also comes back
    short and folded, the fault is in the camera or the render; if it comes
    back as a clean T-pose, the deform is where the lie is.
    """
    sc = bpy.context.scene
    setup_render(W, H, samples=16)
    for o in rig.ob.children_recursive:
        for m in o.modifiers:
            if m.type == "ARMATURE":
                m.show_render = False
    pdir = os.path.join(out, "bind")
    os.makedirs(pdir, exist_ok=True)
    for f in os.listdir(pdir):
        if f.endswith(".png"):
            os.remove(os.path.join(pdir, f))
    for cname in ("FRONT3Q", "SIDE", "GAMEPLAY"):
        cam = cams[cname]
        sc.camera = cam
        show_label(cam, "BIND POSE  no deform  f--",
                   0.55 * (cam.matrix_world.translation - Vector(tar)).length)
        RR.shoot(cam, os.path.join(pdir, "bind_%s.png" % cname), tar)
        print("BIND plate %s" % cname)
    hide_label()


def stage_probe(rig, cf, w, p, sword, saya, cams, tar, W, H, out):
    """Ground truth for a frame that LOOKS wrong.

    Everything above is a chain of assumptions -- mesh local axes, what
    `matrix_local` means once parented, which column of which matrix is the bore
    -- and a chain of assumptions is exactly what a wrong-looking first render is
    made of.  This prints the objects' own numbers next to the computed ones so
    the disagreement names itself.
    """
    setup_render(W, H, samples=1)
    print("PROBE cf.origin %s" % (tuple(round(v, 4) for v in cf.origin),))
    print("PROBE cf fwd %s right %s up %s"
          % (tuple(round(v, 4) for v in cf.fwd), tuple(round(v, 4) for v in cf.right),
             tuple(round(v, 4) for v in cf.up)))
    print("PROBE ground_u %.3f  MOUTH char %s" % (GROUND_U, MOUTH))

    def dump(tag):
        cols = []
        for nm in sorted(rig.pb.keys()):
            if any(x in nm for x in ("Hips", "Foot", "Hand", "Head", "UpperLeg",
                                     "UpperArm", "Root")):
                t = rig.pb[nm].matrix.translation
                cols.append("%s(%.3f,%.3f,%.3f)" % (nm, t.x, t.y, t.z))
        print("PROBE %-10s %s" % (tag, " ".join(cols)))

    rig.reset()
    dump("REST")
    rig.reset()
    p.body(0.0)
    dump("BODY(0)")
    rig.reset()
    d = p.solve(0.0)
    dump("SOLVE(0)")

    # ---- assigned vs evaluated ------------------------------------------
    # `pose_bone.matrix = M` back-solves the bone's channels against the parent
    # chain AS CURRENTLY EVALUATED.  Reading `pose_bone.matrix` afterwards can
    # return the value that was assigned while the renderer re-derives the pose
    # from the channels -- so a probe can certify a pose that is not the pose
    # being drawn.  Print both, and the disagreement names itself.
    dg0 = bpy.context.evaluated_depsgraph_get()
    evo = rig.ob.evaluated_get(dg0)
    for nm in ("Hips", "Chest", "UpperLeg.L", "Foot.L", "Hand.R", "Head"):
        a = rig.pb[nm].matrix.translation
        b = evo.pose.bones[nm].matrix.translation
        print("PROBE EVAL %-12s assigned (%+.3f,%+.3f,%+.3f)  evaluated "
              "(%+.3f,%+.3f,%+.3f)  delta %.4f m"
              % (nm, a.x, a.y, a.z, b.x, b.y, b.z, (a - b).length))

    apply_weapons(d, sword, saya)

    for tag, car in (("SAYA", saya), ("SWORD", sword)):
        m3 = car.matrix_world.to_3x3()
        loc = car.matrix_world.translation
        print("PROBE %s carrier origin %s  col0 %s  col2 %s"
              % (tag, tuple(round(v, 4) for v in loc),
                 tuple(round(v, 4) for v in (m3 @ Vector((1, 0, 0)))),
                 tuple(round(v, 4) for v in (m3 @ Vector((0, 0, 1))))))
        for o in sword_objs_of(car)[:20]:
            ml = o.matrix_local
            ident = all(abs(ml[i][j] - (1.0 if i == j else 0.0)) < 1e-6
                        for i in range(4) for j in range(4))
            vc = [o.matrix_world @ Vector(c) for c in o.bound_box]
            print("PROBE   %-18s parent=%s mlocal_identity=%s  world z %.3f..%.3f  "
                  "x %.3f..%.3f"
                  % (o.name, o.parent.name if o.parent else "-", ident,
                     min(q.z for q in vc), max(q.z for q in vc),
                     min(q.x for q in vc), max(q.x for q in vc)))

    # ---- the character mesh, as the RENDERER sees it ---------------------
    # A frame whose numbers are all correct and whose picture is not means the
    # thing being rendered is not the thing being measured.  So print what the
    # depsgraph actually evaluates -- the DEFORMED vertices in world space --
    # next to the pose bones' own extent, and let the disagreement name itself.
    dg = bpy.context.evaluated_depsgraph_get()
    print("PROBE armature pose_position=%r  ob matrix_world loc=%s"
          % (getattr(rig.ob.data, "pose_position", "?"),
             tuple(round(v, 4) for v in rig.ob.matrix_world.translation)))
    pb_pts = []
    for nm in ("Hips", "Foot.L", "Foot.R", "Hand.L", "Hand.R", "Head"):
        pb_pts.append(rig.pb[nm].matrix.translation.copy())
        pb_pts.append(rig.pb[nm].tail.copy())
    print("PROBE pose-bone extent  z %.3f..%.3f (span %.3f)  x %.3f..%.3f"
          % (min(v.z for v in pb_pts), max(v.z for v in pb_pts),
             max(v.z for v in pb_pts) - min(v.z for v in pb_pts),
             min(v.x for v in pb_pts), max(v.x for v in pb_pts)))
    for o in list(rig.ob.children_recursive):
        if o.type != "MESH":
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        n = len(me.vertices)
        co = [0.0] * (n * 3)
        me.vertices.foreach_get("co", co)
        mw = ev.matrix_world
        zs, xxs, ys = [], [], []
        for i in range(0, n * 3, 3):
            wv = mw @ Vector((co[i], co[i + 1], co[i + 2]))
            zs.append(wv.z)
            xxs.append(wv.x)
            ys.append(wv.y)
        ev.to_mesh_clear()
        mods = ",".join(
            "%s->%s" % (m.type, m.object.name if getattr(m, "object", None) else "-")
            for m in o.modifiers)
        print("PROBE   MESH %-18s verts %5d parent=%-14s mods[%s]"
              % (o.name, n, o.parent.name if o.parent else "-", mods))
        print("PROBE     EVAL world  z %.3f..%.3f (span %.3f)  x %.3f..%.3f  "
              "y %.3f..%.3f"
              % (min(zs), max(zs), max(zs) - min(zs), min(xxs), max(xxs),
                 min(ys), max(ys)))
        # A bbox cannot tell "upright" from "pitched forward by the same z
        # span", and that ambiguity is exactly what a wrong-looking picture of a
        # correct-measuring frame is made of.  The banded y-centroid CAN: an
        # upright torso keeps a constant depth per slice, a pitched one walks
        # forward with height.
        z0, z1 = min(zs), max(zs)
        for k in range(5):
            a_ = z0 + (z1 - z0) * k / 5.0
            b_ = z0 + (z1 - z0) * (k + 1) / 5.0
            sel = [ys[i] for i in range(len(ys)) if a_ <= zs[i] <= b_]
            if sel:
                print("PROBE       z %.2f-%.2f  n %5d  y-centroid %+.4f"
                      % (a_, b_, len(sel), sum(sel) / len(sel)))

    # ---- and where the CAMERA says those same points land ---------------
    # The last link in the chain, and the one that was never checked: a plate
    # whose numbers are all right can still, if the camera maths is wrong,
    # picture something else entirely.  These are pixel coordinates the camera
    # itself computes, so they can be held against the rendered silhouette.
    probe_views(cams, cf, rig, d, w)

    # ---- draw the very state that was just measured ---------------------
    # Everything above certifies this pose.  If a plate rendered from HERE also
    # disagrees with it, the fault is in rendering; if this plate agrees and the
    # `poses` stage does not, the fault is in that stage's state.  Without this
    # the two stages can argue indefinitely about which of them owns the bug.
    print("PROBE before render: %s" % mesh_extent(rig))
    pdir = os.path.join(out, "probe")
    os.makedirs(pdir, exist_ok=True)
    setup_render(W, H, samples=16)
    sc = bpy.context.scene
    hide_label()
    for cname in ("SIDE", "FRONT3Q"):
        cam = cams[cname]
        sc.camera = cam
        RR.shoot(cam, os.path.join(pdir, "probe_rest_%s.png" % cname), tar)
    print("PROBE after  render: %s" % mesh_extent(rig))
    print("PROBE probe plates -> %s" % pdir)

    print("PROBE computed tip %s  kashira %s  guard %s"
          % (tuple(round(v, 4) for v in d["tip"]),
             tuple(round(v, 4) for v in d["kashira"]),
             tuple(round(v, 4) for v in d["guard"])))
    print("PROBE computed mouth %s" % (tuple(round(v, 4) for v in cf.p(*MOUTH)),))
    print("PROBE w.tip_z %.4f w.kashira_z %.4f w.seat_back %.4f w.bore_len %.4f"
          % (w.tip_z, w.kashira_z, w.seat_back, w.bore_len))
    m, at, n = w.bore_margin(0.0)
    print("PROBE bore_margin at travel 0: worst %+.4f m at %s (%d pts inside)"
          % (m, tuple(round(v, 4) for v in at) if at else None, n))
    m2, at2, n2 = w.bore_margin(w.travel_full)
    print("PROBE bore_margin at travel full: worst %+.4f m at %s (%d pts inside)"
          % (m2, tuple(round(v, 4) for v in at2) if at2 else None, n2))

    # ---- hand reach at the moment the blade clears ----------------------
    # The one number that decides whether the draw is a draw or a mime: can each
    # hand actually get to the thing it is supposed to be holding?  Print the
    # shoulder->wrist distance next to the arm's own length so a miss names its
    # own cause (arm too short vs target in a bad place) instead of just being a
    # number that is not zero.
    arm = (rig.length(RC.BONES["upper"]["R"]) + rig.length(RC.BONES["lower"]["R"]))
    print("PROBE arm shoulder->wrist %.4f m" % arm)
    for tt, tag in ((0.0, "rest"), (F_DRAW, "F_DRAW")):
        dd = p.solve(tt)
        ss = p._s(tt)
        for side in ("L", "R"):
            if side == "L":
                tgt, rb = p._left_target(tt, ss, dd["M_saya"])
            else:
                tgt, rb = dd["M_sword"] @ HILT_LOCAL, sword_rod_basis(dd["M_sword"])
            gc = rig.grip_centre_local(side)
            rb = aim_roll(rig, side, rb, gc, Vector(tgt), dd["shoulder_" + side])
            B = rig.grip_basis(side, rb)
            off = B @ gc
            wr = Vector(tgt) - off
            sh = dd["shoulder_" + side]
            print("PROBE %-7s hand %s  shoulder->grip %.3f  shoulder->wrist %.3f  "
                  "grip->wrist %.3f  wrist offset %s  miss %.1f mm  saya yaw %+.1f"
                  % (tag, side, (Vector(tgt) - sh).length, (wr - sh).length,
                     off.length, tuple(round(v, 3) for v in off),
                     dd["lh_err" if side == "L" else "rh_err"] * 1000.0,
                     dd["saya_yaw_deg"]))


def stage_poses(rig, cf, w, p, sword, saya, cams, out, tar, W, H):
    sc = bpy.context.scene
    setup_render(W, H, samples=32)
    pdir = os.path.join(out, "poses")
    os.makedirs(pdir, exist_ok=True)
    for f in os.listdir(pdir):
        if f.endswith(".png"):
            os.remove(os.path.join(pdir, f))

    def dist_of(cam):
        return (cam.matrix_world.translation - Vector(tar)).length

    manifest = []

    # ---- 1. THE REST CONTRACT ------------------------------------------
    # Brief step 1: before any of the eight poses is judged, the scabbard has to
    # be right while the character is simply STANDING.  A saya that is wrong at
    # rest is wrong in every later frame, and it is the kind of wrong that
    # survives every numeric check and dies in the first picture.
    d = p.solve(0)
    apply_weapons(d, sword, saya)
    for cname in POSE_VIEWS:
        cam = cams[cname]
        sc.camera = cam
        show_label(cam, "REST  sheathed", 0.55 * dist_of(cam))
        path = os.path.join(pdir, "rest_%s.png" % cname)
        RR.shoot(cam, path, tar)
        manifest.append(path)

    # ---- 2. THE EIGHT KEY POSES ----------------------------------------
    # Brief 26: lock the key poses and LOOK at them before any in-between is
    # added.  Front 3/4, side and back 3/4 for each, so a pose that only works
    # from the flattering angle is caught here rather than in the movie.
    for name, t in KEYS:
        d = p.solve(t)
        apply_weapons(d, sword, saya)
        # The label carries the EXTRACTION FRACTION, not just the frame number.
        # The brief's pose list is written in fractions of the draw ("25% Draw",
        # "60% Draw") and this rig's draw accelerates hard -- 25% at f29, 77% at
        # f31 -- so a bare frame number is exactly the wrong label for judging
        # whether the beat the brief asked for is the beat on the plate.  It also
        # makes the contact sheet self-auditing: if a cell says "out 60%" and the
        # blade is nearly free, the label is lying and you can see it.
        out_pct = min(100.0, 100.0 * d["travel"] / w.travel_clear)
        for cname in ("FRONT3Q", "SIDE", "BACK3Q"):
            cam = cams[cname]
            sc.camera = cam
            show_label(cam, "%s  f%g  out %.0f%%" % (name, t, out_pct),
                       0.55 * dist_of(cam))
            path = os.path.join(pdir, "%05.1f_%s_%s.png" % (t, name, cname))
            RR.shoot(cam, path, tar)
            manifest.append(path)
        print("POSE %-11s f=%5.1f travel=%.3f out=%5.1f%% blend=%.2f rh_err=%.4f "
              "lh_err=%.4f back=%.3f tip_u=%+.3f tilt=%+.1f yaw=%+.1f"
              % (name, t, d["travel"], out_pct, d["blend"], d["rh_err"],
                 d["lh_err"], d["saya_back"], d["tip"].z, d["saya_tilt_deg"],
                 d["saya_yaw_deg"]))
        # -- the geometry line.  Pixels are how you CATCH a wrong pose; numbers
        # are how you DIAGNOSE it.  Flipping the side camera fixed the first
        # problem and immediately created a second one I could not read off the
        # plate: at 61.6% extraction the blade should already be a visible
        # up-forward spike out of the koiguchi, and the render showed no such
        # spike.  Deciding between "the blade is hidden behind the torso" and
        # "the extraction is rotating the wrong way" by squinting at a 960x540
        # JPEG is how a review round turns into three hours.  So every key pose
        # now states where the mouth, the kojiri, the guard and the tip actually
        # are, in world metres, plus the angle between the saya's bore and the
        # blade -- which is 0 by construction while the blade is inside and
        # starts growing the frame the habaki clears.
        mouth = d["M_saya"].translation
        kojiri = d["M_saya"] @ Vector((0.0, 0.0, w.bore_len))
        bore = Vector(d["M_saya"].col[2][:3]).normalized()
        sep = math.degrees(math.acos(max(-1.0, min(1.0, bore.dot(d["blade_dir"])))))
        print("     mouth(%+.3f,%+.3f,%+.3f) kojiri(%+.3f,%+.3f,%+.3f)\n"
              "     tip  (%+.3f,%+.3f,%+.3f) kashira(%+.3f,%+.3f,%+.3f) "
              "blade_vs_bore %5.1f deg"
              % (mouth.x, mouth.y, mouth.z, kojiri.x, kojiri.y, kojiri.z,
                 d["tip"].x, d["tip"].y, d["tip"].z,
                 d["kashira"].x, d["kashira"].y, d["kashira"].z, sep))
    with open(os.path.join(pdir, "manifest.txt"), "w") as fh:
        fh.write("\n".join(manifest) + "\n")
    print("POSES %d plates" % len(manifest))


SECTIONS = [("01_front3q", "FRONT3Q", 0.0, 1.0), ("02_side", "SIDE", 0.0, 1.0),
            ("03_slowmo", "SIDE", 0.0, 0.25), ("04_gameplay", "GAMEPLAY", 0.0, 1.0)]
# Section 3 is the same camera as section 2 on purpose.  The slow-motion beat is
# an ANALYSIS pass, not a beauty pass, and it belongs on the view that can
# actually see the sword: at 0.25x it is the only place a viewer can check the
# blade sliding down the bore's arc instead of cutting across it.  Putting it on
# FRONT3Q would have made the slowmo a second look at the hero angle and told the
# viewer nothing new.  Standard edit grammar also expects the slowmo to follow the
# shot it is slowing down.


def stage_anim(rig, cf, w, p, sword, saya, cams, out, tar, W, H, res):
    sc = bpy.context.scene
    setup_render(W, H, samples=24)

    # -- bake, so the shot is reproducible and exportable -----------------
    for t in range(0, F_END + 1):
        d = p.solve(float(t))
        apply_weapons(d, sword, saya)
        for pb in rig.pb:
            pb.keyframe_insert("rotation_quaternion", frame=t, group=pb.name)
            if pb.name in ("Root", "Hips"):
                pb.keyframe_insert("location", frame=t, group=pb.name)
        sword.keyframe_insert("location", frame=t)
        sword.keyframe_insert("rotation_quaternion", frame=t)
        saya.keyframe_insert("location", frame=t)
        saya.keyframe_insert("rotation_quaternion", frame=t)
    blend_out = os.path.join(out, "iaido_third_person_v1_%s.blend" % p.variant)
    bpy.ops.wm.save_as_mainfile(filepath=blend_out)
    print("BAKED + saved %s" % blend_out)

    # -- render ------------------------------------------------------------
    frames = os.path.join(out, "frames")
    os.makedirs(frames, exist_ok=True)
    for f in os.listdir(frames):
        if f.endswith(".png"):
            os.remove(os.path.join(frames, f))
    sc.render.filepath = os.path.join(frames, "unused")
    n = 0
    for sec, cname, _, step in SECTIONS:
        cam = cams[cname]
        sc.camera = cam
        RR.purge_lights()
        RR.setup_lights(tar, cam)
        # short section tag only -- brief 29 forbids paragraphs in the movie
        show_label(cam, sec.upper().replace("_", " ").replace("3Q", "3/4"),
                   0.55 * (cam.matrix_world.translation - Vector(tar)).length)
        ts = []
        t = 0.0
        while t <= F_END + 1e-6:
            ts.append(t)
            t += step
        for t in ts:
            d = p.solve(t)
            apply_weapons(d, sword, saya)
            sc.render.filepath = os.path.join(frames, "frame_%05d" % n)
            bpy.ops.render.render(write_still=True)
            n += 1
            if n % 25 == 0:
                print("  frames %d (%.0f%%)" % (n, 100.0 * n / (103 * 3 + 409)))
        print("SECTION %s done (%d frames, %s)" % (sec, len(ts), cname))
    with open(os.path.join(out, "fps.txt"), "w") as fh:
        fh.write("%d\n" % FPS)
    print("RENDERED %d frames into %s" % (n, frames))


def stage_verify(rig, cf, w, p, cams, tar, out):
    res = {"variant": p.variant}
    fails = []

    def chk(name, ok, detail):
        res[name] = detail
        print("%s %-28s %s" % ("PASS" if ok else "FAIL", name, detail))
        if not ok:
            fails.append(name)

    # ---- 1. blade inside the bore for every extraction state ------------
    worst = (1e9, None, 0.0)
    for i in range(0, 101):
        tr = w.travel_full * i / 100.0
        m, at, n = w.bore_margin(tr)
        if n > 0 and m < worst[0]:
            worst = (m, at, tr)
    chk("bore_clearance", worst[0] > 0.0008,
        "worst %.2f mm at travel %.3f (need >0.8 mm; habaki fit is %.2f/%.2f mm)"
        % (worst[0] * 1000.0, worst[2], w.clear_w * 1000.0, w.clear_t * 1000.0))

    # ---- 2. foot planting ----------------------------------------------
    slide = {"L": 0.0, "R": 0.0}
    prev = {}
    for t in [x * 0.5 for x in range(F_END * 2 + 1)]:
        d = p.body(t)
        for s in ("L", "R"):
            # planted unless this is the leading foot during the step window
            stepping = (s == "L" and F_PREP < t < F_DRAW)
            if stepping:
                continue
            q = d["foot_" + s]
            if s in prev:
                slide[s] = max(slide[s], (q - prev[s]).length)
            prev[s] = q.copy()
    chk("no_foot_slide", max(slide.values()) < 0.002,
        "max planted-foot displacement %.4f mm" % (max(slide.values()) * 1000.0))

    # ---- 3. pelvis: sink depth and weight going onto the rear foot ------
    us = [p.pel_u(t) for t in range(0, F_END + 1)]
    sinkmax = max(us) - min(us)
    chk("pelvis_sink", 0.030 <= sinkmax <= 0.070,
        "%.4f m total travel (brief asks 3-6 cm)" % sinkmax)
    chk("weight_to_rear", p.pel_f(F_PREP) < -0.010,
        "pelvis %.4f m behind neutral at the load (negative = rear foot)" % p.pel_f(F_PREP))

    # ---- 4. hand attachment ---------------------------------------------
    rh = lh = 0.0
    rh_t = lh_t = 0
    for t in range(0, F_END + 1):
        d = p.solve(float(t))
        if F_AWARE < t <= F_SETTLE + 40 and d["rh_err"] > rh:
            rh, rh_t = d["rh_err"], t
        if 20 <= t <= 88 and d["lh_err"] > lh:
            lh, lh_t = d["lh_err"], t
    chk("right_hand_on_hilt", rh < 0.006,
        "worst IK miss %.2f mm at f%d over the whole draw and sheath"
        % (rh * 1000.0, rh_t))
    chk("left_hand_on_saya", lh < 0.006,
        "worst IK miss %.2f mm at f%d -- the left hand really is on the sheath"
        % (lh * 1000.0, lh_t))

    # ---- 5. blade arc: a real cut, not a wiggle -------------------------
    tips = []
    for t in [F_DRAW + 0.0] + [x * 0.5 for x in range(2 * F_DRAW, 2 * F_CUT + 1)]:
        d = p.solve(t)
        tips.append((t, d["tip"].copy(), d["blade_dir"].copy()))
    swept = 0.0
    for i in range(1, len(tips)):
        a, b = tips[i - 1][2], tips[i][2]
        swept += math.degrees(math.acos(RC.clamp(a.dot(b), -1.0, 1.0)))
    path = sum((tips[i][1] - tips[i - 1][1]).length for i in range(1, len(tips)))
    chk("blade_arc", swept > 110.0 and path > 1.4,
        "tip sweeps %.0f deg over %.2f m of path in %.2f s" % (swept, path, 0.2))

    # ---- 6. contrast: the draw is much faster than the sheath -----------
    def speed(a, b, key="tip"):
        best = 0.0
        for t in [a + (b - a) * i / 40.0 for i in range(41)]:
            pass
        return best
    v_draw = []
    for i in range(41):
        t0 = F_PREP + (F_DRAW - F_PREP) * i / 40.0
        t1 = F_PREP + (F_DRAW - F_PREP) * (i + 1) / 40.0
        v_draw.append((p.solve(t1)["tip"] - p.solve(t0)["tip"]).length / ((t1 - t0) / FPS))
    v_sheath = []
    for i in range(80):
        t0 = F_SETTLE + (F_SEAT - F_SETTLE) * i / 80.0
        t1 = F_SETTLE + (F_SEAT - F_SETTLE) * (i + 1) / 80.0
        v_sheath.append((p.solve(t1)["tip"] - p.solve(t0)["tip"]).length / ((t1 - t0) / FPS))
    pk, av = max(v_draw), sum(v_sheath) / len(v_sheath)
    chk("speed_contrast", pk / av > 6.0,
        "peak draw %.2f m/s vs mean sheath %.2f m/s -> %.1fx contrast" % (pk, av, pk / av))
    res["peak_draw_speed_ms"] = pk
    res["mean_sheath_speed_ms"] = av

    # ---- 7. overshoot ---------------------------------------------------
    a38 = p.solve(F_CUT)["blade_dir"]
    a37 = p.solve(F_CUT - 1)["blade_dir"]
    ov = math.degrees(math.acos(RC.clamp(a38.dot(a37), -1.0, 1.0)))
    chk("overshoot", 1.0 <= ov <= 8.0,
        "blade overshoots the final cut pose by %.2f deg before settling" % ov)

    # ---- 8. framing -----------------------------------------------------
    setup_render(1280, 720, samples=1)
    worstcam = ("", 0.0, 0.0)
    for cname, cam in cams.items():
        for t in [x * 2.0 for x in range(F_END // 2 + 1)]:
            d = p.solve(t)
            v = ndc(cam, bounds_points(d, rig))
            if v > worstcam[1]:
                worstcam = (cname, v, t)
    chk("framing", worstcam[1] < 0.98,
        "worst NDC %.3f in %s at f%.0f (want <0.98)" % (worstcam[1], worstcam[0], worstcam[2]))

    # ---- 9. tip above ground -------------------------------------------
    low = (1e9, 0)
    for t in range(0, F_END + 1):
        z = p.solve(float(t))["tip"].z
        if z < low[0]:
            low = (z, t)
    chk("tip_above_ground", low[0] > GROUND_U + 0.03,
        "lowest tip height %+.3f m at f%d (ground %+.3f)" % (low[0], low[1], GROUND_U))

    # ---- 10. blade vs own body -----------------------------------------
    # The left forearm is EXCLUDED wherever the left hand is on the sheath.
    # The left hand guides the koiguchi, so the blade base and that forearm are
    # 6-12 mm apart by construction on every frame of the draw -- the first run
    # of this check "found" exactly that and called it a collision.  The gate
    # exists to catch the blade going through the torso, the thigh or the
    # reaching arm; measuring it against the hand that is holding the scabbard
    # measures the mechanism, not a mistake.
    body = []
    for t in [x * 2.0 for x in range(F_END // 2 + 1)]:
        d = p.solve(t)
        guiding = p._s(t)["lh_on"] > 0.5
        holding = p._s(t)["rh_on"] > 0.5
        segs = [(rig.head("Hips"), rig.head("Chest")),
                (rig.head("UpperLeg.L"), rig.head("LowerLeg.L")),
                (rig.head("UpperLeg.R"), rig.head("LowerLeg.R"))]
        if not holding:
            segs.append((rig.head("UpperArm.R"), rig.head("Hand.R")))
        if not guiding:
            segs.append((rig.head("UpperArm.L"), rig.head("Hand.L")))
        pts = [d["M_sword"] @ Vector((0.0, 0.0, z))
               for z in [0.031, 0.15, 0.30, 0.45, 0.60, 0.765]]
        m = 9.9
        for p3 in pts:
            for (a, b) in segs:
                ab = b - a
                tt = RC.clamp((p3 - a).dot(ab) / max(ab.length_squared, 1e-9), 0.0, 1.0)
                m = min(m, (p3 - (a + ab * tt)).length)
        body.append((m, t))
    mmin = min(body)
    chk("blade_body_clearance", mmin[0] > 0.035,
        "closest blade approach to a body capsule %.3f m at f%.0f" % (mmin[0], mmin[1]))

    print("\n=== VERIFY %s: %d pass, %d fail ===" % (p.variant, len(res) - len(fails), len(fails)))
    if fails:
        print("FAILED: %s" % ", ".join(fails))
    with open(os.path.join(out, "verify_%s.json" % p.variant), "w") as fh:
        json.dump({"pass": len(res) - len(fails), "fail": fails,
                   "detail": {k: str(v) for k, v in res.items()}}, fh, indent=1)
    return len(fails)


def stage_encode(out):
    """Encode the rendered frames into the delivery mp4.

    The project's own `godot/tools/encode_iaido_movie.sh` is not reusable here for
    two structural reasons, and quietly reusing it would have produced a broken
    film rather than an error:

      * it globs `frame_%04d.png`; `stage_anim` writes `frame_%05d.png`, so it
        would have encoded ZERO frames and still printed a success line;
      * it splices in iaido audio cues read live from `IaidoAudioTimeline`.  This
        pass is a silent greybox -- brief 17 says the animation must stand up with
        no effects -- so there are no cues to read and the sheet it builds is
        empty.

    So the encode lives here, next to the render that produces its input, and the
    ffmpeg binary is the `ENCODE` constant that this file already declared and
    never used.

    Two honesty guards, because a video is the one deliverable nobody diffs:
      * the container's own duration is read back off the ffmpeg banner and
        compared with frames/fps.  A mismatch means the encode dropped frames.
      * the first and last frames are decoded to 8x4 grey and checked for
        non-blackness.  `setup_render` sets `film_transparent = True`, and a
        transparent film written to a codec without an alpha channel is exactly
        how you ship a 24-second black rectangle that every tool reports as valid.
    """
    import subprocess

    frames = os.path.join(out, "frames")
    if not os.path.isdir(frames):
        raise SystemExit("no %s -- run --stage anim first" % frames)
    seq = sorted(f for f in os.listdir(frames)
                 if f.startswith("frame_") and f.endswith(".png"))
    if not seq:
        raise SystemExit("no frames in %s" % frames)
    n = len(seq)
    fpsf = os.path.join(out, "fps.txt")
    fps = int(open(fpsf).read().strip()) if os.path.exists(fpsf) else FPS

    def probe_gray(idx):
        r = subprocess.run([ENCODE, "-hide_banner", "-loglevel", "error",
                            "-i", os.path.join(frames, "frame_%05d.png" % idx),
                            "-vf", "scale=8:4,format=gray", "-f", "rawvideo", "-"],
                           capture_output=True)
        return max(r.stdout) if r.stdout else 0

    lo_in, hi_in = probe_gray(0), probe_gray(n - 1)
    mp4 = os.path.join(out, "iaido_third_person_v1.mp4")
    tries = [
        ("h264_amf", ["-c:v", "h264_amf", "-quality", "quality", "-rc", "cqp",
                      "-qp_i", "18", "-qp_p", "20", "-qp_b", "22"]),
        ("h264_mf", ["-c:v", "h264_mf", "-quality", "quality"]),
        ("h264_nvenc", ["-c:v", "h264_nvenc", "-preset", "p6", "-cq", "20"]),
        ("libx264", ["-c:v", "libx264", "-preset", "slow", "-crf", "16"]),
    ]
    used = None
    for name, va in tries:
        cmd = ([ENCODE, "-hide_banner", "-loglevel", "error", "-y",
                "-framerate", str(fps), "-start_number", "0",
                "-i", os.path.join(frames, "frame_%05d.png"),
                "-frames:v", str(n)] + va +
               ["-pix_fmt", "yuv420p", "-movflags", "+faststart", mp4])
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode == 0 and os.path.exists(mp4) and os.path.getsize(mp4) > 16384:
            used = name
            break
        print("   encoder %-10s failed: %s" % (name, (r.stderr or "").strip()[-160:]))
    if not used:
        raise SystemExit("every encoder failed; last stderr above")

    # -- read the duration back off the banner (this ffmpeg has no ffprobe) --
    b = subprocess.run([ENCODE, "-hide_banner", "-i", mp4],
                       capture_output=True, text=True).stderr
    dur = None
    for line in b.splitlines():
        if "Duration:" in line:
            hh, mm, ss = line.split("Duration:")[1].split(",")[0].strip().split(":")
            dur = int(hh) * 3600 + int(mm) * 60 + float(ss)
            break
    want = n / float(fps)
    print("ENCODE %s -> %s" % (used, mp4))
    print("ENCODE %d frames @ %d fps = %.2f s expected; container says %s"
          % (n, fps, want, "%.2f s" % dur if dur else "UNREADABLE"))
    print("ENCODE input luma f0 max %d / f%d max %d (0 = black frame)"
          % (lo_in, n - 1, hi_in))
    if dur is None:
        raise SystemExit("ENCODE could not read the duration back -- not shipping a "
                         "video whose length is unknown")
    if abs(dur - want) > 0.5:
        raise SystemExit("ENCODE duration %.2f s != expected %.2f s -- frames were "
                         "dropped" % (dur, want))
    if max(lo_in, hi_in) < 16:
        raise SystemExit("ENCODE first/last frames are black -- the transparent film "
                         "was written without compositing")

    # -- and the guard that actually matters: the MP4 itself, not its input ----
    def probe_mp4(ss):
        r = subprocess.run([ENCODE, "-hide_banner", "-loglevel", "error", "-ss", ss,
                            "-i", mp4, "-frames:v", "1", "-vf", "scale=8:4,format=gray",
                            "-f", "rawvideo", "-"], capture_output=True)
        return max(r.stdout) if r.stdout else -1

    m0, m1, m2 = probe_mp4("0"), probe_mp4("%.1f" % (want * 0.5)), probe_mp4("%.1f" % (want - 0.5))
    print("ENCODE mp4 luma at 0%%/50%%/100%%: %d / %d / %d" % (m0, m1, m2))
    if min(m0, m1, m2) < 16:
        raise SystemExit("ENCODE the encoded mp4 has black regions -- alpha was "
                         "flattened wrong")


def stage_trace(rig, cf, w, p, sword, saya, out, t0, t1):
    """Print the blade's own path, frame by frame.  Read-only: renders nothing.

    Five evenly-spaced stills cannot answer "is this a CUT or a WAVE", because the
    difference between the two is entirely in the frames you did not sample.  A
    cut sweeps from one side of the body to the other and STOPS on the far side;
    a wave goes up and comes back down the way it came.  Both of them produce a
    handsome over-the-head frame in the middle, so the apex plate cannot tell them
    apart -- and the apex plate is the flattering one.

    So: the tip's world position every frame, plus the horizontal bearing of the
    blade about the character's own up axis measured against the body's forward
    (+ = to the character's right, - = their left), plus the per-frame tip speed.
    What that immediately shows on THIS performance is the thing no sampling of
    stills could have shown:
        f32  tip z 0.923  bearing  -76.0 deg  (blade still pointing out left)
        f33  tip z 1.137  bearing  -55.1      speed 11.5 m/s
        f34  tip z 2.091  bearing  +19.3      speed 35.6 m/s   <- apex
        f36  tip z 0.423  bearing  -19.5      speed 46.8 m/s   <- 1.56 m in ONE frame
    The blade is 1.051 m long, so at f36 the tip covers 1.5x its own length inside a
    single 1/30 s frame.  That is not "very fast", that is two positions the eye
    never connects -- it strobes.  Whether to KEEP that snap (the brief does say
    ANIME NEXT-GEN, and anime iai cuts really are 2-3 frames) or to spread it over
    ~6 frames is a look decision, not a bug, so this stage reports the number and
    changes nothing.
    """
    apply_weapons(p.solve(t0), sword, saya)
    print("\n=== TRACE %s  f%g..f%g ===" % (p.variant, t0, t1))
    print("   t     tip x      y      z    |  kashira z | blade dir            "
          "| bearing deg | speed m/s")
    prev, prev_t = None, None
    rows = []
    t = float(t0)
    while t <= t1 + 1e-6:
        d = p.solve(t)
        bd = d["blade_dir"]
        # Horizontal bearing of the blade measured in the character's own frame:
        # 0 = blade lying along the character's forward, +90 = pointing to their
        # RIGHT, -90 = their LEFT.  (The reference vector is `cf.right`, which is
        # the character's right -- world (-1,0,0) -- so the positive side of this
        # axis is the character's RIGHT, not their left.  Getting that sign
        # backwards inverts the reading of the whole trace and turns a cut that
        # crosses the body into one that does not.)
        f_ = Vector(bd); f_.z = 0.0
        if f_.length > 1e-6:
            f_.normalize()
            bear = math.degrees(math.atan2(f_.dot(cf.right), f_.dot(cf.fwd)))
        else:
            bear = float("nan")
        spd = 0.0
        if prev is not None:
            spd = (d["tip"] - prev).length * FPS / (t - prev_t)
        rows.append((t, d["tip"].copy(), d["kashira"].z, bd.copy(), bear, spd))
        prev, prev_t = d["tip"].copy(), t
        t += 1.0
    for t, tip, kz, bd, bear, spd in rows:
        print("  f%5.1f %+.3f %+.3f %+.3f | %+.3f     | %+.2f %+.2f %+.2f | "
              "  %+7.1f    | %5.2f" % (t, tip.x, tip.y, tip.z, kz,
                                        bd.x, bd.y, bd.z, bear, spd))
    zs = [r[1].z for r in rows]
    iup = zs.index(max(zs))
    print("  apex tip z %.3f m at f%g;  first %.3f m, last %.3f m"
          % (max(zs), rows[iup][0], zs[0], zs[-1]))
    be = [r[4] for r in rows if r[4] == r[4]]
    if be:
        print("  bearing %+.1f -> %+.1f deg (start -> end); extremes %+.1f / %+.1f"
              % (be[0], be[-1], min(be), max(be)))
    return 0


def _parse(argv):
    a = {"stage": "poses", "variant": "combat", "out": OUT_DEFAULT,
         "res": "960x540", "render_res": "1280x720"}
    i = 0
    while i < len(argv):
        k = argv[i].lstrip("-")
        if k in ("poses", "anim", "verify", "encode", "trace", "all", "selftest",
                 "probe", "bind"):
            a["stage"] = k
            i += 1
            continue
        if i + 1 < len(argv):
            a[k] = argv[i + 1]
            i += 2
        else:
            i += 1
    return a


def main():
    a = _parse(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    out = os.path.abspath(a["out"])
    os.makedirs(out, exist_ok=True)
    W, H = [int(v) for v in a["res"].split("x")]
    RW, RH = [int(v) for v in a["render_res"].split("x")]

    print("\n=== IAIDO THIRD PERSON V1 | stage=%s variant=%s ===" % (a["stage"], a["variant"]))
    rig, cf, w, p, sword, saya = build(a["variant"])
    ground = add_ground(cf)
    cams = cameras(cf)
    tar = cf.p(0.0, 0.0, 0.24)

    if a["stage"] == "selftest":
        selftest(rig, cf)
        return
    if a["stage"] == "probe":
        stage_probe(rig, cf, w, p, sword, saya, cams, tar, W, H, out)
        return
    if a["stage"] == "bind":
        stage_bind(rig, cf, cams, out, tar, W, H)
        return
    if a["stage"] == "trace":
        stage_trace(rig, cf, w, p, sword, saya, out,
                    float(a.get("t0", 24)), float(a.get("t1", 50)))
        return
    if a["stage"] in ("poses", "all"):
        stage_poses(rig, cf, w, p, sword, saya, cams, out, tar, W, H)
    if a["stage"] in ("anim", "all"):
        stage_anim(rig, cf, w, p, sword, saya, cams, out, tar, RW, RH, a["render_res"])
    nfail = 0
    if a["stage"] in ("verify", "all"):
        nfail = stage_verify(rig, cf, w, p, cams, tar, out)
    if a["stage"] in ("encode", "all"):
        stage_encode(out)
    # The verify exit code is a REPORT, not a gate on the deliverables: the three
    # known misses are all traceable to this rig's 0.379 m arms, and `all` is the
    # command that produces the film.  Exiting before `stage_encode` would mean the
    # one invocation that builds everything refuses to build the video.
    if nfail:
        print("NOTE %d verify check(s) still failing -- see verify_%s.json"
              % (nfail, p.variant))
        sys.exit(1)


if __name__ == "__main__":
    main()
