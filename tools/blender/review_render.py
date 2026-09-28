"""SEKAI asset review rig -- 6-angle sheet + first-person pass.

    blender --background --factory-startup --python tools/blender/review_render.py -- \
        assets_source/weapons/prototypes/fp_sword_v4.blend .render/asset_review/sword_v4

WHY THIS EXISTS
===============
PART N asks for six angles per hero asset and PART R asks for V1 / V2 / FINAL
at the SAME camera.  Both of those are only worth anything if the camera is not
re-invented each time, because a new angle every round is how a bad shape hides
from its own review for three iterations.

Every render is written with `film_transparent`, so one pass yields two
deliverables for the price of one:
  * a colour plate composited over neutral grey, for judging form and material
  * an exact SILHOUETTE from the alpha channel, which is step 2 of the pipeline
    in §1 and the only honest test of a shape

LIGHT
=====
The rig recorded in the ART notes: SUN + world 0.18 @ 0.6 + key 2.4 / fill 0.8
/ rim 1.3.  That is the same rig every previous asset was judged under, so a
comparison against an older render is a comparison of the ASSET and not of the
lighting.

WHY THE BACKGROUND IS GREY AND NOT WHITE
========================================
The blade is steel at value ~0.74.  On a white plate it loses its silhouette
edge and every defect looks like a lighting artefact.  Mid-grey is deliberately
the hardest background to look good against, which is the point: it is closer to
the fog-lit Mistvale the sword will actually be carried through.
"""

import math
import os
import sys

import bpy
from mathutils import Vector, Matrix

BG = 0.20          # ground / world albedo, from the contact-sheet rig
KEY = 2.4
FILL = 0.8
RIM = 1.3

# The ratios above are the art direction and are deliberately unchanged.  The
# ABSOLUTE level is not: the first pass ran the key at 288 W placed 1.75 m from
# the origin, which put ~13.8 W/m^2 on the asset and rendered the grip -- a
# 0.05-albedo near-black -- as MID GREY.  Everything in the first review sheet
# was therefore a review of the exposure, and the two conclusions it invited
# ("the fittings look pale", "the blade is washed out") were both artefacts.
#
# 34 lands the grip near 0.29 sRGB and the blade near 0.72, which is where the
# materials actually sit, and it leaves the top of the range free so a blown
# highlight means an actual blown highlight.
LUX = 34.0


def parse_args():
    if "--" not in sys.argv:
        return None, None
    rest = sys.argv[sys.argv.index("--") + 1:]
    src = rest[0] if rest else "F:/SEKAI/assets_source/weapons/prototypes/fp_sword_v4.blend"
    out = rest[1] if len(rest) > 1 else "F:/SEKAI/.render/asset_review/sword"
    return src, out


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for c in (bpy.data.meshes, bpy.data.materials, bpy.data.objects,
              bpy.data.cameras, bpy.data.lights, bpy.data.worlds):
        for d in list(c):
            try:
                c.remove(d)
            except Exception:
                pass


def setup_world():
    w = bpy.data.worlds.new("ReviewWorld")
    bpy.context.scene.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    # A flat grey dome.  It is what the metal has to reflect, and it gives the
    # roughness channels something to shape -- with a black world, roughness
    # cannot be seen at all and every material looks identical.
    bg.inputs[0].default_value = (BG * 0.9, BG * 0.93, BG, 1.0)
    bg.inputs[1].default_value = 0.62
    return w


def area_light(name, loc, target, energy, size, colour):
    ld = bpy.data.lights.new(name, "AREA")
    ld.energy = energy
    ld.size = size
    ld.color = colour
    ob = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    d = (Vector(target) - Vector(loc)).normalized()
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return ob


