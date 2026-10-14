_sr_box(
    v, f, mi,
    ((x0+x1)*0.5, 0.0, height*0.5),
    (TREAD, 2.0, height),
    0
)

# Pale nosing on selected treads keeps the hierarchy readable.
if i in (1, 3, 5, 7):
    _sr_box(
        v, f, mi,
        (x0 + 0.055, 0.0, height - 0.0125),
        (0.11, 1.96, 0.025),
        1
    )