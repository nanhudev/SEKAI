"""SEKAI Sword VFX - image helpers shared by the render scripts.

WHY THIS IS A MODULE AND NOT COPIED

    Both P21 (the review renderer) and P23 (the world-render probe) need to
    answer the same question about a PNG: does it contain an image, or is it a
    flat block of a render target's clear colour? The first version of that
    check lived inline in P21. A second copy in P23 would be the version that
    drifts, and this project's worst failures have all been cases of two
    measurements of the same thing disagreeing while nobody noticed.

    So it lives here, once, with its verification recorded.

THE UNFILTERING IS NOT OPTIONAL, AND THIS IS THE MEASURED REASON

    PNG scanlines are stored with a per-row filter - None, Sub, Up, Average or
    Paeth - so the decompressed IDAT stream holds DELTAS, not pixel values. A
    first version sampled that stream directly and reported mean luma 2.44 for
    a frame that PIL measures at 0.10. The number looked plausible and was
    meaningless, which is the worst property a check can have: it would have
    passed black frames as good ones.

    Verified against PIL on five known-black frames from the first render pass:
    both report mean 0.10. Run `tools/verify_png_probe.py` to re-do that
    comparison after any change here.

    png_stats() is the form new code should use: per-channel means, the dominant
    RGB triple, and the alpha range. png_probe() is a thin 4-tuple wrapper kept
    so P21 and P23 did not have to change in the same step.
"""
import os
import struct
import zlib


