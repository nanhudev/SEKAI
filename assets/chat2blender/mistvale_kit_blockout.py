# C2B:CHUNK blockout
import bpy
import math
from mathutils import Vector

# ============================================================
# SEKAI / Mistvale Modular Building Kit — Round 1 Blockout
# Blender 4.x / Blender 5.2 compatible
# ============================================================

KIT_COLLECTION_NAME = "SEKAI_MISTVALE_KIT"

# ------------------------------------------------------------
# Scene cleanup
# ------------------------------------------------------------

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

for datablocks in (
    bpy.data.meshes,
    bpy.data.curves,
    bpy.data.cameras,
    bpy.data.lights,
):
    for datablock in list(datablocks):
        if datablock.users == 0:
            datablocks.remove(datablock)

old_collection = bpy.data.collections.get(KIT_COLLECTION_NAME)
if old_collection:
    for obj in list(old_collection.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(old_collection)

kit_collection = bpy.data.collections.new(KIT_COLLECTION_NAME)
bpy.context.scene.collection.children.link(kit_collection)

# ------------------------------------------------------------
# Units
# ------------------------------------------------------------

scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene.unit_settings.length_unit = 'METERS'

# ------------------------------------------------------------
# Material helpers
# Principled BSDF accessed by NODE TYPE, never localized names
# ------------------------------------------------------------

def make_principled_material(name, base_color, roughness=0.7, metallic=0.0):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name=name)

    mat.use_nodes = True

    nt = mat.node_tree
    bsdf = None

    for node in nt.nodes:
        if node.type == 'BSDF_PRINCIPLED':
            bsdf = node
            break

    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")

    base_socket = bsdf.inputs.get("Base Color")
    if base_socket:
        base_socket.default_value = (*base_color, 1.0)

    rough_socket = bsdf.inputs.get("Roughness")
    if rough_socket:
        rough_socket.default_value = roughness

    metallic_socket = bsdf.inputs.get("Metallic")
    if metallic_socket:
        metallic_socket.default_value = metallic

    return mat


MAT_PLASTER = make_principled_material(
    "MST_Plaster_WarmGrey",
    (0.56, 0.54, 0.49),
    0.88
)

MAT_WOOD = make_principled_material(
    "MST_Wood_OldWarm",
    (0.25, 0.115, 0.052),
    0.82
)

MAT_WOOD_DARK = make_principled_material(
    "MST_Wood_Deep",
    (0.105, 0.052, 0.028),
    0.80
)

MAT_ROOF = make_principled_material(
    "MST_Roof_DeepTeal",
    (0.065, 0.145, 0.145),
    0.78
)

MAT_STONE = make_principled_material(
    "MST_Stone_RoughGrey",
    (0.28, 0.285, 0.27),
    0.94
)

MAT_WINDOW = make_principled_material(
    "MST_Window_DarkGlass",
    (0.075, 0.115, 0.12),
    0.34
)

MAT_METAL = make_principled_material(
    "MST_Metal_DarkIron",
    (0.075, 0.07, 0.065),
    0.58,
    0.45
)

MAT_SIGN = make_principled_material(
    "MST_Sign_Wood",
    (0.32, 0.16, 0.065),
    0.82
)


# ------------------------------------------------------------
# Geometry helpers
# ------------------------------------------------------------

def new_mesh_object(name, verts, faces, material=None):
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    kit_collection.objects.link(obj)

    if material is not None:
        obj.data.materials.append(material)

    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)

    return obj


def append_box(verts, faces, center, size):
    cx, cy, cz = center
    sx, sy, sz = size

    hx = sx * 0.5
    hy = sy * 0.5
    hz = sz * 0.5

    start = len(verts)

    verts.extend([
        (cx-hx, cy-hy, cz-hz),
        (cx+hx, cy-hy, cz-hz),
        (cx+hx, cy+hy, cz-hz),
        (cx-hx, cy+hy, cz-hz),
        (cx-hx, cy-hy, cz+hz),
        (cx+hx, cy-hy, cz+hz),
        (cx+hx, cy+hy, cz+hz),
        (cx-hx, cy+hy, cz+hz),
    ])

    faces.extend([
        (start+0, start+3, start+2, start+1),
        (start+4, start+5, start+6, start+7),
        (start+0, start+1, start+5, start+4),
        (start+1, start+2, start+6, start+5),
        (start+2, start+3, start+7, start+6),
        (start+3, start+0, start+4, start+7),
    ])


