"""WPN_CHN -- the three reusable pieces of 缚星链.

THIS IS NOT A VARIANT FAMILY.  Every other `wpn_<fam>_build.py` in this line
answers "what does variant N of this weapon look like".  This one answers a
different question, because the user's ruling of 2026-09-29 asked for a
different thing:

    WPN_CHAIN_HANDLE / WPN_CHAIN_LINK / WPN_CHAIN_TRIDENT / WPN_CHAIN_HELD_ARC_A..D,
    而不是再生成那坨程序圆盘

So there are three rows and they are three ASSETS, not three skins.  The four
held arcs are deliberately absent: they replace a per-frame parameter solve with
an authored performance, which needs COMBAT's show/hide + release-ratio interface
before there is anything to author against (REQ-9).

The chain currently lives in `godot/scripts/combat/chain_visual.gd` -- ~2900 lines
COMBAT owns, drawing the rope as a MultiMesh of a TorusMesh built in code and the
head from `CylinderMesh` prisms.  Nothing here replaces that file.  What this
produces is the GEOMETRY INTERFACE it can be swapped onto, and the three numbers
a link has to keep for the swap to be safe are asserted, not remembered.
"""

import math
import os
import sys

# The framework lives next to this file, and Blender does not put a script's
# directory on sys.path -- without this the import works or fails depending on
# where the process was launched from.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import weapon_common as wc  # noqa: E402

TAU = math.tau


# ===========================================================================
#  1. PRIMITIVES THIS FAMILY NEEDS AND THE FRAMEWORK DOES NOT HAVE
# ===========================================================================

# `oval_torus` now lives in the framework.  A floating ring on a staff is
# the same problem as a chain link -- an elliptical centre path with a round
# tube -- and the ellipse-normal fix below is worth exactly one copy, not
# two.  Kept as an alias so every call site in this file is unchanged.
oval_torus = wc.oval_torus


def blade_section(w, t, ridge=0.62):
    """A blade cross-section with a mid-ridge: sharp in -Z, thick in +Z.

    Eight points, symmetric about x = 0 and about the z = -t line, so a prong
    lofted with it stays on its own axis instead of drifting.  §5 of the asset
    brief asks for a real PROFILE rather than a prism, and a profile is exactly
    this: a section whose mass is not on its centre line.
    """
    return [
        (0.0, -t),
        (w * 0.60, -t * 0.12),
        (w, t * ridge * 0.55),
        (w * 0.60, t * ridge),
        (0.0, t * ridge * 0.88),
        (-w * 0.60, t * ridge),
        (-w, t * ridge * 0.55),
        (-w * 0.60, -t * 0.12),
    ]


def swept_blade(name, mat, y0, x0, length, angle_deg, w, th, seg=8):
    """A PRONG: rings stacked along a swept direction, so the fork can splay.

    `wc.loft` is used rather than hand-rolled face lists for a specific reason
    -- it enforces that every ring has the same point count, which is the one
    failure mode a hand-built swept solid has.  The sweep is done by offsetting
    each ring's CENTRE, not by rotating the mesh, so the section stays
    perpendicular to the sweep direction the whole way and the blade does not
    corkscrew.

    The width curve is not decoration: a prong widest at its ROOT reads as a
    spike welded onto a hub, and widest a third of the way out reads as a blade.
    """
    a = math.radians(angle_deg)
    dx, dy = math.sin(a), math.cos(a)
    k_w = [(0.0, 1.00), (0.22, 1.08), (0.46, 1.13), (0.74, 0.78), (1.0, 0.05)]
    k_t = [(0.0, 1.00), (0.30, 1.06), (0.60, 0.86), (1.0, 0.24)]
    stations = []
    for i in range(seg + 1):
        t = i / float(seg)
        y = y0 + dy * length * t
        xo = x0 + dx * length * t
        sec = blade_section(w * wc.curve(k_w, t), th * wc.curve(k_t, t))
        stations.append((y, [(px + xo, pz) for (px, pz) in sec]))
    return wc.loft(name, stations, mat, cap_start=True, cap_end=True)


