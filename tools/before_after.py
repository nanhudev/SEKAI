"""Before/after sheet for the Mistvale level-art passes.

Pairs frames from two walk renders by their metre mark along ROAD_SPINE and
stacks them BEFORE over AFTER, so a round can be judged as a pair rather than
as a fresh set of stills with no reference.

Why a script and not a one-off: §26 of the addendum asks for BUILD / RUN / WALK
/ CAPTURE / COMPARE every round. The COMPARE half is the same operation every
time and was being retyped.

Usage:
  python before_after.py <before_dir> <before_first_d> <before_step>
                         <after_dir> <after_first_d> <after_step>
                         <out.png> [d1,d2,...] [before_label] [after_label]

`before_first_d` / `after_first_d` are the metre marks of frame w000 in each
directory; frames are indexed as w<NNN>_d<DDDD>.png with a constant step.

The two labels are optional; without them they are built from the directory
names. They used to be hardcoded to "p19 / pass 03", which quietly lied on
every subsequent round.
"""
import os
import sys
from PIL import Image, ImageDraw

BEFORE = sys.argv[1]
BEFORE_D0 = float(sys.argv[2])
BEFORE_STEP = float(sys.argv[3])
AFTER = sys.argv[4]
AFTER_D0 = float(sys.argv[5])
AFTER_STEP = float(sys.argv[6])
OUT = sys.argv[7]
DS = [float(x) for x in sys.argv[8].split(",")]
LABEL_B = sys.argv[9] if len(sys.argv) > 9 else "BEFORE  %s" % os.path.basename(BEFORE.rstrip("/\\"))
LABEL_A = sys.argv[10] if len(sys.argv) > 10 else "AFTER   %s" % os.path.basename(AFTER.rstrip("/\\"))

W = 620          # width of each pane
CAP = 20         # caption strip height


def frame(d: float, root: str, d0: float, step: float) -> str:
    idx = int(round((d - d0) / step))
    return os.path.join(root, "w%03d_d%04d.png" % (idx, int(round(d))))


def load(path: str, w: int) -> Image.Image:
    im = Image.open(path).convert("RGB")
    h = int(im.height * w / im.width)
    return im.resize((w, h), Image.LANCZOS)


rows = []
for d in DS:
    b, a = frame(d, BEFORE, BEFORE_D0, BEFORE_STEP), frame(d, AFTER, AFTER_D0, AFTER_STEP)
    if not os.path.exists(b) or not os.path.exists(a):
        print("skip d=%g (missing %s)" % (d, b if not os.path.exists(b) else a))
        continue
    rows.append((d, load(b, W), load(a, W)))

if not rows:
    raise SystemExit("nothing to compare")

pane_h = rows[0][1].height
H = len(rows) * (pane_h * 2 + CAP * 3)
sheet = Image.new("RGB", (W, H), (14, 14, 16))
dr = ImageDraw.Draw(sheet)
y = 0
for d, b, a in rows:
    dr.text((6, y + 4), "%s  d=%d m" % (LABEL_B, d), fill=(230, 130, 130))
    y += CAP
    sheet.paste(b, (0, y)); y += pane_h
    dr.text((6, y + 4), "%s  d=%d m" % (LABEL_A, d), fill=(130, 230, 150))
    y += CAP
    sheet.paste(a, (0, y)); y += pane_h
    y += CAP

sheet.save(OUT)
print(OUT, sheet.size)
