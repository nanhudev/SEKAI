# C2B:CHUNK bridge
import bpy
import math

COLLECTION_NAME = "SEKAI_ENV01_KIT"


def _br_collection():
    col = bpy.data.collections.get(COLLECTION_NAME)
    if col is None:
        raise RuntimeError(
            "ENV-01 bridge: SEKAI_ENV01_KIT missing. Run kit_common first."
        )
    return col


def _br_mat(name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        raise RuntimeError(
            f"ENV-01 bridge: required material {name} missing"
        )
    return mat


def _br_remove(name):
    obj = bpy.data.objects.get(name)
    if obj is None:
        return
    mesh = obj.data if obj.type == 'MESH' else None
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh is not None and mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def _br_box(v, f, mi, center, size, mat_index):
    cx, cy, cz = center
    sx, sy, sz = size

    if min(sx, sy, sz) <= 0:
        raise ValueError(f"ENV-01 bridge: invalid box {size}")

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


def _br_finish(name, v, f, mi, origin_rule, bevel):
    _br_remove(name)

    mats = [
        _br_mat("MV_Stone_Base"),
        _br_mat("MV_Stone_Pale"),
        _br_mat("MV_Timber_Dark"),
        _br_mat("MV_Moss_Accent"),
    ]

    mesh = bpy.data.meshes.new(name + "_MESH")
    mesh.from_pydata(v, [], f)
    mesh.update(calc_edges=True)

    if len(mesh.polygons) != len(mi):
        raise RuntimeError(
            f"ENV-01 bridge: polygon/material mismatch on {name}"
        )

    for mat in mats:
        mesh.materials.append(mat)

    for poly, idx in zip(mesh.polygons, mi):
        poly.material_index = idx
        poly.use_smooth = False

    obj = bpy.data.objects.new(name, mesh)
    _br_collection().objects.link(obj)

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
                f"ENV-01 bridge: bevel failed on {name}: {exc}"
            ) from exc

    for poly in obj.data.polygons:
        poly.use_smooth = False

    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)

    return obj


# 11. ENV01_BridgeDeck_4
# Overall dimensions = 4.0 x 2.0 x 0.35 m.
v, f, mi = [], [], []

# Stone stringers: run along X below the timber.
_br_box(v, f, mi, (0.0, -0.72, 0.115), (4.0, 0.28, 0.23), 0)
_br_box(v, f, mi, (0.0,  0.72, 0.115), (4.0, 0.28, 0.23), 0)

# Eight transverse timber plank modules along the run.
plank_count = 8
plank_len_x = 4.0 / plank_count
gap = 0.025
actual_plank_x = plank_len_x - gap

for i in range(plank_count):
    xc = -2.0 + plank_len_x * (i + 0.5)
    _br_box(
        v, f, mi,
        (xc, 0.0, 0.29),
        (actual_plank_x, 2.0, 0.12),
        2
    )

# End boards ensure exact X bounds while preserving the board rhythm.
_br_box(v, f, mi, (-1.9875, 0.0, 0.29), (0.025, 2.0, 0.12), 2)
_br_box(v, f, mi, ( 1.9875, 0.0, 0.29), (0.025, 2.0, 0.12), 2)

_br_finish(
    "ENV01_BridgeDeck_4",
    v, f, mi,
    "ground-plane centre of 4.0 x 2.0 m footprint",
    bevel=0.010
)


# 12. ENV01_BridgeRail_4
# Overall dimensions = 4.0 x 0.15 x 1.05 m.
v, f, mi = [], [], []

# Five posts at exactly 1.0 m spacing.
for x in (-2.0, -1.0, 0.0, 1.0, 2.0):
    post_w = 0.12

    # End posts are shifted inward by half their width so the global bounds
    # remain exactly X=-2..+2.
    if x == -2.0:
        xc = -2.0 + post_w * 0.5
    elif x == 2.0:
        xc = 2.0 - post_w * 0.5
    else:
        xc = x

    _br_box(
        v, f, mi,
        (xc, 0.0, 0.525),
        (post_w, 0.15, 1.05),
        2
    )

# Two continuous horizontal rails.
_br_box(v, f, mi, (0.0, 0.0, 0.42), (4.0, 0.11, 0.10), 2)
_br_box(v, f, mi, (0.0, 0.0, 0.78), (4.0, 0.11, 0.10), 2)

# Small stone shoe accents at the two terminal posts.
_br_box(v, f, mi, (-1.94, 0.0, 0.075), (0.12, 0.15, 0.15), 1)
_br_box(v, f, mi, ( 1.94, 0.0, 0.075), (0.12, 0.15, 0.15), 1)

_br_finish(
    "ENV01_BridgeRail_4",
    v, f, mi,
    "ground-plane centre of 4.0 x 0.15 m footprint",
    bevel=0.010
)

for name in ("ENV01_BridgeDeck_4", "ENV01_BridgeRail_4"):
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise RuntimeError(
            f"ENV-01 bridge: expected object {name} missing"
        )

print("ENV-01 BRIDGE READY | 2 pieces")
# C2B:END