def boxes_object(name, boxes, material):
    verts = []
    faces = []

    for center, size in boxes:
        append_box(verts, faces, center, size)

    return new_mesh_object(name, verts, faces, material)


def assign_multi_material(obj, materials, face_material_indices=None):
    for mat in materials:
        obj.data.materials.append(mat)

    if face_material_indices:
        for poly, index in zip(obj.data.polygons, face_material_indices):
            poly.material_index = index


def set_object_ground_origin(obj):
    # Geometry is authored relative to Z=0 ground plane.
    # XY origin is already module center.
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)


def apply_transform(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    bpy.ops.object.transform_apply(
        location=False,
        rotation=True,
        scale=True
    )

    obj.select_set(False)


# ------------------------------------------------------------
# Module generators
# ------------------------------------------------------------

def create_wall_plain():
    verts = []
    faces = []

    # Main warm plaster wall
    append_box(verts, faces, (0, 0, 1.50), (3.00, 0.28, 3.00))

    obj = new_mesh_object("WallPlain", verts, faces, MAT_PLASTER)
    return obj


def create_wall_window():
    # Window opening 1.1 x 1.1
    # sill around 0.95 m, opening top 2.05 m
    boxes = [
        ((-1.025, 0, 1.50), (0.95, 0.28, 3.00)),
        (( 1.025, 0, 1.50), (0.95, 0.28, 3.00)),
        ((0, 0, 0.475), (1.10, 0.28, 0.95)),
        ((0, 0, 2.525), (1.10, 0.28, 0.95)),
    ]
    return boxes_object("WallWindow", boxes, MAT_PLASTER)


def create_wall_door():
    # Door opening: 1.15 wide x 2.35 high
    side_w = (3.0 - 1.15) * 0.5

    boxes = [
        ((-(1.15 * 0.5 + side_w * 0.5), 0, 1.50),
         (side_w, 0.28, 3.00)),

        (((1.15 * 0.5 + side_w * 0.5), 0, 1.50),
         (side_w, 0.28, 3.00)),

        ((0, 0, 2.675),
         (1.15, 0.28, 0.65)),
    ]

    return boxes_object("WallDoor", boxes, MAT_PLASTER)


def create_beam():
    # 3 m reusable timber beam
    return boxes_object(
        "Beam",
        [
            ((0, 0, 0.11), (3.00, 0.22, 0.22))
        ],
        MAT_WOOD_DARK
    )


def create_roof_slope():
    # Horizontal projection 3m x 2.2m
    # 35 degree single slope, thickness ~0.18 m
    width_x = 3.0
    depth_y = 2.2
    slope = math.radians(35.0)

    rise = math.tan(slope) * depth_y
    thickness = 0.18

    x0 = -width_x / 2
    x1 =  width_x / 2
    y0 = -depth_y / 2
    y1 =  depth_y / 2

    # Bottom edge starts at z=0.
    # Top face follows slope.
    z_low_bottom = 0.0
    z_high_bottom = rise
    z_low_top = thickness / math.cos(slope)
    z_high_top = rise + thickness / math.cos(slope)

    verts = [
        (x0, y0, z_low_bottom),
        (x1, y0, z_low_bottom),
        (x1, y1, z_high_bottom),
        (x0, y1, z_high_bottom),

        (x0, y0, z_low_top),
        (x1, y0, z_low_top),
        (x1, y1, z_high_top),
        (x0, y1, z_high_top),
    ]

    faces = [
        (0, 3, 2, 1),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
    ]

    return new_mesh_object("RoofSlope", verts, faces, MAT_ROOF)


def create_door():
    # Standalone door, 1.15 x 2.35
    verts = []
    faces = []

    append_box(
        verts,
        faces,
        (0, 0, 1.175),
        (1.15, 0.12, 2.35)
    )

    obj = new_mesh_object("Door", verts, faces, MAT_WOOD)

    # Add visual vertical divisions directly into geometry
    # using shallow battens to avoid flat-box appearance.
    extra_verts = []
    extra_faces = []

    for x in (-0.38, 0.0, 0.38):
        append_box(
            extra_verts,
            extra_faces,
            (x, -0.075, 1.175),
            (0.045, 0.035, 2.15)
        )

    # merge geometry manually
    base_v = list(obj.data.vertices)
    base_f = [tuple(p.vertices) for p in obj.data.polygons]

    verts2 = [tuple(v.co) for v in base_v]
    faces2 = list(base_f)

    offset = len(verts2)
    verts2.extend(extra_verts)
    faces2.extend(
        tuple(i + offset for i in face)
        for face in extra_faces
    )

    old_mesh = obj.data
    mesh = bpy.data.meshes.new("Door_Mesh_Detailed")
    mesh.from_pydata(verts2, [], faces2)
    mesh.update()

    obj.data = mesh
    bpy.data.meshes.remove(old_mesh)

    obj.data.materials.append(MAT_WOOD)
    return obj


def create_window():
    # 1.1m x 1.1m standalone framed window
    w = 1.10
    h = 1.10
    frame = 0.095
    depth = 0.12
    sill_z = 0.0

    boxes = [
        ((-w/2 + frame/2, 0, sill_z + h/2), (frame, depth, h)),
        (( w/2 - frame/2, 0, sill_z + h/2), (frame, depth, h)),
        ((0, 0, sill_z + frame/2), (w, depth, frame)),
        ((0, 0, sill_z + h - frame/2), (w, depth, frame)),
        ((0, 0, sill_z + h/2), (frame*0.65, depth*0.85, h-frame*2)),
        ((0, 0, sill_z + h/2), (w-frame*2, depth*0.85, frame*0.65)),
    ]

    return boxes_object("Window", boxes, MAT_WOOD_DARK)


def create_foundation():
    # Coarse stone foundation block with slightly inset upper step
    boxes = [
        ((0, 0, 0.125), (3.00, 3.00, 0.25)),
        ((0, 0, 0.300), (2.84, 2.84, 0.10)),
    ]

    return boxes_object("Foundation", boxes, MAT_STONE)


def create_fence():
    boxes = []

    # Posts
    for x in (-1.45, 0.0, 1.45):
        boxes.append(
            ((x, 0, 0.50), (0.14, 0.14, 1.00))
        )

    # Two horizontal rails
    boxes.extend([
        ((0, 0, 0.34), (3.00, 0.11, 0.12)),
        ((0, 0, 0.73), (3.00, 0.11, 0.12)),
    ])

    return boxes_object("Fence", boxes, MAT_WOOD_DARK)


def create_stair():
    # Total height exactly 0.35 m
    # 3 chunky low-poly steps
    step_h = 0.35 / 3.0
    step_depth = 0.35
    width = 1.65

    boxes = []

    for i in range(3):
        level = i + 1
        height = step_h * level

        center_y = 0.35 - i * step_depth

        boxes.append(
            (
                (0, center_y, height * 0.5),
                (width, step_depth, height)
            )
        )

    return boxes_object("Stair", boxes, MAT_STONE)


def create_chimney():
    # 1.5m high masonry chimney
    boxes = [
        ((0, 0, 0.70), (0.48, 0.48, 1.40)),
        ((0, 0, 1.445), (0.60, 0.60, 0.11)),
    ]

    return boxes_object("Chimney", boxes, MAT_STONE)


def create_sign():
    # 2 m overall village direction sign
    boxes = [
        ((0, 0, 0.90), (0.12, 0.12, 1.80)),
        ((0.34, 0, 1.68), (0.80, 0.09, 0.26)),
        ((-0.26, 0, 1.93), (0.64, 0.09, 0.22)),
    ]

    return boxes_object("Sign", boxes, MAT_SIGN)


# ------------------------------------------------------------
# Generate modules
# ------------------------------------------------------------

objects = [
    create_wall_plain(),
    create_wall_window(),
    create_wall_door(),
    create_beam(),
    create_roof_slope(),
    create_door(),
    create_window(),
    create_foundation(),
    create_fence(),
    create_stair(),
    create_chimney(),
    create_sign(),
]


# ------------------------------------------------------------
# Add simple wood trim to main wall modules as same named meshes
# by merging separate boxes into existing meshes
# ------------------------------------------------------------

def merge_boxes_into_object(obj, boxes):
    old_verts = [tuple(v.co) for v in obj.data.vertices]
    old_faces = [tuple(p.vertices) for p in obj.data.polygons]

    new_verts = []
    new_faces = []

    for center, size in boxes:
        append_box(new_verts, new_faces, center, size)

    offset = len(old_verts)

    merged_verts = old_verts + new_verts
    merged_faces = old_faces + [
        tuple(i + offset for i in face)
        for face in new_faces
    ]

    old_mesh = obj.data

    mesh = bpy.data.meshes.new(f"{obj.name}_Mesh_Final")
    mesh.from_pydata(merged_verts, [], merged_faces)
    mesh.update()

    obj.data = mesh

    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)


