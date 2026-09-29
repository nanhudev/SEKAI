"""WPN_STF -- 法杖.  The third family in the M2.5 proof, chosen because it is
STRUCTURALLY DISSIMILAR to the other two.

    SWD  is a rigid single solid          -- one continuous loft plus fittings
    CHN  is a modular set of pieces       -- handle / link / head, instantiated
    STF  is where ONE LOFT STOPS BEING ENOUGH

The framework earns the right to host the remaining fifteen classes only if it
can hold the four things a staff needs and a sword never asked for:

    crystal        a shape defined by POINTS, with facets that twist.  `loft`
                   caps its end rings with a fan, which turns a gemstone into a
                   barrel; and it must be FLAT-SHADED -- see `wc.shade(flat=True)`.
    openwork       geometry that is deliberately NOT closed: a cage of six
                   struts with six windows you can see through, and a separate
                   emissive core floating inside it.
    floating ring  geometry that is deliberately NOT CONNECTED to anything.
    emission / VFX a material that is the light source, and anchors for effects
                   that ride the weapon.

The three rows are the family brief's 三尺寸 -- 短杖 / 中杖 / 长杖 -- and each one
carries a different pair of those four, so a green build is evidence about the
FRAMEWORK rather than about one shape.

CONTRACT.  `CONTRACT["STF"]` is long Y+, origin at the grip centre, no cutting
edge (`kind="none"`, so the edge assertion is skipped rather than passed).
`CLASS_SOCKETS["STF"]` is SOC_HEAD / FX_CORE / FX_RUNE, and the class declares
FX_TRAIL_A/B as OPTIONAL because a staff is swung along its own length: the long
archetype has a shaft to sweep, the short one has nowhere to put a trail.

CONVENTIONS INHERITED FROM THE TWO FAMILIES BEFORE THIS ONE, each paid for:
  * authoring +Y is the length; `bake_axes` rotates so the EXPORTED file has it
    on glTF +Y, which is what the contract is written in;
  * every ring count that feeds a MEASURED extent is a multiple of 4, because a
    ring's extreme along an axis only exists if a vertex lands on that axis;
  * a TILTED ring keeps that guarantee on the axis it was rotated ABOUT and
    loses it on the other two, so the row that asserts an extent puts its widest
    ring in the equatorial plane and tilts the two smaller ones;
  * no part carries its own transform.  Splayed crystals are built by sweeping
    their levels along a direction, not by rotating an object; tilted rings are
    generated already tilted for the same reason.

MATERIAL ALIGNMENT, and this is the second visual iteration rather than the
first.  Pass 1 read as paper: the collars were `iron` (0.086 albedo) and rendered
as a black onion at the base of every head, the cage was `brass` and rendered as
BAMBOO, and the warm crystals were beige card.  Pass 2 moved the cage to `iron`
and got BLACK RUBBER, and the collars to `inlay` and got a KHAKI CUP.  The lesson
is not "lighter" or "darker", it is that each material needs ONE job and enough
specular to travel along the part:

    `brass_dark` the fittings  -- collars, grip rings, the sockets under a head
    `steel_dark` the openwork cage AND the floating rings -- dark enough for a
                                  window to be a window, metallic enough that the
                                  legs keep their round
    `cord`       the wrap       -- BELOW the shaft in value, because a binding is
                                  a shadow line made of rope and not a highlight
    `wood`       the shaft      -- the one matte surface, and the value anchor
    `crystal` / `crystal_warm`  the light sources: dark albedo, emission colour x
                                  strength held at or below 1.0 so the colour
                                  survives the tone curve instead of boiling out
                                  to pastel.  See PALETTE in weapon_common.

Pass 3 also removed the last excuse: the preview was being rendered with
Blender's default AgX view transform while the game runs FILMIC.

PASS 5 IS THE FIRST PASS WHOSE FINDINGS CAME FROM THE FIRST-PERSON PLATE RATHER
THAN FROM THE HEAD PLATE, and three of them are the same mistake in three
places: a value borrowed from a part that had a DIFFERENT JOB.

  * `cloth` (0.300 albedo) was wrapping a 0.150 shaft, which made the grip the
    brightest thing on the weapon -- five bands of pale tape in the one view the
    player actually spends the game in.
  * `brass` (0.430 at 0.55 metallic) was the fittings, and under one sun with a
    grey sky and no reflection source it desaturated to plasticine.  The fix
    moved the METALLIC DOWN, not up: a metallic with nothing to reflect trades
    its own colour for a specular that has nothing to return.
  * `chain_link` (0.474 at 0.20) was the floating rings.  That value is MEASURED
    and correct for chain links, whose job is to stay legible in a moving
    fistful against a bright sky; on a static hoop it made the frame brighter
    than the rune nodes it was framing.

None of the three was visible in the head plates, all three were unmissable at
0.5 m, and all three are the sort of thing an assertion cannot see: the extents
were exact, the tri counts were in band, and the weapon was wrong.
"""

