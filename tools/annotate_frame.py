"""Draw the measured cut line and probe-reported screen geometry onto a frame,
so an eye and a number can be pointed at the same pixels.

Guessing which blob in a 1280x720 frame is the enemy has already cost one
wrong conclusion; this puts the line where it actually is.

Usage:
  python annotate_frame.py <in.png> <out.png> [zoom=1] [rect=x0,y0,x1,y1]
                           [vline=x,x,x] [hline=y,y,y] [nolabel]
Guides:
  green  = the cut line (fitted from the frame's own dark seam)
  red    = vertical guide      cyan = horizontal guide
  yellow = rectangle           magenta mark at the rectangle centre
"""
import sys
import math
import numpy as np
from PIL import Image, ImageDraw

src, out = sys.argv[1], sys.argv[2]
opts = {}
for a in sys.argv[3:]:
    if "=" in a:
        k, v = a.split("=", 1)
        opts[k] = v
    else:
        opts[a] = "1"
zoom = int(opts.get("zoom", 1))

im = Image.open(src).convert("RGB")
A = np.asarray(im, dtype=np.float32)
H, W, _ = A.shape
lum = 0.2126 * A[:, :, 0] + 0.7152 * A[:, :, 1] + 0.0722 * A[:, :, 2]

# --- fit the cut line from the frame's own dark seam ----------------------
cx, cy = W * 0.5, H * 0.5
slope = math.tan(math.radians(-30.0))
anchors = []
for x in range(120, W - 120, 8):
    g = int(cy + (x - cx) * slope) - 30
    col = lum[max(1, g):max(1, g) + 61, x]
    if col.size == 0:
        continue
    i = int(np.argmin(col))
    if col[i] < 60.0:
        anchors.append((x, max(1, g) + i))
fit_note = "authored"
if len(anchors) >= 8:
    ax = np.array([p[0] for p in anchors], dtype=np.float64)
    ay = np.array([p[1] for p in anchors], dtype=np.float64)
    coef = np.polyfit(ax, ay, 1)
    m, c = float(coef[0]), float(coef[1])
    if abs(m - slope) < 0.8:
        slope, cy = m, c + m * cx
        fit_note = "fitted %d anchors, %.2f deg" % (len(anchors),
                                                    math.degrees(math.atan(m)))
print("line: centre=(%.0f,%.0f) slope=%.4f  [%s]" % (cx, cy, slope, fit_note))
print("      y(x=0)=%.0f  y(x=1280)=%.0f" % (cy - cx * slope,
                                              cy + (W - cx) * slope))

d = ImageDraw.Draw(im)


def put(x, y, s, fill):
    d.text((x + 3, y + 2), s, fill=(0, 0, 0))
    d.text((x + 2, y + 1), s, fill=fill)


line_y = cy + (np.arange(W) - cx) * slope
for x in range(W):
    y = int(round(line_y[x]))
    if 0 <= y < H:
        for dy in (-1, 0, 1):
            if 0 <= y + dy < H:
                d.point((x, y + dy), fill=(0, 255, 110))
for x in (0, W // 2, W - 1):
    y = int(round(line_y[x]))
    if 0 <= y < H:
        put(x if x < W // 2 else x - 150, y, "y=%d" % y, (0, 255, 110))

for s in opts.get("vline", "").split(","):
    if s.strip():
        x = int(float(s))
        d.line([(x, 0), (x, H - 1)], fill=(255, 60, 60), width=1)
        put(x, 6, "x=%d" % x, (255, 60, 60))
for s in opts.get("hline", "").split(","):
    if s.strip():
        y = int(float(s))
        d.line([(0, y), (W - 1, y)], fill=(80, 220, 255), width=1)
        put(6, y, "y=%d" % y, (80, 220, 255))
r = opts.get("rect", "")
if r:
    x0, y0, x1, y1 = [int(float(v)) for v in r.split(",")]
    d.rectangle([x0, y0, x1, y1], outline=(255, 235, 40), width=2)
    d.line([(x0, y0), (x1, y1)], fill=(255, 235, 40))
    d.line([(x0, y1), (x1, y0)], fill=(255, 235, 40))
    put(x0, y0 - 14, "rect", (255, 235, 40))
    print("rect %d,%d..%d,%d  centre=(%d,%d)  line y at centre x = %.0f"
          % (x0, y0, x1, y1, (x0 + x1) // 2, (y0 + y1) // 2,
             cy + ((x0 + x1) / 2 - cx) * slope))

if zoom != 1:
    im = im.resize((W * zoom, H * zoom), Image.NEAREST)
im.save(out)
print("wrote", out, im.size)