def setup_lights(target, cam):
    """Three-point rig expressed in CAMERA SPACE, not in world space.

    WHY, AND WHAT IT COST TO LEARN.  The first version placed the key at a
    fixed world offset and the sheet came back with `01_side` -- the view the
    entire build is judged in -- showing a BLACK blade, while `02_flank` showed
    a white one.  Nothing was wrong with the asset: every light was on the +Z
    side and the `01_side` camera sits at -Z, so the surface facing the lens
    was lit by nothing at all.  On a turnaround, a world-space rig reviews the
    LIGHTING once per view and the ASSET not at all.

    Building the rig on the camera's own basis makes every plate lit the same
    way, so a difference between two views is a difference in the model.
    """
    t = Vector(target)
    m = cam.matrix_world
    right = Vector((m[0][0], m[1][0], m[2][0])).normalized()
    up = Vector((m[0][1], m[1][1], m[2][1])).normalized()
    back = Vector((m[0][2], m[1][2], m[2][2])).normalized()

    def at(side, lift, depth, dist):
        return t + (right * side + up * lift + back * depth).normalized() * dist

    # key: high and to the lens's left, just in front of the camera plane
    area_light("Key", at(-0.62, 0.66, 0.42, 1.85), target, KEY * LUX, 0.55,
               (1.0, 0.965, 0.905))
    # fill: low and to the lens's right
    area_light("Fill", at(0.78, -0.28, 0.52, 2.05), target, FILL * LUX, 0.85,
               (0.88, 0.925, 1.0))
    # rim: opposite the key, low, BEHIND the subject, to draw the silhouette
    area_light("Rim", at(0.30, 0.42, -0.86, 2.10), target, RIM * LUX, 0.48,
               (0.98, 0.985, 1.0))
    # a dim sun so there is one hard-ish directional read on the bevels
    sd = bpy.data.lights.new("Sun", "SUN")
    sd.energy = 1.35
    sd.angle = math.radians(6.0)
    sd.color = (1.0, 0.98, 0.945)
    so = bpy.data.objects.new("Sun", sd)
    bpy.context.scene.collection.objects.link(so)
    so.location = at(-0.5, 0.75, 0.45, 3.0)
    so.rotation_euler = (t - so.location).normalized() \
        .to_track_quat("-Z", "Y").to_euler()


def look_at(ob, loc, target, up_world):
    """Right-handed camera basis.

    Built by hand rather than with `to_track_quat`, because the sword's long
    axis is world Y and `to_track_quat` always rolls the up vector toward world
    Z -- which lays a katana on its side in every frame.  The whole reason the
    sheet is worth looking at is that the blade runs UP the page.
    """
    loc = Vector(loc)
    target = Vector(target)
    f = (target - loc)
    if f.length < 1e-9:
        f = Vector((0.0, 0.0, -1.0))
    f = f.normalized()
    z = -f
    u = Vector(up_world).normalized()
    x = u.cross(z)
    if x.length < 1e-6:
        u = Vector((0.0, 0.0, 1.0))
        x = u.cross(z)
    x = x.normalized()
    y = z.cross(x).normalized()
    m = Matrix(((x.x, y.x, z.x, loc.x),
                (x.y, y.y, z.y, loc.y),
                (x.z, y.z, z.z, loc.z),
                (0.0, 0.0, 0.0, 1.0)))
    ob.matrix_world = m


def make_camera(name, loc, target, up_world, ortho=None, lens=50.0):
    cd = bpy.data.cameras.new(name)
    if ortho is not None:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    else:
        cd.lens = lens
    ob = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(ob)
    look_at(ob, loc, target, up_world)
    return ob


