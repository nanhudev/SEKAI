from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
# SEKAI / RealityGlass_Lab — build the Reality Fracture.
#
# WHAT THIS IS
#
# The Iaido cut is not supposed to break the world into a phone-screen
# spiderweb. It is supposed to break REALITY, treated as a brittle sheet. So the
# fracture pattern has to obey a design rule rather than a random seed:
#
#   * cells near the cut are FINE      (the blade shatters locally)
#   * cells away from the cut are COARSE (the sheet fails where it was weakest)
#   * no cell is a regular polygon, and no cell is the same size as its
#     neighbour, because a uniform tessellation reads as a net drawn on screen
#   * boundaries are biased ACROSS the cut, which is what glass does under a
#     line load and what stops the pattern reading as a honeycomb
#
# THE FRACTURE IS COMPUTED BY UE5'S OWN GEOMETRY PIPELINE
# (`UDynamicMesh.AppendVoronoiDiagram2D`), not by a solver written here. This
# project is a design / bake / reference tool; the runtime is Godot and nothing
# in this folder ships.
#
# OUTPUTS (all under ue5_lab/exports/)
#   fracture.json              every cell polygon, CCW, in screen-half-height units
#   fracture.obj               the whole tessellation as a mesh (UE-generated)
#   mask_fracture.png          flat colour per cell
#   mask_crack.png             cell boundaries (the seam network, 1px)
#   mask_edge.png              chamfer distance to the seam, for the shard edge
#   mask_shardid.png           R/G/B = cell id, so Godot can index the polygons
#   mask_flow.png              per-cell outward direction (distortion helper)
#   lab_reference_fracture.png the pattern presented as a visual reference

import json
import math
import os
import struct
import zlib

import unreal

EXPORTS = str(_SEKAI_ROOT / 'ue5_lab/exports')
LOG = os.path.join(EXPORTS, "fracture_build.log")

# --- the plane, in "screen half-heights" (the same unit the Godot glass layer
# --- and the world-cut shader already use) --------------------------------
HALF = 1.15
ASPECT = 16.0 / 9.0
HX = HALF * ASPECT

# The Iaido cut: -30 degrees in screen space, through the centre.
CUT_ANGLE = math.radians(-30.0)
CUT_T = (math.cos(CUT_ANGLE), math.sin(CUT_ANGLE))     # along the cut
CUT_N = (-math.sin(CUT_ANGLE), math.cos(CUT_ANGLE))    # across the cut

SEED = 20260927

# mask resolution (16:9, matches the plane's aspect exactly)
MASK_W = 1024
MASK_H = 576


def log(msg):
    with open(LOG, "a", encoding="utf-8") as handle:
        handle.write(str(msg) + "\n")


# ---------------------------------------------------------------------------
# Deterministic RNG. Python's own hash() is randomised per process, so the
# pattern would not be reproducible across runs — and this pattern has to be
# reviewable, so it has to be reproducible.
# ---------------------------------------------------------------------------

class Rng:
    def __init__(self, seed):
        self.s = seed & 0xFFFFFFFF

    def next(self):
        self.s = (1664525 * self.s + 1013904223) & 0xFFFFFFFF
        return self.s / 4294967296.0

    def range(self, lo, hi):
        return lo + (hi - lo) * self.next()


def to_plane(along, dist):
    """(distance along the cut, signed distance from the cut) -> plane x,y."""
    return (
        along * CUT_T[0] + dist * CUT_N[0],
        along * CUT_T[1] + dist * CUT_N[1],
    )


