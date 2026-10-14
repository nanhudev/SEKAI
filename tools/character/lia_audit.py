# -*- coding: utf-8 -*-
"""
SEKAI / CHARACTER LINE — LIA V0 AUDIT
=====================================
Read-only inspection of the source FBX. Never modifies the source.

Run:
  "G:/blender.exe" -b --factory-startup --python tools/character/lia_audit.py -- \
      --fbx assets_source/characters/lia/01_v0_original/LIA_v0_original.fbx \
      --out assets_source/characters/lia/00_reference
"""

import bpy
import bmesh
import json
import math
import os
import sys
from mathutils import Vector

# ----------------------------------------------------------------------------- args
argv = sys.argv
argv = argv[argv.index("--") + 1:] if "--" in argv else []
ARGS = {}
i = 0
while i < len(argv):
    if argv[i].startswith("--"):
        ARGS[argv[i][2:]] = argv[i + 1] if i + 1 < len(argv) else ""
        i += 2
    else:
        i += 1

FBX = os.path.abspath(ARGS.get("fbx", "assets_source/characters/lia/01_v0_original/LIA_v0_original.fbx"))
OUT = os.path.abspath(ARGS.get("out", "assets_source/characters/lia/00_reference"))
os.makedirs(OUT, exist_ok=True)

R = {}          # the report
TAU = math.tau


def clean_scene():
    bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)


def note(section, key, val):
    R.setdefault(section, {})[key] = val


def log(msg):
    print("[LIA-AUDIT] " + str(msg), flush=True)


# ----------------------------------------------------------------------------- import
clean_scene()
log("fbx = " + FBX)

imported = []
before = set(bpy.data.objects.keys())
try:
    bpy.ops.import_scene.fbx(filepath=FBX, use_custom_normals=True, ignore_leaf_bones=False,
                             automatic_bone_orientation=False, global_scale=1.0)
except Exception as e:
    log("import_scene.fbx failed: %r -- trying wm.fbx_import" % (e,))
    bpy.ops.wm.fbx_import(filepath=FBX)

imported = [o for o in bpy.data.objects if o.name not in before]
log("imported %d objects" % len(imported))

note("source", "fbx_path", FBX)
note("source", "fbx_bytes", os.path.getsize(FBX))
note("source", "blender_version", bpy.app.version_string)

# ----------------------------------------------------------------------------- scene graph
scene_objs = []
for o in sorted(bpy.data.objects, key=lambda x: x.name):
    entry = {
        "name": o.name,
        "type": o.type,
        "parent": o.parent.name if o.parent else None,
        "parent_type": o.parent_type if o.parent else None,
        "collections": [c.name for c in o.users_collection],
        "location": [round(v, 6) for v in o.location],
        "rotation_euler_deg": [round(math.degrees(v), 4) for v in o.rotation_euler],
        "rotation_mode": o.rotation_mode,
        "scale": [round(v, 6) for v in o.scale],
        "dimensions": [round(v, 6) for v in o.dimensions],
        "modifiers": [(m.name, m.type) for m in o.modifiers],
        "hide_render": o.hide_render,
    }
    if o.type == 'MESH':
        entry["verts"] = len(o.data.vertices)
        entry["materials"] = [m.name if m else None for m in o.data.materials]
        entry["shape_keys"] = [k.name for k in o.data.shape_keys.key_blocks] if o.data.shape_keys else []
        entry["uv_layers"] = [l.name for l in o.data.uv_layers]
        entry["vertex_groups"] = len(o.vertex_groups)
    scene_objs.append(entry)
note("scene", "objects", scene_objs)
note("scene", "object_count", len(scene_objs))

