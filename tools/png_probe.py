#!/usr/bin/env python3
"""Numeric probe for PNG screenshots.

WHY THIS EXISTS: the review loop has to answer "WHAT LOOKS FAKE?" but the
renders cannot be looked at directly in this session. Everything is therefore
measured: block luminance grids (composition / silhouette), box averages
(are the roads earth-toned or concrete-grey?), and hue histograms.

Usage:
  python tools/png_probe.py grid  FILE [rows] [cols]
  python tools/png_probe.py box   FILE x0 y0 x1 y1
  python tools/png_probe.py boxes FILE "x0,y0,x1,y1:name" ...
  python tools/png_probe.py hist  FILE
  python tools/png_probe.py stat  FILE [FILE...]
"""

import sys
import zlib
import struct
import os


# --------------------------------------------------------------------------
# Minimal PNG reader. No PIL in this environment, and Godot writes plain
# non-interlaced 8-bit RGB/RGBA, which is all we need.
# --------------------------------------------------------------------------
def read_png(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a png: %s" % path
    pos = 8
    w = h = bitdepth = colortype = None
    idat = b""
    while pos < len(data):
        (ln,) = struct.unpack(">I", data[pos:pos + 4])
        ctag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        if ctag == b"IHDR":
            w, h, bitdepth, colortype, comp, filt, inter = struct.unpack(">IIBBBBB", body)
            assert bitdepth == 8, "only 8-bit supported (%d)" % bitdepth
            assert inter == 0, "interlaced png unsupported"
        elif ctag == b"IDAT":
            idat += body
        elif ctag == b"IEND":
            break
        pos += 12 + ln
    nch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colortype]
    raw = zlib.decompress(idat)
    stride = w * nch
    out = bytearray(h * stride)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        ft = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if ft == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 0xFF
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ft == 3:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ft == 4:
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                b = prev[i]
                c = prev[i - nch] if i >= nch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, nch, bytes(out)


def px(img, x, y):
    w, h, nch, buf = img
    x = max(0, min(w - 1, x))
    y = max(0, min(h - 1, y))
    i = (y * w + x) * nch
    if nch >= 3:
        return buf[i], buf[i + 1], buf[i + 2]
    v = buf[i]
    return v, v, v


