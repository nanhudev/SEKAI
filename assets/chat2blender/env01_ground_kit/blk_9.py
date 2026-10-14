if len(faces) != len(material_indices):
    raise RuntimeError(
        f"ENV-01: {name} face/material count mismatch "
        f"{len(faces)} != {len(material_indices)}"
    )

env01_remove_object(name)

mesh = bpy.data.meshes.new(name + "_MESH")
mesh.from_pydata(vertices, [], faces)
mesh.update(calc_edges=True)

if len(mesh.polygons) != len(material_indices):
    raise RuntimeError(
        f"ENV-01: polygon count mismatch on {name}"
    )

for mat in materials:
    if mat is None:
        raise RuntimeError(
            f"ENV-01: None material passed while building {name}"
        )
    mesh.materials.append(mat)

for poly, mat_index in zip(mesh.polygons, material_indices):
    if mat_index < 0 or mat_index >= len(materials):
        raise RuntimeError(
            f"ENV-01: bad material index {mat_index} on {name}"
        )
    poly.material_index = mat_index
    poly.use_smooth = False

obj = bpy.data.objects.new(name, mesh)
col = env01_get_collection()
col.objects.link(obj)

obj.location = (0.0, 0.0, 0.0)
obj.rotation_euler = (0.0, 0.0, 0.0)
obj.scale = (1.0, 1.0, 1.0)

obj["sekai_asset_id"] = "ENV-01"
obj["sekai_grid_m"] = 2.0
obj["sekai_origin_rule"] = origin_rule
obj["sekai_units"] = "metres"

env01_apply_transforms(obj)

if bevel_width > 0.0:
    env01_apply_bevel(obj, bevel_width, 1)

env01_flat_shade(obj)
env01_apply_transforms(obj)

return obj