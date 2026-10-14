"""SEKAI Sword VFX - host-side PNG inspection. PIL is required; the engine's
Python has no image library, so this runs on the HOST interpreter:

    C:/Users/Administrator/AppData/Local/Programs/Python/Python311/python.exe \\
        scripts/png_dump.py <file-or-dir> [...]

WHY THIS EXISTS, and why it is not "nice to have".

    A render target that was never rendered into and a render target that was
    rendered into but shows a black scene both export as "a black PNG". The mean
    luminance of the two is nearly identical (both ~0) and both fail a
    brightness gate. They are completely different problems, and the measured
    alpha channel separates them cleanly:

        alpha == 0 everywhere   -> the RT was never written. Nothing rendered
                                   into it. Authoring bug / no render pass.
        alpha == 255 everywhere -> something DID render, and the thing rendered
                                   is black. Lighting/placement bug.

    swimg.png_probe() reports mean luma and a count of distinct byte values,
    which is enough for a pass/fail gate but NOT enough to tell those two apart:
    "5 distinct byte values, mean luma 0.10" is consistent with either. So this
    dumps the actual histogram, the alpha range, and the most common pixels, and
    prints a one-line reading of what that means.

    It also reports whether an image is a single flat colour, which catches the
    other silent shape of failure: every camera exporting the same cleared
    buffer under a different filename.
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import os
import sys
from collections import Counter

try:
    from PIL import Image
except ImportError:
    print("PIL is not available on this interpreter. Run this with")
    print(_sekai_os.environ.get('PYTHON_BIN', 'python'))
    raise SystemExit(2)


def analyse(path):
    im = Image.open(path)
    im.load()
    mode = im.mode
    rgba = im.convert("RGBA")
    w, h = rgba.size
    px = list(rgba.getdata())
    n = len(px)

    alpha = [p[3] for p in px]
    a_min, a_max = min(alpha), max(alpha)

    luma = sum(0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2] for p in px) / n

    # Distinct RGB triples, and the top few by count.
    rgb = [(p[0], p[1], p[2]) for p in px]
    counts = Counter(rgb)
    distinct_rgb = len(counts)
    top = counts.most_common(4)

    all_bytes = Counter()
    for p in px:
        for b in p:
            all_bytes[b] += 1
    distinct_bytes = len(all_bytes)

    print("=" * 72)
    print("%s" % path)
    print("    size          : %dx%d  mode=%s  rgb_mode=%s"
          % (w, h, mode, im.mode))
    print("    mean luma     : %.4f  (of 255)" % luma)
    print("    distinct RGB  : %d" % distinct_rgb)
    print("    distinct bytes: %d" % distinct_bytes)
    print("    alpha         : min=%d max=%d" % (a_min, a_max))
    print("    top RGB triples:")
    for (r, g, b), c in top:
        print("        %-16s %10d  (%5.2f%%)" % ("(%d,%d,%d)" % (r, g, b),
                                                  c, 100.0 * c / n))

    # --- the reading -------------------------------------------------------
    if a_max == 0:
        verdict = ("NEVER WRITTEN - alpha is 0 everywhere, so the render target "
                   "is still in its initialised state. Nothing rendered into it.")
    elif a_min == 255 and distinct_rgb == 1:
        verdict = ("FLAT OPAQUE %s - something wrote this, and it is one solid "
                   "colour. Either a clear, or a scene with nothing in frame."
                   % str(top[0][0]))
    elif distinct_rgb <= 8:
        verdict = ("NEAR-FLAT (%d colours) - written, but almost no image. A "
                   "rendered scene has hundreds of colours." % distinct_rgb)
    else:
        verdict = "HAS AN IMAGE (%d colours, mean luma %.2f)" % (distinct_rgb, luma)
    print("    READING       : %s" % verdict)
    return {"path": path, "mean_luma": luma, "distinct_rgb": distinct_rgb,
            "alpha_min": a_min, "alpha_max": a_max,
            "flat": distinct_rgb == 1, "never_written": a_max == 0,
            "top_rgb": top[0][0] if top else None}


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    targets = []
    for a in argv:
        if os.path.isdir(a):
            for name in sorted(os.listdir(a)):
                p = os.path.join(a, name)
                if not os.path.isfile(p):
                    continue
                # NOT filtered on ".png". The engine writes render target
                # exports with NO extension (RenderingLibrary.export_render_target
                # writes `dir/name` verbatim), so an earlier version of this
                # scan silently matched nothing and exited 0 having printed
                # nothing - which reads like "no problems found".
                targets.append(p)
        else:
            targets.append(a)

    results = []
    for t in targets:
        if not os.path.isfile(t):
            print("missing: %s" % t)
            continue
        try:
            results.append(analyse(t))
        except Exception as exc:
            print("FAILED on %s: %s" % (t, exc))

    # The cross-frame question the gate cannot ask: are these all the SAME
    # frame? Byte-identical exports from different cameras mean the capture
    # never moved, or the world never rendered.
    if len(results) > 1:
        print("=" * 72)
        print("--- across %d image(s) ---" % len(results))
        greens = [r for r in results if r["top_rgb"] == (0, 255, 0)]
        if greens:
            print("    %d of them are solid green (a clear we performed) - "
                  "export reads the target correctly." % len(greens))
        never = [r for r in results if r["never_written"]]
        if never:
            print("    %d never written (alpha 0): %s"
                  % (len(never), ", ".join(os.path.basename(r["path"])
                                           for r in never)))
        sigs = {}
        for r in results:
            sigs.setdefault((r["mean_luma"], r["distinct_rgb"], r["top_rgb"]),
                            []).append(os.path.basename(r["path"]))
        groups = [v for v in sigs.values() if len(v) > 1]
        if groups:
            print("    IDENTICAL SIGNATURE groups (different names, same "
                  "content):")
            for g in groups:
                print("        %s" % ", ".join(g))
        else:
            print("    no two images share a content signature - they differ, "
                  "so the camera moves are real.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