import math
import os
import sys

# Blender does not put a script's directory on sys.path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import weapon_common as wc  # noqa: E402

TAU = math.tau


# ===========================================================================
#  1. PRIMITIVES THIS FAMILY NEEDS AND THE FRAMEWORK DOES NOT HAVE
# ===========================================================================

# `bead()` -- an octahedron for the ring's rune nodes -- lived here until pass 6
# and is DELETED rather than kept in case.  Its docstring argued that "eight flat
# triangles reads as a crystal chip at 0.3 m", and the plate said otherwise: at
# 0.3 m eight flat triangles read as eight flat triangles, laid in the ring's own
# plane, which is a sticker.  The rune nodes are now radial crystals from
# `wc.crystal`, which is the same vocabulary the heads use.  A primitive that has
# been superseded by a better one is not a spare part, it is a second answer to a
# settled question.


def cage(name, mat, y0, y1, r0, r1, bulge, struts, strut_r, seg=8, n=6):
    """OPENWORK: a barrel cage of `struts` legs bulging out between two rings.

    This is the structure a single loft cannot express, and the reason the staff
    family exists.  `loft` produces one closed surface; a window is the ABSENCE
    of surface, and the only honest way to author it without a boolean is to
    build the material that is left and then stop.

    `wc.loft_many` rather than one mesh per leg, because the six legs are six
    copies of the same ring-stack and want to be one part so the material
    partition stays per-part -- the same reasoning the framework already applies
    to a trident's prongs.

    The bulge is not decoration: a cage that goes straight from end to end is a
    cylinder with slots in it, and the head stops reading as a lantern.  The
    profile is symmetric about the middle for the same reason -- the first
    version had its peak at 34 percent and read as bamboo.

    n = 6 on the legs, not 5.  The extent band for this row is asserted, and a
    pentagon's own x extent is 1.809 * r rather than 2 * r, because five
    vertices are not symmetric about 180 degrees.  A hexagon is.
    """
    groups = []
    for k in range(struts):
        ang = TAU * k / struts
        cx, cz = math.cos(ang), math.sin(ang)
        st = []
        for i in range(seg + 1):
            t = i / float(seg)
            y = y0 + (y1 - y0) * t
            rr = wc.curve([(0.0, r0), (0.30, bulge * 0.80), (0.5, bulge),
                           (0.70, bulge * 0.80), (1.0, r1)], t)
            st.append((y, [(cx * rr + px, cz * rr + pz)
                           for (px, pz) in wc.ngon(n, strut_r)]))
        groups.append(st)
    return wc.loft_many(name, groups, mat)


def float_ring(name, mat, y, r_path, tube, n_major=24, n_minor=8,
               tilt=0.0, tilt_axis="X"):
    """A ring that circles the staff and does NOT touch it.

    A separate `oval_torus` whose hole is on the shaft axis and whose centre-path
    radius is four to five times the shaft's, so there is visible air on every
    side.  That is the whole idea of 悬浮环, and it is also a structural test:
    the object now contains geometry not connected to the rest of it, so the
    AABB, the tri count and the material partition all have to survive a piece
    that shares nothing with its neighbours but a name.

    n_major = 24 is a 15-degree step, so 90 / 15 is an integer and the ring puts
    a vertex exactly on 0, 90, 180 and 270 degrees.  Circular rings are the one
    case where the extent is EXACT rather than approximate -- `2 * (path + tube)`
    -- and that holds because of the segment count, not in spite of it.

    `tilt` IS WHAT MAKES THIS AN ORRERY AND NOT A HOOP, and it arrived by
    looking rather than by reasoning: pass 4 built three coaxial rings and the
    first-person plate turned a 1.55 m arcane staff into a pole with three
    bicycle rims on it.  The rings were correct as geometry -- exact extents,
    real air gap, three different radii -- and all three of them lived in the
    SAME PLANE, which is the one thing an armillary assembly never does.  Two
    tilts about different axes (see `tilt_axis`) put the three rings in three
    orbital planes, and the assembly immediately reads as something that could
    be read from and not as hardware.

    Note the costing: X stays exact under an X tilt because a rotation about X
    leaves every vertex's X untouched, so `2 * (path + tube)` survives for the
    axis the ring was generated in.  This is why the archetype's widest ring is
    the X-tilted one -- the extent band still has a closed form.
    """
    return wc.oval_torus(name, r_path, r_path, tube, mat, axis="Y",
                         n_major=n_major, n_minor=n_minor,
                         centre=(0.0, y, 0.0),
                         tilt_deg=tilt, tilt_axis=tilt_axis)


