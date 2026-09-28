#!/usr/bin/env python3
"""Thumbnail Test — ART DIRECTION PASS 04, PART K / §22.

    python tools/thumb_test.py <frame.png> [out.png] [scale] [--all]

WHY THIS EXISTS
---------------
§22 is the round's most important new acceptance test and it is a test the eye
cannot perform reliably at full resolution: an artist who has just spent a day
on a scene will read the ROAD, the GRASS MASS, the ROCK FORMATION and the
MOUNTAIN out of a 1280x720 frame because they know where those things are.
Shrunk to a quarter, the same frame answers the question that actually matters:

    does the picture still say what it is?

Measured on the R01 hero frame (d=470) the answer was NO — the thumbnail was one
field of grey-green noise, for a reason that is arithmetic rather than aesthetic.
The palette put grass, soil, stone and town paving all within a few percent of
neutral, so once the picture was small enough that shape detail stopped
resolving, there was nothing left to group by.

WHAT IT REPORTS
---------------
SKY is reported separately and EXCLUDED from everything else. A quarter-scale
frame with a horizon in it is 30-45% sky, and sky is a single large clean blue —
left in, it outvotes the entire landscape and the test reports "blue, 2 masses"
for every frame ever rendered, including good ones. The question §22 asks is
about the land, so the land is what gets measured.

Hue histogram over the remaining pixels, weighted by saturation x value so a
pale pixel does not outvote a coloured one, with neutrals counted separately.
`MASSES` is the number of hue families (including neutral) holding at least 4%
of that weight — a designed landscape has five or six; a grey sheet has one.

`NEUTRAL` is the fraction of non-sky pixels below a tenth saturation. This is
the single number the color-grouping pass moves.

This is a proxy, not a verdict. It cannot tell warm light from mud. It can tell
"one mass" from "six masses", which is the thing that was wrong.
"""

import os
import sys

from PIL import Image

HUES = [
    (0, "red"), (20, "orange"), (45, "yellow"), (70, "yellow-green"),
    (100, "green"), (150, "teal"), (190, "blue"), (250, "violet"),
    (290, "magenta"), (340, "red"),
]

BINS = 18          # 20 PIL units each ~ 28 degrees
MIN_SHARE = 0.04   # a "mass" is at least 4% of the weighted pixels
NEUTRAL_S = 24     # out of 255 ~ a tenth


def hue_name(deg: float) -> str:
    name = HUES[0][1]
    for lo, n in HUES:
        if deg >= lo:
            name = n
    return name


def is_sky(r: int, g: int, b: int, v: int) -> bool:
    """Blue, brighter than it is warm, and light. The river fails the last test
    often enough that it does not matter: a river is 2% of a frame and sky is
    40%."""
    return (b - r) >= 18 and b >= g and v >= 90


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(src)[0] + "_thumb.png"
    scale = float(sys.argv[3]) if len(sys.argv) > 3 else 0.25
    if not os.path.isfile(src):
        print("no such frame: %s" % src)
        return 2

    img = Image.open(src).convert("RGB")
    w, h = img.size
    tw = max(1, int(round(w * scale)))
    th = max(1, int(round(h * scale)))
    small = img.resize((tw, th), Image.BOX)
    small.save(dst)

    rgb = small.tobytes()
    data = small.convert("HSV").tobytes()

    weight = [0.0] * BINS
    neutral = 0
    sky = 0
    ground = 0
    v_hist = [0] * 8
    for i in range(0, len(data), 3):
        hh = data[i]
        ss = data[i + 1]
        vv = data[i + 2]
        if is_sky(rgb[i], rgb[i + 1], rgb[i + 2], vv):
            sky += 1
            continue
        ground += 1
        v_hist[min(7, vv // 32)] += 1
        deg = hh * 360 // 255
        bin_i = min(BINS - 1, deg // 20)
        if ss < NEUTRAL_S:
            neutral += 1
            # A neutral still occupies a hue slot, at a small fixed weight —
            # otherwise "everything is grey" would report zero masses, which is
            # true but hides how much of the frame each grey is.
            weight[bin_i] += 0.10 * (vv / 255.0)
            continue
        if vv < 24:
            continue
        weight[bin_i] += (ss / 255.0) * (vv / 255.0)

    tot_w = sum(weight) or 1.0
    ranked = sorted(range(BINS), key=lambda i: -weight[i])
    masses = sum(1 for i in range(BINS) if weight[i] / tot_w >= MIN_SHARE)
    if sky / max(sky + ground, 1) >= MIN_SHARE:
        masses += 1

    denom = max(ground, 1)
    print("frame      %s  (%dx%d -> %dx%d)" % (os.path.basename(src), w, h, tw, th))
    print("thumb      %s" % dst)
    print("SKY        %.1f%% of the frame, excluded from the counts below"
          % (100.0 * sky / max(sky + ground, 1)))
    print("MASSES     %d   (hue families holding >= %d%% of the LAND weight%s)"
          % (masses, int(MIN_SHARE * 100), ", sky counted as one" if masses else ""))
    print("NEUTRAL    %.1f%% of land pixels below 10%% saturation"
          % (100.0 * neutral / denom))
    print("land hue masses, largest first:")
    for i in ranked[:6]:
        share = 100.0 * weight[i] / tot_w
        if share < 0.5:
            continue
        print("   %5.1f%%   %3d-%3d deg   %s"
              % (share, i * 20, i * 20 + 20, hue_name(i * 20 + 10)))
    spread = " ".join("%d" % (100 * c // denom) for c in v_hist)
    print("land value deciles (dark -> bright, %% of land): %s" % spread)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
