"""W02 ACCEPTANCE -- does the sword actually go into the saya?

    cmd //c "G:\\blender.exe --background --factory-startup \
             --python F:\\SEKAI\\tools\\blender\\saya_fit_render.py -- \
             F:/SEKAI/assets/models/weapons/fp_sword_v8.glb \
             F:/SEKAI/assets/models/weapons/fp_saya.glb \
             F:/SEKAI/.render/asset_review/saya_fit"

PART A §7: "the sword must really fit, no clipping", and §8: "如果模型静态漂亮
但拔刀穿模，不算完成".  A scabbard photographed on its own proves nothing, so this
tool puts the two real GLBs together and asks the only question that matters.

THE SEATED POSE IS A PURE TRANSLATION, AND THAT IS THE WHOLE POINT OF THE AXIS
WORK.  Two conventions had to agree, and they now do:

    sword   origin = grip centre,         +Y = tip direction, -X = edge
    saya    origin = koiguchi mouth plane, +Y = bore,         -X = edge
                                              (iaido_scabbard_rig.gd)

Identical frames mean "fully seated" is not a rotation hunt.  The tsuba's
mouth-side face is at sword y = +0.003 (measured off the sword's own bound box
below, not typed in), so seated is the sword origin moved -0.003 along the bore:

    guard_setback = 0.003     iaido_tuning.gd currently has 0.045
    blade_reach   = 0.762     iaido_tuning.gd currently has 0.95

Those are exactly the two numbers the sword swap moves, and this tool DERIVES
them and prints them rather than asserting them.

RENDERS THREE THINGS, and the middle one is the one that decides the asset:

    fit_whole    the assembly, so the proportion of saya to sword is visible
    fit_mouth    the last ~80 mm at the koiguchi -- THE shot, because the Iaido
                 close-ups happen in the last 5-10 cm
    fit_section  a real lengthwise BISECT of BOTH meshes, so the blade inside
                 the bore is a section drawing rather than a transparency trick
"""

import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT_DEFAULT = "F:/SEKAI/.render/asset_review/saya_fit"
LUX = 58.0      # this asset is deep lacquer at 0.046 albedo; the review rig's 34 buries it


def parse_args():
    if "--" not in sys.argv:
        return None, None, OUT_DEFAULT
    rest = sys.argv[sys.argv.index("--") + 1:]
    sword = rest[0] if len(rest) > 0 else None
    saya = rest[1] if len(rest) > 1 else None
    out = rest[2] if len(rest) > 2 else OUT_DEFAULT
    return sword, saya, out


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for c in (bpy.data.meshes, bpy.data.materials, bpy.data.objects):
        for d in list(c):
            c.remove(d)


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    return new, roots


