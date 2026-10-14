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