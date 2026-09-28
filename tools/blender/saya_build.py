"""SEKAI W02 -- the saya (scabbard).  DIRECT hand-modelled asset, no Chat2Blender.

    cmd //c "G:\\blender.exe --background --factory-startup \
             --python F:\\SEKAI\\tools\\blender\\saya_build.py -- \
             F:/SEKAI/assets_source/weapons/final/fp_saya_v1.blend \
             F:/SEKAI/assets/models/weapons/fp_saya.glb"

=============================================================================
THE FRAME IS NOT A DESIGN CHOICE, IT IS A CONTRACT
=============================================================================
`godot/scripts/combat/iaido_scabbard_rig.gd` states it, and
`godot/scripts/combat/iaido_director.gd` depends on it:

    origin    the centre of the koiguchi mouth plane
    +Y        down the bore, toward the kojiri -- the direction the blade travels
    -X        the side the cutting edge faces
    +Z        the outward-facing side of the body (the kurikata side)

Blender's glTF exporter maps (x, y, z)_blender -> (x, z, -y)_gltf, so to land
that contract in the GLB the mesh has to be AUTHORED as:

    +Z_blender  = the bore (mouth -> kojiri)   -> +Y_gltf
    -X_blender  = the edge side                -> -X_gltf
    -Y_blender  = the kurikata side            -> +Z_gltf

Rather than write every coordinate in that rotated frame -- which is how a
sign gets flipped three months later -- the whole build is written in the
READABLE frame (a = edge-to-spine, b = bore distance, c = kurikata axis) and
`emit()` does the one mapping at the end.  One line to check, one line to get
wrong.

WHY THE FITTINGS AND THE BORE ARE SIZED OFF THE SWORD AND NOT OFF THE BRIEF
The stand-in this replaces was built to `mouth_bore = (0.092, 0.055)` -- a 92 x
55 mm opening.  The real blade that has to go in it is 36.5 mm edge-to-spine and
8.0 mm thick, and its habaki is 40.0 x 10.2 mm.  A 92 mm mouth around a 40 mm
habaki is a 26 mm gap on each side: the blade would visibly rattle, and PART A
§7 is explicit that the sword has to really fit.  So every dimension here is
DERIVED from the measured sword (see `godot/scripts/weapons/sword_class.gd`,
which is where those numbers live so that the next sword does not have to
rediscover them):

    mouth bore   = habaki + 2 x FIT_CLEAR      = 43.5 x 13.0 mm
    wall         = 3.2 mm                      -> 49.9 x 19.4 mm outside
    bore length  = (tip y - tsuba face y) + TIP_CLEAR = 0.768 + 0.022 = 0.790 m
    body length  = 0.803 m to the outside of the kojiri

The body is 0.803 m where the stand-in was 1.02: the stand-in was sized for a
longer blade, and a saya that is 200 mm deeper than its sword is 200 mm of tube
that exists to be looked at by nobody.  The tuning comment wants the body to
leave frame early, so the shorter tube is also the better read.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

TAU = math.pi * 2.0

OUT_BLEND = "F:/SEKAI/assets_source/weapons/final/fp_saya_v1.blend"
OUT_GLB = "F:/SEKAI/assets/models/weapons/fp_saya.glb"

# =============================================================================
#  THE NUMBERS -- every one of them derived from the sword, none of them taste
# =============================================================================

# The habaki is the largest thing that has to pass the mouth.  Measured from
# tools/blender/sword_build.py's own bound box: x +-0.0200, z +-0.0051.
HABAKI_W = 0.0400
HABAKI_T = 0.0102
# Clearance per side.  1.75 mm is a fit you can feel but not see: at 0.6 m a
# 1.75 mm gap is about one pixel, and the koiguchi still reads as a hole the
# blade disappears into rather than a bucket the blade is dropped into.
FIT_CLEAR = 0.00175
WALL = 0.0032

MOUTH_BORE_W = HABAKI_W + 2.0 * FIT_CLEAR       # 0.04350
MOUTH_BORE_T = HABAKI_T + 2.0 * FIT_CLEAR       # 0.01370
MOUTH_OUT_W = MOUTH_BORE_W + 2.0 * WALL         # 0.04990
MOUTH_OUT_T = MOUTH_BORE_T + 2.0 * WALL         # 0.02010

# The blade tip sits at sword y = +0.765 and the tsuba's outer face at -0.003,
# so the tip is 0.768 m down the bore when fully seated.  TIP_CLEAR is real
# clearance, not slack: a saya whose tip touches its kojiri is a saya that
# eventually wears a hole through it.
TIP_INSIDE = 0.768
TIP_CLEAR = 0.022
BORE_LEN = TIP_INSIDE + TIP_CLEAR               # 0.790
KOJIRI_EXT = 0.013
BODY_LEN = BORE_LEN + KOJIRI_EXT                # 0.803

# Sori.  The same parabola the blade uses, expressed in bore distance:
# `sx = SORI * (y / TIP_Y)^2` with `y = b - 0.003`.  Reusing the sword's
# constants is the point -- if the blade's curve changes, this changes with it.
SORI = 0.018
SWORD_TIP_Y = 0.765
TSUBA_FACE_Y = -0.003

TAPER = 0.855            # bore/outer scale at the kojiri
COLLAR_LEN = 0.026       # the koiguchi band
COLLAR_SWELL = 1.150
KOJIRI_LEN = 0.038
KURIKATA_B = 0.118       # how far down the bore the cord knob sits
RINGS = 24               # points round the section
BODY_SEG = 22            # stations along the outer body
BORE_SEG = 10


def sori_at(b):
    """Lateral offset toward the spine, in metres, at bore distance b."""
    y = b + TSUBA_FACE_Y
    return SORI * (max(y, 0.0) / SWORD_TIP_Y) ** 2


def body_scale(b):
    """Section scale along the body.

    Not a straight taper.  A saya is fractionally proud for the first 30 mm
    behind the mouth -- that bulge is what the koiguchi band clamps onto -- then
    it settles and runs a long, almost imperceptible taper to the kojiri.  A
    linear taper reads as a cone, which is a pipe fitting, not a scabbard.
    """
    t = min(max(b / BODY_LEN, 0.0), 1.0)
    if t < 0.045:
        return 1.0 + 0.012 * (t / 0.045)
    settle = 1.012
    k = (t - 0.045) / 0.955
    return settle + (TAPER - settle) * (k ** 0.82)


def section(a_scale, c_scale, b, n=RINGS):
    """One station, in the READABLE frame: (a = edge->spine, b = bore, c = knob axis).

    The profile is an oval with the spine side very slightly flattened.  A pure
    ellipse on a lacquered saya reads as a plastic tube; 4 % of flattening on
    the +a side is enough to catch a highlight line down the back and make it
    read as a shaped wooden shell.
    """
    sx = sori_at(b)
    pts = []
    for i in range(n):
        ang = TAU * i / n
        ca, cc = math.cos(ang), math.sin(ang)
        # spine side is +a (= +X).  Flatten only that half.
        flat = 1.0 - 0.040 * max(ca, 0.0)
        pts.append((sx + ca * a_scale * flat, cc * c_scale))
    return pts


def emit(a, b, c):
    """The one place the authoring frame becomes the contract frame.

        +Z_blender = b (bore)      -> +Y_gltf   (down the bore)
        -X_blender = -a            -> -X_gltf   (edge side)
        -Y_blender = -c            -> +Z_gltf   (kurikata side)
    """
    return (a, -c, b)


def new_mesh(name, verts, faces, mat):
    me = bpy.data.meshes.new(name)
    me.from_pydata([Vector(v) for v in verts], [], faces)
    me.validate(verbose=False)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(mat)
    return ob


def recalc_normals(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def shade(ob, angle=None):
    for p in ob.data.polygons:
        p.use_smooth = True
    if angle is not None:
        mod = ob.modifiers.new("smooth", "EDGE_SPLIT")
        mod.split_angle = math.radians(angle)
    ob.data.update()


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
        # Deep lacquer over wood.  §T: old but MAINTAINED.  There is no chip,
        # no crack and no scratch on this, on purpose -- the wear a saya earns
        # is a polish along the mouth lip where the habaki crosses it and a
        # dulling on the body where a hand has carried it, and both of those
        # are a second pass.  Uniform "dirty" is the failure mode §K names.
        "lacquer": mat("MAT_Saya_Lacquer", (0.082, 0.070, 0.068), 0.05, 0.215),
        # The SAME NAME the sword uses.  A saya whose ironwork is a different
        # iron from its sword's is two objects, not one set.
        "fit": mat("MAT_Sword_Fittings", (0.086, 0.079, 0.070), 0.30, 0.580),
        "cord": mat("MAT_Sword_Grip", (0.052, 0.055, 0.066), 0.0, 0.735),
        # The inside of the bore.  Near-black and rough: it exists to not be
        # seen, and anything with a specular response in there turns the mouth
        # into a lit ring, which reads as a hole in a game asset.
        "bore": mat("MAT_Saya_Bore", (0.012, 0.012, 0.014), 0.0, 0.86),
    }


# =============================================================================
#  the body -- outer shell, inner bore, and the mouth rim that joins them
# =============================================================================

def build_shell(m):
    """A CLOSED tube, and that closure is load-bearing.

    Scene comment on CeremonyScabbard: "the part of the blade that is inside is
    hidden by the scabbard's own walls, not by a `visible = false`".  For that
    to be true there has to be an inner wall, not just an outer one.  A shell
    with no inner surface is a hole you can see through the back of.
    """
    verts, faces = [], []

    # --- outer ---------------------------------------------------------------
    outer = []
    for k in range(BODY_SEG + 1):
        t = k / float(BODY_SEG)
        b = t * BODY_LEN
        sc = body_scale(b)
        # round the very end off into the kojiri instead of cutting it flat
        end = 1.0
        if b > BORE_LEN:
            e = (b - BORE_LEN) / KOJIRI_EXT
            end = math.sqrt(max(0.0, 1.0 - e * e)) * 0.55 + 0.45
        pts = section(MOUTH_OUT_W * 0.5 * sc * end, MOUTH_OUT_T * 0.5 * sc * end, b)
        outer.append(_ring(verts, pts, b))

    for i in range(len(outer) - 1):
        _bridge(faces, outer[i], outer[i + 1], RINGS)
    # cap the extreme end (a tiny n-gon; the rounding above has already taken
    # the ring down to 45 % of full size, so this is a blunt point, not a disc)
    faces.append(list(outer[-1]))

    # --- inner bore ----------------------------------------------------------
    inner = []
    for k in range(BORE_SEG + 1):
        t = k / float(BORE_SEG)
        b = t * BORE_LEN
        sc = body_scale(b) * 0.999
        pts = section(MOUTH_BORE_W * 0.5 * sc, MOUTH_BORE_T * 0.5 * sc, b)
        inner.append(_ring(verts, pts, b))

    for i in range(len(inner) - 1):
        # reversed winding: this surface faces INWARD
        _bridge(faces, inner[i + 1], inner[i], RINGS)
    faces.append(list(reversed(inner[-1])))      # floor of the bore

    # --- the mouth rim: outer ring 0 -> inner ring 0 -------------------------
    # 3.2 mm of real wall thickness, visible as a ring when the blade is out.
    _bridge(faces, outer[0], inner[0], RINGS)

    ob = new_mesh("Saya", verts, faces, m["lacquer"])
    recalc_normals(ob)
    # The body is a long smooth run; the edge-split only has to keep the mouth
    # rim crisp, and a tight angle would facet the oval.
    shade(ob, 46.0)
    return ob


def build_bore_liner(m):
    """The bore's own material, as a separate thin shell just inside the wall.

    Separate object because a glTF primitive carries one material, and the bore
    is the one surface on this asset that has to be matte black.  It is 0.1 mm
    inside the structural bore, so it never z-fights with it.
    """
    verts, faces = [], []
    rings = []
    for k in range(BORE_SEG + 1):
        t = k / float(BORE_SEG)
        b = t * BORE_LEN
        sc = body_scale(b) * 0.9955
        pts = section(MOUTH_BORE_W * 0.5 * sc, MOUTH_BORE_T * 0.5 * sc, b)
        rings.append(_ring(verts, pts, b))
    for i in range(len(rings) - 1):
        _bridge(faces, rings[i + 1], rings[i], RINGS)
    faces.append(list(reversed(rings[-1])))
    ob = new_mesh("Saya_Bore_Liner", verts, faces, m["bore"])
    recalc_normals(ob)
    shade(ob, None)
    return ob


def build_fittings(m):
    """Koiguchi band, kojiri cap, kurikata knob, and the cord through it.

    §7 lists exactly these: sheath mouth / body / reinforced tip / mounting
    detail / subtle wrap / cord.  Four of the six are metalwork and they are on
    this one object so the whole fitting set is one material and one silhouette
    decision.
    """
    verts, faces = [], []

    def band(b0, b1, swell, steps=4):
        rings = []
        for k in range(steps + 1):
            t = k / float(steps)
            b = b0 + (b1 - b0) * t
            # a shallow barrel: proud in the middle so the band has an edge at
            # both ends to catch light, rather than being a straight sleeve
            s = 1.0 + 0.42 * (swell - 1.0) * (1.0 - abs(2.0 * t - 1.0) ** 1.6)
            sc = body_scale(b)
            pts = section(MOUTH_OUT_W * 0.5 * sc * s, MOUTH_OUT_T * 0.5 * sc * s, b)
            rings.append(_ring(verts, pts, b))
        for i in range(len(rings) - 1):
            _bridge(faces, rings[i], rings[i + 1], RINGS)
        faces.append(list(reversed(rings[0])))
        faces.append(list(rings[-1]))

    band(0.0, COLLAR_LEN, COLLAR_SWELL)
    band(BODY_LEN - KOJIRI_LEN, BODY_LEN - 0.0015, 1.115, 5)

    # --- kurikata: the mounting knob the sageo passes through -----------------
    # On the +c side (the saya's +Z_gltf).  A rounded wedge with a real hole
    # would need a boolean; the honest cheaper answer is a knob with a cord
    # WRAPPED round its base, which is what the cord looks like from any
    # distance the asset is ever seen at, and what the cord is FOR.
    kb = KURIKATA_B
    kn = 10

    def knob_ring(dz, w, h, off):
        ring = []
        ay = body_scale(kb) * MOUTH_OUT_T * 0.5 + off
        for i in range(kn):
            ang = TAU * i / kn
            ca, cc = math.cos(ang), math.sin(ang)
            ring.append(len(verts))
            verts.append(emit(ca * w * 0.5, kb + dz, ay + h * 0.5))
        return ring

    rings = [knob_ring(*r) for r in ((0.0, 0.0110, 0.0110, 0.0),
                                     (0.0045, 0.0136, 0.0150, 0.0024),
                                     (0.0125, 0.0126, 0.0136, 0.0030),
                                     (0.0195, 0.0080, 0.0090, 0.0016),
                                     (0.0230, 0.0026, 0.0030, 0.0))]
    for i in range(len(rings) - 1):
        _bridge(faces, rings[i], rings[i + 1], kn)
    faces.append(list(reversed(rings[0])))
    faces.append(list(rings[-1]))

    ob = new_mesh("Saya_Fittings", verts, faces, m["fit"])
    recalc_normals(ob)
    shade(ob, 34.0)
    return ob


def build_cord(m):
    """A short wrap round the kurikata's base.  NOT a hanging sageo.

    A 0.2 m sageo tail leaving the mouth region is the single most likely part
    of this asset to pass through the player's thigh during the draw and the
    final insertion -- §8 asks for draw clearance specifically.  A cord that
    dresses the knob and stops is the part that is actually seen at hip, and it
    is a pass that can be extended later with a real hanging tail once the hip
    motion is verified against it.
    """
    verts, faces = [], []
    kb = KURIKATA_B
    turns = 3
    steps = turns * 8
    TUBE = 8
    prev = None
    for k in range(steps + 1):
        t = k / float(steps)
        b = kb - 0.0075 + 0.0145 * t
        ang = TAU * turns * t
        base_a = body_scale(b) * MOUTH_OUT_T * 0.5 + 0.0026
        # the cord rides round the knob, so its centre follows the knob's axis
        ca, cc = math.cos(ang), math.sin(ang)
        cx = ca * 0.0072
        cy = base_a + cc * 0.0072
        # cross-section of the cord itself
        pa, pc = -cc, ca                    # perpendicular, in the (a, c) plane
        ring = []
        for i in range(TUBE):
            g = TAU * i / TUBE
            gc, gs = math.cos(g), math.sin(g)
            ring.append(len(verts))
            verts.append(emit(cx + pa * 0.0015 * gc, b + 0.0015 * gs,
                              cy + pc * 0.0015 * gc))
        if prev is not None:
            _bridge(faces, prev, ring, TUBE)
        prev = ring
    ob = new_mesh("Saya_Cord", verts, faces, m["cord"])
    recalc_normals(ob)
    shade(ob, None)
    return ob


# =============================================================================
#  ring helpers, written in the READABLE frame and emitted through emit()
# =============================================================================

def _ring(verts, pts, b):
    ring = []
    for (a, c) in pts:
        ring.append(len(verts))
        verts.append(emit(a, b, c))
    return ring


def _bridge(faces, ring_a, ring_b, count, closed=True):
    span = count if closed else count - 1
    for i in range(span):
        j = (i + 1) % count
        faces.append([ring_a[i], ring_a[j], ring_b[j], ring_b[i]])


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for c in (bpy.data.meshes, bpy.data.materials, bpy.data.objects):
        for d in list(c):
            c.remove(d)


def main():
    argv = sys.argv
    out_blend, out_glb = OUT_BLEND, OUT_GLB
    if "--" in argv:
        rest = argv[argv.index("--") + 1:]
        if len(rest) >= 1:
            out_blend = rest[0]
        if len(rest) >= 2:
            out_glb = rest[1]

    clear_scene()
    m = build_materials()

    parts = [
        build_shell(m),
        build_bore_liner(m),
        build_fittings(m),
        build_cord(m),
    ]

    root = bpy.data.objects.new("FP_Saya_Root", None)
    bpy.context.scene.collection.objects.link(root)
    for p in parts:
        p.parent = root

    tris = 0
    for p in parts:
        p.data.calc_loop_triangles()
        tris += len(p.data.loop_triangles)
    print("SAYA_PARTS %d  TRIS %d" % (len(parts), tris))

    # MEASURED, per part, in BOTH frames. These are the numbers
    # sword_class.gd is filled in from, so they are printed rather than typed
    # into a document by hand -- and printing the gltf row as well means a
    # flipped sign in emit() shows up here instead of in Godot.
    for p in parts:
        p.data.calc_loop_triangles()
        bb = [Vector(c) for c in p.bound_box]
        mn = [min(v[i] for v in bb) for i in range(3)]
        mx = [max(v[i] for v in bb) for i in range(3)]
        print("  %-18s tris=%5d  blender x[%7.4f %7.4f] y[%7.4f %7.4f] z[%7.4f %7.4f]"
              % (p.name, len(p.data.loop_triangles), mn[0], mx[0], mn[1], mx[1], mn[2], mx[2]))
        print("  %-18s        -> gltf  X[%7.4f %7.4f]  Y[%7.4f %7.4f]  Z[%7.4f %7.4f]"
              % ("", mn[0], mx[0], mn[2], mx[2], -mx[1], -mn[1]))

    print("SAYA   mouth bore %.4f x %.4f  outer %.4f x %.4f"
          % (MOUTH_BORE_W, MOUTH_BORE_T, MOUTH_OUT_W, MOUTH_OUT_T))
    print("SAYA   bore_len %.4f  body_len %.4f  taper %.3f"
          % (BORE_LEN, BODY_LEN, TAPER))
    print("SAYA   contract frame: origin = koiguchi mouth plane, +Y = bore, -X = edge, +Z = kurikata")

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
