"""SEKAI weapon line -- SHARED BUILDER FRAMEWORK.

    blender -b --factory-startup --python tools/blender/<family>_build.py -- --row <id>

WHY THIS FILE EXISTS
====================
The line has to produce on the order of a hundred weapon variants across 18
families.  If every family builder re-implements "make a mesh", "bake the export
axes", "compute the AABB", "export the GLB", then a hundred assets means a
hundred chances to get the same six things wrong -- and every one of those
mistakes is SILENT in Godot.  A weapon that exports with its long axis on Z does
not raise an error; it just sits sideways in the player's hand, or misses the
scabbard mouth by ninety degrees, and that only shows up as "the sword looks
wrong" three sessions later.

So the infrastructure lives here, ONCE, and each family builder is only allowed
to answer one question: WHAT IS THE SHAPE.

What this module owns
---------------------
  * the unit (metres) and the per-class ORIGIN / AXIS contract, enforced
  * scene setup, mesh primitives, the material factory
  * the metal-trap guard (the single most repeated failure of this line)
  * sockets (empty Object3D anchors for FX and combat)
  * measurement: AABB, per-part AABB, triangle count, material list
  * ASSERTIONS that fail loudly and exit non-zero
  * GLB export with the fixed shipping settings
  * .blend tier routing (hero master vs regenerable variant)
  * the JSON spec loader
  * the first-person preview rig and the contact-sheet renderer
  * the CLI driver

THE ONE RULE
------------
`apply`-style builders must be pure functions of the spec row.  No hidden
module state, no "last time we built this we...".  If a value matters it is in
the row.

WHAT IS DELIBERATELY *NOT* HERE
-------------------------------
Shape.  There is no blade, no staff head, no chain link in this file.  A chain
link and a blade cross-section have nothing in common except that they are
loops of vertices, and pretending otherwise produces the worst kind of shared
code: an abstraction that fits neither.
"""

import math
import os
import sys
import json

import bpy
import bmesh
from mathutils import Matrix, Vector

TAU = math.pi * 2.0

REPO = "F:/SEKAI"


# =============================================================================
#  1. THE CONTRACT -- origin, orientation, budget
# =============================================================================
#
# These are the numbers from docs/weapons/WEAPON_LINE_STANDARD.md §2, but the
# document is not the authority here: THIS TABLE IS, and the builder asserts
# against it.  The document explains why; this file enforces.
#
# Authoring convention for every class: the family builder works in the pose
# that is convenient to author in (length down some axis), and then calls
# `bake_axes()` which rotates the MESH DATA -- not a node transform -- into the
# exported contract.  Baking into the data matters: a leftover root rotation is
# one downstream tool away from being dropped on the floor, and this project has
# already lost a session to exactly that class of bug.
#
#   long    axis the weapon's length runs along IN THE EXPORTED GLB
#   tip     sign the ATTACK END points toward along `long`
#   edge    axis+sign of the cutting edge for single-edge classes ("" if n/a)
#   spine   the axis the blade flat normal occupies
#   origin  plain-English description, for the report and for humans
#   tris    (min, max) triangle band.  From PART H: silhouette and screen size
#           decide this, so the band is per class rather than per asset.

CONTRACT = {
    "SWD": dict(long="Y", tip="+", edge="-X", spine="Z",
                origin="grip centre, at the guard plane",
                tris=(800, 80000), kind="single"),
    "KAT": dict(long="Y", tip="+", edge="-X", spine="Z",
                origin="grip centre, at the guard plane (koiguchi side)",
                tris=(800, 80000), kind="single"),
    "GSW": dict(long="Y", tip="+", edge="-X", spine="Z",
                origin="grip centre, at the guard plane",
                tris=(3000, 90000), kind="single"),
    "DGR": dict(long="Y", tip="+", edge="-X", spine="Z",
                origin="palm centre", tris=(400, 20000), kind="single"),
    "SCY": dict(long="Y", tip="+", edge="-X", spine="Z",
                origin="grip centre", tris=(2000, 60000), kind="single"),
    "STF": dict(long="Y", tip="+", edge="", spine="Z",
                origin="grip centre", tris=(1500, 70000), kind="none"),
    "SCP": dict(long="Y", tip="+", edge="", spine="Z",
                origin="grip centre", tris=(1500, 70000), kind="none"),
    "PLM": dict(long="Y", tip="+", edge="", spine="Z",
                origin="two-hand centre", tris=(1500, 60000), kind="none"),
    "RIT": dict(long="Y", tip="+", edge="", spine="Z",
                origin="grip centre", tris=(1500, 70000), kind="none"),
    "EAS": dict(long="Y", tip="+", edge="", spine="Z",
                origin="grip centre", tris=(800, 40000), kind="none"),
    "HAM": dict(long="Y", tip="+", edge="", spine="Z",
                origin="grip centre", tris=(1000, 50000), kind="none"),
    "CHN": dict(long="Y", tip="+", edge="", spine="Z",
                origin="butt link ring", tris=(300, 30000), kind="none"),
    "GNT": dict(long="Y", tip="+", edge="", spine="Z",
                origin="metacarpal centre", tris=(1000, 50000), kind="none"),
    "SHD": dict(long="Y", tip="+", edge="", spine="Z",
                origin="grip centre", tris=(1000, 50000), kind="none"),
    "BOW": dict(long="Y", tip="+", edge="", spine="Z",
                origin="grip centre", tris=(1200, 50000), kind="none"),
    "XBW": dict(long="Y", tip="+", edge="", spine="Z",
                origin="grip centre", tris=(1500, 60000), kind="none"),
    "THR": dict(long="Y", tip="+", edge="", spine="Z",
                origin="centre of mass", tris=(200, 12000), kind="none"),
}

# Sockets every family must publish, plus per-class extras.  `SOC_` and `FX_`
# prefixes are the whole convention: SOC = a point something attaches to,
# FX = a point an effect is anchored to.  Both are empty Object3D nodes with no
# geometry, so they cost nothing in the runtime and can be found by name.
BASE_SOCKETS = ["SOC_GRIP"]
CLASS_SOCKETS = {
    "SWD": ["SOC_TIP", "SOC_EDGE_MID", "SOC_MOUTH", "FX_TRAIL_A", "FX_TRAIL_B"],
    "KAT": ["SOC_TIP", "SOC_EDGE_MID", "SOC_MOUTH", "FX_TRAIL_A", "FX_TRAIL_B"],
    "GSW": ["SOC_TIP", "SOC_EDGE_MID", "FX_TRAIL_A", "FX_TRAIL_B"],
    "STF": ["SOC_HEAD", "FX_CORE", "FX_RUNE"],
    "CHN": ["SOC_LINK_OUT", "SOC_HEAD"],
}

# Sockets an ARCHETYPE may declare on top of its class.  The distinction is not
# bureaucracy: every SWD needs a SOC_TIP, but only the ones with a rune channel
# need FX_Rune_*.  A required-per-class list would either force a socket onto
# assets that have nowhere to put it, or let a missing one through.
CLASS_SOCKET_OPTIONAL = {
    "SWD": ["FX_Rune_A", "FX_Rune_B", "FX_Rune_C", "FX_Seam"],
    "KAT": ["FX_Rune_A", "FX_Rune_B", "FX_Rune_C"],
    "GSW": ["FX_Rune_A", "FX_Rune_B", "FX_Rune_C"],
    # CHN ships as THREE REUSABLE PIECES whose anchors genuinely differ: a link
    # has two ends and no grip, a handle has a grip and no tip.  So the class can
    # only declare which NAMES exist; each row declares which it must have, via
    # its own `sockets` list.  A class-level required list would force a SOC_HEAD
    # onto a chain link.
    "CHN": ["SOC_GRIP", "SOC_LINK_IN", "SOC_LINK_OUT", "SOC_HEAD", "FX_HEAD_CORE"],
}

# Godot renders this line on gl_compatibility with one directional light and a
# sky ambient.  There is no reflection source behind the player's hand, so a
# high-metallic surface has nothing to reflect and resolves to a black
# silhouette -- the "dark sword" failure that PART A §5 names explicitly, and
# that this line has now hit twice (once on the blade, once on the chain).
# 0.75 is the measured ceiling.  The guard exists because the failure is
# invisible in Blender's own preview: Blender has an HDRI by default.
METALLIC_CEILING = 0.75

# Blade cross-sections that carry a single cutting edge.  The edge-side
# assertion only means something on these; see assert_contract §5.
SINGLE_EDGE_SECTIONS = ("shinogi", "lens", "backed")

