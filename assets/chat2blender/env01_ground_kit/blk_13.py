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