def build_sites():
    """Cut-weighted, ANISOTROPIC, jittered sites.

    The physics being imitated: under a line load, cracks propagate
    PERPENDICULAR to the load line. So the cell boundaries have to run across
    the wound, which makes the cells immediately beside the cut long thin
    slivers stretched ALONG it — not little equilateral tiles.

    That means the two axes have to be scaled in OPPOSITE directions:

      * band k is thin near the cut and thickens with k  (fine in N)
      * the spacing of sites ALONG the cut is coarse near the cut and tightens
        with k                                            (coarse in T)

    An earlier version grew BOTH with k, which produced roughly equilateral
    cells everywhere and read as a mosaic tile, not as brittle glass.
    """
    rng = Rng(SEED)
    sites = []

    # Along-cut extent has to cover the diagonal of the rect, not its width.
    along_span = 2.0 * math.hypot(HX, HALF) + 0.6
    base_thickness = 0.042
    base_along = 0.30

    for side in (-1.0, 1.0):
        k = 0
        d0 = 0.0
        while d0 < HALF * 1.35 + 0.25:
            k += 1
            d1 = base_thickness * (k ** 1.30)
            thickness = d1 - d0
            spacing = base_along * (1.0 + 0.30 * (k - 1)) * rng.range(0.88, 1.14)
            count = max(1, int(math.ceil(along_span / spacing)))
            step = along_span / count
            for i in range(count):
                along = -along_span * 0.5 + (i + 0.5) * step
                # Heavy jitter along the cut: this is what stops neighbouring
                # slivers sharing a boundary and creates the sudden
                # terminations that read as real cracks.
                along += rng.range(-0.45, 0.45) * step
                # Bias the sample toward the inner edge of the band, so cells
                # get denser toward the wound rather than merely smaller.
                u = rng.next() ** 1.25
                dist = (d0 + u * thickness) * side
                jx, jy = to_plane(along, dist)
                # A little purely random scatter on both axes, so no two cells
                # share an edge length.
                jx += rng.range(-1.0, 1.0) * thickness * 0.85
                jy += rng.range(-1.0, 1.0) * thickness * 0.85
                if abs(jx) < HX * 1.16 and abs(jy) < HALF * 1.16:
                    sites.append(unreal.Vector2D(jx, jy))
            d0 = d1

    # A handful of long "runaway" seeds placed well away from the cut. These
    # produce the few long straight boundaries that read as a primary crack
    # rather than as yet another small cell.
    for _ in range(9):
        along = rng.range(-along_span * 0.46, along_span * 0.46)
        dist = rng.range(0.20, 1.15) * (1.0 if rng.next() > 0.5 else -1.0)
        jx, jy = to_plane(along, dist)
        if abs(jx) < HX * 1.10 and abs(jy) < HALF * 1.10:
            sites.append(unreal.Vector2D(jx, jy))

    log("sites: %d" % len(sites))
    return sites


def build_coarse_sites(count=14):
    """The MAIN shards: 8-18 big irregular pieces.

    These are not "the fracture pattern" — they are the pieces the surface
    actually comes apart into at the end. Two rules matter:

      * sizes must be visibly uneven, because glass does not fail into equal
        pieces, and equal pieces read as UI tiles
      * a few must be elongated ACROSS or ALONG the cut, because a line load
        produces slivers, not polygons

    Mitchell's best-candidate sampling gives the irregularity; the random
    weight on the score is what breaks the size uniformity that plain
    farthest-point sampling produces.
    """
    rng = Rng(SEED + 7717)
    chosen = []
    limit = HALF * 1.10

    for i in range(count):
        best = None
        best_score = -1.0
        for _ in range(48):
            cx = rng.range(-HX * 1.06, HX * 1.06)
            cy = rng.range(-limit, limit)
            # distance to the nearest already-chosen site
            near = min(
                (math.hypot(cx - p[0], cy - p[1]) for p in chosen),
                default=1e9,
            )
            # The random weight is the whole point: without it every cell ends
            # up the same size.
            score = near * (0.45 + 1.25 * rng.next())
            if score > best_score:
                best_score = score
                best = (cx, cy)
        if best is None:
            break
        cx, cy = best
        # Jitter the winner so cell boundaries never meet at a clean midpoint.
        cx += rng.range(-0.24, 0.24)
        cy += rng.range(-0.24, 0.24)
        chosen.append((cx, cy))

    # Force four sites tight to the cut with wide spacing along it. These are
    # what produce the long slivers flanking the wound.
    along_span = 2.0 * math.hypot(HX, HALF)
    for i, frac in enumerate((-0.33, -0.10, 0.16, 0.41)):
        along = frac * along_span
        dist = (0.055 if i % 2 == 0 else -0.062) * rng.range(0.8, 1.5)
        px, py = to_plane(along, dist)
        if abs(px) < HX * 1.02 and abs(py) < limit:
            chosen.append((px, py))

    sites = [unreal.Vector2D(p[0], p[1]) for p in chosen]
    log("coarse sites: %d" % len(sites))
    return sites


# ---------------------------------------------------------------------------
# Fracture via UE's Geometry Script.
# ---------------------------------------------------------------------------

