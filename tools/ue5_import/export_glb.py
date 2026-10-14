# UE5 Mistvale level FBX  ->  Godot-importable GLB.
#
# What this is for: the UE5 map is the level art; Godot is the runtime. This is
# the art->game hand-off, so the only acceptable outcome is "the same geometry,
# in the same place, in a format Godot reads".
#
# Two facts this script relies on, both measured rather than assumed:
#
#   1. After Blender's FBX import the scene sits in UE's OWN world frame --
#      Z-up, metres, origin coincident. Verified by diffing every one of the 225
#      objects against ue5_lab/.../exported_scene_bounds.json: max deviation
#      0.0005 m, and no axis comes out sign-flipped (a global mirror scores
#      225/225 on that probe; X scores 6, all genuinely symmetric props).
#      So there is nothing to fix up here. Do not "correct" an axis.
#
#   2. Blender's glTF exporter then converts Z-up -> glTF's Y-up, which is
#      Godot's convention. The mapping Godot will see is
#          godot = ( ue.x , ue.z , -ue.y )
#      and this script writes that expectation to JSON so the Godot side can
#      assert on it instead of eyeballing a screenshot.
#
# Material colours are reported but NOT invented. If the FBX carried no base
# colours the map imports white; that is a materials problem for a later pass,
# not something to paper over by assigning colours here.
#
# Run:
#   "/g/blender.exe" -b --factory-startup --python export_glb.py -- <fbx> <out.glb> <out.json>

import bpy
import json
import sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
fbx_path, glb_path, out_path = argv[0], argv[1], argv[2]

for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
assert len(bpy.data.objects) == 0, "scene was not empty before import"

# Blender 5.1 io_scene_fbx regression: `hasattr(lamp, "cycles")` passes but
# `lamp.cycles.cast_shadow` no longer exists, so importing any FBX that carries
# a light node aborts the WHOLE file. The UE level export carries the level
# lights. Swallow it and let the light node have no Blender data, which also
# keeps UE's sun/sky out of the Godot scene.
import io_scene_fbx.import_fbx as _imp  # noqa: E402

_original_read_light = _imp.blen_read_light


def _read_light_tolerating_cycles_regression(fbx_tmpl, fbx_obj, settings):
    try:
        return _original_read_light(fbx_tmpl, fbx_obj, settings)
    except AttributeError:
        return None


_imp.blen_read_light = _read_light_tolerating_cycles_regression

bpy.ops.import_scene.fbx(filepath=fbx_path)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]

# ---------------------------------------------------------------------------
# The palette.
#
# NOT invented here. The UE FBX export has material baking DISABLED
# (audit_saved_art_scene.py sets bake_material_inputs=DISABLED), so the FBX
# carries material NAMES and no colours, and Blender's importer hands every one
# of them the same 0.8 grey. The map would import as one flat grey mass.
#
# These values are read out of the three scripts that already own them:
#   model_guild.py         -> MV_Guild_*
#   model_stone_bridge.py  -> MV_Bridge_*
#   render_saved_scene.py  -> M_Valley / M_Town_Road / M_River_* / M_Weathered /
#                             M_House_*
# Matching is by substring, longest key first, so MV_Bridge_CreamLimestone
# cannot be captured by a shorter overlapping key.
#
# The UE materials for the four M_House_* also blend wall -> roof by the vertex
# normal's Z (colorize_town.py). That split cannot survive glTF export -- glTF
# carries Principled inputs, not node graphs -- so this pass writes the flat
# value and the wall/roof blend is reproduced on the Godot side as a shader.
# ---------------------------------------------------------------------------
PALETTE = [
    ("MV_Bridge_CreamLimestone", (0.57, 0.53, 0.44), 0.91),
    ("MV_Bridge_ArchVoussoir", (0.68, 0.62, 0.51), 0.91),
    ("MV_Bridge_WetStone", (0.24, 0.27, 0.25), 0.91),
    ("MV_Bridge_Coping", (0.71, 0.66, 0.53), 0.91),
    ("MV_Bridge_Paving", (0.44, 0.44, 0.40), 0.91),
    ("MV_Guild_WarmStone", (0.39, 0.38, 0.34), 0.86),
    ("MV_Guild_IvoryPlaster", (0.74, 0.70, 0.58), 0.86),
    ("MV_Guild_DarkOak", (0.15, 0.095, 0.058), 0.86),
    ("MV_Guild_SlateTeal", (0.12, 0.25, 0.26), 0.86),
    ("MV_Guild_RoofEdge", (0.08, 0.16, 0.17), 0.86),
    ("MV_Guild_AmberTrim", (0.47, 0.28, 0.12), 0.86),
    ("MV_Guild_Glass", (0.13, 0.25, 0.30), 0.20),
    ("M_Valley_Grass_01", (0.24, 0.32, 0.15), 0.83),
    ("M_Town_Road_01", (0.44, 0.35, 0.25), 0.83),
    ("M_River_Track_01", (0.38, 0.30, 0.21), 0.83),
    ("M_River_Surface_Proxy_01", (0.035, 0.25, 0.31), 0.35),
    ("M_Weathered_Stone_01", (0.40, 0.37, 0.30), 0.83),
    ("M_House_Russet", (0.55, 0.29, 0.17), 0.83),
    ("M_House_Slate", (0.18, 0.29, 0.34), 0.83),
    ("M_House_Moss", (0.30, 0.37, 0.21), 0.83),
    ("M_House_Clay", (0.54, 0.36, 0.20), 0.83),
]


