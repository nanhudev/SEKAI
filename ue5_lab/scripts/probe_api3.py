from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
# Sekai / RealityGlass_Lab — probe #3: is any fracture entry point callable from Python?

import unreal

OUT = str(_SEKAI_ROOT / 'ue5_lab/exports/api_probe3.txt')

CANDIDATES = [
    "GeometryScriptLibrary_MeshVoronoiFunctions",
    "GeometryScriptLibrary_MeshBooleanFunctions",
    "GeometryScriptLibrary_MeshPrimitiveFunctions",
    "GeometryScriptLibrary_MeshAssetFunctions",
    "GeometryScriptLibrary_MeshBasicEditFunctions",
    "GeometryScriptLibrary_MeshSelectionFunctions",
    "GeometryScriptLibrary_MeshSubdivideFunctions",
    "GeometryScriptLibrary_MeshDeformFunctions",
    "GeometryScriptLibrary_MeshRepairFunctions",
    "GeometryScriptLibrary_MeshNormalsFunctions",
    "GeometryScriptLibrary_MeshVertexColorFunctions",
    "GeometryScriptLibrary_StaticMeshFunctions",
    "GeometryScriptLibrary_SceneUtilityFunctions",
    "GeometryScriptLibrary_EditorDynamicMeshFunctions",
    "EditorGeometryScriptingLibrary",
    "GeometryScriptFunctionLibrary",
    "DynamicMesh",
    "GeometryScript",
]


def main():
    lines = []
    for name in CANDIDATES:
        obj = getattr(unreal, name, None)
        if obj is None:
            lines.append("MISSING  %s" % name)
            continue
        funcs = sorted(f for f in dir(obj) if not f.startswith("_"))
        lines.append("PRESENT  %s  (%d public names)" % (name, len(funcs)))
        for f in funcs[:40]:
            lines.append("      " + f)

    # Anything at all in the whole namespace that looks callable and fracture-ish.
    lines.append("")
    lines.append("=== every unreal name containing voronoi/fracture/cell (case-insensitive) ===")
    for n in sorted(dir(unreal)):
        low = n.lower()
        if any(k in low for k in ("voronoi", "fracture", "shatter", "geometryscript")):
            lines.append("  %s" % n)

    # Total namespace size, so we know the binding set is real.
    lines.append("")
    lines.append("total unreal namespace entries: %d" % len(dir(unreal)))

    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    unreal.log("API_PROBE3_DONE -> %s" % OUT)


main()
