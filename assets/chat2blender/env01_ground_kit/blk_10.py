hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
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

fs = (
    (0,3,2,1),
    (4,5,6,7),
    (0,1,5,4),
    (1,2,6,5),
    (2,3,7,6),
    (3,0,4,7),
)
for face in fs:
    f.append(tuple(b+i for i in face))
    mi.append(mat_index)