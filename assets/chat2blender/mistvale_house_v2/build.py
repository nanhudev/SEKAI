"""Build three reusable Mistvale house assemblies from one small Blender kit.

Run: blender -b --python assets/chat2blender/mistvale_house_v2/build.py
Origin is the foundation centre at ground level. Dimensions are metres.
"""
import bpy
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "godot/models/environment/mistvale/house_v2"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = ROOT / "assets_source/environment/mistvale/house_v2"
SOURCE.mkdir(parents=True, exist_ok=True)


def material(name, rgb, roughness=0.84):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


STONE = material("Mistvale warm cut stone", (0.27, 0.25, 0.22))
STONE_LIGHT = material("Mistvale stone edge", (0.37, 0.34, 0.29))
PLASTER = material("Mistvale warm plaster", (0.35, 0.305, 0.245))
PLASTER_SHADE = material("Mistvale shadow plaster", (0.265, 0.235, 0.20))
TIMBER = material("Mistvale aged timber", (0.13, 0.095, 0.065))
TIMBER_EDGE = material("Mistvale timber light", (0.22, 0.16, 0.105))
ROOF = material("Mistvale deep teal roof", (0.065, 0.13, 0.145))
ROOF_ALT = material("Mistvale roof tile shade", (0.085, 0.16, 0.165))
GLASS = material("Mistvale window shadow", (0.03, 0.065, 0.085), 0.3)


