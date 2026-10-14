"""Composite the Blender review renders into a sheet + silhouettes.

    python tools/blender/asset_sheet.py <render_dir> <out_dir>
        [--cols N] [--bg 0.20]

The review rig writes every plate with `film_transparent`, which is what makes
the silhouette exact rather than thresholded.  This turns one render pass into
the two things PART N actually asks for:

  * `<name>_p.png`  the plate over a mid-grey field
  * `<name>_s.png`  the silhouette, black on white
  * `SHEET.png`     both, side by side

Mid-grey and not white: a steel blade at value 0.74 against a white field has
no silhouette edge, and every review of it becomes a review of the background.
"""

import os
import sys
import glob

from PIL import Image, ImageDraw

GAMMA = 2.2


def srgb(lin):
    v = max(0.0, min(1.0, lin))
    return int(round(255.0 * (v ** (1.0 / GAMMA))))


def plate(path, bg_lin):
    im = Image.open(path).convert("RGBA")
    bg = (srgb(bg_lin * 0.9), srgb(bg_lin * 0.93), srgb(bg_lin))
    out = Image.new("RGB", im.size, bg)
    out.paste(im, (0, 0), im)
    # a gentle vignette-free gradient so the background is not a dead flat field
    grad = Image.new("L", (1, im.size[1]))
    for y in range(im.size[1]):
        grad.putpixel((0, y), int(18.0 * (1.0 - y / float(im.size[1]))))
    shade = grad.resize(im.size)
    out = Image.composite(Image.new("RGB", im.size, (255, 255, 255)), out,
                          shade.point(lambda v: int(v * 0.35)))
    return out, im.split()[3]


def main():
    if len(sys.argv) < 3:
        print("usage: asset_sheet.py <render_dir> <out_dir> [cols] [bg]")
        return
    rd, od = sys.argv[1], sys.argv[2]
    cols = int(sys.argv[3]) if len(sys.argv) > 3 else 4
    bg = float(sys.argv[4]) if len(sys.argv) > 4 else 0.20
    os.makedirs(od, exist_ok=True)

    files = sorted(glob.glob(os.path.join(rd, "*.png")))
    files = [f for f in files
             if not os.path.basename(f).startswith("SHEET")
             and not os.path.basename(f).endswith(("_p.png", "_s.png"))]
    if not files:
        print("no plates in " + rd)
        return

    tiles = []
    for f in files:
        name = os.path.splitext(os.path.basename(f))[0]
        p, alpha = plate(f, bg)
        p.save(os.path.join(od, name + "_p.png"))
        sil = Image.new("RGB", p.size, (255, 255, 255))
        sil.paste(Image.new("RGB", p.size, (12, 12, 14)), (0, 0), alpha)
        sil.save(os.path.join(od, name + "_s.png"))
        tiles.append((name, p, sil))

    # two tiles per asset: plate and silhouette, stacked
    cw = 330
    first = tiles[0][1]
    ch = int(cw * first.size[1] / first.size[0])
    sh = int(cw * tiles[0][2].size[1] / tiles[0][2].size[0])
    cellw, cellh = cw, ch + sh + 20
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cellw + 8, rows * cellh + 8), (26, 27, 31))
    dr = ImageDraw.Draw(sheet)
    for i, (name, p, sil) in enumerate(tiles):
        x = (i % cols) * cellw + 4
        y = (i // cols) * cellh + 4
        sheet.paste(p.resize((cw, ch), Image.LANCZOS), (x, y))
        sheet.paste(sil.resize((cw, sh), Image.LANCZOS), (x, y + ch))
        dr.text((x + 4, y + ch + 2), name, fill=(235, 235, 240))
    out = os.path.join(od, "SHEET.png")
    sheet.save(out)
    print("SHEET %s  %s  plates=%d cols=%d" % (out, sheet.size, len(tiles), cols))


if __name__ == "__main__":
    main()
