"""LIA WEIGHT BY REGION -- assign arm influence per connected cloth region.

The problem
-----------
`lia_weight_cleanup.py` strips arm influence vertex by vertex. Any cloth panel
that is partly inside and partly outside the arm volume then gets cut in half:
the near half follows the arm, the far half stays with the torso, and raising
the arm tears the panel into a flat wing.

Cloth must be decided as a WHOLE PIECE, not per vertex.

What this does
--------------
1. Split the mesh into connected regions by cutting along CONCAVE creases
   (valley edges whose dihedral angle exceeds THRESH). Cloth panels are
   separated from the body by exactly those creases.
2. Classify each region as ARM or BODY:
     * contains a vertex essentially ON the arm chain (d_arm < 0.025)  -> ARM
     * majority of its vertices within the arm volume (d_arm < R_ARM) -> ARM
     * otherwise                                                      -> BODY
   Regions larger than MAX_REGION fall back to the per-vertex rule, because a
   merged body+arm blob must not be decided as a unit.
3. Strip arm influence from BODY regions only, then clamp to <= 4 influences,
   drop tiny weights and renormalise.

Run:
  "/g/blender.exe" -b --factory-startup --python tools/character/lia_weight_region.py \
      -- --blend <rigged.blend> --out-blend <out.blend> --out-json <out.json>
"""

import bpy
import sys
import os
import json
import math
from mathutils import Vector

# ---------------------------------------------------------------- args


def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    d = {}
    i = 0
    while i < len(argv):
        t = argv[i]
        if t.startswith("--"):
            k = t[2:]
            if i + 1 < len(argv) and not argv[i + 1].startswith("--"):
                d[k] = argv[i + 1]
                i += 2
            else:
                d[k] = True
                i += 1
        else:
            i += 1
    return d


ARGS = parse_args()
SRC = os.path.abspath(ARGS["blend"])
OUT_BLEND = os.path.abspath(ARGS["out-blend"])
OUT_JSON = os.path.abspath(ARGS["out-json"]) if ARGS.get("out-json") else ""
THRESH = float(ARGS.get("crease-deg", 30.0))
R_ARM = float(ARGS.get("r-arm", 0.070))
ON_ARM = float(ARGS.get("on-arm", 0.025))
MODE = ARGS.get("mode", "geodesic")
MAX_REGION = int(ARGS.get("max-region", 5000))
MAX_INF = int(ARGS.get("max-influences", 4))
MIN_W = float(ARGS.get("min-weight", 0.006))
SMOOTH = int(ARGS.get("smooth", 0))
SMOOTH_F = float(ARGS.get("smooth-factor", 0.5))


def log(msg):
    print("[LIA-WREGION] %s" % msg, flush=True)


# ---------------------------------------------------------------- load

bpy.ops.wm.open_mainfile(filepath=SRC)
rig = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
mesh = next((o for o in bpy.data.objects if o.type == "MESH"), None)
if rig is None or mesh is None:
    raise RuntimeError("need one armature + one mesh")
me = mesh.data
mw = mesh.matrix_world

SEG = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones}
ARM_PREFIX = ("clavicle_", "upperarm_", "lowerarm_", "hand_")
ARM_NAMES = [n for n in SEG if n.startswith(ARM_PREFIX)]
BODY_NAMES = [n for n in SEG if n not in ARM_NAMES and n != "root"]

log("rig=%s mesh=%s verts=%d polys=%d" % (rig.name, mesh.name, len(me.vertices), len(me.polygons)))


def seg_dist(p, seg):
    a, b = seg
    ab = b - a
    l2 = ab.length_squared
    if l2 < 1e-12:
        return (p - a).length
    t = (p - a).dot(ab) / l2
    t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
    return (p - (a + ab * t)).length


def nearest(p, names):
    best, bd = None, 1e9
    for n in names:
        d = seg_dist(p, SEG[n])
        if d < bd:
            bd, best = d, n
    return best, bd


arm_segs = [SEG[n] for n in ARM_NAMES]
body_segs = [SEG[n] for n in BODY_NAMES]
REST = [mw @ v.co for v in me.vertices]
N = len(REST)
D_ARM = [min(seg_dist(p, s) for s in arm_segs) for p in REST]
D_BODY = [min(seg_dist(p, s) for s in body_segs) for p in REST]

# ---------------------------------------------------------------- region split

edge_faces = {}
for p in me.polygons:
    for ek in p.edge_keys:
        edge_faces.setdefault(ek, []).append(p.index)

