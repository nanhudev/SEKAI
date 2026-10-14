"""SEKAI WPN-01 -- the SWD family builder.  Sword / long sword.

    blender -b --factory-startup --python tools/blender/wpn_swd_build.py -- --list
    blender -b --factory-startup --python tools/blender/wpn_swd_build.py -- --row relic
    blender -b --factory-startup --python tools/blender/wpn_swd_build.py -- --all --no-blend

THIS FILE ANSWERS ONE QUESTION: WHAT IS THE SHAPE.
==================================================
Units, the origin and axis contract, the material factory, the metal-trap
guard, sockets, measurement, assertions, export, the .blend tier routing and
the preview renderer all live in `weapon_common.py` and are NOT re-implemented
here.  That split is the whole point of the M2 framework: eighteen families
times six variants is a hundred chances to get the same six infrastructure
things wrong, and each of those six fails SILENTLY in Godot.  A family builder
that re-rolls its own exporter is a family builder that will eventually export
a sword with its long axis on Z and nobody will notice for three sessions.

WHAT THE PARAMETERS ARE FOR
===========================
NOT randomisation.  `assets_source/weapons/specs/swd_variants.json` holds ten
STRUCTURAL archetypes -- different cross-section, different curvature,
different mass distribution, different guard mechanism, different grip length,
one-handed vs two -- and this file turns each into geometry.  Sweeping
blade_length and guard_radius produces a hundred copies of one sword; the
family table's own §"辨识度优先" calls that the failure to avoid.

THE AUTHORING POSE
==================
Length down Blender +Y, edge toward -X, blade flat normal to Z, origin at the
guard plane.  That is the pose that is convenient to build in; `bake_axes()`
rotates the MESH DATA into the export contract afterwards.  Do not author in
the export pose -- the +90 X bake is the only place axis handling happens, and
having two places is how you get a sword that is correct in Blender and
sideways in the player's hand.

INHERITED FROM THE SHIPPING KATANA (WPN-03), DELIBERATELY
========================================================
  * the section runs -0.5 .. +0.5 in X, CENTRED ON THE BLADE AXIS.  The first
    shipping sword ran the section 0 .. +1 and then centred the guard, grip and
    collars on x = 0, which put the entire handle on the blade's EDGE line
    instead of behind the middle of the blade.  The 3/4 review showed the guard
    hanging off one side of the sword and it would have been blamed on the guard
    design.  `assert_contract` §5 now measures for exactly this.
  * the ridge is a real cross-section feature, not a normal map.  At the 0.3-1 m
    acceptance band the silhouette IS the read, so a blade has to have a profile.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import weapon_common as wc  # noqa: E402

TAU = wc.TAU


# =============================================================================
#  CROSS-SECTIONS
# =============================================================================
#
# Normalised: u is the fraction of blade width from EDGE (-0.5) to SPINE (+0.5),
# v is the fraction of half-thickness.  Read each list as a walk: start at the
# edge, go up one flat, over the ridge, out to the spine, across the spine, and
# back down.  The walk closes, so the list is the whole boundary and there is no
# "back face" to get wrong.
#
# `shinogi` is carried over from the shipping katana: a flat grind up to a ridge
# two thirds of the way to the spine, then a steeper shinogi-ji.  That ridge is
# what catches light along the length of a blade, and it is why a slab with a
# normal map cannot substitute for a real section.
#
# `flat_diamond` is the default for this family.  SWD is the STRAIGHT
# DOUBLE-EDGED sword -- the thing that makes it a different visual family from
# KAT, which is single-edged and bowed.  A family that ships both needs the
# section to be a per-row choice, not a per-family constant.
SECTIONS = {
    # single edge, flat grind to a ridge, narrow flat spine
    "shinogi": [(-0.500, 0.000), (-0.180, 0.640), (0.160, 1.000), (0.360, 0.880),
                (0.485, 0.460), (0.500, 0.145), (0.500, -0.145), (0.485, -0.460),
                (0.360, -0.880), (0.160, -1.000), (-0.180, -0.640)],
    # single edge, no ridge: a smooth convex lens, for the elegant archetypes
    "lens": [(-0.500, 0.000), (-0.220, 0.560), (0.020, 0.860), (0.300, 0.980),
             (0.480, 0.720), (0.500, 0.320), (0.500, -0.320), (0.480, -0.720),
             (0.300, -0.980), (0.020, -0.860), (-0.220, -0.560)],
    # single edge, full-thickness flat back -- a re-ground break or a falchion
    "backed": [(-0.500, 0.000), (-0.240, 0.760), (0.040, 0.960), (0.300, 1.000),
               (0.500, 0.900), (0.500, -0.900), (0.300, -1.000), (0.040, -0.960),
               (-0.240, -0.760)],
    # double edge, central ridge -- the narrow thrusting blade
    "diamond": [(-0.500, 0.000), (-0.250, 0.520), (0.000, 1.000), (0.250, 0.520),
                (0.500, 0.000), (0.250, -0.520), (0.000, -1.000), (-0.250, -0.520)],
    # double edge, flat faces between two bevels -- the general-purpose blade
    "flat_diamond": [(-0.500, 0.000), (-0.300, 0.620), (-0.100, 0.900), (0.100, 0.900),
                     (0.300, 0.620), (0.500, 0.000), (0.300, -0.620), (0.100, -0.900),
                     (-0.100, -0.900), (-0.300, -0.620)],
}

# Grip swell: fatter at both ends than in the middle.  A mathematically even
# oval grip reads as a machined tube at 0.3 m, which is inside the band PART I
# calls the highest quality bar.
GRIP_SWELL = [(0.0, 1.055), (0.12, 1.000), (0.55, 0.955), (0.86, 1.005), (1.0, 0.940)]

KEYS = ["tier", "section", "blade_length", "blade_w_base", "blade_t_base", "sori",
        "width_profile", "thick_profile", "stations", "habaki_len",
        "guard", "guard_x", "guard_x2", "guard_z", "guard_thick", "guard_mat",
        "grip_length", "grip_rx", "grip_rz", "grip_mat", "wrapped", "wrap_mat",
        "pommel", "pommel_mat", "blade_mat", "accent_mat", "accent_seams",
        "channel", "channel_mat", "length_band"]


# =============================================================================
#  helpers
# =============================================================================

def params(spec, row):
    return {k: wc.resolve(spec, row, k) for k in KEYS}


def sgnpow(v, p):
    return math.copysign(abs(v) ** p, v) if v != 0.0 else 0.0


def superellipse(a, b, n, exponent=4.0):
    """A rounded rectangle.  exponent 2 is an ellipse, 4 is a rounded rect,
    higher is crisper.  Guards, pommels and ferrules are all boxes with the
    corners taken off, and a hard box reads as a placeholder at 0.3 m."""
    pts = []
    for i in range(n):
        t = TAU * i / n
        pts.append((a * sgnpow(math.cos(t), 2.0 / exponent),
                    b * sgnpow(math.sin(t), 2.0 / exponent)))
    return pts


def seam_mult(t, P):
    """Cumulative width step across the forge seams.

    A seam is not decoration: where two billets are joined, the re-grind leaves
    a step, and that step is visible in silhouette.  Multiplying the width
    profile means the step is part of the blade's own surface, so it survives
    into the GLB and into any later LOD reduction -- unlike a bump in a normal
    map, which is the first thing a LOD throws away.
    """
    m = 1.0
    for s in P["accent_seams"]:
        if t >= float(s[0]):
            m *= float(s[1])
    return m


def w_at(t, P):
    return P["blade_w_base"] * wc.curve(P["width_profile"], t) * seam_mult(t, P)


def th_at(t, P):
    """HALF thickness at t -- the section's v runs -1..1, so the full
    thickness is twice this."""
    return 0.5 * P["blade_t_base"] * wc.curve(P["thick_profile"], t)


def xo_at(t, P):
    """Sori, as a displacement of the blade's own axis.

    A parabola with its vertex at mid-blade: zero at the base, zero at the tip,
    maximum in the middle.  `sori > 0` puts the vertex at -X, which is the EDGE
    side, so the edge ends up on the convex side of the bow -- which is what a
    katana does and what a saber does.  The shipping katana used the same
    parabola and the same sign; a sign slip here produces a blade that curves
    backwards and still measures the same length, which is why it is stated
    rather than left to a comment in a builder nobody reads.
    """
    return P["sori"] * ((2.0 * t - 1.0) ** 2 - 1.0)


def ring_at(t, P, scale=1.0):
    sec = SECTIONS[P["section"]]
    w = w_at(t, P)
    th = th_at(t, P)
    xo = xo_at(t, P)
    return [(xo + (u * w) * scale, (v * th) * scale) for (u, v) in sec]


def stations_for(P, t0, t1, n, scale_fn=None):
    """Uniform stations between two length fractions.  `scale_fn(t)` shrinks the
    ring, which is how the point and the tapering rails are made."""
    out = []
    for i in range(n + 1):
        t = t0 + (t1 - t0) * i / float(n)
        y = P["blade_length"] * t
        sc = scale_fn(t) if scale_fn else 1.0
        out.append((y, ring_at(t, P, sc)))
    return out


# =============================================================================
#  parts
# =============================================================================

def build_blade(P, mats):
    n = int(P["stations"])
    st = []
    for i in range(n):
        t = i / float(n)
        st.append((P["blade_length"] * t, ring_at(t, P)))
    # THE POINT.  Two extra stations, not one: a section scaled to 20% and
    # capped reads as a chisel end, and the tip is a silhouette feature the
    # player looks at constantly because it is where the weapon is going.
    for frac, sc in ((0.962, 0.84), (1.0, 0.16)):
        st.append((P["blade_length"] * frac, ring_at(frac, P, sc)))
    return wc.loft("Blade", st, mats[P["blade_mat"]])


def build_habaki(P, mats):
    """The blade collar / ferrule sitting on the guard.  A real habaki is what
    the scabbard mouth grips, so it is a hard mechanical band, not a decoration:
    it gets a rounded-rect section with a wall thick enough to read at 0.3 m."""
    a = 0.5 * w_at(0.0, P) + 0.0036
    b = th_at(0.0, P) + 0.0030
    pts = superellipse(a, b, 40, 5.0)
    return wc.extrude_profile("Habaki", pts, -0.004, P["habaki_len"], mats["iron"])


def build_guard(P, mats):
    gx = P["guard_x"]
    gx2 = P["guard_x2"] if P["guard_x2"] else gx
    gz = P["guard_z"]
    gt = P["guard_thick"]
    m = mats[P["guard_mat"]]
    kind = P["guard"]

    if kind == "none":
        return None

    if kind in ("cross", "tsuba"):
        # cross: a bar, long on X, thin on Z.  Doubles as the mechanism that
        #        makes a sword look like a sword from the side.
        # tsuba: a plate, so the outline is a face rather than a bar -- the
        #        ritual read is frontal ornament, not a side profile.
        exp = 5.0 if kind == "cross" else 4.0
        pts = []
        for i in range(72):
            t = TAU * i / 72
            ux = sgnpow(math.cos(t), 2.0 / exp)
            uz = sgnpow(math.sin(t), 2.0 / exp)
            a = gx if ux >= 0 else gx2
            pts.append((ux * a, uz * gz))
        ob = wc.extrude_profile("Guard", pts, -gt * 0.5, gt * 0.5, m)
        wc.bevel(ob, 0.0005, 2, 40.0)
        return ob

    if kind == "shell":
        # A shallow bowl.  Built as a solid of revolution rather than a shell
        # so there is no open edge for backface culling to reveal in Godot.
        prof = [(0.00, 0.26), (0.30, 0.66), (0.62, 0.90), (0.90, 1.00),
                (1.06, 0.96), (1.20, 0.74)]
        st = []
        for (u, r) in prof:
            y = -gt * 0.5 + u * gt * 1.7
            st.append((y, wc.oval_pts(gx * r, gz * r, 28)))
        ob = wc.loft("Guard", st, m)
        return ob

    raise SystemExit("SWD  unknown guard kind %r" % kind)


def build_grip(P, mats):
    top = -0.004
    bot = -P["grip_length"]
    n = 12
    st = []
    for i in range(n + 1):
        t = i / float(n)
        y = top + (bot - top) * t
        s = wc.curve(GRIP_SWELL, t)
        st.append((y, wc.oval_pts(P["grip_rx"] * s, P["grip_rz"] * s, 20,
                                  offset=t * 1.7, wobble=0.012)))
    return wc.loft("Grip", st, mats[P["grip_mat"]])


def build_wrap(P, mats):
    """The over-wrap.  A sleeve with a slight helical swell, not a crossed
    ito-maki braid: at 0.3 m the read is a dark textured mass with ridges, and a
    real braid is a separate asset's worth of work.  Recorded as a known
    limitation in the WPN-01 report rather than passed off as finished."""
    top = -0.012
    bot = -P["grip_length"] + 0.012
    n = 14
    st = []
    for i in range(n + 1):
        t = i / float(n)
        y = top + (bot - top) * t
        s = wc.curve(GRIP_SWELL, t) * 1.10
        rx = P["grip_rx"] * s + 0.0007
        rz = P["grip_rz"] * s + 0.0007
        st.append((y, wc.oval_pts(rx, rz, 20, offset=t * 5.4, wobble=0.030)))
    return wc.loft("Wrap", st, mats[P["wrap_mat"]])


def build_pommel(P, mats):
    if P["pommel"] == "none":
        return None
    bot = -P["grip_length"]
    a = P["grip_rx"] * 1.16
    b = P["grip_rz"] * 1.20
    pts = superellipse(a, b, 32, 3.2)
    ob = wc.extrude_profile("Pommel", pts, bot - 0.001, bot - 0.016, mats[P["pommel_mat"]])
    wc.bevel(ob, 0.0008, 2, 40.0)
    return ob


def build_seams(P, mats, rig):
    """One collar per forge seam, plus the FX anchors that live on it.

    The seam does three jobs at once and that is why the family table picked it
    as the Hero: it is a deformation feature (the two billets are ground on
    different axes, so the joint carries a step), an emission channel, and a
    parameter family (where the seam is, what fills it, whether it lights).
    """
    out = []
    half = 0.007
    for idx, s in enumerate(P["accent_seams"], start=1):
        t_s = float(s[0])
        dt = half / P["blade_length"]
        st = []
        for (k, sc) in ((-1.0, 0.985), (-0.30, 1.0), (0.30, 1.0), (1.0, 0.985)):
            t = t_s + k * dt
            st.append((P["blade_length"] * t,
                       [(x * 1.035 * sc, z * 1.035 * sc) for (x, z) in ring_at(t, P)]))
        out.append(wc.loft("Seam_%02d" % idx, st, mats[P["accent_mat"]]))
        rig.socket("FX_Rune_%s" % "ABC"[idx - 1],
                   (xo_at(t_s, P), P["blade_length"] * t_s, 0.0))
    if out:
        rig.socket("FX_Seam", (xo_at(0.5, P), P["blade_length"] * 0.5, 0.0))
    return out


def build_channel(P, mats, rig):
    """A raised emissive rail down each flat.

    Independent geometry, deliberately: it has its own FX anchors, it can emit,
    and it can be swapped or removed per variant without touching the blade.
    The alternative -- a masked strip in the base colour -- would be invisible
    in the silhouette and would evaporate at the first LOD.
    """
    n = 16
    t0, t1 = 0.07, 0.90
    groups = []
    for side in (1.0, -1.0):
        st = []
        for i in range(n + 1):
            t = t0 + (t1 - t0) * i / float(n)
            y = P["blade_length"] * t
            xo = xo_at(t, P)
            cz = side * th_at(t, P) * 0.88
            # The rail widens slightly toward the guard, the way a real fuller
            # does, so it reads as flow rather than as a painted stripe.
            rx = 0.0026 * wc.curve([(0.0, 1.15), (0.45, 0.95), (1.0, 0.70)], (t - t0) / (t1 - t0))
            st.append((y, [(xo + px, cz + pz) for (px, pz) in wc.oval_pts(rx, 0.0022, 12)]))
        groups.append(st)
    rig.socket("FX_Rune_A", (xo_at(0.30, P), P["blade_length"] * 0.30, 0.0))
    rig.socket("FX_Rune_B", (xo_at(0.70, P), P["blade_length"] * 0.70, 0.0))
    return [wc.loft_many("Blade_Channel", groups, mats[P["channel_mat"]])]


# =============================================================================
#  the row
# =============================================================================

def build_row(row, spec):
    P = params(spec, row)
    rig = wc.Rig("SWD")

    keys = {P["blade_mat"], P["grip_mat"], P["guard_mat"], P["pommel_mat"],
            P["accent_mat"], P["wrap_mat"], P["channel_mat"], "iron"}
    mats = wc.palette(sorted(keys))

    rig.add(build_blade(P, mats))
    rig.add(build_habaki(P, mats))

    guard = build_guard(P, mats)
    if guard is not None:
        rig.add(guard)

    rig.add(build_grip(P, mats))
    if P["wrapped"]:
        rig.add(build_wrap(P, mats))

    pommel = build_pommel(P, mats)
    if pommel is not None:
        rig.add(pommel)

    rig.extend(build_seams(P, mats, rig))
    if P["channel"]:
        rig.extend(build_channel(P, mats, rig))

    # Anchors.  Declared in the AUTHORING pose -- bake_axes moves them along
    # with the mesh, because a socket that stays behind when the asset rotates
    # is worse than no socket at all.
    rig.socket("SOC_GRIP", (0.0, -P["grip_length"] * 0.55, 0.0))
    rig.socket("SOC_MOUTH", (0.0, 0.004, 0.0))
    rig.socket("SOC_TIP", (xo_at(1.0, P), P["blade_length"], 0.0))
    rig.socket("SOC_EDGE_MID",
               (xo_at(0.5, P) - 0.5 * w_at(0.5, P), P["blade_length"] * 0.5, 0.0))
    rig.socket("FX_TRAIL_A", (xo_at(0.72, P), P["blade_length"] * 0.72, 0.0))
    rig.socket("FX_TRAIL_B", (xo_at(0.36, P), P["blade_length"] * 0.36, 0.0))

    # Shading.  Hard-surface parts get an angle limit so the ridge, the guard
    # rim and the seam shoulders stay crisp; soft parts are fully smooth or the
    # grip shows a facet line down its length.
    for p in rig.parts:
        if p.name.startswith(("Blade", "Habaki", "Guard", "Pommel", "Seam")):
            wc.shade(p, 33.0)
        else:
            wc.shade(p, None)

    rig.note("archetype %s / %s" % (row.get("archetype", "?"), row.get("world_name", "")))
    rig.note("section=%s guard=%s grip=%.3f wrapped=%s seams=%d channel=%s"
             % (P["section"], P["guard"], P["grip_length"], P["wrapped"],
                len(P["accent_seams"]), P["channel"]))
    return rig


def main():
    wc.run("SWD", build_row)


if __name__ == "__main__":
    main()
