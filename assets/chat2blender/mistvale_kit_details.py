# C2B:CHUNK details
import bpy
import math
from mathutils import Matrix, Vector

# ============================================================
# SEKAI / Mistvale Modular Building Kit
# Round 1 — Detail Pass
# Blender 4.x / 5.2 compatible
# Works on existing 12 named mesh objects.
# ============================================================

COLLECTION_NAME = "SEKAI_MISTVALE_KIT"

MODULE_NAMES = (
    "WallPlain",
    "WallWindow",
    "WallDoor",
    "Beam",
    "RoofSlope",
    "Door",
    "Window",
    "Foundation",
    "Fence",
    "Stair",
    "Chimney",
    "Sign",
)

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

kit = bpy.data.collections.get(COLLECTION_NAME)
if kit is None:
    raise RuntimeError(
        f"Required collection '{COLLECTION_NAME}' was not found."
    )

objs = {}
for name in MODULE_NAMES:
    obj = bpy.data.objects.get(name)
    if obj is None or obj.type != 'MESH':
        raise RuntimeError(f"Required mesh object '{name}' was not found.")
    objs[name] = obj


# ------------------------------------------------------------
# Existing materials only
# ------------------------------------------------------------

def get_mat(name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        raise RuntimeError(
            f"Existing material '{name}' not found. "
            "Run the blockout chunk first."
        )
    return mat


MAT_PLASTER = get_mat("MST_Plaster_WarmGrey")
MAT_WOOD = get_mat("MST_Wood_OldWarm")
MAT_WOOD_DARK = get_mat("MST_Wood_Deep")
MAT_ROOF = get_mat("MST_Roof_DeepTeal")
MAT_STONE = get_mat("MST_Stone_RoughGrey")
MAT_WINDOW = get_mat("MST_Window_DarkGlass")
MAT_METAL = get_mat("MST_Metal_DarkIron")
MAT_SIGN = get_mat("MST_Sign_Wood")


# ------------------------------------------------------------
# Mesh editing helper
# Rebuilds each existing object data while preserving object,
# origin, location and scale.
# ------------------------------------------------------------

class MeshBuilder:
    def __init__(self, obj):
        self.obj = obj

        self.verts = [tuple(v.co) for v in obj.data.vertices]
        self.faces = [tuple(p.vertices) for p in obj.data.polygons]
        self.face_mats = [p.material_index for p in obj.data.polygons]

        self.materials = []
        for mat in obj.data.materials:
            self.materials.append(mat)

    def mat_index(self, mat):
        for i, existing in enumerate(self.materials):
            if existing == mat:
                return i
        self.materials.append(mat)
        return len(self.materials) - 1

    def add_box(
        self,
        center,
        size,
        mat,
        rotation=(0.0, 0.0, 0.0),
    ):
        cx, cy, cz = center
        sx, sy, sz = size

        hx = sx * 0.5
        hy = sy * 0.5
        hz = sz * 0.5

        local = [
            Vector((-hx, -hy, -hz)),
            Vector(( hx, -hy, -hz)),
            Vector(( hx,  hy, -hz)),
            Vector((-hx,  hy, -hz)),
            Vector((-hx, -hy,  hz)),
            Vector(( hx, -hy,  hz)),
            Vector(( hx,  hy,  hz)),
            Vector((-hx,  hy,  hz)),
        ]

        rot = (
            Matrix.Rotation(rotation[2], 4, 'Z')
            @ Matrix.Rotation(rotation[1], 4, 'Y')
            @ Matrix.Rotation(rotation[0], 4, 'X')
        )

        offset = len(self.verts)

        for co in local:
            p = rot @ co
            self.verts.append(
                (
                    p.x + cx,
                    p.y + cy,
                    p.z + cz,
                )
            )

        new_faces = [
            (0, 3, 2, 1),
            (4, 5, 6, 7),
            (0, 1, 5, 4),
            (1, 2, 6, 5),
            (2, 3, 7, 6),
            (3, 0, 4, 7),
        ]

        mi = self.mat_index(mat)

        for f in new_faces:
            self.faces.append(tuple(offset + i for i in f))
            self.face_mats.append(mi)

    def add_pyramid(
        self,
        center,
        base_size,
        height,
        mat,
    ):
        cx, cy, cz = center
        sx, sy = base_size

        hx = sx * 0.5
        hy = sy * 0.5

        offset = len(self.verts)

        self.verts.extend([
            (cx-hx, cy-hy, cz),
            (cx+hx, cy-hy, cz),
            (cx+hx, cy+hy, cz),
            (cx-hx, cy+hy, cz),
            (cx,    cy,    cz+height),
        ])

        fs = [
            (0, 3, 2, 1),
            (0, 1, 4),
            (1, 2, 4),
            (2, 3, 4),
            (3, 0, 4),
        ]

        mi = self.mat_index(mat)
        for f in fs:
            self.faces.append(tuple(offset + i for i in f))
            self.face_mats.append(mi)

    def add_xz_extrusion(
        self,
        points_xz,
        depth,
        mat,
        y_center=0.0,
    ):
        """
        Extrudes an ordered XZ polygon along Y.
        Useful for low-poly sign arrows / decorative silhouette.
        """
        n = len(points_xz)
        if n < 3:
            return

        y0 = y_center - depth * 0.5
        y1 = y_center + depth * 0.5

        offset = len(self.verts)

        for x, z in points_xz:
            self.verts.append((x, y0, z))

        for x, z in points_xz:
            self.verts.append((x, y1, z))

        mi = self.mat_index(mat)

        # front/back
        self.faces.append(
            tuple(offset + i for i in range(n-1, -1, -1))
        )
        self.face_mats.append(mi)

        self.faces.append(
            tuple(offset + n + i for i in range(n))
        )
        self.face_mats.append(mi)

        # sides
        for i in range(n):
            j = (i + 1) % n
            self.faces.append((
                offset + i,
                offset + j,
                offset + n + j,
                offset + n + i,
            ))
            self.face_mats.append(mi)

    def commit(self):
        old_mesh = self.obj.data

        new_mesh = bpy.data.meshes.new(
            f"{self.obj.name}_Mesh_Details"
        )
        new_mesh.from_pydata(
            self.verts,
            [],
            self.faces
        )
        new_mesh.update()

        for mat in self.materials:
            new_mesh.materials.append(mat)

        for poly, mi in zip(new_mesh.polygons, self.face_mats):
            if mi < len(new_mesh.materials):
                poly.material_index = mi
            poly.use_smooth = False

        self.obj.data = new_mesh

        if old_mesh.users == 0:
            bpy.data.meshes.remove(old_mesh)


# ------------------------------------------------------------
# Convenience: diagonal timber in X/Z plane
# ------------------------------------------------------------

def add_xz_beam(
    builder,
    start,
    end,
    depth,
    width,
    mat,
    y=-0.205,
):
    x1, z1 = start
    x2, z2 = end

    dx = x2 - x1
    dz = z2 - z1

    length = math.sqrt(dx*dx + dz*dz)
    angle = -math.atan2(dz, dx)

    builder.add_box(
        center=(
            (x1+x2)*0.5,
            y,
            (z1+z2)*0.5,
        ),
        size=(length, depth, width),
        mat=mat,
        rotation=(0.0, angle, 0.0),
    )


# ============================================================
# WALL PLAIN
# ============================================================

b = MeshBuilder(objs["WallPlain"])

# Dark timber perimeter
b.add_box((-1.405, -0.205, 1.50), (0.19, 0.13, 3.00), MAT_WOOD_DARK)
b.add_box(( 1.405, -0.205, 1.50), (0.19, 0.13, 3.00), MAT_WOOD_DARK)
b.add_box((0.0, -0.205, 2.90), (3.00, 0.13, 0.20), MAT_WOOD_DARK)
b.add_box((0.0, -0.205, 0.12), (3.00, 0.13, 0.24), MAT_WOOD_DARK)

# Central structural post
b.add_box((0.0, -0.205, 1.50), (0.16, 0.13, 2.75), MAT_WOOD)

# Slight plaster relief panels
b.add_box((-0.72, -0.166, 1.52), (1.18, 0.035, 2.37), MAT_PLASTER)
b.add_box(( 0.72, -0.166, 1.52), (1.18, 0.035, 2.37), MAT_PLASTER)

# Asymmetric countryside braces
add_xz_beam(
    b,
    (-1.29, 0.31),
    (-0.10, 1.15),
    0.12,
    0.13,
    MAT_WOOD,
)
add_xz_beam(
    b,
    (0.10, 1.76),
    (1.29, 2.66),
    0.12,
    0.13,
    MAT_WOOD,
)

# Low stone moisture course
b.add_box((0, 0.0, 0.08), (2.74, 0.34, 0.16), MAT_STONE)

b.commit()


# ============================================================
# WALL WINDOW
# ============================================================

b = MeshBuilder(objs["WallWindow"])

# Structural perimeter
b.add_box((-1.405, -0.205, 1.50), (0.19, 0.13, 3.00), MAT_WOOD_DARK)
b.add_box(( 1.405, -0.205, 1.50), (0.19, 0.13, 3.00), MAT_WOOD_DARK)
b.add_box((0, -0.205, 2.90), (3.00, 0.13, 0.20), MAT_WOOD_DARK)
b.add_box((0, -0.205, 0.12), (3.00, 0.13, 0.24), MAT_WOOD_DARK)

# Window surround
b.add_box((-0.625, -0.215, 1.50), (0.15, 0.15, 1.35), MAT_WOOD_DARK)
b.add_box(( 0.625, -0.215, 1.50), (0.15, 0.15, 1.35), MAT_WOOD_DARK)
b.add_box((0, -0.215, 2.115), (1.40, 0.15, 0.15), MAT_WOOD_DARK)
b.add_box((0, -0.230, 0.885), (1.48, 0.20, 0.17), MAT_WOOD)

# Glass readable from front
b.add_box((0, -0.145, 1.50), (1.02, 0.035, 1.02), MAT_WINDOW)

# Window muntins
b.add_box((0, -0.245, 1.50), (0.075, 0.09, 1.05), MAT_WOOD)
b.add_box((0, -0.245, 1.50), (1.05, 0.09, 0.075), MAT_WOOD)

# Side braces
add_xz_beam(
    b,
    (-1.28, 0.31),
    (-0.76, 0.92),
    0.12,
    0.12,
    MAT_WOOD,
)
add_xz_beam(
    b,
    (0.76, 2.06),
    (1.28, 2.68),
    0.12,
    0.12,
    MAT_WOOD,
)

# Plaster depth
b.add_box((-1.00, -0.162, 1.55), (0.55, 0.03, 2.35), MAT_PLASTER)
b.add_box(( 1.00, -0.162, 1.55), (0.55, 0.03, 2.35), MAT_PLASTER)

b.commit()


# ============================================================
# WALL DOOR
# ============================================================

b = MeshBuilder(objs["WallDoor"])

# Perimeter timber
b.add_box((-1.405, -0.205, 1.50), (0.19, 0.13, 3.00), MAT_WOOD_DARK)
b.add_box(( 1.405, -0.205, 1.50), (0.19, 0.13, 3.00), MAT_WOOD_DARK)
b.add_box((0, -0.205, 2.90), (3.00, 0.13, 0.20), MAT_WOOD_DARK)
b.add_box((0, -0.205, 0.12), (3.00, 0.13, 0.24), MAT_WOOD_DARK)

# Strong portal frame
b.add_box((-0.665, -0.225, 1.175), (0.18, 0.17, 2.35), MAT_WOOD_DARK)
b.add_box(( 0.665, -0.225, 1.175), (0.18, 0.17, 2.35), MAT_WOOD_DARK)
b.add_box((0, -0.225, 2.415), (1.50, 0.17, 0.18), MAT_WOOD_DARK)

# Projecting lintel
b.add_box((0, -0.255, 2.52), (1.72, 0.25, 0.14), MAT_WOOD)

# Side braces
add_xz_beam(
    b,
    (-1.28, 0.31),
    (-0.78, 0.91),
    0.12,
    0.13,
    MAT_WOOD,
)
add_xz_beam(
    b,
    (0.78, 0.91),
    (1.28, 0.31),
    0.12,
    0.13,
    MAT_WOOD,
)

# Slight upper plaster relief
b.add_box((-1.02, -0.163, 1.78), (0.48, 0.03, 1.77), MAT_PLASTER)
b.add_box(( 1.02, -0.163, 1.78), (0.48, 0.03, 1.77), MAT_PLASTER)

b.commit()


# ============================================================
# BEAM
# ============================================================

b = MeshBuilder(objs["Beam"])

# Offset iron straps make it read as reusable structural timber
for x in (-1.00, 0.0, 1.00):
    b.add_box(
        (x, -0.125, 0.11),
        (0.075, 0.035, 0.25),
        MAT_METAL
    )

# Small irregular-looking secondary wood strips
b.add_box((0, 0.125, 0.050), (2.72, 0.045, 0.055), MAT_WOOD)
b.add_box((0.15, -0.125, 0.175), (2.35, 0.04, 0.045), MAT_WOOD)

b.commit()


# ============================================================
# ROOF SLOPE
# ============================================================

b = MeshBuilder(objs["RoofSlope"])

slope = math.radians(35.0)
depth = 2.2
rise = math.tan(slope) * depth

# Main eave edge
b.add_box(
    (0, -1.16, 0.075),
    (3.25, 0.24, 0.16),
    MAT_WOOD_DARK
)

# Upper ridge backing
b.add_box(
    (0, 1.105, rise + 0.105),
    (3.18, 0.16, 0.17),
    MAT_WOOD_DARK,
    rotation=(slope, 0, 0),
)

# Long tile ribs / battens
for x in (-1.30, -0.86, -0.43, 0.0, 0.43, 0.86, 1.30):
    b.add_box(
        center=(x, 0.0, rise * 0.5 + 0.155),
        size=(0.085, 2.34, 0.075),
        mat=MAT_ROOF,
        rotation=(slope, 0.0, 0.0),
    )

# Broad horizontal tile courses.
# Low count = visible rhythm without dense tessellation.
for y in (-0.72, -0.24, 0.24, 0.72):
    z = math.tan(slope) * (y + 1.1) + 0.185
    b.add_box(
        center=(0, y, z),
        size=(3.12, 0.105, 0.075),
        mat=MAT_ROOF,
        rotation=(slope, 0.0, 0.0),
    )

# Slight deep teal fascia under eave
b.add_box(
    (0, -1.205, 0.145),
    (3.18, 0.10, 0.23),
    MAT_ROOF
)

# Exposed support tails
for x in (-1.22, -0.61, 0.0, 0.61, 1.22):
    b.add_box(
        (x, -1.06, 0.0),
        (0.09, 0.42, 0.13),
        MAT_WOOD_DARK,
        rotation=(slope, 0, 0)
    )

b.commit()


# ============================================================
# DOOR
# ============================================================

b = MeshBuilder(objs["Door"])

# Outer frame / rails
b.add_box((-0.515, -0.095, 1.175), (0.10, 0.08, 2.25), MAT_WOOD_DARK)
b.add_box(( 0.515, -0.095, 1.175), (0.10, 0.08, 2.25), MAT_WOOD_DARK)

b.add_box((0, -0.095, 2.285), (1.10, 0.08, 0.105), MAT_WOOD_DARK)
b.add_box((0, -0.095, 1.55), (1.02, 0.07, 0.09), MAT_WOOD)
b.add_box((0, -0.095, 0.57), (1.02, 0.07, 0.11), MAT_WOOD_DARK)

# Diagonal countryside brace
add_xz_beam(
    b,
    (-0.43, 0.68),
    (0.43, 1.42),
    0.07,
    0.10,
    MAT_WOOD_DARK,
    y=-0.103,
)

# Small iron handle + plate, box-only
b.add_box((0.39, -0.132, 1.13), (0.07, 0.035, 0.22), MAT_METAL)
b.add_box((0.34, -0.153, 1.13), (0.13, 0.035, 0.055), MAT_METAL)

b.commit()


# ============================================================
# WINDOW
# ============================================================

b = MeshBuilder(objs["Window"])

# Full glass panel behind frame
b.add_box(
    (0, 0.035, 0.55),
    (0.94, 0.035, 0.94),
    MAT_WINDOW
)

# Strong outer wooden trim
b.add_box((-0.505, -0.07, 0.55), (0.10, 0.12, 1.10), MAT_WOOD_DARK)
b.add_box(( 0.505, -0.07, 0.55), (0.10, 0.12, 1.10), MAT_WOOD_DARK)
b.add_box((0, -0.07, 1.055), (1.10, 0.12, 0.10), MAT_WOOD_DARK)
b.add_box((0, -0.09, 0.045), (1.22, 0.18, 0.09), MAT_WOOD)

# Muntins
b.add_box((0, -0.085, 0.55), (0.065, 0.08, 0.94), MAT_WOOD)
b.add_box((0, -0.085, 0.55), (0.94, 0.08, 0.065), MAT_WOOD)

# tiny iron latch
b.add_box((0.08, -0.137, 0.50), (0.15, 0.035, 0.045), MAT_METAL)

b.commit()


# ============================================================
# FOUNDATION
# ============================================================

b = MeshBuilder(objs["Foundation"])

# Chunkier perimeter stones with small size changes
stone_specs = [
    ((-1.28, -1.31, 0.26), (0.52, 0.30, 0.25)),
    ((-0.66, -1.34, 0.25), (0.58, 0.24, 0.22)),
    (( 0.05, -1.32, 0.27), (0.68, 0.28, 0.26)),
    (( 0.80, -1.34, 0.24), (0.56, 0.24, 0.20)),
    (( 1.30, -1.30, 0.27), (0.30, 0.31, 0.25)),

    ((-1.33, 1.27, 0.25), (0.33, 0.34, 0.22)),
    ((-0.74, 1.32, 0.27), (0.70, 0.24, 0.25)),
    (( 0.05, 1.29, 0.24), (0.68, 0.30, 0.20)),
    (( 0.82, 1.32, 0.26), (0.58, 0.24, 0.24)),
    (( 1.30, 1.28, 0.25), (0.30, 0.32, 0.22)),
]

for center, size in stone_specs:
    b.add_box(center, size, MAT_STONE)

# Wooden sill sitting on stone
b.add_box((0, 0, 0.365), (2.78, 2.78, 0.10), MAT_WOOD_DARK)

b.commit()


# ============================================================
# FENCE
# ============================================================

b = MeshBuilder(objs["Fence"])

# Pointed post silhouettes
for x in (-1.45, 0.0, 1.45):
    b.add_pyramid(
        center=(x, 0, 1.00),
        base_size=(0.18, 0.18),
        height=0.18,
        mat=MAT_WOOD_DARK,
    )

# Thicker top rail
b.add_box((0, 0, 0.77), (2.92, 0.15, 0.13), MAT_WOOD)

# Rural diagonal support
add_xz_beam(
    b,
    (-1.34, 0.18),
    (-0.08, 0.69),
    0.10,
    0.105,
    MAT_WOOD_DARK,
    y=-0.09,
)

# Foot stones under outer posts
for x in (-1.45, 1.45):
    b.add_box(
        (x, 0, 0.07),
        (0.34, 0.32, 0.14),
        MAT_STONE
    )

b.commit()


# ============================================================
# STAIR
# ============================================================

b = MeshBuilder(objs["Stair"])

step_h = 0.35 / 3.0

# Projecting tread lips
for i in range(3):
    level = i + 1
    top_z = step_h * level
    y = 0.35 - i * 0.35

    b.add_box(
        (0, y - 0.11, top_z + 0.018),
        (1.74, 0.14, 0.055),
        MAT_STONE
    )

# Side edge stones make stair read as architecture
b.add_box((-0.86, 0.00, 0.175), (0.13, 1.05, 0.35), MAT_STONE)
b.add_box(( 0.86, 0.00, 0.175), (0.13, 1.05, 0.35), MAT_STONE)

# Small wooden threshold
b.add_box(
    (0, -0.405, 0.375),
    (1.62, 0.20, 0.09),
    MAT_WOOD_DARK
)

b.commit()


# ============================================================
# CHIMNEY
# ============================================================

b = MeshBuilder(objs["Chimney"])

# Stone course bands
for z in (0.36, 0.73, 1.10):
    b.add_box(
        (0, 0, z),
        (0.53, 0.53, 0.065),
        MAT_STONE
    )

# Dark collar below cap
b.add_box(
    (0, 0, 1.375),
    (0.54, 0.54, 0.085),
    MAT_WOOD_DARK
)

# Pronounced stone chimney crown
b.add_box(
    (0, 0, 1.48),
    (0.72, 0.72, 0.13),
    MAT_STONE
)

# Simple central opening indication without booleans
b.add_box(
    (0, 0, 1.555),
    (0.34, 0.34, 0.055),
    MAT_METAL
)

b.commit()


# ============================================================
# SIGN
# ============================================================

b = MeshBuilder(objs["Sign"])

# Stone footing
b.add_box(
    (0, 0, 0.07),
    (0.38, 0.38, 0.14),
    MAT_STONE
)

# Dark post facing
b.add_box(
    (0, -0.08, 0.92),
    (0.15, 0.08, 1.78),
    MAT_WOOD_DARK
)

# Left-facing lower directional arrow
b.add_xz_extrusion(
    [
        (-0.78, 1.57),
        (-0.47, 1.82),
        ( 0.42, 1.82),
        ( 0.42, 1.60),
        (-0.47, 1.60),
    ],
    depth=0.13,
    mat=MAT_SIGN,
    y_center=-0.03,
)

# Right-facing upper directional arrow
b.add_xz_extrusion(
    [
        (-0.35, 1.88),
        ( 0.50, 1.88),
        ( 0.82, 2.08),
        ( 0.50, 2.27),
        (-0.35, 2.27),
    ],
    depth=0.13,
    mat=MAT_SIGN,
    y_center=0.03,
)

# Small dark mounting strips
b.add_box(
    (0.0, -0.105, 1.71),
    (0.38, 0.035, 0.05),
    MAT_WOOD_DARK
)
b.add_box(
    (0.0, -0.105, 2.07),
    (0.38, 0.035, 0.05),
    MAT_WOOD_DARK
)

b.commit()


# ------------------------------------------------------------
# Preserve transforms / enforce export-friendly scale
# ------------------------------------------------------------

for name in MODULE_NAMES:
    obj = objs[name]

    # Geometry was edited in local coordinates only;
    # do not alter placement/origin.
    if any(abs(s - 1.0) > 0.00001 for s in obj.scale):
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.transform_apply(
            location=False,
            rotation=False,
            scale=True
        )
        obj.select_set(False)

    for poly in obj.data.polygons:
        poly.use_smooth = False


# ------------------------------------------------------------
# Material Preview viewport
# ------------------------------------------------------------

for window in bpy.context.window_manager.windows:
    screen = window.screen

    for area in screen.areas:
        if area.type != 'VIEW_3D':
            continue

        space = area.spaces.active

        try:
            # Material Preview
            space.shading.type = 'MATERIAL'
            space.shading.show_shadows = True
            space.shading.show_cavity = True
            space.shading.cavity_type = 'BOTH'

            # Studio-light based material preview
            space.shading.use_scene_world = False
            space.shading.use_scene_lights = False

        except Exception:
            # Safe fallback for API differences
            try:
                space.shading.type = 'SOLID'
                space.shading.color_type = 'MATERIAL'
            except Exception:
                pass


# ------------------------------------------------------------
# Select all modules and frame them
# ------------------------------------------------------------

bpy.ops.object.select_all(action='DESELECT')

for obj in objs.values():
    obj.select_set(True)

bpy.context.view_layer.objects.active = objs["WallPlain"]

for window in bpy.context.window_manager.windows:
    screen = window.screen

    for area in screen.areas:
        if area.type != 'VIEW_3D':
            continue

        region = next(
            (r for r in area.regions if r.type == 'WINDOW'),
            None
        )

        if region is None:
            continue

        try:
            with bpy.context.temp_override(
                window=window,
                screen=screen,
                area=area,
                region=region,
                space_data=area.spaces.active,
            ):
                bpy.ops.view3d.view_selected(
                    use_all_regions=False
                )

            rv3d = area.spaces.active.region_3d
            rv3d.view_distance = max(rv3d.view_distance, 16.5)
            rv3d.view_location = Vector((0.0, 0.0, 1.25))

        except Exception:
            pass


# ------------------------------------------------------------
# Triangle report
# ------------------------------------------------------------

total_tris = 0

print("=" * 72)
print("SEKAI / MISTVALE MODULAR BUILDING KIT — DETAILS PASS")
print("=" * 72)

for name in MODULE_NAMES:
    obj = objs[name]
    obj.data.calc_loop_triangles()

    tris = len(obj.data.loop_triangles)
    verts = len(obj.data.vertices)
    total_tris += tris

    print(
        f"{name:12s} | "
        f"{verts:5d} verts | "
        f"{tris:5d} tris | "
        f"scale=({obj.scale.x:.3f}, "
        f"{obj.scale.y:.3f}, "
        f"{obj.scale.z:.3f})"
    )

print("-" * 72)
print(f"TOTAL TRIANGLES : {total_tris}")
print("DETAIL BUDGET   : <= 12000")
print(
    "BUDGET STATUS   : "
    + ("OK" if total_tris <= 12000 else "OVER BUDGET")
)
print("=" * 72)

# C2B:END