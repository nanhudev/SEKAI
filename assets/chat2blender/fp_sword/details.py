# C2B:CHUNK details

import bpy
import bmesh
import math

ASSET_COLLECTION = "SEKAI_FP_SWORD"
ROOT_NAME = "FP_Sword_Root"


# ------------------------------------------------------------
# Material helpers — localization safe
# ------------------------------------------------------------

def principled(mat):
    mat.use_nodes = True

    for node in mat.node_tree.nodes:
        if node.type == 'BSDF_PRINCIPLED':
            return node

    nodes = mat.node_tree.nodes
    links = mat.node_tree.links

    bsdf = nodes.new("ShaderNodeBsdfPrincipled")

    output = None
    for node in nodes:
        if node.type == 'OUTPUT_MATERIAL':
            output = node
            break

    if output is None:
        output = nodes.new("ShaderNodeOutputMaterial")

    links.new(bsdf.outputs[0], output.inputs[0])
    return bsdf


def _socket_key(value):
    if not value:
        return ""
    return (
        str(value)
        .casefold()
        .replace(" ", "")
        .replace("_", "")
        .replace("-", "")
    )


def find_input(node, names, fallback_index=None):
    if isinstance(names, str):
        names = [names]

    wanted = {_socket_key(name) for name in names}

    for socket in node.inputs:
        candidates = {
            _socket_key(getattr(socket, "identifier", "")),
            _socket_key(getattr(socket, "name", "")),
        }

        if wanted.intersection(candidates):
            return socket

    for socket in node.inputs:
        candidates = (
            _socket_key(getattr(socket, "identifier", "")),
            _socket_key(getattr(socket, "name", "")),
        )

        for target in wanted:
            if not target:
                continue
            for candidate in candidates:
                if target in candidate or candidate in target:
                    return socket

    if fallback_index is not None:
        if 0 <= fallback_index < len(node.inputs):
            return node.inputs[fallback_index]

    return None


def set_input(node, names, value, fallback_index=None):
    socket = find_input(
        node,
        names,
        fallback_index=fallback_index
    )

    if socket is None:
        return False

    socket.default_value = value
    return True


def configure_principled(
    mat,
    base_color,
    metallic,
    roughness,
    emission_color=None,
    emission_strength=0.0
):
    bsdf = principled(mat)

    if not set_input(
        bsdf,
        ["Base Color", "BaseColor"],
        (*base_color, 1.0),
        fallback_index=0
    ):
        raise RuntimeError(
            f"Cannot resolve Base Color input for {mat.name}"
        )

    if not set_input(
        bsdf,
        ["Metallic"],
        metallic,
        fallback_index=1
    ):
        raise RuntimeError(
            f"Cannot resolve Metallic input for {mat.name}"
        )

    if not set_input(
        bsdf,
        ["Roughness"],
        roughness,
        fallback_index=2
    ):
        raise RuntimeError(
            f"Cannot resolve Roughness input for {mat.name}"
        )

    if emission_color is not None:
        if not set_input(
            bsdf,
            ["Emission Color", "Emission"],
            (*emission_color, 1.0)
        ):
            raise RuntimeError(
                f"Cannot resolve Emission Color input for {mat.name}"
            )

        if not set_input(
            bsdf,
            ["Emission Strength", "EmissionStrength"],
            emission_strength
        ):
            raise RuntimeError(
                f"Cannot resolve Emission Strength input for {mat.name}"
            )

    mat.diffuse_color = (*base_color, 1.0)
    return mat


def ensure_material(
    name,
    base_color,
    metallic,
    roughness,
    emission_color=None,
    emission_strength=0.0
):
    mat = bpy.data.materials.get(name)

    if mat is None:
        mat = bpy.data.materials.new(name)

    mat.use_nodes = True

    configure_principled(
        mat,
        base_color,
        metallic,
        roughness,
        emission_color,
        emission_strength
    )

    return mat


# ------------------------------------------------------------
# Generic helpers
# ------------------------------------------------------------

