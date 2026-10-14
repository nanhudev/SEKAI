#!/usr/bin/env python3
"""Retarget the Quaternius Universal Animation Library onto ANY humanoid rig.

Why: the animation library ships with a Rigify-style rig (`DEF-upper_arm.L`, ...)
while character packs ship their own naming (`UpperArm.L`, ...).  Same skeleton
topology, different labels -> no drop-in.  This bakes clip-by-clip so the result
is a single self-contained GLB with real AnimationPlayer clips in Godot.

Method (world-delta rotation retarget, no constraints, no third-party retargeter):
  For every mapped bone pair, per frame:
      D      = pose_src @ rest_src^-1        (the world rotation the source bone performed)
      R_des  = D @ rest_tgt                  (same rotation applied to the target rest)
      R_basis= (R_parent_des @ R_rest_offs)^-1 @ R_des
  Worked entirely in ARMATURE SPACE so it is immune to whatever object-level
  transform the FBX / glTF importer bolted on.  Bone roll and bone-direction
  conventions cancel out, which is why this survives Mixamo/Rigify/etc.

Proportion differences are handled by scaling hip translation by the hip-height
ratio; all other bones are rotation-only, which is what keeps foot/hand contacts
sane across rigs of different lengths.

Output: one GLB per character, N clips, ready for Godot.

    "/g/blender.exe" -b --factory-startup --python tools/character/retarget_humanoid.py -- \
        --target <character.fbx> --lib <AnimationLibrary_Godot_Standard.glb> \
        --name lia_placeholder --out-glb <dir> --target-height 1.70 \
        --clips all --fps 30
"""
import json
import math
import os
import re
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

# ---------------------------------------------------------------- args

ARGS = {}
if "--" in sys.argv:
    argv = sys.argv[sys.argv.index("--") + 1:]
    for i in range(0, len(argv) - 1, 2):
        ARGS[argv[i].lstrip("-")] = argv[i + 1]

TARGET = os.path.abspath(ARGS["target"])
LIB = os.path.abspath(ARGS["lib"])
NAME = ARGS.get("name") or os.path.splitext(os.path.basename(TARGET))[0]
OUT_GLB = os.path.abspath(ARGS.get("out-glb", "."))
OUT_JSON = ARGS.get("out-json") or os.path.join(OUT_GLB, "%s_retarget.json" % NAME)
TARGET_HEIGHT = float(ARGS.get("target-height", 0.0))
FPS = int(ARGS.get("fps", 30))
CLIPS = ARGS.get("clips", "all")
SKIP = [c.strip() for c in ARGS.get("skip", "A_TPose").split(",") if c.strip()]
# Bones to leave at the TARGET's own rest pose.  Fingers are excluded by default:
# the library's mannequin clenches its fists (~170 deg per joint), which is a
# perfectly sensible MANNEQUIN, but those three-bone fingers on a low-poly hand
# are authored for a relaxed hand - driving them with that delta folds them back
# through the palm.  Stylised characters read better with the author's hand.
EXCLUDE = re.compile(ARGS.get("exclude", r"^(Index|Middle|Ring|Pinky|Thumb)\d\.[LR]$"))
PROBE = [b.strip() for b in ARGS.get("probe", "").split(",") if b.strip()]

os.makedirs(OUT_GLB, exist_ok=True)


def log(m):
    print("[RETGT] %s" % m, flush=True)


# ---------------------------------------------------------------- bone map
# Matching is done on NORMALISED names, not a fixed dictionary, because the
# Quaternius packs disagree with each other: the women's rig spells fingers
# `Index1/2/3.L` while the (newer) universal rig spells them `Index2/3/4.L` and
# appends `_end` leaf bones.  A rigid dict silently maps 20/62 bones and you ship
# a character whose arms never move.  So: normalise -> alias -> match by
# (part, side); fingers are paired POSITIONALLY along each chain, which is
# immune to whatever numbering a pack happens to use.

