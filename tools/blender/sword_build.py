"""SEKAI W01 -- first-person sword.  Direct bpy, no GPT / no Chat2Blender.

    blender --background --factory-startup --python tools/blender/sword_build.py

WHY THIS FILE IS WRITTEN FROM SCRATCH
=====================================
The asset it replaces is a 0.131 x 0.044 x 1.047 m flat bar: a 13 cm wide,
4.4 cm thick slab of grey, with a cylinder for a grip and a hook for a guard.
Measured from the GLB, not from memory.  It has no blade PROFILE at all, so
there is nothing to refine -- the first thing §5 asks for ("刀刃必须真正有
PROFILE，不是一个薄长方体") is a rebuild, not an edit.

The whole point of this pass is that the blade is a SWEPT CROSS-SECTION, not a
box.  A katana's section is shinogi-zukuri: a flat grind from the edge up to a
ridge (the shinogi) placed about two thirds of the way to the spine, then a
steeper bevel to a narrow flat spine (the mune).  That ridge is what catches
light along the length of the blade and it is the single most identifiable
silhouette feature of the weapon.  It cannot be faked with a normal map on a
slab, because at 0.3-1 m -- the first-person band, PART I -- the silhouette is
the whole read.

ORIENTATION AND CONTRACT (measured, not assumed)
================================================
`godot/scenes/weapons/Sword_FP.tscn` claims the blade runs +Y.  It does not.
Parsing `godot/models/weapons/fp_sword.glb` gives an axis-aligned box of
0.1308 x 0.0440 x 1.0473 m with the long axis on Z, and the nodes confirm it:
`blade_tip` sits at z = -0.910, `blade_mid` at z = -0.520.  `docs/ASSET_MANIFEST.md`
records the same correction.  The scene comment is simply wrong.

So the exported contract is:  long axis Z, tip toward -Z, width X, thickness Y,
origin at the blade base.  Blender's glTF exporter maps

    (x, y, z)_blender  ->  (x, z, -y)_gltf

which means the authoring pose is:  LENGTH along +Y, edge-to-spine along X,
thickness along Z.  This file is written in exactly that pose, and
`tools/blender/verify_axis.py` re-measures the exported GLB so the next session
does not have to trust this paragraph either.

ORIGIN
======
Kept at the blade base / guard plane (y = 0), which is where the current asset
has it, so nothing downstream shifts by a millimetre.  The scene's stated
"origin at the grip centre" is NOT what the shipping asset does; the grip centre
of this build is at y = -0.135 if anything ever wants to move to it.

TRIANGLES
=========
PART H gives 20k-80k for a first-person weapon.  This lands far below that,
deliberately: the resolution goes where the silhouette needs it (blade length &
guard outline) and nowhere else.  PART H's own rule is that the number is
decided by silhouette and screen size, not by how impressive it looks in a log.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

TAU = math.pi * 2.0


# =============================================================================
#  DIMENSIONS -- all metres, all from real katana proportions
# =============================================================================
#
# The hybrid in §3 is "medium-long blade, clean narrow profile, Iaido
# compatible".  A real katana is about 1.0 m overall: 0.70-0.75 of nagasa
# (edge, measured from the habaki to the tip) against 0.26-0.30 of tsuka.  The
# asset being replaced has a 0.91 m blade on a 0.137 m grip, which is why it
# reads as a longsword that someone forgot to finish.
#
# 0.765 blade + 0.285 grip = 1.05 m, inside a centimetre of the old envelope, so
# reach does not change and no combat tuning has to be redone.

GUARD_Y = 0.0            # origin plane: blade base, front face of the tsuba
BLADE_BASE_Y = 0.030     # where the blade leaves the habaki
YOKOTE_Y = 0.700         # the tip starts here
BLADE_TIP_Y = 0.765

GRIP_END_Y = -0.268      # where the grip core stops
KASHIRA_Y = -0.286       # tip of the pommel cap

# Blade, edge -> spine.  36.5 mm at the base tapering to 29.0 mm at the yokote
# is a true distal taper; a constant width is the tell of an extruded box.
#
# Deliberately ~10% wider than a historical katana (30 mm).  §17 authorises
# "slightly exaggerated readability", and §I puts the acceptance distance at
# 0.3-1 m: at arm's length a strictly-correct 30 mm blade reads as a spike, and
# a sword that reads as a spike in the player's hand is a worse failure than a
# sword that is 6 mm wider than a museum piece.
BLADE_W_BASE = 0.0365
BLADE_W_TIP = 0.0290
# Full thickness at the shinogi.  8.0 mm at the base is a heavy blade; 5.8 at
# the yokote is a fine one.
BLADE_T_BASE = 0.0080
BLADE_T_TIP = 0.0058
# Sori -- the curvature.  A katana bows so that the EDGE is on the convex side.
# The edge sits at low X and the spine at high X, so a parabola opening toward
# +X puts the convexity on the edge.  18 mm over 0.765 m is a visible, elegant
# bow; 40 mm would be a tachi, 5 mm would be a straight blade with a wobble.
SORI = 0.018

# Shinogi-zukuri, normalised: x = fraction of blade width, z = fraction of half
# thickness.  Read it as a path from the edge, up the flat grind, over the
# ridge, into the steeper shinogi-ji, then across the flat of the mune.
#
# X IS CENTRED ON THE BLADE AXIS, AND THAT IS NOT COSMETIC.
# The first build ran the section from 0 (edge) to +1 (spine) and then centred
# the guard, the grip and the collars on x = 0 -- which put the entire handle on
# the blade's EDGE line rather than behind the middle of the blade.  The 3/4
# review showed the guard hanging off one side of the sword and it would have
# been blamed on the guard design.  The shipping placeholder has a symmetric X
# AABB (+-0.0654), which is what a weapon gripped behind its own axis looks
# like, so the section now runs -0.5 .. +0.5 and every part is concentric by
# construction rather than by remembering to offset it.
#
#   0.000  sharp edge, thickness zero -- a real zero, so the blade has an edge
#   0.660  RIDGE: the full 8 mm of thickness arrives here, not at the edge
#   0.860  the shinogi-ji climbs
#   1.000  spine flat, 2.3 mm wide for a 8 mm blade
SECTION = [
    (-0.500, 0.000),
    (-0.180, 0.640),
    (0.160, 1.000),
    (0.360, 0.880),
    (0.485, 0.460),
    (0.500, 0.145),
    (0.500, -0.145),
    (0.485, -0.460),
    (0.360, -0.880),
    (0.160, -1.000),
    (-0.180, -0.640),
]
NSEC = len(SECTION)

# Tsuka: 30 mm across the blade-height axis by 22 mm through, which is a katana
# grip and not a broom handle.  Slight waist, fatter at both ends.
GRIP_RX = 0.0150
GRIP_RZ = 0.0110

FIT_METALLIC = 0.55


# =============================================================================
#  helpers
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
    ob.data.materials.append(mat)
    return ob


def bridge_rings(verts, faces, ring_a, ring_b, count, closed=True):
    """Quad strip between two equal-length rings of vertex indices."""
    span = count if closed else count - 1
    for i in range(span):
        j = (i + 1) % count
        faces.append([ring_a[i], ring_a[j], ring_b[j], ring_b[i]])


def add_ring(verts, points, y):
    ring = []
    for (x, z) in points:
        ring.append(len(verts))
        verts.append((x, y, z))
    return ring


def recalc_normals(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()


def shade(ob, smooth_angle=None):
    """Smooth shading, optionally angle-limited."""
    for p in ob.data.polygons:
        p.use_smooth = True
    if smooth_angle is None:
        return
    mod = ob.modifiers.new("SmoothByAngle", "NODES")
    # Blender has no stable public API for the auto-smooth node group across
    # versions, so the angle limiter is applied through the operator when it is
    # available and silently skipped when it is not.  Shading is not worth a
    # hard dependency here.
    ob.modifiers.remove(mod)
    try:
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(smooth_angle))
    except Exception:
        try:
            bpy.ops.object.shade_auto_smooth(angle=math.radians(smooth_angle))
        except Exception:
            pass


def bevel(ob, width=0.0006, segments=2, angle=42.0):
    """PART J: every visible hard edge gets a believable bevel.

    Widths here are fractions of a millimetre to a millimetre.  Anything larger
    turns a forged part into a toy, which is exactly the failure §21 warns
    about, so the bevel is always sized to the FEATURE it is rounding and never
    set globally.
    """
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    m.harden_normals = False
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=m.name)


# =============================================================================
#  materials -- PART F / PART 22
# =============================================================================
#
# All four names are kept from the shipping GLB so `Sword_FP.tscn`'s
# "material assignment comes from the GLB, do not override it" note stays true
# and nothing has to be re-bound.
#
# THE METALLIC VALUES ARE AN IN-GAME DECISION, NOT A PBR SHOWCASE ONE.
# Godot is on gl_compatibility with one directional light and a sky ambient.
# There is no reflection probe behind the player's hand, so a blade at
# metallic 0.9 with roughness 0.1 renders as a black silhouette with one
# highlight -- the "dark sword" failure §5 names explicitly.  0.45-0.55 with a
# rougher surface keeps the metal reading as metal while giving it something to
# respond to.  The value is deliberately below the physically-correct one and
# deliberately above zero.

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


def build_materials():
    return {
        # STEEL.  V5 HAD THIS WRONG AND ONLY GODOT SHOWED IT.
        #
        # The value was 0.735 linear -- "slightly cool mid-value steel" on paper,
        # and physically defensible, since real polished steel sits around
        # 0.56-0.60.  In the Godot training ground at 0.5 m, which is inside the
        # 0.3-1 m band PART I calls the highest quality bar, the blade rendered as
        # a UNIFORM WHITE BAR with a single dark line along the edge.  Every piece
        # of form this pass was for -- the shinogi ridge, the taper, the sori bow,
        # the kissaki -- was present in the geometry and invisible in value.  That
        # is §2's "material too flat" arriving as "too bright to have any form".
        #
        # Two changes, and they do different jobs:
        #   0.735 -> 0.460 linear   removes most of the DIFFUSE, which is what was
        #                           saturating.  The blade keeps ~0.24 of diffuse
        #                           response instead of ~0.38, so a mid-grey sits
        #                           under any highlight instead of a white.
        #   0.295 -> 0.200 rough    tightens the SPECULAR so the highlight becomes
        #                           a streak the ridge can catch rather than a wash
        #                           that covers the whole flat.  A ~10 degree normal
        #                           difference between the flat grind and the
        #                           shinogi-ji only reads if the lobe is small.
        # Metallic stays at 0.48: the project's own measurement says 0.75+ with no
        # reflection source is a black silhouette, and the sword is meant to sit
        # just below that ceiling, not at it.
        "steel": mat("MAT_Sword_Steel", (0.460, 0.472, 0.496), 0.48, 0.200, 0.55),
        # Near-black blue-grey wrap.  The grip's job in the frame is to be the
        # dark anchor under a bright blade, not to be looked at.
        "grip": mat("MAT_Sword_Grip", (0.052, 0.055, 0.066), 0.0, 0.735),
        # Restrained warm ancient metal, used ONLY on the broken-ring motif and
        # the menuki.  §4 tertiary, §V "不要所有物件都刻 Rune" -- two places,
        # not twenty.
        "inlay": mat("MAT_Sword_Inlay", (0.610, 0.470, 0.235), 0.60, 0.345, 0.6),
        # A DARK, ROUGH, NEARLY-DIELECTRIC IRON.  Two corrections in one pass.
        # The first was the albedo, which V1 had at 0.238 -- too light to be
        # iron.  The second was the METALLIC, which V2 took to 0.55 to give it
        # a "metal edge": at 0.55 on a broad close source the specular lobe
        # floods the plate, so the base colour stops meaning anything and the
        # guard renders as pale cream regardless of what it is tinted.  0.30 at
        # 0.58 roughness keeps a metal response while letting the dark colour
        # survive -- and it is further below Godot's black-silhouette threshold
        # than the old value, not closer to it.
        "fit": mat("MAT_Sword_Fittings", (0.086, 0.079, 0.070), 0.30, 0.580),
    }


# =============================================================================
#  the blade
# =============================================================================

def blade_rings():
    """The lengthwise stations.

    Denser at the base and through the kissaki, where curvature changes fast,
    and sparse in the long straight middle where nothing happens.  Uniform
    spacing would spend half the triangles on the part of the blade that is a
    ruled surface.
    """
    ys = []
    # base, out of the habaki
    ys += [0.030, 0.050, 0.074, 0.102, 0.134, 0.170, 0.208]
    # the long carry
    step = 1
    y = 0.208
    while y < 0.640:
        y += 0.036
        ys.append(round(y, 4))
    # approach to the yokote
    ys += [0.664, 0.684, 0.700]
    return ys


def build_blade(m):
    verts, faces = [], []
    rings = []

    # --- the body, base -> yokote -------------------------------------------
    body = blade_rings()
    for y in body:
        t = (y - BLADE_BASE_Y) / max(YOKOTE_Y - BLADE_BASE_Y, 1e-9)
        t = min(max(t, 0.0), 1.0)
        w = lerp(BLADE_W_BASE, BLADE_W_TIP, t) * curve(
            [(0.0, 1.0), (0.35, 0.985), (1.0, 1.0)], t)
        th = lerp(BLADE_T_BASE, BLADE_T_TIP, t)
        # sori: the section slides toward the spine as it goes out, which is
        # what makes the edge the convex side of the bow.
        sx = SORI * (y / BLADE_TIP_Y) ** 2
        pts = []
        for (fx, fz) in SECTION:
            # A barely-there lengthwise wave so the flat of the blade is not a
            # mathematically flat reflector.  Sub-millimetre; it shows as a
            # change of sheen down the blade, never as a lump.
            wob = 1.0 + 0.020 * math.sin(fx * 5.1 + y * 3.3)
            pts.append((sx + fx * w * wob, fz * th * 0.5))
        rings.append(add_ring(verts, pts, y))

    # cap the base.  It lives inside the habaki, so an n-gon is the correct
    # amount of effort rather than a modelled tang.
    faces.append(list(reversed(rings[0])))

    # --- the kissaki --------------------------------------------------------
    # The section collapses toward the edge line.  §5 asks for real tip
    # geometry, and the honest version of that is that the spine falls to meet
    # the edge rather than the whole blade being pinched like a toothpaste tube.
    tip_y0 = YOKOTE_Y
    tip_steps = 7
    prev = rings[-1]
    for k in range(1, tip_steps + 1):
        t = k / float(tip_steps)
        y = lerp(tip_y0, BLADE_TIP_Y, t)
        # width collapses to nothing; thickness collapses a little faster so the
        # tip is never a blunt wedge
        w = BLADE_W_TIP * (1.0 - t) ** 0.88
        th = BLADE_T_TIP * (1.0 - t ** 1.55)
        sx = SORI * (y / BLADE_TIP_Y) ** 2
        pts = []
        for (fx, fz) in SECTION:
            pts.append((sx + fx * w, fz * th * 0.5))
        ring = add_ring(verts, pts, y)
        bridge_rings(verts, faces, prev, ring, NSEC)
        prev = ring
    # the point itself
    apex = len(verts)
    verts.append((SORI + 0.0012, BLADE_TIP_Y, 0.0))
    for i in range(NSEC):
        j = (i + 1) % NSEC
        faces.append([prev[i], prev[j], apex])

    # --- stitch the body ----------------------------------------------------
    for i in range(len(rings) - 1):
        bridge_rings(verts, faces, rings[i], rings[i + 1], NSEC)

    ob = new_mesh("Blade", verts, faces, m["steel"])
    recalc_normals(ob)
    return ob


# =============================================================================
#  habaki -- the collar that holds the blade out of the guard
# =============================================================================

def build_tang(m):
    """The nakago -- the unpolished bar the whole weapon hangs on.

    THIS PART WAS MISSING AND IT LEFT A HOLE IN THE MODEL.  The blade's first
    ring is at y = +0.030 and the guard's front face is at y = +0.003, so
    between them there was 27 mm of NOTHING: a gap you could see daylight
    through in the side plate, and a guard slot with nothing behind it.  It
    survived three review passes because at full-sword framing a 27 mm gap
    reads as a deliberate waist.

    The tang runs from the guard back through the grip to the kashira, which
    also means the guard's aperture finally has the part in it that the
    aperture was cut for.  Section 15 x 7 mm: narrower than the blade, because
    a tang that is as wide as the blade is a blade with the furniture slid onto
    it.
    """
    verts, faces = [], []
    steps = [
        (-0.2920, 0.62),
        (-0.2760, 0.86),
        (-0.2400, 0.94),
        (-0.1200, 1.00),
        (-0.0200, 1.00),
        (0.0030, 1.00),
        (0.0060, 0.92),
        (0.0240, 0.86),
        (0.0315, 0.80),
    ]
    NS = 8
    rings = []
    for (y, sc) in steps:
        pts = []
        for i in range(NS):
            a = TAU * i / NS
            ca, sa = math.cos(a), math.sin(a)
            ex = 2.0 / 3.6
            px = math.copysign(abs(ca) ** ex, ca)
            pz = math.copysign(abs(sa) ** ex, sa)
            pts.append((0.0075 * px * sc, 0.0035 * pz * sc))
        rings.append(add_ring(verts, pts, y))
    faces.append(list(rings[0]))
    faces.append(list(reversed(rings[-1])))
    for i in range(len(rings) - 1):
        bridge_rings(verts, faces, rings[i], rings[i + 1], NS)
    ob = new_mesh("Tang", verts, faces, m["steel"])
    recalc_normals(ob)
    return ob


def build_habaki(m):
    """A metal sleeve at the blade base.

    It exists for a mechanical reason (it wedges the blade into the saya) and a
    visual one: without it the blade appears to grow out of the guard like a
    branch, and the eye reads the whole weapon as one extruded shape.  With it,
    there are three materials and three thicknesses stacked inside 8 cm, which
    is the "secondary form" §4 is asking for.
    """
    verts, faces = [], []
    # V2's multipliers were 1.30 on width and 1.95 on THICKNESS, which is a
    # 15.6 mm collar on an 8 mm blade -- and the review showed it as a chunky
    # white shoe wider than the blade it was holding.  A habaki is a thin
    # sleeve: it has to be visibly a separate part, not visibly a bigger one.
    # 1.10 / 1.28 leaves it 4 mm proud on width and 2 mm through, which reads
    # as a fitted cap at 0.5 m and stops reading as a boot.
    steps = [
        (0.0030, 1.10, 1.28),
        (0.0085, 1.10, 1.28),
        (0.0105, 1.040, 1.14),
        (0.0240, 1.025, 1.09),
        (0.0300, 1.012, 1.04),
        (0.0335, 1.055, 1.17),
        (0.0355, 1.075, 1.26),
        (0.0375, 1.025, 1.09),
    ]
    rings = []
    for (y, sx, sz) in steps:
        t = max(0.0, y - BLADE_BASE_Y) / (YOKOTE_Y - BLADE_BASE_Y)
        w = BLADE_W_BASE
        th = BLADE_T_BASE
        sxo = SORI * (y / BLADE_TIP_Y) ** 2
        pts = []
        for (fx, fz) in SECTION:
            pts.append((sxo + fx * w * sx, fz * th * 0.5 * sz))
        # ABSOLUTE y, not offset from the blade base.  The habaki has to sit
        # against the guard's front face at +0.003; the previous version placed
        # it at `y + 0.026` and left a visible gap behind it.
        rings.append(add_ring(verts, pts, y))
    faces.append(list(reversed(rings[0])))
    faces.append(list(rings[-1]))
    for i in range(len(rings) - 1):
        bridge_rings(verts, faces, rings[i], rings[i + 1], NSEC)
    ob = new_mesh("Habaki", verts, faces, m["fit"])
    recalc_normals(ob)
    bevel(ob, 0.00025, 2, 38.0)
    return ob


# =============================================================================
#  tsuba -- the guard, and the one place the sword gets to have an identity
# =============================================================================

def extrude_polygon(name, pts2d, y0, y1, mat):
    """A closed 2D outline extruded along Y into a solid plate.

    Used for the guard motif.  Built as a solid rather than as a single-sided
    sheet because Godot culls backfaces on opaque material: a ribbon lying flat
    on the guard face is invisible from one side, and "the ornament disappears
    when you turn the sword over" is a bug that ships.
    """
    verts, faces = [], []
    N = len(pts2d)
    r0 = []
    r1 = []
    for (x, z) in pts2d:
        r0.append(len(verts))
        verts.append((x, y0, z))
    for (x, z) in pts2d:
        r1.append(len(verts))
        verts.append((x, y1, z))
    faces.append(list(r0))
    faces.append(list(reversed(r1)))
    for i in range(N):
        j = (i + 1) % N
        faces.append([r0[i], r0[j], r1[j], r1[i]])
    ob = new_mesh(name, verts, faces, mat)
    recalc_normals(ob)
    return ob


def catmull_closed(ctrl, n):
    """Sample a closed Catmull-Rom spline through `ctrl` at n points."""
    pts = []
    m = len(ctrl)
    for k in range(n):
        t = k * m / float(n)
        i = int(math.floor(t))
        u = t - i
        p0 = ctrl[(i - 1) % m]
        p1 = ctrl[i % m]
        p2 = ctrl[(i + 1) % m]
        p3 = ctrl[(i + 2) % m]
        out = []
        for c in range(2):
            a0, a1, a2, a3 = p0[c], p1[c], p2[c], p3[c]
            out.append(0.5 * ((2 * a1) + (-a0 + a2) * u
                              + (2 * a0 - 5 * a1 + 4 * a2 - a3) * u * u
                              + (-a0 + 3 * a1 - 3 * a2 + a3) * u * u * u))
        pts.append((out[0], out[1]))
    return pts


def offset_inward(pts, d):
    """Offset a closed clockwise outline inward by a constant distance.

    Scaled-by-0.855 was tried and it PINCHES wherever the outline turns tightly
    or turns concave -- at the bite below, a radial shrink would collapse the
    rim to nothing at the mouth and fan it open at the throat.  A true offset
    along the interior normal keeps the rim the same width the whole way round,
    which is what makes a forged rim read as forged.
    """
    m = len(pts)
    out = []
    for i in range(m):
        p = pts[i]
        q = pts[(i + 1) % m]
        r = pts[(i - 1) % m]
        # average the two adjacent edge normals so the offset does not notch at
        # every vertex
        nx = nz = 0.0
        for (a, b) in ((r, p), (p, q)):
            dx = b[0] - a[0]
            dz = b[1] - a[1]
            ln = math.hypot(dx, dz)
            if ln > 1e-12:
                # clockwise winding -> the interior is to the RIGHT of each edge
                nx += dz / ln
                nz += -dx / ln
        ln = math.hypot(nx, nz)
        if ln < 1e-9:
            out.append(p)
            continue
        out.append((p[0] + nx / ln * d, p[1] + nz / ln * d))
    return out


# --- THE GUARD SILHOUETTE -----------------------------------------------
#
# FOUR ATTEMPTS, AND WHAT EACH ONE TAUGHT.  All of them are worth keeping in
# the record because the failure was the same failure every time:
#
#   V1  a circle with 15% flattening + a gold ring on the face.
#       Read as: a pale DONUT wearing a decal.  A modulated circle is still a
#       circle -- the eye compares the two flanks and finds them equal.
#   V2  a superellipse with a horn and a chip, tilted 12 degrees.
#       Read as: a rounded SQUARE.  At exponent 3.2 the radius is pinned at 1
#       across most of the arc, so an 18% bump moves one corner by 2 mm.
#   V3  hand-forged sine irregularity + a raised rim.
#       Read as: a lumpy PEBBLE.  Irregularity is not design; without a feature
#       to name it is just noise at low frequency.
#   V4  a hand-placed spline wing with concave waists.
#       Read as: a FLOWER.  Concave waists in a closed plate always become
#       petals.
#
# The pattern: every one of those was "a plate whose OUTLINE is modulated".
# Modulating an outline can only ever produce a soft, organic blob, and §0 asks
# for clean silhouette and designed shape language.  What produces "designed"
# is a CRISP outline plus one DELIBERATE feature, and §6 names the feature it
# wants: a broken circle.
#
# So the guard is now a clean shield -- a superellipse, no modulation at all,
# because an unmodulated superellipse at a crisp bevel reads as PRECISE rather
# than as bland -- with a true circular BITE subtracted from the edge side.
# The bite is the whole identity: it breaks the circle, it is unmistakably
# deliberate, it is asymmetric by construction, and it reads at 25% scale.
GUARD_A = 0.0380        # half-extent along X (edge <-> spine)
GUARD_B = 0.0335        # half-extent along Z
GUARD_EX = 2.0 / 3.1    # superellipse exponent: crisp corners, no straight runs
GUARD_BITE_X = -0.0400  # centre of the bite, out past the edge
GUARD_BITE_Z = 0.0
GUARD_BITE_R = 0.0160


def guard_outline(n_se=96, n_arc=24):
    """Trace the shield clockwise and splice the bite in where it intrudes.

    Clockwise from the top: (0, +B) -> +X -> (0, -B) -> -X -> back to the top.
    The bite sits at -X, i.e. about a quarter of the way round, so the
    intruding run is contiguous and never wraps the seam.
    """
    se = []
    for k in range(n_se):
        a = math.pi / 2.0 - TAU * k / n_se
        ca, sa = math.cos(a), math.sin(a)
        px = math.copysign(abs(ca) ** GUARD_EX, ca)
        pz = math.copysign(abs(sa) ** GUARD_EX, sa)
        se.append((GUARD_A * px, GUARD_B * pz))

    def inside(p):
        return ((p[0] - GUARD_BITE_X) ** 2 + (p[1] - GUARD_BITE_Z) ** 2
                < GUARD_BITE_R * GUARD_BITE_R)

    first = last = None
    for i, p in enumerate(se):
        if inside(p):
            if first is None:
                first = i
            last = i
    if first is None:
        return se

    keep = se[:first] + se[last + 1:]
    pa = se[first - 1]
    pb = se[(last + 1) % len(se)]

    def polar_on_bite(p):
        return math.atan2(p[1] - GUARD_BITE_Z, p[0] - GUARD_BITE_X)

    ta = polar_on_bite(pa)
    tb = polar_on_bite(pb)
    # walk the SHORT way, which for a bite at -X is the way that passes through
    # the +X direction of the bite's own frame -- i.e. the arc that eats inward
    while tb - ta > math.pi:
        tb -= TAU
    while tb - ta < -math.pi:
        tb += TAU
    arc = []
    for k in range(1, n_arc):
        t = lerp(ta, tb, k / float(n_arc))
        arc.append((GUARD_BITE_X + GUARD_BITE_R * math.cos(t),
                    GUARD_BITE_Z + GUARD_BITE_R * math.sin(t)))
    return se[:first] + arc + se[last + 1:]


def build_guard(m):
    """§6: an ORIGINAL fantasy guard. The identity is a BITE, not an outline.

    Four rejected attempts are recorded above `GUARD_A`; the short version is
    that modulating a plate's outline can only produce a soft organic blob, and
    §0 asks for clean silhouette and designed shape language instead.

    So: an unmodulated superellipse -- deliberately crisp, because a precise
    curve with a hard bevel reads as MADE, while a wobbly one reads as noise --
    tilted 9 degrees off the blade axis so it is not symmetric about X, with a
    true CIRCULAR BITE subtracted from the edge side.  The bite is §6's "broken
    circle", it is the one thing a viewer can name, and it survives being shrunk
    to a thumbnail.

    Plus the raised rim, which is what stops the plate reading as a washer: the
    field sits 1.7 mm below a rim of constant width, so there is a lit edge all
    the way round the bite as well as the outside.
    """
    verts, faces = [], []
    TH = 0.0030            # half thickness -> 6.0 mm plate
    RECESS = 0.0017
    RIM = 0.0052           # rim width, constant the whole way round
    TILT = math.radians(9.0)
    ct, st = math.cos(TILT), math.sin(TILT)

    def place(pts):
        return [(x * ct - z * st, x * st + z * ct) for (x, z) in pts]

    outer = place(guard_outline())
    rim_in = place(offset_inward(guard_outline(), RIM))
    N = len(outer)

    # The slot is cut in the guard's own tilted frame, so it stays square to the
    # plate.  A slot aligned to world X under a tilted plate is a slot the tang
    # cannot pass through.
    slot = []
    for i in range(N):
        a = TAU * i / N
        ca, sa = math.cos(a), math.sin(a)
        ex = 2.0 / 4.6     # a rounded rectangle: a slot, not a hole
        px = math.copysign(abs(ca) ** ex, ca)
        pz = math.copysign(abs(sa) ** ex, sa)
        # 17.6 x 8.6 mm: clears the 15 x 7 mm tang without touching it
        x, z = 0.0088 * px, 0.0043 * pz
        slot.append((x * ct - z * st, x * st + z * ct))

    def ring_at(xz, y):
        out = []
        for (x, z) in xz:
            out.append(len(verts))
            verts.append((x, y, z))
        return out

    y_out = GUARD_Y - TH
    y_rec = GUARD_Y - TH + RECESS
    y_outB = GUARD_Y + TH
    y_recB = GUARD_Y + TH - RECESS

    ofront = ring_at(outer, y_out)
    rfront = ring_at(rim_in, y_out)
    ffront = ring_at(rim_in, y_rec)
    sfront = ring_at(slot, y_rec)
    oback = ring_at(outer, y_outB)
    rback = ring_at(rim_in, y_outB)
    fback = ring_at(rim_in, y_recB)
    sback = ring_at(slot, y_recB)

    for i in range(N):
        j = (i + 1) % N
        faces.append([ofront[i], ofront[j], rfront[j], rfront[i]])    # rim face
        faces.append([rfront[i], rfront[j], ffront[j], ffront[i]])    # rim wall
        faces.append([ffront[i], ffront[j], sfront[j], sfront[i]])    # field
        faces.append([oback[j], oback[i], rback[i], rback[j]])        # rim face
        faces.append([rback[j], rback[i], fback[i], fback[j]])        # rim wall
        faces.append([fback[j], fback[i], sback[i], sback[j]])        # field
        faces.append([oback[i], oback[j], ofront[j], ofront[i]])      # outer wall
        faces.append([sfront[i], sfront[j], sback[j], sback[i]])      # slot wall

    g = new_mesh("Guard", verts, faces, m["fit"])
    recalc_normals(g)
    # A hard, small bevel.  Big enough to light the rim edge, small enough that
    # the bite's throat stays a clean curve instead of a rounded mush.
    bevel(g, 0.00038, 2, 26.0)
    return g


def build_guard_motif(m):
    """Two script strokes. Nothing else.

    The crescent is gone.  It was a nice idea stacked on top of a guard that
    already had no identity, and once the BITE became the identity an arc of
    bright metal across the same plate was competing with it.  §6 wants a hint
    of ancient script and §T says not everything gets a rune, so this is two
    short strokes in the recessed field on the spine side -- the one place the
    eye lands after the bite, and small enough that it never reads as pattern.

    Mirroring is deliberate: strokes on BOTH faces so the guard is finished
    from either side, which a single-sided ornament is not.
    """
    parts = []
    TILT = math.radians(9.0)
    ct, st = math.cos(TILT), math.sin(TILT)

    def place(pts):
        return [(x * ct - z * st, x * st + z * ct) for (x, z) in pts]

    # ONE stroke, long and thin, following the sweep of the spine-side lobe.
    # Two short thick bars read as two short thick bars; a single incised line
    # that follows the plate reads as script, which is what §6 asked for.
    strokes = [
        [(0.0075, 0.0198), (0.0262, 0.0132), (0.0328, 0.0052),
         (0.0336, 0.0032), (0.0268, 0.0106), (0.0080, 0.0172)],
    ]
    for (tag, yface, lift) in (("F", GUARD_Y - 0.0030, -0.0012),
                               ("B", GUARD_Y + 0.0030, 0.0012)):
        for si, s in enumerate(strokes):
            parts.append(extrude_polygon(
                "Guard_Motif_%s%d" % (tag, si + 1), place(s),
                yface + lift, yface, m["inlay"]))
    return parts

# =============================================================================
#  tsuka -- grip core, fuchi, kashira, wrap, menuki
# =============================================================================

def grip_section(s):
    """Oval at normalised length s (0 at the guard, 1 at the kashira).

    A real tsuka is not a tapered cylinder: it swells slightly toward the
    middle and pinches just behind the fuchi, which is what makes it look
    gripped rather than turned.
    """
    rx = GRIP_RX * curve([(0.0, 0.965), (0.35, 1.030), (0.75, 1.010), (1.0, 0.985)], s)
    rz = GRIP_RZ * curve([(0.0, 0.945), (0.35, 1.045), (0.75, 1.020), (1.0, 0.985)], s)
    return rx, rz


def oval_pts(rx, rz, n, y, offset=0.0, wobble=0.0):
    pts = []
    for i in range(n):
        a = TAU * i / n
        k = 1.0 + wobble * math.sin(a * 3.0 + 1.1)
        pts.append((math.cos(a) * (rx + offset) * k, y, math.sin(a) * (rz + offset) * k))
    return pts


def build_grip(m):
    verts, faces = [], []
    N = 20
    steps = [i / 16.0 for i in range(17)]
    rings = []
    for s in steps:
        # Starts at -0.004, hard against the guard's back face at -0.003.  The
        # grip used to start at -0.020, which left a 17 mm band of bare tang
        # showing between the tsuba and the fuchi -- and on a real katana the
        # fuchi is against the tsuba with only a seppa washer between them.
        y = lerp(GUARD_Y - 0.004, GRIP_END_Y, s)
        rx, rz = grip_section(s)
        pts = [(math.cos(TAU * i / N) * rx, math.sin(TAU * i / N) * rz) for i in range(N)]
        rings.append(add_ring(verts, pts, y))
    faces.append(list(reversed(rings[0])))
    faces.append(list(rings[-1]))
    for i in range(len(rings) - 1):
        bridge_rings(verts, faces, rings[i], rings[i + 1], N)
    ob = new_mesh("Grip", verts, faces, m["grip"])
    recalc_normals(ob)
    return ob


def build_collar(m, name, y0, y1, swell, mat_key, sched=None):
    """Fuchi / kashira: a band of metal that is slightly proud of the grip.

    `sched` is the ring schedule as (position along the band, scale relative to
    `swell`).  It used to be hard-coded to three rings with a single `taper`
    number on the last one, and the kashira's 0.72 turned its end into a smooth
    pinched DOME -- a featureless grey capsule, which at 0.6 m read as the most
    generic thing on the whole sword.  A kashira is a flat end cap with a rim,
    not a bullet.  The default schedule now ends flat, and a caller can pass a
    four-ring schedule when it wants the cap to have a real face and a chamfer.
    """
    verts, faces = [], []
    N = 20
    rings = []
    if sched is None:
        sched = [(0.0, 0.94), (0.5, 1.0), (1.0, 0.96)]
    for (t, sc) in sched:
        y = lerp(y0, y1, t)
        rx, rz = grip_section(max(0.0, min(1.0, (abs(y) - 0.004) / 0.264)))
        pts = [(math.cos(TAU * i / N) * rx * swell * sc,
                math.sin(TAU * i / N) * rz * swell * sc) for i in range(N)]
        rings.append(add_ring(verts, pts, y))
    faces.append(list(reversed(rings[0])))
    faces.append(list(rings[-1]))
    for i in range(len(rings) - 1):
        bridge_rings(verts, faces, rings[i], rings[i + 1], N)
    ob = new_mesh(name, verts, faces, m[mat_key])
    recalc_normals(ob)
    bevel(ob, 0.0004, 2, 40.0)
    return ob


def build_wrap(m, mat_override=None):
    """The ito -- crossed cord wrap, built as a REVERSING zig-zag of SOLID CORD.

    TWO structural corrections, and neither is a tuning number.

    1. THE PATH.  The first version was two families of helices and rendered as a
       bare SPRING wound round the grip: one continuous ribbon climbing at a
       constant pitch, with visible gaps.  That is not a wrap, and the reason is
       structural rather than a tuning error -- katana cord does not spiral.  It
       folds back on itself at every turn, which is why the samegawa shows through
       in diamonds instead of in a helix-shaped trench.  So the path in (angle, y)
       is a triangle wave: it sweeps from -DELTA/2 to +DELTA/2 of arc over one
       LEG, then sweeps back.  Four cords, phased a quarter-turn apart, tile the
       circumference; two are always travelling in opposite directions, so they
       cross exactly at the reversal points, which is where a real wrap has its
       fold and its visible cord corner.

    2. THE CROSS-SECTION.  The ribbon used to be a zero-thickness strip.  Godot
       settled it: at 0.6 m -- inside the 0.3-1 m band PART I calls the highest
       bar -- the wrap read as BROKEN DASHES, a row of scratches, and the closer
       the camera the worse it got, because a flat strip viewed at a grazing
       angle collapses to a sub-pixel line and vanishes for a few samples and then
       reappears.  A cord is not a decal.  Each cord is now a rectangular prism
       (WIDTH across, THICK proud of the core) so it has a lit top face, a shaded
       flank and an end cap, and it cannot disappear at any angle.  The prism's
       inner face sits at ROOT, a fraction of a millimetre INSIDE the core, so the
       cord is genuinely wound onto the grip instead of floating above it.

    LEGS drops 15 -> 11 at the same time: 240 mm of grip over 15 crossings is
    16 mm per diamond, and a real tsuka-ito diamond is nearer 22-25 mm.  The old
    count was inherited from the helix version, where leg count was pitch.
    """
    verts, faces = [], []
    Y_TOP = GUARD_Y - 0.0235          # clear of the fuchi, which ends at -0.021
    Y_BOT = GRIP_END_Y + 0.0075       # clear of the kashira, which starts at -0.264
    CORDS = 4
    LEGS = 11
    SEG_PER_LEG = 6
    DELTA = math.radians(90.0)        # 4 cords x 90 deg = one full turn
    WIDTH = 0.0078                    # across the cord
    THICK = 0.0021                    # the cord's own gauge, proud of the core
    ROOT = -0.0004                    # inner face, sunk into the core

    for c in range(CORDS):
        phase0 = TAU * c / CORDS
        rings = []
        n = LEGS * SEG_PER_LEG
        for i in range(n + 1):
            u = i / float(n)
            y = lerp(Y_TOP, Y_BOT, u)
            ph = u * LEGS
            leg = int(math.floor(ph))
            frac = ph - leg
            sgn = 1.0 if (leg % 2 == 0) else -1.0
            # triangle wave: continuous across a leg boundary because the value
            # is +1/2 at the end of one leg and +1/2 at the start of the next
            # with the sign already flipped.
            ang = phase0 + sgn * (frac - 0.5) * DELTA
            rx, rz = grip_section(u)
            sin_a, cos_a = math.sin(ang), math.cos(ang)
            # Tangent of the path, so the prism's width runs ACROSS the cord.
            d_ang = sgn * DELTA * LEGS
            d_y = (Y_BOT - Y_TOP)
            cx = -sin_a * rx * d_ang
            cz = cos_a * rz * d_ang
            cl = math.sqrt(cx * cx + cz * cz + d_y * d_y) or 1.0
            cx, cy, cz = cx / cl, d_y / cl, cz / cl
            # A quad cross-section: (inner,outer) x (one side, other side).
            quad = []
            for (dr, dc) in ((ROOT, 1.0), (ROOT, -1.0), (THICK, -1.0), (THICK, 1.0)):
                half = WIDTH * 0.5 * dc
                quad.append(len(verts))
                verts.append(((rx + dr) * cos_a + cx * half,
                              y + cy * half,
                              (rz + dr) * sin_a + cz * half))
            rings.append(quad)
        faces.append(list(reversed(rings[0])))
        faces.append(list(rings[-1]))
        for i in range(len(rings) - 1):
            bridge_rings(verts, faces, rings[i], rings[i + 1], 4)

    ob = new_mesh("Grip_Wrap", verts, faces, mat_override or m["grip"])
    recalc_normals(ob)
    # Flat shading on the cord: an angle-limited smooth pass would round the
    # prism's corners and undo the whole point of giving it a section.
    shade(ob, 26.0)
    return ob


def build_menuki(m):
    """A small ornament on the grip -- the second and last place the sword is
    allowed an ancient motif."""
    verts, faces = [], []
    N = 12
    L = 0.0215
    rings = []
    steps = [(-1.0, 0.30), (-0.55, 0.80), (0.0, 1.0), (0.55, 0.80), (1.0, 0.30)]
    for (s, sc) in steps:
        y = -0.148 + s * L * 0.5
        pts = []
        for i in range(N):
            a = TAU * i / N
            k = 1.0 + 0.22 * math.sin(a * 2.0 + 0.4)
            rx, rz = grip_section(0.5)
            pts.append((math.cos(a) * 0.0105 * sc * k,
                        math.sin(a) * 0.0062 * sc * k))
        rings.append((y, pts))
    # place it on the +X flank of the grip and stand it proud
    rx, rz = grip_section(0.5)
    base = []
    for (y, pts) in rings:
        idx = []
        for (px, pz) in pts:
            idx.append(len(verts))
            verts.append((rx + 0.0012 + pz * 0.55, y, px * 0.85))
        base.append(idx)
    faces.append(list(reversed(base[0])))
    faces.append(list(base[-1]))
    for i in range(len(base) - 1):
        bridge_rings(verts, faces, base[i], base[i + 1], N)
    ob = new_mesh("Menuki", verts, faces, m["inlay"])
    recalc_normals(ob)
    return ob


# =============================================================================
#  assembly
# =============================================================================

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for c in (bpy.data.meshes, bpy.data.materials, bpy.data.objects):
        for d in list(c):
            c.remove(d)


def bake_to_godot_axes(parts):
    """Rotate the whole sword so the EXPORTED asset has its blade along +Y.

    WHY THIS EXISTS, AND WHY IT IS THE ASSET THAT MOVES RATHER THAN THE CODE.

    The authoring pose below is length along Blender +Y, edge-to-spine along X.
    The Blender glTF exporter maps (x, y, z)_blender -> (x, z, -y)_gltf, so that
    pose exports with the LONG AXIS ON Z and the tip toward -Z -- which is what
    both the shipping placeholder (AABB 0.1308 x 0.0440 x 1.0473, blade_tip at
    z = -0.910) and the previous three versions of this build actually did.

    But every consumer of the sword is written against +Y:

      * scenes/weapons/Sword_FP.tscn's contract said "blade runs along +Y";
      * combat/iaido_director.gd:_bore_pose() seated the sword by giving it
        `rotation = seat_euler`, i.e. the SCABBARD's own basis, whose +Y
        (combat/iaido_tuning.gd:621) is the bore -- "the direction the blade
        travels to go home".  That only puts the blade down the sheath if the
        blade runs along the sword's local +Y.  With the blade on -Z it seats
        the sword at ninety degrees to its own scabbard;
      * combat/iaido_scabbard_rig.gd declares the mirror contract: origin at the
        koiguchi mouth plane, +Y down the bore, -X the side the edge faces.

    So the scene comment was not wrong about the DESIGN, it was wrong about the
    FILE.  The file is what has to change: the combat side is the side with
    IaidoDirector in it (an ART must-not-touch file, see
    docs/ART_INTEGRATION_REQUESTS.md), and the +Y convention is the one the
    sheath maths, the saya rig and the scene header all already speak.

    A +90 degree rotation about X maps Blender +Y -> +Z, which the exporter then
    takes to +Y_gltf, exactly as required.  It leaves -X on -X (the edge stays
    on the edge side, which is what the saya's -X expects) and takes the
    thickness from +/-Z to -/+Y_blender, i.e. onto +/-Z_gltf.  The rotation is
    baked into the MESH DATA rather than left as a node transform, so the GLB
    carries no root rotation for a downstream tool to drop on the floor.

    Net effect, measured rather than asserted: long axis Y, tip toward +Y,
    edge toward -X, blade flat normal to Z.  Geometry, materials and tri count
    are untouched, so this is an orientation-only change and is verified by
    AABB, not by eye.
    """
    rot = Matrix.Rotation(math.radians(90.0), 4, "X")
    for p in parts:
        p.data.transform(rot)
        p.data.update()
        # The root is an Empty at the origin and the parts are parented with an
        # identity local transform, so rotating each mesh's data about (0,0,0)
        # rotates the whole sword about the grip origin -- which is the pivot
        # every anchor in Player.tscn is expressed against.
    print("AXES  baked +90 X: blade on +Y (tip +Y), edge on -X, flat normal to Z")


def main():
    argv = sys.argv
    out_blend = "F:/SEKAI/assets_source/weapons/prototypes/fp_sword_v4.blend"
    out_glb = "F:/SEKAI/assets/models/weapons/fp_sword_v4.glb"
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        if len(rest) >= 1:
            out_blend = rest[0]
        if len(rest) >= 2:
            out_glb = rest[1]

    clear_scene()
    m = build_materials()

    parts = []
    parts.append(build_blade(m))
    parts.append(build_tang(m))
    parts.append(build_habaki(m))
    parts.append(build_guard(m))
    parts += build_guard_motif(m)
    parts.append(build_grip(m))
    parts.append(build_collar(m, "Fuchi", GUARD_Y - 0.005, GUARD_Y - 0.021, 1.13, "fit"))
    # The kashira: max rim at 38 %, a nearly full-width cap face at 80 %, then a
    # 10 % chamfer into the end. Four rings, because three cannot describe a
    # flat cap with a rim and a chamfer at once.
    parts.append(build_collar(m, "Kashira", GRIP_END_Y + 0.004, KASHIRA_Y, 1.20, "fit",
                              [(0.0, 0.96), (0.38, 1.0), (0.80, 0.99), (1.0, 0.88)]))
    parts.append(build_wrap(m))
    parts.append(build_menuki(m))

    root = bpy.data.objects.new("FP_Sword_Root", None)
    bpy.context.scene.collection.objects.link(root)
    for p in parts:
        p.parent = root

    # Hard-surface parts get an angle limit so the shinogi and the guard rim
    # stay crisp while the long runs stay smooth.  Soft parts are fully smooth:
    # an angled limit on a 20-sided oval puts a visible facet line down the
    # grip, which is the other half of why the first pass read as machined.
    for p in parts:
        if p.name in ("Blade", "Habaki", "Guard", "Guard_Motif_Bar") or \
                p.name.startswith("Guard_Motif_"):
            shade(p, 33.0)
        else:
            shade(p, None)

    # Orientation LAST, after every builder has finished working in the pose
    # that is convenient to author in.  See bake_to_godot_axes for why.
    bake_to_godot_axes(parts)

    tris = 0
    for p in parts:
        me = p.data
        me.calc_loop_triangles()
        tris += len(me.loop_triangles)
    print("SWORD_PARTS %d  TRIS %d" % (len(parts), tris))
    for p in parts:
        p.data.calc_loop_triangles()
        bb = [Vector(c) for c in p.bound_box]
        mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
        mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
        print("  %-14s tris=%5d  x[%7.4f %7.4f] y[%7.4f %7.4f] z[%7.4f %7.4f]"
              % (p.name, len(p.data.loop_triangles), mn.x, mx.x, mn.y, mx.y, mn.z, mx.z))

    os.makedirs(os.path.dirname(out_blend), exist_ok=True)
    os.makedirs(os.path.dirname(out_glb), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=out_blend)

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=out_glb,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )
    print("SAVED  %s" % out_blend)
    print("SAVED  %s" % out_glb)


if __name__ == "__main__":
    main()
