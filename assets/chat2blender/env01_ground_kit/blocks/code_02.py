if mat is None:
    raise RuntimeError(f"ENV-01: failed to create material {name}")

mat.use_nodes = True

if mat.node_tree is None:
    raise RuntimeError(f"ENV-01: material {name} has no node tree")

bsdf = next(
    (n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'),
    None
)
if bsdf is None:
    raise RuntimeError(
        f"ENV-01: material {name} has no BSDF_PRINCIPLED node"
    )

base_socket = env01_find_socket(
    bsdf,
    ("Base Color", "BaseColor"),
    ("Base Color", "基础色", "基色")
)
metallic_socket = env01_find_socket(
    bsdf,
    ("Metallic",),
    ("Metallic", "金属度", "金属")
)
roughness_socket = env01_find_socket(
    bsdf,
    ("Roughness",),
    ("Roughness", "粗糙度")
)

base_socket.default_value = base_color
metallic_socket.default_value = metallic
roughness_socket.default_value = roughness

return mat