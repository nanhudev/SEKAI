from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import unreal

OUT = str(_SEKAI_ROOT / 'ue5_lab/exports/api_probe7.txt')
lines = []


def log(s):
    lines.append(str(s))
    try:
        with open(OUT, "a", encoding="utf-8") as f:
            f.write(str(s) + "\n")
    except Exception:
        pass


open(OUT, "w", encoding="utf-8").close()

log("=== wrapper classes exist? ===")
for name in ("GeometryScriptVectorList", "GeometryScriptIndexList",
             "GeometryScriptTriangleList", "GeometryScriptGroupLayer"):
    cls = getattr(unreal, name, None)
    log("%s -> %r" % (name, cls))

log("")
log("=== GeometryScriptGroupLayer dir ===")
gl_cls = getattr(unreal, "GeometryScriptGroupLayer", None)
if gl_cls is not None:
    log(repr([a for a in dir(gl_cls) if not a.startswith("_")]))

log("")
log("=== construct a tiny voronoi and inspect returns ===")
mesh = unreal.DynamicMesh()
sites = [unreal.Vector2D(0.0, 0.0), unreal.Vector2D(0.5, 0.2),
         unreal.Vector2D(-0.4, 0.3), unreal.Vector2D(0.1, -0.5)]
prim = unreal.GeometryScriptPrimitiveOptions()
opts = unreal.GeometryScriptVoronoiOptions()
opts.set_editor_property("bounds", unreal.Box(
    unreal.Vector(-1.0, -1.0, -0.5), unreal.Vector(1.0, 1.0, 0.5)))
mesh.append_voronoi_diagram2d(prim, unreal.Transform(), sites, opts)
log("tris=%d verts=%d" % (mesh.get_triangle_count(), mesh.get_vertex_count()))

try:
    r = mesh.get_all_vertex_positions(True)
    log("get_all_vertex_positions(True) -> type=%s len=%s" % (type(r), len(r) if hasattr(r, "__len__") else "?"))
    if isinstance(r, tuple):
        for i, e in enumerate(r):
            log("  [%d] type=%s repr=%.160s" % (i, type(e), repr(e)))
        wrapper = r[1]
    else:
        wrapper = r
    log("  wrapper attrs: %s" % repr([a for a in dir(wrapper) if not a.startswith("_")]))
    for attr in ("list", "items", "vector_list", "positions"):
        v = getattr(wrapper, attr, "MISSING")
        if v != "MISSING":
            try:
                log("  .%s -> len=%d first=%r" % (attr, len(v), v[0] if len(v) else None))
            except Exception as exc:
                log("  .%s -> %r (%s)" % (attr, v, exc))
except Exception as exc:
    log("vertex positions FAILED: %r" % (exc,))

try:
    r2 = mesh.get_all_triangle_indices(True)
    log("get_all_triangle_indices(True) -> type=%s" % type(r2))
    if isinstance(r2, tuple):
        for i, e in enumerate(r2):
            log("  [%d] type=%s repr=%.200s" % (i, type(e), repr(e)))
        w2 = r2[1]
    else:
        w2 = r2
    log("  wrapper attrs: %s" % repr([a for a in dir(w2) if not a.startswith("_")]))
    for attr in ("list", "items", "triangle_list"):
        v = getattr(w2, attr, "MISSING")
        if v != "MISSING":
            try:
                log("  .%s -> len=%d first=%r" % (attr, len(v), v[0] if len(v) else None))
            except Exception as exc:
                log("  .%s -> %r (%s)" % (attr, v, exc))
except Exception as exc:
    log("triangle indices FAILED: %r" % (exc,))

log("")
log("=== group layer + polygroups ===")
gl = None
if gl_cls is not None:
    for args in ((), (0,), (True, 0)):
        try:
            gl = gl_cls(*args)
            log("GeometryScriptGroupLayer%r OK -> %r" % (args, gl))
            break
        except Exception as exc:
            log("GeometryScriptGroupLayer%r failed: %s" % (args, exc))
if gl is not None:
    for maker in ("GeometryScriptIndexList", "GeometryScriptTriangleList"):
        wcls = getattr(unreal, maker, None)
        if wcls is None:
            log("%s missing" % maker)
            continue
        try:
            w = wcls()
            log("%s() OK -> %r attrs=%s" % (maker, w, repr([a for a in dir(w) if not a.startswith("_")])))
        except Exception as exc:
            log("%s() failed: %s" % (maker, exc))

log("PROBE7_DONE")
print("PROBE7_DONE")
