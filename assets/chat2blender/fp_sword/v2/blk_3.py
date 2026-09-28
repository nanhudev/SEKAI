# --- REPLACE THE BLOCKOUT MATERIAL HELPERS WITH THIS VERSION ---

def principled(mat):
    mat.use_nodes = True

    for node in mat.node_tree.nodes:
        if node.type == 'BSDF_PRINCIPLED':
            return node

    nodes = mat.node_tree.nodes
    links = mat.node_tree.links

    bsdf = nodes.new("ShaderNodeBsdfPrincipled")

    output = None
    for node in nodes:
        if node.type == 'OUTPUT_MATERIAL':
            output = node
            break

    if output is None:
        output = nodes.new("ShaderNodeOutputMaterial")

    links.new(bsdf.outputs[0], output.inputs[0])
    return bsdf


def _socket_key(value):
    if not value:
        return ""
    return (
        str(value)
        .casefold()
        .replace(" ", "")
        .replace("_", "")
        .replace("-", "")
    )


def find_input(node, names, fallback_index=None):
    if isinstance(names, str):
        names = [names]

    wanted = {_socket_key(name) for name in names}

    # Prefer stable socket identifier; also accept localized display name.
    for socket in node.inputs:
        candidates = {
            _socket_key(getattr(socket, "identifier", "")),
            _socket_key(getattr(socket, "name", "")),
        }

        if wanted.intersection(candidates):
            return socket

    # Secondary fuzzy match, mainly useful for Emission Color /
    # Emission Strength across Blender 4.x / 5.x.
    for socket in node.inputs:
        candidates = (
            _socket_key(getattr(socket, "identifier", "")),
            _socket_key(getattr(socket, "name", "")),
        )

        for target in wanted:
            if not target:
                continue
            for candidate in candidates:
                if target in candidate or candidate in target:
                    return socket

    if fallback_index is not None:
        if 0 <= fallback_index < len(node.inputs):
            return node.inputs[fallback_index]

    return None


def set_input(node, names, value, fallback_index=None):
    socket = find_input(node, names, fallback_index=fallback_index)

    if socket is None:
        return False

    socket.default_value = value
    return True


def configure_principled(
    mat,
    base_color,
    metallic,
    roughness,
    emission_color=None,
    emission_strength=0.0
):
    bsdf = principled(mat)

    if not set_input(
        bsdf,
        ["Base Color", "BaseColor"],
        (*base_color, 1.0),
        fallback_index=0
    ):
        raise RuntimeError(f"Cannot resolve Base Color input for {mat.name}")

    if not set_input(
        bsdf,
        ["Metallic"],
        metallic,
        fallback_index=1
    ):
        raise RuntimeError(f"Cannot resolve Metallic input for {mat.name}")

    if not set_input(
        bsdf,
        ["Roughness"],
        roughness,
        fallback_index=2
    ):
        raise RuntimeError(f"Cannot resolve Roughness input for {mat.name}")

    if emission_color is not None:
        emission_ok = set_input(
            bsdf,
            ["Emission Color", "Emission"],
            (*emission_color, 1.0)
        )

        strength_ok = set_input(
            bsdf,
            ["Emission Strength", "EmissionStrength"],
            emission_strength
        )

        if not emission_ok:
            raise RuntimeError(
                f"Cannot resolve Emission Color input for {mat.name}"
            )

        if not strength_ok:
            raise RuntimeError(
                f"Cannot resolve Emission Strength input for {mat.name}"
            )

    mat.diffuse_color = (*base_color, 1.0)
    return mat


def make_material(
    name,
    base_color,
    metallic=0.0,
    roughness=0.5,
    emission_color=None,
    emission_strength=0.0
):
    mat = bpy.data.materials.get(name)

    if mat is None:
        mat = bpy.data.materials.new(name)

    mat.use_nodes = True

    configure_principled(
        mat,
        base_color=base_color,
        metallic=metallic,
        roughness=roughness,
        emission_color=emission_color,
        emission_strength=emission_strength
    )

    return mat