hard = set()
thr = math.radians(THRESH)
for ek, fs in edge_faces.items():
    if len(fs) != 2:
        continue
    f1, f2 = me.polygons[fs[0]], me.polygons[fs[1]]
    n1, n2 = f1.normal, f2.normal
    if n1.length < 1e-9 or n2.length < 1e-9:
        continue
    ang = n1.angle(n2, 0.0)
    if ang < thr:
        continue
    # concave (valley) if the neighbouring face centre lies behind this face
    if (f2.center - f1.center).dot(n1) < 0.0:
        hard.add(ek)

log("crease edges (>%.0f deg, concave): %d / %d" % (THRESH, len(hard), len(edge_faces)))

parent = list(range(N))


def find(x):
    while parent[x] != x:
        parent[x] = parent[parent[x]]
        x = parent[x]
    return x


def union(a, b):
    ra, rb = find(a), find(b)
    if ra != rb:
        parent[ra] = rb


for e in me.edges:
    ek = (e.vertices[0], e.vertices[1]) if e.vertices[0] < e.vertices[1] \
        else (e.vertices[1], e.vertices[0])
    if ek not in hard:
        union(e.vertices[0], e.vertices[1])

regions = {}
for i in range(N):
    regions.setdefault(find(i), []).append(i)

log("regions: %d   largest: %s" % (
    len(regions), sorted((len(v) for v in regions.values()), reverse=True)[:8]))

# ---------------------------------------------------------------- classify

strip_flag = [False] * N
summary = []
for root, vs in regions.items():
    size = len(vs)
    on_arm = sum(1 for i in vs if D_ARM[i] < ON_ARM)
    in_arm = sum(1 for i in vs if D_ARM[i] < R_ARM)
    frac = in_arm / float(size)
    if size > MAX_REGION:
        cls = "PER-VERTEX"           # too big to decide as a unit
    elif on_arm > 0 or frac > 0.5:
        cls = "ARM"
    else:
        cls = "BODY"

    if cls == "BODY":
        for i in vs:
            strip_flag[i] = True
    elif cls == "PER-VERTEX":
        for i in vs:
            if D_ARM[i] > R_ARM or D_BODY[i] + 0.045 < D_ARM[i]:
                strip_flag[i] = True

    summary.append({"size": size, "on_arm": on_arm,
                    "arm_frac": round(frac, 3), "class": cls})

summary.sort(key=lambda r: -r["size"])
log("region classes (top 14):")
for r in summary[:14]:
    log("   size=%-6d on_arm=%-5d arm_frac=%-6.3f -> %s"
        % (r["size"], r["on_arm"], r["arm_frac"], r["class"]))

cls_count = {}
for r in summary:
    cls_count[r["class"]] = cls_count.get(r["class"], 0) + 1
log("class histogram: %s" % json.dumps(cls_count))

# ---------------------------------------------------------------- geodesic override
# Crease-based splitting collapsed: 19958 of 20456 verts land in ONE region, i.e.
# QuadriFlow left no usable crease between the cloth panels and the body.  So the
# whole panel must still be decided, and the only signal that separates "cloth
# hanging beside the arm" from "the arm" is the distance measured ALONG the
# surface.  The arm seed set is deliberately limited to hand..elbow: seeding the
# whole forearm puts seeds right next to the skirt panel and the Voronoi split
# goes the wrong way.

if MODE == "geodesic":
    import heapq

    def dijkstra(adj, seeds):
        INF = float("inf")
        dist = [INF] * N
        h = [(0.0, s) for s in seeds]
        for s in seeds:
            dist[s] = 0.0
        heapq.heapify(h)
        while h:
            d, u = heapq.heappop(h)
            if d > dist[u]:
                continue
            for v, w in adj[u]:
                nd = d + w
                if nd < dist[v]:
                    dist[v] = nd
                    heapq.heappush(h, (nd, v))
        return dist

    adj = [[] for _ in range(N)]
    for e in me.edges:
        a, b = e.vertices
        w = (REST[a] - REST[b]).length
        adj[a].append((b, w))
        adj[b].append((a, w))

    body_seeds, arm_seeds = [], []
    for i in range(N):
        p = REST[i]
        if abs(p.x) < 0.05 and 0.42 < p.z < 1.52:
            body_seeds.append(i)
        if D_ARM[i] < 0.035 and 0.60 < p.z < 1.00:
            arm_seeds.append(i)
    log("geodesic seeds: body=%d arm=%d" % (len(body_seeds), len(arm_seeds)))
    if not body_seeds or not arm_seeds:
        raise RuntimeError("seed sets empty - refusing to guess")

    dg_body = dijkstra(adj, body_seeds)
    dg_arm = dijkstra(adj, arm_seeds)

    strip_flag = [False] * N
    for i in range(N):
        if dg_body[i] + 0.0 < dg_arm[i]:
            strip_flag[i] = True
        elif abs(REST[i].y) > 0.11:
            strip_flag[i] = True
    log("geodesic strip: %d / %d (%.1f%%)" %
        (sum(strip_flag), N, 100.0 * sum(strip_flag) / N))

