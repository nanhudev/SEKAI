seg_count = 4 if row % 2 == 0 else 5
seg_len = body_outer / seg_count

for i in range(seg_count):
    xc = -body_outer * 0.5 + seg_len * (i + 0.5)
    mat_idx = 3 if (row == 2 and i == seg_count - 2) else 0

    _we_box(
        v, f, mi,
        (xc, -2.0 + 0.04 + body_t*0.5, zc),
        (seg_len, body_t, course_h),
        mat_idx
    )