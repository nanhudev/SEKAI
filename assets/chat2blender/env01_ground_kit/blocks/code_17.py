b = len(v)

xl_b = x0
xr_b = x1
xl_t = x0 + inset_left
xr_t = x1 - inset_right

v.extend([
    (xl_b, y_back, 0.0),
    (xr_b, y_back, 0.0),
    (xr_b, y_front, 0.0),
    (xl_b, y_front, 0.0),

    (xl_t, y_back + 0.06, top_left),
    (xr_t, y_back + 0.04, top_right),
    (xr_t, y_front - 0.05, top_right * 0.96),
    (xl_t, y_front - 0.03, top_left * 0.95),
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