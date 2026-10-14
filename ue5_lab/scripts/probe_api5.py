from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
# Sekai / RealityGlass_Lab — probe #5: calling conventions for the fracture path.
#
# DynamicMesh exposes the Geometry Script operations directly, so the fracture
# can be built with UE's own geometry pipeline rather than a hand-rolled solver.
# This probe settles the signatures AND runs a tiny end-to-end so we know the
# calling convention before writing the real generator.

import unreal

OUT = str(_SEKAI_ROOT / 'ue5_lab/exports/api_probe5.txt')


def main():
    lines = []

    for name in ("append_rectangle_xy", "append_voronoi_diagram2d",
                 "apply_mesh_plane_cut", "apply_mesh_plane_slice",
                 "apply_mesh_self_union", "apply_mesh_boolean",
                 "compute_mesh_convex_hull", "append_simple_extrude_polygon",
                 "get_vertices", "get_triangle_count", "get_vertex_count"):
        fn = getattr(unreal.DynamicMesh, name, None)
        lines.append("--- %s ---" % name)
        lines.append(getattr(fn, "__doc__", "<no doc>") or "<empty doc>")
        lines.append("")

    # --- end to end -------------------------------------------------------
    lines.append("=== END TO END ===")
    try:
        mesh = unreal.DynamicMesh()
        lines.append("constructed: %s" % type(mesh))
        try:
            res = mesh.append_rectangle_xy(unreal.Vector2(0.0, 0.0), 2.0, 1.5, 8, 8)
            lines.append("append_rectangle_xy -> %r" % (res,))
        except Exception as exc:  # noqa: BLE001
            lines.append("append_rectangle_xy(raw) failed: %s" % exc)
        lines.append("tris after rect: %s" % mesh.get_triangle_count())
        lines.append("verts after rect: %s" % mesh.get_vertex_count())

        # Does apply_mesh_plane_cut work, and what does it return?
        try:
            frame = unreal.Transform()
            res = mesh.apply_mesh_plane_cut(frame, unreal.GeometryScriptMeshPlaneCutOptions())
            lines.append("plane_cut -> %r" % (res,))
            lines.append("tris after cut: %s" % mesh.get_triangle_count())
        except Exception as exc:  # noqa: BLE001
            lines.append("plane_cut failed: %s" % exc)

        # And the voronoi diagram append.
        try:
            res = mesh.append_voronoi_diagram2d(unreal.Vector2(0.0, 0.0), 1.6, 12, 0.02)
            lines.append("voronoi2d -> %r" % (res,))
        except Exception as exc:  # noqa: BLE001
            lines.append("voronoi2d failed: %s" % exc)

    except Exception as exc:  # noqa: BLE001
        lines.append("construct failed: %s" % exc)

    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    unreal.log("API_PROBE5_DONE -> %s" % OUT)


main()
