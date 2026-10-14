# -*- coding: utf-8 -*-
"""
SEKAI / CHARACTER LINE — LIA V0 REVIEW RENDERS
Read-only. Imports the source FBX, renders orthographic review views.

Run:
  "G:/blender.exe" -b --factory-startup --python tools/character/lia_render_views.py -- \
      --fbx <path.fbx> --out <dir> [--tag LIA_V0]
"""

import bpy
import math
import os
import sys
from mathutils import Vector

argv = sys.argv
argv = argv[argv.index("--") + 1:] if "--" in argv else []
ARGS = {}
i = 0
while i < len(argv):
    if argv[i].startswith("--"):
        ARGS[argv[i][2:]] = argv[i + 1] if i + 1 < len(argv) else ""
        i += 2
    else:
        i += 1

FBX = os.path.abspath(ARGS.get("fbx", "")) if ARGS.get("fbx") else ""
BLEND = os.path.abspath(ARGS["blend"]) if ARGS.get("blend") else ""
OUT = os.path.abspath(ARGS.get("out"))
TAG = ARGS.get("tag", "LIA_V0")
WIRE = bool(ARGS.get("wireframe"))
WIRE_THICK = float(ARGS.get("wire-thick", 0.0016))
os.makedirs(OUT, exist_ok=True)


def log(m):
    print("[LIA-RENDER] " + str(m), flush=True)


if BLEND:
    bpy.ops.wm.open_mainfile(filepath=BLEND)
else:
    bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
    bpy.ops.import_scene.fbx(filepath=FBX, use_custom_normals=True, global_scale=1.0)

if WIRE:
    for o in [x for x in bpy.data.objects if x.type == 'MESH']:
        mm = o.modifiers.new("WIRE", 'WIREFRAME')
        mm.thickness = WIRE_THICK
        mm.use_replace = True
        mm.use_even_offset = True
        print("[LIA-RENDER] wireframe on %s thickness=%.4f" % (o.name, WIRE_THICK), flush=True)

meshes = [o for o in bpy.data.objects if o.type == 'MESH']
mn = Vector((1e9, 1e9, 1e9))
mx = Vector((-1e9, -1e9, -1e9))
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        for k in range(3):
            mn[k] = min(mn[k], w[k])
            mx[k] = max(mx[k], w[k])
size = mx - mn
center = (mn + mx) * 0.5
log("bbox %s -> %s  size %s" % (tuple(round(v, 4) for v in mn),
                               tuple(round(v, 4) for v in mx),
                               tuple(round(v, 4) for v in size)))

scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
sh = scene.display.shading
sh.background_type = 'VIEWPORT'


def make_cam(name):
    cam_data = bpy.data.cameras.new(name)
    cam_data.type = 'ORTHO'
    cam = bpy.data.objects.new(name, cam_data)
    scene.collection.objects.link(cam)
    return cam


cam = make_cam("REVIEW_CAM")


def place(azimuth_deg, elev_deg, target, ortho, dist=8.0):
    az = math.radians(azimuth_deg)
    el = math.radians(elev_deg)
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    cam.location = target + d * dist
    # aim at target
    direction = target - cam.location
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    cam.data.ortho_scale = ortho
    scene.camera = cam


def render(path, w, h):
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    log("wrote " + path)


def set_style(style):
    if style == "silhouette":
        sh.light = 'FLAT'
        sh.color_type = 'SINGLE'
        sh.single_color = (0.02, 0.02, 0.025)
        sh.show_cavity = False
        sh.show_object_outline = False
        sh.background_color = (1.0, 1.0, 1.0)
    elif style == "form":
        sh.light = 'STUDIO'
        sh.studio_light = 'Default'
        sh.color_type = 'SINGLE'
        sh.single_color = (0.62, 0.62, 0.64)
        sh.show_cavity = True
        sh.cavity_type = 'BOTH'
        sh.curvature_ridge_factor = 1.0
        sh.curvature_valley_factor = 1.0
        sh.show_object_outline = False
        sh.background_color = (0.22, 0.23, 0.25)
    elif style == "matcap":
        sh.light = 'MATCAP'
        sh.color_type = 'SINGLE'
        sh.single_color = (0.6, 0.6, 0.6)
        sh.show_cavity = False
        sh.background_color = (0.16, 0.17, 0.19)


H = float(size.z)
W = float(size.x)
D = float(size.y)
PAD = 1.12

# ---- full body ortho views (portrait canvas)
body_ortho = H * PAD
views = [("front", 0, 0), ("right", 90, 0), ("back", 180, 0), ("threequarter", 40, 0)]
for style in ("silhouette", "form", "matcap"):
    set_style(style)
    for name, az, el in views:
        place(az, el, center, body_ortho)
        render(os.path.join(OUT, "%s_%s_%s.png" % (TAG, style, name)), 900, round(900 * 1.45))

# ---- head close-up (top ~22% of body)
head_top = mx.z
head_bottom = mx.z - H * 0.30
head_center = Vector((center.x, center.y, (head_top + head_bottom) * 0.5))
head_ortho = (head_top - head_bottom) * 1.15
set_style("form")
for name, az, el in [("front", 0, 0), ("threequarter", 35, 6), ("right", 90, 0), ("front_low", 0, -12)]:
    place(az, el, head_center, head_ortho)
    render(os.path.join(OUT, "%s_head_%s.png" % (TAG, name)), 900, 900)

# ---- torso / shoulder close-up
torso_top = mx.z - H * 0.16
torso_bottom = mx.z - H * 0.55
tc = Vector((center.x, center.y, (torso_top + torso_bottom) * 0.5))
set_style("form")
for name, az, el in [("front", 0, 0), ("threequarter", 40, 0)]:
    place(az, el, tc, (torso_top - torso_bottom) * 1.15)
    render(os.path.join(OUT, "%s_torso_%s.png" % (TAG, name)), 900, 900)

# ---- legs / boots close-up
leg_top = mx.z - H * 0.48
leg_center = Vector((center.x, center.y, (mn.z + leg_top) * 0.5))
set_style("form")
for name, az, el in [("front", 0, 0), ("right", 90, 0)]:
    place(az, el, leg_center, (leg_top - mn.z) * 1.15)
    render(os.path.join(OUT, "%s_legs_%s.png" % (TAG, name)), 900, 900)

# ---- top-down (hair silhouette)
set_style("silhouette")
place(0, 89.9, center, max(W, D) * 1.2)
render(os.path.join(OUT, "%s_silhouette_top.png" % TAG), 900, 900)

print("RENDER_DONE", OUT)
