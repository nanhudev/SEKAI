# C2B:CHUNK stairs_ramps
import bpy
import math

COLLECTION_NAME = "SEKAI_ENV01_KIT"


def _sr_collection():
    col = bpy.data.collections.get(COLLECTION_NAME)
    if col is None:
        raise RuntimeError(
            "ENV-01 stairs_ramps: SEKAI_ENV01_KIT missing. Run kit_common first."
        )
    return col


def _sr_mat(name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        raise RuntimeError(
            f"ENV-01 stairs_ramps: required material {name} missing"
        )
    return mat


def _sr_remove(name):
    obj = bpy.data.objects.get(name)
    if obj is None:
        return
    mesh = obj.data if obj.type == 'MESH' else None
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh is not None and mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def _sr_box(v, f, mi, center, size, mat_index):
    cx, cy, cz = center
    sx, sy, sz = size

    if min(sx, sy, sz) <= 0:
        raise ValueError(f"ENV-01 stairs_ramps: invalid box {size}")

    hx, hy, hz = sx/2, sy/2, sz/2
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

    for face in (
        (0,3,2,1),
        (4,5,6,7),
        (0,1,5,4),
        (1,2,6,5),
        (2,3,7,6),
        (3,0,4,7),
    ):
        f.append(tuple(b+i for i in face))
        mi.append(mat_index)


def _sr_wedge(v, f, mi, x0, x1, y0, y1, z0, z1, side_mat, top_mat):
    if x1 <= x0 or y1 <= y0 or z1 <= z0:
        raise ValueError("ENV-01 stairs_ramps: invalid wedge dimensions")

    b = len(v)

    v.extend([
        (x0, y0, z0),
        (x1, y0, z0),
        (x1, y1, z0),
        (x0, y1, z0),

        (x0, y0, z0),
        (x1, y0, z1),
        (x1, y1, z1),
        (x0, y1, z0),
    ])

    faces = [
        ((0,3,2,1), side_mat),
        ((4,5,6,7), top_mat),
        ((0,1,5,4), side_mat),
        ((3,7,6,2), side_mat),
        ((1,2,6,5), side_mat),
    ]

    for face, mat_idx in faces:
        f.append(tuple(b+i for i in face))
        mi.append(mat_idx)


def _sr_finish(name, v, f, mi, origin_rule, bevel):
    _sr_remove(name)

    mats = [
        _sr_mat("MV_Stone_Base"),
        _sr_mat("MV_Stone_Pale"),
        _sr_mat("MV_Timber_Dark"),
        _sr_mat("MV_Moss_Accent"),
    ]

    mesh = bpy.data.meshes.new(name + "_MESH")
    mesh.from_pydata(v, [], f)
    mesh.update(calc_edges=True)

    if len(mesh.polygons) != len(mi):
        raise RuntimeError(
            f"ENV-01 stairs_ramps: polygon/material mismatch on {name}"
        )

    for mat in mats:
        mesh.materials.append(mat)

    for poly, idx in zip(mesh.polygons, mi):
        poly.material_index = idx
        poly.use_smooth = False

    obj = bpy.data.objects.new(name, mesh)
    _sr_collection().objects.link(obj)

    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)

    obj["sekai_asset_id"] = "ENV-01"
    obj["sekai_grid_m"] = 2.0
    obj["sekai_origin_rule"] = origin_rule

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
                f"ENV-01 stairs_ramps: bevel failed on {name}: {exc}"
            ) from exc

    for poly in obj.data.polygons:
        poly.use_smooth = False

    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)

    return obj


# 4. ENV01_Stair_Straight_4
# Origin = bottom of run, centered across width, on ground plane.
# Local footprint: X = 0..4, Y = -1..1, Z = 0..1.44.
v, f, mi = [], [], []

TREAD = 0.50
RISE = 0.18
STEPS = 8

for i in range(STEPS):
    x0 = i * TREAD
    x1 = x0 + TREAD
    height = (i + 1) * RISE

    _sr_box(
        v, f, mi,
        ((x0+x1)*0.5, 0.0, height*0.5),
        (TREAD, 2.0, height),
        0
    )

    # Pale nosing on selected treads keeps the hierarchy readable.
    if i in (1, 3, 5, 7):
        _sr_box(
            v, f, mi,
            (x0 + 0.055, 0.0, height - 0.0125),
            (0.11, 1.96, 0.025),
            1
        )

# Sparse moss, confined to one low riser.
_sr_box(
    v, f, mi,
    (0.49, -0.991, 0.26),
    (0.26, 0.018, 0.16),
    3
)

_sr_finish(
    "ENV01_Stair_Straight_4",
    v, f, mi,
    "bottom of 4.0 m run at local (0,0,0), centred across 2.0 m width",
    bevel=0.010
)


# 6. ENV01_Ramp_4x2
# Origin = bottom of run at X=0, centred across width.
# Walking centre uses pale paving. Side strips form solid stone cheeks.
v, f, mi = [], [], []

_sr_wedge(
    v, f, mi,
    0.0, 4.0,
    -0.75, 0.75,
    0.0, 0.90,
    0, 1
)

_sr_wedge(
    v, f, mi,
    0.0, 4.0,
    -1.0, -0.75,
    0.0, 0.90,
    0, 0
)

_sr_wedge(
    v, f, mi,
    0.0, 4.0,
    0.75, 1.0,
    0.0, 0.90,
    0, 0
)

_sr_finish(
    "ENV01_Ramp_4x2",
    v, f, mi,
    "bottom of 4.0 m run at local (0,0,0), centred across 2.0 m width",
    bevel=0.008
)

for name in ("ENV01_Stair_Straight_4", "ENV01_Ramp_4x2"):
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise RuntimeError(
            f"ENV-01 stairs_ramps: expected object {name} missing"
        )

print("ENV-01 STAIRS/RAMPS READY | 2 pieces")
# C2B:END