def bounds(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH" or o.hide_render:
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for i in range(3):
                mn[i] = min(mn[i], w[i])
                mx[i] = max(mx[i], w[i])
    return mn, mx


def setup_world():
    scene = bpy.context.scene
    world = bpy.data.worlds.new("FitWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    # This asset is DEEP LACQUER: albedo 0.046.  Under the review rig's exposure
    # and Filmic it rendered as a black silhouette against a black field and the
    # fit was unreadable -- a measurement tool that cannot be read is not a
    # measurement tool.  A lighter world plus Standard (rather than Filmic)
    # keeps the values predictable, which is what a FIT CHECK wants; the pretty
    # pass is review_render.py's job.
    bg.inputs[0].default_value = (0.300, 0.320, 0.360, 1.0)
    bg.inputs[1].default_value = 1.55
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"


def make_camera(name, loc, target, lens=62.0, up=(0.0, 0.0, 1.0)):
    cd = bpy.data.cameras.new(name)
    cd.lens = lens
    cam = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(cam)
    loc = Vector(loc)
    d = (Vector(target) - loc).normalized()
    up = Vector(up).normalized()
    if abs(d.dot(up)) > 0.995:
        up = Vector((0, 1, 0))
    right = d.cross(up).normalized()
    real_up = right.cross(d).normalized()
    cam.matrix_world = Matrix((
        (right.x, real_up.x, -d.x, loc.x),
        (right.y, real_up.y, -d.y, loc.y),
        (right.z, real_up.z, -d.z, loc.z),
        (0.0, 0.0, 0.0, 1.0),
    ))
    return cam


def setup_lights(target, cam):
    """Rig built on the CAMERA's basis.  A world-space rig made 01_side render a
    black blade while 02_flank rendered a white one -- see review_render.py."""
    for o in list(bpy.data.objects):
        if o.type == "LIGHT":
            bpy.data.objects.remove(o, do_unlink=True)
    t = Vector(target)
    fwd = (t - cam.location).normalized()
    right = fwd.cross(Vector((0, 0, 1))).normalized()
    up = right.cross(fwd).normalized()
    for (nm, a, b, c, power) in (("key", 0.62, 0.72, 0.62, 1.0),
                                 ("fill", -0.85, 0.30, 0.30, 0.34),
                                 ("rim", -0.35, 0.55, -0.80, 0.55)):
        d = (right * a + up * b + fwd * c).normalized()
        ld = bpy.data.lights.new(nm, "AREA")
        ld.energy = LUX * power
        ld.size = 1.1
        lo = bpy.data.objects.new(nm, ld)
        bpy.context.scene.collection.objects.link(lo)
        lo.location = t - d * 1.9
        lo.rotation_mode = "QUATERNION"
        lo.rotation_quaternion = (-d).to_track_quat("-Z", "Y")


def shoot(cam, path, target, w=1200, h=760):
    scene = bpy.context.scene
    scene.camera = cam
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    setup_lights(target, cam)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("SHOT %s" % path)


def bisect_meshes(objs, plane_no=(1.0, 0.0, 0.0)):
    """Cut every mesh on the plane and drop the far half.

    Cutting BOTH the saya and the sword is the point: a section of the saya
    alone still has the blade's near half in front of it and shows nothing.
    """
    for o in objs:
        if o.type != "MESH":
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        bmesh.ops.bisect_plane(
            bm, geom=geom, dist=0.00001,
            plane_co=(0.0, 0.0, 0.0), plane_no=plane_no,
            clear_outer=True)
        bm.to_mesh(o.data)
        bm.free()
        o.data.update()


def main():
    sword_path, saya_path, out = parse_args()
    if sword_path is None or saya_path is None:
        print("FIT: need <sword.glb> <saya.glb> [out_dir]")
        return
    clear_scene()
    setup_world()
    os.makedirs(out, exist_ok=True)

    saya_objs, _ = import_glb(saya_path)
    sword_objs, sword_roots = import_glb(sword_path)
    if not sword_roots:
        print("FIT: no root object in the sword GLB")
        return
    sword_root = sword_roots[0]

    # --- the seated offset, MEASURED --------------------------------------
    # The glTF importer puts Y-up into Blender Z-up, so after import BOTH assets
    # run along Blender +Z and the bore is +Z.  Everything below is in that frame.
    guard = [o for o in sword_objs if o.type == "MESH" and o.name.startswith("Guard")]
    if not guard:
        print("FIT: no Guard object in the sword GLB -- cannot derive the seated pose")
        return
    g_mn, g_mx = bounds(guard)
    mouth_face = g_mx.z                     # the tsuba face that meets the mouth
    s_mn, s_mx = bounds(sword_objs)
    tip_z = s_mx.z

    print("FIT: sword blender-frame bounds  z[%.4f .. %.4f]" % (s_mn.z, s_mx.z))
    print("FIT: tsuba mouth-side face z=%.4f  -> guard_setback = %.4f" % (mouth_face, mouth_face))
    print("FIT: blade_reach = tip - tsuba face = %.4f - %.4f = %.4f"
          % (tip_z, mouth_face, tip_z - mouth_face))
    print("FIT: iaido_tuning.gd ships guard_setback=0.045  blade_reach=0.95")

    sword_root.location = sword_root.location + Vector((0.0, 0.0, -mouth_face))
    bpy.context.view_layer.update()

    a_mn, a_mx = bounds([o for o in bpy.data.objects if o.type == "MESH"])
    print("FIT: assembled bounds  z[%.4f .. %.4f]  (bore end at z=%.4f -- so %.4f m of room past the tip)"
          % (a_mn.z, a_mx.z, a_mx.z, a_mx.z - tip_z))
    centre = (a_mn + a_mx) * 0.5

    # --- 1. whole assembly.  up=(1,0,0) so a 1.1 m object runs ACROSS the
    # frame instead of down it -- a sword photographed vertically is 1/4 the
    # pixels for the same camera.
    cam = make_camera("whole", (centre.x - 1.55, centre.y - 0.70, centre.z + 0.05),
                      (centre.x, centre.y, centre.z), lens=50.0, up=(1.0, 0.0, 0.0))
    shoot(cam, os.path.join(out, "fit_whole.png"), (centre.x, centre.y, centre.z))

    # --- 2. THE MOUTH.  The bore runs +z, so the MOUTH FACES -z and the camera
    # has to be on that side.  The first pass put it at +z, i.e. inside the
    # saya's own wall, and photographed the blade leaving a hole it could not
    # see.  Iaido's close-ups happen in the last 5-10 cm, so this is the shot.
    cam = make_camera("mouth", (-0.235, -0.150, -0.165), (0.0, 0.0, 0.034),
                      lens=88.0, up=(0.0, 0.0, 1.0))
    shoot(cam, os.path.join(out, "fit_mouth.png"), (0.0, 0.0, 0.034), w=1100, h=1100)

    # --- 3. lengthwise section of BOTH -------------------------------------
    bisect_meshes([o for o in bpy.data.objects if o.type == "MESH"])
    bpy.context.view_layer.update()
    # the cut plane faces -x; the camera goes to -x to see the cut face.
    cam = make_camera("section", (centre.x - 1.25, centre.y - 0.04, centre.z + 0.02),
                      (centre.x, centre.y, centre.z), lens=62.0, up=(1.0, 0.0, 0.0))
    shoot(cam, os.path.join(out, "fit_section.png"), (centre.x, centre.y, centre.z),
          w=1400, h=620)
    # and the section at the mouth, where wall thickness and clearance are the
    # whole question
    cam = make_camera("section_mouth", (-0.115, -0.010, 0.030), (0.0, 0.0, 0.030),
                      lens=95.0, up=(0.0, 0.0, 1.0))
    shoot(cam, os.path.join(out, "fit_section_mouth.png"), (0.0, 0.0, 0.030),
          w=1100, h=900)
    print("FIT_DONE %s" % out)


if __name__ == "__main__":
    main()
