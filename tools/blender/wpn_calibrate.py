"""IS THE PREVIEW LIGHT RIG REPRESENTATIVE OF THE ROOM?  MEASURE IT.

    "/g/blender.exe" -b --factory-startup --python tools/blender/wpn_calibrate.py

WHY THIS EXISTS.  `weapon_common.set_preview_lighting()` lights every plate this
line has ever judged with a SUN of energy 3.2 and a sky of 0.55, and both numbers
were chosen by eye.  `scenes/training/TrainingGround.tscn` lights the room the
assets are signed off in with `light_energy = 1.2`, `ambient_light_energy = 0.5`
and `light_indirect_energy = 0.4`.  THOSE ARE DIFFERENT UNIT SYSTEMS -- Blender's
sun energy is irradiance in W/m2 and Godot's is a multiplier -- so no amount of
reading the two files says which rig is brighter, and the first in-game plates
came back with every material markedly PALER than the Blender plates of the same
material.

That difference decides where the fix goes.  If the room is brighter, the preview
is under-lit and every material in this line was tuned too light.  If the preview
is brighter, the room is fine and the materials are wrong.  Guessing is how a
material gets "fixed" to compensate for a light rig -- the two-bugs-cancelling
pattern the level line already paid for once.

THE METHOD.  One card per run, centred, so the sample point is the image centre
and no projection arithmetic can be quietly wrong.  0.30 m square, vertical,
1.20 m from a camera 0.10 m above it -- EXACTLY the geometry of the card
`godot/tools/shot_weapon_families.gd` stands in the room, so the two numbers are
comparable rather than merely both about grey.

THE COUNTERPART CARD IS `albedo_0214`, NOT `albedo_0500`.  Godot declares colour
properties in sRGB and converts them for shading, which was measured rather than
assumed: an UNSHADED quad with `albedo_color = Color(0.5)` renders 0x7e under the
LINEAR tone mapper, which is the sRGB round trip of 0.5 and not the display
encoding of a raw 0.5.  So the card standing in the room has a LINEAR reflectance
of 0.2140, and the Blender card that matches it must be set to 0.2140 too.  The
0.5000 card is printed beside it to show how much that convention is worth.

RUN IT WITH THE SAME VIEW TRANSFORM THE PREVIEWS USE.  This script sets AgX, look
None, exposure 0 -- matching `render_previews`.  If it is ever changed, change
both, or the two numbers stop being about the same thing.
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import weapon_common as wc  # noqa: E402

OUT_DIR = str(_SEKAI_ROOT / 'assets_source/review/weapon/_calib')

## sRGB 0.5 converted to linear, which is what the Godot card really reflects.
SRGB50_LINEAR = 0.21404114

CARDS = [
    ("albedo_0214", SRGB50_LINEAR, "lit"),
    ("albedo_0500", 0.5, "lit"),
    ("flat_0214", SRGB50_LINEAR, "flat"),
]

RES = 200
CARD = 0.30
CAM_DIST = 1.20
CAM_RISE = 0.10
## Mirrors `godot/tools/shot_weapon_families.gd`'s own offset, so neither card is
## dead-flat on the light and the two numbers describe the same geometry.
AZIMUTH_OFFSET = 18.0


def card_material(value, mode):
    m = bpy.data.materials.new("Cal")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (240, 0)
    if mode == "flat":
        # An Emission shader puts the value into the shading result unchanged,
        # which is what Godot's SHADING_MODE_UNSHADED does.
        em = nt.nodes.new("ShaderNodeEmission")
        em.location = (0, 0)
        em.inputs["Color"].default_value = (value, value, value, 1.0)
        em.inputs["Strength"].default_value = 1.0
        nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
        m.diffuse_color = (value, value, value, 1.0)
        return m
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (0, 0)
    bsdf.inputs["Base Color"].default_value = (value, value, value, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.0
    # 1.0, because that is `StandardMaterial3D`'s default and the room's card
    # does not override it.  A specular highlight on a calibration card is a
    # measurement of the highlight.
    bsdf.inputs["Roughness"].default_value = 1.0
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    m.diffuse_color = (value, value, value, 1.0)
    return m


def card_mesh():
    h = CARD * 0.5
    # Vertical, in the XZ plane, normal +Y.  The orientation is set per run by
    # `to_track_quat("Y", "Z")`, which aims that normal AT THE CAMERA -- and the
    # camera is placed on the SUN'S bearing, so the card ends up facing the
    # light.  See the note in main().
    verts = [(-h, 0.0, -h), (h, 0.0, -h), (h, 0.0, h), (-h, 0.0, h)]
    me = bpy.data.meshes.new("CalCard")
    me.from_pydata(verts, [], [(0, 1, 2, 3)])
    me.update()
    return me


## WHERE THE SUN IS, IN THE SAME TERMS THE ROOM USES.
##
## `weapon_common.set_preview_lighting()` aims the sun with a literal Euler of
## (52 deg, 0, -38 deg), and a sun shines along its own -Z -- so the direction
## the light TRAVELS is that rotation applied to (0, 0, -1), and an object is lit
## head-on when its normal points along the NEGATIVE of that.
##
## THE FIRST VERSION OF THIS SCRIPT DID NOT DO THIS AND THE MEASUREMENT WAS
## MEANINGLESS.  It stood the card facing +Y because that is where its camera
## was, without asking where the sun was -- and the preview sun comes from -Y, so
## every card was measured on its SHADOW side.  The result was a confident
## "the preview rig is 2.7x darker than the room", which is a measurement of the
## cosine between a card and a light, not of a light rig.
##
## It is the same mistake as the first in-game pass, one file later, which is the
## argument for deriving it rather than writing it down twice.
def sun_bearing():
    sun = bpy.data.objects.get("PreviewSun")
    if sun is None:
        raise SystemExit("CALIB: no PreviewSun -- set_preview_lighting() not run?")
    travel = sun.rotation_euler.to_matrix() @ wc.Vector((0.0, 0.0, -1.0))
    to_light = -wc.Vector(travel)
    return math.atan2(to_light.y, to_light.x), to_light


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    scene = bpy.context.scene

    # EMPTY THE FILE FIRST, AND THIS COST A RENDER TO LEARN.
    #
    # `--factory-startup` does NOT start empty: it starts with the default
    # startup scene, which is a 2 m Cube, a Light and a Camera all sitting on the
    # origin.  The first version of this script put its card AT the origin and
    # its camera 1.20 m away, which means the cube's +Y face filled the entire
    # lens from 0.20 m, the card was inside the cube, and three cards with three
    # different albedos all came back the SAME uniform grey -- a grey that read
    # perfectly convincingly as "the world background".  It was the cube.
    #
    # `clear_scene()` is the framework's own answer (`read_factory_settings`
    # with `use_empty=True`, then a sweep of the orphan datablocks), so this
    # script starts from the same empty file every builder in this line does.
    wc.clear_scene()
    scene = bpy.context.scene

    wc.set_preview_lighting()

    vs = scene.view_settings
    for cand in ("AgX", "Filmic", "Standard", "Raw"):
        try:
            vs.view_transform = cand
            break
        except Exception:
            continue
    try:
        vs.look = "None"
        vs.exposure = 0.0
    except Exception:
        pass

    scene.render.engine = wc._engine()
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.resolution_percentage = 100
    scene.render.resolution_x = RES
    scene.render.resolution_y = RES

    cam_data = bpy.data.cameras.new("CalCam")
    # The room's card is shot on a 52-degree camera; matching it here keeps the
    # card's on-screen size and its incidence angle the same, which is all that
    # makes two grey numbers comparable.
    cam_data.angle = math.radians(52.0)
    # Blender's default near plane is 0.1 m and this camera stands at 1.20 m, so
    # unlike the asset previews there is nothing to fall inside it -- but the
    # near plane is written down because it has silently ruined plates on this
    # line twice.
    cam_data.clip_start = 0.01
    cam = bpy.data.objects.new("CalCam", cam_data)
    scene.collection.objects.link(cam)

    az, to_light = sun_bearing()
    cam_az = az + math.radians(AZIMUTH_OFFSET)
    cam.location = (math.cos(cam_az) * CAM_DIST, math.sin(cam_az) * CAM_DIST,
                    CAM_RISE)
    look = wc.Vector((0.0, 0.0, 0.0)) - wc.Vector(cam.location)
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam

    print("CALIB  engine=%s view=%s look=%s exposure=%.2f"
          % (scene.render.engine, vs.view_transform, vs.look, vs.exposure))
    print("CALIB  to_light=%s  sun bearing %.1f deg  camera bearing %.1f deg"
          % (str(to_light.snappedf(0.0001) if hasattr(to_light, "snappedf")
                 else to_light), math.degrees(az), math.degrees(cam_az)))
    print("CALIB  sun=%.2f  sky=0.55  card=%.2fm at %.2fm, camera rise %.2f"
          % (3.2, CARD, CAM_DIST, CAM_RISE))

    for name, value, mode in CARDS:
        me = card_mesh()
        ob = bpy.data.objects.new(name, me)
        me.materials.append(card_material(value, mode))
        scene.collection.objects.link(ob)
        # THE NORMAL IS AIMED AT THE CAMERA, and because the camera is on the
        # sun's bearing, that is the same thing as aiming it at the sun.  The
        # `to_track_quat` also reproduces the few degrees of pitch the room's
        # card carries, since that camera is 0.10 m higher than its card.
        face = wc.Vector(cam.location) - wc.Vector(ob.location)
        ob.rotation_euler = face.to_track_quat("Y", "Z").to_euler()
        scene.render.filepath = os.path.abspath(os.path.join(OUT_DIR, name + ".png"))
        bpy.ops.render.render(write_still=True)
        incidence = abs(face.normalized().dot(to_light.normalized()))
        print("CALIB  %-12s mode=%-5s linear=%.4f  sun incidence cos=%.4f -> %s"
              "  exists=%s"
              % (name, mode, value, incidence, scene.render.filepath,
                 os.path.isfile(scene.render.filepath)))
        bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.meshes.remove(me)

    print("CALIB_DONE")


main()