ALIASES = {
    "hips": "hips", "pelvis": "hips", "hip": "hips",
    "spine001": "spine1", "abdomen": "spine1", "spine1": "spine1",
    "spine002": "spine2", "torso": "spine2", "spine2": "spine2", "spine": "spine2",
    "spine003": "spine3", "chest": "spine3", "spine3": "spine3",
    "neck": "neck", "head": "head",
    "shoulder": "shoulder", "clavicle": "shoulder",
    "upperarm": "upperarm", "arm": "upperarm",
    "forearm": "lowerarm", "lowerarm": "lowerarm",
    "hand": "hand", "wrist": "hand",
    "upperleg": "upperleg", "thigh": "upperleg", "upleg": "upperleg",
    "lowerleg": "lowerleg", "shin": "lowerleg", "calf": "lowerleg",
    "foot": "foot", "ankle": "foot",
    "toe": "toe", "toebase": "toe",
}
FAMILIES = (("index", ("findex", "index")), ("middle", ("fmiddle", "middle")),
            ("ring", ("fring", "ring")), ("pinky", ("fpinky", "pinky")),
            ("thumb", ("fthumb", "thumb")))


def _strip_end(s):
    return re.sub(r"[-_]?end$", "", s, flags=re.I)


def _strip_side(s):
    return re.sub(r"[._-][LR]$", "", s, flags=re.I)


def _stem(name):
    s = _strip_end(name).lower()
    s = re.sub(r"^def[-_]", "", s)
    return re.sub(r"[^a-z0-9]", "", s)


def _core(name):
    """stem with the side marker removed - `UpperLeg.L` -> `upperleg`."""
    return _stem(_strip_side(name))


def _side(name):
    s = _strip_end(name)
    m = re.search(r"[._-]([LR])$", s)
    return m.group(1).upper() if m else ""


def _family(name):
    s = _stem(name)
    for fam, keys in FAMILIES:
        for k in keys:
            if s.startswith(k):
                return fam
    return None


def build_pairs(src_bones, tgt_bones):
    """map target bone -> source bone; returns (pairs, unmapped_targets, stats)"""
    def norm_lookup(names):
        bykey = {}
        for n in names:
            if re.search(r"[-_]end$", n, re.I):
                continue
            fam = _family(n)
            if fam:
                continue
            key = ALIASES.get(_core(n))
            if key is None:
                continue
            bykey.setdefault((key, _side(n)), n)
        return bykey

    s_by, t_by = norm_lookup(src_bones), norm_lookup(tgt_bones)
    out, unmapped = [], []
    for t_name in tgt_bones:
        key = ALIASES.get(_core(t_name))
        if key is None or _family(t_name):
            unmapped.append(t_name)
            continue
        s_name = s_by.get((key, _side(t_name)))
        if s_name:
            out.append((t_name, s_name))
        else:
            unmapped.append(t_name)

    # fingers: pair positionally along each (family, side) chain
    def chain(names, fam, sd):
        picked = [n for n in names if _family(n) == fam and _side(n) == sd]
        return sorted(picked, key=lambda n: (_chain_depth(n, names), len(n), n))

    def _chain_depth(n, names):
        return _stem(n)

    for fam, _ in FAMILIES:
        for sd in ("L", "R"):
            ss = chain(src_bones, fam, sd)
            ts = chain(tgt_bones, fam, sd)
            ss = [n for n in ss if not re.search(r"[-_]end$", n, re.I)]
            ts = [n for n in ts if not re.search(r"[-_]end$", n, re.I)]
            # order by the trailing joint index when present, else by name
            def jidx(n):
                m = re.search(r"(\d+)", _stem(n))
                return int(m.group(1)) if m else 0
            ss.sort(key=jidx)
            ts.sort(key=jidx)
            for a, b in zip(ss, ts):
                out.append((b, a))
            for b in ts[len(ss):]:
                unmapped.append(b)

    unmapped = [n for n in unmapped if n not in {t for t, _ in out}]
    return out, unmapped