# The contract points `assert_contract` knows how to ask about.  A row may
# declare `checks` (a list of these keys) to say which ones APPLY to it, and a
# class may declare a default under CONTRACT[code]["checks"].
#
# Why this exists at all: the contract was written for weapons, and a weapon is
# an object with an origin at the grip, mass behind the origin and a point
# ahead of it.  A CHAIN LINK is none of those things -- it is a ring, symmetric
# by construction, with no long axis to dominate and no tip to point anywhere.
# Running the weapon checks on it does not test the link; it tests whether the
# link is secretly a sword, and fails a correct asset.
#
# The alternative -- loosening the numbers until a ring passes -- would have
# quietly disabled the same checks for the swords they were written for.
ALL_CHECKS = ("long", "band", "origin", "grip", "ahead", "edge",
              "tris", "metal", "sockets", "extent")

# CONTRACT AXES ARE EXPORTED-FILE AXES.  THEY ARE NOT BLENDER AXES.
#
# The contract says "+Y is the attack end", and that is true of the GLB -- the
# file Godot imports.  It is NOT true of the Blender scene the builder leaves
# behind, because `bake_axes()` rotates the mesh so that the EXPORTER's Y-up
# conversion lands the length on glTF +Y.  Measured on the built asset: after
# the bake, vertices span y in [-0.0032, 0.0032] and z in [0.0, 0.7] -- the long
# axis in Blender is Z.
#
# That distinction is not academic.  The first version of assert_contract read
# the AABB on contract axis Y, so on the baked asset it was measuring the
# THICKNESS and calling it the length.  Every axis assertion passed for the
# wrong reason.
#
# The export mapping, with export_yup=True:
#
#     gltf_x =  blender_x
#     gltf_y =  blender_z
#     gltf_z = -blender_y
#
# so to read a measurement taken in Blender against the contract:
#
#     contract "X" -> blender index 0, sign +1
#     contract "Y" -> blender index 2, sign +1
#     contract "Z" -> blender index 1, sign -1
GLTF_TO_BLENDER = {"x": (0, 1.0), "y": (2, 1.0), "z": (1, -1.0)}


def axis_in_blender(spec_axis):
    """('Y') -> (2, +1.0).  ('-X') -> (0, -1.0).

    Returns the Blender index and the sign that maps a Blender-space coordinate
    onto the contract axis, i.e. `contract_value = blender_coord[idx] * sign`.
    """
    sign = -1.0 if spec_axis.startswith("-") else 1.0
    idx, s = GLTF_TO_BLENDER[spec_axis[-1].lower()]
    return idx, sign * s


# =============================================================================
#  2. SPEC -- the parameter row
# =============================================================================

def spec_path(code, spec_dir=None):
    fam = code.lower()
    d = spec_dir or os.path.join(REPO, "assets_source", "weapons", "specs")
    return os.path.join(d, "%s_variants.json" % fam)


def load_spec(code, spec_dir=None):
    p = spec_path(code, spec_dir)
    if not os.path.isfile(p):
        raise SystemExit("SPEC  missing %s" % p)
    with open(p, "r", encoding="utf-8") as f:
        spec = json.load(f)
    if "rows" not in spec or not isinstance(spec["rows"], list):
        raise SystemExit("SPEC  %s has no 'rows' list" % p)
    return spec


def row_named(spec, row_id):
    for r in spec["rows"]:
        if r.get("id") == row_id:
            return r
    raise SystemExit("SPEC  no row with id=%r (have: %s)"
                     % (row_id, ", ".join(str(r.get("id")) for r in spec["rows"])))


def resolve(spec, row, key, default=None):
    """Row value, falling back to the spec-level `defaults` block.

    Archetypes share a common envelope and differ in a handful of structural
    numbers.  Restating the envelope ten times is how ten variants drift apart
    for no reason, so the defaults block is the envelope.
    """
    if key in row:
        return row[key]
    if default is not None:
        return default
    d = spec.get("defaults", {})
    if key in d:
        return d[key]
    raise SystemExit("SPEC  row %r and defaults both lack %r" % (row.get("id"), key))


# =============================================================================
#  3. PATHS -- where things are allowed to be written
# =============================================================================

def paths_for(code, row, out_glb=None):
    """Resolve output paths for a row, honouring the three-tier asset policy.

    The tiers are the user's ruling of 2026-09-29, and they decide what is
    allowed into version control:

      hero       -- the handful of assets that DEFINE a family's visual
                    language.  .blend to masters/<code>/ (Git LFS), GLB to
                    assets/models/weapons/ (tracked).
      candidate  -- pushed to game-ready.  .blend is regenerable and stays
                    local; GLB is tracked because the game loads it.
      concept    -- the 100+ silhouette explorations.  .blend AND .glb stay in
                    prototypes/ (gitignored).  A concept is not an asset; it is
                    a shape that was considered.

    A hundred variant .blend in history is an unmaintainable pile of binaries,
    not an asset library -- and the same is true of a hundred GLB the game never
    loads.  Both are one `git add -A` away from being permanent.

    Nothing here writes to godot/models/weapons/.  That copy is a deliberate,
    separate step -- `GLB copied != integrated` is a rule this project learned
    the hard way, and a builder that quietly writes into the runtime tree would
    make it easy to skip the verification that goes with it.
    """
    fam = code.lower()
    tier = str(row.get("tier", "concept"))
    row_id = str(row.get("id", "unnamed"))
    name = str(row.get("glb", "%s_%s.glb" % (fam, row_id)))
    # The master .blend name is a PER-ROW value, not a per-family one.  A family
    # whose hero tier is a single defining piece can leave it alone and get
    # `<fam>_master.blend`.  A family that ships SEVERAL named pieces at hero
    # tier -- CHN is three: handle, link, trident -- would otherwise have all
    # three write to the same path and silently keep only the last one.
    master = str(row.get("blend", "%s_master.blend" % fam))
    proto = os.path.join(REPO, "assets_source", "weapons", "prototypes")

    if tier == "hero":
        blend = os.path.join(REPO, "assets_source", "weapons", "masters", fam, master)
        glb = os.path.join(REPO, "assets", "models", "weapons", name)
    elif tier == "candidate":
        blend = os.path.join(proto, "%s_%s.blend" % (fam, row_id))
        glb = os.path.join(REPO, "assets", "models", "weapons", name)
    else:
        blend = os.path.join(proto, "%s_%s.blend" % (fam, row_id))
        glb = os.path.join(proto, "glb", name)
    return blend, (out_glb or glb)


# =============================================================================
#  4. SCENE
# =============================================================================

