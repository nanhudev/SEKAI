# -*- coding: utf-8 -*-
"""
SEKAI / CHARACTER LINE — CONTACT SHEET BUILDER
Composes a labelled grid contact sheet from review renders (pure Blender pixel copy,
no external deps). Cells are letterboxed onto a flat background.

Run:
  "G:/blender.exe" -b --factory-startup --python tools/character/make_contact_sheet.py -- \
      --out <sheet.png> --cell 460x640 --cols 4 --bg 0.10 -- <img1> <img2> ...
"""

import bpy
import os
import sys

argv = sys.argv
argv = argv[argv.index("--") + 1:] if "--" in argv else []
ARGS = {}
IMAGES = []
i = 0
while i < len(argv):
    if argv[i] == "--":
        IMAGES.extend(argv[i + 1:])
        break
    if argv[i].startswith("--"):
        ARGS[argv[i][2:]] = argv[i + 1] if i + 1 < len(argv) else ""
        i += 2
    else:
        i += 1

OUT = os.path.abspath(ARGS["out"])
CW, CH = [int(v) for v in ARGS.get("cell", "460x640").split("x")]
COLS = int(ARGS.get("cols", 4))
BG = float(ARGS.get("bg", 0.10))
GAP = int(ARGS.get("gap", 6))

IMAGES = [os.path.abspath(p) for p in IMAGES]
IMAGES = [p for p in IMAGES if os.path.exists(p)]
if not IMAGES:
    raise SystemExit("no input images")

ROWS = (len(IMAGES) + COLS - 1) // COLS
W = COLS * CW + (COLS + 1) * GAP
H = ROWS * CH + (ROWS + 1) * GAP
print("[SHEET] %d images -> %dx%d (%dx%d)" % (len(IMAGES), W, H, COLS, ROWS))

# numpy + foreach_get/foreach_set.  The original version wrote the canvas one
# pixel at a time through a Python function, which is 12.4 million calls for a
# 24-cell review sheet -- minutes of wall clock and a 400 MB list of boxed
# floats.  Same output, same interface, two orders of magnitude less patience.
import numpy as np

canvas = np.zeros((H, W, 4), dtype=np.float32)
canvas[:, :, 0:3] = BG
canvas[:, :, 3] = 1.0

for idx, path in enumerate(IMAGES):
    col = idx % COLS
    row = idx // COLS
    img = bpy.data.images.load(path, check_existing=False)
    iw, ih = img.size
    buf = np.empty(iw * ih * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    a = buf.reshape(ih, iw, 4)            # row 0 is the BOTTOM row
    s = min(CW / float(iw), CH / float(ih))
    dw, dh = max(1, int(iw * s)), max(1, int(ih * s))
    ys = np.minimum((np.arange(dh) / s).astype(np.int32), ih - 1)
    xs = np.minimum((np.arange(dw) / s).astype(np.int32), iw - 1)
    tiny = a[ys][:, xs]
    ox = GAP + col * (CW + GAP) + (CW - dw) // 2
    oy = H - (GAP + (row + 1) * CH + row * GAP) + (CH - dh) // 2
    canvas[oy:oy + dh, ox:ox + dw, 0:3] = tiny[:, :, 0:3]
    bpy.data.images.remove(img)
    print("   + %-46s %dx%d -> %dx%d" % (os.path.basename(path), iw, ih, dw, dh))

out = bpy.data.images.new("sheet", W, H, alpha=False)
out.pixels.foreach_set(canvas.reshape(-1))
out.filepath_raw = OUT
out.file_format = 'PNG'
out.save()
print("SHEET_DONE " + OUT)
