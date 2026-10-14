"""Split a rendered frame into SKY / MIDDLE / GROUND bands and report each.

    C:/Users/Administrator/AppData/Local/Programs/Python/Python311/python.exe \\
        tools/split_luma.py <dir> [prefix]

WHY A GLOBAL MEAN IS NOT ENOUGH

    P27 measured every rung of its lighting ladder with one number: the mean
    luma of the whole 512x512 frame. That number went UP when the sun's
    intensity went up, and it went up for two completely different reasons -
    the ground got lit, or the sky got brighter - and the frame cannot say
    which. The review lab's requirement (section 30: effects must hold on a
    BRIGHT BACKGROUND) is about the surface BEHIND the effect, so "the sky is
    now bright" does not satisfy it and would not have been noticed.

    There is a second reason this exists. The sun in L_SwordVFX_Lab is built
    with `(-42.0, 35.0, 0.0)` passed into `unreal.Rotator(*t)`, which expands
    as (ROLL, PITCH, YAW) - so the intended pitch of -42 became ROLL, and the
    actual PITCH is +35, aiming the light UP INTO THE SKY. A frame whose top
    band is bright and whose bottom band is black is the fingerprint of exactly
    that mistake, and this tool is what renders that fingerprint readable.

READING IT

    SKY / MID / GROUND are the top, middle and bottom thirds. `ratio` is
    GROUND/SKY: for a lit outdoor scene it should be within roughly 0.3-3.0.
    A ratio far below that - with a bright SKY and a near-black GROUND - is not
    a lighting level, it is a light aimed the wrong way.

    Bands are means of 8-bit luminance, so 0 is black and 255 is white.
"""
import glob
import os
import sys

try:
    from PIL import Image
except ImportError:
    print("PIL not available in this interpreter")
    raise SystemExit(2)


def luma_bands(path):
    im = Image.open(path).convert("L")
    w, h = im.size
    t = max(1, h // 3)
    bands = []
    for i in range(3):
        y0 = i * t
        y1 = h if i == 2 else (i + 1) * t
        box = im.crop((0, y0, w, y1))
        px = list(box.getdata())
        bands.append(sum(px) / float(len(px)) if px else 0.0)
    allpx = list(im.getdata())
    overall = sum(allpx) / float(len(allpx)) if allpx else 0.0
    return bands, overall, (w, h)


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    directory = argv[0]
    prefix = argv[1] if len(argv) > 1 else ""
    if not os.path.isdir(directory):
        print("not a directory: %s" % directory)
        return 2
    files = sorted(glob.glob(os.path.join(directory, prefix + "*.png")))
    if not files:
        print("no .png under %s%s" % (directory, (" matching " + prefix) if prefix else ""))
        return 1
    print("=" * 88)
    print("%-34s %7s %7s %7s %8s %8s" %
          ("frame", "SKY", "MID", "GROUND", "overall", "G/S"))
    print("-" * 88)
    for f in files:
        try:
            (sky, mid, grd), overall, size = luma_bands(f)
        except Exception as exc:
            print("%-34s unreadable: %s" % (os.path.basename(f)[:34], exc))
            continue
        ratio = (grd / sky) if sky > 0.5 else float("inf")
        note = ""
        if sky > 60 and grd < 12:
            note = "  <-- SKY LIT, GROUND BLACK: light aimed up?"
        print("%-34s %7.1f %7.1f %7.1f %8.2f %8s%s"
              % (os.path.basename(f)[:34], sky, mid, grd, overall,
                 ("%.2f" % ratio) if ratio != float("inf") else "inf", note))
    print("=" * 88)
    print("bands are top/middle/bottom thirds of %s" % files[0])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
