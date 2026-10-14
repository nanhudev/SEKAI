# -*- coding: utf-8 -*-
"""SEKAI / ANIMATION LINE -- humanoid posing library (Blender, headless-safe).

WHY THIS EXISTS
===============
The first attempt at a third-person iaido draw hit a wall that is worth writing
down, because it is the reason this file is a library and not a one-off script:

    The sword must travel 0.765 m *relative to the saya* before its tip clears
    the koiguchi -- that is not a style choice, it is `tip_y` from
    `sword_classes.gd`.  A straight pull therefore puts the hilt 0.77 m from a
    mouth that is itself only 0.36 m from the right shoulder, i.e. 0.9 m from a
    shoulder whose whole arm is 0.55 m long.  Unreachable.  So the draw CANNOT
    be authored as "hand moves along a line"; it has to fall out of the saya's
    own rotation, which is why the left hand is load-bearing rather than
    decorative.

Everything here exists to make that solvable and checkable:

  * a measured CHARACTER FRAME (forward / right / up) taken off the rig's own
    feet, so no pose constant is typed in an axis convention I guessed;
  * analytic two-bone IK that RETURNS ITS OWN ERROR, so "the arm cannot reach
    that" is a number and not a silent straight-arm;
  * posing primitives that work in ARMATURE space, because bone-local axes on a
    retargeted Quaternius rig are not something anyone should hand-author
    against;
  * a grip frame DERIVED from the hand's own thumb / index / pinky joints
    rather than a guessed Euler offset.

Traps recorded the hard way (see docs/anim/IAIDO_V1.md):
  * `pose_bone.matrix` is armature space and reading a child's `.translation`
    before `view_layer.update()` gives the PREVIOUS frame's head.  Every setter
    here updates before returning.
  * `bpy.ops.import_scene.gltf` names changed across Blender versions; both
    spellings are tried.
  * Blender's glTF import maps glTF +Y to Blender +Z, so a weapon authored
    "+Y is the tip" has its long axis on Blender Z.  Pose math here is done in
    whichever ARMATURE space the rig actually has, which is why nothing depends
    on that convention being remembered correctly.

Run standalone to dump a rig's measured table:

    "/g/blender.exe" -b --factory-startup --python tools/anim/rig_common.py -- \
        --char <glb> --dump
"""

import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

TAU = math.pi * 2.0


# ---------------------------------------------------------------------------
#  small helpers
# ---------------------------------------------------------------------------

def log(*a):
    print("[rig]", *a)
    sys.stdout.flush()


def die(msg):
    print("[rig][FATAL] " + msg)
    sys.stdout.flush()
    sys.exit(1)


def clamp(v, lo, hi):
    return lo if v < lo else (hi if v > hi else v)


def mat_from_cols(x, y, z, t=None):
    """4x4 whose columns are the three axis vectors (right-handed)."""
    m = Matrix(((x[0], y[0], z[0], 0.0),
                (x[1], y[1], z[1], 0.0),
                (x[2], y[2], z[2], 0.0),
                (0.0, 0.0, 0.0, 1.0)))
    if t is not None:
        m.translation = Vector(t)
    return m


def orthonormalise(y, z_hint):
    """y = primary axis (kept exactly).  z = z_hint orthogonalised.  x = y x z."""
    y = Vector(y)
    if y.length < 1e-9:
        die("orthonormalise got a zero primary axis")
    y = y.normalized()
    z = Vector(z_hint)
    z = z - y * z.dot(y)
    if z.length < 1e-6:
        for alt in (Vector((0, 0, 1)), Vector((0, 1, 0)), Vector((1, 0, 0))):
            z = alt - y * alt.dot(y)
            if z.length > 1e-6:
                break
    z.normalize()
    x = y.cross(z)
    return x, y, z


def deg(v):
    return v * 180.0 / math.pi


def rad(v):
    return v * math.pi / 180.0


