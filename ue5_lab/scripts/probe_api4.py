from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
# Sekai / RealityGlass_Lab — probe #4: what can a DynamicMesh actually do?

import unreal

OUT = str(_SEKAI_ROOT / 'ue5_lab/exports/api_probe4.txt')


def main():
    lines = []
    dm = unreal.DynamicMesh
    funcs = sorted(f for f in dir(dm) if not f.startswith("_"))
    lines.append("DynamicMesh methods: %d" % len(funcs))
    lines.append("")
    lines.append("=== every DynamicMesh method (full list) ===")
    for f in funcs:
        lines.append("  " + f)

    keys = ("voronoi", "fracture", "cut", "slice", "boolean", "split", "plane",
            "convex", "decompose", "cluster", "collapse", "separate", "polygroup",
            "simplify", "remesh", "intersect", "union", "difference", "trim")
    lines.append("")
    lines.append("=== DynamicMesh fracture-relevant ===")
    for f in funcs:
        if any(k in f.lower() for k in keys):
            lines.append("  " + f)

    lines.append("")
    lines.append("=== names containing 'Dataflow' or 'GeometryCollection' ===")
    for n in sorted(dir(unreal)):
        if "dataflow" in n.lower() or "geometrycollection" in n.lower():
            lines.append("  " + n)

    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    unreal.log("API_PROBE4_DONE -> %s" % OUT)


main()