def build_fracture_mesh(sites):
    mesh = unreal.DynamicMesh()
    primitive = unreal.GeometryScriptPrimitiveOptions()
    options = unreal.GeometryScriptVoronoiOptions()
    options.set_editor_property("bounds", unreal.Box(
        unreal.Vector(-HX * 1.25, -HALF * 1.25, -0.5),
        unreal.Vector(HX * 1.25, HALF * 1.25, 0.5),
    ))
    options.set_editor_property("bounds_expand", 0.0)
    # `create_cells` is a list of site indices, not a flag; empty means "every
    # site gets a cell", which is what the fracture needs.

    result = mesh.append_voronoi_diagram2d(
        primitive, unreal.Transform(), sites, options
    )
    log("voronoi mesh: %r" % (result,))
    log("triangles: %s  vertices: %s" % (
        mesh.get_triangle_count(), mesh.get_vertex_count()))
    return mesh


# ---------------------------------------------------------------------------
# Cell extraction.
# ---------------------------------------------------------------------------
#
# UE's Python bindings return out-params as GeometryScript*List STRUCTS, not
# Python lists, and a struct cannot be read by iteration. Probed surface:
#
#   GeometryScriptVectorList   -> convert_vector_list_to_array() /
#                                 get_vector_list_length() / get_vector_list_item(i)
#   GeometryScriptTriangleList -> convert_triangle_list_to_array() / ..._length() / ..._item(i)
#   GeometryScriptIndexList    -> convert_index_list_to_array()  / ..._length() / ..._item(i)
#
# Real signatures (from __doc__):
#
#   get_all_vertex_positions(skip_gaps) -> (DynamicMesh, position_list, has_gaps)
#   get_all_triangle_indices(skip_gaps) -> (DynamicMesh, triangle_list, has_gaps)
#   get_all_triangle_polygroup_i_ds(group_layer, polygroup_i_ds_out)
#                                       -> (DynamicMesh, polygroup_i_ds_out)
#
# The payload is index 1 in all three — NOT the last element. The last element
# is a trailing bool, which is what silently produced an empty list twice.
#
# Out-params MUST be a constructed struct instance. Passing None segfaults the
# editor, so `GeometryScriptIndexList()` is always built explicitly.

def _payload(result, index=1):
    """Pull the GeometryScript*List struct out of a UE return value."""
    if isinstance(result, tuple):
        return result[index] if len(result) > index else result[-1]
    return result


def _read_list(wrapper, kind):
    """Read a GeometryScript*List struct into a plain Python list.

    `kind` is one of "vector", "triangle", "index".
    """
    if wrapper is None:
        return []
    convert = getattr(wrapper, "convert_%s_list_to_array" % kind, None)
    if convert is not None:
        try:
            raw = convert()
            arr = raw[-1] if isinstance(raw, tuple) and len(raw) >= 2 else raw
            if arr is not None:
                out = list(arr)
                if out:
                    return out
        except Exception as exc:  # noqa: BLE001
            log("convert_%s_list_to_array failed: %s" % (kind, exc))
    length = getattr(wrapper, "get_%s_list_length" % kind, None)
    item = getattr(wrapper, "get_%s_list_item" % kind, None)
    if length is None or item is None:
        log("WARN: no accessors for %s list" % kind)
        return []
    n = int(length())
    return [item(i) for i in range(n)]


def _group_layer():
    """UE's PolyGroup group-layer descriptor for the standard layer."""
    cls = getattr(unreal, "GeometryScriptGroupLayer", None)
    if cls is None:
        log("WARN: unreal.GeometryScriptGroupLayer missing")
        return None
    try:
        # Defaults are already {default_layer: True, extended_layer_index: 0},
        # which is the standard PolyGroup layer the Voronoi append writes to.
        return cls()
    except Exception as exc:  # noqa: BLE001
        log("group layer ctor failed: %s" % exc)
        return None


def _flatten_triangles(entries):
    """Triangle list -> flat [a,b,c, a,b,c, ...]."""
    flat = []
    for e in entries:
        if isinstance(e, int):
            flat.append(e)
            continue
        got = False
        for attr in ("x", "y", "z"):
            v = getattr(e, attr, None)
            if v is None:
                break
            flat.append(int(v))
            got = True
        if got:
            continue
        if isinstance(e, (list, tuple)):
            flat.extend(int(v) for v in e)
            continue
        try:
            flat.extend(int(v) for v in e)
        except TypeError:
            pass
    return flat


