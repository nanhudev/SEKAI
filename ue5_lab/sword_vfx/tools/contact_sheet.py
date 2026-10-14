"""Tile the review frames into one contact sheet.

    python tools/contact_sheet.py [render_dir] [cols] [out.png]

WHY, AND WHAT IT IS NOT FOR

    A single sheet is how a reviewer gets the overview: five cameras of the same
    stage, side by side, so that "does it hold on a bright background" can be
    answered at a glance rather than by opening five files.

    It is NOT for judging detail. Downsampling 1920x1080 into a fifth of a sheet
    invents and destroys exactly the things this batch is about - a 1-2 px scar
    core, a black void 1 px wide, whether three scars still read as three. The
    project has already been bitten by this once ("do not judge overlap or
    legibility on a thumbnail: resampling lies"). So the sheet carries each
    frame's own resolution in its label, and any judgement about an edge, a seam
    or a count is made on the full-size frame, never here.

    The label also carries the frame's mean luminance, because a review sheet is
    the easiest place in the world for a black or blown-out frame to hide.
"""
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def mean_lum(img):
    small = img.convert("RGB").resize((64, 36))
    px = list(small.getdata())
    return sum(0.2126 * r + 0.7152 * g + 0.0722 * b for r, g, b in px) / float(len(px))


def main():
    render_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "render")
    cols = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(render_dir, "contact_sheet.png")

    files = sorted(f for f in os.listdir(render_dir)
                   if f.startswith("review_") and f.endswith(".png"))
    if not files:
        print("no review_*.png in %s" % render_dir)
        return 1

    pad, label_h = 12, 30
    thumbs = []
    for fn in files:
        img = Image.open(os.path.join(render_dir, fn)).convert("RGB")
        lum = mean_lum(img)
        thumbs.append((fn, img, lum))

    tw = max(t[1].width for t in thumbs)
    th = max(t[1].height for t in thumbs)
    rows = (len(thumbs) + cols - 1) // cols
    W = cols * tw + (cols + 1) * pad
    H = rows * (th + label_h) + (rows + 1) * pad

    sheet = Image.new("RGB", (W, H), (16, 16, 18))
    draw = ImageDraw.Draw(sheet)

    for i, (fn, img, lum) in enumerate(thumbs):
        r, c = divmod(i, cols)
        x = pad + c * (tw + pad)
        y = pad + r * (th + label_h + pad)
        sheet.paste(img, (x, y + label_h))
        draw.text((x + 4, y + 8),
                  "%s   %dx%d   mean lum %.1f" % (fn, img.width, img.height, lum),
                  fill=(235, 235, 235))
        draw.rectangle([x - 1, y + label_h - 1, x + tw, y + label_h + th],
                       outline=(70, 70, 74))

    sheet.save(out)
    print("wrote %s  (%d frames, %dx%d)" % (out, len(thumbs), W, H))
    for fn, img, lum in thumbs:
        print("  %-34s %5dx%-5d mean lum %6.2f" % (fn, img.width, img.height, lum))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