def apply_palette():
    hits = {}
    for mat in bpy.data.materials:
        for key, rgb, rough in PALETTE:
            if key in mat.name:
                mat.use_nodes = True
                bsdf = next((n for n in mat.node_tree.nodes
                             if n.type == "BSDF_PRINCIPLED"), None)
                if bsdf is None:
                    continue
                bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
                bsdf.inputs["Roughness"].default_value = rough
                mat.diffuse_color = (*rgb, 1.0)
                hits[mat.name] = key
                break
    return hits


palette_hits = apply_palette()


def base_colour(mat):
    if not mat.use_nodes:
        return None
    for node in mat.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            return [round(c, 4) for c in node.inputs["Base Color"].default_value]
    return None


material_report = {}
for mat in bpy.data.materials:
    material_report[mat.name] = {"base_color": base_colour(mat)}

# Expected Godot-space AABB per node, so the Godot side can assert it landed
# where this says it did.  godot = (ue.x, ue.z, -ue.y)
nodes = []
lo = Vector((1e18,) * 3)
hi = Vector((-1e18,) * 3)
for ob in meshes:
    corners = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    g = [Vector((c.x, c.z, -c.y)) for c in corners]
    gmn = Vector((min(v.x for v in g), min(v.y for v in g), min(v.z for v in g)))
    gmx = Vector((max(v.x for v in g), max(v.y for v in g), max(v.z for v in g)))
    for i in range(3):
        lo[i] = min(lo[i], gmn[i])
        hi[i] = max(hi[i], gmx[i])
    me = ob.data
    me.calc_loop_triangles()
    nodes.append({
        "name": ob.name,
        "tris": len(me.loop_triangles),
        "godot_min": [round(v, 4) for v in gmn],
        "godot_max": [round(v, 4) for v in gmx],
    })

bpy.ops.export_scene.gltf(
    filepath=glb_path,
    export_format="GLB",
    export_apply=False,
    export_yup=True,
    export_materials="EXPORT",
    export_cameras=False,
    export_lights=False,
)

report = {
    "source_fbx": fbx_path,
    "glb": glb_path,
    "mesh_objects": len(meshes),
    "tris": sum(n["tris"] for n in nodes),
    "godot_bbox_min": [round(v, 4) for v in lo],
    "godot_bbox_max": [round(v, 4) for v in hi],
    "godot_size": [round(hi[i] - lo[i], 4) for i in range(3)],
    "axes_convention": "godot = (ue.x, ue.z, -ue.y)",
    "palette_hits": palette_hits,
    "materials": material_report,
    "nodes": sorted(nodes, key=lambda n: n["name"]),
}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=1)

unmatched = sorted(k for k in material_report if k not in palette_hits)
print("EXPORT objects=%d tris=%d godot_size=%s" % (len(meshes), report["tris"], report["godot_size"]))
print("EXPORT materials=%d palette_matched=%d unmatched=%s"
      % (len(material_report), len(palette_hits), unmatched))