def convex_hull(points):
    """Andrew's monotone chain. Voronoi cells clipped to a box are convex, so
    this is an exact outline and doubles as a fallback if the edge walk is
    disturbed by non-shared vertex ids."""
    pts = sorted(set((round(p[0], 6), round(p[1], 6)) for p in points))
    if len(pts) < 3:
        return [list(p) for p in pts]

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return [list(p) for p in (lower[:-1] + upper[:-1])]


def polygon_area(poly):
    s = 0.0
    n = len(poly)
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        s += a[0] * b[1] - b[0] * a[1]
    return s * 0.5


def outline_from_triangles(polys, positions):
    """Walk the cell's triangle boundary. Returns None if the soup does not
    share vertex ids (interior edges then fail to cancel)."""
    edge_count = {}
    for (a, b, c) in polys:
        for (p, q) in ((a, b), (b, c), (c, a)):
            key = (min(p, q), max(p, q))
            edge_count[key] = edge_count.get(key, 0) + 1
    boundary = [e for e, n in edge_count.items() if n == 1]
    # A triangulation of T triangles has 3T edges; one that cancels properly
    # leaves roughly 2*sqrt(T) boundary edges. If we got nearly all of them,
    # nothing cancelled and the walk is meaningless.
    if len(boundary) * 4 > len(polys) * 3:
        return None

    adj = {}
    for (p, q) in boundary:
        adj.setdefault(p, []).append(q)
        adj.setdefault(q, []).append(p)
    start = boundary[0][0]
    loop = [start]
    prev = None
    cur = start
    for _ in range(8192):
        nxts = [n for n in adj.get(cur, []) if n != prev]
        if not nxts:
            break
        nxt = nxts[0]
        if nxt == start:
            break
        loop.append(nxt)
        prev, cur = cur, nxt
    if len(loop) < 3:
        return None
    return [[positions[i].x, positions[i].y] for i in loop]