def png_stats(path):
    """Full statistics for an 8-bit PNG. Returns a dict, or None.

    Keys: width, height, mean_luma, mean_rgb, top_rgb, top_rgb_frac,
    alpha_min, alpha_max, distinct_rgb, distinct_bytes, sampled.

    WHY THIS REPLACED A LUMA-ONLY PROBE

        Mean luma cannot tell a render target that was never rendered into from
        a render target showing a black scene: both sit near 0. MEASURED on the
        archived first render pass - mean luma 0.1019, and the frame is
        create_render_target2d's clear colour dithered by the exporter:

            alpha   min=255 max=255          (so something DID write it)
            RGB     (0,0,0) 89.81%, (1,1,1) 10.19%, 2 distinct colours
            all five cameras byte-identical

        Per-channel means plus the dominant RGB triple turn that into a
        readable answer, and they are what make the "clear the target to bright
        green, then look" test a bit rather than a judgement call.

    Sampling is sparse (every third row, every third pixel) which is plenty for
    a dominant colour and keeps this at ~1 s per 1080p frame. `distinct_rgb` is
    therefore a LOWER BOUND on the true count - it is a shape indicator, not a
    census, and it is only ever used to separate "flat" from "has an image".
    """
    try:
        with open(path, "rb") as fh:
            blob = fh.read()
    except Exception:
        return None
    if blob[:8] != b"\x89PNG\r\n\x1a\n":
        return None

    pos, idat, w, h, bitd, ctype = 8, [], 0, 0, 8, 6
    while pos + 8 <= len(blob):
        ln = struct.unpack(">I", blob[pos:pos + 4])[0]
        typ = blob[pos + 4:pos + 8]
        data = blob[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            w, h, bitd, ctype = struct.unpack(">IIBB", data[:10])
        elif typ == b"IDAT":
            idat.append(data)
        elif typ == b"IEND":
            break
        pos += 12 + ln

    blank = {"width": w, "height": h, "mean_luma": None, "mean_rgb": None,
             "top_rgb": None, "top_rgb_frac": None, "alpha_min": None,
             "alpha_max": None, "distinct_rgb": None, "distinct_bytes": None,
             "sampled": 0}

    try:
        raw = zlib.decompress(b"".join(idat))
    except Exception:
        return blank
    if bitd != 8:
        return blank

    step = {0: 1, 2: 3, 4: 2, 6: 4}.get(ctype)
    if step is None or w <= 0 or h <= 0:
        return blank
    stride = w * step
    if len(raw) < h * (stride + 1):
        return blank

    counts = {}
    sr = sg = sb = 0
    n = 0
    a_min, a_max = 255, 0
    seen_bytes = set()

    prev = bytearray(stride)
    for y in range(h):
        base = y * (stride + 1)
        ftype = raw[base]
        line = bytearray(raw[base + 1:base + 1 + stride])
        if ftype == 1:                      # Sub
            for i in range(step, stride):
                line[i] = (line[i] + line[i - step]) & 0xFF
        elif ftype == 2:                    # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:                    # Average
            for i in range(stride):
                a = line[i - step] if i >= step else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:                    # Paeth
            for i in range(stride):
                a = line[i - step] if i >= step else 0
                b = prev[i]
                c = prev[i - step] if i >= step else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        elif ftype != 0:
            return blank
        prev = line
        if y % 3 == 0:                      # every third row is plenty
            for x in range(0, max(1, stride - step + 1), step * 3):
                if step >= 3:
                    r, g, b = line[x], line[x + 1], line[x + 2]
                    a = line[x + 3] if step == 4 else 255
                else:
                    r = g = b = line[x]
                    a = 255
                sr += r
                sg += g
                sb += b
                n += 1
                if a < a_min:
                    a_min = a
                if a > a_max:
                    a_max = a
                key = (r, g, b)
                counts[key] = counts.get(key, 0) + 1

    sampled_bytes = raw[::max(1, len(raw) // 200000)]
    seen_bytes = set(sampled_bytes)

    top, top_n = None, 0
    for k, v in counts.items():
        if v > top_n:
            top, top_n = k, v

    return {
        "width": w, "height": h,
        "mean_luma": ((sr * 299 + sg * 587 + sb * 114) / 1000.0 / n)
        if n else None,
        "mean_rgb": (sr / float(n), sg / float(n), sb / float(n)) if n else None,
        "top_rgb": top,
        "top_rgb_frac": (top_n / float(n)) if n else None,
        "alpha_min": a_min if n else None,
        "alpha_max": a_max if n else None,
        "distinct_rgb": len(counts),
        "distinct_bytes": len(seen_bytes),
        "sampled": n,
    }


def png_probe(path):
    """(width, height, mean_luma, distinct_byte_values) - kept for callers.

    Thin wrapper over png_stats so P21 and P23 keep working; the richer dict is
    the form new code should use.
    """
    st = png_stats(path)
    if st is None:
        return None
    return (st["width"], st["height"], st["mean_luma"], st["distinct_bytes"])


def collect(out_dir, fname):
    """Find what the engine wrote for `fname` and normalise it to `<fname>.png`.

    MEASURED: `RenderingLibrary.export_render_target(W, rt, dir, "review_fp")`
    writes a valid PNG at `dir/review_fp` - with NO extension. Only the name is
    wrong, so a check for `review_fp.png` reports MISSING while a real frame
    sits on disk, and the natural next move is to debug the export API, which
    is working fine.

    HAZARD, and it is not hypothetical: this prefers an EXISTING `<name>.png`
    over whatever was just written. So calling it twice with the SAME name
    returns the first file both times. That is correct for a shot list where
    every shot has a unique name (P21), and wrong for anything that re-exports a
    fixed name in a loop - the second and later reads would silently report the
    first image's contents. P24 gives every measurement its own name for exactly
    this reason. If you need to re-export one name repeatedly, delete the
    normalised file first or use a counter.
    """
    plain = os.path.join(out_dir, fname)
    dotted = plain + ".png"
    if os.path.exists(dotted) and os.path.getsize(dotted) > 0:
        return dotted
    if os.path.exists(plain) and os.path.getsize(plain) > 0:
        try:
            os.replace(plain, dotted)
            return dotted
        except Exception:
            return plain
    return None


def describe(path):
    """One readable line about a frame: size, colour, luma, distinct values.

    Includes the dominant RGB triple because that is what separates "a flat
    clear colour" from "an image" at a glance, and because the failure it exists
    to catch - every camera exporting the same cleared buffer under a different
    filename - is invisible in a luma number alone.
    """
    st = png_stats(path)
    if st is None:
        return "not an 8-bit PNG this can read"
    if st["mean_luma"] is None:
        return "%dx%d  (shape only - could not decode pixels)" % (
            st["width"], st["height"])
    top = st["top_rgb"]
    return ("%dx%d  mean_luma=%-7s dominant=%-15s %5.1f%%  distinct_rgb=%s"
            % (st["width"], st["height"], "%.2f" % st["mean_luma"],
               str(top), 100.0 * (st["top_rgb_frac"] or 0.0),
               st["distinct_rgb"]))


def is_flat_colour(path, colour, tol=10, min_frac=0.75):
    """True if at least `min_frac` of sampled pixels are within `tol` of colour.

    This is the reader for the green-clear test: clear a render target to
    (0,255,0), wait, and ask whether it is still that colour. Green means
    nothing rendered into it. Anything else means something did.

    CAVEAT ON THE SAMPLING. png_stats samples every third row and every third
    pixel, so a noise pattern periodic on a stride commensurate with 6 can alias
    and under-report the dominant colour's share. MEASURED while testing this:
    a synthetic dither on `(x + y) % 9` read as 66.5% dominant instead of 88.9%.
    Real exporter dither is not periodic, so this has not bitten on real frames -
    but a future synthetic test must use a non-aliasing pattern.
    """
    st = png_stats(path)
    if st is None or st["top_rgb"] is None:
        return False, "could not read"
    r, g, b = st["top_rgb"]
    cr, cg, cb = colour
    close = (abs(r - cr) <= tol and abs(g - cg) <= tol and abs(b - cb) <= tol)
    frac = st["top_rgb_frac"] or 0.0
    return (close and frac >= min_frac), ("dominant %s at %.1f%%"
                                          % (st["top_rgb"], 100.0 * frac))