wall_plain = bpy.data.objects.get("WallPlain")
merge_boxes_into_object(
    wall_plain,
    [
        ((-1.42, -0.17, 1.50), (0.14, 0.10, 3.00)),
        (( 1.42, -0.17, 1.50), (0.14, 0.10, 3.00)),
        ((0, -0.17, 2.91), (3.00, 0.10, 0.14)),
        ((0, -0.17, 0.09), (3.00, 0.10, 0.18)),
    ]
)

wall_window = bpy.data.objects.get("WallWindow")
merge_boxes_into_object(
    wall_window,
    [
        ((-1.42, -0.17, 1.50), (0.14, 0.10, 3.00)),
        (( 1.42, -0.17, 1.50), (0.14, 0.10, 3.00)),
        ((-0.61, -0.17, 1.50), (0.12, 0.10, 1.24)),
        (( 0.61, -0.17, 1.50), (0.12, 0.10, 1.24)),
        ((0, -0.17, 0.89), (1.34, 0.10, 0.12)),
        ((0, -0.17, 2.11), (1.34, 0.10, 0.12)),
    ]
)

wall_door = bpy.data.objects.get("WallDoor")
merge_boxes_into_object(
    wall_door,
    [
        ((-1.42, -0.17, 1.50), (0.14, 0.10, 3.00)),
        (( 1.42, -0.17, 1.50), (0.14, 0.10, 3.00)),
        ((-0.635, -0.17, 1.175), (0.12, 0.10, 2.35)),
        (( 0.635, -0.17, 1.175), (0.12, 0.10, 2.35)),
        ((0, -0.17, 2.41), (1.39, 0.10, 0.12)),
    ]
)