def box(name, pos, size, mat, bevel=0.0, rotation_x=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    ob = bpy.context.object
    ob.name = name
    ob.dimensions = size
    ob.rotation_euler.x = rotation_x
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(mat)
    if bevel:
        mod = ob.modifiers.new("soft crafted edges", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.affect = "EDGES"
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=mod.name)
        weighted = ob.modifiers.new("weighted normals", "WEIGHTED_NORMAL")
        bpy.ops.object.modifier_apply(modifier=weighted.name)
    return ob


def base(w, d):
    box("stone foundation", (0, 0, 0.24), (w + 0.75, d + 0.75, 1.1), STONE, 0.08)
    box("foundation ledge", (0, 0, 0.79), (w + 0.95, d + 0.95, 0.18), STONE_LIGHT, 0.045)
    for side in (-1, 1):
        for j in range(4):
            x = -w * 0.39 + j * w * 0.26
            box("visible foundation course", (x, side * (d / 2 + 0.39), 0.33),
                (w * 0.245, 0.045, 0.42), STONE_LIGHT if (j + side) % 3 == 0 else STONE)


def wall_panel(w, d, h):
    box("warm plaster core", (0, 0, 0.87 + h / 2), (w, d, h), PLASTER, 0.06)
    # A broad lower storey is visible from the river even when the windows are
    # only a few pixels. It stops the house reading as one white plaster block.
    box("warm lower storey", (0, 0, 1.55),
        (w + 0.045, d + 0.045, 1.35), PLASTER_SHADE, 0.025)
    for y in (-d / 2 - 0.08, d / 2 + 0.08):
        box("lower storey cap", (0, y, 2.25),
            (w + 0.15, 0.18, 0.16), TIMBER_EDGE, 0.015)
    for x in (-w / 2, w / 2):
        for y in (-d / 2, d / 2):
            box("load bearing corner", (x, y, 0.87 + h / 2),
                (0.29, 0.31, h + 0.11), TIMBER, 0.035)
    for z in (0.96, 0.87 + h):
        for y in (-d / 2, d / 2):
            box("long timber rail", (0, y, z), (w + 0.26, 0.25, 0.25), TIMBER_EDGE, 0.025)
        for x in (-w / 2, w / 2):
            box("end timber rail", (x, 0, z), (0.25, d + 0.2, 0.25), TIMBER_EDGE, 0.025)
    for x in (-w * 0.23, w * 0.23):
        for y in (-d / 2 - 0.015, d / 2 + 0.015):
            box("front timber mullion", (x, y, 0.87 + h / 2),
                (0.15, 0.22, h - 0.15), TIMBER)


def window(name, x, y, z, wide=1.15, high=1.35):
    face = 1 if y > 0 else -1
    box(name + " inset", (x, y + face * 0.055, z),
        (wide, 0.06, high), GLASS)
    box(name + " sill", (x, y + face * 0.16, z - high / 2),
        (wide + 0.3, 0.27, 0.16), STONE_LIGHT, 0.025)
    box(name + " lintel", (x, y + face * 0.13, z + high / 2),
        (wide + 0.25, 0.20, 0.14), TIMBER_EDGE)
    for side in (-1, 1):
        box(name + " shutter", (x + side * (wide / 2 + 0.19),
            y + face * 0.13, z), (0.25, 0.13, high + 0.04), TIMBER, 0.015)
    box(name + " crossbar", (x, y + face * 0.09, z),
        (wide, 0.09, 0.09), TIMBER_EDGE)


def end_window(name, x, y, z):
    face = 1 if x > 0 else -1
    box(name + " deep recess", (x + face * 0.06, y, z),
        (0.11, 1.30, 1.55), GLASS)
    for side in (-1, 1):
        box(name + " timber jamb", (x + face * 0.15,
            y + side * 0.72, z), (0.18, 0.18, 1.64), TIMBER_EDGE)
    for side in (-1, 1):
        box(name + " head and sill", (x + face * 0.15, y,
            z + side * 0.81), (0.20, 1.60, 0.17), TIMBER_EDGE)
    box(name + " crossbar", (x + face * 0.17, y, z),
        (0.11, 1.30, 0.10), TIMBER_EDGE)


def doorway(d):
    front = d / 2 + 0.055
    box("recessed front door", (0, front, 1.88), (1.36, 0.09, 2.05), TIMBER)
    box("door lintel", (0, front + 0.10, 2.96), (1.76, 0.28, 0.22), TIMBER_EDGE)
    for side in (-1, 1):
        box("door jamb", (side * 0.77, front + 0.09, 1.88),
            (0.18, 0.2, 2.15), TIMBER_EDGE)
    box("threshold", (0, front + 0.38, 0.88), (2.0, 0.95, 0.20), STONE_LIGHT, 0.04)


def gable_roof(w, d, eave, rise):
    slope_len = math.hypot(d / 2 + 0.7, rise)
    angle = math.atan2(rise, d / 2 + 0.7)
    for side in (-1, 1):
        box("deep roof slope", (0, side * (d / 4 + 0.35), eave + rise / 2),
            (w + 1.2, slope_len, 0.24), ROOF,
            0.045, -side * angle)
    box("ridge cap", (0, 0, eave + rise + 0.13),
        (w + 1.32, 0.38, 0.26), TIMBER_EDGE, 0.025)
    for end in (-1, 1):
        x = end * (w / 2 + 0.02)
        verts = [(x, -d / 2, eave), (x, d / 2, eave),
                 (x, 0, eave + rise)]
        mesh = bpy.data.meshes.new("closed gable mesh")
        mesh.from_pydata(verts, [], [(0, 1, 2) if end > 0 else (0, 2, 1)])
        mesh.materials.append(PLASTER_SHADE)
        ob = bpy.data.objects.new("closed gable", mesh)
        bpy.context.collection.objects.link(ob)
        box("gable tie beam", (x, 0, eave + 0.08),
            (0.23, d + 0.20, 0.18), TIMBER_EDGE, 0.02)
        for side in (-1, 1):
            box("sloped barge board", (x, side * (d / 4 + 0.35), eave + rise / 2),
                (0.23, slope_len, 0.17), TIMBER_EDGE, 0.02, -side * angle)


def porch(d, broad=False):
    width = 4.2 if broad else 3.1
    front = d / 2 + 1.45
    for x in (-width / 2 + 0.28, width / 2 - 0.28):
        box("porch load post", (x, front, 1.9),
            (0.20, 0.22, 2.5), TIMBER_EDGE, 0.025)
    box("porch canopy", (0, d / 2 + 0.82, 3.18),
        (width + 0.5, 2.15, 0.22), ROOF, 0.045, 0.17)
    box("porch step", (0, front + 0.32, 0.43),
        (width - 0.28, 0.75, 0.22), STONE_LIGHT, 0.04)


def annex(w, d, side):
    x = side * (w / 2 + 1.35)
    box("side workshop volume", (x, 0, 1.78),
        (2.65, d * 0.72, 2.60), PLASTER_SHADE, 0.05)
    box("side lean roof", (x, 0, 3.16),
        (3.15, d * 0.78, 0.20), ROOF_ALT, 0.035, side * 0.16)
    for y in (-d * 0.30, d * 0.30):
        box("annex corner", (x + side * 1.28, y, 1.80),
            (0.18, 0.20, 2.65), TIMBER)


def chimney(w, d, eave, rise, side):
    x = side * w * 0.28
    box("heavy chimney shaft", (x, -d * 0.2, eave + rise * 0.62),
        (0.95, 0.95, 2.5), STONE, 0.06)
    box("chimney cap", (x, -d * 0.2, eave + rise * 0.62 + 1.3),
        (1.24, 1.22, 0.22), STONE_LIGHT, 0.035)


def build(variant, w, d, h, rise):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    base(w, d)
    wall_panel(w, d, h)
    doorway(d)
    for x in (-w * 0.32, w * 0.32):
        window("front window", x, d / 2 + 0.025, 2.45)
    for x in (-w * 0.28, w * 0.28):
        window("back window", x, -d / 2 - 0.025, 2.32, 0.95, 1.18)
    for x in (-w / 2 - 0.025, w / 2 + 0.025):
        for y in (-d * 0.24, d * 0.24):
            end_window("gable window", x, y, 2.48)
    eave = h + 0.87
    gable_roof(w, d, eave, rise)
    porch(d, broad=(variant == 1))
    if variant != 2:
        annex(w, d, -1 if variant == 0 else 1)
    chimney(w, d, eave, rise, -1 if variant == 1 else 1)
    # Export everything as one reusable, self-contained scene.
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / f"MV_House_V2_{variant + 1}.blend"))
    # Keep editable pieces in the .blend source, but ship one mesh per material.
    # Seven hero houses should cost about ten draw nodes each, not 700 cubes.
    for mat in (STONE, STONE_LIGHT, PLASTER, PLASTER_SHADE,
                TIMBER, TIMBER_EDGE, ROOF, ROOF_ALT, GLASS):
        pieces = [ob for ob in bpy.context.scene.objects
                  if ob.type == "MESH" and ob.data.materials and ob.data.materials[0] == mat]
        if not pieces:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for ob in pieces:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = pieces[0]
        bpy.ops.object.join()
    bpy.ops.object.select_all(action="SELECT")
    target = OUT / f"MV_House_V2_{variant + 1}.glb"
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB",
                              use_selection=True, export_apply=True)
    print(f"EXPORTED {target} ({len(bpy.context.selected_objects)} parts)")


for args in ((0, 9.2, 7.6, 3.75, 2.15),
             (1, 10.5, 8.3, 4.15, 2.60),
             (2, 8.4, 7.1, 3.45, 2.05)):
    build(*args)
