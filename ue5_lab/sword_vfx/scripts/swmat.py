"""SEKAI UE5 Sword VFX - master material graph builder.

Builds the M_SW_* master materials from a declarative spec so the graph, the
parameter names and the Niagara usage flags stay in one place instead of being
clicked into six assets by hand.

Blend model, and why:

    M_SW_Trail / Wave / SpatialScar / Mist  -> Translucent AlphaComposite, Unlit
    M_SW_Glint / Mote                       -> Additive, Unlit

AlphaComposite for the sheets is a deliberate correctness choice, not a style
one. The brief requires every effect to hold on a bright background, and a
purely additive stroke is invisible against white. Alpha composite lets a
saturated stroke cover the background, and it is the only way the magic sword's
"darkness leaks through the cut" can read at all - the void has to *darken*.

Channel convention, matched to the texture generator:
    R = CORE, G = GLOW, B = DETAIL, A = MASK.
"""
import unreal

MEL = unreal.MaterialEditingLibrary


def make_material(asset_path, name):
    """Create an empty material, replacing anything already there."""
    if unreal.EditorAssetLibrary.does_asset_exist("%s/%s" % (asset_path, name)):
        unreal.EditorAssetLibrary.delete_asset("%s/%s" % (asset_path, name))
    factory = unreal.MaterialFactoryNew()
    return unreal.AssetToolsHelpers.get_asset_tools().create_asset(
        name, asset_path, unreal.Material, factory)


def set_prop(obj, name, value, required=False):
    """set_editor_property that tolerates a missing/renamed property."""
    try:
        obj.set_editor_property(name, value)
        return True
    except Exception as exc:
        if required:
            raise
        return False


def vec(mat, name, x, y, z, a=1.0, px=-900, py=0):
    n = MEL.create_material_expression(mat, unreal.MaterialExpressionVectorParameter, px, py)
    n.set_editor_property("parameter_name", name)
    n.set_editor_property("default_value", unreal.LinearColor(x, y, z, a))
    return n


def scal(mat, name, value, px=-900, py=0):
    n = MEL.create_material_expression(mat, unreal.MaterialExpressionScalarParameter, px, py)
    n.set_editor_property("parameter_name", name)
    n.set_editor_property("default_value", float(value))
    return n


def tex(mat, name, px=-1400, py=0):
    n = MEL.create_material_expression(mat, unreal.MaterialExpressionTextureSampleParameter2D,
                                        px, py)
    n.set_editor_property("parameter_name", name)
    return n


def const(mat, value, px, py):
    n = MEL.create_material_expression(mat, unreal.MaterialExpressionConstant, px, py)
    n.set_editor_property("r", float(value))
    return n


def const3(mat, x, y, z, px, py):
    n = MEL.create_material_expression(mat, unreal.MaterialExpressionConstant3Vector, px, py)
    n.set_editor_property("constant", unreal.LinearColor(x, y, z, 1.0))
    return n


def op(mat, cls, px, py):
    return MEL.create_material_expression(mat, cls, px, py)


def wire(a, a_out, b, b_in=""):
    MEL.connect_material_expressions(a, a_out, b, b_in)
    return b


def material_property(name):
    """Resolve an EMaterialProperty, accepting either the enum or a plain string.

    `connect_material_property` takes the ENUM. Passing the string "BASE_COLOR"
    raises

        TypeError: NativizeEnumEntry: Cannot nativize 'str' as 'MaterialProperty'

    and in an editor session that error is logged and then swallowed while the
    editor stays open - so the symptom is a process that appears to hang at the
    exact point the typo is, with no trace in the script's own log. That cost
    two engine launches and one wrong root-cause theory before the commandlet's
    log named it. Resolving here, and printing the valid members when the name
    does not exist, means the next occurrence is a one-line read instead.

    Exact match on MP_<NAME> only. Deliberately not fuzzy: a near-miss that
    silently connected the wrong channel would be far worse than an exception.
    """
    if not isinstance(name, str):
        return name
    key = name.upper()
    if not key.startswith("MP_"):
        key = "MP_" + key
    try:
        return getattr(unreal.MaterialProperty, key)
    except AttributeError:
        valid = sorted(a for a in dir(unreal.MaterialProperty)
                       if a.startswith("MP_"))
        raise ValueError(
            "unknown material property %r (tried %s). valid: %s"
            % (name, key, ", ".join(valid)))


def to_property(expr, out, prop):
    MEL.connect_material_property(expr, out, material_property(prop))