# ----------------------------------------------------------------------------- world bbox / scale
def world_bbox(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    found = False
    for o in objs:
        if o.type != 'MESH':
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for k in range(3):
                mn[k] = min(mn[k], w[k])
                mx[k] = max(mx[k], w[k])
            found = True
    return (mn, mx) if found else (None, None)


meshes = [o for o in bpy.data.objects if o.type == 'MESH']
armatures = [o for o in bpy.data.objects if o.type == 'ARMATURE']
mn, mx = world_bbox(meshes)
if mn:
    size = mx - mn
    note("scale", "bbox_min_m", [round(v, 5) for v in mn])
    note("scale", "bbox_max_m", [round(v, 5) for v in mx])
    note("scale", "size_m", [round(v, 5) for v in size])
    note("scale", "height_Z_m", round(size.z, 5))
    note("scale", "width_X_m", round(size.x, 5))
    note("scale", "depth_Y_m", round(size.y, 5))
    note("scale", "feet_at_z", round(mn.z, 5))
    # which world axis is "up" (largest extent on a humanoid)
    note("scale", "note_units", "Blender m; 1 unit = 1 m assumed")

# ----------------------------------------------------------------------------- per-mesh geometry
def analyse_mesh(o):
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()

    tri = 0
    ngon = 0
    quad = 0
    degenerate = 0
    for f in bm.faces:
        n = len(f.verts)
        if n == 3:
            tri += 1
        elif n == 4:
            quad += 1
        else:
            ngon += 1
            tri += n - 2
        if f.calc_area() < 1e-10:
            degenerate += 1
    tri += quad * 2

    non_manifold = 0
    boundary = 0
    wire = 0
    non_contiguous = 0
    loose_verts = 0
    for e in bm.edges:
        nf = len(e.link_faces)
        if nf == 0:
            wire += 1
        elif nf == 1:
            boundary += 1
        elif nf > 2:
            non_manifold += 1
        if nf == 2 and not e.is_contiguous:
            non_contiguous += 1
    for v in bm.verts:
        if not v.link_edges:
            loose_verts += 1

    # duplicate / coincident vertices
    buckets = {}
    for v in bm.verts:
        k = (round(v.co.x, 4), round(v.co.y, 4), round(v.co.z, 4))
        buckets.setdefault(k, 0)
        buckets[k] += 1
    dup_verts = sum(c - 1 for c in buckets.values() if c > 1)

    # duplicate faces (same rounded centroid) -> doubled shells
    fcent = {}
    for f in bm.faces:
        c = f.calc_center_median()
        k = (round(c.x, 4), round(c.y, 4), round(c.z, 4))
        fcent.setdefault(k, 0)
        fcent[k] += 1
    dup_faces = sum(c - 1 for c in fcent.values() if c > 1)

    # 3d area
    area3d = sum(f.calc_area() for f in bm.faces)

    bm.free()

    # ---- UV
    uv_report = {}
    for layer in me.uv_layers:
        uvl = layer.data
        uvs = [(d.uv[0], d.uv[1]) for d in uvl]
        if not uvs:
            continue
        xs = [u for u, _ in uvs]
        ys = [v for _, v in uvs]
        outside = sum(1 for u, v in uvs if u < -1e-4 or u > 1 + 1e-4 or v < -1e-4 or v > 1 + 1e-4)
        area2d = 0.0
        flipped_uv = 0
        for poly in me.polygons:
            pts = [Vector(uvs[li]) for li in poly.loop_indices]
            a = 0.0
            for k in range(len(pts)):
                x1, y1 = pts[k]
                x2, y2 = pts[(k + 1) % len(pts)]
                a += x1 * y2 - x2 * y1
            a *= 0.5
            area2d += abs(a)
            if a < 0:
                flipped_uv += 1
        td = (math.sqrt(area2d) / math.sqrt(area3d)) if area3d > 1e-9 else 0.0
        uv_report[layer.name] = {
            "uv_bbox": [round(min(xs), 4), round(min(ys), 4), round(max(xs), 4), round(max(ys), 4)],
            "loops_outside_0_1": outside,
            "uv_area_0_1": round(area2d, 5),
            "mesh_area_m2": round(area3d, 6),
            "texel_density_index": round(td, 4),
            "loops_total": len(uvs),
        }
        # loose / unused uv space indicator
        uv_report[layer.name]["uv_coverage_of_unit"] = round(area2d, 5)
        uv_report[layer.name]["uv_mirrored_faces"] = flipped_uv
    return {
        "verts": len(me.vertices),
        "edges": len(me.edges),
        "faces": len(me.polygons),
        "tris": tri,
        "quads": quad,
        "ngons": ngon,
        "degenerate_faces": degenerate,
        "non_manifold_edges": non_manifold,
        "boundary_edges": boundary,
        "wire_edges": wire,
        "non_contiguous_edges": non_contiguous,
        "loose_verts": loose_verts,
        "duplicate_verts": dup_verts,
        "duplicate_faces": dup_faces,
        "area_m2": round(area3d, 6),
        "uv": uv_report,
        "has_custom_normals": bool(me.has_custom_normals) if hasattr(me, "has_custom_normals") else None,
        "shade_smooth_faces": sum(1 for p in me.polygons if p.use_smooth),
        "auto_smooth": None,
    }


mesh_report = {}
total_tris = 0
for o in sorted(meshes, key=lambda x: x.name):
    r = analyse_mesh(o)
    mesh_report[o.name] = r
    total_tris += r["tris"]
note("geometry", "per_mesh", mesh_report)
note("geometry", "total_tris", total_tris)
note("geometry", "total_verts", sum(len(o.data.vertices) for o in meshes))
note("geometry", "mesh_object_count", len(meshes))

# ----------------------------------------------------------------------------- object intersection (overlap proxy)
def world_aabb(o):
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    return (Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))),
            Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))))