# ---------------------------------------------------------------- rig normalisation


def normalise_leg_chain(arm):
    """Attach the leg chains to the pelvis; returns (names, head_drift_m).

    Quaternius' WOMEN pack hangs `UpperLeg.L/R` off the ROOT bone -- a leftover
    of their modular rig -- while their MEN pack hangs them off `Hips`.  A
    rotation-only retarget cannot tell the difference and silently produces two
    different behaviours from the same clip.  Measured, `Sitting_Idle`:

        women  hips 0.891 -> 0.551   UpperLeg 0.964 -> 0.964   (frozen: the
                                                               pelvis sinks and
                                                               leaves the legs
                                                               hanging -> "sits
                                                               on an invisible
                                                               chair")
        men    hips 0.783 -> 0.484   UpperLeg 0.846 -> 0.548   (follows)

    Edit-mode re-parenting does NOT move the bone: `EditBone.head/tail` are
    armature-space, so the rest pose, `matrix_local`, and the skin bind are all
    untouched -- only the chain changes.  This is measured below rather than
    assumed, because "should not move" is how rest poses get broken.
    """
    bones = arm.data.bones
    roots = {b.name for b in bones if b.parent is None}
    legs = [b.name for b in bones
            if ALIASES.get(_core(b.name)) == "upperleg"
            and b.parent is not None and b.parent.name in roots]
    if not legs:
        return [], 0.0
    hips = next((b.name for b in bones if ALIASES.get(_core(b.name)) == "hips"), None)
    if hips is None:
        log("!! %d leg chain(s) hang off a root bone and there is no hips bone to "
            "attach them to - the pelvis will not carry the legs" % len(legs))
        return [], 0.0

    bpy.context.view_layer.objects.active = arm
    if arm.mode != "EDIT":
        bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    before = {n: eb[n].head.copy() for n in legs + [hips]}
    for n in legs:
        eb[n].parent = eb[hips]
        eb[n].use_connect = False          # else Blender snaps head -> parent tail
    after = {n: eb[n].head.copy() for n in legs + [hips]}
    drift = max((before[n] - after[n]).length for n in before)
    bpy.ops.object.mode_set(mode="OBJECT")
    return legs, drift


# ---------------------------------------------------------------- import

bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
scn = bpy.context.scene
scn.render.fps = FPS
scn.render.fps_base = 1.0

log("importing target %s" % os.path.basename(TARGET))
bpy.ops.import_scene.fbx(filepath=TARGET, global_scale=1.0)

tgt_meshes = [o for o in bpy.context.selected_objects if o.type == "MESH"]
tgt_arms = [o for o in bpy.context.selected_objects if o.type == "ARMATURE"]
if not tgt_arms:
    raise SystemExit("no armature in target")
ARM_T = tgt_arms[0]
log("target armature '%s' bones=%d meshes=%d" % (ARM_T.name, len(ARM_T.data.bones), len(tgt_meshes)))

# ---- rig normalisation: legs must hang off the pelvis, not the root bone
_legs, _drift = normalise_leg_chain(ARM_T)
if _legs:
    log("re-parented leg chain to the pelvis: %s  (head drift %.6f m)"
        % (", ".join(_legs), _drift))
    if _drift > 1e-5:
        raise SystemExit("leg re-parent moved the rest pose by %.6f m - aborting "
                         "rather than baking a broken bind" % _drift)

