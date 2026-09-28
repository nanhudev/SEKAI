# C2B:CHUNK kit_common
import bpy
import math
from mathutils import Vector, Matrix

COLLECTION_NAME = "SEKAI_ENV01_KIT"

MAT_SPECS = {
    "MV_Stone_Base":  ((0.42, 0.44, 0.47, 1.0), 0.0, 0.85),
    "MV_Stone_Pale":  ((0.68, 0.64, 0.55, 1.0), 0.0, 0.80),
    "MV_Timber_Dark": ((0.20, 0.15, 0.12, 1.0), 0.0, 0.70),
    "MV_Moss_Accent": ((0.32, 0.38, 0.30, 1.0), 0.0, 0.90),
}


def env01_get_collection():
    col = bpy.data.collections.get(COLLECTION_NAME)
    if col is None:
        col = bpy.data.collections.new(COLLECTION_NAME)
        bpy.context.scene.collection.children.link(col)

    if col is None:
        raise RuntimeError("ENV-01: failed to create/find SEKAI_ENV01_KIT collection")
    return col


def env01_find_socket(node, identifiers, fallback_names=()):
    identifiers = tuple(identifiers)
    fallback_names = tuple(fallback_names)

    for socket in node.inputs:
        identifier = getattr(socket, "identifier", "")
        if identifier in identifiers:
            return socket

    for socket in node.inputs:
        identifier = str(getattr(socket, "identifier", "")).lower()
        for wanted in identifiers:
            if identifier == str(wanted).lower():
                return socket

    for socket in node.inputs:
        name = str(getattr(socket, "name", ""))
        if name in fallback_names:
            return socket

    for socket in node.inputs:
        name = str(getattr(socket, "name", "")).lower()
        for wanted in fallback_names:
            if name == str(wanted).lower():
                return socket

    raise RuntimeError(
        "ENV-01: required shader socket not found. "
        f"Identifiers={identifiers}, fallback_names={fallback_names}"
    )


