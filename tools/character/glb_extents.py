# -*- coding: utf-8 -*-
"""
SEKAI / CHARACTER LINE — GLB world-extent measurer (no engine, no Blender)

Answers one question precisely: "how tall is this GLB, really?"
Reads the GLB container directly (JSON chunk + accessor min/max), composes node
transforms, and for SKINNED meshes uses the skeleton root's world matrix per the
glTF spec (a skinned mesh ignores its own node transform).

This exists because Godot's `MeshInstance3D.get_aabb()` reports the *bind-space*
mesh AABB and does NOT include the skeleton node's scale, so it can under-report
height by several percent. Never quote a character height off that number.

    python tools/character/glb_extents.py <a.glb> [b.glb ...]
    python tools/character/glb_extents.py --json out.json <a.glb>

Prints per file:
    name  height  (x/y/z extent)  skin=<yes/no>  scale_on_skeleton=<matrix diag>
"""

import json
import os
import struct
import sys

# --- minimal 4x4 matrix math (row-major lists of 16, glTF order) -------------


def m_identity():
    return [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]


def m_mul(a, b):
    """a @ b, column-vector convention (glTF): result = a then b applied as a*b*x"""
    out = [0.0] * 16
    for c in range(4):
        for r in range(4):
            s = 0.0
            for k in range(4):
                s += a[k * 4 + r] * b[c * 4 + k]
            out[c * 4 + r] = s
    return out


def m_from_trs(t, r, s):
    x, y, z, w = r
    x2, y2, z2 = x + x, y + y, z + z
    xx, xy, xz = x * x2, x * y2, x * z2
    yy, yz, zz = y * y2, y * z2, z * z2
    wx, wy, wz = w * x2, w * y2, w * z2
    m = [
        (1 - (yy + zz)) * s[0], (xy + wz) * s[0], (xz - wy) * s[0], 0.0,
        (xy - wz) * s[1], (1 - (xx + zz)) * s[1], (yz + wx) * s[1], 0.0,
        (xz + wy) * s[2], (yz - wx) * s[2], (1 - (xx + yy)) * s[2], 0.0,
        t[0], t[1], t[2], 1.0,
    ]
    return m


def m_apply(m, p):
    x, y, z = p
    return (
        m[0] * x + m[4] * y + m[8] * z + m[12],
        m[1] * x + m[5] * y + m[9] * z + m[13],
        m[2] * x + m[6] * y + m[10] * z + m[14],
    )


def m_scale_of(m):
    """length of the three basis columns -> effective per-axis scale"""
    def col(c):
        return (m[c * 4], m[c * 4 + 1], m[c * 4 + 2])
    return tuple(round(sum(v * v for v in col(c)) ** 0.5, 5) for c in range(3))


# --- GLB container ----------------------------------------------------------


def read_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, _length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError("%s is not a GLB (magic=%r)" % (path, magic))
    off = 12
    gltf = None
    while off < len(data):
        clen, ctype = struct.unpack_from("<I4s", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == b"JSON":
            gltf = json.loads(chunk.decode("utf-8"))
        off += 8 + clen + ((4 - clen % 4) % 4 if clen % 4 else 0)
    if gltf is None:
        raise ValueError("%s has no JSON chunk" % path)
    return gltf


def node_local(n):
    if "matrix" in n:
        return list(n["matrix"])
    t = n.get("translation", [0.0, 0.0, 0.0])
    r = n.get("rotation", [0.0, 0.0, 0.0, 1.0])
    s = n.get("scale", [1.0, 1.0, 1.0])
    return m_from_trs(t, r, s)


def world_matrices(gltf):
    """node index -> world matrix (scene roots as given)"""
    nodes = gltf.get("nodes", [])
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    cache = {}

    def world(i):
        if i in cache:
            return cache[i]
        local = node_local(nodes[i])
        p = parent.get(i)
        cache[i] = m_mul(world(p), local) if p is not None else local
        return cache[i]

    return world


def measure(path):
    gltf = read_glb(path)
    nodes = gltf.get("nodes", [])
    meshes = gltf.get("meshes", [])
    accessors = gltf.get("accessors", [])
    skins = gltf.get("skins", [])
    world = world_matrices(gltf)

    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    skinned = False
    skel_scale = None

    for i, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        mat = world(i)
        if "skin" in n:
            skinned = True
            sk = skins[n["skin"]]
            root = sk.get("skeleton")
            if root is None and sk.get("joints"):
                # walk up from the first joint to the topmost node that is still
                # below the mesh's own parent chain
                root = sk["joints"][0]
            if root is not None:
                mat = world(root)
            skel_scale = m_scale_of(mat)
        for prim in meshes[n["mesh"]].get("primitives", []):
            pos = prim.get("attributes", {}).get("POSITION")
            if pos is None:
                continue
            acc = accessors[pos]
            amin, amax = acc.get("min"), acc.get("max")
            if not amin or not amax:
                continue
            for bx in (amin[0], amax[0]):
                for by in (amin[1], amax[1]):
                    for bz in (amin[2], amax[2]):
                        p = m_apply(mat, (bx, by, bz))
                        for k in range(3):
                            lo[k] = min(lo[k], p[k])
                            hi[k] = max(hi[k], p[k])

    if hi[0] == float("-inf"):
        return None
    ext = [round(hi[k] - lo[k], 4) for k in range(3)]
    return {
        "name": os.path.basename(path),
        "skinned": skinned,
        "skeleton_scale": skel_scale,
        "min": [round(v, 4) for v in lo],
        "max": [round(v, 4) for v in hi],
        "extent": ext,
        "height_y": ext[1],
    }


def main():
    argv = sys.argv[1:]
    if not argv:
        raise SystemExit(__doc__)
    out_json = None
    if argv[0] == "--json":
        out_json = argv[1]
        argv = argv[2:]
    rows = []
    for p in argv:
        try:
            r = measure(p)
        except Exception as e:  # noqa: BLE001
            print("ERR  %-40s %s" % (os.path.basename(p), e))
            continue
        if r is None:
            print("ERR  %-40s no POSITION accessors" % os.path.basename(p))
            continue
        rows.append(r)
        print("%-34s H=%.3f  ext=%s  skin=%s  skel_scale=%s"
              % (r["name"], r["height_y"], r["extent"],
                 "yes" if r["skinned"] else "no", r["skeleton_scale"]))
    if out_json:
        with open(out_json, "w") as f:
            json.dump(rows, f, indent=2)
        print("wrote " + out_json)


if __name__ == "__main__":
    main()
