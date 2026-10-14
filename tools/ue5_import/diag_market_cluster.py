"""Diagnose the z=5.5..13 step cluster reported by probe_mistvale_playable.gd.

Reads only the handoff JSON files. No Blender, no Godot, no writing into the
level. The question it answers: is that window a decorative prop cluster the
player walks around, or a real discontinuity in the route surface?

Usage:
    python tools/ue5_import/diag_market_cluster.py
"""
from __future__ import annotations

import json
import os
import sys

HANDOFF = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "..", "ue5_lab", "Mistvale_Rebuild", "_handoff",
)
HANDOFF = os.path.normpath(HANDOFF)

# The spine is marched at x = the probe's SPAWN_XY.x
SPINE_X = 6.0
WIN_LO, WIN_HI = -4.0, 24.0


def load(name):
    with open(os.path.join(HANDOFF, name), encoding="utf-8") as fh:
        return json.load(fh)


def main() -> int:
    route = load("godot_route_audit.json")
    spine = route["spine"]
    steps = route["steps"]

    print("=" * 78)
    print("GOLDEN ROUTE SPINE  (x = %.1f m, ray march, 0.5 m step)" % SPINE_X)
    print("=" * 78)
    print("z range %.1f -> %.1f   samples=%d   holes=%d   steps>0.35=%d"
          % (spine[0]["z"], spine[-1]["z"], len(spine),
             route["holes"], route["step_count"]))
    print()

    prev = None
    prev_z = None
    for s in spine:
        z, y = s["z"], s["y"]
        if not (WIN_LO <= z <= WIN_HI):
            prev = y
            prev_z = z
            continue
        if prev is None:
            print("  z=%8.2f  y=%8.3f  (window start)" % (z, y))
        else:
            dy = y - prev
            dz = z - prev_z
            flag = "  <== STEP" if abs(dy) > 0.35 else ""
            print("  z=%8.2f  y=%8.3f   dy=%+7.3f over dz=%+.2f   grade=%+6.1f%%%s"
                  % (z, y, dy, dz, 100.0 * dy / dz if abs(dz) > 1e-9 else 0.0, flag))
        prev, prev_z = y, z

    print()
    print("=" * 78)
    print("ALL STEPS")
    print("=" * 78)
    for s in steps:
        print("  z=%8.2f  delta=%+7.3f  y=%8.3f" % (s["z"], s["delta"], s["y"]))

    # ---- which exported mesh actors overlap the suspicious window? ----
    print()
    print("=" * 78)
    print("MESH ACTORS OVERLAPPING THE WINDOW")
    print("  (from glb_expected.json: Godot-space AABBs written at export time)")
    print("=" * 78)
    exp = load("glb_expected.json")
    nodes = exp["nodes"]
    print("  total nodes in manifest: %d" % len(nodes))

    rows = []
    skipped_no_bbox = 0
    for n in nodes:
        # Keys are godot_min / godot_max (flat lists). Getting this name wrong
        # makes every node silently skip and the report then claims "clear",
        # which is a lie produced by a typo -- so count the skips and print them.
        if "godot_min" not in n or "godot_max" not in n:
            skipped_no_bbox += 1
            continue
        lo, hi = n["godot_min"], n["godot_max"]
        # march column is at x=SPINE_X with zero width, so test containment
        if not (lo[0] - 1e-6 <= SPINE_X <= hi[0] + 1e-6):
            continue
        if hi[2] < WIN_LO or lo[2] > WIN_HI:
            continue
        rows.append((lo[2], n["name"], lo, hi))

    rows.sort()
    for _, name, lo, hi in rows:
        print("  z[%8.2f,%8.2f]  y[%8.2f,%8.2f]  x[%8.2f,%8.2f]  %s"
              % (lo[2], hi[2], lo[1], hi[1], lo[0], hi[0], name))

    if skipped_no_bbox:
        print("  !! %d nodes had no bbox and were skipped -- treat the list below"
              " as incomplete" % skipped_no_bbox)

    if not rows:
        print("  (none -- the march column at x=%.1f is clear of every actor" % SPINE_X)
        print("   bounding box in this window, so the step comes from a surface")
        print("   whose AABB does not straddle x=%.1f)" % SPINE_X)
    else:
        # Any single actor tall enough to be the hump will show a y extent that
        # brackets the observed peak (16.64 m) and a z extent inside the window.
        print("  --- candidates whose y extent brackets the observed peak ---")
        for _, name, lo, hi in rows:
            if lo[1] <= 16.64 <= hi[1]:
                print("    %-46s z[%8.2f,%8.2f] y[%8.2f,%8.2f]"
                      % (name, lo[2], hi[2], lo[1], hi[1]))

    return 0


if __name__ == "__main__":
    sys.exit(main())
