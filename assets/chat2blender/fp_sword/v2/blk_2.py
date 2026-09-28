```python
# C2B:CHUNK blockout

import bpy
import math
from mathutils import Matrix

ASSET_COLLECTION = "SEKAI_FP_SWORD"
ROOT_NAME = "FP_Sword_Root"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

def ensure_object_mode():
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')


def delete_collection_if_exists(name):
    col = bpy.data.collections.get(name)
    if not col:
        return

    for obj in list(col.all_objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    for child in list(col.children):
        bpy.data.collections.remove(child)

    bpy.data.collections.remove(col)


def make_collection(name):
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


def move_to_collection(obj, collection):
    for col in list(obj.users_collection):
        col.objects.unlink(obj)
    collection.objects.link(obj)


def make_material(name, base_color, metallic=0.0, roughness=0.5):
    existing = bpy.data.materials.get(name)
    if existing:
        bpy.data.materials.remove(existing)

    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*base_color, 1.0)

    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness

    return mat


def select_only(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_all_transforms(obj):
    select_only(obj)
    bpy.ops.object.transform_apply(
        location=True,
        rotation=True,
        scale=True
    )


def bevel_object(obj, width, segments=2):
    mod = obj.modifiers.new(name="Blockout_Bevel", type='BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'

    if hasattr(mod, "harden_normals"):
        mod.harden_normals = True

    select_only(obj)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def recalc_normals_and_uv(obj):
    if obj.type != 'MESH':
        return

    select_only(obj)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False) if hasattr(
        bpy.ops.mesh, "normals_make_consistent"
    ) else None

    if len(obj.data.uv_layers) == 0:
        obj.data.uv_layers.new(name="UVMap")

    try:
        bpy.ops.uv.smart_project(
            angle_limit=math.radians(66.0),
            island_margin=0.02
        )
    except Exception:
        pass

    bpy.ops.object.mode_set(mode='OBJECT')
    obj.data.validate(verbose=False)
    obj.data.update()


def parent_keep_transform(obj, parent):
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world


def create_empty(name, location, parent, collection, display_type='SPHERE', size=0.022):
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.empty_display_type = display_type
    obj.empty_display_size = size
    obj.location = location
    obj.parent = parent
    return obj


# ------------------------------------------------------------
# Scene / collection setup
# ------------------------------------------------------------

ensure_object_mode()

scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0

delete_collection_if_exists(ASSET_COLLECTION)
asset_col = make_collection(ASSET_COLLECTION)

steel_mat = make_material(
    "MAT_Sword_Steel",
    (0.24, 0.28, 0.31),
    metallic=0.88,
    roughness=0.24
)

grip_mat = make_material(
    "MAT_Sword_Grip",
    (0.028, 0.032, 0.038),
    metallic=0.02,
    roughness=0.68
)

fittings_mat = make_material(
    "MAT_Sword_Fittings",
    (0.25, 0.145, 0.065),
    metallic=0.82,
    roughness=0.34
)

root = bpy.data.objects.new(ROOT_NAME, None)
asset_col.objects.link(root)
root.empty_display_type = 'PLAIN_AXES'
root.empty_display_size = 0.07
root.location = (0.0, 0.0, 0.0)
root.rotation_euler = (0.0, 0.0, 0.0)
root.scale = (1.0, 1.0, 1.0)

root["asset_id"] = "C2B-01"
root["asset_name"] = "First Person Sword"
root["forward_axis"] = "+Y"
root["cutting_edge_axis"] = "-X"
root["pivot"] = "grip_center"
root["total_length_m"] = 1.05
root["blade_length_m"] = 0.78
root["grip_length_m"] = 0.22


# ------------------------------------------------------------
# Blade
#
# Blade root: Y = 0.13
# Blade tip : Y = 0.91
# Length    : 0.78 m
#
# Cutting edge is the -X silhouette.
# ------------------------------------------------------------

blade_outline = [
    (-0.0310, 0.1300),
    ( 0.0230, 0.1300),
    ( 0.0210, 0.3800),
    ( 0.0180, 0.6700),
    ( 0.0100, 0.8350),
    ( 0.0000, 0.9100),
    (-0.0090, 0.8400),
    (-0.0175, 0.6750),
    (-0.0250, 0.3900),
]

half_thickness = 0.0038

blade_verts = []
for x, y in blade_outline:
    blade_verts.append((x, y, -half_thickness))
for x, y in blade_outline:
    blade_verts.append((x, y, half_thickness))

n = len(blade_outline)

blade_faces = []

# Bottom face
blade_faces.append(tuple(reversed(range(n))))

# Top face
blade_faces.append(tuple(range(n, n * 2)))

# Side walls
for i in range(n):
    j = (i + 1) % n
    blade_faces.append((
        i,
        j,
        n + j,
        n + i
    ))

blade_mesh = bpy.data.meshes.new("Blade_Mesh")
blade_mesh.from_pydata(blade_verts, [], blade_faces)
blade_mesh.update()

blade = bpy.data.objects.new("Blade", blade_mesh)
asset_col.objects.link(blade)
blade.data.materials.append(steel_mat)

bevel_object(blade, width=0.00115, segments=2)
recalc_normals_and_uv(blade)
parent_keep_transform(blade, root)


# ------------------------------------------------------------
# Guard
# Compact forward-readable guard.
# Width 0.128 m, deliberately restrained.
# ------------------------------------------------------------

bpy.ops.mesh.primitive_cube_add(
    size=1.0,
    location=(0.0, 0.1200, 0.0)
)
guard = bpy.context.object
guard.name = "Guard"
move_to_collection(guard, asset_col)

guard.dimensions = (0.128, 0.020, 0.018)
apply_all_transforms(guard)

bevel_object(guard, width=0.0055, segments=3)
guard.data.materials.append(fittings_mat)

recalc_normals_and_uv(guard)
parent_keep_transform(guard, root)


# ------------------------------------------------------------
# Grip
# Exactly 0.22 m long, centered on world origin.
# This establishes the weapon pivot / future hand alignment.
# ------------------------------------------------------------

bpy.ops.mesh.primitive_cylinder_add(
    vertices=16,
    radius=0.0178,
    depth=0.220,
    location=(0.0, 0.0, 0.0),
    rotation=(math.radians(90.0), 0.0, 0.0)
)

grip = bpy.context.object
grip.name = "Grip"
move_to_collection(grip, asset_col)

# Slightly oval in Z for a more blade-aware grip orientation.
grip.scale = (1.0, 1.0, 0.88)
apply_all_transforms(grip)

bevel_object(grip, width=0.0012, segments=2)
grip.data.materials.append(grip_mat)

recalc_normals_and_uv(grip)
parent_keep_transform(grip, root)


# ------------------------------------------------------------
# Pommel
# Y range: -0.14 to -0.11
# Combined overall weapon length:
# 0.91 - (-0.14) = 1.05 m
# ------------------------------------------------------------

bpy.ops.mesh.primitive_cylinder_add(
    vertices=12,
    radius=0.0220,
    depth=0.030,
    location=(0.0, -0.125, 0.0),
    rotation=(math.radians(90.0), 0.0, 0.0)
)

pommel = bpy.context.object
pommel.name = "Pommel"
move_to_collection(pommel, asset_col)

pommel.scale = (1.0, 1.0, 0.82)
apply_all_transforms(pommel)

bevel_object(pommel, width=0.0038, segments=3)
pommel.data.materials.append(fittings_mat)

recalc_normals_and_uv(pommel)
parent_keep_transform(pommel, root)


# ------------------------------------------------------------
# Gameplay / alignment markers
# ------------------------------------------------------------

blade_tip = create_empty(
    "blade_tip",
    (0.0, 0.910, 0.0),
    root,
    asset_col,
    display_type='SPHERE',
    size=0.018
)

blade_mid = create_empty(
    "blade_mid",
    (0.0, 0.520, 0.0),
    root,
    asset_col,
    display_type='SPHERE',
    size=0.018
)

hilt = create_empty(
    "hilt",
    (0.0, 0.0, 0.0),
    root,
    asset_col,
    display_type='CIRCLE',
    size=0.025
)

cutting_edge_center = create_empty(
    "cutting_edge_center",
    (-0.0215, 0.520, 0.0),
    root,
    asset_col,
    display_type='SPHERE',
    size=0.015
)


# ------------------------------------------------------------
# Final hygiene
# ------------------------------------------------------------

for obj in (blade, guard, grip, pommel):
    # Geometry is already baked relative to grip-center root.
    obj.rotation_mode = 'XYZ'

    for poly in obj.data.polygons:
        poly.use_smooth = False

    obj.data.validate(verbose=False)
    obj.data.update()

root.location = (0.0, 0.0, 0.0)
root.rotation_euler = (0.0, 0.0, 0.0)
root.scale = (1.0, 1.0, 1.0)

select_only(root)

# C2B:END
```