def ensure_object_mode():
    if bpy.context.object:
        if bpy.context.object.mode != 'OBJECT':
            bpy.ops.object.mode_set(mode='OBJECT')


def select_only(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def parent_keep_transform(obj, parent):
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world


def replace_mesh(obj, mesh):
    old_mesh = obj.data
    obj.data = mesh

    if old_mesh is not None and old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)


def recalc_mesh_normals(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)

    if bm.faces:
        bmesh.ops.recalc_face_normals(
            bm,
            faces=list(bm.faces)
        )

    bm.to_mesh(mesh)
    bm.free()

    mesh.validate(verbose=False)
    mesh.update()


def create_uv(obj):
    if obj.type != 'MESH':
        return

    if len(obj.data.uv_layers) == 0:
        obj.data.uv_layers.new(name="UVMap")

    select_only(obj)

    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')

    try:
        bpy.ops.uv.smart_project(
            angle_limit=math.radians(66.0),
            island_margin=0.02
        )
    except Exception:
        pass

    bpy.ops.object.mode_set(mode='OBJECT')


def apply_bevel(obj, width, segments=2):
    select_only(obj)

    modifier = obj.modifiers.new(
        name="Details_Bevel",
        type='BEVEL'
    )
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = 'ANGLE'

    if hasattr(modifier, "harden_normals"):
        modifier.harden_normals = True

    bpy.ops.object.modifier_apply(
        modifier=modifier.name
    )