# ---- force opaque materials
# The Quaternius FBX ships every material with Principled alpha = 0.  The glTF
# exporter faithfully writes baseColorFactor alpha 0 -> the character imports
# into Godot fully transparent and NOTHING renders.  Silent, and it cost a
# debugging round; fix it here rather than in every consumer.
_fixed_alpha = 0
for mat in bpy.data.materials:
    if not mat.use_nodes:
        mat.diffuse_color[3] = 1.0
        continue
    for node in mat.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            inp = node.inputs.get("Alpha")
            if inp is not None and abs(inp.default_value - 1.0) > 1e-6:
                inp.default_value = 1.0
                _fixed_alpha += 1
    mat.diffuse_color[3] = 1.0
    for attr, val in (("blend_method", "OPAQUE"), ("shadow_method", "OPAQUE"),
                      ("surface_render_method", "DITHERED")):
        if hasattr(mat, attr):
            try:
                setattr(mat, attr, val)
            except (TypeError, AttributeError):
                pass
log("forced alpha=1.0 on %d Principled inputs across %d materials"
    % (_fixed_alpha, len(bpy.data.materials)))

# ---- optional uniform rescale (do it before retargeting, else proportions lie)

def _world_z_extent(objs):
    """Union world-space bbox of every object's bound_box corners."""
    bpy.context.view_layer.update()
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    return mn, mx


RESCALE_K = 1.0
ACTUAL_HEIGHT = 0.0

if TARGET_HEIGHT > 0:
    mn, mx = _world_z_extent(tgt_meshes)
    h0 = mx.z - mn.z
    k = TARGET_HEIGHT / h0

    # Scale only the TOP of each hierarchy. The imported meshes are parented to
    # the armature (parent_type=OBJECT) and therefore ALREADY inherit its scale;
    # scaling parent and child both applies k twice and silently yields h0*k^2.
    # Adventurer came out 1.581 m instead of 1.70 (7% short), yet the requested
    # number still got written into the metadata -- so nobody noticed.
    _names = set(o.name for o in tgt_meshes + tgt_arms)
    roots = [o for o in tgt_meshes + tgt_arms
             if o.parent is None or o.parent.name not in _names]

    log("rescale height %.4f -> %.4f (x%.5f) via %d root object(s): %s"
        % (h0, TARGET_HEIGHT, k, len(roots), [o.name for o in roots]))
    for o in roots:
        o.scale = o.scale * k
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    for o in roots:
        o.select_set(True)
    bpy.context.view_layer.objects.active = ARM_T if ARM_T in roots else roots[0]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.select_all(action="DESELECT")

    # VERIFY, don't trust: transform_apply reporting OK does not mean the world
    # extent moved by k. Measure the result and record the measured value.
    RESCALE_K = k
    mn1, mx1 = _world_z_extent(tgt_meshes)
    ACTUAL_HEIGHT = mx1.z - mn1.z
    drift = abs(ACTUAL_HEIGHT - TARGET_HEIGHT) / TARGET_HEIGHT
    log("rescale verify h=%.4f (target %.4f, drift %+.2f%%)"
        % (ACTUAL_HEIGHT, TARGET_HEIGHT, drift * 100.0))
    if drift > 0.01:
        log("!! HEIGHT OFF BY %.1f%% -- rescale did not land; check parent/inherit"
            % (drift * 100.0))

# ---------------------------------------------------------------- source

log("importing library %s" % os.path.basename(LIB))
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=LIB)
new_objs = [o for o in bpy.data.objects if o not in before]
ARM_S = next((o for o in new_objs if o.type == "ARMATURE"), None)
if ARM_S is None:
    raise SystemExit("no armature in library")
src_mesh_objs = [o for o in new_objs if o.type == "MESH"]
src_actions = [a for a in bpy.data.actions]
# Park the library actions under a namespace so our baked actions get the clean
# clip name; they are deleted before export (otherwise the glTF exporter in
# ACTIONS mode re-exports them and you get ~45 dead clips alongside the good ones).
for a in src_actions:
    a.name = "__src__" + a.name
log("library armature '%s' bones=%d, %d actions" % (ARM_S.name, len(ARM_S.data.bones), len(src_actions)))

# ---------------------------------------------------------------- build plan

bones_t = list(ARM_T.data.bones)


def parent_chain(name):
    out, b = [], ARM_T.data.bones[name]
    while b:
        out.append(b.name)
        b = b.parent
    return list(reversed(out))