def barrel(name, mat, ys, radii, n=12, wobble=0.0):
    """A lofted body of revolution from (y, rx, rz) control points.

    Used for the handle's grip and the head's hub -- the same shape question
    twice, so it is worth answering once.
    """
    stations = []
    for i, y in enumerate(ys):
        rx, rz = radii[i]
        stations.append((y, wc.oval_pts(rx, rz, n, offset=0.7 * i, wobble=wobble)))
    return wc.loft(name, stations, mat)


# ===========================================================================
#  2. THE LINK -- DIMENSIONS ARE DERIVED, AND THAT IS THE POINT
# ===========================================================================

def link_metrics(P):
    """The link's four numbers, in ONE place, from the live constants.

    THE NUMBERS IN THE BUILD RECORD USED TO BE WRONG, AND THAT IS WHY THIS
    FUNCTION EXISTS.  docs/weapons/CHAIN_ASSET_DECOMPOSITION.md quoted the link's
    half-extents as "0.0312 / 0.0114 / 0.0473 m, measured by stow_diag.gd".  Two
    of those are simply the values for LINK_FILL = 1.82 -- 0.0473 is
    `link_spacing * 1.82 / 2` -- and the constant has been 1.752 for some time.
    The third does not match its own closed form under either value.  All three
    were transcribed from a comment instead of computed from the constants that
    the running code actually reads.

    The closed forms, all of which are `stow_diag.gd`'s own:
        length along the rope   L = link_spacing * link_fill
        tube radius             r = L * (1 - link_tube_ratio) * 0.25
        ring centre, along rope b = L / 2 - r
        ring centre, across     a = L / 2 * link_width_scale - r

    `r` is the SAME quantity `stow_ring_readings()` subtracts twice when it
    reports material clearance, which is why the authored link has to agree with
    it rather than merely look about right.
    """
    L = float(P["link_spacing"]) * float(P["link_fill"])
    r = L * (1.0 - float(P["link_tube_ratio"])) * 0.25
    return dict(L=L, r=r, b=L * 0.5 - r,
                a=L * 0.5 * float(P["link_width_scale"]) - r)


def build_link(P, mats, rig):
    m = link_metrics(P)
    ob = oval_torus("LinkBody", m["a"], m["b"], m["r"], mats["chain_link"],
                    axis="Z",
                    n_major=int(P["link_major_segments"]),
                    n_minor=int(P["link_minor_segments"]))
    rig.note("link  L=%.5f m  tube r=%.5f m  centre (a=%.5f, b=%.5f)"
             % (m["L"], m["r"], m["a"], m["b"]))
    rig.note("      outer envelope along/rope %.5f  across %.5f  thick %.5f m"
             % (2 * (m["b"] + m["r"]), 2 * (m["a"] + m["r"]), 2 * m["r"]))

    # The two ends.  A link's anchors are where the next link's ring passes
    # through, which is the ring centre offset along the rope -- not the ring's
    # outer edge, which is where a naive reading would put them.
    rig.socket("SOC_LINK_IN", (0.0, -m["b"], 0.0))
    rig.socket("SOC_LINK_OUT", (0.0, m["b"], 0.0))
    return [ob]


# ===========================================================================
#  3. THE HANDLE -- the one piece the HAND drives
# ===========================================================================

