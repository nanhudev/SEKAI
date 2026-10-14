from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
# SEKAI / RealityGlass_Lab — API probe.
#
# UE 5.8's Python surface for fracture is not documented well enough to code
# against blind, so ask the engine directly and write the answer to a file.
# We are looking for: a Voronoi / fracture entry point, a mesh-component that
# can hold a Geometry Collection, and anything that can export meshes.

import unreal
import json

OUT = str(_SEKAI_ROOT / 'ue5_lab/exports/api_probe.txt')


def main():
    lines = []
    lines.append("engine: %s" % unreal.SystemLibrary.get_engine_version())

    names = [n for n in dir(unreal)]

    def bucket(title, needles):
        hits = sorted(n for n in names if any(k.lower() in n.lower() for k in needles))
        lines.append("")
        lines.append("=== %s (%d) ===" % (title, len(hits)))
        for h in hits[:200]:
            lines.append("  " + h)

    bucket("FRACTURE", ["fracture", "voronoi", "vorono", "cell", "shatter"])
    bucket("GEOMETRY_SCRIPT", ["geometryscript", "geometry_script"])
    bucket("PLANAR / CUT / SLICE", ["planarcut", "cut", "slice", "clip"])
    bucket("STATIC MESH / EXPORT", ["meshdescription", "staticmeshex", "assetexport", "savemesh", "obj "])
    bucket("RENDER / MRQ", ["movierender", "renderqueue", "screenshot", "highres"])
    bucket("PCG", ["pcg"])

    # The Geometry Script library namespaces are the likely home for a
    # Voronoi-fracture node exposed to Python.
    lines.append("")
    lines.append("=== unreal classes with 'GeometryScript' in the name ===")
    try:
        classes = sorted(n for n in names if "GeometryScript" in n)
        for c in classes[:200]:
            lines.append("  " + c)
    except Exception as exc:  # noqa: BLE001
        lines.append("  <error %s>" % exc)

    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    unreal.log("API_PROBE_DONE -> %s" % OUT)


main()
