"""Verify swimg's PNG reader against PIL. HOST interpreter only.

    C:/Users/Administrator/AppData/Local/Programs/Python/Python311/python.exe \\
        tools/verify_png_probe.py [file-or-dir ...]

WHY, AND WHY ON THE HOST

    swimg.py decodes PNG by hand - it has to, because the engine's Python has no
    image library and the render scripts run inside the engine. A hand-rolled
    decoder is exactly the kind of code that can be confidently wrong, and it
    HAS been: the first version read the filtered IDAT deltas as if they were
    pixels and reported mean luma 2.44 for a frame PIL measures at 0.10. A
    plausible number, from a check whose entire job was to catch bad frames.

    So the reader is checked against an independent implementation on every
    change. PIL lives on the host interpreter, so this runs there.

WHAT IT CHECKS

    1. mean_luma matches PIL within tolerance on every real frame given.
    2. The dominant colour matches PIL's most common RGB triple. This is the
       statistic the green-clear test relies on, so it gets its own assertion
       rather than being folded into the luma check.
    3. A synthesised flat-green PNG is read back as flat green - the green-clear
       test is verified end to end, including the dither that a real export
       introduces (tested separately with a 1-in-9 noise pattern).
    4. alpha_min/alpha_max are read at all, since "alpha 0 everywhere" is the
       reading that distinguishes never-written from rendered-black.

    Exit code is the number of failed checks, so it can gate a build.
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "scripts"))

try:
    from PIL import Image
except ImportError:
    print("PIL missing. Run this with the host interpreter:")
    print(_sekai_os.environ.get('PYTHON_BIN', 'python'))
    raise SystemExit(2)

import swimg  # noqa: E402

DEFAULT_FRAMES = os.path.join(os.path.dirname(HERE), "exports", "black_pass_01")
LUMA_TOL = 0.75          # the two implementations sample on different strides


def write_png(path, w, h, pixel_fn):
    """Minimal 8-bit RGBA PNG writer with ftype 0 rows."""
    rows = []
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            row.extend(pixel_fn(x, y))
        rows.append(bytes(row))
    raw = zlib.compress(b"".join(rows), 9)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    blob = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", raw)
            + chunk(b"IEND", b""))
    with open(path, "wb") as fh:
        fh.write(blob)
    return path


def pil_dominant(path):
    im = Image.open(path).convert("RGBA")
    counts = {}
    for p in im.getdata():
        key = (p[0], p[1], p[2])
        counts[key] = counts.get(key, 0) + 1
    top = max(counts.items(), key=lambda kv: kv[1])
    n = sum(counts.values())
    return top[0], float(top[1]) / n


def pil_alpha_range(path):
    im = Image.open(path).convert("RGBA")
    a = [p[3] for p in im.getdata()]
    return min(a), max(a)


def check_frame(path, failures):
    st = swimg.png_stats(path)
    if st is None:
        print("  ! %s: swimg could not read it at all" % path)
        failures.append(path)
        return
    im = Image.open(path).convert("RGBA")
    px = list(im.getdata())
    n = len(px)
    pil_luma = sum(0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]
                   for p in px) / n
    pil_top, pil_frac = pil_dominant(path)
    pil_a = pil_alpha_range(path)

    dl = abs(st["mean_luma"] - pil_luma)
    ok_l = dl <= LUMA_TOL
    ok_t = st["top_rgb"] == pil_top
    ok_a = (st["alpha_min"] == pil_a[0] and st["alpha_max"] == pil_a[1])

    print("  %s" % os.path.basename(path))
    print("      luma   swimg=%.4f  pil=%.4f  (d=%.4f) %s"
          % (st["mean_luma"], pil_luma, dl, "OK" if ok_l else "MISMATCH"))
    print("      top    swimg=%-15s pil=%-15s %s"
          % (str(st["top_rgb"]), str(pil_top), "OK" if ok_t else "MISMATCH"))
    print("      frac   swimg=%.4f  pil=%.4f" % (st["top_rgb_frac"], pil_frac))
    print("      alpha  swimg=%s..%s  pil=%d..%d  %s"
          % (st["alpha_min"], st["alpha_max"], pil_a[0], pil_a[1],
             "OK" if ok_a else "MISMATCH"))
    if not (ok_l and ok_t and ok_a):
        failures.append(path)


def main(argv):
    failures = []
    targets = []
    for a in argv:
        if os.path.isdir(a):
            targets += [os.path.join(a, n) for n in sorted(os.listdir(a))
                        if os.path.isfile(os.path.join(a, n))]
        else:
            targets.append(a)
    if not targets and os.path.isdir(DEFAULT_FRAMES):
        targets = [os.path.join(DEFAULT_FRAMES, n)
                   for n in sorted(os.listdir(DEFAULT_FRAMES))]

    print("--- 1/3 real frames: swimg vs PIL ---")
    if not targets:
        print("  (none found; pass a directory or file)")
    for t in targets:
        check_frame(t, failures)

    print("--- 2/3 synthesised flat green + dither ---")
    tmp = os.path.join(HERE, "_verify_tmp")
    os.makedirs(tmp, exist_ok=True)
    try:
        flat = write_png(os.path.join(tmp, "flat_green.png"), 64, 64,
                         lambda x, y: (0, 255, 0, 255))
        st = swimg.png_stats(flat)
        ok, why = swimg.is_flat_colour(flat, (0, 255, 0))
        print("  flat green  -> top=%s mean_luma=%.1f  is_flat=%s (%s)"
              % (st["top_rgb"], st["mean_luma"], ok, why))
        if not ok:
            failures.append("flat green not recognised")

        # A real export is dithered by one code value, so the reader must still
        # call a clear colour flat when ~11% of pixels wobble.
        #
        # The pattern must NOT be periodic on a small grid. MEASURED: with
        # `(x + y) % 9 == 0` the reader reported 66.5% dominant green instead of
        # 88.9%, because it samples every third row and every third pixel - a
        # stride of 6 - and 6 mod 9 cycles through {0, 6, 3}, so a third of the
        # SAMPLED pixels landed on noise. The reader was right; the test was
        # aliasing with its stride. Real exporter dither is not periodic, which
        # is why it reads back as 0.8982 against PIL's 0.8981.
        def noise(x, y):
            h = (x * 7919 + y * 104729) & 0xFFFF
            return (1, 255, 1, 255) if h % 9 == 0 else (0, 255, 0, 255)

        dith = write_png(os.path.join(tmp, "green_dither.png"), 64, 64, noise)
        ok2, why2 = swimg.is_flat_colour(dith, (0, 255, 0))
        st2 = swimg.png_stats(dith)
        print("  dithered    -> top=%s at %.1f%%  is_flat=%s (%s)"
              % (st2["top_rgb"], 100.0 * st2["top_rgb_frac"], ok2, why2))
        if not ok2:
            failures.append("dithered green not recognised as flat")

        # And it must NOT call a red frame green.
        red = write_png(os.path.join(tmp, "red.png"), 64, 64,
                        lambda x, y: (255, 0, 0, 255))
        ok3, _ = swimg.is_flat_colour(red, (0, 255, 0))
        print("  red frame   -> is_flat(green)=%s %s"
              % (ok3, "OK" if not ok3 else "FALSE POSITIVE"))
        if ok3:
            failures.append("red frame reported as green")
    finally:
        for n in os.listdir(tmp):
            try:
                os.remove(os.path.join(tmp, n))
            except Exception:
                pass
        try:
            os.rmdir(tmp)
        except Exception:
            pass

    print("--- 3/3 summary ---")
    print("  frames checked : %d" % len(targets))
    print("  failures       : %d" % len(failures))
    for f in failures:
        print("      ! %s" % f)
    return len(failures)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
