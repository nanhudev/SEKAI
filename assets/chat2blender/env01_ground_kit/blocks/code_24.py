# End posts are shifted inward by half their width so the global bounds
# remain exactly X=-2..+2.
if x == -2.0:
    xc = -2.0 + post_w * 0.5
elif x == 2.0:
    xc = 2.0 - post_w * 0.5
else:
    xc = x

_br_box(
    v, f, mi,
    (xc, 0.0, 0.525),
    (post_w, 0.15, 1.05),
    2
)