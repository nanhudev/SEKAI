mats = [
    _we_mat("MV_Stone_Base"),
    _we_mat("MV_Stone_Pale"),
    _we_mat("MV_Timber_Dark"),
    _we_mat("MV_Moss_Accent"),
]

mesh = bpy.data.meshes.new(name + "_MESH")
mesh.from_pydata(v, [], f)
mesh.update(calc_edges=True)

if len(mesh.polygons) != len(mi):
    raise RuntimeError(
        f"ENV-01 walls_edges: polygon/material mismatch on {name}"
    )

for mat in mats:
    mesh.materials.append(mat)

for poly, idx in zip(mesh.polygons, mi):
    poly.material_index = idx
    poly.use_smooth = False

obj = bpy.data.objects.new(name, mesh)
_we_collection().objects.link(obj)

obj.location = (0.0, 0.0, 0.0)
obj.rotation_euler = (0.0, 0.0, 0.0)
obj.scale = (1.0, 1.0, 1.0)

obj["sekai_asset_id"] = "ENV-01"
obj["sekai_grid_m"] = 2.0
obj["sekai_origin_rule"] = origin_rule

bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.object.transform_apply(
    location=False,
    rotation=True,
    scale=True
)

if bevel > 0:
    mod = obj.modifiers.new("ENV01_Chamfer", 'BEVEL')
    mod.width = bevel
    mod.segments = 1
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(20)

    try:
        bpy.ops.object.modifier_apply(modifier=mod.name)
    except Exception as exc:
        raise RuntimeError(
            f"ENV-01 walls_edges: bevel failed on {name}: {exc}"
        ) from exc

for poly in obj.data.polygons:
    poly.use_smooth = False

obj.rotation_euler = (0.0, 0.0, 0.0)
obj.scale = (1.0, 1.0, 1.0)

return obj