def build_handle(P, mats, rig):
    parts = []

    # THE BUTT RING, at the origin.  `behind >= 0.04` is a real constraint here
    # and not a formality: the ring IS everything behind the origin, so its outer
    # radius has to clear 0.04 on its own or the handle reads as a grip floating
    # with nothing at its end.
    rr, rt = float(P["ring_r"]), float(P["ring_tube"])
    parts.append(oval_torus("ChainEye", rr, rr, rt, mats["chain_head"], axis="Z",
                            n_major=24, n_minor=8))

    # THE GRIP.  Densities differ along it on purpose: the swell is under the
    # palm, the waists are where the fingers close.  This is the part of the
    # whole weapon the player looks at most (PART I: 0.3-1 m first person).
    gf = float(P["grip_front"])
    swap = float(P["grip_swell"])
    wst = float(P["grip_waist"])
    ys = [0.026, 0.045, 0.078, 0.108, 0.138, 0.172, gf]
    rad = [(0.0144, 0.0128),      # emerging from the ring
           (wst, wst * 0.895),    # waist below the palm
           (swap, swap * 0.862),  # the swell
           (swap * 0.985, swap * 0.848),
           (swap * 0.940, swap * 0.812),
           (0.0142, 0.0126),      # in to meet the collar
           (0.0124, 0.0110)]
    parts.append(barrel("ChainGrip", mats["chain_grip"], ys, rad, n=12, wobble=0.012))

    # THE WRAP.  A separate loft that stands slightly PROUD of the grip and is
    # ribbed, so it reads as cord wound on rather than as a painted band.  The
    # ribs are geometry, not texture -- this line has no texture pipeline and a
    # grip that is smooth at 0.3 m reads as a machined tube.
    ribs = int(P["ribs"])
    w0, w1 = 0.064, 0.156
    band = []
    steps = ribs * 4
    for i in range(steps + 1):
        t = i / float(steps)
        y = w0 + (w1 - w0) * t
        base = wc.curve([(0.0, 0.0158), (0.5, 0.0165), (1.0, 0.0142)], t)
        pulse = 0.0018 * math.sin(t * TAU * ribs)
        band.append((y, wc.oval_pts(base + pulse, (base + pulse) * 0.87,
                                    12, wobble=0.02)))
    parts.append(wc.loft("ChainWrap", band, mats["leather"]))

    # THE COLLAR + the fore eye.  The eye's hole faces +Y, because the rope
    # leaves along +Y and a loop the rope cannot pass through is a decoration.
    cf = float(P["collar_front"])
    parts.append(barrel("ChainCollar", mats["chain_head"],
                        [gf - 0.010, gf + 0.014, cf - 0.009, cf],
                        [(0.0140, 0.0124), (0.0212, 0.0190),
                         (0.0186, 0.0166), (0.0152, 0.0138)],
                        n=12))
    ey = float(P["eye_y"])
    parts.append(oval_torus("ChainMouth", float(P["eye_r"]), float(P["eye_r"]),
                            float(P["eye_tube"]), mats["chain_head"], axis="Y",
                            n_major=20, n_minor=7))

    rig.socket("SOC_GRIP", (0.0, 0.105, 0.0))
    rig.socket("SOC_LINK_OUT", (0.0, 0.0, 0.0))
    rig.socket("SOC_HEAD", (0.0, ey + float(P["eye_tube"]), 0.0))
    rig.note("handle  butt ring at the ORIGIN (outer %.4f m) -> eye at %.4f m"
             % (rr + rt, ey))
    return parts


# ===========================================================================
#  4. THE TRIDENT -- judged on silhouette alone
# ===========================================================================