overlaps = []
boxes = {o.name: world_aabb(o) for o in meshes}
names = sorted(boxes)
for a in range(len(names)):
    for b in range(a + 1, len(names)):
        (a0, a1) = boxes[names[a]]
        (b0, b1) = boxes[names[b]]
        ov = min(a1.x, b1.x) - max(a0.x, b0.x)
        oy = min(a1.y, b1.y) - max(a0.y, b0.y)
        oz = min(a1.z, b1.z) - max(a0.z, b0.z)
        if ov > 0.01 and oy > 0.01 and oz > 0.01:
            overlaps.append({"a": names[a], "b": names[b],
                             "overlap_m": [round(ov, 3), round(oy, 3), round(oz, 3)]})
note("geometry", "aabb_overlaps", overlaps[:200])
note("geometry", "aabb_overlap_count", len(overlaps))

# ----------------------------------------------------------------------------- materials
mats = []
for m in bpy.data.materials:
    entry = {"name": m.name, "use_nodes": m.use_nodes, "blend_method": getattr(m, "blend_method", None),
             "double_sided": not m.use_backface_culling}
    if m.use_nodes:
        nodes = []
        bsdf = None
        for n in m.node_tree.nodes:
            nodes.append({"name": n.name, "type": n.type, "label": n.label})
            if n.type == 'BSDF_PRINCIPLED':
                bsdf = n
        entry["nodes"] = nodes
        if bsdf:
            def iv(k):
                try:
                    v = bsdf.inputs[k].default_value
                    try:
                        return [round(x, 4) for x in v]
                    except TypeError:
                        return round(float(v), 4)
                except Exception:
                    return None
            entry["base_color"] = iv("Base Color")
            entry["metallic"] = iv("Metallic")
            entry["roughness"] = iv("Roughness")
            entry["ior"] = iv("IOR")
            linked = []
            for s in bsdf.inputs:
                if s.is_linked:
                    linked.append({"socket": s.name, "from": s.links[0].from_node.type,
                                   "image": getattr(s.links[0].from_node, "image", None).name
                                   if getattr(s.links[0].from_node, "image", None) else None})
            entry["linked_inputs"] = linked
        entry["image_nodes"] = [n.image.name for n in m.node_tree.nodes
                                if n.type == 'TEX_IMAGE' and n.image]
    mats.append(entry)
