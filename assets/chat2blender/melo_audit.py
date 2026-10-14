"""MELO LEGACY ASSET AUDIT - tile renderer + measured facts.

READ-ONLY with respect to the melo project: this script never writes inside
C:/Users/Administrator/Desktop/项目_开发与研究/Melo-Godot-Prototype. It only reads
GLB files and writes tiles/reports under F:/SEKAI/assets_source/review/melo/.

It also never disturbs the reviewer's current Blender scene. Everything happens
in a dedicated scene named ZZ_MELO_AUDIT, which is cleaned up at the end and the
original scene is made active again. That matters because the live Blender holds
the MELO hero body (62 objects) that the reviewer may still be inspecting.

Why tiles and not just dimensions: the brief is explicit that a file name is not
evidence. Every candidate is rendered, next to a 1 m reference cube, so "is this
100 mm or 1 m" and "does the silhouette actually read" are answered by looking.

Usage (from the Producer side, via the Blender MCP socket):
    run_audit(0, 20)     # render tiles for index range [0, 20)
    write_audit_report()  # print/write the measured table
    close_audit()
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import bpy
import os
import json
import math
from mathutils import Vector

INDEX = str(_SEKAI_ROOT / 'assets_source/review/melo/melo_glb_index.json')
TILE_DIR = str(_SEKAI_ROOT / '.render/melo_tiles/')
LOG = str(_SEKAI_ROOT / 'assets_source/review/melo/melo_measured.json')
TMP_SCENE = "ZZ_MELO_AUDIT"
RES = 560

# The audit's own rig. Everything else in the temp scene is an import and gets
# swept before the next asset.
KEEP_OBJECTS = {
    "AuditCam", "AuditKey", "AuditFill", "AuditRim", "AuditGround", "AuditRef1m",
}

# glTF is Y-up; Blender's importer rotates it to Z-up, which maps the glTF
# forward (-Z) onto Blender +Y. So "front" is +Y here and the 3/4 eye sits at
# +X +Y +Z. Verified against the first tile rather than assumed.
VIEW_DIR = Vector((-0.62, -0.72, -0.31)).normalized()

_rows = []
_dyn = []
_measured = {}
_origin_scene = None


def log(t):
    _rows.append(str(t))
    print(t)


def flush_log(path=None):
    """Persist the audit log to a file.

    The MCP socket response is truncated once a GLB import fills it with the
    glTF importer's own INFO lines, so reading results out of the response is
    unreliable. The log file is the dependable channel.
    """
    out = path or str(_SEKAI_ROOT / 'assets_source/review/melo/melo_audit_out.txt')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(_rows))
    return out


# ---------------------------------------------------------------------------
# scene plumbing
# ---------------------------------------------------------------------------

def _ensure_scene():
    global _origin_scene
    if _origin_scene is None:
        _origin_scene = bpy.context.window.scene.name

    tmp = bpy.data.scenes.get(TMP_SCENE)
    if tmp is None:
        tmp = bpy.data.scenes.new(TMP_SCENE)
        log("created audit scene %s" % TMP_SCENE)

    bpy.context.window.scene = tmp
    _setup_render(tmp)
    _setup_lights(tmp)
    return tmp


def _setup_render(scene):
    try:
        scene.render.engine = 'BLENDER_EEVEE_NEXT'
    except Exception:
        scene.render.engine = 'BLENDER_EEVEE'

    scene.render.film_transparent = False
    scene.render.resolution_x = RES
    scene.render.resolution_y = RES
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'

    # Same reason as the KIT-02a review rig: a hot rig makes every material look
    # like the rig, not like the asset. AgX + a dim world keeps mid-grey mid-grey.
    try:
        scene.view_settings.view_transform = 'AgX'
    except Exception:
        pass
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0.0

    r = scene.render
    r.use_stamp = True
    for f in ("use_stamp_date", "use_stamp_time", "use_stamp_render_time",
              "use_stamp_frame", "use_stamp_scene", "use_stamp_camera",
              "use_stamp_filename", "use_stamp_marker", "use_stamp_lens",
              "use_stamp_memory", "use_stamp_hostname", "use_stamp_frame_range",
              "use_stamp_sequencer_strip", "use_stamp_labels"):
        if hasattr(r, f):
            setattr(r, f, False)
    r.use_stamp_note = True
    r.stamp_font_size = 22

    if scene.world is None:
        scene.world = bpy.data.worlds.new("MeloAuditWorld")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.18, 0.19, 0.22, 1.0)
        bg.inputs[1].default_value = 0.60


def _get_collection(scene):
    return scene.collection


def _make_sun(scene, name, energy, direction, angle=0.04):
    obj = bpy.data.objects.get(name)
    if obj is None:
        data = bpy.data.lights.new(name, type='SUN')
        obj = bpy.data.objects.new(name, data)
        _get_collection(scene).objects.link(obj)
    obj.data.energy = energy
    obj.data.angle = angle
    d = Vector(direction).normalized()
    obj.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    return obj


def _setup_lights(scene):
    # SUNs, not AREA lights: sun strength does not fall off with distance, so one
    # rig exposes a 0.3 m drone part and a 40 m megagate identically. An area rig
    # would have to be re-tuned per asset and the sheet would stop being comparable.
    _make_sun(scene, "AuditKey", 2.4, (0.75, 0.72, 1.0))
    _make_sun(scene, "AuditFill", 0.8, (-0.85, 0.45, 0.35))
    _make_sun(scene, "AuditRim", 1.3, (-0.25, -0.95, 0.45))


def _get_camera(scene):
    cam = bpy.data.objects.get("AuditCam")
    if cam is None:
        data = bpy.data.cameras.new("AuditCam")
        cam = bpy.data.objects.new("AuditCam", data)
        _get_collection(scene).objects.link(cam)
    cam.data.lens = 50.0
    cam.data.clip_start = 0.001
    cam.data.clip_end = 5000.0
    scene.camera = cam
    return cam


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def _link(scene, obj):
    _get_collection(scene).objects.link(obj)
    return obj


def _make_ref_cube(scene):
    """A 1.00 m cube, so absolute scale is readable rather than implied."""
    obj = bpy.data.objects.get("AuditRef1m")
    if obj is not None:
        return obj
    mesh = bpy.data.meshes.new("AuditRef1m")
    verts = [(-0.5, -0.5, 0.0), (0.5, -0.5, 0.0), (0.5, 0.5, 0.0), (-0.5, 0.5, 0.0),
             (-0.5, -0.5, 1.0), (0.5, -0.5, 1.0), (0.5, 0.5, 1.0), (-0.5, 0.5, 1.0)]
    faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
             (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    mat = bpy.data.materials.get("AuditRefMat")
    if mat is None:
        mat = bpy.data.materials.new("AuditRefMat")
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (0.55, 0.20, 0.14, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.55
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("AuditRef1m", mesh)
    return _link(scene, obj)


def _make_ground(scene):
    obj = bpy.data.objects.get("AuditGround")
    if obj is not None:
        return obj
    mesh = bpy.data.meshes.new("AuditGround")
    s = 500.0
    mesh.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    mesh.update()
    mat = bpy.data.materials.get("AuditGroundMat")
    if mat is None:
        mat = bpy.data.materials.new("AuditGroundMat")
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (0.20, 0.20, 0.22, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.85
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("AuditGround", mesh)
    return _link(scene, obj)


def _scene_collections(scene):
    out = []
    stack = [scene.collection]
    while stack:
        col = stack.pop()
        out.append(col)
        stack.extend(col.children)
    return out


def _clear_dynamic(scene):
    """Remove every imported object from the audit scene.

    This deliberately does NOT rely on a module-level list of imported names.
    The MCP socket re-executes this file for every call, so such a list is empty
    at the start of each batch and objects from the previous batch survive into
    the next one's frames. That is exactly what happened on the first full sheet:
    the Ancient Sentinel stayed in the scene and appeared standing inside all 62
    sanctuary tiles. Sweeping the scene's own collections is stateless and immune
    to it. The audit's own rig is protected by name.
    """
    doomed = []
    for col in _scene_collections(scene):
        for obj in list(col.objects):
            if obj.name in KEEP_OBJECTS:
                continue
            doomed.append(obj)
    for obj in doomed:
        bpy.data.objects.remove(obj, do_unlink=True)
    return len(doomed)


def _world_bounds(objs):
    mn = Vector((1e18, 1e18, 1e18))
    mx = Vector((-1e18, -1e18, -1e18))
    found = False
    for obj in objs:
        if obj.type != 'MESH' or obj.data is None:
            continue
        mw = obj.matrix_world
        for corner in obj.bound_box:
            p = mw @ Vector(corner)
            mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y); mn.z = min(mn.z, p.z)
            mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y); mx.z = max(mx.z, p.z)
            found = True
    return (mn, mx) if found else (None, None)


def _tri_count(objs):
    n = 0
    for obj in objs:
        if obj.type != 'MESH' or obj.data is None:
            continue
        obj.data.calc_loop_triangles()
        n += len(obj.data.loop_triangles)
    return n


# Names that are never the asset's body. MELO's own module extractor solved the
# same problem with an explicit allowlist (visible_mesh_names), which is the other
# legitimate answer; a denylist is used here so an unknown new part still shows up
# in the sheet instead of silently vanishing.
HELPER_TOKENS = (
    "icosphere", "棱角球", "collision", "collider", "collide", "proxy", "helper",
    "bounds", "bounding", "ucx_", "ubx_", "usp_", "ucs_", "_col", "_collision",
    "trigger", "hitbox", "hull",
)


def _classify_helpers(objs, model_diag):
    """Split objects into (visual, helper).

    Two independent tests, because either one alone misfires:

      * name — anything that says it is a collider.
      * shape — a very low-poly object that spans most of the model is a proxy,
        not geometry someone modelled. MELO's Ancient Sentinel ships an 80-tri
        icosphere at 1.9 x 2.0 x 2.0 m wrapping a 0.56 m body; without this the
        audit frames the icosphere and reports a body five times too small.

    A high-poly object is never reclassified by shape, so a genuinely large
    detailed mesh still survives.
    """
    visual, helper = [], []
    meshes = [o for o in objs if o.type == 'MESH' and o.data is not None]

    stats = []
    for obj in meshes:
        obj.data.calc_loop_triangles()
        mn, mx = _world_bounds([obj])
        diag = (mx - mn).length if mn is not None else 0.0
        stats.append((obj, diag, len(obj.data.loop_triangles)))
    diags = sorted(s[1] for s in stats)
    median_diag = diags[len(diags) // 2] if diags else 0.0

    for obj in objs:
        name = obj.name.lower()
        if any(t in name for t in HELPER_TOKENS):
            helper.append(obj)

    for obj, diag, tris in stats:
        if obj in helper:
            continue
        # Shape test, deliberately conservative. A proxy is low-poly, spans the
        # whole model, and is far bigger than everything else. Without the
        # "far bigger than its siblings" clause a legitimately simple single-piece
        # asset (a 12-tri floor slab is the only object in its GLB) would be
        # thrown away and the asset would render empty.
        spans_model = model_diag > 0.0 and diag >= 0.70 * model_diag
        outsized = median_diag > 0.0 and diag >= 2.5 * median_diag
        if len(meshes) >= 3 and tris <= 400 and spans_model and outsized:
            helper.append(obj)
        else:
            visual.append(obj)

    # Never let the whole asset be classified away.
    if not any(o.type == 'MESH' and o.data is not None for o in visual):
        visual, helper = list(objs), []

    return visual, helper


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def run_audit(from_i=0, to_i=None, views=None, prefix=""):
    """Render one tile per asset in [from_i, to_i)."""
    entries = json.load(open(INDEX, encoding="utf-8"))
    if to_i is None:
        to_i = len(entries)
    to_i = min(to_i, len(entries))

    scene = _ensure_scene()
    _clear_dynamic(scene)
    ground = _make_ground(scene)
    ref = _make_ref_cube(scene)
    cam = _get_camera(scene)
    os.makedirs(TILE_DIR, exist_ok=True)

    if views is None:
        views = [("34", Vector((-0.62, -0.72, -0.31)))]

    n_ok = 0
    for i in range(from_i, to_i):
        e = entries[i]
        path = e["path"]
        if not os.path.exists(path):
            log("MISSING FILE %s" % path)
            continue

        _clear_dynamic(scene)

        before = {o.name for o in bpy.data.objects}
        try:
            bpy.ops.import_scene.gltf(filepath=path)
        except Exception as exc:
            log("IMPORT FAILED %s :: %s" % (e["rel"], exc))
            continue
        new_names = [o.name for o in bpy.data.objects if o.name not in before]
        _dyn.extend(new_names)
        objs = [bpy.data.objects[n] for n in new_names]

        mn, mx = _world_bounds(objs)
        if mn is None:
            log("NO GEOMETRY %s" % e["rel"])
            continue

        model_diag = (mx - mn).length
        visual, helper = _classify_helpers(objs, model_diag)

        vmn, vmx = _world_bounds(visual)
        if vmn is None:
            log("NO VISUAL GEOMETRY %s" % e["rel"])
            continue

        size = vmx - vmn
        centre = (vmn + vmx) * 0.5
        radius = max(size.length * 0.5, 1e-4)

        # Sit the asset on the ground plane so the reference cube shares its floor.
        # (Done on the root objects, not the meshes, so relative transforms survive.)
        roots = [o for o in objs if o.parent is None]
        for r in roots:
            r.location.z -= vmn.z

        mn2, mx2 = _world_bounds(visual)
        size = mx2 - mn2
        centre = (mn2 + mx2) * 0.5
        radius = max(size.length * 0.5, 1e-4)

        # Reference cube just outside the asset's right-hand edge, on the floor.
        ref.location = Vector((mx2.x + max(size.x, 0.4) * 0.25 + 0.6, centre.y, 0.0))
        ref.scale = (1.0, 1.0, 1.0)

        tris = _tri_count(visual)
        helper_tris = _tri_count(helper)
        mats = sorted({ms.material.name for o in visual if o.type == 'MESH' and o.data
                       for ms in o.material_slots if ms.material})
        dim_txt = "%.2f x %.2f x %.2f m" % (size.x, size.y, size.z)

        _measured[e["rel"]] = {
            "path": path,
            "group": e["group"],
            "owner": e["owner"],
            "size_bytes": e["size"],
            "dims_m": [round(size.x, 4), round(size.y, 4), round(size.z, 4)],
            "triangles": tris,
            "helper_triangles": helper_tris,
            "helper_objects": sorted(o.name for o in helper),
            "materials": mats,
            "objects": len(objs),
            "visual_objects": len(visual),
        }

        # Frame the ASSET to a fixed fill fraction of the frame, and treat the
        # reference cube as a marker rather than as a framing constraint.
        #
        # Why not fit asset+cube: a 1 m cube parked beside a 0.56 m construct is
        # legitimately larger than the subject, so fitting both makes the subject
        # a speck and the sheet stops being comparable between assets. Framing
        # each asset to the same fill is what makes a contact sheet readable; the
        # stamp carries the exact dimensions, so an asset smaller than the cube
        # still reads as "smaller than 1 m" rather than as "unknown".
        cam_centre = centre
        fov = cam.data.angle
        fill = 0.78
        dist = radius / math.sin(fill * fov * 0.5)

        for vname, vdir in views:
            d = vdir.normalized()
            eye = cam_centre - d * dist
            cam.location = eye
            cam.rotation_euler = (cam_centre - eye).to_track_quat('-Z', 'Y').to_euler()

            base = os.path.basename(e["rel"]).replace(".glb", "")
            tile = "%s%s__%s__%s.png" % (prefix, e["group"], base, vname)
            scene.render.filepath = TILE_DIR + tile
            scene.render.stamp_note_text = "%s  |  %s  |  %d tris" % (base, dim_txt, tris)
            bpy.ops.render.render(write_still=True)

        n_ok += 1
        if n_ok % 5 == 0:
            log("... %d/%d rendered (%s)" % (n_ok, to_i - from_i, os.path.basename(e["rel"])))

    log("AUDIT BATCH %d..%d done, %d tiles rendered" % (from_i, to_i, n_ok))
    _write_measured()
    return n_ok


def _write_measured():
    merged = {}
    if os.path.exists(LOG):
        try:
            merged = json.load(open(LOG, encoding="utf-8"))
        except Exception:
            merged = {}
    merged.update(_measured)
    json.dump(merged, open(LOG, "w", encoding="utf-8"), indent=1, ensure_ascii=False)


def write_audit_report():
    """Print the measured table and persist the log."""
    _write_measured()
    entries = json.load(open(INDEX, encoding="utf-8"))
    log("")
    log("=== MELO MEASURED (%d glb) ===" % len(entries))
    for e in entries:
        m = _measured.get(e["rel"])
        if m is None:
            log("(not yet rendered) %s" % e["rel"])
            continue
        log("%-58s %-22s %8d tris  %s" % (
            os.path.basename(e["rel"]),
            "%.2fx%.2fx%.2fm" % tuple(m["dims_m"]),
            m["triangles"],
            ",".join(m["materials"])[:60]))
    return len(entries)


def dump_objects(i, top=45):
    """Per-object world sizes for one asset.

    Needed because a bounding box alone can lie: if one stray or helper object is
    much larger than the hero body, sphere-fit framing makes the body render
    small and the reviewer mis-reads the asset. This is how that gets caught.
    """
    entries = json.load(open(INDEX, encoding="utf-8"))
    e = entries[i]
    scene = _ensure_scene()
    _clear_dynamic(scene)

    before = {o.name for o in bpy.data.objects}
    bpy.ops.import_scene.gltf(filepath=e["path"])
    new = [bpy.data.objects[n] for n in bpy.data.objects.keys() if n not in before]
    _dyn.extend([o.name for o in new])

    rows = []
    total = 0
    for o in new:
        if o.type != 'MESH' or o.data is None:
            rows.append((0.0, o.name, "%s (no mesh)" % o.type, 0))
            continue
        o.data.calc_loop_triangles()
        mn, mx = _world_bounds([o])
        d = mx - mn
        tris = len(o.data.loop_triangles)
        total += tris
        rows.append((d.length, o.name, "%.3f x %.3f x %.3f" % (d.x, d.y, d.z), tris))
    rows.sort(key=lambda r: -r[0])

    full_mn, full_mx = _world_bounds([o for o in new if o.type == 'MESH'])
    model_diag = (full_mx - full_mn).length if full_mn is not None else 0.0
    _, helper = _classify_helpers(new, model_diag)
    helper_names = {o.name for o in helper}

    log("")
    log("OBJECT SIZES :: %s  (%d objects, %d tris, model diag %.3f m)"
        % (e["rel"], len(new), total, model_diag))
    log("     diag   %-46s %-26s tris  flag" % ("name", "world size (m)"))
    for r in rows[:top]:
        flag = "  <-- HELPER (excluded from framing)" if r[1] in helper_names else ""
        log("  %8.3f   %-46s %-26s %d%s" % (r[0], r[1], r[2], r[3], flag))
    if len(rows) > top:
        log("  ... %d more" % (len(rows) - top))
    return len(new)


def close_audit():
    """Return the reviewer to the scene they were in before the audit."""
    global _origin_scene
    _clear_dynamic(bpy.context.scene)
    if _origin_scene and bpy.data.scenes.get(_origin_scene):
        bpy.context.window.scene = bpy.data.scenes[_origin_scene]
    log("audit closed, active scene restored to %s" % (bpy.context.window.scene.name))
    return bpy.context.window.scene.name