def one_minus(mat, expr, out, px, py):
    n = op(mat, unreal.MaterialExpressionOneMinus, px, py)
    return wire(expr, out, n, "")


# --------------------------------------------------------------------------
# the sheet material: core + glow + detail, with an optional dark void term
# --------------------------------------------------------------------------

def build_sheet_material(asset_path, name, additive=False, two_sided=True,
                         fresnel_edge=False, dark_term=True):
    """CORE/GLOW/DETAIL material used by trail, wave, scar and mist."""
    mat = make_material(asset_path, name)
    set_prop(mat, "shading_model", unreal.MaterialShadingModel.MSM_UNLIT)
    set_prop(mat, "blend_mode",
             unreal.BlendMode.BLEND_ADDITIVE if additive
             else unreal.BlendMode.BLEND_TRANSLUCENT)
    # NOTE: blendable_location is deliberately left at the engine default. The
    # enum member names move between 5.x releases, this is a post-process
    # concern rather than a sword-VFX one, and guessing it once aborted the
    # build of every sheet material before a single node was wired.
    set_prop(mat, "two_sided", two_sided)
    # minimal usage flags - each one costs a shader permutation
    set_prop(mat, "used_with_niagara_sprites", True)
    set_prop(mat, "used_with_niagara_ribbons", True)
    set_prop(mat, "used_with_niagara_mesh_particles", True)

    # ---- parameters
    p_primary = vec(mat, "PrimaryColor", 0.72, 0.86, 1.00, 1.0, -1900, -700)
    p_core = vec(mat, "CoreColor", 1.00, 1.00, 1.00, 1.0, -1900, -480)
    p_dark = vec(mat, "DarkColor", 0.010, 0.012, 0.030, 1.0, -1900, -260)
    p_intensity = scal(mat, "Intensity", 1.0, -1900, -40)
    p_core_power = scal(mat, "CorePower", 3.0, -1900, 140)
    p_opacity = scal(mat, "Opacity", 1.0, -1900, 320)
    p_void = scal(mat, "VoidAmount", 0.0, -1900, 500)
    p_edge = scal(mat, "EdgeFalloff", 0.0, -1900, 680)

    mask = tex(mat, "MaskTex", -1900, 900)

    # ---- core = R^CorePower * CoreColor
    core_p = op(mat, unreal.MaterialExpressionPower, -1400, -700)
    wire(mask, "R", core_p, "Base")
    wire(p_core_power, "", core_p, "Exponent")

    core_col = op(mat, unreal.MaterialExpressionMultiply, -1150, -700)
    wire(core_p, "", core_col, "A")
    wire(p_core, "", core_col, "B")

    # ---- glow = G * PrimaryColor
    glow_col = op(mat, unreal.MaterialExpressionMultiply, -1150, -400)
    wire(mask, "G", glow_col, "A")
    wire(p_primary, "", glow_col, "B")

    # ---- detail (B) feeds the dark/void term
    detail_dark = op(mat, unreal.MaterialExpressionMultiply, -1150, -100)
    wire(mask, "B", detail_dark, "A")
    wire(p_dark, "", detail_dark, "B")
    detail_void = op(mat, unreal.MaterialExpressionMultiply, -900, -100)
    wire(detail_dark, "", detail_void, "A")
    wire(p_void, "", detail_void, "B")

    if dark_term:
        emissive_sum = op(mat, unreal.MaterialExpressionAdd, -700, -600)
        wire(core_col, "", emissive_sum, "A")
        wire(glow_col, "", emissive_sum, "B")
        emissive = op(mat, unreal.MaterialExpressionAdd, -450, -600)
        wire(emissive_sum, "", emissive, "A")
        wire(detail_void, "", emissive, "B")
    else:
        emissive = op(mat, unreal.MaterialExpressionAdd, -450, -600)
        wire(core_col, "", emissive, "A")
        wire(glow_col, "", emissive, "B")

    emissive_i = op(mat, unreal.MaterialExpressionMultiply, -250, -600)
    wire(emissive, "", emissive_i, "A")
    wire(p_intensity, "", emissive_i, "B")

    # ---- opacity = A * Opacity  (additive ignores it but keeps the param graph identical)
    opacity = op(mat, unreal.MaterialExpressionMultiply, -450, 600)
    wire(mask, "A", opacity, "A")
    wire(p_opacity, "", opacity, "B")

    if fresnel_edge:
        # a flat sheet seen edge-on becomes a hard line; fade opacity with the
        # grazing angle so the sheet dissolves instead. EdgeFalloff=0 restores
        # the plain behaviour, so one material covers both needs.
        fres = op(mat, unreal.MaterialExpressionFresnel, -1000, 900)
        set_prop(fres, "exponent", 6.0)
        inv = one_minus(mat, fres, "", -800, 900)
        one_c = const(mat, 1.0, -1000, 1150)
        edge_lerp = op(mat, unreal.MaterialExpressionLinearInterpolate, -650, 900)
        wire(one_c, "", edge_lerp, "A")
        wire(inv, "", edge_lerp, "B")
        wire(p_edge, "", edge_lerp, "Alpha")
        final_op = op(mat, unreal.MaterialExpressionMultiply, -420, 780)
        wire(opacity, "", final_op, "A")
        wire(edge_lerp, "", final_op, "B")
        to_property(final_op, "", unreal.MaterialProperty.MP_OPACITY)
    else:
        to_property(opacity, "", unreal.MaterialProperty.MP_OPACITY)

    to_property(emissive_i, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)
    MEL.recompile_material(mat)
    return mat


