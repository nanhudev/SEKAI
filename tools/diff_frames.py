"""Difference two rendered frames and report where they actually disagree.

Used for controlled A/B renders: with every other uniform held identical, the
only thing that can differ is the variable under test. Prints the global change
plus per-region peaks, and writes an amplified difference image.

Usage: python diff_frames.py a.png b.png [out_diff.png] [block]
"""
import sys
from PIL import Image, ImageChops

a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
out = sys.argv[3] if len(sys.argv) > 3 else "diff.png"
block = int(sys.argv[4]) if len(sys.argv) > 4 else 20

if a.size != b.size:
    raise SystemExit("size mismatch: %s vs %s" % (a.size, b.size))

d = ImageChops.difference(a, b)
px = d.load()
w, h = d.size
total = 0
changed = 0
for y in range(h):
    for x in range(w):
        v = max(px[x, y])
        total += v
        if v > 8:
            changed += 1
print("size %dx%d  mean |diff| = %.2f  pixels >8 = %d (%.2f%%)"
      % (w, h, total / (w * h), changed, 100.0 * changed / (w * h)))

# Where is it changing? Coarse block map, top offenders first.
grid = []
for by in range(0, h, block):
    for bx in range(0, w, block):
        s = 0
        n = 0
        for y in range(by, min(by + block, h), 2):
            for x in range(bx, min(bx + block, w), 2):
                s += max(px[x, y])
                n += 1
        grid.append((s / max(n, 1), bx, by))
grid.sort(reverse=True)
print("top 12 blocks (x, y, mean|diff|):")
for v, bx, by in grid[:12]:
    print("   x=%4d y=%4d  %6.2f" % (bx, by, v))

# Amplified difference so faint geometry changes are visible to the eye.
amp = d.point(lambda v: min(255, v * 8))
amp.save(out)
print("wrote", out)
