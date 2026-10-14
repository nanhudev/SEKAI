"""Measure how much of the cut's A/B displacement is actually VISIBLE.

A displacement is only visible where there is contrast. Rendering the same
moment twice -- once with `separation_px = 0` and once with the real value --
and differencing the two frames gives, pixel for pixel, the amount by which the
picture changed. That difference IS the visible displacement:

    |diff|  ~=  |step in px|  x  |local gradient|  x  |displacement|

So the diff image answers the only question that matters for the hero hold:

    "is there anything along the line for the eye to see move?"

Usage:
  python line_legibility.py <sep0.png> <sepN.png> [angle_deg=-30] [out_prefix]
Writes <out_prefix>_diff.png (amplified diff, line drawn) and prints a
per-column profile of the displaced contrast.
"""
import sys
import math
import numpy as np
from PIL import Image, ImageDraw

a_path, b_path = sys.argv[1], sys.argv[2]
angle = float(sys.argv[3]) if len(sys.argv) > 3 else -30.0
prefix = sys.argv[4] if len(sys.argv) > 4 else "legib"

A = np.asarray(Image.open(a_path).convert("RGB"), dtype=np.int16)
B = np.asarray(Image.open(b_path).convert("RGB"), dtype=np.int16)
if A.shape != B.shape:
    sys.exit("size mismatch: %s vs %s" % (A.shape, B.shape))
H, W, _ = A.shape
cx, cy = W * 0.5, H * 0.5
print("frame %dx%d" % (W, H))

diff = np.abs(A - B).max(axis=2).astype(np.float32)
lum = (0.2126 * A[:, :, 0] + 0.7152 * A[:, :, 1] + 0.0722 * A[:, :, 2])

# --- locate the line: darkest pixel in a +-30px band, then fit ------------
slope = math.tan(math.radians(angle))
xs = np.arange(120, W - 120, 8)
anchors = []
lo_guess = np.clip((cy + (xs - cx) * slope).astype(int) - 30, 1, H - 2)
for x, g in zip(xs, lo_guess):
    col = lum[g:g + 61, x]
    i = int(np.argmin(col))
    if col[i] < 60.0:
        anchors.append((x, g + i))
if len(anchors) >= 8:
    ax = np.array([p[0] for p in anchors], dtype=np.float64)
    ay = np.array([p[1] for p in anchors], dtype=np.float64)
    coef = np.polyfit(ax, ay, 1)
    m, c = float(coef[0]), float(coef[1])
    if abs(m - slope) < 0.8:
        slope, cy = m, c + m * cx
        print("fitted line: y = %.4fx + %.1f  (%.2f deg, %d anchors)"
              % (m, c, math.degrees(math.atan(m)), len(anchors)))
print("using: centre=(%.0f,%.0f) slope=%.4f (%.2f deg)"
      % (cx, cy, slope, math.degrees(math.atan(slope))))

# --- per-column visible displacement -------------------------------------
BAND = 46
cols = np.arange(0, W, 8)
peak_near = np.zeros(len(cols), dtype=np.float32)
peak_any = diff.max(axis=0)[cols]
y_near = np.zeros(len(cols), dtype=int)
ys = np.arange(H)
for i, x in enumerate(cols):
    y_on = cy + (x - cx) * slope
    m = np.abs(ys - y_on) <= BAND
    band = diff[:, x] * m
    j = int(np.argmax(band))
    peak_near[i] = band[j]
    y_near[i] = j

print("\n=== VISIBLE DISPLACEMENT ALONG THE LINE "
      "(peak |diff| within +-%dpx of the seam) ===" % BAND)
buckets = 10
bw = W // buckets
print("  %-14s %7s %8s  %s" % ("screen column", "peak", "mean", "read"))
for b in range(buckets):
    lo, hi = b * bw, (b + 1) * bw
    sel = peak_near[(cols >= lo) & (cols < hi)]
    if sel.size == 0:
        continue
    pk, mn = float(sel.max()), float(sel.mean())
    if pk >= 90:
        note = "STRONG  - the eye sees a step here"
    elif pk >= 45:
        note = "visible"
    elif pk >= 18:
        note = "faint   - barely"
    else:
        note = "dead    - nothing to displace"
    print("  x %4d-%4d  %7.0f %8.1f  %s" % (lo, hi, pk, mn, note))

print("\n  peak on seam              : %.0f" % float(peak_near.max()))
print("  peak anywhere in a column : %.0f" % float(peak_any.max()))
strong = int((peak_near >= 45).sum())
print("  columns with a visible step: %d / %d  (%.0f%%)"
      % (strong, len(cols), 100.0 * strong / len(cols)))

run = best_run = 0
best_at = 0
for i in range(len(cols)):
    if peak_near[i] < 18:
        run += 1
        if run > best_run:
            best_run, best_at = run, i - run + 1
    else:
        run = 0
if best_run:
    print("  longest dead stretch      : %.0f px, starting at x=%d"
          % (best_run * 8.0, cols[best_at]))
print("  displaced contrast (sum)  : %.0f" % float(peak_near.sum() * 8.0))

order = np.argsort(-peak_near)[:14]
print("\n=== THE SPOTS THAT READ (strongest 14 columns) ===")
for i in order:
    print("  x=%4d  y=%4d  peak=%3.0f" % (cols[i], y_near[i], peak_near[i]))

# --- picture -------------------------------------------------------------
SCALE = 4
v = np.clip(diff * SCALE, 0, 255).astype(np.uint8)
rgb = np.stack([v, (v // 3).astype(np.uint8),
                np.clip(120 - v, 0, 255).astype(np.uint8)], axis=2)
out = Image.fromarray(rgb, "RGB")
d = ImageDraw.Draw(out)
line_y = cy + (np.arange(W) - cx) * slope
for x in range(W):
    y = int(line_y[x])
    if 0 <= y < H:
        d.point((x, y), fill=(0, 255, 120))
        if y + 1 < H:
            d.point((x, y + 1), fill=(0, 255, 120))
p = "%s_diff.png" % prefix
out.save(p)
print("\nwrote %s  (diff x%d, seam drawn in green)" % (p, SCALE))