note("materials", "list", mats)
note("materials", "count", len(mats))

images = []
for im in bpy.data.images:
    images.append({"name": im.name, "size": list(im.size), "filepath": im.filepath,
                   "packed": bool(im.packed_file), "source": im.source,
                   "colorspace": im.colorspace_settings.name if im.colorspace_settings else None})
note("materials", "images", images)

# ----------------------------------------------------------------------------- armature
arm_report = {}
for arm in armatures:
    bones = []
    for b in arm.data.bones:
        bones.append({
            "name": b.name,
            "parent": b.parent.name if b.parent else None,
            "head": [round(v, 5) for v in b.head_local],
            "tail": [round(v, 5) for v in b.tail_local],
            "length": round(b.length, 5),
            "use_deform": b.use_deform,
            "roll_deg": round(math.degrees(b.matrix_local.to_euler().y), 3),
        })
    arm_report[arm.name] = {
        "bone_count": len(bones),
        "bones": bones,
        "scale": [round(v, 6) for v in arm.scale],
        "dimensions": [round(v, 5) for v in arm.dimensions],
        "rest_height_span_z": round(max(b.tail_local.z for b in arm.data.bones) -
                                    min(b.head_local.z for b in arm.data.bones), 5) if bones else None,
    }
note("rig", "armatures", arm_report)
note("rig", "armature_count", len(armatures))

if not armatures:
    note("rig", "verdict", "NO ARMATURE IN SOURCE — rig must be built from scratch")

# ----------------------------------------------------------------------------- weights
weights = {}
for o in meshes:
    if not o.vertex_groups:
        continue
    groups = {g.index: g.name for g in o.vertex_groups}
    counts = []
    unweighted = 0
    over4 = 0
    maxinf = 0
    bad_sum = 0
    side_mismatch = 0
    per_group = {name: 0 for name in groups.values()}
    for v in o.data.vertices:
        gs = [g for g in v.groups if g.weight > 1e-5]
        n = len(gs)
        counts.append(n)
        if n == 0:
            unweighted += 1
        if n > 4:
            over4 += 1
        maxinf = max(maxinf, n)
        s = sum(g.weight for g in gs)
        if abs(s - 1.0) > 0.02:
            bad_sum += 1
        for g in gs:
            if g.group in groups:
                per_group[groups[g.group]] += 1
    weights[o.name] = {
        "vertex_groups": len(groups),
        "group_names": list(groups.values()),
        "verts": len(o.data.vertices),
        "unweighted_verts": unweighted,
        "verts_over_4_influences": over4,
        "max_influences": maxinf,
        "avg_influences": round(sum(counts) / max(1, len(counts)), 3),
        "non_normalized_verts": bad_sum,
        "empty_groups": [k for k, v in per_group.items() if v == 0],
    }
note("weights", "per_mesh", weights)

# ----------------------------------------------------------------------------- shape keys
sk = {}
for o in meshes:
    if o.data.shape_keys:
        sk[o.name] = [k.name for k in o.data.shape_keys.key_blocks]
note("shape_keys", "per_mesh", sk)
note("shape_keys", "count", sum(len(v) for v in sk.values()))

# ----------------------------------------------------------------------------- write
json_path = os.path.join(OUT, "LIA_V0_AUDIT.json")
with open(json_path, "w", encoding="utf-8") as f:
    json.dump(R, f, indent=2, ensure_ascii=False)
log("wrote " + json_path)

