# -*- coding: utf-8 -*-
"""
SEKAI / CHARACTER LINE — LIA V0 METRIC MEASUREMENT
Renders orthographic silhouettes with a 5 cm grid overlay burned in, and
derives a pixel-accurate width/depth profile in metres.

Run:
  "G:/blender.exe" -b --factory-startup --python tools/character/lia_measure.py -- \
      --fbx <path> --out <dir> [--grid 0.05]
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

FBX = os.path.abspath(ARGS.get("fbx"))
OUT = os.path.abspath(ARGS.get("out"))
GRID = float(ARGS.get("grid", 0.05))
ZLO = ARGS.get("zlo")
ZHI = ARGS.get("zhi")
RES_X = int(ARGS.get("resx", 1000))
RES_Y = int(ARGS.get("resy", 1400))
TAG = ARGS.get("tag", "LIA_V0")
os.makedirs(OUT, exist_ok=True)


def log(m):
    print("[LIA-MEASURE] " + str(m), flush=True)


bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
bpy.ops.import_scene.fbx(filepath=FBX, use_custom_normals=True, global_scale=1.0)

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
H = size.z
if ZLO and ZHI:
    zlo = float(ZLO)
    zhi = float(ZHI)
    center = Vector((center.x, center.y, (zlo + zhi) * 0.5))
    ORTHO_V = (zhi - zlo) * 1.12
    ZONES = (zlo, zhi)
    log("HEAD/ZONE mode: z %.3f..%.3f  vertical span %.4f" % (zlo, zhi, ORTHO_V))
else:
    ORTHO_V = 1.30
    ZONES = None
log("bbox size %s" % (tuple(round(v, 4) for v in size),))

scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
sh = scene.display.shading
STYLE = ARGS.get("style", "silhouette")
if STYLE == "form":
    sh.light = 'STUDIO'
    sh.studio_light = 'Default'
    sh.color_type = 'SINGLE'
    sh.single_color = (0.72, 0.72, 0.74)
    sh.show_cavity = True
    sh.cavity_type = 'BOTH'
    sh.show_object_outline = False
    sh.background_color = (0.30, 0.31, 0.33)
else:
    sh.light = 'FLAT'
    sh.color_type = 'SINGLE'
    sh.single_color = (0.02, 0.02, 0.025)
    sh.show_cavity = False
    sh.show_object_outline = False
    sh.background_color = (1.0, 1.0, 1.0)
sh.background_type = 'VIEWPORT'
sh.background_color = (1.0, 1.0, 1.0)
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False

cam_data = bpy.data.cameras.new("MCAM")
cam_data.type = 'ORTHO'
cam = bpy.data.objects.new("MCAM", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

RES_X = RES_X or 1000
RES_Y = RES_Y or 1400
ORTHO = ORTHO_V                       # metres across the LARGER canvas dimension
MPP = ORTHO / max(RES_X, RES_Y)       # metres per pixel (sensor_fit AUTO -> larger dim)
log("m/px = %.6f  vertical span = %.4f m" % (MPP, ORTHO))


def place(az_deg, target):
    az = math.radians(az_deg)
    d = Vector((math.sin(az), -math.cos(az), 0.0))
    cam.location = target + d * 8.0
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.ortho_scale = ORTHO
    cam.data.sensor_fit = 'VERTICAL'


scene.render.resolution_x = RES_X
scene.render.resolution_y = RES_Y


def render_to(path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


# vertex cloud in world space (silhouette outer extents == vertex extents, so
# measure from geometry rather than from the rendered image: exact and reusable)
WORLD_CO = []
for o in meshes:
    m_ = o.matrix_world
    for v in o.data.vertices:
        WORLD_CO.append(m_ @ v.co)
log("world verts = %d" % len(WORLD_CO))


def profile(axis):
    """per-row min/max along `axis` (0=X for front/back, 1=Y for side)."""
    out = {}
    for p in WORLD_CO:
        r = int(round((p.z - center.z) / MPP + RES_Y * 0.5 - 0.5))
        if r < 0 or r >= RES_Y:
            continue
        e = out.get(r)
        v = p[axis]
        if e is None:
            out[r] = [v, v]
        else:
            if v < e[0]:
                e[0] = v
            if v > e[1]:
                e[1] = v
    rows = []
    for r in range(RES_Y):
        z = center.z + ((r + 0.5) - RES_Y * 0.5) * MPP
        e = out.get(r)
        rows.append((r, z, e[0] if e else None, e[1] if e else None))
    return rows


def burn_grid(path, path_out, horizontal_only=True):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = list(img.pixels)

    def set_px(x, y, rgb):
        if 0 <= x < w and 0 <= y < h:
            i0 = (y * w + x) * 4
            px[i0] = rgb[0]
            px[i0 + 1] = rgb[1]
            px[i0 + 2] = rgb[2]
            px[i0 + 3] = 1.0

    # horizontal grid lines every GRID metres, thicker every 0.1 m
    z_lo = ZONES[0] if ZONES else mn.z
    z_hi = ZONES[1] if ZONES else mx.z
    n = int((z_hi - z_lo) / GRID) + 2
    for k in range(n):
        z = z_lo + k * GRID
        row = int(round((z - center.z) / MPP + h * 0.5 - 0.5))
        major = (k % round(0.10 / GRID) == 0) if GRID > 0 else False
        col = (0.9, 0.1, 0.15) if major else (0.35, 0.65, 1.0)
        if STYLE == 'form':
            col = (1.0, 0.85, 0.1) if major else (0.0, 1.0, 0.6)
        for dy in range(-1, 2 if major else 1):
            for x in range(w):
                set_px(x, row + dy, col)
    # vertical centre line
    for y in range(h):
        set_px(w // 2, y, (1.0, 0.2, 0.6))
    img.pixels = px
    img.filepath_raw = path_out
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)
    log("wrote " + path_out)


results = {}
for tag, az, axis in (("front", 0, 0), ("side", 90, 1), ("back", 180, 0)):
    place(az, center)
    p = render_to(os.path.join(OUT, "_tmp_%s.png" % tag))
    burn_grid(p, os.path.join(OUT, "%s_measure_%s.png" % (TAG, tag)))
    os.remove(p)
    results[tag] = profile(axis)

with open(os.path.join(OUT, "%s_measure.csv" % TAG), "w", encoding="utf-8") as f:
    f.write("# z_m,front_x_min,front_x_max,front_width,side_y_min,side_y_max,side_depth\n")
    fr = results["front"]
    sd = results["side"]
    for k in range(min(len(fr), len(sd))):
        z = fr[k][1]
        if fr[k][2] is None or sd[k][2] is None:
            continue
        f.write("%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n" %
                (z, fr[k][2], fr[k][3], fr[k][3] - fr[k][2],
                 sd[k][2], sd[k][3], sd[k][3] - sd[k][2]))

# coarse table every 2.5 cm
with open(os.path.join(OUT, "%s_measure_table.txt" % TAG), "w", encoding="utf-8") as f:
    f.write("LIA V0 METRIC PROFILE  (ortho %.3f m / %d px = %.6f m/px)\n" % (ORTHO, RES_Y, MPP))
    f.write("bbox min=%s max=%s size=%s\n\n" % (
        tuple(round(v, 4) for v in mn), tuple(round(v, 4) for v in mx), tuple(round(v, 4) for v in size)))
    f.write("  %-8s %-8s %-8s %-8s %-8s %-8s %-8s %-8s\n" %
            ("z(m)", "%H", "fr_xmin", "fr_xmax", "fr_w", "sd_ymin", "sd_ymax", "sd_d"))
    step = max(1, int(round(0.025 / MPP)))
    for k in range(0, min(len(results["front"]), len(results["side"])), step):
        z = results["front"][k][1]
        if z < mn.z or z > mx.z:
            continue
        fr_ = results["front"][k]
        sd_ = results["side"][k]
        if fr_[2] is None or sd_[2] is None:
            continue
        f.write("  %-8.4f %-8.3f %-8.4f %-8.4f %-8.4f %-8.4f %-8.4f %-8.4f\n" %
                (z, (z - mn.z) / H, fr_[2], fr_[3], fr_[3] - fr_[2],
                 sd_[2], sd_[3], sd_[3] - sd_[2]))

print("MEASURE_DONE")