def build_glint_material(asset_path, name, additive=True):
    """Sparkle material: a hot core with a small tinted halo. No dark term."""
    mat = make_material(asset_path, name)
    set_prop(mat, "shading_model", unreal.MaterialShadingModel.MSM_UNLIT)
    set_prop(mat, "blend_mode",
             unreal.BlendMode.BLEND_ADDITIVE if additive
             else unreal.BlendMode.BLEND_TRANSLUCENT)
    set_prop(mat, "two_sided", True)
    set_prop(mat, "used_with_niagara_sprites", True)
    set_prop(mat, "used_with_niagara_ribbons", True)
    set_prop(mat, "used_with_niagara_mesh_particles", True)

    p_primary = vec(mat, "PrimaryColor", 0.80, 0.92, 1.00, 1.0, -1900, -500)
    p_core = vec(mat, "CoreColor", 1.00, 1.00, 1.00, 1.0, -1900, -280)
    p_intensity = scal(mat, "Intensity", 1.0, -1900, -40)
    p_core_power = scal(mat, "CorePower", 1.6, -1900, 140)
    p_opacity = scal(mat, "Opacity", 1.0, -1900, 320)

    mask = tex(mat, "MaskTex", -1900, 800)

    core_p = op(mat, unreal.MaterialExpressionPower, -1400, -500)
    wire(mask, "R", core_p, "Base")
    wire(p_core_power, "", core_p, "Exponent")
    core_col = op(mat, unreal.MaterialExpressionMultiply, -1150, -500)
    wire(core_p, "", core_col, "A")
    wire(p_core, "", core_col, "B")
    glow_col = op(mat, unreal.MaterialExpressionMultiply, -1150, -250)
    wire(mask, "G", glow_col, "A")
    wire(p_primary, "", glow_col, "B")
    emissive = op(mat, unreal.MaterialExpressionAdd, -700, -400)
    wire(core_col, "", emissive, "A")
    wire(glow_col, "", emissive, "B")
    emissive_i = op(mat, unreal.MaterialExpressionMultiply, -450, -400)
    wire(emissive, "", emissive_i, "A")
    wire(p_intensity, "", emissive_i, "B")

    opacity = op(mat, unreal.MaterialExpressionMultiply, -450, 400)
    wire(mask, "A", opacity, "A")
    wire(p_opacity, "", opacity, "B")

    to_property(emissive_i, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)
    to_property(opacity, "", unreal.MaterialProperty.MP_OPACITY)
    MEL.recompile_material(mat)
    return mat


def build_instance(parent, asset_path, name, params=None):
    """Create (or replace) a material instance constant off a parent material."""
    full = "%s/%s" % (asset_path, name)
    if unreal.EditorAssetLibrary.does_asset_exist(full):
        unreal.EditorAssetLibrary.delete_asset(full)
    factory = unreal.MaterialInstanceConstantFactoryNew()
    mi = unreal.AssetToolsHelpers.get_asset_tools().create_asset(
        name, asset_path, unreal.MaterialInstanceConstant, factory)
    mi.set_editor_property("parent", parent)
    for key, value in (params or {}).items():
        if isinstance(value, (tuple, list)):
            MEL.set_material_instance_vector_parameter_value(
                mi, key, unreal.LinearColor(*value))
        elif isinstance(value, float):
            MEL.set_material_instance_scalar_parameter_value(mi, key, value)
        elif value is not None:
            MEL.set_material_instance_texture_parameter_value(mi, key, value)
    return mi