# The views.  `ortho` is the vertical span in metres where the shot is a
# technical orthographic plate; `None` means a perspective shot.
#
#   side   -- the classic blade photograph.  Looking down the thickness axis,
#             so the sori (curvature), the distal taper and the kissaki are all
#             on the silhouette.  THE view this whole build is judged in.
#   flat   -- the other flank, because the guard is deliberately asymmetric and
#             one flank hides half of that.
#   edge   -- down the edge, which is where a blade with no profile is exposed
#             instantly: a slab is a long thin rectangle, a real blade is a
#             wedge that narrows.
#   front  -- the guard face, camera behind the pommel.
#   three_q-- the hero angle.
#   fp     -- the first-person framing (PART I): eye at the grip, looking along
#             the blade, which is the distance the player actually sees it at.
VIEWS = [
    ("01_side",   "ortho", (0.0, 0.10, -2.20), (0.0, 0.10, 0.0), (0, 1, 0), 1.30),
    ("02_flank",  "ortho", (0.0, 0.10, 2.20), (0.0, 0.10, 0.0), (0, 1, 0), 1.30),
    ("03_edge",   "ortho", (-2.20, 0.10, 0.0), (0.0, 0.10, 0.0), (0, 1, 0), 1.30),
    ("04_spine",  "ortho", (2.20, 0.10, 0.0), (0.0, 0.10, 0.0), (0, 1, 0), 1.30),
    # 05_guard looks from the BLADE side (+Y).  The first version looked from
    # -Y, which turned out to be a shot straight down the axis at the pommel
    # cap -- the guard was in frame but behind the kashira, and the review sheet
    # labelled a picture of a pommel as "guard".  From +Y the guard face fills
    # the frame with the habaki in the middle of it, which is the relationship
    # that actually has to be right for the scabbard.
    ("05_guard",  "ortho", (0.030, 1.60, 0.020), (0.0, 0.0, 0.0), (0, 0, 1), 0.17),
    ("06_three_q", "persp", (-0.62, -0.72, 0.48), (0.0, 0.14, 0.0), (0, 1, 0), None),
]

# Close-ups that PART N and §7 need: the guard motif, the sheath-mouth region
# of the blade base (habaki), and the grip.
DETAILS = [
    ("D1_guard_motif", (0.055, 0.62, 0.045), (0.0, 0.0, 0.0), (0, 0, 1), 0.125),
    ("D2_habaki",      (0.100, 0.36, 0.030), (0.0, 0.048, 0.0), (0, 0, 1), 0.105),
    ("D3_grip",        (0.110, 0.30, -0.010), (0.0, -0.145, 0.0), (0, 0, 1), 0.235),
]


def setup_render(w, h, samples=64):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = w
    sc.render.resolution_y = h
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    # Standard, with the rig's level set correctly, is the honest transform: it
    # shows the material as authored.  AgX would roll the highlights off and
    # simultaneously desaturate the one warm metal on the asset, which is the
    # opposite of what a material pass needs to see.
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    try:
        sc.eevee.taa_render_samples = samples
    except Exception:
        pass
    try:
        sc.eevee.use_raytracing = True
    except Exception:
        pass


def purge_lights():
    for ob in list(bpy.data.objects):
        if ob.type in ("LIGHT",):
            bpy.data.objects.remove(ob, do_unlink=True)


def shoot(cam, path, target):
    sc = bpy.context.scene
    purge_lights()
    setup_lights(target, cam)
    sc.camera = cam
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    src, out = parse_args()
    if src is None:
        print("REVIEW: no -- args; nothing to do")
        return
    clear_scene()
    setup_world()

    bpy.ops.wm.open_mainfile(filepath=src)
    os.makedirs(out, exist_ok=True)
    touched = []

    for (name, kind, loc, tgt, up, sc_) in VIEWS:
        setup_render(760, 1020)
        cam = make_camera(name, loc, tgt, up,
                          ortho=(sc_ if kind == "ortho" else None),
                          lens=62.0)
        shoot(cam, os.path.join(out, name + ".png"), tgt)
        touched.append(name)

    for (name, loc, tgt, up, sc_) in DETAILS:
        setup_render(900, 900, samples=96)
        cam = make_camera(name, loc, tgt, up, ortho=sc_)
        shoot(cam, os.path.join(out, name + ".png"), tgt)
        touched.append(name)

    # PART I: the first-person pass.  Eye 0.6 m behind and above the grip,
    # offset to the player's left so the weapon sits low-right in frame the way
    # a right hand holds it -- which is the distance and the angle the whole
    # asset is really being judged at, and the one §I calls the highest bar.
    setup_render(1280, 720, samples=96)
    cam = make_camera("FP", (-0.255, -0.585, 0.255), (0.020, 0.340, -0.010),
                      (0, 0, 1), lens=58.0)
    shoot(cam, os.path.join(out, "FP_camera.png"), (0.02, 0.10, 0.0))
    touched.append("FP_camera")

    print("REVIEW_DONE %s  views=%d" % (out, len(touched)))


if __name__ == "__main__":
    main()