def build_trident(P, mats, rig):
    parts = []
    k = float(P["scale"])

    rr = float(P["ring_r"]) * k
    rt = float(P["ring_tube"]) * k
    ry = float(P["ring_y"]) * k
    parts.append(oval_torus("HeadEye", rr, rr, rt, mats["iron"], axis="Y",
                            n_major=20, n_minor=8, centre=(0.0, ry, 0.0)))

    # THE HUB.  §4's "reinforced central body", and the reason three points read
    # as ONE weapon: a fork mounted on nothing is three separate shards, which is
    # what the earlier five-prism version was.
    hb, hm, hf = (float(P["hub_back"]) * k, float(P["hub_mouth"]) * k,
                  float(P["hub_front"]) * k)
    parts.append(barrel("HeadHub", mats["iron"],
                        [hb, hm * 0.5, hm, (hm + hf) * 0.5, hf],
                        [(float(P["hub_r_back"]) * k, float(P["hub_r_back"]) * k * 0.90),
                         (float(P["hub_r_swell"]) * k * 0.78,
                          float(P["hub_r_swell"]) * k * 0.72),
                         (float(P["hub_r_swell"]) * k,
                          float(P["hub_r_swell"]) * k * 0.90),
                         (float(P["hub_r_front"]) * k,
                          float(P["hub_r_front"]) * k * 0.90),
                         (float(P["hub_r_front"]) * k * 0.88,
                          float(P["hub_r_front"]) * k * 0.80)],
                        n=12))

    # THE CENTRAL SPIKE, and 贯穿 is its whole job.  Long, straight, on the chain
    # axis: the one part that must NOT splay.
    sb, st = float(P["spike_base"]) * k, float(P["spike_tip"]) * k
    sw = float(P["spike_w1"]) * k
    stations = []
    k_w = [(0.0, float(P["spike_w0"]) / float(P["spike_w1"])),
           (0.26, 1.0), (0.58, 0.84), (0.85, 0.42), (1.0, 0.04)]
    k_t = [(0.0, 1.10), (0.30, 1.0), (0.70, 0.74), (1.0, 0.26)]
    for i in range(9):
        t = i / 8.0
        y = sb + (st - sb) * t
        sec = blade_section(sw * wc.curve(k_w, t),
                            float(P["spike_th"]) * k * wc.curve(k_t, t))
        stations.append((y, sec))
    parts.append(wc.loft("HeadSpike", stations, mats["chain_head"]))

    # THE FORK.  22 degrees, 0.40 of the axis, and it must NOT go wider: the
    # frame refuted 40 degrees already ("five pale prisms radiating from one
    # point is a STARFISH").  The two shapes are not told apart by width; they
    # are told apart by whether the points SHARE A DIRECTION.
    pb, po = float(P["prong_base"]) * k, float(P["prong_offset"]) * k
    pl, sp = float(P["prong_length"]) * k, float(P["prong_splay_deg"])
    for sgn, tag in ((1.0, "R"), (-1.0, "L")):
        parts.append(swept_blade("HeadProng" + tag, mats["chain_head"],
                                 pb, sgn * po, pl, sgn * sp,
                                 float(P["prong_w"]) * k,
                                 float(P["prong_th"]) * k))

    # THE REAR FLUKES.  钩 and 拉扯, so they face BACKWARD: the head has to still
    # hold something when the rope is hauled, and a shape that only points away
    # from you lets go.  Short and swept, because the first pass made them long
    # and they became the fourth and fifth prongs of the starfish.
    fb, fo = float(P["fluke_base"]) * k, float(P["fluke_offset"]) * k
    fl, fa = float(P["fluke_length"]) * k, float(P["fluke_angle_deg"])
    for sgn, tag in ((1.0, "R"), (-1.0, "L")):
        parts.append(swept_blade("HeadFluke" + tag, mats["chain_head"],
                                 fb, sgn * fo, fl, sgn * fa,
                                 float(P["fluke_w"]) * k,
                                 float(P["fluke_th"]) * k, seg=6))

    tip = st
    rig.socket("SOC_LINK_IN", (0.0, 0.0, 0.0))
    rig.socket("SOC_HEAD", (0.0, tip, 0.0))
    rig.socket("FX_HEAD_CORE", (0.0, sb + (st - sb) * 0.32, 0.0))
    rig.note("trident  eye R=%.4f -> spike tip %.4f m; fork %d deg, flukes %.0f deg"
             % (rr, tip, int(sp), fa))
    return parts


# ===========================================================================
#  5. ROW DISPATCH
# ===========================================================================

BUILDERS = {
    "handle": build_handle,
    "link": build_link,
    "trident": build_trident,
}

SHADING = {
    # Hard-surface parts get an angle limit so the ridge, the fork shoulders and
    # the collar rims stay crisp; the grip and the wrap are fully smooth or a
    # facet line runs down the handle at close range.
    "smooth_angle": 33.0,
    "soft": ("ChainGrip", "ChainWrap", "LinkBody"),
}


def build_row(row, spec):
    part = str(row.get("part") or row.get("id"))
    if part not in BUILDERS:
        raise SystemExit("CHN  no builder for part %r (have: %s)"
                         % (part, ", ".join(sorted(BUILDERS))))

    mats = wc.palette(sorted({
        "chain_link", "chain_head", "chain_grip", "leather", "iron",
    }))

    rig = wc.Rig("CHN")
    rig.extend(BUILDERS[part](row, mats, rig))

    for p in rig.parts:
        if p.name in SHADING["soft"]:
            wc.shade(p, None)
        else:
            wc.shade(p, SHADING["smooth_angle"])

    rig.note("part=%s  world_name=%s" % (part, row.get("world_name", "")))
    return rig


def main():
    wc.run("CHN", build_row)


if __name__ == "__main__":
    main()