def levels_of(P, key):
    return [(float(a), float(b), float(c)) for (a, b, c) in P[key]]


# ===========================================================================
#  2. THE LOWER TWO THIRDS -- the same problem in all three archetypes
# ===========================================================================

def staff_base(P, mats):
    """Ferrule, shaft, grip and wrap.

    Shared deliberately.  The three archetypes are supposed to differ where it
    MATTERS -- the head -- and a staff's lower half is the same question every
    time.  Three copies would drift, and the drift would be invisible until two
    of them were held side by side.
    """
    parts = []
    n = int(P["n_shaft"])
    y_lo, y_hi = float(P["y_butt"]), float(P["y_neck"])
    r_lo = float(P["shaft_r_butt"])
    r_mid = float(P["shaft_r_mid"])
    r_hi = float(P["shaft_r_neck"])
    gl, gh = float(P["grip_lo"]), float(P["grip_hi"])
    gr = float(P["grip_r"])

    # SHAFT.  The profile is pinned at both ends and in the middle, so the taper
    # is a decision rather than whatever the loft happened to interpolate.
    stations = 11
    st = []
    for i in range(stations):
        t = i / float(stations - 1)
        y = y_lo + (y_hi - y_lo) * t
        r = wc.curve([(0.0, r_lo), (0.30, r_mid), (0.62, r_mid * 0.985),
                      (1.0, r_hi)], t)
        st.append((y, wc.ngon(n, r, ratio=0.94)))
    parts.append(wc.loft("StaffShaft", st, mats["wood"]))

    # FERRULE.  The end that goes in the ground, so it is iron and it is the
    # widest thing below the grip.
    fl, fr = float(P["ferrule_len"]), float(P["ferrule_r"])
    parts.append(wc.loft("StaffFerrule", [
        (y_lo - 0.002, wc.ngon(n, fr * 0.86)),
        (y_lo + fl * 0.20, wc.ngon(n, fr)),
        (y_lo + fl * 0.78, wc.ngon(n, fr * 0.97)),
        (y_lo + fl, wc.ngon(n, fr * 0.72)),
    ], mats["iron"]))

    # GRIP.  Leather, proud of the shaft: PART I puts the eye at 0.3-1 m and a
    # grip flush with the shaft reads as a painted band.
    #
    # THE GRIP IS NOW THE UNDERLAYER AND IT IS DELIBERATELY *SMALLER* THAN IT
    # WAS.  Passes 1-4 had the grip bulge to 1.045 * gr and the wrap oscillate
    # around 0.965 * gr, which meant the two parts were fighting for the same
    # millimetre: at the midpoint of the grip the wrap's rib peak and the
    # grip's own radius came out at 0.02128 m and 0.02132 m, four hundredths of
    # a millimetre apart.  The plates looked plausible -- the ribs did show --
    # so nothing failed, and that is exactly the problem: the wrap was visible
    # by arithmetic accident, and any future change to the grip profile would
    # have swallowed it silently.  A wrap that exists because two surfaces
    # happen to miss each other is not a wrap.
    parts.append(wc.loft("StaffGrip", [
        (gl, wc.ngon(n, gr * 0.86)),
        (gl + 0.030, wc.ngon(n, gr * 0.97)),
        ((gl + gh) * 0.5, wc.ngon(n, gr * 0.995)),
        (gh - 0.030, wc.ngon(n, gr * 0.955)),
        (gh, wc.ngon(n, gr * 0.82)),
    ], mats["leather"]))

    # WRAP -- ribs as GEOMETRY.  This line has no texture pipeline, so a smooth
    # grip at 0.3 m reads as a machined tube; the ribs are the only thing that
    # says cord.  The rib amplitude is now a real 1.2 mm proud of the path and
    # the troughs sink 0.9 mm BELOW the leather under them, so the cord reads as
    # cord wound into a groove -- which is what a grip wrap physically is -- and
    # it does so by construction rather than by coincidence.
    #
    # THE AMPLITUDE CAME DOWN BY MORE THAN HALF, AND THE NUMBER THAT MATTERS IS
    # THE RATIO AND NOT THE DEPTH.  At 0.0028 over a 0.0354 m pitch the wrap
    # rendered as THREADS -- a screw, not a cord -- because peak-to-trough over
    # pitch was 0.0056 / 0.0354, or 1 : 6.3.  0.0012 gives 1 : 14.8.  This is a
    # scale cue rather than a taste call: a hand at 0.3 m reads the pitch AND the
    # depth, and their RATIO is what says rope rather than machining.  Shrinking
    # the pitch instead would have been the wrong lever -- finer threads are
    # still threads.
    ribs = int(P.get("ribs", 6))
    steps = ribs * 4
    band = []
    a0, a1 = gl + 0.016, gh - 0.016
    for i in range(steps + 1):
        t = i / float(steps)
        y = a0 + (a1 - a0) * t
        base = wc.curve([(0.0, gr * 1.010), (0.5, gr * 1.020), (1.0, gr * 0.995)], t)
        pulse = 0.0012 * math.sin(t * TAU * ribs)
        band.append((y, wc.ngon(n, base + pulse)))
    parts.append(wc.loft("StaffWrap", band, mats["cord"]))

    # Two collars at the ends of the grip: what actually stops the hand.
    #
    # THEY HAD TO MOVE OUT WITH THE WRAP, and this is the second time in the
    # same function that two parts were competing for one diameter.  Raising the
    # cord to 1.020 * gr + 0.0012 put the ribs at 0.02201 m, and the collars
    # were sitting at 1.14 * gr = 0.02326 m -- proud of a grip that no longer
    # existed and BURIED under the wrap that replaced it.  Rectifying one
    # overlap created the next one, which is what happens when two surfaces are
    # tuned against each other instead of against a stated stack: leather
    # inside, cord on top of it, collar over the cord.
    #
    # The stack, in metres for a 0.0204 m grip radius:
    #   grip core   <= 0.995 * gr = 0.02030
    #   cord trough    1.010 * gr - 0.0012 = 0.01940   (beds into the leather)
    #   cord rib       1.020 * gr + 0.0012 = 0.02201
    #   collar bump    1.280 * gr          = 0.02611   (4.1 mm over the rib)
    for tag, y in (("Low", gl), ("High", gh)):
        parts.append(wc.loft("StaffCollar" + tag, [
            (y - 0.014, wc.ngon(n, gr * 0.90)),
            (y - 0.005, wc.ngon(n, gr * 1.28)),
            (y + 0.004, wc.ngon(n, gr * 1.20)),
            (y + 0.016, wc.ngon(n, gr * 0.96)),
        ], mats["brass_dark"]))

    # THE MID-SHAFT BAND, AND IT IS THE FIX FOR THE LARGEST THING ON THE MODEL.
    # The 3/4 plate of the short archetype is 1.06 m tall and the shaft is 78
    # percent of that: from the head collar down to the grip the weapon was one
    # uninterrupted brown pole, and the eye had exactly two landmarks -- a head
    # at the top and a grip at the bottom -- with 0.6 m of nothing between them.
    # A long shaft needs to be broken into readable LENGTHS or it stops being a
    # shaft and becomes a pole, and the cheapest honest way to do that is a
    # fitting that is already in the family's vocabulary rather than a new part.
    #
    # The shaft tapers 0.0166 -> 0.0182 -> 0.0136 m over its whole length, which
    # is a real taper and completely invisible: 1.6 mm over 1.28 m is 0.1
    # degrees.  The band is 7.4 mm proud, which is visible at the 0.3-1 m the
    # contract puts the eye at, and it sits at the same fraction on all three
    # archetypes because it is the SAME function -- which is also what keeps
    # them reading as one family rather than three staffs.
    band_y = y_lo + (y_hi - y_lo) * float(P["band_at"])
    band_r = float(P["band_r"])
    parts.append(wc.loft("StaffBand", [
        (band_y - 0.010, wc.ngon(n, band_r * 0.80)),
        (band_y - 0.003, wc.ngon(n, band_r)),
        (band_y + 0.004, wc.ngon(n, band_r * 1.06)),
        (band_y + 0.011, wc.ngon(n, band_r * 0.78)),
    ], mats["brass_dark"]))
    return parts


