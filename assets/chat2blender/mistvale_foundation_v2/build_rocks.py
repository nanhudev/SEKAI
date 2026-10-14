"""Mistvale foundation rock family. Run with Blender --background --python."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import math
import os
import random

OUT = str(_SEKAI_ROOT / 'godot/models/environment/mistvale/foundation_v2')
os.makedirs(OUT, exist_ok=True)

PALETTE = [
    ("stone_dry", (0.45, 0.42, 0.36, 1)),
    ("stone_wet", (0.36, 0.38, 0.34, 1)),
]


def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    mats = []
    for name, color in PALETTE:
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = color
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.72 if name == "stone_wet" else 0.91
        mats.append(mat)
    return mats


def rock(name, seed, radius, height, stretch=(1, 1), location=(0, 0, 0), wet=False):
    rng = random.Random(seed)
    count = 9
    phase = rng.uniform(-0.2, 0.2)
    angular = [phase + math.tau * j / count for j in range(count)]
    radial = [rng.uniform(0.82, 1.10) for _ in range(count)]
    # A low, broad foot and two offset shoulders give the rock a weight-bearing
    # silhouette. Shared angular stations make long fracture planes legible.
    rings = [
        (0.00, 0.98, (-0.06, 0.00)),
        (0.18, 1.00, (0.00, 0.00)),
        (0.63, 0.75, (0.12, -0.05)),
        (0.94, 0.30, (0.21, -0.08)),
    ]
    verts = []
    for level, (y, width, shift) in enumerate(rings):
        for j, angle in enumerate(angular):
            r = radial[j] * width
            # Parallel shallow ledges, with one larger broken flank.
            py = y * height + (0.025 if j in (2, 3, 4) and level == 2 else 0)
            verts.append((location[0] + (math.cos(angle) * r + shift[0]) * radius * stretch[0],
                          location[1] + (math.sin(angle) * r + shift[1]) * radius * stretch[1],
                          location[2] + py))
    verts.append((location[0] + 0.16 * radius, location[1] - 0.04 * radius, location[2] + height))
    verts.append((location[0], location[1], location[2]))
    top, bottom = len(verts) - 2, len(verts) - 1
    faces = []
    for ring in range(len(rings) - 1):
        for j in range(count):
            nj = (j + 1) % count
            a, b = ring * count + j, ring * count + nj
            c, d = (ring + 1) * count + j, (ring + 1) * count + nj
            # Split selected quads diagonally to make fracture facets, without
            # the isotropic noise-sphere silhouette of a displaced ico mesh.
            if (j + ring) % 3 == 0:
                faces.extend([(a, b, d), (a, d, c)])
            else:
                faces.extend([(a, b, c), (b, d, c)])
    for j in range(count):
        faces.append(((len(rings) - 1) * count + j, (len(rings) - 1) * count + (j + 1) % count, top))
        faces.append(((j + 1) % count, j, bottom))
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(verts, [], faces)
    # One material per rock mesh keeps the cluster usable in Compatibility;
    # splitting each facet into 4-5 GLB primitives added dozens of draw calls.
    mesh.materials.clear()
    mesh.materials.append(MATERIALS[1 if wet else 0])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for poly in mesh.polygons:
        poly.use_smooth = False
        poly.material_index = 0
    return obj


def export(name, specs):
    global MATERIALS
    MATERIALS = reset()
    for i, spec in enumerate(specs):
        rock(name + "_%02d" % i, **spec)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB",
                              use_selection=True, export_apply=True)
    print("EXPORTED", name)


export("MV_RiverRock_S", [dict(seed=11, radius=0.62, height=0.38, wet=True)])
export("MV_RiverRock_M", [dict(seed=29, radius=1.15, height=1.12, stretch=(1.25, .85), wet=True)])
export("MV_RiverRock_L", [dict(seed=47, radius=1.95, height=2.15, stretch=(1.22, .82), wet=True)])
export("MV_RiverCluster_A", [
    dict(seed=8, radius=1.45, height=0.9, location=(-1.3, 0, 0), wet=True),
    dict(seed=12, radius=1.05, height=0.55, location=(1.4, -0.55, 0), wet=True),
    dict(seed=17, radius=0.52, height=0.32, location=(0.2, 1.0, 0), wet=True),
])
export("MV_RiverCluster_B", [
    dict(seed=18, radius=2.0, height=1.28, stretch=(.7, 1.25), location=(-0.7, 0, 0), wet=True),
    dict(seed=35, radius=0.85, height=0.50, location=(1.25, 0.7, 0), wet=True),
])
export("MV_CliffShelf_A", [dict(seed=101, radius=3.2, height=1.9, stretch=(1.5, .62))])
export("MV_CliffShelf_B", [dict(seed=108, radius=2.5, height=2.65, stretch=(.72, 1.3))])
