"""Producer QA pass. Runs inside Blender via the MCP socket.

Not modelling code. It only reports on what already exists so the Producer can
judge silhouette, proportion, scale and material slot count before export.

    python blender_mcp_client.py exec --file assets/chat2blender/review_scene.py
"""

import bpy  # noqa: F401  (provided by the Blender runtime)

REPORT = []


def tri_count(obj):
    if obj.type != 'MESH' or obj.data is None:
        return 0
    try:
        mesh = obj.data
        total = 0
        for poly in mesh.polygons:
            total += max(0, len(poly.vertices) - 2)
        return total
    except Exception:
        return 0


REPORT.append("BLENDER " + bpy.app.version_string)
REPORT.append("FILE " + (bpy.data.filepath or "(unsaved)"))
REPORT.append("")

total_tris = 0
for obj in bpy.data.objects:
    dims = getattr(obj, 'dimensions', None)
    dim = "%.3f x %.3f x %.3f" % (dims.x, dims.y, dims.z) if dims else "-"
    tris = tri_count(obj)
    total_tris += tris
    mats = 0
    if obj.type == 'MESH' and obj.data is not None:
        mats = len(obj.data.materials)
    loc = obj.location
    rot = obj.rotation_euler
    scl = obj.scale
    unapplied = (
        abs(scl.x - 1.0) > 0.001
        or abs(scl.y - 1.0) > 0.001
        or abs(scl.z - 1.0) > 0.001
    )
    REPORT.append(
        "%-28s %-6s tris=%-7d mats=%d  dim=%s  loc=(%.3f, %.3f, %.3f)  rot=(%.2f, %.2f, %.2f)  scale=%s%s"
        % (
            obj.name,
            obj.type,
            tris,
            mats,
            dim,
            loc.x, loc.y, loc.z,
            rot.x, rot.y, rot.z,
            "%.3f,%.3f,%.3f" % (scl.x, scl.y, scl.z),
            "  <== UNAPPLIED SCALE" if unapplied else "",
        )
    )

REPORT.append("")
REPORT.append("TOTAL TRIS %d" % total_tris)
REPORT.append("COLLECTIONS: " + ", ".join(c.name for c in bpy.data.collections))
REPORT.append("MATERIALS: " + ", ".join(m.name for m in bpy.data.materials))

print("\n".join(REPORT))