def head_collar(P, mats, y0, r, mat, name="HeadCollar", ln=None, rr=None):
    """The metal socket the head is seated in -- on all three archetypes, which
    is what makes them one family rather than three unrelated staffs.

    `ln` / `rr` are overridable because the middle archetype needs a SECOND one
    above its cage: an openwork head that ends in mid-air is a broken cage, and
    the two sockets together are what make the cage read as a section of the
    staff instead of its end.

    `mat` is explicit and is NOT left to the caller's memory.  Pass 1 built every
    one of these out of `iron`, and because the profile flares to 1.5 times the
    shaft and then tapers, a 0.086-albedo dark metal under one sun rendered as a
    BLACK ONION sitting under every head -- the first thing the eye found, on the
    one part of the weapon that is supposed to be a detail.
    """
    n = int(P["n_shaft"])
    ln = float(P["head_collar_len"]) if ln is None else float(ln)
    rr = float(P["head_collar_r"]) if rr is None else float(rr)
    # A LIP AND A GROOVE, and they are not ornament.  Pass 1 and pass 2 both
    # rendered these sockets as a plain khaki CUP: a smooth flare straight into a
    # taper has no edge for the shading limiter to catch, so the whole fitting
    # read as one extruded plastic part with no scale cue.  The swell at 0.34 and
    # the cut at 0.46 give it a rim and a shadow line, which is what tells the eye
    # it is a machined collar on a wooden shaft.
    return wc.loft(name, [
        (y0 - 0.006, wc.ngon(n, r * 0.92)),
        (y0 + ln * 0.10, wc.ngon(n, rr)),
        (y0 + ln * 0.34, wc.ngon(n, rr * 1.035)),
        (y0 + ln * 0.46, wc.ngon(n, rr * 0.790)),
        (y0 + ln * 0.62, wc.ngon(n, rr * 0.945)),
        (y0 + ln * 0.84, wc.ngon(n, rr * 0.840)),
        (y0 + ln, wc.ngon(n, rr * 0.640)),
    ], mat)


