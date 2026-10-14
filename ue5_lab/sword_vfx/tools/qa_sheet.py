"""Build a downscaled contact sheet + singles from the QA camera frames.

    python tools/qa_sheet.py <render_dir> <out_dir>

The engine writes 1920x1080 PNGs at ~2.2 MB each, which is right for review and
too large to look at inline. This makes a grid sheet and one smaller copy of
each frame, and NEVER touches the originals.

Downscaling is for the overview only: at these sizes fine detail is lost, so
anything that has to be judged closely (edge weight, whether a scar reads,
whether a mark is a mark) must be checked with a CROP of the full-resolution
file, not from this sheet. This project has already been caught by that
difference once - a thumbnail can fabricate both "these overlap" and "this
reads as three marks".
"""
import os
import sys

from PIL import Image

COLS = 3
CELL = (620, 349)      # 16:9, small enough to open inline


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    src, out = argv[0], argv[1]
    os.makedirs(out, exist_ok=True)
    names = ["review_fp", "review_tp34", "review_side", "review_top",
             "review_long"]
    made = []
    thumbs = []
    for n in names:
        p = os.path.join(src, n + ".png")
        if not os.path.isfile(p):
            print("missing: %s" % p)
            continue
        im = Image.open(p).convert("RGB")
        big = im.size
        t = im.resize(CELL, Image.LANCZOS)
        # label drawn as a filename instead of on the image: writing text needs
        # a font, and a missing font is a worse failure than a file name.
        q = os.path.join(out, n + "_small.png")
        t.save(q)
        made.append(q)
        thumbs.append((n, t, big))
        print("%-12s %sx%s -> %s" % (n, big[0], big[1], q))

    if thumbs:
        rows = (len(thumbs) + COLS - 1) // COLS
        sheet = Image.new("RGB", (COLS * CELL[0], rows * CELL[1]), (24, 24, 24))
        for i, (n, t, big) in enumerate(thumbs):
            sheet.paste(t, ((i % COLS) * CELL[0], (i // COLS) * CELL[1]))
        sp = os.path.join(out, "qa_contact_sheet.png")
        sheet.save(sp)
        print("sheet: %s  (%d cells, order: %s)"
              % (sp, len(thumbs), ", ".join(n for n, _, _ in thumbs)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
