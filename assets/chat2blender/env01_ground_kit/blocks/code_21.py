for i in range(seg_count):
    yc = arm_y_min + seg_len * (i + 0.5)
    _we_box(
        v, f, mi,
        (-2.0 + 0.04 + body_t*0.5, yc, zc),
        (body_t, seg_len, course_h),
        0
    )