def env01_make_material(name, base_color, metallic, roughness):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)

    if mat is None:
        raise RuntimeError(f"ENV-01: failed to create material {name}")

    mat.use_nodes = True

    if mat.node_tree is None:
        raise RuntimeError(f"ENV-01: material {name} has no node tree")

    bsdf = next(
        (n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'),
        None
    )
    if bsdf is None:
        raise RuntimeError(
            f"ENV-01: material {name} has no BSDF_PRINCIPLED node"
        )

    base_socket = env01_find_socket(
        bsdf,
        ("Base Color", "BaseColor"),
        ("Base Color", "基础色", "基色")
    )
    metallic_socket = env01_find_socket(
        bsdf,
        ("Metallic",),
        ("Metallic", "金属度", "金属")
    )
    roughness_socket = env01_find_socket(
        bsdf,
        ("Roughness",),
        ("Roughness", "粗糙度")
    )

    base_socket.default_value = base_color
    metallic_socket.default_value = metallic
    roughness_socket.default_value = roughness

    return mat


def env01_require_material(name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        if name not in MAT_SPECS:
            raise RuntimeError(f"ENV-01: unknown required material {name}")
        spec = MAT_SPECS[name]
        mat = env01_make_material(name, spec[0], spec[1], spec[2])

    if mat is None:
        raise RuntimeError(f"ENV-01: failed to resolve material {name}")
    return mat


def env01_remove_object(name):
    obj = bpy.data.objects.get(name)
    if obj is None:
        return

    mesh = obj.data if obj.type == 'MESH' else None
    bpy.data.objects.remove(obj, do_unlink=True)

    if mesh is not None and mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def env01_apply_transforms(obj):
    if obj is None:
        raise RuntimeError("ENV-01: apply_transforms received None")

    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    bpy.ops.object.transform_apply(
        location=False,
        rotation=True,
        scale=True
    )

    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)


def env01_flat_shade(obj):
    if obj is None or obj.type != 'MESH':
        raise RuntimeError("ENV-01: flat_shade requires mesh object")

    for poly in obj.data.polygons:
        poly.use_smooth = False


def env01_apply_bevel(obj, width=0.018, segments=1):
    if obj is None or obj.type != 'MESH':
        raise RuntimeError("ENV-01: apply_bevel requires mesh object")

    mod = obj.modifiers.new(name="ENV01_Chamfer", type='BEVEL')
    mod.width = float(width)
    mod.segments = int(segments)
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(20.0)

    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    try:
        bpy.ops.object.modifier_apply(modifier=mod.name)
    except Exception as exc:
        raise RuntimeError(
            f"ENV-01: failed applying bevel to {obj.name}: {exc}"
        ) from exc


def env01_add_box_geometry(vertices, faces, material_indices, center, size, material_index):
    cx, cy, cz = center
    sx, sy, sz = size

    if sx <= 0.0 or sy <= 0.0 or sz <= 0.0:
        raise ValueError(
            f"ENV-01: invalid box size {size}; all dimensions must be positive"
        )

    hx = sx * 0.5
    hy = sy * 0.5
    hz = sz * 0.5

    base = len(vertices)

    vertices.extend([
        (cx - hx, cy - hy, cz - hz),
        (cx + hx, cy - hy, cz - hz),
        (cx + hx, cy + hy, cz - hz),
        (cx - hx, cy + hy, cz - hz),
        (cx - hx, cy - hy, cz + hz),
        (cx + hx, cy - hy, cz + hz),
        (cx + hx, cy + hy, cz + hz),
        (cx - hx, cy + hy, cz + hz),
    ])

    local_faces = [
        (0, 3, 2, 1),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
    ]

    for face in local_faces:
        faces.append(tuple(base + i for i in face))
        material_indices.append(material_index)


def env01_create_mesh_object(
    name,
    vertices,
    faces,
    material_indices,
    materials,
    origin_rule,
    bevel_width=0.018
):
    if not vertices or not faces:
        raise RuntimeError(f"ENV-01: {name} has no geometry")

    if len(faces) != len(material_indices):
        raise RuntimeError(
            f"ENV-01: {name} face/material count mismatch "
            f"{len(faces)} != {len(material_indices)}"
        )

    env01_remove_object(name)

    mesh = bpy.data.meshes.new(name + "_MESH")
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)

    if len(mesh.polygons) != len(material_indices):
        raise RuntimeError(
            f"ENV-01: polygon count mismatch on {name}"
        )

    for mat in materials:
        if mat is None:
            raise RuntimeError(
                f"ENV-01: None material passed while building {name}"
            )
        mesh.materials.append(mat)

    for poly, mat_index in zip(mesh.polygons, material_indices):
        if mat_index < 0 or mat_index >= len(materials):
            raise RuntimeError(
                f"ENV-01: bad material index {mat_index} on {name}"
            )
        poly.material_index = mat_index
        poly.use_smooth = False

    obj = bpy.data.objects.new(name, mesh)
    col = env01_get_collection()
    col.objects.link(obj)

    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)

    obj["sekai_asset_id"] = "ENV-01"
    obj["sekai_grid_m"] = 2.0
    obj["sekai_origin_rule"] = origin_rule
    obj["sekai_units"] = "metres"

    env01_apply_transforms(obj)

    if bevel_width > 0.0:
        env01_apply_bevel(obj, bevel_width, 1)

    env01_flat_shade(obj)
    env01_apply_transforms(obj)

    return obj


kit_collection = env01_get_collection()

for mat_name, spec in MAT_SPECS.items():
    env01_make_material(mat_name, spec[0], spec[1], spec[2])

required_names = set(MAT_SPECS.keys())
resolved = [bpy.data.materials.get(n) for n in required_names]

if any(m is None for m in resolved):
    raise RuntimeError("ENV-01: one or more required materials failed creation")

print(
    "ENV-01 KIT COMMON READY | "
    "collection=SEKAI_ENV01_KIT | "
    "materials=4 | "
    "metric scale: 1 BU = 1 m"
)
# C2B:END