def ease_in_out(t):
    return t * t * (3.0 - 2.0 * t)


def ease_out(t):
    return 1.0 - (1.0 - t) ** 2


def ease_in(t):
    return t * t


def lerp(a, b, t):
    return a + (b - a) * t


def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for blk in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials,
                bpy.data.cameras, bpy.data.lights):
        for it in list(blk):
            blk.remove(it)


def _mix(a, b, t):
    """Interpolate whatever a key holds, however deeply nested.

    The authored cut stores `(blade_dir_xyz)` on one channel and
    `((grip_dir_xyz), length)` on another.  A flat `tuple(a + (b - a) * t ...)`
    works for the first and raises `TypeError: unsupported operand type(s) for
    -: 'tuple' and 'tuple'` on the second -- which is exactly where the first
    authored cut died, at its first in-between frame.
    """
    if isinstance(a, (tuple, list)) and isinstance(b, (tuple, list)):
        return tuple(_mix(x, y, t) for x, y in zip(a, b))
    return a + (b - a) * t


def lerp_key(keys, u):
    """Piecewise-linear lookup over [(u, value)] where `value` is a tuple.
    A None at either end of a segment means "this stretch is derived, not
    authored" and propagates None out."""
    keys = sorted(keys, key=lambda k: k[0])
    if u <= keys[0][0]:
        return keys[0][1]
    if u >= keys[-1][0]:
        return keys[-1][1]
    for i in range(1, len(keys)):
        u0, v0 = keys[i - 1]
        u1, v1 = keys[i]
        if u0 <= u <= u1:
            if v0 is None or v1 is None:
                return None
            t = (u - u0) / (u1 - u0) if u1 > u0 else 1.0
            return _mix(v0, v1, t)
    return keys[-1][1]


def flatten_to_carrier(objs, name):
    """Collapse an imported glTF onto one carrier Empty and return it.

    WHY.  Blender's glTF importer converts Y-up to Z-up by putting a rotation on
    the imported ROOT, so after import a weapon documented as "+Y is the tip"
    has its tip on Blender +Z.  That is fine for a viewer and poison for
    animation: any matrix I compute in the documented frame is then off by a
    quarters turn, and it fails silently because the object still looks right
    standing still.

    So: bake each mesh object's full world matrix into its own vertex data and
    leave every mesh at the origin.  Afterwards the mesh-local coordinates ARE
    the GLB's own coordinates, and the documented frame is literally true.
    """
    me = bpy.data.meshes.new(name + "_carrier")
    carrier = bpy.data.objects.new(name, None)
    carrier.empty_display_type = "ARROWS"
    carrier.empty_display_size = 0.12
    bpy.context.scene.collection.objects.link(carrier)
    meshes = [o for o in objs if o.type == "MESH"]
    if not meshes:
        die("no meshes to flatten in %s" % name)
    for o in meshes:
        if o.data.users > 1:
            o.data = o.data.copy()
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    for o in objs:
        if o is not carrier and o.type != "MESH":
            try:
                bpy.data.objects.remove(o, do_unlink=True)
            except Exception:
                pass
    for o in meshes:
        o.parent = carrier
        o.matrix_parent_inverse = Matrix.Identity(4)
        o.matrix_basis = Matrix.Identity(4)
    log("flattened %s: %d meshes, local coords are now GLB coords"
        % (name, len(meshes)))
    return carrier