def _satellites(parts, P, mats, prefix, lv, count_key="shard_sats",
                scale_key="sat_scale", splay_key="sat_splay",
                rise_key="sat_rise"):
    """The splayed crystals around a main head crystal.

    Factored out because two archetypes grow them and the third does not: a
    cluster is what gives a head WIDTH as well as height, and one bipyramid on a
    stick is a spear, which is not a staff.  They are COLD, the same mineral as
    the crystal they surround; see the note on colour below.

    EVERY SATELLITE USED TO BE THE SAME LENGTH AT THE SAME SPLAY, AND THE PLATE
    SHOWED EXACTLY THAT.  Four equal crystals at right angles on a common splay
    is a ROSETTE -- the short staff's head rendered as a pinwheel, four petals
    of identical size around a bud.

    THE COUNT WAS THE REAL CULPRIT, AND THE EVIDENCE WAS ALREADY ON DISK.  Pass 5
    tried to break the rosette with a size order -- four different lengths, four
    different splays -- and the head still read as a lotus, because size was
    never what made it a flower.  What makes it a flower is FOUR-FOLD RADIAL
    SYMMETRY ABOUT A CONTRASTING CENTRE, and no amount of stagger removes that.
    The proof was sitting in the same contact sheet the whole time: the long
    archetype has THREE satellites and its head has never once read as a flower,
    because three-fold spacing has an odd satellite that lands opposite nothing.
    So the short archetype goes to three as well.

    `sat_rise` is a per-index HEIGHT offset, and it is the last of the three
    flower cues.  Even at three, satellites all rooted at one height lie on a
    ring; rooting them at three heights makes the cluster read as crystals that
    grew where they grew.

    `sat_scale` / `sat_splay` / `sat_rise` are per-index lists in the row, not
    scalars, and they are authored rather than random: 参数化 != 参数随机化.  A
    fixed profile like (1.00, 0.72, 0.86) is a structural archetype -- the same
    cluster every build, diffable, and reason-about-able -- where a random draw
    per build would make the row unreproducible and the extent unassertable.
    Lengths are checked against the count so a five-satellite row cannot silently
    reuse a three-entry profile.
    """
    count = int(P[count_key])
    splay = math.radians(float(P["shard_splay"]))
    off = float(P["shard_offset"])
    ln = float(P["shard_len"])
    scales = [float(x) for x in P.get(scale_key) or []] or [1.0] * count
    splay_off = [float(x) for x in P.get(splay_key) or []] or [0.0] * count
    rise = [float(x) for x in P.get(rise_key) or []] or [0.0] * count
    for tag, prof in ((scale_key, scales), (splay_key, splay_off),
                      (rise_key, rise)):
        if len(prof) != count:
            raise SystemExit(
                "STF  satellite profile %s is %d long but the row has %d "
                "satellites (%s=%d)" % (tag, len(prof), count, count_key, count))
    for k in range(count):
        ang = TAU * k / count
        base = (off * math.cos(ang),
                float(P["shard_y"]) + rise[k],
                off * math.sin(ang))
        sp = splay + math.radians(splay_off[k])
        d = (math.sin(sp) * math.cos(ang), math.cos(sp),
             math.sin(sp) * math.sin(ang))
        parts.append(wc.crystal("%s%d" % (prefix, k), mats["crystal"],
                                base, ln * scales[k], lv, direction=d, n=6))
    return count


