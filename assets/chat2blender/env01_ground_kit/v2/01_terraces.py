# C2B:CHUNK terraces
import bpy
import math

COLLECTION_NAME = "SEKAI_ENV01_KIT"

MAT_NAMES = (
    "MV_Stone_Base",
    "MV_Stone_Pale",
    "MV_Timber_Dark",
    "MV_Moss_Accent",
)


def _env01_collection():
    col = bpy.data.collections.get(COLLECTION_NAME)
    if col is None:
        raise RuntimeError(
            "ENV-01 terraces: SEKAI_ENV01_KIT missing. Run kit_common first."
        )
    return col


def _env01_mat(name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        raise RuntimeError(
            f"ENV-01 terraces: required material {name} missing. "
            "Run kit_common first."
        )
    return mat


def _env01_remove(name):
    obj = bpy.data.objects.get(name)
    if obj is None:
        return
    mesh = obj.data if obj.type == 'MESH' else None
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh is not None and mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def _env01_box(v, f, mi, center, size, mat_index):
    cx, cy, cz = center
    sx, sy, sz = size
    if min(sx, sy, sz) <= 0:
        raise ValueError(f"ENV-01 terraces: invalid box size {size}")

    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    b = len(v)

    v.extend([
        (cx-hx, cy-hy, cz-hz),
        (cx+hx, cy-hy, cz-hz),
        (cx+hx, cy+hy, cz-hz),
        (cx-hx, cy+hy, cz-hz),
        (cx-hx, cy-hy, cz+hz),
        (cx+hx, cy-hy, cz+hz),
        (cx+hx, cy+hy, cz+hz),
        (cx-hx, cy+hy, cz+hz),
    ])

    fs = (
        (0,3,2,1),
        (4,5,6,7),
        (0,1,5,4),
        (1,2,6,5),
        (2,3,7,6),
        (3,0,4,7),
    )
    for face in fs:
        f.append(tuple(b+i for i in face))
        mi.append(mat_index)


def _env01_finish(name, v, f, mi, origin_rule, bevel=0.014):
    _env01_remove(name)

    mats = [
        _env01_mat("MV_Stone_Base"),
        _env01_mat("MV_Stone_Pale"),
        _env01_mat("MV_Timber_Dark"),
        _env01_mat("MV_Moss_Accent"),
    ]

    mesh = bpy.data.meshes.new(name + "_MESH")
    mesh.from_pydata(v, [], f)
    mesh.update(calc_edges=True)

    if len(mesh.polygons) != len(mi):
        raise RuntimeError(
            f"ENV-01 terraces: material assignment mismatch on {name}"
        )

    for mat in mats:
        mesh.materials.append(mat)

    for poly, idx in zip(mesh.polygons, mi):
        poly.material_index = idx
        poly.use_smooth = False

    obj = bpy.data.objects.new(name, mesh)
    _env01_collection().objects.link(obj)

    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)

    obj["sekai_asset_id"] = "ENV-01"
    obj["sekai_origin_rule"] = origin_rule
    obj["sekai_grid_m"] = 2.0

    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(
        location=False,
        rotation=True,
        scale=True
    )

    if bevel > 0:
        mod = obj.modifiers.new("ENV01_Chamfer", 'BEVEL')
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = 'ANGLE'
        mod.angle_limit = math.radians(20)

        try:
            bpy.ops.object.modifier_apply(modifier=mod.name)
        except Exception as exc:
            raise RuntimeError(
                f"ENV-01 terraces: bevel failed on {name}: {exc}"
            ) from exc

    for poly in obj.data.polygons:
        poly.use_smooth = False

    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)

    return obj


# 1. ENV01_Terrace_4x4
v, f, mi = [], [], []

# Three stone courses. The mesh itself is centred on the grid-footprint origin.
for zc in (0.0475, 0.1425, 0.2375):
    _env01_box(v, f, mi, (0.0, 0.0, zc), (4.0, 4.0, 0.095), 0)

