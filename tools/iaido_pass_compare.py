"""PASS 3 vs PASS 4 key-frame sheet for the Iaido ceremony.

Pairs frames from two ceremony renders at the same ceremony TIMES and stacks
them PASS 3 over PASS 4, so a lock pass can be judged against the build the
reviewer actually looked at instead of against a fresh set of stills with no
reference.

Why a script and not a one-off: FINAL LOCK PART T asks for the before/after
keyframes every pass, and the index arithmetic (`idx = PRE_ROLL + (t - start)
* FPS`) is the kind of thing that gets retyped wrong once and then quietly
compares two different moments. This is `tools/before_after.py` for the Iaido
renderer rather than for the Mistvale walk loop — same idea, and the two name
their frames differently on purpose.

Usage:
  python iaido_pass_compare.py <out.png> <before_dir> <after_dir> <start_time>
                               <t1,t2,...> [before_label] [after_label]

`start_time` must be the `start_time` argument the two renders were made with
(both must match, or the pair is meaningless). Times are ceremony seconds.
"""
import os
import sys
from PIL import Image, ImageDraw

OUT = sys.argv[1]
BEFORE = sys.argv[2]
AFTER = sys.argv[3]
START = float(sys.argv[4])
TS = [float(x) for x in sys.argv[5].split(",")]
LABEL_B = sys.argv[6] if len(sys.argv) > 6 else "PASS 3"
LABEL_A = sys.argv[7] if len(sys.argv) > 7 else "PASS 4"

FPS = 30.0
PRE_ROLL = 12           # must match PRE_ROLL in iaido_movie_renderer.gd
W = 620                 # width of each pane
CAP = 20                # caption strip height

# What each moment IS, so the sheet is readable without the pass notes open.
NOTES = {
    5.70: "hero hold  (world split, nothing else moving)",
    8.30: "pre-click  (broken but still holding)",
    8.60: "post-click (collapse + release)",
}


def frame(t: float, root: str) -> str:
    idx = int(round(PRE_ROLL + (t - START) * FPS))
    return os.path.join(root, "frame_%04d.png" % idx)


def load(path: str) -> Image.Image:
    im = Image.open(path).convert("RGB")
    h = int(im.height * W / im.width)
    return im.resize((W, h), Image.LANCZOS)


cells = []
for t in TS:
    b, a = frame(t, BEFORE), frame(t, AFTER)
    if not os.path.exists(b) or not os.path.exists(a):
        print("skip t=%g (missing %s)" % (t, b if not os.path.exists(b) else a))
        continue
    cells.append((t, load(b), load(a)))

if not cells:
    raise SystemExit("nothing to compare")

pane_h = cells[0][1].height
sheet_w = W * len(cells)
sheet_h = CAP + 2 * (CAP + pane_h)
sheet = Image.new("RGB", (sheet_w, sheet_h), (14, 14, 16))
dr = ImageDraw.Draw(sheet)

for i, (t, _b, _a) in enumerate(cells):
    x = i * W
    note = NOTES.get(t, "")
    dr.text((x + 6, 4), "t=%.2fs  %s" % (t, note), fill=(210, 210, 220))

y = CAP
dr.text((6, y + 4), LABEL_B, fill=(230, 130, 130))
y += CAP
for i, (_t, b, _a) in enumerate(cells):
    sheet.paste(b, (i * W, y))
y += pane_h

dr.text((6, y + 4), LABEL_A, fill=(130, 230, 150))
y += CAP
for i, (_t, _b, a) in enumerate(cells):
    sheet.paste(a, (i * W, y))
y += pane_h

sheet.save(OUT)
print(OUT, sheet.size)
