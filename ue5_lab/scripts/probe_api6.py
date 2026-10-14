from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import unreal

OUT = str(_SEKAI_ROOT / 'ue5_lab/exports/api_probe6.txt')
lines = []

def log(s):
    lines.append(str(s))

NAMES = [
    "get_all_vertex_positions",
    "get_all_vertex_i_ds",
    "get_all_triangle_indices",
    "get_all_triangle_polygroup_i_ds",
    "get_all_triangle_material_i_ds",
    "get_polygroup_i_ds_in_mesh",
    "get_triangles_in_polygroup",
    "get_triangle_polygroup_id",
    "get_has_polygroups",
    "get_vertex_position",
    "get_vertex_count",
    "get_triangle_count",
    "get_num_extended_polygroup_layers",
    "append_voronoi_diagram2d",
]

mesh = unreal.DynamicMesh()
for n in NAMES:
    fn = getattr(mesh, n, None)
    if fn is None:
        log("MISSING: %s" % n)
        continue
    doc = getattr(fn, "__doc__", None)
    log("=== %s ===" % n)
    log(doc)

with open(OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
print("\n".join(lines))
