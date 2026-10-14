#!/usr/bin/env python3
"""Probe one or more animation clips inside a GLB, per node, per path.

WHY THIS EXISTS
---------------
A retarget bug showed up as a *pose* problem ("sitting looks wrong") but the
cause was a *data* problem: the hip drop of `Sitting_Idle` never made it into
the baked clip, so the character sat on an invisible chair.  You cannot see
that by looking at the character -- you have to read the animation channel.
This tool answers, without launching an engine:

    does the Hips node actually translate in this clip, and by how much?

USAGE
-----
    python tools/character/glb_anim_probe.py <glb> --clips Idle,Sitting_Idle
    python tools/character/glb_anim_probe.py <glb> --clips all --path translation
    python tools/character/glb_anim_probe.py <glb> --clips all --nodes Hips,Root
    python tools/character/glb_anim_probe.py <glb> --channels          # inventory

NOTE  glTF stores a node's local TRS.  For a bone chain that means the value is
      *relative to the parent bone*, not the world.  That is still exactly what
      we need here: if the parent is static, a Hips drop shows up verbatim.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys

COMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


# --------------------------------------------------------------------------- #
# GLB container
# --------------------------------------------------------------------------- #
def read_glb(path: str):
    """Return (gltf_json, bin_chunk).  Raises on anything unexpected."""
    with open(path, "rb") as fh:
        data = fh.read()
    magic, version, _ = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError("%s is not a GLB (magic=%r)" % (path, magic))
    if version != 2:
        raise ValueError("%s is glTF %d, expected 2" % (path, version))

    gltf = None
    blob = b""
    off = 12
    while off + 8 <= len(data):
        clen, ctype = struct.unpack_from("<I4s", data, off)
        body = data[off + 8: off + 8 + clen]
        if ctype == b"JSON":
            gltf = json.loads(body.decode("utf-8"))
        elif ctype.rstrip(b"\x00") == b"BIN":
            blob = body
        off += 8 + clen + ((4 - clen % 4) % 4 if clen % 4 else 0)
    if gltf is None:
        raise ValueError("%s has no JSON chunk" % path)
    return gltf, blob


def accessor_floats(gltf: dict, blob: bytes, idx: int):
    """Decode a (non-sparse, non-interleaved) float accessor into a list of tuples."""
    acc = gltf["accessors"][idx]
    n = COMP[acc["type"]]
    fmt = "<" + "f" * n
    size = 4 * n
    bv = gltf["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or size
    out = []
    for i in range(acc["count"]):
        out.append(struct.unpack_from(fmt, blob, base + i * stride))
    return out


# --------------------------------------------------------------------------- #
# reporting
# --------------------------------------------------------------------------- #
def stat(vals):
    """(min, max, span, first, last) over a 1-D sequence."""
    return min(vals), max(vals), max(vals) - min(vals), vals[0], vals[-1]


def fmt_stat(s) -> str:
    return "min %+.4f  max %+.4f  span %.4f  first %+.4f -> last %+.4f" % s


def probe(path: str, want_clips, want_path, want_nodes) -> int:
    gltf, blob = read_glb(path)
    node_names = [n.get("name", "<unnamed%d>" % i)
                  for i, n in enumerate(gltf.get("nodes", []))]
    anims = gltf.get("animations", [])
    print("== %s" % path)
    print("   nodes=%d  animations=%d" % (len(node_names), len(anims)))

    if not anims:
        print("   !! no animations")
        return 1

    names = [a.get("name", "<anim%d>" % i) for i, a in enumerate(anims)]
    if want_clips and want_clips != ["all"]:
        missing = [c for c in want_clips if c not in names]
        for m in missing:
            print("   !! clip '%s' not present" % m)
        anims = [a for a, n in zip(anims, names) if n in want_clips]
        names = [n for n in names if n in want_clips]

    for anim, aname in zip(anims, names):
        channels = anim.get("channels", [])
        samplers = anim.get("samplers", [])
        print("\n   -- clip '%s'  channels=%d" % (aname, len(channels)))

        rows = []
        for ch in channels:
            tgt = ch["target"]
            node = node_names[tgt["node"]] if "node" in tgt else "<none>"
            p = tgt.get("path", "?")
            if want_path and p != want_path:
                continue
            if want_nodes and node not in want_nodes:
                continue
            smp = samplers[ch["sampler"]]
            vals = accessor_floats(gltf, blob, smp["input"])
            frames = [v[0] for v in vals]
            outv = accessor_floats(gltf, blob, smp["output"])
            rows.append((node, p, frames, outv, smp))

        if not rows:
            print("      (nothing matched the filter)")
            continue

        for node, p, frames, outv, smp in rows:
            n = len(outv[0]) if outv else 0
            interp = smp.get("interpolation", "LINEAR")
            print("      %-22s %-12s keys=%-4d comps=%d  t[%.3f..%.3f] %s"
                  % (node, p, len(frames), n, frames[0], frames[-1], interp))
            if p == "translation":
                for axis, lbl in enumerate("XYZ"[:n]):
                    s = stat([v[axis] for v in outv])
                    tag = "  <-- moves" if s[2] > 1e-4 else ""
                    print("        %s  %s%s" % (lbl, fmt_stat(s), tag))
            elif p == "scale":
                for axis, lbl in enumerate("XYZ"[:n]):
                    s = stat([v[axis] for v in outv])
                    if s[2] > 1e-5:
                        print("        %s  %s" % (lbl, fmt_stat(s)))
    return 0


def inventory(path: str) -> int:
    """Which clips move the root-most bones, and by how much (translation only)."""
    gltf, blob = read_glb(path)
    node_names = [n.get("name", "<unnamed%d>" % i)
                  for i, n in enumerate(gltf.get("nodes", []))]
    print("== %s" % path)
    print("   %-28s %-22s %s" % ("clip", "node", "translation span (X,Y,Z)"))
    for anim in gltf.get("animations", []):
        aname = anim.get("name", "?")
        for ch in anim.get("channels", []):
            if ch["target"].get("path") != "translation":
                continue
            node = node_names[ch["target"]["node"]]
            outv = accessor_floats(gltf, blob, anim["samplers"][ch["sampler"]]["output"])
            spans = [max(v[i] for v in outv) - min(v[i] for v in outv)
                     for i in range(len(outv[0]))]
            if max(spans) < 1e-3:
                continue
            print("   %-28s %-22s %s" % (aname, node,
                                         "  ".join("%.4f" % s for s in spans)))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("glb")
    ap.add_argument("--clips", default="",
                    help="comma separated clip names, or 'all' (default: all)")
    ap.add_argument("--path", default="", choices=["", "translation", "rotation", "scale"])
    ap.add_argument("--nodes", default="", help="comma separated node names filter")
    ap.add_argument("--channels", action="store_true",
                    help="inventory: which clips move which nodes at all")
    a = ap.parse_args()

    if a.channels:
        return inventory(a.glb)
    clips = [c.strip() for c in a.clips.split(",") if c.strip()] or ["all"]
    nodes = {n.strip() for n in a.nodes.split(",") if n.strip()}
    return probe(a.glb, clips, a.path, nodes)


if __name__ == "__main__":
    sys.exit(main())