def box_avg(img, x0, y0, x1, y1):
    r = g = b = n = 0
    for y in range(int(y0), int(y1), max(1, (int(y1) - int(y0)) // 40)):
        for x in range(int(x0), int(x1), max(1, (int(x1) - int(x0)) // 40)):
            pr, pg, pb = px(img, x, y)
            r += pr
            g += pg
            b += pb
            n += 1
    if n == 0:
        return (0, 0, 0)
    return (r // n, g // n, b // n)


def lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


RAMP = " .:-=+*#%@"


def hue_letter(c):
    r, g, b = c
    mx = max(r, g, b)
    mn = min(r, g, b)
    if mx < 12:
        return "K"
    if mx - mn < 10:
        return "g" if mx > 110 else ("n" if mx > 55 else ".")
    if r >= g and r >= b:
        return "R" if b + 18 < g else ("Y" if g > b + 25 else "r")
    if g >= r and g >= b:
        return "G" if b + 18 < r else "C"
    return "B" if r + 18 < g else "M"


def cmd_grid(path, rows=18, cols=32):
    img = read_png(path)
    w, h = img[0], img[1]
    print("%s  %dx%d" % (os.path.basename(path), w, h))
    for j in range(rows):
        y0 = h * j // rows
        y1 = h * (j + 1) // rows
        line_l = ""
        line_h = ""
        for i in range(cols):
            x0 = w * i // cols
            x1 = w * (i + 1) // cols
            c = box_avg(img, x0, y0, x1, y1)
            lv = lum(c)
            line_l += RAMP[min(9, int(lv / 25.6))]
            line_h += hue_letter(c)
        print("  %s   %s" % (line_l, line_h))


def cmd_box(path, x0, y0, x1, y1):
    img = read_png(path)
    c = box_avg(img, x0, y0, x1, y1)
    print("%s [%s,%s]-[%s,%s] = rgb(%d,%d,%d)  lum %.0f  sat %d  hue %s"
          % (os.path.basename(path), x0, y0, x1, y1, c[0], c[1], c[2],
             lum(c), max(c) - min(c), hue_letter(c)))


def cmd_boxes(path, specs):
    img = read_png(path)
    for s in specs:
        name, _, rng = s.partition(":")
        x0, y0, x1, y1 = [int(v) for v in rng.split(",")]
        c = box_avg(img, x0, y0, x1, y1)
        print("  %-18s rgb(%3d,%3d,%3d)  lum %5.1f  sat %3d  %s"
              % (name, c[0], c[1], c[2], lum(c), max(c) - min(c), hue_letter(c)))


def cmd_maskstat(base_path, tint_path, thresh=25.0, rows=90, cols=160):
    """Mean colour of BASE on exactly the pixels TINT changed.

    WHY: "--tint=Land/Roads#ff0000" says WHERE a layer is on screen but destroys
    its colour, so the tint render alone cannot answer "what colour is the road
    actually rendering as". Sampling a hand-picked box answers it only if you
    already know where the road is, which is the thing being asked. This takes
    the coverage from the tinted frame and the colour from the untinted one.
    """
    a = read_png(base_path)
    b = read_png(tint_path)
    w, h = a[0], a[1]
    n = 0
    rs = gs = bs = 0
    lmin = 999.0
    lmax = -1.0
    for j in range(rows):
        y = h * j // rows + h // (2 * rows)
        for i in range(cols):
            x = w * i // cols + w // (2 * cols)
            ca = px(a, x, y)
            cb = px(b, x, y)
            ra = ca[0] - (ca[1] + ca[2]) * 0.5
            rb = cb[0] - (cb[1] + cb[2]) * 0.5
            if rb - ra <= thresh:
                continue
            rs += ca[0]
            gs += ca[1]
            bs += ca[2]
            lv = lum(ca)
            lmin = min(lmin, lv)
            lmax = max(lmax, lv)
            n += 1
    if n == 0:
        print("  no pixels matched (threshold %.0f)" % thresh)
        return
    c = (rs // n, gs // n, bs // n)
    print("  %-22s coverage %5.2f%%  mean rgb(%3d,%3d,%3d)  lum %5.1f  sat %3d"
          "  L range %.0f..%.0f"
          % (os.path.basename(base_path), 100.0 * n / (rows * cols),
             c[0], c[1], c[2], lum(c), max(c) - min(c), lmin, lmax))


def cmd_hist(path):
    img = read_png(path)
    w, h = img[0], img[1]
    buckets = {}
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            c = px(img, x, y)
            k = hue_letter(c)
            buckets[k] = buckets.get(k, 0) + 1
    tot = sum(buckets.values())
    print(os.path.basename(path))
    for k, v in sorted(buckets.items(), key=lambda kv: -kv[1]):
        print("  %s  %5.2f%%" % (k, 100.0 * v / tot))


def cmd_stat(paths):
    for p in paths:
        img = read_png(p)
        w, h = img[0], img[1]
        whole = box_avg(img, 0, 0, w, h)
        # upper third = sky, lower third = ground, middle = midground
        up = box_avg(img, 0, 0, w, h // 3)
        mid = box_avg(img, 0, h // 3, w, 2 * h // 3)
        lo = box_avg(img, 0, 2 * h // 3, w, h)
        print("%-24s all(%3d,%3d,%3d) L%3.0f | sky(%3d,%3d,%3d) L%3.0f | "
              "mid(%3d,%3d,%3d) L%3.0f | gnd(%3d,%3d,%3d) L%3.0f"
              % (os.path.basename(p), whole[0], whole[1], whole[2], lum(whole),
                 up[0], up[1], up[2], lum(up),
                 mid[0], mid[1], mid[2], lum(mid),
                 lo[0], lo[1], lo[2], lum(lo)))


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        sys.exit(1)
    cmd = a[0]
    if cmd == "grid":
        cmd_grid(a[1], int(a[2]) if len(a) > 2 else 18, int(a[3]) if len(a) > 3 else 32)
    elif cmd == "box":
        cmd_box(a[1], *[int(v) for v in a[2:6]])
    elif cmd == "boxes":
        cmd_boxes(a[1], a[2:])
    elif cmd == "maskstat":
        cmd_maskstat(a[1], a[2], float(a[3]) if len(a) > 3 else 25.0)
    elif cmd == "hist":
        cmd_hist(a[1])
    elif cmd == "stat":
        cmd_stat(a[1:])
    else:
        print(__doc__)
