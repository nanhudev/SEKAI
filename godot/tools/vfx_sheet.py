"""Contact sheet for VFX LAB review stills.

Not a deliverable — an instrument. The acceptance test for this round is a single
still, so the review has to be able to put six stills of one clip side by side and
read them as one strip. Written as a tool rather than a one-off shell line because
it gets run once per prototype and once again per pass.

    python tools/vfx_sheet.py <out.png> <cols> <in1.png> <in2.png> ...

Optional env `VFX_TILE_W`: downscale every tile to this width before pasting. A
four-column sheet of 1280x720 stills is 5144 px wide, which is more than anything
will display at once, so the review sheets are built at 640 px per tile and the
full-size PNGs are what gets looked at when a tile looks wrong.
"""
import os
import sys
from PIL import Image, ImageDraw

def main() -> int:
    out = sys.argv[1]
    cols = int(sys.argv[2])
    paths = sys.argv[3:]
    if not paths:
        print("no inputs")
        return 1
    tile_w = int(os.environ.get("VFX_TILE_W", "0"))
    tiles = [Image.open(p).convert("RGB") for p in paths]
    if tile_w > 0:
        scaled = []
        for im in tiles:
            h = max(1, int(round(im.size[1] * tile_w / im.size[0])))
            scaled.append(im.resize((tile_w, h), Image.LANCZOS))
        tiles = scaled
    w, h = tiles[0].size
    rows = (len(tiles) + cols - 1) // cols
    pad = 6
    label = 26
    sheet = Image.new(
        "RGB",
        (cols * w + (cols + 1) * pad, rows * (h + label) + (rows + 1) * pad),
        (18, 18, 20),
    )
    d = ImageDraw.Draw(sheet)
    for i, im in enumerate(tiles):
        cx = i % cols
        cy = i // cols
        x = pad + cx * (w + pad)
        y = pad + cy * (h + label + pad)
        d.text((x + 4, y + 6), paths[i].split("/")[-1].replace(".png", ""),
               fill=(230, 230, 235))
        sheet.paste(im, (x, y + label))
    sheet.save(out)
    print("wrote %s  %dx%d  %d tiles" % (out, sheet.size[0], sheet.size[1], len(tiles)))
    return 0

sys.exit(main())