order = sorted([b.name for b in bones_t], key=lambda n: len(parent_chain(n)))
_pairs, _unmapped = build_pairs([b.name for b in ARM_S.data.bones], order)
pairs = [(t, s) for t, s in _pairs if ARM_S.data.bones.get(s)]
missing = [s for t, s in _pairs if not ARM_S.data.bones.get(s)]
managed = {t for t, _ in pairs}

if EXCLUDE.pattern:
    kept, dropped = [], []
    for t, s in pairs:
        (dropped if EXCLUDE.match(t) else kept).append((t, s))
    if dropped:
        log("excluded from retarget (kept at target rest): %d bones -> %s"
            % (len(dropped), ", ".join(t for t, _ in dropped[:6]) + (" ..." if len(dropped) > 6 else "")))
    pairs = kept
    managed = {t for t, _ in pairs}

log("mapped %d / %d target bones%s" % (
    len(pairs), len(bones_t), ("  (source missing: %s)" % missing) if missing else ""))
if _unmapped:
    log("unmapped target bones (%d): %s" % (
        len(_unmapped), ", ".join(_unmapped[:12]) + (" ..." if len(_unmapped) > 12 else "")))

# hips height ratio drives translation scaling
_hips_candidates = [t for t in managed if ALIASES.get(_core(t)) == "hips"]
if not _hips_candidates:
    raise SystemExit("no hips bone mapped - check ALIASES")
hips_t = _hips_candidates[0]
hips_s = dict((t, s) for t, s in pairs)[hips_t]
rest_t = {n: ARM_T.data.bones[n].matrix_local.copy() for n in managed}
rest_s = {n: ARM_S.data.bones[n].matrix_local.copy() for _, n in pairs}
off_t = {}
for n in managed:
    b = ARM_T.data.bones[n]
    off_t[n] = (b.parent.matrix_local.inverted() @ b.matrix_local) if b.parent else Matrix.Identity(4)

z_t = rest_t[hips_t].translation.z
z_s = rest_s[hips_s].translation.z
HIP_RATIO = (z_t / z_s) if (abs(z_s) > 1e-6 and abs(z_t) > 1e-6) else 1.0
log("hip rest z  target=%.4f  source=%.4f  ratio=%.4f" % (z_t, z_s, HIP_RATIO))

# ---------------------------------------------------------------- frame bridge
# `pose.bones[].matrix` and `bone.matrix_local` are both ARMATURE-space, so they
# are immune to object-level transforms - but the two armatures can still be
# oriented differently (glTF import vs FBX import bolt on different axis fixes).
# A rotation delta read in source-armature space must therefore be conjugated into
# target-armature space, otherwise every bone gets the delta applied about the
# wrong axes.  When both objects are oriented the same way C == identity and this
# is a no-op - which is exactly why it is easy to miss.
MS = ARM_S.matrix_world.to_3x3().normalized()
MT = ARM_T.matrix_world.to_3x3().normalized()
CONJ = MT.inverted() @ MS
CONJ_INV = CONJ.inverted()
_ci = CONJ.to_quaternion().angle
log("armature frames: source=%s" % [round(v, 4) for v in MS.to_euler()])
log("armature frames: target=%s  conjugation=%.2f deg" % (
    [round(v, 4) for v in MT.to_euler()], math.degrees(_ci)))
DEBUG = "--debug" in sys.argv

# ---------------------------------------------------------------- bake

if CLIPS.strip().lower() == "all":
    # NOTE: src_actions were namespaced to "__src__<clip>" back when they were
    # imported, so strip that back off here. Reading a.name raw makes `want` hold
    # prefixed names, while the match below compares against the stripped name --
    # they never intersect and `--clips all` silently bakes 0 clips.
    want = [a.name.replace("__src__", "", 1) for a in src_actions]
else:
    want = [c.strip() for c in CLIPS.split(",") if c.strip()]