log("verts stripped of arm influence: %d / %d (%.1f%%)"
    % (sum(strip_flag), N, 100.0 * sum(strip_flag) / N))

# ---------------------------------------------------------------- read / process / write

def read_weights():
    names = [vg.name for vg in mesh.vertex_groups]
    data = [dict() for _ in range(N)]
    for v in me.vertices:
        d = data[v.index]
        for g in v.groups:
            d[names[g.group]] = g.weight
    return names, data


def process(names, data, strip):
    st = {"stripped": 0, "dropped_small": 0, "clamped": 0, "rescaled": 0, "orphans": 0}
    for i in range(N):
        d = data[i]
        if strip[i]:
            before = len(d)
            for nm in ARM_NAMES:
                d.pop(nm, None)
            if len(d) != before:
                st["stripped"] += 1
        small = [nm for nm, w in d.items() if w < MIN_W]
        for nm in small:
            del d[nm]
        if small:
            st["dropped_small"] += 1
        if not d:
            pool = ARM_NAMES if (D_ARM[i] < D_BODY[i] and not strip[i]) else BODY_NAMES
            d[nearest(REST[i], pool)[0]] = 1.0
            st["orphans"] += 1
            continue
        if len(d) > MAX_INF:
            keep = sorted(d.items(), key=lambda t: -t[1])[:MAX_INF]
            d.clear()
            d.update(keep)
            st["clamped"] += 1
        total = sum(d.values())
        if total > 0 and abs(total - 1.0) > 1e-5:
            for nm in d:
                d[nm] /= total
            st["rescaled"] += 1
    return st


def write_weights(names, data):
    mesh.vertex_groups.clear()
    vg = {nm: mesh.vertex_groups.new(name=nm) for nm in names}
    for i in range(N):
        for nm, w in data[i].items():
            vg[nm].add([i], w, "REPLACE")


names, data = read_weights()
st1 = process(names, data, strip_flag)
write_weights(names, data)
log("pass 1: %s" % json.dumps(st1))

st2 = {}
if SMOOTH > 0:
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
    try:
        bpy.ops.object.vertex_group_smooth(
            group_select_mode="BONE_DEFORM", factor=SMOOTH_F, repeat=SMOOTH)
        log("vertex_group_smooth repeat=%d factor=%.2f" % (SMOOTH, SMOOTH_F))
    except Exception as exc:
        log("smooth failed: %s" % exc)
    bpy.ops.object.mode_set(mode="OBJECT")
    names, data = read_weights()
    st2 = process(names, data, strip_flag)
    write_weights(names, data)
    log("pass 2: %s" % json.dumps(st2))

# ---------------------------------------------------------------- verify

names, data = read_weights()
counts = sorted(len(d) for d in data)
bad = sum(1 for i in range(N)
          if strip_flag[i] and any(nm in data[i] and data[i][nm] > 0.005 for nm in ARM_NAMES))
report = {
    "source": SRC, "output_blend": OUT_BLEND,
    "crease_deg": THRESH, "r_arm": R_ARM, "on_arm": ON_ARM,
    "regions": len(regions), "class_histogram": cls_count,
    "stripped_verts": sum(strip_flag),
    "pass1": st1, "pass2": st2,
    "influences_median": counts[len(counts) // 2],
    "influences_p95": counts[int(len(counts) * 0.95)],
    "influences_max": counts[-1],
    "over_max": sum(1 for c in counts if c > MAX_INF),
    "unassigned_verts": sum(1 for c in counts if c == 0),
    "forbidden_verts_still_armed": bad,
}
log("VERIFY: %s" % json.dumps(report))
assert report["unassigned_verts"] == 0
assert report["over_max"] == 0
assert bad == 0

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
if OUT_JSON:
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump({"report": report, "regions": summary}, f, indent=2, ensure_ascii=False)
log("saved %s" % OUT_BLEND)
log("WREGION_DONE")