def import_glb(path, tag=None):
    path = os.path.abspath(path)
    if not os.path.isfile(path):
        die("missing GLB: %s" % path)
    before = set(bpy.data.objects)
    # Blender renamed this operator across versions, AND an unknown operator
    # still resolves to a callable that only explodes when invoked -- so every
    # candidate has to be actually tried, not merely looked up.
    last = None
    for name in ("import_scene.gltf", "wm.gltf_import", "import_scene.gltf2"):
        op = bpy.ops
        ok = True
        for p in name.split("."):
            op = getattr(op, p, None)
            if op is None:
                ok = False
                break
        if not ok:
            continue
        try:
            op(filepath=path)
            last = None
            break
        except (AttributeError, RuntimeError) as e:
            last = e
    if last is not None:
        die("glTF import failed (%s): %s" % (path, last))
    # Blender's importer parks helper geometry in a `glTF_not_exported`
    # collection -- an unparented 2 m Icosphere for this character GLB, sitting
    # at the origin, which would silently become a sphere in every render.
    # Nothing that lands there is part of the asset.
    for o in list(bpy.data.objects):
        if any(c.name.startswith("glTF_not_exported") for c in o.users_collection):
            log("dropping importer artefact: %s (%s)" % (o.name, o.type))
            bpy.data.objects.remove(o, do_unlink=True)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if tag:
            o.name = tag + "_" + o.name
    if not new:
        die("import produced no objects: %s" % path)
    return new


# ---------------------------------------------------------------------------
#  character frame
# ---------------------------------------------------------------------------

class CharFrame(object):
    """Measured, not assumed.

    `forward` comes off the toes (Foot -> Foot_end projected to horizontal),
    which is a property of the rig's rest pose rather than of any exporter
    convention.  (forward, right, up) is right-handed.
    """

    def __init__(self, origin, fwd, right, up):
        self.origin = Vector(origin)
        self.fwd = Vector(fwd).normalized()
        self.right = Vector(right).normalized()
        self.up = Vector(up).normalized()

    def v(self, f=0.0, r=0.0, u=0.0):
        """char-frame components -> world vector (no origin added)."""
        return self.fwd * f + self.right * r + self.up * u

    def p(self, f=0.0, r=0.0, u=0.0):
        """point: origin + components."""
        return self.origin + self.v(f, r, u)

    def decompose(self, world):
        d = Vector(world) - self.origin
        return (d.dot(self.fwd), d.dot(self.right), d.dot(self.up))

    def basis(self):
        return mat_from_cols(self.right, self.fwd, self.up)

    def rot(self, yaw=0.0, pitch=0.0, roll=0.0):
        """Rotation matrix in char-frame terms.

        +yaw   turns the character's front toward its OWN LEFT.  (A right-handed
               turn about `up` takes the front toward `right`, so the sign is
               negative -- and getting this backwards produces a character who
               draws a cross-body cut while facing away from it.)
        +pitch leans the front FORWARD.
        +roll  tips the top toward the character's left.

        `ci_selfcheck` in the animation script asserts the first two, because a
        silent sign error here is invisible in every number and obvious in every
        frame.
        """
        R = Matrix.Identity(3)
        if yaw:
            R = Matrix.Rotation(rad(yaw), 3, self.up) @ R
        if pitch:
            R = Matrix.Rotation(-rad(pitch), 3, self.right) @ R
        if roll:
            R = Matrix.Rotation(rad(roll), 3, self.fwd) @ R
        return R


# ---------------------------------------------------------------------------
#  the rig
# ---------------------------------------------------------------------------

# Everything the animation is allowed to address.  Names are the Quaternius
# "Universal Animation Library" spelling, which is what the demo placeholders
# and Lia's future retarget both speak.
BONES = {
    "root": "Root",
    "hips": "Hips",
    "spine": ["Abdomen", "Torso", "Chest"],
    "neck": "Neck",
    "head": "Head",
    "shoulder": {"L": "Shoulder.L", "R": "Shoulder.R"},
    "upper": {"L": "UpperArm.L", "R": "UpperArm.R"},
    "lower": {"L": "LowerArm.L", "R": "LowerArm.R"},
    "hand": {"L": "Hand.L", "R": "Hand.R"},
    "upleg": {"L": "UpperLeg.L", "R": "UpperLeg.R"},
    "loleg": {"L": "LowerLeg.L", "R": "LowerLeg.R"},
    "foot": {"L": "Foot.L", "R": "Foot.R"},
    "toe": {"L": "Foot.L_end", "R": "Foot.R_end"},
}
SIDES = ("L", "R")