want = [w for w in want if not any(w == s or w.startswith(s) for s in SKIP)]

ARM_T.animation_data_create()
made = []


def bake_action(src_action, clip_name):
    ARM_S.animation_data_create()
    ARM_S.animation_data.action = src_action
    # Blender 4.4+: assigning an action leaves the slot unset -> nothing evaluates
    try:
        if ARM_S.animation_data.action_slot is None and src_action.slots:
            ARM_S.animation_data.action_slot = src_action.slots[0]
    except AttributeError:
        pass

    f0, f1 = (int(math.floor(src_action.frame_range[0])),
              int(math.ceil(src_action.frame_range[1])))
    if f1 <= f0:
        return None

    act = bpy.data.actions.new(clip_name)
    act.use_fake_user = True
    ARM_T.animation_data.action = act
    try:
        if ARM_T.animation_data.action_slot is None and act.slots:
            ARM_T.animation_data.action_slot = act.slots[0]
    except AttributeError:
        pass

    for pb in ARM_T.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)

    probe_rows = []
    for f in range(f0, f1 + 1):
        scn.frame_set(f)
        bpy.context.view_layer.update()

        des = {}
        angles = {}
        for t_name, s_name in pairs:
            br_s = rest_s[s_name]
            bp_s = ARM_S.pose.bones[s_name].matrix
            D = CONJ @ (bp_s.to_3x3() @ br_s.to_3x3().inverted()) @ CONJ_INV
            D.normalize()
            br_t = rest_t[t_name]
            R_des = (D @ br_t.to_3x3()).normalized()
            angles[t_name] = math.degrees(D.to_quaternion().angle)
            if PROBE and t_name in PROBE:
                probe_rows.append((f, t_name, angles[t_name]))

            bone = ARM_T.data.bones[t_name]
            pname = bone.parent.name if bone.parent is not None else ""
            if pname != "" and pname in des:
                R_par = des[pname].to_3x3().normalized()
            elif pname != "" and pname in managed:
                # The parent is retargeted but has not been computed yet, so the
                # fallback below would quietly use its REST rotation and the child
                # would inherit the wrong world orientation.  Silent failure --
                # refuse to bake it instead of shipping a broken chain.
                raise SystemExit(
                    "bake order: '%s' is processed before its retargeted parent "
                    "'%s'; results would silently use the parent's rest rotation"
                    % (t_name, pname))
            elif pname != "":
                # parent is not retargeted -> it sits at its own rest pose
                R_par = ARM_T.data.bones[pname].matrix_local.to_3x3().normalized()
            else:
                R_par = Matrix.Identity(3)
            R_offs = off_t[t_name].to_3x3().normalized()
            R_basis = (R_par @ R_offs).inverted() @ R_des
            des[t_name] = R_des.to_4x4()

            pb = ARM_T.pose.bones[t_name]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = R_basis.to_quaternion()

            if t_name == hips_t:
                dpos = CONJ @ ((bp_s.translation - br_s.translation) * HIP_RATIO)
                # hips basis translation: how far the bone head travels from rest,
                # expressed in the bone's own local axes
                local = (br_t.inverted() @ Matrix.Translation(rest_t[hips_t].translation + dpos)
                         @ R_des.to_4x4())
                pb.location = local.to_translation()
            else:
                pb.location = (0.0, 0.0, 0.0)

            pb.keyframe_insert(data_path="rotation_quaternion", frame=f, group=t_name)
            if t_name == hips_t:
                pb.keyframe_insert(data_path="location", frame=f, group=t_name)

        if DEBUG and f == (f0 + f1) // 2:
            top = sorted(angles.items(), key=lambda kv: -kv[1])[:14]
            log("  [debug] frame %d largest applied world rotations:" % f)
            for n, a in top:
                log("      %-16s %7.2f deg" % (n, a))

    for fc in iter_fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
        fc.update()

    if PROBE and probe_rows:
        by = {}
        for f, n, a in probe_rows:
            by.setdefault(n, []).append((f, a))
        log("  [probe] %s" % clip_name)
        for n, rows in by.items():
            step = max(1, len(rows) // 8)
            log("      %-16s %s" % (n, " ".join("f%d=%.0f" % (f, a) for f, a in rows[::step])))
    return (f0, f1)


def iter_fcurves(action):
    """Blender <4.4 has action.fcurves; 4.4+ uses slotted layers/channelbags."""
    try:
        fcs = list(action.fcurves)
        if fcs:
            return fcs
    except AttributeError:
        pass
    out = []
    try:
        for layer in action.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    out.extend(cb.fcurves)
    except AttributeError:
        pass
    return out


for a in src_actions:
    nm = a.name.replace("__src__", "", 1)
    if nm not in want:
        continue
    rng = bake_action(a, nm)
    if rng:
        made.append({"name": nm, "frames": [rng[0], rng[1]],
                     "seconds": round((rng[1] - rng[0]) / float(FPS), 3)})
        log("baked %-26s frames %d..%d" % (nm, rng[0], rng[1]))

log("baked %d clips" % len(made))

# ---------------------------------------------------------------- cleanup + export

ARM_T.animation_data.action = None
for a in src_actions:
    try:
        bpy.data.actions.remove(a)
    except (ReferenceError, RuntimeError):
        pass
for o in src_mesh_objs + [ARM_S]:
    bpy.data.objects.remove(o, do_unlink=True)

remaining = [a.name for a in bpy.data.actions]
log("actions in file after cleanup: %d %s" % (len(remaining), remaining[:4]))

# keep one clip assigned so the exporter always has an active animation
if made:
    ARM_T.animation_data.action = bpy.data.actions[made[0]["name"]]

bpy.ops.object.select_all(action="DESELECT")
kept = [o for o in bpy.data.objects if o.type in ("MESH", "ARMATURE")]
for o in kept:
    o.select_set(True)
bpy.context.view_layer.objects.active = ARM_T

glb = os.path.join(OUT_GLB, "%s.glb" % NAME)
bpy.ops.export_scene.gltf(
    filepath=glb,
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_apply=False,
    export_skins=True,
    export_morph=False,
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_bake_animation=False,
    export_optimize_animation_size=True,
    export_optimize_animation_keep_anim_armature=True,
    export_materials="EXPORT",
    export_normals=True,
    export_texcoords=True,
    export_tangents=False,
)

report = {
    "name": NAME,
    "target_fbx": TARGET.replace("\\", "/"),
    "lib": LIB.replace("\\", "/"),
    "target_armature": ARM_T.name,
    "target_bones": len(bones_t),
    "mapped_bones": len(pairs),
    "unmapped_target_bones": sorted(set(b.name for b in bones_t) - managed),
    "hip_ratio": round(HIP_RATIO, 5),
    "target_height_m": round(ACTUAL_HEIGHT, 4) if ACTUAL_HEIGHT > 0 else TARGET_HEIGHT,
    "target_height_requested": TARGET_HEIGHT,
    "rescale_k": round(RESCALE_K, 6),
    # Which rig normalisations had to be applied.  A future rig (formal Lia) that
    # needs no repair should record an empty list -- a diff here means the model
    # swap silently changed the skeleton *profile*, which the cast manifest
    # promises will not happen.
    "rig_repairs": (["legs_reparented_to_pelvis: " + ",".join(_legs)] if _legs else []),
    "leg_head_drift_m": round(_drift, 8),
    "fps": FPS,
    "clips": made,
    "glb": glb.replace("\\", "/"),
    "glb_bytes": os.path.getsize(glb),
}
with open(OUT_JSON, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2, ensure_ascii=False)
log("wrote %s (%.2f MB) + %s" % (glb, report["glb_bytes"] / 1048576.0, OUT_JSON))
print("[RETGT_DONE] clips=%d glb=%s" % (len(made), glb), flush=True)
