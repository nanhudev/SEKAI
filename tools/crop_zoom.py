"""Crop + upscale a region of a rendered frame so small details of the wound
can actually be judged instead of guessed at from a full-frame thumbnail.

Usage:
  python crop_zoom.py <png> <x> <y> <w> <h> [scale] [out.png]
"""
import sys
from PIL import Image

src, x, y, w, h = sys.argv[1], *[int(v) for v in sys.argv[2:6]]
scale = int(sys.argv[6]) if len(sys.argv) > 6 else 3
out = sys.argv[7] if len(sys.argv) > 7 else "zoom.png"

im = Image.open(src).convert("RGB")
print("source size:", im.size)
crop = im.crop((x, y, x + w, y + h))
crop = crop.resize((crop.width * scale, crop.height * scale), Image.NEAREST)
crop.save(out)
print("wrote", out, crop.size)

# Sample a horizontal scanline across the crop's middle so the wound's actual
# pixel values can be read, not eyeballed.
mid = h // 2
row = [im.getpixel((x + i, y + mid)) for i in range(w)]
print("scanline y=%d:" % (y + mid))
print("  " + " ".join("%02x%02x%02x" % p for p in row[::max(1, w // 40)]))
