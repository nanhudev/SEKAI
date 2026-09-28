# C2B:CHUNK walls_edges
import bpy
import math

COLLECTION_NAME = "SEKAI_ENV01_KIT"


def _we_collection():
    col = bpy.data.collections.get(COLLECTION_NAME)
    if col is None:
        raise RuntimeError(
            "ENV-01 walls_edges: SEKAI_ENV01_KIT missing. Run kit_common first."
        )
    return col


def _we_mat(name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        raise RuntimeError(
            f"ENV-01 walls_edges: required material {name} missing"
        )
    return mat


def _we_remove(name):
    obj = bpy.data.objects.get(name)
    if obj is None:
        return
    mesh = obj.data if obj.type == 'MESH' else None
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh is not None and mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def _we_box(v, f, mi, center, size, mat_index):
    cx, cy, cz = center
    sx, sy, sz = size

    if min(sx, sy, sz) <= 0:
        raise ValueError(f"ENV-01 walls_edges: invalid box {size}")

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


def _we_rock(
    v, f, mi,
    x0, x1,
    y_back, y_front,
    top_left, top_right,
    mat_index,
    inset_left=0.0,
    inset_right=0.0
):
    if x1 <= x0:
        raise ValueError("ENV-01 walls_edges: invalid rock segment")

    b = len(v)

    xl_b = x0
    xr_b = x1
    xl_t = x0 + inset_left
    xr_t = x1 - inset_right

    v.extend([
        (xl_b, y_back, 0.0),
        (xr_b, y_back, 0.0),
        (xr_b, y_front, 0.0),
        (xl_b, y_front, 0.0),

        (xl_t, y_back + 0.06, top_left),
        (xr_t, y_back + 0.04, top_right),
        (xr_t, y_front - 0.05, top_right * 0.96),
        (xl_t, y_front - 0.03, top_left * 0.95),
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


def _we_finish(name, v, f, mi, origin_rule, bevel):
    _we_remove(name)

    mats = [
        _we_mat("MV_Stone_Base"),
        _we_mat("MV_Stone_Pale"),
        _we_mat("MV_Timber_Dark"),
        _we_mat("MV_Moss_Accent"),
    ]

    mesh = bpy.data.meshes.new(name + "_MESH")
    mesh.from_pydata(v, [], f)
    mesh.update(calc_edges=True)

    if len(mesh.polygons) != len(mi):
        raise RuntimeError(
            f"ENV-01 walls_edges: polygon/material mismatch on {name}"
        )

    for mat in mats:
        mesh.materials.append(mat)

    for poly, idx in zip(mesh.polygons, mi):
        poly.material_index = idx
        poly.use_smooth = False

    obj = bpy.data.objects.new(name, mesh)
    _we_collection().objects.link(obj)

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
                f"ENV-01 walls_edges: bevel failed on {name}: {exc}"
            ) from exc

    for poly in obj.data.polygons:
        poly.use_smooth = False

    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)

    return obj


# 7. ENV01_RetainingWall_4x1p5
# Overall max dimensions including cap: 4.0 x 0.45 x 1.50.
# Body is reduced by 0.04 m each exposed side so the cap can overhang by 0.04.
v, f, mi = [], [], []

body_len = 3.92
body_depth = 0.37
course_h = 0.284
courses = 5

for row in range(courses):
    zc = row * course_h + course_h * 0.5

    if row % 2 == 0:
        blocks = [
            (-1.47, 0.98),
            (-0.49, 0.98),
            ( 0.49, 0.98),
            ( 1.47, 0.98),
        ]
    else:
        blocks = [
            (-1.715, 0.49),
            (-0.98, 0.98),
            ( 0.00, 0.98),
            ( 0.98, 0.98),
            ( 1.715, 0.49),
        ]

    for bi, (xc, sx) in enumerate(blocks):
        mat_idx = 3 if (row == 1 and bi == 3) else 0
        _we_box(
            v, f, mi,
            (xc, 0.0, zc),
            (sx, body_depth, course_h),
            mat_idx
        )

# Cap reaches exact outer dimensions.
_we_box(v, f, mi, (0.0, 0.0, 1.46), (4.0, 0.45, 0.08), 1)

_we_finish(
    "ENV01_RetainingWall_4x1p5",
    v, f, mi,
    "ground-plane centre of 4.0 x 0.45 m overall footprint",
    bevel=0.012
)


# 8. ENV01_RetainingWall_Corner
# Overall footprint = 4 x 4 m L-plan.
# Outer edges at X/Y +/-2.0. Inner open quadrant faces +X/+Y.
v, f, mi = [], [], []

body_outer = 3.92
body_t = 0.37
cap_outer = 4.0
cap_t = 0.45
course_h = 0.284

# Horizontal arm near negative Y outer edge.
for row in range(5):
    zc = row * course_h + course_h * 0.5

    seg_count = 4 if row % 2 == 0 else 5
    seg_len = body_outer / seg_count

    for i in range(seg_count):
        xc = -body_outer * 0.5 + seg_len * (i + 0.5)
        mat_idx = 3 if (row == 2 and i == seg_count - 2) else 0

        _we_box(
            v, f, mi,
            (xc, -2.0 + 0.04 + body_t*0.5, zc),
            (seg_len, body_t, course_h),
            mat_idx
        )

# Vertical arm near negative X outer edge.
# Start above the horizontal-arm inner boundary to avoid excessive overlap.
arm_y_min = -2.0 + 0.04 + body_t
arm_y_max =  1.96
arm_len = arm_y_max - arm_y_min

for row in range(5):
    zc = row * course_h + course_h * 0.5
    seg_count = 4 if row % 2 == 1 else 5
    seg_len = arm_len / seg_count

    for i in range(seg_count):
        yc = arm_y_min + seg_len * (i + 0.5)
        _we_box(
            v, f, mi,
            (-2.0 + 0.04 + body_t*0.5, yc, zc),
            (body_t, seg_len, course_h),
            0
        )

# Cap stones, maximum outer footprint exactly 4 x 4.
_we_box(
    v, f, mi,
    (0.0, -2.0 + cap_t*0.5, 1.46),
    (4.0, cap_t, 0.08),
    1
)

vertical_cap_len = 4.0 - cap_t
_we_box(
    v, f, mi,
    (-2.0 + cap_t*0.5, -2.0 + cap_t + vertical_cap_len*0.5, 1.46),
    (cap_t, vertical_cap_len, 0.08),
    1
)

_we_finish(
    "ENV01_RetainingWall_Corner",
    v, f, mi,
    "ground-plane centre of 4.0 x 4.0 m L-plan footprint",
    bevel=0.012
)


# 10. ENV01_CliffEdge_4
# Six distinct rock masses, full footprint bounds = 4 x 1 m.
v, f, mi = [], [], []

rock_specs = [
    (-2.00, -1.28, -0.50, 0.44, 0.82, 1.02, 0, 0.00, 0.07),
    (-1.28, -0.62, -0.46, 0.50, 1.02, 0.91, 3, 0.05, 0.02),
    (-0.62,  0.02, -0.50, 0.43, 0.91, 1.20, 0, 0.02, 0.06),
    ( 0.02,  0.70, -0.43, 0.50, 1.20, 0.96, 0, 0.07, 0.03),
    ( 0.70,  1.36, -0.50, 0.46, 0.96, 1.10, 3, 0.03, 0.05),
    ( 1.36,  2.00, -0.45, 0.50, 1.10, 0.84, 0, 0.04, 0.00),
]

for spec in rock_specs:
    _we_rock(v, f, mi, *spec)

_we_finish(
    "ENV01_CliffEdge_4",
    v, f, mi,
    "ground-plane centre of 4.0 x 1.0 m footprint",
    bevel=0.018
)

for name in (
    "ENV01_RetainingWall_4x1p5",
    "ENV01_RetainingWall_Corner",
    "ENV01_CliffEdge_4",
):
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise RuntimeError(
            f"ENV-01 walls_edges: expected object {name} missing"
        )

print("ENV-01 WALLS/EDGES READY | 3 pieces")
# C2B:END