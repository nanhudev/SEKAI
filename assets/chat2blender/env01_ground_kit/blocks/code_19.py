if row % 2 == 0:
    blocks = [
        (-1.47, 0.98),
        (-0.49, 0.98),
        ( 0.49, 0.98),
        ( 1.47, 0.98),
    ]
else:
    blocks = [
        (-1.715, 0.49),
        (-0.98, 0.98),
        ( 0.00, 0.98),
        ( 0.98, 0.98),
        ( 1.715, 0.49),
    ]

for bi, (xc, sx) in enumerate(blocks):
    mat_idx = 3 if (row == 1 and bi == 3) else 0
    _we_box(
        v, f, mi,
        (xc, 0.0, zc),
        (sx, body_depth, course_h),
        mat_idx
    )