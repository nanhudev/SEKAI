"""SEKAI UE5 Sword VFX - VFX mask texture generator.

Deterministic, dependency-light (numpy + pillow). Produces the clean VFX masks
the sword line needs. Deliberately NOT photoreal smoke and NOT fire noise: these
are thin, high-contrast, readable sheets.

Channel convention used by every M_SW_* master material:

    R = CORE        near-white, sharp. Drives the hot centre of a stroke.
    G = GLOW        soft falloff. Drives the coloured bleed / bloom skirt.
    B = DETAIL      secondary data. Breakup, mist leak, distortion strength.
    A = MASK        what to draw at all.

Sizes are 512 unless noted. Everything is authored so that the U axis is the
"travel" axis wherever a system needs to scroll the texture along the blade or
along an arc: those maps are invariant along U so scrolling never pops.

Usage:
    python gen_textures.py [outdir]
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import math
import os
import sys

import numpy as np
from PIL import Image

SIZE = 512


# ---------------------------------------------------------------- noise tools
def _hash2(ix, iy, seed):
    """Integer lattice -> [0,1) pseudo random, stable across runs."""
    h = (ix * 374761393 + iy * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF) / float(0x1000000)


def value_noise(x, y, seed=0):
    """Bilinear value noise. x,y are float arrays in lattice units."""
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    fx = x - x0
    fy = y - y0
    # quintic smoothstep - no visible lattice creases
    sx = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
    sy = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
    n00 = _hash2(x0, y0, seed)
    n10 = _hash2(x0 + 1, y0, seed)
    n01 = _hash2(x0, y0 + 1, seed)
    n11 = _hash2(x0 + 1, y0 + 1, seed)
    a = n00 + (n10 - n00) * sx
    b = n01 + (n11 - n01) * sx
    return a + (b - a) * sy


def fbm(x, y, octaves=5, seed=0, gain=0.5, lac=2.0):
    total = np.zeros_like(x, dtype=np.float64)
    amp = 1.0
    norm = 0.0
    fx, fy = x.copy(), y.copy()
    for o in range(octaves):
        total += amp * value_noise(fx, fy, seed + o * 131)
        norm += amp
        amp *= gain
        fx *= lac
        fy *= lac
    return total / norm


def uv_grid(size=SIZE):
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    return xs / (size - 1.0), ys / (size - 1.0)


def smoothstep(a, b, t):
    """Smoothstep that also handles descending edges (a > b).

    The denominator keeps its sign; guarding it with max(.., eps) silently
    inverted every descending edge into a constant zero.
    """
    den = b - a
    if abs(den) < 1e-9:
        den = 1e-9 if den >= 0 else -1e-9
    x = np.clip((t - a) / den, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def pack(core, glow, detail, mask):
    """Assemble RGBA float arrays -> 8 bit image. Scalars broadcast."""
    ref = np.asarray(mask, dtype=np.float64)
    shape = ref.shape or (1,)

    def arr(v):
        a = np.asarray(v, dtype=np.float64)
        return np.broadcast_to(a, shape)

    rgba = np.stack([np.clip(arr(core), 0, 1),
                     np.clip(arr(glow), 0, 1),
                     np.clip(arr(detail), 0, 1),
                     np.clip(arr(mask), 0, 1)], axis=-1)
    return Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8), mode="RGBA")


# ------------------------------------------------------------------- maps
def t_edge_mask():
    """Thin cold glint ramp. Completely invariant along U so a glint can scroll.

    V=0 is the blade edge, V=1 is off the blade. Three nested bands:
    a razor core, a tight inner glow, and a wide faint skirt.

    Iteration note: the first version modulated the core along U, which put a
    visible repeating bead pattern down the length of every stroke the moment a
    system scrolled it. Any variation along the sweep now has to come from the
    system (over-life curves), never from this map - so this map is a pure
    function of V.
    """
    _u, v = uv_grid()
    d = np.abs(v - 0.5)

    core = np.exp(-(d / 0.020) ** 2)
    inner = np.exp(-(d / 0.065) ** 2) * 0.62
    skirt = np.exp(-(d / 0.230) ** 2) * 0.22

    # V-only soft asymmetry: a stroke is hotter on the edge side than the wake side
    side = 1.0 + 0.16 * np.tanh((0.5 - v) * 26.0)
    core = core * side

    glow = np.maximum(inner, skirt)
    mask = np.clip(core + glow, 0, 1)
    return pack(core, glow, np.clip(glow * 0.65, 0, 1), mask)


def t_streak():
    """Glint / motes streak: a small hot point with an elongated soft tail.

    U is the tail axis. Used for the inspect glint and for angle-of-view
    starbursts without ever needing a lens flare.
    """
    u, v = uv_grid()
    cu = 0.30
    du = u - cu
    dv = v - 0.5
    # hot point
    core = np.exp(-((du / 0.018) ** 2 + (dv / 0.030) ** 2))
    # horizontal tail (brighter one way, like a specular smear)
    tail_l = np.exp(-(du / 0.260) ** 2) * np.exp(-(dv / 0.055) ** 2) * 0.55
    tail_r = np.exp(-(du / 0.085) ** 2) * np.exp(-(dv / 0.040) ** 2) * 0.75
    skirt = np.exp(-((du / 0.55) ** 2 + (dv / 0.30) ** 2)) * 0.12
    # four-point star hint, very restrained
    sx = np.exp(-(du / 0.330) ** 2) * np.exp(-(dv / 0.012) ** 2) * 0.34
    sy = np.exp(-(du / 0.014) ** 2) * np.exp(-(dv / 0.300) ** 2) * 0.34
    glow = np.clip(tail_l + tail_r + skirt + sx + sy, 0, 1)
    mask = np.clip(core + glow, 0, 1)
    return pack(core, glow, 0.5, mask)


def t_mote():
    """Purple mote / point glint: small, soft, with a real core. 256."""
    size = 256
    u, v = uv_grid(size)
    d = np.sqrt((u - 0.5) ** 2 + (v - 0.5) ** 2) * 2.0
    core = np.exp(-(d / 0.075) ** 2)
    halo = np.exp(-(d / 0.330) ** 2) * 0.42
    glow = halo
    mask = np.clip(core + halo, 0, 1)
    return pack(core, glow, 0.5, mask)


def t_scar_mask():
    """World-space spatial scar: a long, slightly irregular slash along U.

    Tapers to nothing at both ends so the draw-on reads as a cut being made,
    not a sticker appearing. B carries the amount of void/mist leak.

    Iteration note: the first version used a single low-frequency wobble and
    came out looking like a drawn sine wave. A cut is mostly straight, so the
    low-frequency term is now much smaller and a small high-frequency jitter
    supplies the "walking blade" quality.
    """
    u, v = uv_grid()
    slow = (fbm(u * 2.4, np.zeros_like(u) + 0.5, octaves=2, seed=41) - 0.5) * 0.042
    fast = (fbm(u * 37.0, np.zeros_like(u) + 4.5, octaves=2, seed=43) - 0.5) * 0.013
    dv = v - (0.5 + slow + fast)

    # thickness is not constant - a cut thins where it accelerates
    tp = fbm(u * 6.0, np.zeros_like(u) + 9.0, octaves=4, seed=57)
    thick = 0.0068 * (0.42 + 1.15 * smoothstep(0.12, 0.88, tp))
    core = np.exp(-(dv / np.maximum(thick, 1e-4)) ** 2)

    inner = np.exp(-(dv / (thick * 4.0)) ** 2) * 0.46
    outer = np.exp(-(dv / (thick * 12.0)) ** 2) * 0.14

    # end taper: the cut has a definite start and end, sharpened at the tips
    taper = smoothstep(0.0, 0.030, u) * smoothstep(1.0, 0.970, u)
    taper = taper ** 0.72
    core = core * taper
    inner = inner * taper
    outer = outer * taper

    glow = np.maximum(inner, outer)
    leak = np.exp(-(dv / (thick * 21.0)) ** 2) * taper * 0.85
    mask = np.clip(core + glow, 0, 1)
    return pack(core, glow, leak, mask)


def t_wave_mask():
    """Mid-range pressure sheet: thin bright leading edge, faint body, ends taper.

    U = along the swept arc. V = across the sheet; the leading edge sits at
    V=0.10 and the sheet body trails off by V~0.62.

    Iteration note: the first version put the leading edge exactly on V=0, so
    half the texture was empty and the sheet read as a band stuck to the top of
    the UV square. The profile is now inset and the sheet occupies most of V.
    """
    u, v = uv_grid()
    edge = 0.10

    lead = np.exp(-((v - edge) / 0.048) ** 2)
    body = np.exp(-((v - edge) / 0.200) ** 2) * 0.42
    air = np.exp(-((v - edge) / 0.470) ** 2) * 0.11

    # the sheet is not uniform along its length
    ripple = 0.80 + 0.20 * fbm(u * 7.0, v * 3.0, octaves=4, seed=73)
    lead = lead * ripple
    body = body * ripple

    # leading edge stays crisper than the body at the tips
    lead = lead * smoothstep(0.0, 0.030, u) * smoothstep(1.0, 0.970, u) ** 0.7
    taper = smoothstep(0.0, 0.075, u) * smoothstep(1.0, 0.925, u) ** 0.7
    body = body * taper
    air = air * taper

    glow = np.clip(body + air, 0, 1)
    mask = np.clip(lead + glow, 0, 1)
    return pack(lead, glow, np.clip(ripple - 0.6, 0, 1) * 1.4, mask)


def t_mist_mask():
    """Black mist / wisp alpha. Stretched along U. No billowing smoke bells.

    Iteration note: plain fbm at high contrast produced soft round blobs. Mist
    that reads as mist has to be filamentary, so the noise is now ridged
    (1-|2n-1|) and then sheared, which is what turns blobs into strands.
    """
    u, v = uv_grid()

    # anisotropic ridged noise: compressed on V, stretched on U
    n1 = fbm(u * 1.7, v * 13.0, octaves=5, seed=101)
    n2 = fbm(u * 4.4, v * 31.0, octaves=4, seed=113)

    def ridge(n):
        return 1.0 - np.abs(2.0 * n - 1.0)

    f1 = ridge(n1) ** 2.1
    f2 = ridge(n2) ** 2.8
    wisps = f1 * 0.66 + f2 * 0.34

    # shear: wisps lean, so they are not vertical combs
    shear_v = v + (u - 0.5) * 0.16
    strands = np.exp(-(np.abs(np.sin((shear_v * 5.0 + n1 * 1.7) * math.pi)) / 0.46) ** 2)
    alpha = wisps * (0.46 + 0.54 * strands)
    alpha = smoothstep(0.04, 0.66, alpha)

    # vertical falloff so it fades rather than ends
    fade = smoothstep(0.0, 0.14, v) * smoothstep(1.0, 0.84, v)
    fade *= smoothstep(0.0, 0.05, u) * smoothstep(1.0, 0.95, u)
    alpha *= fade

    core = alpha * 0.16
    glow = alpha
    return pack(core, glow, alpha * 0.55, alpha)


def t_distortion_normal():
    """Flow / refraction offset map. RG = signed direction, B = curl, A = strength.

    Smooth and large scale on purpose: high frequency here turns into pixel
    soup the moment a particle is small on screen.

    Iteration note: the curl channel ran at 2x the base frequency and speckled
    the whole map when previewed. Frequencies are now well separated from the
    gradient field so the R/G direction data survives compression.
    The strength term was also a smoothstep, which put a contour line wherever
    it crossed a threshold - visible as colour banding that would have read as
    hard rings in refraction. It is now a gentle continuous field.
    """
    u, v = uv_grid()
    fx = fbm(u * 2.2, v * 2.2, octaves=3, seed=211)
    fy = fbm(u * 2.2, v * 2.2, octaves=3, seed=307)
    dx = np.gradient(fx, axis=1)
    dy = np.gradient(fy, axis=0)
    mag = np.sqrt(dx ** 2 + dy ** 2) + 1e-6
    nx = dx / mag
    ny = dy / mag

    strength = 0.32 + 0.68 * fbm(u * 1.6, v * 1.6, octaves=3, seed=401)
    # RG packed 0..1 around 0.5 so no sign is lost in 8 bit
    r = 0.5 + 0.5 * nx * strength
    g = 0.5 + 0.5 * ny * strength
    curl = fbm(u * 2.6, v * 2.6, octaves=2, seed=503)
    return pack(r, g, curl, strength)


MAPS = {
    "T_SW_EdgeMask": (t_edge_mask, 512),
    "T_SW_Streak": (t_streak, 512),
    "T_SW_Mote": (t_mote, 256),
    "T_SW_ScarMask": (t_scar_mask, 512),
    "T_SW_WaveMask": (t_wave_mask, 512),
    "T_SW_MistMask": (t_mist_mask, 512),
    "T_SW_DistortionNormal": (t_distortion_normal, 512),
}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else \
        str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/source/textures')
    os.makedirs(out, exist_ok=True)
    for name, (fn, _size) in MAPS.items():
        img = fn()
        path = os.path.join(out, name + ".png")
        img.save(path)
        a = np.asarray(img).astype(np.float64) / 255.0
        print("%-24s %s  %dx%d  meanA=%.3f maxA=%.3f" % (
            name, "written", img.size[0], img.size[1], a[..., 3].mean(), a[..., 3].max()))
    print("textures -> " + out)


if __name__ == "__main__":
    main()