def clear_scene():
    """Empty file, then sweep the orphan datablocks `read_factory_settings`
    leaves behind.  Without the sweep a second build in the same process keeps
    the previous run's meshes alive and the tri count reads high."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.objects,
                 bpy.data.cameras, bpy.data.lights):
        for d in list(coll):
            coll.remove(d)


def activate(ob):
    """Bevel and the shade operators act on the ACTIVE object, so every
    modifier-driven helper has to go through here first.  Forgetting it makes
    `modifier_apply` fail with a message about context that reads like a Blender
    bug rather than a missing line."""
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)


# =============================================================================
#  5. MESH PRIMITIVES
# =============================================================================

def lerp(a, b, t):
    return a + (b - a) * t


def curve(points, t):
    """Piecewise-linear lookup over [(t, value), ...] with t ascending."""
    if t <= points[0][0]:
        return points[0][1]
    if t >= points[-1][0]:
        return points[-1][1]
    for i in range(len(points) - 1):
        t0, v0 = points[i]
        t1, v1 = points[i + 1]
        if t0 <= t <= t1:
            return lerp(v0, v1, (t - t0) / max(t1 - t0, 1e-9))
    return points[-1][1]


def new_mesh(name, verts, faces, mat):
    me = bpy.data.meshes.new(name)
    me.from_pydata([Vector(v) for v in verts], [], faces)
    me.validate(verbose=False)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if mat is not None:
        ob.data.materials.append(mat)
    return ob


def add_ring(verts, points, y):
    """Append a ring of (x, z) points at height y; return their indices."""
    ring = []
    for (x, z) in points:
        ring.append(len(verts))
        verts.append((x, y, z))
    return ring


def bridge_rings(verts, faces, ring_a, ring_b, count, closed=True):
    """Quad strip between two equal-length rings of vertex indices."""
    span = count if closed else count - 1
    for i in range(span):
        j = (i + 1) % count
        faces.append([ring_a[i], ring_a[j], ring_b[j], ring_b[i]])


def cap_ring(verts, faces, ring, y, z_scale=1.0, reverse=False):
    """Fan a ring closed with a centre vertex.  Used for tips and butt caps,
    where a flat n-gon would leave a visible polygon seam on a curved end."""
    cx = sum(verts[i][0] for i in ring) / len(ring)
    cz = sum(verts[i][2] for i in ring) / len(ring)
    c = len(verts)
    verts.append((cx, y, cz * z_scale))
    n = len(ring)
    for i in range(n):
        j = (i + 1) % n
        if reverse:
            faces.append([c, ring[j], ring[i]])
        else:
            faces.append([c, ring[i], ring[j]])
    return c


def loft(name, stations, mat, cap_start=True, cap_end=True):
    """Loft a stack of rings into a closed solid.

    `stations` is [(y, [(x, z), ...]), ...] with every ring the same length --
    which is the single most common way to build anything in this line, from a
    blade to a spear shaft to a staff head.  It is worth having exactly one
    implementation so that "the rings got out of step" is not a per-family bug.
    """
    ring_pts = [pts for (_y, pts) in stations]
    count = len(ring_pts[0])
    for i, pts in enumerate(ring_pts):
        if len(pts) != count:
            raise SystemExit("LOFT  %s ring %d has %d points, ring 0 has %d"
                             % (name, i, len(pts), count))
    verts, faces, rings = [], [], []
    for y, pts in stations:
        rings.append(add_ring(verts, pts, y))
    for i in range(len(rings) - 1):
        bridge_rings(verts, faces, rings[i], rings[i + 1], count)
    if cap_start:
        cap_ring(verts, faces, rings[0], stations[0][0], reverse=True)
    if cap_end:
        cap_ring(verts, faces, rings[-1], stations[-1][0])
    ob = new_mesh(name, verts, faces, mat)
    recalc_normals(ob)
    return ob


def loft_many(name, groups, mat, cap=True):
    """Several independent ring-stacks welded into ONE mesh.

    Two rails down a blade, four prongs of a trident head, a pair of swept
    quillons: all of them are "the same loft, more than once", and all of them
    want to be a single part so the material partition stays per-part.  Kept
    here rather than in each family because the alternative is each family
    discovering the winding order independently.
    """
    verts, faces = [], []
    for st in groups:
        count = len(st[0][1])
        rings = [add_ring(verts, pts, y) for (y, pts) in st]
        for i in range(len(rings) - 1):
            bridge_rings(verts, faces, rings[i], rings[i + 1], count)
        if cap:
            cap_ring(verts, faces, rings[0], st[0][0], reverse=True)
            cap_ring(verts, faces, rings[-1], st[-1][0])
    ob = new_mesh(name, verts, faces, mat)
    recalc_normals(ob)
    return ob


def extrude_profile(name, pts2d, y0, y1, mat):
    """Extrude a closed 2D outline (a guard plate, a pommel disc, a shield
    face) along Y.  The outline must be given once; the return path is
    generated so the two caps are wound oppositely."""
    n = len(pts2d)
    verts, faces = [], []
    a = add_ring(verts, pts2d, y0)
    b = add_ring(verts, pts2d, y1)
    for i in range(n):
        j = (i + 1) % n
        faces.append([a[i], a[j], b[j], b[i]])
    faces.append(list(reversed(a)))
    faces.append(list(b))
    ob = new_mesh(name, verts, faces, mat)
    recalc_normals(ob)
    return ob


def oval_pts(rx, rz, n, y=0.0, offset=0.0, wobble=0.0):
    """A closed oval cross-section.  `wobble` gives the section a slight
    hand-made asymmetry; a mathematically perfect oval on a grip reads as a
    machined tube at 0.3 m, which is inside the band PART I cares about."""
    pts = []
    for i in range(n):
        t = TAU * i / n
        w = 1.0 + wobble * math.sin(t * 3.0 + offset)
        pts.append((rx * math.cos(t) * w, rz * math.sin(t) * w))
    return pts


def catmull_closed(ctrl, n):
    """Resample a closed control polygon into n points with a Catmull-Rom
    spline.  Used for outlines that need to look drawn rather than built."""
    out = []
    m = len(ctrl)
    per = max(1, n // m)
    for i in range(m):
        p0 = ctrl[(i - 1) % m]
        p1 = ctrl[i]
        p2 = ctrl[(i + 1) % m]
        p3 = ctrl[(i + 2) % m]
        for s in range(per):
            t = s / float(per)
            t2, t3 = t * t, t * t * t
            out.append([(
                0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t
                       + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                       + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3)
            ) for k in range(2)])
    return [(p[0], p[1]) for p in out]


def offset_inward(pts, d):
    """Inward offset of a closed polygon by moving each vertex along its
    vertex normal.  Good enough for rims and lips; not a general polygon
    offset -- it will self-intersect on a concave feature tighter than d."""
    out = []
    n = len(pts)
    for i in range(n):
        p = Vector(pts[i])
        a = Vector(pts[(i - 1) % n])
        b = Vector(pts[(i + 1) % n])
        nrm = (b - a)
        if nrm.length < 1e-9:
            out.append(pts[i])
            continue
        nrm.normalize()
        nrm = Vector((-nrm.y, nrm.x))
        out.append((p.x - nrm.x * d, p.y - nrm.y * d))
    return out


def recalc_normals(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()


def shade(ob, smooth_angle=None):
    """Smooth shading, optionally angle-limited.

    Hard-surface parts want a limit so the ridge and the guard rim stay crisp;
    soft parts (a grip, a wrap) want full smooth or they show a facet line down
    the length.  Blender has no stable public API for the auto-smooth node group
    across versions, so the limiter goes through whichever operator exists and
    is skipped if neither does -- shading is not worth a hard dependency.
    """
    for p in ob.data.polygons:
        p.use_smooth = True
    if smooth_angle is None:
        return
    try:
        activate(ob)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(smooth_angle))
    except Exception:
        try:
            bpy.ops.object.shade_auto_smooth(angle=math.radians(smooth_angle))
        except Exception:
            pass


def bevel(ob, width=0.0006, segments=2, angle=42.0):
    """Every visible hard edge gets a believable bevel.

    Widths here are fractions of a millimetre to a millimetre.  Anything larger
    turns a forged part into a toy.  Size the bevel to the FEATURE it is
    rounding and never set it globally.
    """
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    m.harden_normals = False
    activate(ob)
    bpy.ops.object.modifier_apply(modifier=m.name)


# =============================================================================
#  6. MATERIALS
# =============================================================================

def mat(name, base, metallic, rough, spec=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf is None:
        return m
    bsdf.inputs["Base Color"].default_value = (base[0], base[1], base[2], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = spec
    return m


# The family material palette.  Values are IN-GAME decisions, not PBR showcase
# ones -- see METALLIC_CEILING.  Families pick from this dict and may add their
# own; what they may not do is invent a metallic above the ceiling without
# saying so in the row.
PALETTE = {
    # Polished blade steel.  The albedo is deliberately mid: 0.735 linear (the
    # physically-defensible value for polished steel) rendered as a UNIFORM
    # WHITE BAR in the training ground at 0.5 m, with every bit of form --
    # ridge, taper, bow, point -- present in the geometry and invisible in
    # value.  0.460 leaves a mid-grey under the highlight instead of a white.
    "steel":      dict(base=(0.460, 0.472, 0.496), metallic=0.48, rough=0.200, spec=0.55),
    # Darker, coarser blade for the heavy and the ruined archetypes.
    "steel_dark": dict(base=(0.235, 0.240, 0.252), metallic=0.42, rough=0.330, spec=0.50),
    "steel_pale": dict(base=(0.585, 0.590, 0.610), metallic=0.46, rough=0.165, spec=0.60),
    # Near-black blue-grey wrap.  Job is to be the dark anchor under a bright
    # blade, not to be looked at.
    "grip":       dict(base=(0.052, 0.055, 0.066), metallic=0.0, rough=0.735),
    "leather":    dict(base=(0.108, 0.070, 0.048), metallic=0.0, rough=0.660),
    "cloth":      dict(base=(0.300, 0.278, 0.240), metallic=0.0, rough=0.780),
    # Restrained warm ancient metal, for the ritual archetypes only.
    "inlay":      dict(base=(0.610, 0.470, 0.235), metallic=0.60, rough=0.345, spec=0.60),
    "brass":      dict(base=(0.430, 0.330, 0.150), metallic=0.55, rough=0.400),
    # Dark, rough, nearly-dielectric iron.  Two corrections in one value: the
    # albedo, because 0.238 reads as pale stone rather than iron; and the
    # metallic, because 0.55 on a broad close source floods the plate with
    # specular so the base colour stops meaning anything and the guard renders
    # cream no matter what it is tinted.  0.30 lets the dark colour survive.
    "iron":       dict(base=(0.086, 0.079, 0.070), metallic=0.30, rough=0.580),
    "wood":       dict(base=(0.150, 0.098, 0.058), metallic=0.0, rough=0.620),
    "bone":       dict(base=(0.560, 0.530, 0.470), metallic=0.0, rough=0.520),
    "stone":      dict(base=(0.190, 0.192, 0.196), metallic=0.0, rough=0.720),
    # Crystal cores.  Emission is what makes these readable in the two-darkness
    # setup; a clear crystal with no emission is an invisible crystal.
    "crystal":    dict(base=(0.240, 0.470, 0.560), metallic=0.0, rough=0.120,
                       emission=(0.180, 0.480, 0.620), emit_strength=2.4),
    "crystal_warm": dict(base=(0.560, 0.400, 0.180), metallic=0.0, rough=0.140,
                         emission=(0.900, 0.520, 0.180), emit_strength=2.0),
    # CHAIN -- three values that were already MEASURED, moved here so they are
    # finally guarded.  They lived in `godot/scripts/combat/chain_visual.gd` as
    # LINK_TINT / HEAD_TINT / HANDLE_TINT, set in code, and the metallic numbers
    # are the ones that cost two review passes: 0.75 rendered the whole weapon
    # as a silhouette and 0.45 STILL rendered the held bundle as a charcoal
    # blob, because a fistful of small ovals reflects the sky away from the eye.
    # Until the chain moves into this line nothing asserted any of it -- the
    # ceiling existed and this asset was outside it in a file the ceiling could
    # not see.
    #
    # The base colours are the EXACT linear conversions of those three sRGB
    # tints (1.055*v^(1/2.4) - 0.055), not new picks; 0.72 sRGB is 0.474 linear.
    "chain_link": dict(base=(0.474, 0.503, 0.578), metallic=0.20, rough=0.440, spec=0.50),
    "chain_head": dict(base=(0.171, 0.188, 0.235), metallic=0.30, rough=0.440, spec=0.50),
    "chain_grip": dict(base=(0.055, 0.047, 0.040), metallic=0.0, rough=0.720),
}


def palette(keys):
    """Build the named materials for one row, with the metal-trap guard applied
    at creation time so a bad value cannot reach the exporter."""
    out = {}
    for k in keys:
        if k not in PALETTE:
            raise SystemExit("MAT  unknown palette key %r (have: %s)"
                             % (k, ", ".join(sorted(PALETTE))))
        spec = PALETTE[k]
        name = "MAT_%s" % k
        m = mat(name, spec["base"], spec["metallic"], spec.get("rough", 0.5),
                spec.get("spec", 0.5))
        if "emission" in spec:
            bsdf = m.node_tree.nodes.get("Principled BSDF")
            e = spec["emission"]
            # Blender 4.x renamed the emission sockets; try both spellings.
            for key in ("Emission Color", "Emission"):
                if key in bsdf.inputs:
                    bsdf.inputs[key].default_value = (e[0], e[1], e[2], 1.0)
                    break
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = spec.get("emit_strength", 1.0)
        out[k] = m
    return out


# =============================================================================
#  7. THE RIG -- parts, root, sockets
# =============================================================================

class Rig(object):
    """The single object a family builder hands back to the framework.

    A builder never touches the exporter, the assertions or the file paths.  It
    makes geometry, declares where the sockets are, and returns.
    """

    def __init__(self, code):
        if code not in CONTRACT:
            raise SystemExit("RIG  unknown class code %r" % code)
        self.code = code
        self.contract = CONTRACT[code]
        self.parts = []
        self.sockets = []
        self.root = None
        self.notes = []

    def add(self, ob):
        self.parts.append(ob)
        return ob

    def extend(self, obs):
        self.parts.extend(obs)
        return obs

    def socket(self, name, loc, rot_euler=None):
        """Declare an anchor.  Empty Object3D, no mesh, so it costs nothing at
        runtime and Godot can find it by name."""
        allowed = (list(BASE_SOCKETS)
                   + CLASS_SOCKETS.get(self.code, [])
                   + CLASS_SOCKET_OPTIONAL.get(self.code, []))
        if name not in allowed:
            raise SystemExit("RIG  socket %r is not declared for %s (allowed: %s)"
                             % (name, self.code, ", ".join(allowed)))
        ob = bpy.data.objects.new(name, None)
        ob.empty_display_size = 0.02
        bpy.context.scene.collection.objects.link(ob)
        ob.location = Vector(loc)
        if rot_euler is not None:
            ob.rotation_euler = rot_euler
        self.sockets.append(ob)
        return ob

    def note(self, text):
        self.notes.append(text)

    def finish(self):
        """Parent everything under one root Empty at the ORIGIN.

        The root must stay at the origin and the parts must keep identity local
        transforms: every downstream anchor (the sword rig, the saya, the
        hitbox, the Iaido directors) is expressed against the model origin, so
        a part that carries its own offset would look identical in Blender and
        be wrong in Godot.
        """
        self.root = bpy.data.objects.new("%s_Root" % self.code, None)
        bpy.context.scene.collection.objects.link(self.root)
        for p in self.parts + self.sockets:
            p.parent = self.root
        return self.root


# =============================================================================
#  8. AXES -- the export bake
# =============================================================================

def bake_axes(rig):
    """Rotate the whole weapon so the EXPORTED asset matches the contract.

    THE MATH.  Blender's glTF exporter maps

        (x, y, z)_blender  ->  (x, z, -y)_gltf

    so authoring with length down Blender +Y exports with the long axis on
    Z_gltf and the tip toward -Z.  A +90 degree rotation about X maps Blender
    +Y -> +Z, which the exporter then takes to +Y, leaving -X on -X.  That is
    the whole trick, and it is why the bake exists rather than a node rotation:
    a rotation left on the root is one downstream tool away from being dropped.

    This was NOT a theoretical concern.  The first shipping sword exported with
    its long axis on Z and the tip on -Z while `Sword_FP.tscn`'s header claimed
    "+Y", and the consequence was that `iaido_director.gd:_bore_pose()` -- which
    seats the sword by giving it the SCABBARD's own basis, whose +Y is the bore
    -- seated the blade at ninety degrees to its own scabbard.  Geometry, tri
    count and materials were all fine.  Only the axis was wrong, and nothing
    complained.

    Baked into MESH DATA, after every builder has finished, so builders are free
    to author in whatever pose is convenient.
    """
    if rig.contract["long"] != "Y":
        raise SystemExit("AXES  contract for %s is not Y-long; bake_axes only "
                         "implements the +90 X case" % rig.code)
    rot = Matrix.Rotation(math.radians(90.0), 4, "X")
    for p in rig.parts:
        p.data.transform(rot)
        p.data.update()
    for s in rig.sockets:
        s.location = rot @ s.location
        e = s.rotation_euler
        s.rotation_euler = (Matrix.Rotation(math.radians(90.0), 3, "X")
                            @ e.to_matrix()).to_euler()
    print("AXES  baked +90 X -> long %s%s, edge %s"
          % (rig.contract["long"], rig.contract["tip"], rig.contract["edge"] or "-"))
    return rot


# =============================================================================
#  9. MEASUREMENT
# =============================================================================

def part_aabb(ob):
    """AABB straight from the mesh vertices.

    NOT `ob.bound_box`.  Object bound_box is a lazily evaluated cache, and it is
    STALE immediately after `mesh.transform()` -- measured: right after
    `bake_axes()` the bound_box still reported the pre-bake box on every axis
    while the vertex data was already rotated.  Every AABB this framework
    printed, and every assertion computed from it, was therefore measuring the
    AUTHORING pose rather than the exported one, which made the axis assertions
    blind to exactly the failure they exist to catch.  Reading the vertices
    cannot go stale.
    """
    cos = [v.co for v in ob.data.vertices]
    if not cos:
        z = Vector((0, 0, 0))
        return z, z
    mn = Vector((min(c.x for c in cos), min(c.y for c in cos), min(c.z for c in cos)))
    mx = Vector((max(c.x for c in cos), max(c.y for c in cos), max(c.z for c in cos)))
    return mn, mx


def aabb(parts):
    mns, mxs = [], []
    for p in parts:
        mn, mx = part_aabb(p)
        mns.append(mn)
        mxs.append(mx)
    mn = Vector((min(v.x for v in mns), min(v.y for v in mns), min(v.z for v in mns)))
    mx = Vector((max(v.x for v in mxs), max(v.y for v in mxs), max(v.z for v in mxs)))
    return mn, mx


def contract_extents(mn, mx):
    """Per-axis extents in the frame the CONTRACT is written in.

    A row can only be asked for sizes on contract axes, and the measurement is
    taken on Blender axes, so the mapping has to happen here and in one place.
    See GLTF_TO_BLENDER for why these are not the same three numbers.
    """
    out = {}
    for ax in "xyz":
        idx, sign = GLTF_TO_BLENDER[ax]
        a = mn[idx] * sign
        b = mx[idx] * sign
        out[ax] = abs(b - a)
    return out


def tri_count(parts):
    n = 0
    for p in parts:
        p.data.calc_loop_triangles()
        n += len(p.data.loop_triangles)
    return n


def cluster_stats(name, ob):
    """Vertex centroid in LOCAL space.  Kept for reports; NOT used by the
    edge-side assertion, see section_asymmetry for why."""
    if not ob.data.vertices:
        return Vector((0, 0, 0))
    c = Vector((0, 0, 0))
    for v in ob.data.vertices:
        c += v.co
    return c / len(ob.data.vertices)


def section_asymmetry(ob, long_idx, edge_idx):
    """Mass asymmetry of the CROSS-SECTION, with the curvature removed.

    THE TEST THIS REPLACES WAS WRONG, AND IT TOOK A REAL ASSET TO SHOW IT.

    The obvious way to ask "is the cutting edge on the -X side" is to take the
    vertex centroid of the blade and check its sign.  That is what this file did
    first, and it failed an asset that was correct: the re-ground single-edged
    archetype reports its centroid at x = -0.00118, which is the EDGE side, and
    the blade is fine.

    The cause is that a bowed blade's rings are not centred on x = 0 -- each
    ring sits at the sori offset for its station, and over the length that
    offset averages to roughly -2/3 of the bow.  A 6 mm bow therefore contributes
    about -4 mm of centroid, which SWAMPS the 2.5 mm of asymmetry the section
    itself carries.  The metric was measuring the curvature and reporting it as
    a mirrored edge.

    So the ring centre is subtracted out first.  Vertices are grouped by their
    station along the length axis (a loft's rings are at distinct values), each
    ring's own mid-point is removed, and what is left is the section's
    asymmetry alone.  For a double-edged section this is exactly zero by
    construction, which is also why the caller only runs it on single-edged
    sections.

    Returns (residue_in_metres, mean_half_width_in_metres).
    """
    if not ob.data.vertices:
        return 0.0, 0.0
    groups = {}
    for v in ob.data.vertices:
        groups.setdefault(round(v.co[long_idx], 5), []).append(v.co)
    total, half_w = 0.0, 0.0
    n = 0
    for _key, cos in groups.items():
        xs = [c[edge_idx] for c in cos]
        mid = (min(xs) + max(xs)) * 0.5
        total += (sum(xs) / len(xs)) - mid
        half_w += (max(xs) - min(xs)) * 0.5
        n += 1
    if n == 0:
        return 0.0, 0.0
    return total / n, half_w / n


# =============================================================================
# 10. ASSERTIONS -- the reason this file exists
# =============================================================================

class Violations(object):
    def __init__(self):
        self.items = []

    def check(self, ok, text):
        if not ok:
            self.items.append(text)
        return ok

    def report(self, code, name):
        if not self.items:
            print("ASSERT %s [%s]  PASS" % (code, name))
            return True
        print("ASSERT %s [%s]  FAIL  (%d)" % (code, name, len(self.items)))
        for t in self.items:
            print("   ! %s" % t)
        return False


def assert_contract(rig, row, strict=True):
    """Every declared contract point, checked against the built geometry.

    These are the failures that are SILENT in Godot.  A sword with its long axis
    on Z renders, animates, swings, and is wrong; you find out by looking at it
    three sessions later and blaming the animation.  So the build fails here
    instead, loudly, and exits non-zero so a batch run stops.
    """
    v = Violations()
    mn, mx = aabb(rig.parts)
    size = mx - mn
    c = rig.contract

    # Which contract points APPLY here.  Row wins, then class, then everything.
    # Defaulting to everything keeps every existing family's behaviour identical.
    enabled = set(row.get("checks") or c.get("checks") or ALL_CHECKS)

    # Translate the contract into the frame the measurement is actually in.
    # See GLTF_TO_BLENDER: the contract is about the exported file, the mesh is
    # in the baked authoring pose, and conflating the two made every axis check
    # below pass for the wrong reason.
    long_idx, long_sign = axis_in_blender(c["long"])
    others = [size[i] for i in range(3) if i != long_idx]
    length = size[long_idx]
    # Signed bounds on the contract axis: contract-lo < contract-hi always.
    lo_c = mn[long_idx] * long_sign
    hi_c = mx[long_idx] * long_sign
    if lo_c > hi_c:
        lo_c, hi_c = hi_c, lo_c

    # 1. Long axis really carries the length.
    if "long" in enabled:
        v.check(length > max(others) * 1.2,
                "contract long axis %s is Blender axis %s with extent %.4f, which "
                "does not dominate the AABB %s"
                % (c["long"], "XYZ"[long_idx], length, _fmt(size)))

    # 2. Declared length band, if the row states one.
    span = row.get("length_band")
    if span:
        v.check(span[0] <= length <= span[1],
                "length %.4f m outside the row's declared band %s" % (length, span))

    # 3. Origin inside the envelope, and it is a real origin rather than a
    #    formality: the grip has to extend BEHIND it or the model is a blade
    #    with nothing to hold.
    if "origin" in enabled:
        v.check(lo_c <= 0.0 <= hi_c,
                "origin is outside the model: %.4f .. %.4f on contract %s"
                % (lo_c, hi_c, c["long"]))
    behind = -lo_c if c["tip"] == "+" else hi_c
    if "grip" in enabled:
        v.check(behind >= 0.04,
                "only %.4f m of geometry behind the origin -- no grip" % behind)

    # 4. Attack end on the declared sign.
    ahead = hi_c if c["tip"] == "+" else -lo_c
    if "ahead" in enabled:
        v.check(ahead > behind,
                "attack end %s: forward %.4f m vs backward %.4f m -- the weapon "
                "points the wrong way" % (c["tip"], ahead, behind))

    # 5. Cutting edge on the declared side.  Uses mass asymmetry, so it also
    #    catches the class of bug where every part is centred on the blade's
    #    EDGE line instead of behind its middle -- which looks perfect in a
    #    front view and shows the guard hanging off one side in a 3/4.
    #
    #    THE TEST IS DRIVEN BY THE SECTION, NOT BY THE CLASS.  A family is not
    #    single- or double-edged; a blade is.  SWD contains both a double-edged
    #    arming sword and a re-ground single-edged one, so a per-class flag would
    #    have to be wrong for one of them.  On a double-edged blade the mass
    #    centroid sits on the axis by construction and there is nothing to
    #    measure, which is why the check is skipped rather than passed.
    if c["edge"] and str(row.get("section", "")) in SINGLE_EDGE_SECTIONS:
        blade = None
        for p in rig.parts:
            if p.name.lower().startswith("blade"):
                blade = p
                break
        if blade is None:
            v.check(False, "single-edge class but no part named Blade* to test")
        else:
            edge_idx, edge_sign = axis_in_blender(c["edge"])
            # Thin edge -> the section's mass sits on the side OPPOSITE the
            # declared edge.  Measured with the ring centres subtracted, so a
            # bowed blade is not mistaken for a mirrored one -- see
            # section_asymmetry for the asset that proved this matters.
            res, half_w = section_asymmetry(blade, long_idx, edge_idx)
            # `res` is a coordinate ALONG the declared edge direction, so a
            # positive value means the mass sits on the edge side.  That is the
            # opposite of what the raw Blender-space number means, and getting
            # the label backwards here produced a report that read "the mass is
            # on the +X side, but it must be on the +X side".
            res *= edge_sign
            side = ("-%s" if res > 0 else "+%s") % c["edge"][-1].upper()
            want = ("-%s" if edge_sign < 0 else "+%s") % c["edge"][-1].upper()
            v.check(res < 0.0,
                    "blade section residue %+.5f m (half-width %.5f m): the mass "
                    "is on the %s side, but edge %s means it must be on the %s "
                    "side -- the section is mirrored"
                    % (res, half_w, side, c["edge"], want))
            print("      edge-check  section residue %+.5f m / half-width %.5f m"
                  "  -> edge on %s" % (res, half_w, c["edge"]))

    # 6. Triangle budget.
    tris = tri_count(rig.parts)
    lo, hi = c["tris"]
    v.check(lo <= tris <= hi,
            "triangles %d outside the %s band %d..%d" % (tris, rig.code, lo, hi))

    # 7. Metal trap.
    for m in {ms.material for p in rig.parts for ms in p.material_slots if ms.material}:
        bsdf = m.node_tree.nodes.get("Principled BSDF") if m.use_nodes else None
        if bsdf is None:
            continue
        mt = bsdf.inputs["Metallic"].default_value
        if mt > METALLIC_CEILING:
            v.check(False,
                    "material %s metallic %.2f > ceiling %.2f -- with no "
                    "reflection source this renders as a black silhouette "
                    "(the metal trap)" % (m.name, mt, METALLIC_CEILING))

    # 8. Sockets.  A row that declares its own `sockets` list REPLACES the class
    #    list rather than adding to it -- see CLASS_SOCKET_OPTIONAL["CHN"] for
    #    why a class-wide required set cannot describe three different pieces.
    have = {s.name for s in rig.sockets}
    if row.get("sockets"):
        need = list(row["sockets"])
    else:
        need = list(BASE_SOCKETS) + CLASS_SOCKETS.get(rig.code, [])
    missing = [n for n in need if n not in have]
    v.check(not missing, "missing sockets: %s" % ", ".join(missing))

    # 9. Declared per-axis extents, on CONTRACT axes.
    #
    # This is the check a MODULAR PART wants and the length band cannot give it.
    # The chain link is the case that forced it: the link's three dimensions are
    # not free -- two of them set the interlock (see LINK_FILL) and the third is
    # the material the ring test subtracts -- and none of them is "the length of
    # the weapon".  A band on one axis would have been satisfied by a link that
    # was right along the rope and wrong across it.
    band = row.get("extent_band")
    if band and "extent" in enabled:
        ext = contract_extents(mn, mx)
        for ax, rng in zip("xyz", band):
            v.check(rng[0] <= ext[ax] <= rng[1],
                    "contract %s extent %.4f m outside the row's band [%.4f, %.4f]"
                    % (ax.upper(), ext[ax], rng[0], rng[1]))
        print("      extents     X %.4f  Y %.4f  Z %.4f m"
              % (ext["x"], ext["y"], ext["z"]))

    ok = v.report(rig.code, row.get("id", "?"))
    if not ok and strict:
        sys.exit(2)
    return ok


def _fmt(v):
    return "(%.4f, %.4f, %.4f)" % (v.x, v.y, v.z)


def write_build_record(code, entries):
    """Persist one JSON line per built row, MERGING into any existing record.

    This is the source the family table and the contact sheet are generated
    from.  The alternative -- retyping measurements into a markdown table -- is
    how a spec and a document drift apart, and this project has a rule about it:
    the single source of truth is generated, not hand-copied.

    Merging matters because `--row relic` is the common case during iteration,
    and overwriting the record with that one row would silently delete the other
    nine from the "source of truth".
    """
    if not entries:
        return None
    p = os.path.join(REPO, "assets_source", "weapons", "specs",
                     "%s_build.json" % code.lower())
    os.makedirs(os.path.dirname(p), exist_ok=True)
    prior = {}
    if os.path.isfile(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                for r in json.load(f).get("rows", []):
                    prior[r.get("id")] = r
        except Exception:
            prior = {}
    for r in entries:
        prior[r.get("id")] = r
    rows = sorted(prior.values(), key=lambda r: str(r.get("id")))
    doc = dict(code=code, rows=rows)
    with open(p, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("RECORD %s  %d rows total" % (p, len(rows)))
    return p


def report_json(rig, row):
    mn, mx = aabb(rig.parts)
    size = mx - mn
    c = rig.contract
    li, ls = axis_in_blender(c["long"])
    lo_c, hi_c = sorted((mn[li] * ls, mx[li] * ls))
    return dict(
        id=row.get("id"),
        archetype=row.get("archetype"),
        world_name=row.get("world_name"),
        tier=row.get("tier", "concept"),
        tris=tri_count(rig.parts),
        parts=[p.name for p in rig.parts],
        sockets=[s.name for s in rig.sockets],
        aabb_mm=[round(size.x * 1000, 1), round(size.y * 1000, 1), round(size.z * 1000, 1)],
        length_mm=round((hi_c - lo_c) * 1000, 1),
        grip_behind_mm=round(-lo_c * 1000, 1),
        reach_mm=round(hi_c * 1000, 1),
        section=row.get("section"),
        guard=row.get("guard"),
        grip_length_mm=round(float(row.get("grip_length", 0.0)) * 1000, 1),
        wrapped=bool(row.get("wrapped")),
        seams=len(row.get("accent_seams", []) or []),
        channel=bool(row.get("channel")),
    )


def report(rig, row):
    mn, mx = aabb(rig.parts)
    size = mx - mn
    tris = tri_count(rig.parts)
    mats = []
    for p in rig.parts:
        for s in p.material_slots:
            if s.material and s.material.name not in mats:
                mats.append(s.material.name)
    c = rig.contract
    li, ls = axis_in_blender(c["long"])
    lo_c, hi_c = sorted((mn[li] * ls, mx[li] * ls))
    print("BUILD %s [%s]  tier=%s" % (rig.code, row.get("id", "?"), row.get("tier", "variant")))
    for n in rig.notes:
        print("      %s" % n)
    print("      AABB (blender XYZ)  %s  =  %.4f x %.4f x %.4f m"
          % (_fmt(size), size.x, size.y, size.z))
    print("      BOUND x[%7.4f %7.4f]  y[%7.4f %7.4f]  z[%7.4f %7.4f]"
          % (mn.x, mx.x, mn.y, mx.y, mn.z, mx.z))
    print("      CONTRACT long %s%s = %.4f m   origin inside   back %.4f  fwd %.4f"
          % (c["long"], c["tip"], hi_c - lo_c, -lo_c, hi_c))
    print("      TRIS  %d across %d parts" % (tris, len(rig.parts)))
    for p in rig.parts:
        pmn, pmx = part_aabb(p)
        p.data.calc_loop_triangles()
        matn = p.material_slots[0].material.name if p.material_slots else "-"
        print("        %-16s tris=%5d  x[%7.4f %7.4f] y[%7.4f %7.4f] z[%7.4f %7.4f]  %s"
              % (p.name, len(p.data.loop_triangles), pmn.x, pmx.x, pmn.y, pmx.y,
                 pmn.z, pmx.z, matn))
    print("      MATS  %s" % ", ".join(mats))
    print("      SOC   %s" % ", ".join(s.name for s in rig.sockets))
    return tris


# =============================================================================
# 11. EXPORT
# =============================================================================

def export_glb(rig, out_glb):
    """One export path for the whole line.

    Settings are fixed rather than per-family, because every one of them has a
    downstream consequence: `export_apply` bakes modifiers (an unapplied bevel
    exports at the wrong width), `export_yup` is what makes the axis bake above
    mean anything, and `export_materials` has to be EXPLY or Godot gets a model
    with no material at all.
    """
    os.makedirs(os.path.dirname(out_glb), exist_ok=True)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=out_glb,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )
    print("SAVED %s" % out_glb)


def save_blend(out_blend):
    os.makedirs(os.path.dirname(out_blend), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out_blend)
    print("SAVED %s" % out_blend)


# =============================================================================
# 11b. READ BACK THE GLB
# =============================================================================
#
# Everything above measures the BLENDER SCENE.  The contract is about the GLB.
# Those are different objects, related by a rotation that the exporter applies,
# and this framework already shipped one version of itself that conflated them.
#
# So after exporting, the GLB is opened and its POSITION accessors are measured,
# with every node transform in the file applied.  That is the only measurement
# in the whole pipeline that describes what Godot will import -- and it is the
# one that would have caught the original shipped sword, whose long axis was on
# glTF Z while its scene header claimed +Y.
#
# Pure stdlib: no bpy, no mathutils, so the same function can be called from a
# plain `python` verification script outside Blender.

import struct as _struct


def _glb_chunks(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"glTF":
        raise SystemExit("GLB  %s is not a binary glTF" % path)
    total = _struct.unpack_from("<I", data, 8)[0]
    out = {}
    off = 12
    while off < min(total, len(data)) - 8:
        clen, ctype = _struct.unpack_from("<II", data, off)
        body = data[off + 8: off + 8 + clen]
        out[ctype] = body
        off += 8 + clen
        off += (-off) % 4
    return out.get(0x4E4F534A), out.get(0x004E4942)


def _mat_mul(a, b):
    """Row-major 4x4 multiply, plain lists so this works outside Blender."""
    out = [0.0] * 16
    for r in range(4):
        for c in range(4):
            out[r * 4 + c] = sum(a[r * 4 + k] * b[k * 4 + c] for k in range(4))
    return out


def _quat_mat(q):
    x, y, z, w = q
    return [
        1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0.0,
        2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0.0,
        2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0.0,
        0.0, 0.0, 0.0, 1.0,
    ]


def _node_matrix(node):
    if "matrix" in node:
        # glTF stores column-major; convert to row-major.
        m = node["matrix"]
        return [m[0], m[4], m[8], m[12],
                m[1], m[5], m[9], m[13],
                m[2], m[6], m[10], m[14],
                m[3], m[7], m[11], m[15]]
    t = node.get("translation", [0.0, 0.0, 0.0])
    r = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    s = node.get("scale", [1.0, 1.0, 1.0])
    m = _quat_mat(r)
    for row in range(3):
        for col in range(3):
            m[row * 4 + col] *= s[col]
    m[3], m[7], m[11] = t[0], t[1], t[2]
    return m


def glb_aabb(path):
    """AABB of the exported file, in glTF axes, with node transforms applied."""
    jchunk, _bin = _glb_chunks(path)
    doc = json.loads(jchunk.decode("utf-8"))
    nodes = doc.get("nodes", [])
    meshes = doc.get("meshes", [])
    accs = doc.get("accessors", [])

    mn = [float("inf")] * 3
    mx = [float("-inf")] * 3
    prims = 0

    def walk(i, parent):
        nonlocal prims
        node = nodes[i]
        world = _mat_mul(parent, _node_matrix(node))
        if "mesh" in node:
            for p in meshes[node["mesh"]].get("primitives", []):
                ai = p.get("attributes", {}).get("POSITION")
                if ai is None:
                    continue
                acc = accs[ai]
                lo, hi = acc.get("min"), acc.get("max")
                if not lo or not hi:
                    continue
                prims += 1
                for cx in (lo[0], hi[0]):
                    for cy in (lo[1], hi[1]):
                        for cz in (lo[2], hi[2]):
                            v = [cx, cy, cz, 1.0]
                            w = [sum(world[r * 4 + k] * v[k] for k in range(4)) for r in range(3)]
                            for a in range(3):
                                mn[a] = min(mn[a], w[a])
                                mx[a] = max(mx[a], w[a])
        for c in node.get("children", []):
            walk(c, world)

    scene = doc.get("scenes", [{}])[doc.get("scene", 0)]
    for i in scene.get("nodes", []):
        walk(i, [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0])
    if prims == 0:
        raise SystemExit("GLB  %s exposes no POSITION accessor" % path)
    return mn, mx, prims, len(nodes)


# The exported file's own axes.  In glTF, X = 0, Y = 1, Z = 2, and the contract
# is written in these -- so this map is the identity apart from the sign, which
# is the whole point: measuring the GLB needs no conversion at all, while
# measuring the Blender scene needs GLTF_TO_BLENDER above.
GLTF_AXIS = {"x": (0, 1.0), "y": (1, 1.0), "z": (2, 1.0)}


def verify_glb(path, rig, row):
    """The check that closes the loop: does the FILE match the contract?

    Everything else in this file measures the Blender scene.  The contract is
    about the exported GLB, and the two are related by a rotation the exporter
    applies -- a relationship this framework has already got wrong once, in a
    way that made every axis assertion pass for the wrong reason.  So the file
    is opened and measured directly.

    Deliberately a hard failure.  A weapon that exports with its length on the
    wrong axis renders, animates and swings perfectly while being wrong in the
    player's hand; the only place that surfaces is three sessions later as "the
    sword looks off".  Failing the build is cheaper.
    """
    mn, mx, prims, nnodes = glb_aabb(path)
    size = [mx[i] - mn[i] for i in range(3)]
    c = rig.contract
    li, ls = GLTF_AXIS[c["long"].lower()]
    lo_c, hi_c = sorted((mn[li] * ls, mx[li] * ls))
    length = hi_c - lo_c
    others = [size[i] for i in range(3) if i != li]

    v = Violations()
    # The same per-row question set the scene assertions use.  It has to be the
    # same set: the file check is the one that owns "the exported axis is right",
    # and a symmetric part -- a chain link -- would otherwise pass in the scene
    # and fail in the file for a reason that is not about the file at all.
    enabled = set(row.get("checks") or c.get("checks") or ALL_CHECKS)
    if "long" in enabled:
        v.check(length > max(others) * 1.2,
                "GLB long extent %.4f on %s does not dominate (%.4f, %.4f) -- the "
                "exported file has its length on the wrong axis"
                % (length, c["long"], others[0], others[1]))
    v.check(abs(length) > 0.0 and hi_c > lo_c, "GLB has a degenerate extent")
    behind = -lo_c if c["tip"] == "+" else hi_c
    ahead = hi_c if c["tip"] == "+" else -lo_c
    if "origin" in enabled:
        v.check(lo_c <= 0.0 <= hi_c, "GLB origin is outside the file's own bounds")
    if "ahead" in enabled:
        v.check(ahead > behind,
                "GLB attack end points the wrong way (forward %.4f, backward %.4f)"
                % (ahead, behind))
    span = row.get("length_band")
    if span:
        v.check(span[0] <= length <= span[1],
                "GLB length %.4f outside the declared band %s" % (length, span))

    if v.items:
        print("GLB   %s  FAIL" % os.path.basename(path))
        for t in v.items:
            print("   ! %s" % t)
        sys.exit(3)
    print("GLB   %s  PASS  longs %s+ %.4f m, %d prims, %d nodes"
          % (os.path.basename(path), c["long"], length, prims, nnodes))
    return length


# =============================================================================
# 12. PREVIEW -- the FP rig and the contact sheet
# =============================================================================
#
# PART I puts the acceptance distance at 0.3-1 m, so a preview that frames the
# whole weapon from two metres away is measuring the wrong thing.  The three
# standard views are, deliberately:
#
#   fp          0.55 m from the grip, looking down the length.  This is the
#               view the asset actually lives in.
#   three_q     3/4 review, ~0.9 m.  Silhouette and part relationships.
#   silhouette  orthographic side-on, flat single-colour shading.  If the
#               weapon is not identifiable here it is a generic shape, and
#               §"轮廓优先" has failed before any material is involved.

PREVIEW_FRAMES = [
    dict(name="fp", dir=(-0.085, 0.400, -0.660), look=(-0.00, 0.00, -0.190),
         lens=42.0, ortho=False),
    dict(name="three_q", dir=(0.900, 0.720, 0.520), look=(0.0, 0.0, 0.020),
         lens=50.0, ortho=False),
    dict(name="silhouette", dir=(0.0, -1.0, 0.0), look=(0.0, 0.0, 0.0),
         lens=50.0, ortho=True, flat=True),
]

# The preview rig is expressed in POST-BAKE Blender axes, which are NOT the
# contract axes.  See GLTF_TO_BLENDER: after the bake the length runs along
# Blender Z, the blade's width along Blender X and the flat normal along
# Blender Y.  The first version of this rig was written in the contract frame
# and put the "silhouette" camera 2.4 m down the blade's own axis, which
# rendered a photograph of the point -- and it did look like a rendered
# silhouette sheet, just an empty one.  Every `dir` below is a MULTIPLE of the
# model's longest extent, so the rig frames a dagger and a halberd alike.


def _frame(rig, f):
    """Camera position and aim, scaled off the measured AABB."""
    mn, mx = aabb(rig.parts)
    c = (mn + mx) * 0.5
    span = max((mx - mn).x, (mx - mn).y, (mx - mn).z)
    d = Vector(f["dir"]) * span
    l = Vector(f["look"]) * span
    return c + d, c + l, span


def _look_at(cam, target):
    d = Vector(target) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def _engine():
    """Blender renamed EEVEE across 4.x/5.x and this repo runs 5.1.2 while the
    docs elsewhere assume 4.x.  Pick whatever this build actually has."""
    avail = bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items.keys()
    for cand in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_EEVEE_LEGACY", "CYCLES"):
        if cand in avail:
            return cand
    return avail[0]


def set_preview_lighting():
    """Match the Godot contract: ONE directional light plus sky ambient.

    Not a three-point studio rig.  A preview lit like a product shot will show a
    model as acceptable that renders as a dark shape in the only place that
    counts, which is the exact failure the metal trap caused twice on this line.
    """
    scene = bpy.context.scene
    world = bpy.data.worlds.new("PreviewWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.42, 0.46, 0.52, 1.0)
        bg.inputs[1].default_value = 0.55
    sun_data = bpy.data.lights.new("PreviewSun", type="SUN")
    sun_data.energy = 3.2
    sun_data.angle = math.radians(6.0)
    sun = bpy.data.objects.new("PreviewSun", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(52.0), 0.0, math.radians(-38.0))
    return sun


def render_previews(rig, out_dir, tag, flat_only=False):
    """Write the standard view set.  One process, all views: launching Blender
    per view costs about as long as the build itself.

    THE SILHOUETTE GETS ITS OWN CANVAS SHAPE.  A sword is a 1:12 object, and
    rendering it square wastes eleven twelfths of the frame -- the blade lands
    as a five-pixel line and the review sheet cannot be read.  So the silhouette
    pass sizes its canvas off the measured aspect and uses a LIGHT ground, since
    a near-black shape on a dark background is a shape nobody can judge.
    """
    os.makedirs(out_dir, exist_ok=True)
    # ABSOLUTE, ALWAYS.  Blender resolves a relative `render.filepath` against
    # the BLEND FILE's directory, not the process working directory -- and this
    # tool runs with `-b` and never saves a blend, so a relative path silently
    # resolves somewhere else.  It does not fail: the render completes, the log
    # prints a path, and the file is not where it says it is.  Measured: a
    # relative --out-dir produced an empty directory and three "PREVIEW ..."
    # success lines.
    out_dir = os.path.abspath(out_dir)
    scene = bpy.context.scene
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False

    mn, mx = aabb(rig.parts)
    size = mx - mn
    span = max(size.x, size.y, size.z)
    short = max(min(size.x, size.y, size.z), 0.01)

    sun = None
    if not flat_only:
        sun = set_preview_lighting()

    cam_data = bpy.data.cameras.new("PreviewCam")
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    written = []
    for f in PREVIEW_FRAMES:
        loc, look, span = _frame(rig, f)
        flat = f.get("flat", False)
        if flat:
            scene.render.engine = "BLENDER_WORKBENCH"
            sh = scene.display.shading
            sh.light = "FLAT"
            sh.color_type = "SINGLE"
            sh.single_color = (0.04, 0.04, 0.05)
            sh.show_object_outline = False
            sh.show_shadows = False
            # ALPHA, NOT A PAINTED BACKGROUND.  Workbench's render background is
            # a viewport setting that does not behave like the world node, and
            # the first attempt to set it produced a mid-grey card that looked
            # like a rendering artefact.  Rendering with film_transparent gives
            # an alpha mask instead: it composites onto any ground the review
            # sheet wants, and -- more useful -- it is a MASK, so the silhouette
            # can be measured rather than only looked at.
            scene.render.film_transparent = True
            scene.render.image_settings.color_mode = "RGBA"
            if sun:
                sun.hide_render = True
            scene.render.resolution_y = 1000
            # CANVAS WIDTH OFF THE WIDEST TRANSVERSE EXTENT, not off the
            # thinnest.  The first version sized it from `min(size)` and clamped
            # to 220 px, which CLIPPED the guard on every archetype with a wide
            # crossguard -- measured, five of the ten silhouettes reported their
            # widest row as exactly the canvas width, which is the signature of
            # a clipped measurement rather than a wide weapon.
            scene.render.resolution_x = int(max(
                200, min(1400, 1000 * (size.x * 1.12) / (span * 1.06))))
        else:
            scene.render.engine = _engine()
            scene.render.film_transparent = False
            scene.render.image_settings.color_mode = "RGB"
            if sun:
                sun.hide_render = False
            scene.render.resolution_x = 900
            scene.render.resolution_y = 900

        cam.location = loc
        cam_data.lens = f["lens"]
        cam_data.type = "ORTHO" if f["ortho"] else "PERSP"
        # CLIP PLANES ARE DERIVED FROM THE SPAN, AND THE DEFAULT IS A TRAP.
        # A camera created with `bpy.data.cameras.new` gets Blender's default
        # clip_start of 0.1 m, and every `dir` in PREVIEW_FRAMES places the camera
        # `span` away from the subject.  For a sword (span ~0.9 m) that is fine
        # and has been all along.  For a CHAIN LINK -- span 0.091 m, so the camera
        # sits 0.084 m in front of the near surface -- the entire object falls
        # INSIDE the near plane.  The render succeeds, writes a file, and the file
        # is a blank sheet: measured, `chn_link_silhouette.png` came back with ink
        # 0.000% and no alpha bbox at all, while every other view in the same run
        # was fine.  It is the same shape of failure as the camera that was once
        # pointed down the blade's own axis -- an empty sheet that still looks
        # like a sheet -- and it is only visible because the tooling measures the
        # image rather than trusting the log line.
        cam_data.clip_start = max(1e-4, span * 0.02)
        cam_data.clip_end = max(1.0, span * 20.0)
        if f["ortho"]:
            # VERTICAL, so ortho_scale always means "metres across the 1000 px
            # of height" and the width formula above can be relied on.  With
            # the default AUTO fit, a canvas wider than it is tall silently
            # redefines ortho_scale as a WIDTH and the blade gets cut off.
            cam_data.sensor_fit = "VERTICAL"
            cam_data.ortho_scale = span * 1.06
        else:
            cam_data.sensor_fit = "AUTO"
        _look_at(cam, look)
        p = os.path.join(out_dir, "%s_%s.png" % (tag, f["name"]))
        scene.render.filepath = os.path.abspath(p)
        bpy.ops.render.render(write_still=True)
        if not os.path.isfile(p):
            raise SystemExit("PREVIEW  render reported success but %s does not "
                             "exist -- check the filepath resolution" % p)
        written.append(p)
        print("PREVIEW %s  %dx%d  (cam %s, target %s, span %.3f)"
              % (p, scene.render.resolution_x, scene.render.resolution_y,
                 _fmt(loc), _fmt(look), span))
    return written


# =============================================================================
# 13. CLI DRIVER
# =============================================================================

def parse_args(argv=None):
    argv = list(sys.argv if argv is None else argv)
    rest = argv[argv.index("--") + 1:] if "--" in argv else []
    out = {"row": None, "spec": None, "out_glb": None, "out_dir": None,
           "no_blend": False, "no_glb": False, "render": False,
           "flat_only": False, "list": False, "all": False, "loose": False}
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--row" and i + 1 < len(rest):
            out["row"] = rest[i + 1]; i += 2; continue
        if a == "--spec" and i + 1 < len(rest):
            out["spec"] = rest[i + 1]; i += 2; continue
        if a == "--out-glb" and i + 1 < len(rest):
            out["out_glb"] = rest[i + 1]; i += 2; continue
        if a == "--out-dir" and i + 1 < len(rest):
            out["out_dir"] = rest[i + 1]; i += 2; continue
        if a == "--no-blend":
            out["no_blend"] = True; i += 1; continue
        if a == "--no-glb":
            out["no_glb"] = True; i += 1; continue
        if a == "--render":
            out["render"] = True; i += 1; continue
        if a == "--flat-only":
            out["flat_only"] = True; i += 1; continue
        if a == "--list":
            out["list"] = True; i += 1; continue
        if a == "--all":
            out["all"] = True; i += 1; continue
        if a == "--loose":
            out["loose"] = True; i += 1; continue
        i += 1
    return out


def run(code, build_row, argv=None):
    """The driver every family builder calls.

    `build_row(row, spec)` must return a finished Rig.  Everything after that --
    asserting, reporting, exporting, writing the .blend at the right tier,
    rendering -- is this function's job, identical for all 18 families.
    """
    args = parse_args(argv)
    spec = load_spec(code, args["spec"])

    if args["list"]:
        print("SPEC %s  %d rows" % (spec_path(code, args["spec"]), len(spec["rows"])))
        for r in spec["rows"]:
            print("   %-22s tier=%-8s %s" % (r.get("id"), r.get("tier", "variant"),
                                             r.get("archetype", "")))
        return

    rows = spec["rows"] if args["all"] else [row_named(spec, args["row"])]
    built = []
    failed = []
    records = []
    for row in rows:
        # Resolve the row against the spec defaults ONCE, so every consumer --
        # the report, the path router, the assertions -- sees the same tier.
        # Before this, a row that left `tier` to the defaults was reported as
        # "variant" while being routed as "concept": the label and the behaviour
        # disagreed, which is how a hero gets quietly written to a gitignored
        # directory.
        row = dict(row)
        for k, v in spec.get("defaults", {}).items():
            row.setdefault(k, v)
        clear_scene()
        rig = build_row(row, spec)
        rig.finish()
        if not args["loose"]:
            bake_axes(rig)
        report(rig, row)
        ok = assert_contract(rig, row, strict=not args["all"])
        if not ok:
            failed.append(row.get("id"))
            if args["all"]:
                continue
        blend, glb = paths_for(code, row, args["out_glb"])
        print("      tier=%s -> %s" % (row.get("tier", "concept"),
                                       os.path.relpath(blend, REPO).replace("\\", "/")))
        if not args["no_blend"]:
            save_blend(blend)
        if not args["no_glb"]:
            export_glb(rig, glb)
            # Read the FILE back.  The scene assertions above cannot see an
            # exporter that put the length on the wrong axis; this can.
            verify_glb(glb, rig, row)
        if args["render"]:
            out_dir = args["out_dir"] or os.path.join(REPO, "assets_source",
                                                      "review", "weapon")
            render_previews(rig, out_dir, "%s_%s" % (code.lower(), row.get("id")),
                            flat_only=args["flat_only"])
        built.append(row.get("id"))
        records.append(report_json(rig, row))

    write_build_record(code, records)
    print("DONE  built=%d failed=%d  %s" % (len(built), len(failed),
                                            ",".join(str(x) for x in failed) or "-"))
    if failed:
        sys.exit(2)


def import_siblings():
    """Blender does set __file__, but not always sys.path[0] -- make the import
    deterministic so a builder can be launched from any working directory."""
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.insert(0, here)
