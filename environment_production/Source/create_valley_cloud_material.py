"""Art-directed finite cloud banks using the native volume renderer."""
import unreal

def create_cloud_material(tools,destination):
    mat=tools.create_asset('M_Valley_Cumulus',destination,unreal.Material,unreal.MaterialFactoryNew())
    assert mat
    mat.set_editor_property('material_domain',unreal.MaterialDomain.MD_VOLUME)
    mat.set_editor_property('used_with_volumetric_cloud',True)
    mat.set_editor_property('blend_mode',unreal.BlendMode.BLEND_ADDITIVE)
    edit=unreal.MaterialEditingLibrary
    albedo=edit.create_material_expression(mat,unreal.MaterialExpressionConstant3Vector)
    albedo.constant=unreal.LinearColor(.98,.98,.96,1)
    assert edit.connect_material_property(albedo,'',unreal.MaterialProperty.MP_BASE_COLOR)
    density=edit.create_material_expression(mat,unreal.MaterialExpressionCustom)
    density.set_editor_property('output_type',unreal.CustomMaterialOutputType.CMOT_FLOAT1)
    inputs=[]
    for name in ['P','T']:
        value=unreal.CustomInput();value.set_editor_property('input_name',name);inputs.append(value)
    density.set_editor_property('inputs',inputs)
    density.set_editor_property('code',r'''
float3 p = P * 0.00001;
p.x += T * 0.00015;
float3 centres[18] = {
float3(-1.4,-3.6,1.02),float3(-1.8,-3.6,1.23),float3(-1.35,-3.65,1.40),
float3(-.85,-3.62,1.23),float3(-.60,-3.7,1.08),float3(-1.18,-3.9,1.12),
float3(1.9,-4.7,1.04),float3(1.4,-4.7,1.24),float3(1.82,-4.65,1.48),
float3(2.25,-4.72,1.30),float3(2.6,-4.7,1.1),float3(2.05,-4.9,1.18),
float3(-2.8,2.9,1.03),float3(-3.3,2.9,1.22),float3(-2.85,2.85,1.44),
float3(-2.45,2.9,1.25),float3(-2.15,2.8,1.08),float3(-2.65,3.2,1.14)};
float3 radii[6] = {float3(.55,.6,.20),float3(.34,.45,.34),float3(.38,.42,.42),
float3(.35,.5,.30),float3(.28,.4,.18),float3(.42,.5,.25)};
float field = 0;
float erosion = .065 * sin(p.x*17.3+p.y*4.1) * sin(p.y*14.7-p.z*11.2)
              + .030 * sin(p.x*31.1-p.z*27.7) * sin(p.y*25.8+p.x*12.4);
for (int i=0;i<18;i++) {
    float d = length((p-centres[i])/radii[i%6]);
    field=max(field,1.0-d+erosion);
}
return .012*saturate(field*2.5);
''')
    position=edit.create_material_expression(mat,unreal.MaterialExpressionWorldPosition)
    clock=edit.create_material_expression(mat,unreal.MaterialExpressionTime);clock.set_editor_property('ignore_pause',True)
    assert edit.connect_material_expressions(position,'',density,'P')
    assert edit.connect_material_expressions(clock,'',density,'T')
    # Native VolumetricCloud.usf reads extinction from material subsurface RGB.
    assert edit.connect_material_property(density,'',unreal.MaterialProperty.MP_SUBSURFACE_COLOR)
    advanced=edit.create_material_expression(mat,unreal.MaterialExpressionVolumetricAdvancedMaterialOutput)
    for key,value in [('multi_scattering_approximation_octave_count',2),('const_multi_scattering_contribution',.65),
        ('const_multi_scattering_occlusion',.4),('const_multi_scattering_eccentricity',.25),('const_phase_g',.55),
        ('const_phase_blend',.2),('ray_march_volume_shadow',True)]:advanced.set_editor_property(key,value)
    edit.recompile_material(mat)
    assert unreal.EditorAssetLibrary.save_loaded_asset(mat)
    return mat