# Top central inset.
_env01_box(v, f, mi, (0.0, 0.0, 0.2925), (3.80, 3.80, 0.015), 0)

# 0.10 m pale rim.
_env01_box(v, f, mi, (0.0, -1.95, 0.2925), (4.0, 0.10, 0.015), 1)
_env01_box(v, f, mi, (0.0,  1.95, 0.2925), (4.0, 0.10, 0.015), 1)
_env01_box(v, f, mi, (-1.95, 0.0, 0.2925), (0.10, 3.80, 0.015), 1)
_env01_box(v, f, mi, ( 1.95, 0.0, 0.2925), (0.10, 3.80, 0.015), 1)

_env01_finish(
    "ENV01_Terrace_4x4",
    v, f, mi,
    "ground-plane centre of 4.0 x 4.0 m footprint",
    bevel=0.012
)


# 2. ENV01_Terrace_8x8
v, f, mi = [], [], []

for zc in (0.0475, 0.1425, 0.2375):
    _env01_box(v, f, mi, (0.0, 0.0, zc), (8.0, 8.0, 0.095), 0)

line = 0.055
half_cell = (4.0 - line * 0.5) * 0.5
cell_size = 4.0 - line * 0.5

for x in (-2.0, 2.0):
    for y in (-2.0, 2.0):
        _env01_box(
            v, f, mi,
            (x, y, 0.2925),
            (cell_size, cell_size, 0.015),
            0
        )

# Pale inset paving cross, splitting the top into 4 x 4 m cells.
_env01_box(v, f, mi, (0.0, 0.0, 0.2925), (line, 8.0, 0.015), 1)
_env01_box(v, f, mi, (0.0, 0.0, 0.2925), (8.0, line, 0.015), 1)

_env01_finish(
    "ENV01_Terrace_8x8",
    v, f, mi,
    "ground-plane centre of 8.0 x 8.0 m footprint",
    bevel=0.012
)


# 3. ENV01_Terrace_StepEdge_4
v, f, mi = [], [], []

# Main low lip / bench body.
_env01_box(v, f, mi, (0.0, 0.0, 0.135), (4.0, 0.60, 0.27), 0)

# Pale seat/cap surface.
_env01_box(v, f, mi, (0.0, 0.0, 0.285), (4.0, 0.60, 0.03), 1)

# Sparse moss accent on one side block only.
_env01_box(v, f, mi, (1.25, -0.291, 0.115), (0.58, 0.018, 0.11), 3)

_env01_finish(
    "ENV01_Terrace_StepEdge_4",
    v, f, mi,
    "ground-plane centre of 4.0 x 0.60 m footprint",
    bevel=0.014
)


# 5. ENV01_Stair_Landing_2x2
v, f, mi = [], [], []

for zc in (0.05, 0.15, 0.25):
    _env01_box(v, f, mi, (0.0, 0.0, zc), (2.0, 2.0, 0.10), 0)

_env01_finish(
    "ENV01_Stair_Landing_2x2",
    v, f, mi,
    "ground-plane centre of 2.0 x 2.0 m footprint; top Z = 0.30 m",
    bevel=0.012
)


# 9. ENV01_Curb_4
v, f, mi = [], [], []

_env01_box(v, f, mi, (0.0, 0.0, 0.08), (4.0, 0.30, 0.16), 0)

_env01_finish(
    "ENV01_Curb_4",
    v, f, mi,
    "ground-plane centre of 4.0 x 0.30 m footprint",
    bevel=0.025
)

for name in (
    "ENV01_Terrace_4x4",
    "ENV01_Terrace_8x8",
    "ENV01_Terrace_StepEdge_4",
    "ENV01_Stair_Landing_2x2",
    "ENV01_Curb_4",
):
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise RuntimeError(f"ENV-01 terraces: expected object {name} missing")

print("ENV-01 TERRACES READY | 5 pieces")
# C2B:END