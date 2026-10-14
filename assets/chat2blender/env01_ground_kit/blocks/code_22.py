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