# ===========================================================================
#  3. 短杖 · SHARD -- crystal + emission, at the shortest size
# ===========================================================================

def build_shard(P, mats, rig):
    parts = staff_base(P, mats)
    y_neck = float(P["y_neck"])
    parts.append(head_collar(P, mats, y_neck, float(P["collar_r_at_neck"]),
                            mats["brass_dark"]))

    # THE CRYSTAL.  The point of this archetype: a shape with two POINTS, whose
    # facets twist.  Three levels and not two -- see `wc.crystal` for why a bare
    # bipyramid reads as a leaf.
    c0, c1 = float(P["crystal_y0"]), float(P["crystal_y1"])
    parts.append(wc.crystal("HeadCrystal", mats["crystal"], (0.0, c0, 0.0),
                            c1 - c0, levels_of(P, "crystal_levels"),
                            n=int(P["crystal_n"])))

    sat = _satellites(parts, P, mats, "HeadShard", levels_of(P, "shard_levels"))

    rig.socket("SOC_GRIP", (0.0, float(P["grip_lo"]) + 0.10, 0.0))
    rig.socket("SOC_HEAD", (0.0, c1, 0.0))
    rig.socket("FX_CORE", (0.0, c0 + (c1 - c0) * 0.42, 0.0))
    rig.note("shard   crystal %.3f -> %.3f m, %d satellites at %.0f deg from "
             "r %.4f" % (c0, c1, sat, float(P["shard_splay"]),
                         float(P["shard_offset"])))
    return parts


# ===========================================================================
#  4. 中杖 · LATTICE -- openwork, at the middle size
# ===========================================================================

def build_lattice(P, mats, rig):
    parts = staff_base(P, mats)
    y_neck = float(P["y_neck"])
    parts.append(head_collar(P, mats, y_neck, float(P["collar_r_at_neck"]),
                             mats["brass_dark"]))

    # THE UPPER COLLAR -- the cage ends in a socket, not in mid-air.
    parts.append(head_collar(P, mats, float(P["cap_y"]),
                             float(P["shaft_r_neck"]),
                             mats["brass_dark"], name="HeadCap",
                             ln=float(P["cap_len"]), rr=float(P["cap_r"])))

    # THE CAGE.  Dark metal on purpose: the bars are the frame the light is seen
    # THROUGH, so they have to be darker than what they frame.  Two corrections
    # in one line.  Pass 1 built it out of `brass`, which under one sun rendered
    # as BAMBOO -- a pale strut against a grey background is a strut with no
    # window in it.  Pass 2 built it out of `iron`, which is 0.086 albedo at 0.30
    # metallic, and rendered as BLACK RUBBER: too dark to hold a highlight, so
    # the legs lost their roundness and the cage read as wire insulation.  What
    # the legs need is a dark albedo WITH a specular to travel along them, which
    # is `steel_dark`: 0.235 albedo at 0.42 metallic.
    parts.append(cage("HeadCage", mats["steel_dark"],
                      float(P["cage_y0"]), float(P["cage_y1"]),
                      float(P["cage_r_lo"]), float(P["cage_r_hi"]),
                      float(P["cage_bulge"]), int(P["cage_struts"]),
                      float(P["cage_strut_r"]), seg=int(P["cage_seg"]), n=6))

    # THE CORE, inside the cage, visible only THROUGH the windows -- which is
    # the difference between openwork and a hole.  The light has to be behind
    # something for the window to be a window.
    parts.append(wc.crystal("HeadCore", mats["crystal"],
                            (0.0, float(P["core_y0"]), 0.0),
                            float(P["core_y1"]) - float(P["core_y0"]),
                            levels_of(P, "core_levels"),
                            n=int(P["crystal_n"])))

    # TOP FINIAL.  Above the upper collar, so the cage reads as a SECTION of the
    # staff rather than as its end.
    parts.append(wc.crystal("HeadFinial", mats["crystal_warm"],
                            (0.0, float(P["finial_y0"]), 0.0),
                            float(P["finial_y1"]) - float(P["finial_y0"]),
                            levels_of(P, "finial_levels"),
                            n=int(P["crystal_n"])))

    rig.socket("SOC_GRIP", (0.0, float(P["grip_lo"]) + 0.10, 0.0))
    rig.socket("SOC_HEAD", (0.0, float(P["finial_y1"]), 0.0))
    rig.socket("FX_CORE", (0.0, (float(P["core_y0"]) + float(P["core_y1"])) * 0.5, 0.0))
    rig.socket("FX_RUNE", (0.0, float(P["cage_y0"]) - 0.004, 0.0))
    rig.note("lattice cage %.3f -> %.3f m, %d struts bulging to %.4f m "
             "(core r %.4f inside)" % (float(P["cage_y0"]), float(P["cage_y1"]),
                                       int(P["cage_struts"]),
                                       float(P["cage_bulge"]),
                                       float(P["core_levels"][1][1])))
    return parts