def assign_single_material(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def delete_object_if_exists(name):
    obj = bpy.data.objects.get(name)

    if obj is not None:
        bpy.data.objects.remove(
            obj,
            do_unlink=True
        )


# ------------------------------------------------------------
# Validate blockout
# ------------------------------------------------------------

ensure_object_mode()

asset_col = bpy.data.collections.get(ASSET_COLLECTION)
root = bpy.data.objects.get(ROOT_NAME)
blade = bpy.data.objects.get("Blade")
guard = bpy.data.objects.get("Guard")
grip = bpy.data.objects.get("Grip")
pommel = bpy.data.objects.get("Pommel")

required = {
    ASSET_COLLECTION: asset_col,
    ROOT_NAME: root,
    "Blade": blade,
    "Guard": guard,
    "Grip": grip,
    "Pommel": pommel,
    "blade_tip": bpy.data.objects.get("blade_tip"),
    "blade_mid": bpy.data.objects.get("blade_mid"),
    "hilt": bpy.data.objects.get("hilt"),
    "cutting_edge_center": bpy.data.objects.get(
        "cutting_edge_center"
    ),
}

missing = [
    name
    for name, value in required.items()
    if value is None
]

if missing:
    raise RuntimeError(
        "SEKAI FP Sword blockout missing: "
        + ", ".join(missing)
    )


# ------------------------------------------------------------
# Correct all materials
# ------------------------------------------------------------

steel_mat = ensure_material(
    "MAT_Sword_Steel",
    base_color=(0.24, 0.28, 0.31),
    metallic=0.88,
    roughness=0.24
)

grip_mat = ensure_material(
    "MAT_Sword_Grip",
    base_color=(0.028, 0.032, 0.038),
    metallic=0.02,
    roughness=0.68
)

fittings_mat = ensure_material(
    "MAT_Sword_Fittings",
    base_color=(0.25, 0.145, 0.065),
    metallic=0.82,
    roughness=0.34
)

inlay_mat = ensure_material(
    "MAT_Sword_Inlay",
    base_color=(0.025, 0.095, 0.105),
    metallic=0.20,
    roughness=0.36,
    emission_color=(0.035, 0.19, 0.21),
    emission_strength=0.22
)

assign_single_material(blade, steel_mat)
assign_single_material(guard, fittings_mat)
assign_single_material(grip, grip_mat)
assign_single_material(pommel, fittings_mat)


# ------------------------------------------------------------
# Blade refinement
#
# Cross section:
#
# cutting edge (-X)
#       /
#      /___ ridge
#          \__
#             spine (+X)
#
# Gives strong close-range light breakup without making
# the sword broad or oversized.
# ------------------------------------------------------------

blade_sections = [
    # y,      cutting x, spine x, thickness factor
    (0.130,  -0.0310,    0.0230, 1.00),
    (0.250,  -0.0300,    0.0225, 1.00),
    (0.400,  -0.0278,    0.0212, 0.98),
    (0.580,  -0.0238,    0.0193, 0.94),
    (0.720,  -0.0190,    0.0163, 0.82),
    (0.835,  -0.0100,    0.0105, 0.55),
    (0.890,  -0.0040,    0.0045, 0.28),
    (0.910,  -0.0005,    0.0005, 0.12),
]

blade_vertices = []
blade_faces = []

for y, x_cut, x_spine, tf in blade_sections:
    width = x_spine - x_cut

    x_edge = x_cut
    x_shoulder = x_cut + width * 0.245
    x_ridge = x_cut + width * 0.615
    x_spine_edge = x_spine

    z_edge = 0.00022 * tf
    z_shoulder = 0.00245 * tf
    z_ridge = 0.00430 * tf
    z_spine = 0.00300 * tf

    top = [
        (x_edge,       y,  z_edge),
        (x_shoulder,   y,  z_shoulder),
        (x_ridge,      y,  z_ridge),
        (x_spine_edge, y,  z_spine),
    ]

    bottom = [
        (x_edge,       y, -z_edge),
        (x_shoulder,   y, -z_shoulder),
        (x_ridge,      y, -z_ridge),
        (x_spine_edge, y, -z_spine),
    ]

    blade_vertices.extend(top)
    blade_vertices.extend(bottom)


def t(section, column):
    return section * 8 + column


def b(section, column):
    return section * 8 + 4 + column


section_count = len(blade_sections)

for s in range(section_count - 1):
    # Top facets
    for j in range(3):
        blade_faces.append((
            t(s, j),
            t(s, j + 1),
            t(s + 1, j + 1),
            t(s + 1, j),
        ))

    # Bottom facets
    for j in range(3):
        blade_faces.append((
            b(s, j),
            b(s + 1, j),
            b(s + 1, j + 1),
            b(s, j + 1),
        ))

    # Cutting edge wall
    blade_faces.append((
        t(s, 0),
        t(s + 1, 0),
        b(s + 1, 0),
        b(s, 0),
    ))

    # Spine wall
    blade_faces.append((
        t(s, 3),
        b(s, 3),
        b(s + 1, 3),
        t(s + 1, 3),
    ))

# Root cap
for j in range(3):
    blade_faces.append((
        t(0, j),
        b(0, j),
        b(0, j + 1),
        t(0, j + 1),
    ))

# Tip cap
last = section_count - 1
for j in range(3):
    blade_faces.append((
        t(last, j),
        t(last, j + 1),
        b(last, j + 1),
        b(last, j),
    ))

blade_mesh = bpy.data.meshes.new(
    "Blade_Mesh_Detailed"
)

blade_mesh.from_pydata(
    blade_vertices,
    [],
    blade_faces
)

recalc_mesh_normals(blade_mesh)
replace_mesh(blade, blade_mesh)
assign_single_material(blade, steel_mat)

for poly in blade.data.polygons:
    poly.use_smooth = False

create_uv(blade)


# ------------------------------------------------------------
# Guard refinement
#
# Compact forward-swept silhouette:
# tips advance toward +Y but remain restrained.
# ------------------------------------------------------------

guard_outline = [
    (-0.0660, 0.1360),
    (-0.0580, 0.1220),
    (-0.0350, 0.1130),
    (-0.0180, 0.1100),
    ( 0.0180, 0.1100),
    ( 0.0350, 0.1130),
    ( 0.0580, 0.1220),
    ( 0.0660, 0.1360),
    ( 0.0580, 0.1480),
    ( 0.0340, 0.1360),
    ( 0.0160, 0.1280),
    (-0.0160, 0.1280),
    (-0.0340, 0.1360),
    (-0.0580, 0.1480),
]

guard_half_z = 0.0090

guard_vertices = []

for x, y in guard_outline:
    guard_vertices.append(
        (x, y, -guard_half_z)
    )

for x, y in guard_outline:
    guard_vertices.append(
        (x, y, guard_half_z)
    )

guard_n = len(guard_outline)

guard_faces = [
    tuple(reversed(range(guard_n))),
    tuple(range(guard_n, guard_n * 2)),
]

for i in range(guard_n):
    j = (i + 1) % guard_n

    guard_faces.append((
        i,
        j,
        guard_n + j,
        guard_n + i,
    ))

guard_mesh = bpy.data.meshes.new(
    "Guard_Mesh_Detailed"
)

guard_mesh.from_pydata(
    guard_vertices,
    [],
    guard_faces
)

recalc_mesh_normals(guard_mesh)
replace_mesh(guard, guard_mesh)
assign_single_material(guard, fittings_mat)

apply_bevel(
    guard,
    width=0.0022,
    segments=2
)

for poly in guard.data.polygons:
    poly.use_smooth = False

create_uv(guard)


# ------------------------------------------------------------
# Restrained ancient-civilization guard motif
#
# Three broken lozenge glyphs.
# Present on both broadside faces for reverse-cut readability.
# ------------------------------------------------------------

delete_object_if_exists("Guard_Motif")


def add_prism_polygon(
    verts_out,
    faces_out,
    polygon_xy,
    z0,
    z1
):
    start = len(verts_out)
    count = len(polygon_xy)

    for x, y in polygon_xy:
        verts_out.append((x, y, z0))

    for x, y in polygon_xy:
        verts_out.append((x, y, z1))

    faces_out.append(
        tuple(
            start + i
            for i in reversed(range(count))
        )
    )

    faces_out.append(
        tuple(
            start + count + i
            for i in range(count)
        )
    )

    for i in range(count):
        j = (i + 1) % count

        faces_out.append((
            start + i,
            start + j,
            start + count + j,
            start + count + i,
        ))


def diamond(cx, cy, sx, sy):
    return [
        (cx - sx, cy),
        (cx, cy + sy),
        (cx + sx, cy),
        (cx, cy - sy),
    ]


motif_shapes = [
    diamond(
        -0.0260,
        0.1280,
        0.0068,
        0.0031
    ),
    diamond(
        0.0000,
        0.1215,
        0.0042,
        0.0048
    ),
    diamond(
        0.0260,
        0.1280,
        0.0068,
        0.0031
    ),
]

motif_vertices = []
motif_faces = []

# Upper broadside
for shape in motif_shapes:
    add_prism_polygon(
        motif_vertices,
        motif_faces,
        shape,
        0.00905,
        0.00962
    )

# Lower broadside
for shape in motif_shapes:
    add_prism_polygon(
        motif_vertices,
        motif_faces,
        shape,
        -0.00962,
        -0.00905
    )

motif_mesh = bpy.data.meshes.new(
    "Guard_Motif_Mesh"
)

motif_mesh.from_pydata(
    motif_vertices,
    [],
    motif_faces
)

recalc_mesh_normals(motif_mesh)

guard_motif = bpy.data.objects.new(
    "Guard_Motif",
    motif_mesh
)

asset_col.objects.link(guard_motif)
guard_motif.data.materials.append(inlay_mat)

for poly in guard_motif.data.polygons:
    poly.use_smooth = False

create_uv(guard_motif)
parent_keep_transform(
    guard_motif,
    guard
)


# ------------------------------------------------------------
# Final validation / hygiene
# ------------------------------------------------------------

for obj in (
    blade,
    guard,
    grip,
    pommel,
    guard_motif,
):
    if obj.type == 'MESH':
        obj.data.validate(verbose=False)
        obj.data.update()

# Existing gameplay empties and hierarchy remain untouched.
# Existing weapon pivot remains grip centre at (0,0,0).
# Blade still extends along local +Y.
# Cutting edge remains local -X.

select_only(root)

# C2B:END