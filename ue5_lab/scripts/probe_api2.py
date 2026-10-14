from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
# Sekai / RealityGlass_Lab — targeted probe #2.
#
# The first probe proved the Python environment works but only dumped class
# names off `unreal`; the callable function libraries live in their own
# sub-modules. Ask for them directly.

import unreal

OUT = str(_SEKAI_ROOT / 'ue5_lab/exports/api_probe2.txt')


def main():
    lines = []
    names = sorted(n for n in dir(unreal) if n.startswith("GeometryScriptLibrary_"))
    lines.append("GeometryScriptLibrary_* modules: %d" % len(names))
    for n in names:
        lines.append("  " + n)

    wanted = [n for n in names if any(k in n for k in
              ("Voronoi", "Boolean", "Primitive", "Asset", "BasicEdit", "Polygroup",
               "MeshSelection", "Transform", "Repair", "Subdivide", "UV", "Bake",
               "MeshQuery", "Collision", "Convex", "Sampling", "Deform", "Simplify",
               "VertexColor", "Normals", "MeshBoolean"))]

    for mod_name in wanted:
        mod = getattr(unreal, mod_name, None)
        if mod is None:
            lines.append("")
            lines.append("### %s : MISSING" % mod_name)
            continue
        funcs = sorted(f for f in dir(mod) if not f.startswith("_"))
        interesting = [f for f in funcs if any(k in f.lower() for k in
                       ("voronoi", "fracture", "cut", "boolean", "split", "plane",
                        "cell", "subdivide", "copy", "asset", "polygroup", "select",
                        "box", "sphere", "append", "combine"))]
        lines.append("")
        lines.append("### %s  (%d funcs, %d interesting)" % (mod_name, len(funcs), len(interesting)))
        for f in interesting:
            lines.append("    " + f)

    # Export / asset helpers we will need to write shard meshes to disk.
    lines.append("")
    lines.append("### unreal.EditorAssetLibrary funcs of interest")
    eal = [f for f in dir(unreal.EditorAssetLibrary) if not f.startswith("_")]
    for f in sorted(eal):
        if any(k in f.lower() for k in ("create", "save", "export", "duplicate", "asset")):
            lines.append("    " + f)

    lines.append("")
    lines.append("### unreal.GeometryScriptVoronoiOptions fields")
    try:
        for f in sorted(x for x in dir(unreal.GeometryScriptVoronoiOptions) if not x.startswith("_")):
            lines.append("    " + f)
    except Exception as exc:  # noqa: BLE001
        lines.append("    <error %s>" % exc)

    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    unreal.log("API_PROBE2_DONE -> %s" % OUT)


main()