# ===========================================================================
#  5. 长杖 · ORRERY -- floating rings + VFX anchors, at the longest size
# ===========================================================================

def build_orrery(P, mats, rig):
    parts = staff_base(P, mats)
    y_neck = float(P["y_neck"])
    parts.append(head_collar(P, mats, y_neck, float(P["collar_r_at_neck"]),
                             mats["brass_dark"]))

    # THE FLOATING RINGS.  Nothing joins them to the shaft and that is the
    # design: the staff is not a stick with rings on it, it is a stick that three
    # rings have decided to orbit.  Which is also why the widest one carries the
    # rune nodes -- the float needs a reason visible ON THE MODEL, or it reads as
    # a modelling error instead of as magic.
    #
    # `steel_dark`, AND THE MATERIAL IS NOT A TASTE CALL.  Passes 1-4 built these
    # out of `chain_link`, which is 0.474 albedo at 0.20 metallic -- a value
    # MEASURED for chain links, where the job is to stay visible in a moving
    # fistful against a bright sky.  On a static 0.26 m hoop that same value
    # makes the ring the brightest object on the model, and the first-person
    # plate read as three galvanised hula hoops with the staff as a handle
    # bolted through them.  The rings have the opposite job here: they are a
    # FRAME for the rune nodes, and a frame has to be darker than what it frames
    # or the accent has nothing to be an accent against.  0.235 albedo puts the
    # steel below the wood of the shaft and lets the amber nodes carry the eye.
    #
    # AND THE THREE RINGS ARE IN THREE PLANES.  See `float_ring` for why: three
    # coaxial rings at three radii are three hoops, and an orrery is defined by
    # its rings intersecting at different angles.  Ring widths also come
    # down from 0.100 / 0.118 / 0.088 to 0.076 / 0.086 / 0.064 m of path radius;
    # at the old size the assembly was 6.5 times the shaft diameter, which is
    # wider than the character's own shoulders.
    rings = P["rings"]
    for i, row in enumerate(rings):
        y, r_path, tube = float(row[0]), float(row[1]), float(row[2])
        tilt = float(row[3]) if len(row) > 3 else 0.0
        t_ax = str(row[4]) if len(row) > 4 else "X"
        parts.append(float_ring("FloatRing%d" % i, mats["steel_dark"],
                                y, r_path, tube, tilt=tilt, tilt_axis=t_ax))

    # THE RUNE NODES.  Pass 1 made these 0.0120 across and they rendered as dust
    # -- three pale specks on a hoop, which is worse than nothing because the eye
    # reads them as dirt.  A node has to be big enough to be an object.
    #
    # THEY ARE SPIKES NOW, NOT BEADS, AND THE PASS THAT CHANGED THEM IS THE ONE
    # THAT WENT LOOKING FOR WHY THEY READ AS STICKERS.  Pass 5 sat eight
    # octahedra of 0.0165 m astride the ring path: geometrically they were beads
    # threaded on a hoop, and on the plate they were eight flat amber RHOMBI laid
    # against the steel -- because an octahedron viewed near its own axis IS a
    # rhombus, flat-shaded, in the same plane as the ring, and high contrast
    # against a dark frame.  Enlarging it would only have made a bigger sticker,
    # which is the same trap as the teardrop crystal: the shape was wrong, not
    # the size.
    #
    # A CRYSTAL POINTING RADIALLY OUTWARD cannot read as a sticker from any
    # angle: its silhouette is a wedge on three of them and a hexagon on the
    # fourth, and it is the SAME vocabulary as the head, so the family reads as
    # one object rather than as a staff with gems glued to it.  It also makes the
    # extent honest and closed-form again -- a radial spike's apex is at exactly
    # `br_path + bead_len` on the axis its angle lands on, so a count that is a
    # multiple of 4 puts one on X and one on Z and makes X == Z.
    br_i = int(P["bead_ring"])
    by, br_path = float(rings[br_i][0]), float(rings[br_i][1])
    beads = int(P["bead_count"])
    lv_bead = levels_of(P, "bead_levels")
    for k in range(beads):
        ang = TAU * k / beads
        d = (math.cos(ang), 0.0, math.sin(ang))
        parts.append(wc.crystal("RuneNode%d" % k, mats["crystal_warm"],
                                (br_path * d[0], by, br_path * d[2]),
                                float(P["bead_len"]), lv_bead, direction=d, n=6))

    # THE HEAD -- the same crystal vocabulary as the short archetype, so the
    # family reads as one family.
    c0, c1 = float(P["crystal_y0"]), float(P["crystal_y1"])
    parts.append(wc.crystal("HeadCrystal", mats["crystal"], (0.0, c0, 0.0),
                            c1 - c0, levels_of(P, "crystal_levels"),
                            n=int(P["crystal_n"])))
    sat = _satellites(parts, P, mats, "HeadShard", levels_of(P, "shard_levels"))

    rig.socket("SOC_GRIP", (0.0, float(P["grip_lo"]) + 0.10, 0.0))
    rig.socket("SOC_HEAD", (0.0, c1, 0.0))
    rig.socket("FX_CORE", (0.0, c0 + (c1 - c0) * 0.42, 0.0))
    # The rune anchor sits ON the first node, not on the shaft: an effect anchor
    # that is not on the geometry it decorates is a point nobody can author to.
    rig.socket("FX_RUNE", (br_path, by, 0.0))
    # Trail anchors -- a staff is swung along its own length, so its trail is a
    # SEGMENT and needs both of its ends.
    rig.socket("FX_TRAIL_A", (0.0, float(P["trail_a_y"]), 0.0))
    rig.socket("FX_TRAIL_B", (0.0, float(P["trail_b_y"]), 0.0))
    rig.note("orrery  %d floating rings (widest path r %.4f, air gap %.4f m), "
             "%d rune spikes across %.4f m, %d satellites"
             % (len(rings), br_path, br_path - float(P["shaft_r_neck"]),
                beads, float(P["bead_len"]) * 2.0, sat))
    return parts


