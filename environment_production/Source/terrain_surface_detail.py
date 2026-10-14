"""Slope-blended world-space detail; authored valley color remains the palette."""
import unreal

def apply_terrain_detail(mat, baked_color, textures):
    edit=unreal.MaterialEditingLibrary
    def node(kind):return edit.create_material_expression(mat,getattr(unreal,'MaterialExpression'+kind))
    def link(a,out,b,pin):
        names=list(edit.get_material_expression_input_names(b))
        if pin not in names and len(names)==1:pin=names[0]
        assert edit.connect_material_expressions(a,out,b,pin),(out,pin)
    def scalar(value):
        n=node('Constant');n.r=value;return n
    def vector(values):
        n=node('Constant3Vector');n.constant=unreal.LinearColor(*values,1);return n
    def projected(asset,kind,size):
        tex=node('TextureObject');tex.texture=textures[(asset,kind)]
        tex.sampler_type=(unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL if kind=='nor_dx' else
                          unreal.MaterialSamplerType.SAMPLERTYPE_MASKS if kind=='Rough' else unreal.MaterialSamplerType.SAMPLERTYPE_COLOR)
        call=node('MaterialFunctionCall')
        normal=kind=='nor_dx'
        call.set_editor_property('material_function',unreal.load_asset('/Engine/Functions/Engine_MaterialFunctions01/Texturing/'+('WorldAlignedNormal' if normal else 'WorldAlignedTexture')))
        link(tex,'',call,'TextureObject');link(vector((size,size,size)),'',call,'TextureSize')
        return call
    nz=node('ComponentMask')
    for key,value in [('r',False),('g',False),('b',True),('a',False)]:nz.set_editor_property(key,value)
    link(node('VertexNormalWS'),'',nz,'Input')
    absolute=node('Abs');link(nz,'',absolute,'Input')
    offset=node('Subtract');link(absolute,'',offset,'A');link(scalar(.45),'',offset,'B')
    scale=node('Multiply');link(offset,'',scale,'A');link(scalar(2.5),'',scale,'B')
    slope=node('Saturate');link(scale,'',slope,'Input')
    def blended(kind):
        mix=node('LinearInterpolate')
        link(projected('rock_face_03',kind,450),'XYZ Texture',mix,'A')
        link(projected('grass_ground',kind,300),'XYZ Texture',mix,'B')
        link(slope,'',mix,'Alpha');return mix
    diffuse=blended('Diffuse')
    luminance=node('DotProduct');link(diffuse,'',luminance,'A');link(vector((.2126,.7152,.0722)),'',luminance,'B')
    strength=node('Multiply');link(luminance,'',strength,'A');link(scalar(.9),'',strength,'B')
    bias=node('Add');link(strength,'',bias,'A');link(scalar(.8),'',bias,'B')
    color=node('Multiply');link(baked_color,'RGB',color,'A');link(bias,'',color,'B')
    assert edit.connect_material_property(color,'',unreal.MaterialProperty.MP_BASE_COLOR)
    normals=blended('nor_dx');normalized=node('Normalize');link(normals,'',normalized,'VectorInput')
    mat.set_editor_property('tangent_space_normal',False)
    assert edit.connect_material_property(normalized,'',unreal.MaterialProperty.MP_NORMAL)
    rough=blended('Rough')
    assert edit.connect_material_property(rough,'',unreal.MaterialProperty.MP_ROUGHNESS)