# Re-add plaster material if necessary after merge
for obj_name in ("WallPlain", "WallWindow", "WallDoor"):
    obj = bpy.data.objects[obj_name]
    if MAT_PLASTER.name not in [m.name for m in obj.data.materials]:
        obj.data.materials.append(MAT_PLASTER)


# ------------------------------------------------------------
# Placement grid for visible validation
# ------------------------------------------------------------

layout = {
    "WallPlain":   (-6.0,  4.0, 0.0),
    "WallWindow":  (-2.0,  4.0, 0.0),
    "WallDoor":    ( 2.0,  4.0, 0.0),
    "RoofSlope":   ( 6.0,  4.0, 0.0),

    "Foundation":  (-6.0,  0.0, 0.0),
    "Door":        (-2.0,  0.0, 0.0),
    "Window":      ( 2.0,  0.0, 0.0),
    "Beam":        ( 6.0,  0.0, 0.0),

    "Fence":       (-6.0, -4.0, 0.0),
    "Stair":       (-2.0, -4.0, 0.0),
    "Chimney":     ( 2.0, -4.0, 0.0),
    "Sign":        ( 6.0, -4.0, 0.0),
}

for obj in objects:
    pos = layout[obj.name]
    obj.location = pos

    set_object_ground_origin(obj)

    # Keep location as module placement but ensure rotation/scale are applied.
    apply_transform(obj)


# ------------------------------------------------------------
# Useful custom properties for downstream Three.js pipeline
# ------------------------------------------------------------

dimensions_meta = {
    "WallPlain":  "3x0.28x3",
    "WallWindow": "3x0.28x3_Window1.1x1.1",
    "WallDoor":   "3x0.28x3_DoorOpening1.15x2.35",
    "Beam":       "3m",
    "RoofSlope":  "Projection3x2.2_Slope35deg",
    "Door":       "1.15x2.35",
    "Window":     "1.1x1.1",
    "Foundation": "3x3x0.35",
    "Fence":      "3m_Length_1m_Height",
    "Stair":      "0.35m_TotalRise",
    "Chimney":    "1.5m_Height",
    "Sign":       "2m_Height",
}