# ===========================================================================
#  6. ROW DISPATCH
# ===========================================================================

BUILDERS = {
    "shard": build_shard,
    "lattice": build_lattice,
    "orrery": build_orrery,
}

# Flat parts are the crystal family, and this is the one place in the line where
# smooth shading is not merely a taste call: a smoothed crystal is a blob, and
# the blob and the gem have identical vertices, extents and triangle counts, so
# nothing else in the toolchain can tell them apart.
SHADING = {
    "smooth_angle": 30.0,
    "flat": ("HeadCrystal", "HeadCore", "HeadFinial", "HeadShard0",
             "HeadShard1", "HeadShard2", "HeadShard3", "HeadShard4",
             "RuneNode0", "RuneNode1", "RuneNode2", "RuneNode3",
             "RuneNode4", "RuneNode5", "RuneNode6", "RuneNode7"),
    "soft": ("StaffGrip", "StaffWrap", "StaffShaft"),
}


def build_row(row, spec):
    part = str(row.get("part") or row.get("id"))
    if part not in BUILDERS:
        raise SystemExit("STF  no builder for part %r (have: %s)"
                         % (part, ", ".join(sorted(BUILDERS))))

    mats = wc.palette(sorted({
        "wood", "iron", "brass_dark", "leather", "cord", "crystal",
        "crystal_warm", "steel_dark",
    }))

    rig = wc.Rig("STF")
    rig.extend(BUILDERS[part](row, mats, rig))

    for p in rig.parts:
        if p.name in SHADING["flat"]:
            wc.shade(p, flat=True)
        elif p.name in SHADING["soft"]:
            wc.shade(p, None)
        else:
            wc.shade(p, SHADING["smooth_angle"])

    rig.note("part=%s  world_name=%s" % (part, row.get("world_name", "")))
    return rig


def main():
    wc.run("STF", build_row)


if __name__ == "__main__":
    main()