FINGERS = {
    "thumb": ["Thumb2", "Thumb3"],
    "index": ["Index2", "Index3", "Index4"],
    "middle": ["Middle2", "Middle3", "Middle4"],
    "ring": ["Ring2", "Ring3", "Ring4"],
    "pinky": ["Pinky2", "Pinky3", "Pinky4"],
}


class Rig(object):
    def __init__(self, arm_obj):
        self.ob = arm_obj
        self.pb = arm_obj.pose.bones
        self.rest = {}                 # name -> bone.matrix_local (armature space)
        self.rest_len = {}             # name -> rest bone length
        self._grip_cache = {}
        for b in arm_obj.data.bones:
            self.rest[b.name] = b.matrix_local.copy()
            self.rest_len[b.name] = b.length
        self._check()
        for s in SIDES:
            self.grip_frame(s)

    # -- introspection ------------------------------------------------------

    def _need(self, name):
        if name not in self.pb:
            die("rig is missing bone '%s'" % name)
        return name

    def _check(self):
        need = [BONES["root"], BONES["hips"]] + BONES["spine"] + [BONES["neck"], BONES["head"]]
        for s in SIDES:
            for k in ("shoulder", "upper", "lower", "hand", "upleg", "loleg", "foot"):
                need.append(BONES[k][s])
        for n in need:
            self._need(n)
        log("rig ok: %d bones" % len(self.pb))

    def rest_head(self, name):
        return self.rest[name].translation.copy()

    def rest_matrix(self, name):
        return self.rest[name].copy()

    def head(self, name):
        return self.pb[name].matrix.translation.copy()

    def tail(self, name):
        return self.pb[name].tail.copy()

    def length(self, name):
        return self.rest_len[name]

    def aim_of(self, name):
        return (self.tail(name) - self.head(name)).normalized()

    def upd(self):
        bpy.context.view_layer.update()

    def char_frame(self):
        """Derive forward/right/up from the feet in the CURRENT pose is wrong
        (feet move); derive from REST, once."""
        toes = {}
        for s in SIDES:
            a = self.rest_head(BONES["foot"][s])
            b = self.rest_head(BONES["toe"][s])
            toes[s] = b - a
        up = Vector((0.0, 0.0, 1.0))
        fwd = Vector()
        for s in SIDES:
            t = toes[s].copy()
            t.z = 0.0
            fwd += t
        fwd /= 2.0
        if fwd.length < 1e-4:
            die("cannot derive facing: both foot bones point straight down")
        fwd.normalize()
        # keep `fwd` horizontal and make the frame right-handed: r x f = u
        right = fwd.cross(up)
        right.normalize()
        cf = CharFrame(self.rest_head(BONES["hips"]), fwd, right, up)

        # -- the check that makes the frame trustworthy --------------------
        # Foot.L must sit on the character's LEFT, i.e. at NEGATIVE `right`.
        fl = cf.decompose(self.rest_head(BONES["foot"]["L"]))[1]
        fr = cf.decompose(self.rest_head(BONES["foot"]["R"]))[1]
        if not (fl < -1e-3 and fr > 1e-3):
            die("left/right convention wrong: Foot.L r=%.4f Foot.R r=%.4f" % (fl, fr))
        if abs(fr - fl) < 0.02:
            die("feet only %.4f m apart -- rig is not standing" % abs(fr - fl))
        log("char frame: fwd=%s  right=%s  feet r=%.3f / %.3f"
            % (tuple(round(v, 3) for v in cf.fwd),
               tuple(round(v, 3) for v in cf.right), fl, fr))
        return cf

    # -- posing primitives (all armature space, all update before returning) --

    def reset(self):
        for b in self.pb:
            b.rotation_mode = "QUATERNION"
            b.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
            b.location = (0.0, 0.0, 0.0)
            b.scale = (1.0, 1.0, 1.0)
        self.upd()

    def set_matrix(self, name, M):
        self.pb[name].matrix = M
        self.upd()

    def translate_root(self, world_delta):
        self.set_matrix(BONES["root"],
                        Matrix.Translation(Vector(world_delta)) @ self.rest[BONES["root"]])

    def place(self, name, delta, R3=None):
        """Move a bone by `delta` (world) and rotate its basis by R3 about its
        rest head.  Used on Hips."""
        rest = self.rest[name]
        head = rest.translation.copy()
        M = Matrix.Translation(head) @ (R3.to_4x4() if R3 else Matrix.Identity(4)) \
            @ Matrix.Translation(-head) @ rest
        M = Matrix.Translation(Vector(delta)) @ M
        self.set_matrix(name, M)

    def rot_world(self, name, R3):
        """Rotate a bone in place, in world axes, about its current head."""
        m = self.pb[name].matrix.copy()
        head = m.translation.copy()
        M = Matrix.Translation(head) @ R3.to_4x4() @ Matrix.Translation(-head) @ m
        M.translation = head
        # the rotation must not move the head
        self.pb[name].matrix = M
        self.upd()

    def aim(self, name, y_dir, z_hint):
        head = self.pb[name].matrix.translation.copy()
        x, y, z = orthonormalise(y_dir, z_hint)
        self.pb[name].matrix = mat_from_cols(x, y, z, head)
        self.upd()

    def set_basis(self, name, basis3):
        """Give a bone an exact world basis (3x3), keeping its head."""
        head = self.pb[name].matrix.translation.copy()
        M = basis3.to_4x4()
        M.translation = head
        self.pb[name].matrix = M
        self.upd()

    # -- IK -----------------------------------------------------------------

    def ik2(self, root, mid, end, target, pole):
        """Analytic two-bone IK.

        `target` is the position of `end`'s head.  Returns the MISS DISTANCE
        (0.0 = reached).  A caller that ignores the return value is how you get
        a straight-armed fake that looks like the character is reaching.
        """
        S = self.pb[root].matrix.translation.copy()
        L1 = (self.rest_head(mid) - self.rest_head(root)).length
        L2 = (self.rest_head(end) - self.rest_head(mid)).length
        T = Vector(target)
        v = T - S
        d = v.length
        if d < 1e-6:
            return 1e9
        axis = v / d
        d_cl = clamp(d, abs(L1 - L2) + 1e-4, L1 + L2 - 1e-4)
        Tp = S + axis * d_cl
        a = (L1 * L1 - L2 * L2 + d_cl * d_cl) / (2.0 * d_cl)
        h2 = L1 * L1 - a * a
        h = math.sqrt(h2) if h2 > 0.0 else 0.0
        pv = Vector(pole)
        pv = pv - axis * pv.dot(axis)
        if pv.length < 1e-6:
            die("ik2 pole is parallel to the limb axis (%s)" % root)
        pv.normalize()
        elbow = S + axis * a + pv * h
        hinge = axis.cross(pv).normalized()
        self.aim(root, elbow - S, hinge)
        self.aim(mid, Tp - elbow, hinge)
        return (T - Tp).length

    def ik_arm(self, side, wrist_target, elbow_pole):
        return self.ik2(BONES["upper"][side], BONES["lower"][side],
                        BONES["hand"][side], wrist_target, elbow_pole)

    def ik_leg(self, side, ankle_target, knee_pole):
        return self.ik2(BONES["upleg"][side], BONES["loleg"][side],
                        BONES["foot"][side], ankle_target, knee_pole)

    # -- the hand's own grip frame -----------------------------------------

    def grip_frame(self, side):
        """The frame a rod sits in when this hand grips it, expressed in
        ARMATURE space at rest (columns: X = edge side, Y = thumb side,
        Z = knuckle line / toward the tip).  MEASURED off the hand's own joints:

          Z = pinky knuckle -> index knuckle.  A gripped rod runs along the
              knuckle line, and the index knuckle is the one nearest the tsuba,
              so +Z is "toward the tip".
          Y = the thumb side, orthogonalised against Z.  A katana's mune sits in
              the V between thumb and index, so +X (the spine side of the shared
              sword/saya frame) lands on the thumb side.
          X = Y x Z, i.e. the direction the edge faces.

        The returned frame is in armature space; `apply_grip` converts it to the
        hand bone's own space before using it, because a bone's pose `matrix` is
        a bone-local -> armature map and mixing the two is a silent 90 deg error.
        """
        hb = BONES["hand"][side]
        head = self.rest_head(hb)
        f = FINGERS
        need = [f["index"][0], f["pinky"][0], f["thumb"][0], f["index"][1]]
        for n in need:
            if n + "." + side not in self.rest:
                die("no finger bone '%s.%s'" % (n, side))
        idx = self.rest_head(f["index"][0] + "." + side)
        pnk = self.rest_head(f["pinky"][0] + "." + side)
        thb = self.rest_head(f["thumb"][0] + "." + side)
        idx3 = self.rest_head(f["index"][1] + "." + side)
        Z = idx - pnk
        if Z.length < 1e-4:
            die("knuckle line is degenerate on %s" % side)
        Z.normalize()
        Y = (thb - head)
        Y = Y - Z * Y.dot(Z)
        if Y.length < 1e-5:
            die("cannot find the thumb side on %s" % side)
        Y.normalize()
        curl = (idx3 - idx)
        if curl.length > 1e-5:
            c = curl.normalized()
            if abs(c.dot(Z)) > 0.9:
                die("finger curl runs along the knuckle line on %s" % side)
            # the fingers must curl toward the palm, i.e. across the thumb side
            if abs(c.dot(Y)) < 0.15:
                die("finger curl is not in the palm plane on %s" % side)
        X = Y.cross(Z)
        H = mat_from_cols(X, Y, Z).to_3x3()
        self._grip_cache[side] = H
        log("grip frame %s: knuckle line %.4f m, thumb offset %.4f m, "
            "curl.Z=%.3f curl.Y=%.3f"
            % (side, (idx - pnk).length, (thb - head).length,
               curl.normalized().dot(Z) if curl.length > 1e-5 else 0.0,
               curl.normalized().dot(Y) if curl.length > 1e-5 else 0.0))
        return H

    def rod_basis_for_grip(self, side):
        """The rod basis (X = spine side, Y = toward the rod's far end,
        Z = flat) that the hand's measured grip frame expects, so that
        grip_frame == rod basis."""
        return self.grip_frame(side)

    def grip_centre_local(self, side):
        """Where the rod's centreline sits inside the fist, in the HAND BONE's
        own space.  Mean of the four finger bases -- a fist closes around its
        knuckles, not around the wrist."""
        key = ("gc", side)
        if key in self._grip_cache:
            return self._grip_cache[key].copy()
        heads = [self.rest_head(FINGERS[g][0] + "." + side)
                 for g in ("index", "middle", "ring", "pinky")]
        c = Vector((0.0, 0.0, 0.0))
        for h in heads:
            c += h
        c /= 4.0
        d = c - self.rest_head(BONES["hand"][side])
        loc = self.rest[BONES["hand"][side]].to_3x3().inverted() @ d
        self._grip_cache[key] = loc
        log("grip centre %s: %.4f m from the wrist (local %s)"
            % (side, d.length, tuple(round(v, 4) for v in loc)))
        return loc.copy()

    def grip_basis(self, side, sword_basis3):
        """The hand bone's desired armature-space basis for gripping a rod whose
        frame is `sword_basis3` (columns: X = spine/mune side, Y = toward the
        tip, Z = the flat).

        Both the measured grip frame and the rod frame are armature-space
        directions; the hand's own basis lives in bone space, so the conversion
        `H_local = rest_basis^-1 @ H_arm` is what stops this from being a
        quarters-turn guess.  Split out from `apply_grip` so a caller can know
        the answer BEFORE posing the arm -- which is what makes an exact
        one-pass IK to the hilt possible.
        """
        H_arm = self._grip_cache.get(side)
        if H_arm is None:
            H_arm = self.grip_frame(side)
        rest_b = self.rest[BONES["hand"][side]].to_3x3()
        H_local = rest_b.inverted() @ H_arm
        W = mat_from_cols(sword_basis3.col[2], sword_basis3.col[0],
                          sword_basis3.col[1]).to_3x3()
        return W @ H_local.inverted()

    def apply_grip(self, side, sword_basis3):
        basis = self.grip_basis(side, sword_basis3)
        self.set_basis(BONES["hand"][side], basis)
        return basis

    def curl_fingers(self, side, amount, rod_axis):
        """Close the hand around the rod.

        The hinge is the ROD AXIS: a finger starts pointing away from the rod
        and wraps around it, so the motion lives in the plane perpendicular to
        the rod.  The sign is mirrored between hands.  A flat low-poly hand has
        no palm arch, so this is deliberately a whole-hand curl and nothing
        cleverer is claimed.
        """
        if abs(amount) < 0.01:
            return
        axis = Vector(rod_axis).normalized()
        sign = -1.0 if side == "R" else 1.0
        R = Matrix.Rotation(rad(amount) * sign, 3, axis)
        for grp in ("index", "middle", "ring", "pinky"):
            prev = R
            for bone in FINGERS[grp]:
                n = bone + "." + side
                if n in self.pb:
                    self.rot_world(n, R)
        t0 = FINGERS["thumb"][0] + "." + side
        t1 = FINGERS["thumb"][1] + "." + side
        for n in (t0, t1):
            if n in self.pb:
                self.rot_world(n, Matrix.Rotation(rad(amount) * sign * -0.45, 3, axis))

    # -- snapshots ----------------------------------------------------------

    def snapshot(self):
        out = {}
        for b in self.pb:
            out[b.name] = (b.rotation_quaternion.copy(), b.location.copy())
        return out

    def apply_snapshot(self, snap):
        for n, (q, loc) in snap.items():
            b = self.pb[n]
            b.rotation_mode = "QUATERNION"
            b.rotation_quaternion = q
            b.location = loc
        self.upd()


