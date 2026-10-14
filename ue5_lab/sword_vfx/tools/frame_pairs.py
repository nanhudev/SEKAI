"""
frame_pairs.py - compare _before / _after capture pairs, and say what they mean.

WHY A TOOL AND NOT AN EYEBALL
    `p33` shoots every Niagara system twice from the same camera: as-loaded, and
    immediately after `activate(reset=True)`. The PAIR is the measurement. One
    frame cannot distinguish "this system produced nothing" from "this system
    produced nothing YET" or from "the camera is pointing somewhere else" - all
    three look like a picture of the level.

    Comparing two frames by eye in a contact sheet is exactly the judgement that
    gets made wrongly at 2 a.m., because the interesting difference can be a few
    hundred pixels of a thin ribbon against grass. So the arithmetic is done
    here, and the three numbers that matter are printed:

        differing pixels   how much of the frame the effect occupies
        bounding box       WHERE it landed, which is checkable against the
                           emitter's authored position
        max channel delta  how strong it is; a delta of 2 on a few hundred
                           pixels is dithering, a delta of 200 is a stroke

    Two renders of the same scene are not bit-identical (TAA jitter, Lumen
    noise), so "identical" means "within <tol> on every channel for at least
    <quiet_frac> of the frame", not "byte-equal".

Usage:
    tools/frame_pairs.py <dir> [--tol 3] [--write]

    Scans <dir> for *_before.<ext> / *_after.<ext> pairs. Pure file reading, so
    it runs on the host - no engine, no Python-in-UE.

Exit code = number of pairs that showed NO difference (the things that need
explaining). A clean run over a healthy gallery is not 0: the mist emitters are
expected to be quiet in the Normal profile.
"""

import os
import sys

from PIL import Image, ImageChops


def load(path):
    return Image.open(path).convert("RGB")


def diff_pair(a_path, b_path, tol):
    a = load(a_path)
    b = load(b_path)
    if a.size != b.size:
        return {"error": "size %s vs %s" % (a.size, b.size)}
    d = ImageChops.difference(a, b)
    # Collapse the RGB delta to one number per pixel: the max channel delta
    # catches a colour change that a luminance average would wash out.
    px = d.getdata()
    W, H = a.size
    n_diff = 0
    maxd = 0
    x0 = y0 = 10 ** 9
    x1 = y1 = -1
    for i, (r, g, bl) in enumerate(px):
        m = r if r > g else g
        if bl > m:
            m = bl
        if m > maxd:
            maxd = m
        if m > tol:
            n_diff += 1
            x = i % W
            y = i // W
            if x < x0:
                x0 = x
            if x > x1:
                x1 = x
            if y < y0:
                y0 = y
            if y > y1:
                y1 = y
    total = W * H
    return {"w": W, "h": H, "total": total, "ndiff": n_diff, "maxd": maxd,
            "bbox": (x0, y0, x1, y1) if n_diff else None,
            "frac": float(n_diff) / total, "img_a": a, "img_b": b, "dimg": d}


def swatch(before, after, d, out_path):
    """before | after | diff-boosted, side by side, downscaled to fit."""
    w, h = before.size
    gap = 6
    sheet = Image.new("RGB", (w * 3 + gap * 2, h), (24, 24, 28))
    sheet.paste(before, (0, 0))
    sheet.paste(after, (w + gap, 0))
    # Boost the difference so a delta of 6 is visible; scale each channel by 8.
    boosted = d.point(lambda v: min(255, v * 8))
    sheet.paste(boosted, (2 * (w + gap), 0))
    scale = 1500.0 / sheet.size[0]
    if scale < 1.0:
        sheet = sheet.resize((int(sheet.size[0] * scale),
                              int(sheet.size[1] * scale)), Image.LANCZOS)
    sheet.save(out_path)
    return out_path