collision_types = {
    "WallPlain": "BOX_SIMPLIFIED",
    "WallWindow": "BOX_SIMPLIFIED",
    "WallDoor": "BOX_SIMPLIFIED",
    "Beam": "NONE_OR_BOX",
    "RoofSlope": "BOX_SIMPLIFIED",
    "Door": "BOX_SIMPLIFIED",
    "Window": "NONE",
    "Foundation": "BOX",
    "Fence": "BOX_SIMPLIFIED",
    "Stair": "BOX_STEPS",
    "Chimney": "BOX",
    "Sign": "NONE_OR_BOX",
}

for obj in objects:
    obj["sekai_asset"] = "Mistvale Modular Building Kit"
    obj["sekai_round"] = 1
    obj["sekai_module"] = obj.name
    obj["dimensions_m"] = dimensions_meta[obj.name]
    obj["collision_hint"] = collision_types[obj.name]
    obj["lod_level"] = "LOD0"
    obj["glb_ready"] = True


# ------------------------------------------------------------
# Smooth/shading policy
# Blockout is intentionally hard-surface / faceted.
# ------------------------------------------------------------

for obj in objects:
    if obj.type == 'MESH':
        for poly in obj.data.polygons:
            poly.use_smooth = False


# ------------------------------------------------------------
# Ground-reference labels using empty objects
# (No text meshes: keeps kit geometry clean.)
# ------------------------------------------------------------

for obj in objects:
    empty = bpy.data.objects.new(f"MARKER_{obj.name}", None)
    kit_collection.objects.link(empty)
    empty.empty_display_type = 'PLAIN_AXES'
    empty.empty_display_size = 0.20
    empty.location = (
        obj.location.x,
        obj.location.y,
        obj.location.z
    )
    empty.hide_render = True


# ------------------------------------------------------------
# Selection
# ------------------------------------------------------------

bpy.ops.object.select_all(action='DESELECT')

for obj in objects:
    obj.select_set(True)

if objects:
    bpy.context.view_layer.objects.active = objects[0]


# ------------------------------------------------------------
# Triangle estimate
# ------------------------------------------------------------

triangle_count = 0

for obj in objects:
    if obj.type != 'MESH':
        continue

    obj.data.calc_loop_triangles()
    triangle_count += len(obj.data.loop_triangles)


# ------------------------------------------------------------
# Viewport framing
# ------------------------------------------------------------

def frame_all_viewports():
    for window in bpy.context.window_manager.windows:
        screen = window.screen

        for area in screen.areas:
            if area.type != 'VIEW_3D':
                continue

            region = None
            for candidate in area.regions:
                if candidate.type == 'WINDOW':
                    region = candidate
                    break

            if region is None:
                continue

            space = area.spaces.active

            try:
                with bpy.context.temp_override(
                    window=window,
                    screen=screen,
                    area=area,
                    region=region,
                    space_data=space,
                ):
                    bpy.ops.view3d.view_selected(use_all_regions=False)

                # Friendly elevated perspective
                if getattr(space, "region_3d", None):
                    rv3d = space.region_3d
                    rv3d.view_distance = max(rv3d.view_distance, 16.5)
                    rv3d.view_location = Vector((0.0, 0.0, 1.2))

            except Exception:
                pass


frame_all_viewports()


# ------------------------------------------------------------
# Final validation
# ------------------------------------------------------------

mesh_objects = [
    obj for obj in kit_collection.objects
    if obj.type == 'MESH'
]

print("=" * 64)
print("SEKAI / MISTVALE MODULAR BUILDING KIT — ROUND 1 BLOCKOUT")
print(f"Collection: {KIT_COLLECTION_NAME}")
print(f"Mesh module objects: {len(mesh_objects)}")
print(f"Estimated triangles: {triangle_count}")
print("Triangle budget target: <= 25,000")
print(f"Budget status: {'OK' if triangle_count <= 25000 else 'OVER BUDGET'}")
print("Modules:")
for obj in objects:
    obj.data.calc_loop_triangles()
    print(
        f"  - {obj.name:12s} | "
        f"{len(obj.data.vertices):4d} verts | "
        f"{len(obj.data.loop_triangles):4d} tris | "
        f"scale={tuple(round(v, 3) for v in obj.scale)}"
    )
print("=" * 64)

# C2B:END