def extract_cells(mesh):
    positions = _read_list(
        _payload(mesh.get_all_vertex_positions(True)), "vector")
    log("vertex payload: %d entries" % len(positions))
    if not positions:
        positions = _read_list(
            _payload(mesh.get_all_vertex_positions(False)), "vector")
        log("vertex payload (skip_gaps=False): %d entries" % len(positions))

    indices = _flatten_triangles(_read_list(
        _payload(mesh.get_all_triangle_indices(True)), "triangle"))
    log("index payload: %d entries" % len(indices))

    layer = _group_layer()
    polygroups = []
    if layer is not None:
        # The out-param must be a real struct; None segfaults the editor.
        out = unreal.GeometryScriptIndexList()
        polygroups = _read_list(
            _payload(mesh.get_all_triangle_polygroup_i_ds(layer, out)), "index")
    log("polygroup payload: %d entries" % len(polygroups))

    tris = min(len(polygroups), len(indices) // 3)
    log("extract: %d verts, %d indices, %d tris, %d groups"
        % (len(positions), len(indices), tris, len(set(polygroups[:tris]))))
    if tris == 0:
        log("FAIL: could not read triangle polygroups")
        return []

    per_group = {}
    for t in range(tris):
        gid = polygroups[t]
        per_group.setdefault(gid, []).append((
            indices[t * 3 + 0], indices[t * 3 + 1], indices[t * 3 + 2]))

    cells = []
    from_walk = 0
    from_hull = 0
    for gid in sorted(per_group):
        polys = per_group[gid]
        clean = outline_from_triangles(polys, positions)
        if clean is not None:
            # Drop duplicated consecutive points and a repeated closing point.
            dedup = []
            for p in clean:
                if not dedup or math.hypot(p[0] - dedup[-1][0], p[1] - dedup[-1][1]) > 1e-5:
                    dedup.append(p)
            if len(dedup) > 2 and math.hypot(
                    dedup[0][0] - dedup[-1][0], dedup[0][1] - dedup[-1][1]) <= 1e-5:
                dedup.pop()
            clean = dedup

        hull = convex_hull([[positions[i].x, positions[i].y]
                            for tri in polys for i in tri])
        if clean is None or len(clean) < 3:
            clean = hull
            from_hull += 1
        else:
            # Voronoi cells are convex, so the walk and the hull must agree.
            # If they disagree the walk found the wrong loop.
            walk_area = abs(polygon_area(clean))
            hull_area = abs(polygon_area(hull))
            if hull_area > 1e-9 and abs(walk_area - hull_area) > 0.02 * hull_area:
                clean = hull
                from_hull += 1
            else:
                from_walk += 1

        if len(clean) < 3:
            continue
        area = polygon_area(clean)
        if abs(area) < 1e-6:
            continue
        if area < 0.0:
            clean.reverse()
            area = -area

        n = len(clean)
        cx = sum(p[0] for p in clean) / n
        cy = sum(p[1] for p in clean) / n
        dist = abs(cx * CUT_N[0] + cy * CUT_N[1])
        cells.append({
            "id": int(gid),
            "area": area,
            "centroid": [cx, cy],
            "dist_to_cut": dist,
            "polygon": clean,
        })

    cells.sort(key=lambda c: c["dist_to_cut"])
    log("cells extracted: %d  (walk %d / hull %d)"
        % (len(cells), from_walk, from_hull))
    log("area covered: %.3f of %.3f" % (
        sum(c["area"] for c in cells), 4.0 * HX * HALF))
    return cells


# ---------------------------------------------------------------------------
# §F deliverables: masks + OBJ + reference image.
# ---------------------------------------------------------------------------

def write_png(path, width, height, rows):
    """Minimal RGB8 PNG writer (no PIL dependency inside UE's interpreter)."""
    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw.extend(row)

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    blob = b"\x89PNG\r\n\x1a\n"
    blob += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    blob += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    blob += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(blob)


def rasterise(cells):
    """Scanline fill. Every cell is convex, so a horizontal line crosses its
    outline at exactly two points and one min/max fill per scanline is exact."""
    W, H = MASK_W, MASK_H
    sx = (2.0 * HX) / W
    sy = (2.0 * HALF) / H
    owner = [-1] * (W * H)

    for idx, cell in enumerate(cells):
        poly = cell["polygon"]
        n = len(poly)
        ys = [p[1] for p in poly]
        y0 = max(0, int((HALF - max(ys)) / sy))
        y1 = min(H - 1, int((HALF - min(ys)) / sy) + 1)
        for py in range(y0, y1 + 1):
            wy = HALF - (py + 0.5) * sy
            xmin = None
            xmax = None
            for i in range(n):
                ax, ay = poly[i]
                bx, by = poly[(i + 1) % n]
                if ay == by:
                    continue
                if (ay <= wy < by) or (by <= wy < ay):
                    t = (wy - ay) / (by - ay)
                    x = ax + t * (bx - ax)
                    if xmin is None or x < xmin:
                        xmin = x
                    if xmax is None or x > xmax:
                        xmax = x
            if xmin is None or xmax is None:
                continue
            px0 = max(0, int((xmin + HX) / sx))
            px1 = min(W - 1, int((xmax + HX) / sx))
            base = py * W
            for px in range(px0, px1 + 1):
                owner[base + px] = idx
    return owner


def cell_colour(i):
    c = (i * 2654435761) & 0xFFFFFFFF
    r = 90 + (c & 0x7F)
    g = 90 + ((c >> 8) & 0x7F)
    b = 90 + ((c >> 16) & 0x7F)
    return r, g, b


def _u8(v):
    """Clamp to a byte. Several of the tones below are sums of two gains and can
    legally overshoot 255, which `bytes()` rejects outright."""
    n = int(v)
    if n < 0:
        return 0
    if n > 255:
        return 255
    return n


def seam_fields(owner):
    """(crack mask, chamfer distance to the seam) for an ownership raster."""
    W, H = MASK_W, MASK_H

    crack = bytearray(W * H)
    for py in range(H):
        base = py * W
        for px in range(W):
            i = base + px
            o = owner[i]
            if o < 0:
                crack[i] = 1
                continue
            if px > 0 and owner[i - 1] != o:
                crack[i] = 1
            elif px < W - 1 and owner[i + 1] != o:
                crack[i] = 1
            elif py > 0 and owner[i - W] != o:
                crack[i] = 1
            elif py < H - 1 and owner[i + W] != o:
                crack[i] = 1

    INF = 1 << 20
    dist = [0 if crack[i] else INF for i in range(W * H)]
    for py in range(H):
        base = py * W
        for px in range(W):
            i = base + px
            d = dist[i]
            if px > 0 and dist[i - 1] + 3 < d:
                d = dist[i - 1] + 3
            if py > 0:
                if dist[i - W] + 3 < d:
                    d = dist[i - W] + 3
                if px > 0 and dist[i - W - 1] + 4 < d:
                    d = dist[i - W - 1] + 4
                if px < W - 1 and dist[i - W + 1] + 4 < d:
                    d = dist[i - W + 1] + 4
            dist[i] = d
    for py in range(H - 1, -1, -1):
        base = py * W
        for px in range(W - 1, -1, -1):
            i = base + px
            d = dist[i]
            if px < W - 1 and dist[i + 1] + 3 < d:
                d = dist[i + 1] + 3
            if py < H - 1:
                if dist[i + W] + 3 < d:
                    d = dist[i + W] + 3
                if px < W - 1 and dist[i + W + 1] + 4 < d:
                    d = dist[i + W + 1] + 4
                if px > 0 and dist[i + W - 1] + 4 < d:
                    d = dist[i + W - 1] + 4
            dist[i] = d
    return crack, dist


def emit_reference(cells, owner, path, near=26.0):
    """Presentation image of a fracture set: flat tone per cell, bright seams."""
    W, H = MASK_W, MASK_H
    _crack, dist = seam_fields(owner)
    rows = []
    for py in range(H):
        base = py * W
        row = bytearray()
        for px in range(W):
            i = base + px
            o = owner[i]
            if o < 0:
                row += bytes((6, 6, 8))
                continue
            r, g, b = cell_colour(o)
            e = _u8(255.0 * max(0.0, 1.0 - min(1.0, dist[i] / near)) ** 1.5)
            shade = 0.30 + 0.55 * (r + g + b) / (3.0 * 217.0)
            row += bytes((
                _u8(255 * shade * 0.62 + e * 0.55),
                _u8(255 * shade * 0.72 + e * 0.62),
                _u8(255 * shade * 0.86 + e * 0.70),
            ))
        rows.append(row)
    write_png(path, W, H, rows)
    log("wrote %s" % os.path.basename(path))


def emit_masks(cells, owner):
    W, H = MASK_W, MASK_H
    crack, dist = seam_fields(owner)

    NEAR = 26.0  # ~ 1.3% of the mask width: a thin shard edge, not a border

    rows_frac = []
    rows_crack = []
    rows_edge = []
    rows_id = []
    rows_flow = []
    for py in range(H):
        base = py * W
        rf = bytearray()
        rc = bytearray()
        re_ = bytearray()
        ri = bytearray()
        rw = bytearray()
        for px in range(W):
            i = base + px
            o = owner[i]
            if o < 0:
                rf += bytes((6, 6, 8))
                rc += bytes((0, 0, 0))
                re_ += bytes((0, 0, 0))
                ri += bytes((0, 0, 0))
                rw += bytes((128, 128, 255))
                continue
            r, g, b = cell_colour(o)
            rf += bytes((r, g, b))
            rc += bytes((255, 255, 255)) if crack[i] else bytes((0, 0, 0))
            t = 1.0 - min(1.0, dist[i] / NEAR)
            e = _u8(255.0 * (t ** 1.5))
            re_ += bytes((e, e, e))
            ri += bytes((o & 0xFF, (o >> 8) & 0xFF, (o >> 16) & 0xFF))
            # outward direction from the cell centroid
            cell = cells[o]
            nx = (px + 0.5) * ((2.0 * HX) / W) - HX - cell["centroid"][0]
            ny = HALF - (py + 0.5) * ((2.0 * HALF) / H) - cell["centroid"][1]
            ln = math.hypot(nx, ny)
            if ln > 1e-6:
                nx /= ln
                ny /= ln
            rw += bytes((_u8(128 + 127 * nx), _u8(128 - 127 * ny), 255))
        rows_frac.append(rf)
        rows_crack.append(rc)
        rows_edge.append(re_)
        rows_id.append(ri)
        rows_flow.append(rw)

    write_png(os.path.join(EXPORTS, "mask_fracture.png"), W, H, rows_frac)
    write_png(os.path.join(EXPORTS, "mask_crack.png"), W, H, rows_crack)
    write_png(os.path.join(EXPORTS, "mask_edge.png"), W, H, rows_edge)
    write_png(os.path.join(EXPORTS, "mask_shardid.png"), W, H, rows_id)
    write_png(os.path.join(EXPORTS, "mask_flow.png"), W, H, rows_flow)
    log("wrote masks (%dx%d)" % (W, H))


def write_obj(path, positions, indices):
    lines = [
        "# SEKAI / RealityGlass_Lab - Reality Fracture tessellation",
        "# Generated by UE 5.8 Geometry Script (AppendVoronoiDiagram2D)",
        "# Units: screen half-heights, plane in XY, z = 0",
        "o RealityFracture",
    ]
    for p in positions:
        lines.append("v %.6f %.6f %.6f" % (p.x, p.y, getattr(p, "z", 0.0)))
    for t in range(len(indices) // 3):
        lines.append("f %d %d %d" % (
            indices[t * 3] + 1, indices[t * 3 + 1] + 1, indices[t * 3 + 2] + 1))
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    log("wrote %s (%d verts, %d faces)"
        % (os.path.basename(path), len(positions), len(indices) // 3))


# ---------------------------------------------------------------------------

def main():
    with open(LOG, "w", encoding="utf-8") as handle:
        handle.write("reality fracture build\n")

    # ---- pass 1: the fine fracture pattern (the crack network) -----------
    sites = build_sites()
    mesh = build_fracture_mesh(sites)
    if mesh.get_triangle_count() == 0:
        log("FAIL: voronoi produced no geometry")
        return

    cells = extract_cells(mesh)
    if not cells:
        log("FAIL: no cells extracted")
        return

    payload = {
        "half": HALF,
        "aspect": ASPECT,
        "cut_angle_deg": -30.0,
        "cut_normal": [CUT_N[0], CUT_N[1]],
        "cut_tangent": [CUT_T[0], CUT_T[1]],
        "seed": SEED,
        "cell_count": len(cells),
        "cells": cells,
    }
    with open(os.path.join(EXPORTS, "fracture.json"), "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=1)
    log("wrote fracture.json")

    positions = _read_list(
        _payload(mesh.get_all_vertex_positions(True)), "vector")
    indices = _flatten_triangles(_read_list(
        _payload(mesh.get_all_triangle_indices(True)), "triangle"))
    if positions and indices:
        write_obj(os.path.join(EXPORTS, "fracture.obj"), positions, indices)

    owner = rasterise(cells)
    emit_masks(cells, owner)
    emit_reference(cells, owner,
                   os.path.join(EXPORTS, "lab_reference_fracture.png"))

    # ---- pass 2: the MAIN shards (the pieces that actually come apart) ----
    log("--- coarse pass ---")
    coarse_sites = build_coarse_sites(14)
    coarse_mesh = build_fracture_mesh(coarse_sites)
    shards = extract_cells(coarse_mesh) if coarse_mesh.get_triangle_count() else []
    if not shards:
        log("FAIL: no shards extracted")
        return
    shard_payload = {
        "half": HALF,
        "aspect": ASPECT,
        "cut_angle_deg": -30.0,
        "cut_normal": [CUT_N[0], CUT_N[1]],
        "cut_tangent": [CUT_T[0], CUT_T[1]],
        "seed": SEED + 7717,
        "cell_count": len(shards),
        "cells": shards,
    }
    with open(os.path.join(EXPORTS, "shards.json"), "w", encoding="utf-8") as handle:
        json.dump(shard_payload, handle, indent=1)
    log("wrote shards.json")

    c_positions = _read_list(
        _payload(coarse_mesh.get_all_vertex_positions(True)), "vector")
    c_indices = _flatten_triangles(_read_list(
        _payload(coarse_mesh.get_all_triangle_indices(True)), "triangle"))
    if c_positions and c_indices:
        write_obj(os.path.join(EXPORTS, "shards.obj"), c_positions, c_indices)

    # A review image of the MAIN shards on their own. Worth having separately
    # from the fine pattern: the fine one is what the shader draws, the coarse
    # one is what actually comes apart, and they have to be judged differently
    # (the coarse set must not show equal-sized pieces).
    shard_owner = rasterise(shards)
    emit_reference(shards, shard_owner,
                   os.path.join(EXPORTS, "lab_reference_shards.png"))

    log("DONE cells=%d shards=%d" % (len(cells), len(shards)))
    unreal.log("REALITY_FRACTURE_DONE cells=%d shards=%d"
               % (len(cells), len(shards)))


main()