# also dump a plain-text summary
txt_path = os.path.join(OUT, "LIA_V0_AUDIT_raw.txt")
with open(txt_path, "w", encoding="utf-8") as f:
    def w(line=""):
        f.write(str(line) + "\n")
    w("LIA V0 AUDIT RAW — blender %s" % bpy.app.version_string)
    w("fbx: %s (%d bytes)" % (FBX, os.path.getsize(FBX)))
    w()
    w("== SCALE ==")
    for k, v in R.get("scale", {}).items():
        w("  %-18s %s" % (k, v))
    w()
    w("== OBJECTS ==")
    for o in R["scene"]["objects"]:
        w("  %-30s %-9s parent=%-22s scale=%s dim=%s" %
          (o["name"], o["type"], o["parent"], o["scale"], o["dimensions"]))
    w()
    w("== GEOMETRY ==")
    for name, g in R["geometry"]["per_mesh"].items():
        w("  %s" % name)
        w("     verts=%d tris=%d faces=%d quads=%d ngons=%d degen=%d" %
          (g["verts"], g["tris"], g["faces"], g["quads"], g["ngons"], g["degenerate_faces"]))
        w("     nonmanifold=%d boundary=%d wire=%d noncontig=%d looseV=%d dupV=%d dupF=%d" %
          (g["non_manifold_edges"], g["boundary_edges"], g["wire_edges"],
           g["non_contiguous_edges"], g["loose_verts"], g["duplicate_verts"], g["duplicate_faces"]))
        w("     area=%.6f m2  smooth_faces=%d/%d custom_normals=%s" %
          (g["area_m2"], g["shade_smooth_faces"], g["faces"], g["has_custom_normals"]))
        for ln, u in g["uv"].items():
            w("     UV[%s] bbox=%s outside=%d uvarea=%.4f texdensity=%.3f mirrored=%d" %
              (ln, u["uv_bbox"], u["loops_outside_0_1"], u["uv_area_0_1"],
               u["texel_density_index"], u["uv_mirrored_faces"]))
    w()
    w("  TOTAL tris = %d  verts = %d  meshes = %d" %
      (R["geometry"]["total_tris"], R["geometry"]["total_verts"], R["geometry"]["mesh_object_count"]))
    w()
    w("== MATERIALS ==")
    for m in R["materials"]["list"]:
        w("  %-28s nodes=%s bsdf=%s base=%s metal=%s rough=%s" %
          (m["name"], m.get("use_nodes"), "yes" if "base_color" in m else "NO",
           m.get("base_color"), m.get("metallic"), m.get("roughness")))
        for li in m.get("linked_inputs", []):
            w("        linked %s <- %s %s" % (li["socket"], li["from"], li["image"]))
    w()
    w("  images:")
    for im in R["materials"]["images"]:
        w("     %-30s %s packed=%s cs=%s path=%s" %
          (im["name"], im["size"], im["packed"], im["colorspace"], im["filepath"]))
    w()
    w("== RIG ==")
    if not arm_report:
        w("  NO ARMATURE")
    for an, a in arm_report.items():
        w("  %s bones=%d scale=%s" % (an, a["bone_count"], a["scale"]))
        for b in a["bones"]:
            w("     %-24s parent=%-22s len=%.4f deform=%s" %
              (b["name"], b["parent"], b["length"], b["use_deform"]))
    w()
    w("== WEIGHTS ==")
    for name, ww in weights.items():
        w("  %s groups=%d unweighted=%d over4=%d max=%d avg=%.2f nonnorm=%d empty=%s" %
          (name, ww["vertex_groups"], ww["unweighted_verts"], ww["verts_over_4_influences"],
           ww["max_influences"], ww["avg_influences"], ww["non_normalized_verts"],
           ww["empty_groups"][:10]))
    w()
    w("== SHAPE KEYS ==")
    for name, keys in sk.items():
        w("  %s: %s" % (name, keys))
    w()
    w("== AABB OVERLAPS (proximity, >1cm on all axes) ==")
    for ov in R["geometry"]["aabb_overlaps"]:
        w("  %-26s <-> %-26s %s" % (ov["a"], ov["b"], ov["overlap_m"]))
log("wrote " + txt_path)

print("AUDIT_DONE", json_path)