def _find(d, name):
    for cand in (name, name + ".png"):
        p = os.path.join(d, cand)
        if os.path.isfile(p):
            return p
    return None


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    d = argv[0]
    tol = 3
    write = False
    explicit = None
    i = 1
    while i < len(argv):
        if argv[i] == "--tol":
            i += 1
            tol = int(argv[i])
        elif argv[i] == "--write":
            write = True
        elif argv[i] == "--names":
            i += 1
            explicit = [s for s in argv[i].split(",") if s]
        i += 1

    if not os.path.isdir(d):
        print("no such directory: %s" % d)
        return 2

    # The engine writes exports with no extension, so do not filter on ".png".
    files = {}
    for f in sorted(os.listdir(d)):
        base, ext = os.path.splitext(f)
        if ext.lower() not in ("", ".png"):
            continue
        if base.endswith("_before"):
            files.setdefault(base[:-len("_before")], {})["before"] = os.path.join(d, f)
        elif base.endswith("_after"):
            files.setdefault(base[:-len("_after")], {})["after"] = os.path.join(d, f)

    if explicit:
        # Ordered comparison: n0 vs n1, n1 vs n2, ... For a probe that holds the
        # camera still and changes one thing per frame, the question is always
        # "what did THIS step add", not "is this a before/after pair".
        pairs = {}
        for a, b in zip(explicit, explicit[1:]):
            pa = _find(d, a)
            pb = _find(d, b)
            if pa and pb:
                pairs["%s -> %s" % (a, b)] = {"before": pa, "after": pb}
            else:
                print("missing frame for %s -> %s  (%s / %s)" % (a, b, pa, pb))
    else:
        pairs = {k: v for k, v in files.items()
                 if "before" in v and "after" in v}
    print("directory : %s" % d)
    print("pairs     : %d  (tol=%d per channel)" % (len(pairs), tol))
    print("")

    if not pairs:
        print("NO COMPLETE PAIRS FOUND.")
        print("  A _before with no _after means the run stopped between the two")
        print("  shots. Check the export log, not this tool's output.")
        return 2

    quiet = []
    for k in sorted(pairs):
        p = pairs[k]
        r = diff_pair(p["before"], p["after"], tol)
        if "error" in r:
            print("%-34s SIZE MISMATCH: %s" % (k, r["error"]))
            quiet.append(k)
            continue
        print("%-34s %dx%d" % (k, r["w"], r["h"]))
        print("    differing pixels : %d / %d  (%.3f%% of frame)"
              % (r["ndiff"], r["total"], 100.0 * r["frac"]))
        print("    max channel delta: %d" % r["maxd"])
        if r["bbox"]:
            x0, y0, x1, y1 = r["bbox"]
            print("    bounding box     : x %d..%d  y %d..%d  (%dx%d px)"
                  % (x0, x1, y0, y1, x1 - x0 + 1, y1 - y0 + 1))
            print("    => DIFFERENT: something rendered after the reactivate")
        else:
            print("    => IDENTICAL within tolerance: the forced reactivate put")
            print("       nothing new on screen")
            quiet.append(k)
        if write:
            # The label can be "a -> b", which is not a legal filename.
            safe = "".join(c if (c.isalnum() or c in "-_") else "_" for c in k)
            out = os.path.join(d, "_ab_%s.png" % safe)
            swatch(r["img_a"], r["img_b"], r["dimg"], out)
            print("    sheet            : %s" % os.path.basename(out))
        print("")

    print("=" * 66)
    print("pairs with no visible difference: %d of %d" % (len(quiet), len(pairs)))
    for k in quiet:
        print("    - %s" % k)
    print("")
    print("Read that list against the emitter table, not against zero:")
    print("  * E_ScarMist / E_ArcMist / E_MistWake carry User.MistCount /")
    print("    User.MistRate = 0 in the Normal profile. Quiet is CORRECT there.")
    print("  * Anything else on the list either does not run, renders through an")
    print("    invisible material, or is too small to register at 3 m. Those are")
    print("    three different diagnoses and the bounding box tells them apart.")
    return len(quiet)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
