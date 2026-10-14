"""Author Mistvale guild hall as a reusable, single UE static mesh.

Run with: blender -b -P Source/model_guild.py
Dimensions are metres. The entrance faces south (negative Y).
"""
import bpy
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Source" / "SM_Mistvale_Guild.fbx"
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=0.88):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    return m


stone = material("MV_Guild_WarmStone", (.39, .38, .34))
plaster = material("MV_Guild_IvoryPlaster", (.74, .70, .58))
timber = material("MV_Guild_DarkOak", (.15, .095, .058))
roofmat = material("MV_Guild_SlateTeal", (.12, .25, .26))
roofedge = material("MV_Guild_RoofEdge", (.08, .16, .17))
trim = material("MV_Guild_AmberTrim", (.47, .28, .12))
glass = material("MV_Guild_Glass", (.13, .25, .30), .2)
objects = []


def box(name, loc, scale, mat, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    if bevel:
        mod = o.modifiers.new("Soft stone and wood edges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        o.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    objects.append(o)
    return o


def roof(name, x, y, z, width, depth, rise):
    # Both slate planes project past the walls, with a heavy readable eave.
    for sign in (-1, 1):
        p = box(name + ("_W" if sign < 0 else "_E"),
                (x + sign * width / 4, y, z + rise / 2),
                (math.hypot(width / 2, rise) + .45, depth + 1.7, .28),
                roofmat, .09)
        p.rotation_euler[1] = sign * math.atan2(rise, width / 2)
        for course in range(1, 7):
            t = course / 7
            strip = box(name + "_SlateCourse", (x + sign * width/2 * (1-t),
                        y, z + rise*t + .13),
                        (.12, depth + 1.66, .13), roofedge, .035)
            strip.rotation_euler[1] = sign * math.atan2(rise, width/2)
        box(name + "_Eave" + str(sign),
            (x + sign * width / 2, y, z - .09), (.25, depth + 2, .55), roofedge, .06)
    box(name + "_Ridge", (x, y, z + rise + .1), (.4, depth + 1.9, .42), roofedge, .08)


def framed_hall(name, x, y, w, d, wall_h, foundation=1.2):
    box(name + "_StoneFoundation", (x, y, foundation / 2),
        (w + .3, d + .3, foundation), stone, .16)
    box(name + "_PlasterWall", (x, y, foundation + wall_h / 2),
        (w, d, wall_h), plaster, .12)
    z0 = foundation + .1
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(name + "_CornerPost", (x + sx * (w/2-.26), y + sy * (d/2-.26),
                 z0 + wall_h / 2), (.44, .44, wall_h), timber, .04)
    for iy in range(-2, 3):
        yy = y + iy * (d - 1) / 4
        for sx in (-1, 1):
            box(name + "_SidePost", (x + sx * (w/2-.18), yy, z0 + wall_h / 2),
                (.34, .42, wall_h), timber, .04)
    for ix in range(-3, 4):
        xx = x + ix * (w - 1) / 6
        for sy in (-1, 1):
            box(name + "_EndPost", (xx, y + sy * (d/2-.18), z0 + wall_h / 2),
                (.4, .34, wall_h), timber, .04)
    for h in (.18, wall_h*.50, wall_h-.15):
        for sx in (-1, 1):
            box(name + "_LongBeam", (x + sx*(w/2-.18), y, foundation+h),
                (.38, d+.6, .35), timber, .04)
        for sy in (-1, 1):
            box(name + "_CrossBeam", (x, y + sy*(d/2-.18), foundation+h),
                (w+.6, .38, .35), timber, .04)
    roof(name + "_Roof", x, y, foundation + wall_h, w+1.2, d, max(2.8, w*.19))


def window(name, x, y, z, face, width=1.55, height=2.2):
    box(name + "_Glass", (x,y,z),
        (width, .11, height) if face == "Y" else (.11,width,height), glass, .02)
    for side in (-1,1):
        box(name + "_Jamb", (x + side*width/2,y,z) if face == "Y" else (x,y+side*width/2,z),
            (.18,.3,height+.35) if face == "Y" else (.3,.18,height+.35), timber, .03)
    box(name + "_Lintel", (x,y,z+height/2),
        (width+.35,.35,.22) if face == "Y" else (.35,width+.35,.22), trim, .04)
    box(name + "_Sill", (x,y,z-height/2),
        (width+.35,.4,.21) if face == "Y" else (.4,width+.35,.21), stone, .03)


# Main meeting hall, higher records wing and asymmetric signal tower.
framed_hall("Guild_MainHall", 2.5, 0, 25, 17, 8.8)
framed_hall("Guild_RecordsWing", -12.5, 1.8, 10, 13, 10.5)
box("Guild_Tower_StoneBase", (-13.3, 7.4, 4.9), (7, 7, 9.8), stone, .18)
box("Guild_Tower_Plaster", (-13.3, 7.4, 12.7), (6.5, 6.5, 5.8), plaster, .12)
for xx in (-16.3,-10.3):
    for yy in (4.4,10.4):
        box("Guild_Tower_Post", (xx,yy,12.7), (.45,.45,6.2), timber, .04)
roof("Guild_TowerRoof", -13.3, 7.4, 15.6, 8, 8, 4.3)
box("Guild_StoneChimney", (8.8, 5.2, 14.0), (2.1, 2.0, 8.0), stone, .11)
box("Guild_ChimneyCrown", (8.8, 5.2, 18.2), (2.7, 2.6, .65), trim, .09)
box("Guild_ChimneyCap", (8.8, 5.2, 18.7), (2.8, 2.7, .35), roofedge, .08)

# South-facing porch has a double-height entry and a usable raised platform.
box("Guild_EntryStair", (1,-11.6,.28), (7,4,.56), stone, .12)
box("Guild_EntryLanding", (1,-9.2,1), (9,4.2,.4), stone, .12)
for xx in (-3.2,5.2):
    box("Guild_PorchColumn", (xx,-11.0,3.4), (.65,.65,5.3), timber, .08)
box("Guild_PorchLintel", (1,-11,6.1), (9,.7,.65), timber, .08)
roof("Guild_PorchRoof", 1,-10.4,6.2, 9.7, 5, 1.7)
box("Guild_MainDoor", (1,-8.57,3.1), (3.4,.24,4.5), timber, .08)
box("Guild_DoorFrame", (1,-8.85,5.5), (4.1,.5,.46), trim, .07)

for xx in (-7.2,-3.5,8,12):
    window("Guild_SouthWindow", xx,-8.63,5.2,"Y")
    window("Guild_NorthWindow", xx,8.63,5.2,"Y")
for yy in (-4.8,0,4.8):
    window("Guild_EastWindow", 15.13,yy,5.1,"X")

# Gable emblem and balcony mark the building from market street and aerials.
box("Guild_EmblemBack", (2.5,-8.89,10.8), (3.7,.25,2.5), timber, .1)
box("Guild_EmblemGold", (2.5,-9.08,10.8), (2.4,.12,.18), trim, .02)
box("Guild_BalconySlab", (-12.5,-7.65,8.4), (7.8,2.3,.45), timber, .08)
for xx in (-15.8,-13.6,-11.4,-9.2):
    box("Guild_BalconyRail", (xx,-8.7,9.1), (.24,.24,1.2), timber, .03)
box("Guild_BalconyTopRail", (-12.5,-8.7,9.7), (7.8,.25,.23), timber, .03)

# Join so UE sees one mesh, while material slots survive.
bpy.ops.object.select_all(action="DESELECT")
for obj in objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.object.convert(target="MESH")
bpy.ops.object.join()
bpy.context.object.name = "SM_Mistvale_Guild"
OUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.fbx(filepath=str(OUT), use_selection=True, apply_unit_scale=True,
                         add_leaf_bones=False, mesh_smooth_type="FACE")
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "Source" / "Mistvale_Guild.blend"))
print("GUILD_EXPORT", OUT, OUT.stat().st_size, "VERTS", len(bpy.context.object.data.vertices))