# ---------------------------------------------------------------------------
#  standalone dump
# ---------------------------------------------------------------------------

def _dump(argv):
    clear_scene()
    objs = import_glb(argv["char"])
    arms = [o for o in objs if o.type == "ARMATURE"]
    if not arms:
        die("no armature in %s" % argv["char"])
    rig = Rig(arms[0])
    cf = rig.char_frame()
    print("\n%-16s %8s %8s %8s   %s" % ("bone", "f", "r", "u", "len(m)"))
    for b in sorted(rig.pb.keys(), key=lambda n: -rig.rest_head(n).z):
        h = rig.rest_head(b)
        f, r, u = cf.decompose(h)
        print("%-16s %+8.4f %+8.4f %+8.4f   %.4f" % (b, f, r, u, rig.length(b)))
    print("\nheight: head=%.4f  head_end=%.4f" %
          (rig.rest_head("Head").z, rig.rest_head("Head_end").z))
    for s in SIDES:
        rig.grip_frame(s)
        for k in ("upper", "lower"):
            print("  arm %s %-6s len=%.4f" % (s, k, rig.length(BONES[k][s])))


def _parse(argv):
    out = {}
    for i in range(0, len(argv) - 1, 2):
        out[argv[i].lstrip("-")] = argv[i + 1]
    return out


if __name__ == "__main__":
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not a or "--dump" in a:
        _dump(_parse(a) if a else {})
