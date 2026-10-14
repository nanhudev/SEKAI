"""Import the authored valley in a new, isolated review map."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
import os
from pathlib import Path
import unreal

VERSION=os.environ.get('SEKAI_REVIEW_VERSION','v003')
ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/VERSION
manifest=json.loads((ROOT/'terrain_manifest.json').read_text())
DEST='/Game/Environment/Village/Landscape/'+VERSION
MAP='/Game/Environment/Village/Landscape/L_StarterValley_'+VERSION
if unreal.EditorAssetLibrary.does_asset_exist(MAP):
    raise RuntimeError('Map exists; use a new version before importing any assets')
for name in manifest['assets']:
    source=manifest.get('mesh_source_versions',{}).get(name)
    if source:
        path='/Game/Environment/Village/Landscape/'+source+'/'+name
        if not unreal.EditorAssetLibrary.does_asset_exist(path):
            raise RuntimeError('Shared mesh source is not imported: '+path)
    elif not (ROOT/(name+'.fbx')).is_file():
        raise RuntimeError('Local mesh file missing: '+name)
tools=unreal.AssetToolsHelpers.get_asset_tools()
import_world=unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
unreal.SystemLibrary.execute_console_command(import_world,'Interchange.FeatureFlags.Import.FBX 0')
palette={'MV_Valley_Grass':(.24,.31,.12),'MV_Valley_Cliff':(.31,.34,.33),
         'MV_Valley_Dirt':(.38,.30,.19),'MV_Valley_WetBank':(.15,.19,.16),
         'MV_Valley_Water_Prototype':(.025,.22,.24),'MV_Valley_Paving':(.39,.40,.34),
         'MV_Valley_Surface':(.24,.31,.12),'MV_Valley_Foam':(.78,.84,.80)}
materials={}
palette.update(manifest.get('material_palette',{}))
surface_textures={}
water_textures={}
detail_textures={}
terrain_textures={}
if manifest.get('terrain_detail_trial'):
    for row in manifest['terrain_detail_trial']['textures']:
        task=unreal.AssetImportTask();task.filename=str(_SEKAI_ROOT / row['file'])
        task.destination_path=DEST+'/Textures';task.destination_name='T_Terrain_'+row['asset']+'_'+row['map'];task.automated=True;task.save=True
        tools.import_asset_tasks([task]);texture=unreal.load_asset(task.destination_path+'/'+task.destination_name)
        assert isinstance(texture,unreal.Texture2D),task.filename
        texture.set_editor_property('srgb',row['map']=='Diffuse')
        if row['map']!='Diffuse':texture.set_editor_property('compression_settings',unreal.TextureCompressionSettings.TC_NORMALMAP if row['map']=='nor_dx' else unreal.TextureCompressionSettings.TC_MASKS)
        unreal.EditorAssetLibrary.save_loaded_asset(texture);terrain_textures[(row['asset'],row['map'])]=texture
for filename in manifest.get('authored_detail_textures',[]):
    task=unreal.AssetImportTask();task.filename=str(ROOT/(filename+'.png'))
    task.destination_path=DEST+'/Textures';task.destination_name=filename;task.automated=True;task.save=True
    tools.import_asset_tasks([task])
    texture=unreal.load_asset(DEST+'/Textures/'+filename)
    if not isinstance(texture,unreal.Texture2D):raise RuntimeError('Missing detail texture: '+filename)
    texture.set_editor_property('srgb',False)
    if filename.endswith('Normal'):
        texture.set_editor_property('compression_settings',unreal.TextureCompressionSettings.TC_NORMALMAP)
    unreal.EditorAssetLibrary.save_loaded_asset(texture);detail_textures[filename]=texture
if manifest.get('water_material_trial'):
    texture_files=[('Normal','T_Valley_Water_Normal'),('Foam','T_Valley_Foam_Mask')]
    if manifest.get('water_flow_texture'):texture_files.append(('Flow','T_Valley_Fall_Flow'))
    for key,filename in texture_files:
        task=unreal.AssetImportTask();task.filename=str(ROOT/(filename+'.png'))
        task.destination_path=DEST+'/Textures';task.destination_name=filename;task.automated=True;task.save=True
        tools.import_asset_tasks([task])
        texture=unreal.load_asset(DEST+'/Textures/'+filename)
        texture.set_editor_property('srgb',False)
        texture.set_editor_property('compression_settings',unreal.TextureCompressionSettings.TC_NORMALMAP if key=='Normal' else unreal.TextureCompressionSettings.TC_MASKS)
        unreal.EditorAssetLibrary.save_loaded_asset(texture);water_textures[key]=texture

def water_detail(mat,name,color):
    edit=unreal.MaterialEditingLibrary
    panner=edit.create_material_expression(mat,unreal.MaterialExpressionPanner)
    panner.set_editor_property('speed_y',-.18 if name=='MV_Valley_FallingWater' and manifest.get('water_animation_trial') else -.055)
    if name=='MV_Valley_Water_Prototype' and manifest.get('surface_water_flow'):
        panner.set_editor_property('speed_x',.018);panner.set_editor_property('speed_y',-.085)
    clock=edit.create_material_expression(mat,unreal.MaterialExpressionTime)
    clock.set_editor_property('ignore_pause',True)
    if manifest.get('water_clock_parameters'):
        enabled=edit.create_material_expression(mat,unreal.MaterialExpressionScalarParameter)
        enabled.set_editor_property('parameter_name','WaterUseRuntimeTime');enabled.set_editor_property('default_value',1.0)
        timed=edit.create_material_expression(mat,unreal.MaterialExpressionMultiply)
        assert edit.connect_material_expressions(clock,'',timed,'A')
        assert edit.connect_material_expressions(enabled,'',timed,'B')
        offset=edit.create_material_expression(mat,unreal.MaterialExpressionScalarParameter)
        offset.set_editor_property('parameter_name','WaterFlowTestTime');offset.set_editor_property('default_value',0.0)
        summed=edit.create_material_expression(mat,unreal.MaterialExpressionAdd)
        assert edit.connect_material_expressions(timed,'',summed,'A')
        assert edit.connect_material_expressions(offset,'',summed,'B')
        clock=summed
    assert edit.connect_material_expressions(clock,'',panner,'Time'),'Water clock connection failed'
    sample=edit.create_material_expression(mat,unreal.MaterialExpressionTextureSample)
    sample.set_editor_property('texture',water_textures['Normal'])
    sample.set_editor_property('sampler_type',unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL)
    assert edit.connect_material_expressions(panner,'',sample,'UVs'),'Water normal UV flow connection failed'
    assert edit.connect_material_property(sample,'RGB',unreal.MaterialProperty.MP_NORMAL),'Water normal output failed'
    if name=='MV_Valley_Water_Prototype':
        mat.set_editor_property('shading_model',unreal.MaterialShadingModel.MSM_SINGLE_LAYER_WATER)
        output=edit.create_material_expression(mat,unreal.MaterialExpressionSingleLayerWaterMaterialOutput)
        for pin,rgb in [('ScatteringCoefficients',(.001,.004,.005)),
                        ('AbsorptionCoefficients',(.025,.009,.006)),('ColorScaleBehindWater',(1,1,1))]:
            node=edit.create_material_expression(mat,unreal.MaterialExpressionConstant3Vector)
            node.constant=unreal.LinearColor(*rgb,1)
            if not edit.connect_material_expressions(node,'',output,pin):raise RuntimeError('Water output connection failed: '+pin)
        opacity=edit.create_material_expression(mat,unreal.MaterialExpressionConstant);opacity.r=.15
        edit.connect_material_property(opacity,'',unreal.MaterialProperty.MP_OPACITY)
        if manifest.get('surface_water_flow'):
            mask=edit.create_material_expression(mat,unreal.MaterialExpressionTextureSample)
            mask.texture=water_textures['Foam'];mask.sampler_type=unreal.MaterialSamplerType.SAMPLERTYPE_MASKS
            assert edit.connect_material_expressions(panner,'',mask,'UVs'),'Water surface foam UV flow connection failed'
            strength=edit.create_material_expression(mat,unreal.MaterialExpressionMultiply)
            strength.set_editor_property('const_b',.14);edit.connect_material_expressions(mask,'A',strength,'A')
            white=edit.create_material_expression(mat,unreal.MaterialExpressionConstant3Vector);white.constant=unreal.LinearColor(.38,.66,.63,1)
            mix=edit.create_material_expression(mat,unreal.MaterialExpressionLinearInterpolate)
            edit.connect_material_expressions(color,'',mix,'A');edit.connect_material_expressions(white,'',mix,'B')
            edit.connect_material_expressions(strength,'',mix,'Alpha');edit.connect_material_property(mix,'',unreal.MaterialProperty.MP_BASE_COLOR)
            rough=edit.create_material_expression(mat,unreal.MaterialExpressionConstant);rough.r=.34
            edit.connect_material_property(rough,'',unreal.MaterialProperty.MP_ROUGHNESS)
    else:
        mat.set_editor_property('two_sided',True)
        mask=edit.create_material_expression(mat,unreal.MaterialExpressionTextureSample)
        mask.set_editor_property('texture',water_textures.get('Flow',water_textures['Foam']) if name=='MV_Valley_FallingWater' else water_textures['Foam'])
        mask.set_editor_property('sampler_type',unreal.MaterialSamplerType.SAMPLERTYPE_MASKS)
        assert edit.connect_material_expressions(panner,'',mask,'UVs'),'Waterfall/foam UV flow connection failed'
        if name=='MV_Valley_Foam_Detail':
            mat.set_editor_property('blend_mode',unreal.BlendMode.BLEND_MASKED)
            mat.set_editor_property('opacity_mask_clip_value',.35)
            edit.connect_material_property(mask,'A',unreal.MaterialProperty.MP_OPACITY_MASK)
        else:
            white=edit.create_material_expression(mat,unreal.MaterialExpressionConstant3Vector)
            white.constant=unreal.LinearColor(.76,.85,.83,1)
            mix=edit.create_material_expression(mat,unreal.MaterialExpressionLinearInterpolate)
            edit.connect_material_expressions(color,'',mix,'A');edit.connect_material_expressions(white,'',mix,'B')
            edit.connect_material_expressions(mask,'A',mix,'Alpha')
            edit.connect_material_property(mix,'',unreal.MaterialProperty.MP_BASE_COLOR)
for material_name,texture_name in manifest.get('surface_color_textures',{}).items():
    task=unreal.AssetImportTask()
    task.filename=str(ROOT/(texture_name+'.png'));task.destination_path=DEST+'/Textures'
    task.destination_name=texture_name;task.automated=True;task.save=True
    tools.import_asset_tasks([task])
    texture=unreal.load_asset(DEST+'/Textures/'+texture_name)
    if not isinstance(texture,unreal.Texture2D):raise RuntimeError('Missing baked color texture: '+texture_name)
    texture.set_editor_property('srgb',False)
    unreal.EditorAssetLibrary.save_loaded_asset(texture)
    surface_textures[material_name]=texture
for name,rgb in palette.items():
    mat=tools.create_asset(name,DEST+'/Materials',unreal.Material,unreal.MaterialFactoryNew())
    color=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionConstant3Vector)
    color.constant=unreal.LinearColor(*rgb,1)
    unreal.MaterialEditingLibrary.connect_material_property(color,'',unreal.MaterialProperty.MP_BASE_COLOR)
    if name in surface_textures:
        sample=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionTextureSample)
        sample.set_editor_property('texture',surface_textures[name])
        sample.set_editor_property('sampler_type',unreal.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR)
        if not unreal.MaterialEditingLibrary.connect_material_property(sample,'RGB',unreal.MaterialProperty.MP_BASE_COLOR):
            raise RuntimeError('Baked terrain color failed to connect: '+name)
    elif name=='MV_Valley_Surface':
        vertex=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionVertexColor)
        if not unreal.MaterialEditingLibrary.connect_material_property(vertex,'',unreal.MaterialProperty.MP_BASE_COLOR):
            raise RuntimeError('Terrain vertex-color output failed to connect')
    rough=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionConstant)
    rough.r=(.25 if manifest.get('water_material_trial') else .18) if 'Water_Prototype' in name else .9
    unreal.MaterialEditingLibrary.connect_material_property(rough,'',unreal.MaterialProperty.MP_ROUGHNESS)
    if 'Foliage_Leaf' in name:
        mat.set_editor_property('two_sided',True)
        mat.set_editor_property('shading_model',unreal.MaterialShadingModel.MSM_TWO_SIDED_FOLIAGE)
        unreal.MaterialEditingLibrary.connect_material_property(color,'',unreal.MaterialProperty.MP_SUBSURFACE_COLOR)
    family=next((family for family in ['Timber','Stone','Plaster','Slate'] if family in name),None)
    if name=='MV_Tree_Bark':family='Timber'
    if family:
        folder='/Game/Environment/Village/Textures/OriginalSurfaces/T_VIL_'+family+'_'
        for kind,prop,output in [('Color',unreal.MaterialProperty.MP_BASE_COLOR,'RGB'),
                                 ('ORM',unreal.MaterialProperty.MP_ROUGHNESS,'G')]:
            texture=unreal.load_asset(folder+kind)
            if texture:
                sample=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionTextureSample)
                sample.set_editor_property('texture',texture)
                sampler=unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL if kind=='Normal' else (
                    unreal.MaterialSamplerType.SAMPLERTYPE_MASKS if kind=='ORM' else unreal.MaterialSamplerType.SAMPLERTYPE_COLOR)
                sample.set_editor_property('sampler_type',sampler)
                if kind=='Color':
                    soften=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionLinearInterpolate)
                    soften.set_editor_property('const_a',1.0);soften.set_editor_property('const_alpha',.22)
                    unreal.MaterialEditingLibrary.connect_material_expressions(sample,'RGB',soften,'B')
                    tint=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionMultiply)
                    unreal.MaterialEditingLibrary.connect_material_expressions(soften,'',tint,'A')
                    unreal.MaterialEditingLibrary.connect_material_expressions(color,'',tint,'B')
                    unreal.MaterialEditingLibrary.connect_material_property(tint,'',prop)
                else:unreal.MaterialEditingLibrary.connect_material_property(sample,output,prop)
    properties=manifest.get('material_properties',{}).get(name,{})
    for key,prop in [('roughness',unreal.MaterialProperty.MP_ROUGHNESS),
                     ('metallic',unreal.MaterialProperty.MP_METALLIC)]:
        if key in properties:
            node=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionConstant)
            node.r=properties[key]
            unreal.MaterialEditingLibrary.connect_material_property(node,'',prop)
    if 'emissive' in properties:
        node=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionConstant3Vector)
        node.constant=unreal.LinearColor(*properties['emissive'],1)
        unreal.MaterialEditingLibrary.connect_material_property(node,'',unreal.MaterialProperty.MP_EMISSIVE_COLOR)
    if 'normal_map' in properties:
        texture=unreal.load_asset(properties['normal_map'])
        if not isinstance(texture,unreal.Texture2D):raise RuntimeError('Authored surface normal missing: '+name)
        node=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionTextureSample)
        node.set_editor_property('texture',texture)
        node.set_editor_property('sampler_type',unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL)
        unreal.MaterialEditingLibrary.connect_material_property(node,'RGB',unreal.MaterialProperty.MP_NORMAL)
    for key,pin in [('detail_color_map',unreal.MaterialProperty.MP_BASE_COLOR),
                    ('detail_normal_map',unreal.MaterialProperty.MP_NORMAL),
                    ('detail_roughness_map',unreal.MaterialProperty.MP_ROUGHNESS)]:
        if key not in properties:continue
        node=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionTextureSample)
        node.set_editor_property('texture',detail_textures[properties[key]])
        node.set_editor_property('sampler_type',unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL if key=='detail_normal_map' else unreal.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR)
        output=node;channel='RGB' if key!='detail_roughness_map' else 'R'
        if key=='detail_color_map':
            output=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionMultiply)
            unreal.MaterialEditingLibrary.connect_material_expressions(color,'',output,'A')
            unreal.MaterialEditingLibrary.connect_material_expressions(node,'RGB',output,'B');channel=''
        unreal.MaterialEditingLibrary.connect_material_property(output,channel,pin)
    if water_textures and name in ['MV_Valley_Water_Prototype','MV_Valley_FallingWater','MV_Valley_Foam_Detail']:
        water_detail(mat,name,color)
    if terrain_textures and name in manifest['terrain_detail_trial']['materials']:
        import sys
        sys.path.insert(0,str(Path(__file__).parent))
        from terrain_surface_detail import apply_terrain_detail
        baked=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionTextureSample)
        baked.texture=surface_textures[name];baked.sampler_type=unreal.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR
        apply_terrain_detail(mat,baked,terrain_textures)
    unreal.MaterialEditingLibrary.recompile_material(mat)
    unreal.EditorAssetLibrary.save_loaded_asset(mat)
    materials[name]=mat
tasks=[]
for name in manifest['assets']:
    if name in manifest.get('mesh_source_versions',{}):continue
    task=unreal.AssetImportTask()
    task.filename=str(ROOT/(name+'.fbx'));task.destination_path=DEST
    task.destination_name=name;task.automated=True;task.save=True
    options=unreal.FbxImportUI()
    options.import_mesh=True;options.import_materials=False;options.import_textures=False
    options.import_as_skeletal=False
    options.mesh_type_to_import=unreal.FBXImportType.FBXIT_STATIC_MESH
    options.static_mesh_import_data.combine_meshes=True
    options.static_mesh_import_data.auto_generate_collision=False
    options.static_mesh_import_data.vertex_color_import_option=unreal.VertexColorImportOption.REPLACE
    task.options=options;tasks.append(task)
tools.import_asset_tasks(tasks)
level=unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
if unreal.EditorAssetLibrary.does_asset_exist(MAP):raise RuntimeError('Map exists; use a new version')
if not level.new_level(MAP):raise RuntimeError('Map creation failed')
actors=unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
def load_scene_mesh(name):
    source=manifest.get('mesh_source_versions',{}).get(name,VERSION)
    return unreal.load_asset('/Game/Environment/Village/Landscape/'+source+'/'+name)
for name in manifest['assets']:
    mesh=load_scene_mesh(name)
    if not isinstance(mesh,unreal.StaticMesh):raise RuntimeError('Mesh missing: '+name)
    slots=mesh.get_editor_property('static_materials')
    # Shared meshes are immutable: new actors override their materials without changing old maps.
    if name not in manifest.get('mesh_source_versions',{}):
        for index,slot in enumerate(slots):
            key=str(slot.get_editor_property('imported_material_slot_name'))
            mesh.set_material(index,materials[key])
        mesh.get_editor_property('body_setup').set_editor_property('collision_trace_flag',unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
        unreal.EditorAssetLibrary.save_loaded_asset(mesh)
    if name in manifest.get('library_assets',[]):continue
    actor=actors.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector())
    actor.set_actor_label(name);actor.set_folder_path('Village/Terrain')
    actor.static_mesh_component.set_static_mesh(mesh)
    for index,slot in enumerate(slots):
        key=str(slot.get_editor_property('imported_material_slot_name'))
        actor.static_mesh_component.set_material(index,materials[key])
    if 'Stream' in name or 'Foliage' in name or name in manifest.get('noncollision_assets',[]):
        actor.static_mesh_component.set_collision_enabled(unreal.CollisionEnabled.NO_COLLISION)
for index,row in enumerate(manifest.get('instances',[])):
    mesh=load_scene_mesh(row['mesh'])
    x,y,z=row['position_m'];actor=actors.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(x*100,-y*100,z*100))
    actor.set_actor_label('Forest_%03d'%index);actor.set_folder_path('Village/Vegetation')
    actor.static_mesh_component.set_static_mesh(mesh)
    actor.set_actor_rotation(unreal.Rotator(yaw=-row['yaw_degrees']),False)
    scale=row['scale'];actor.set_actor_scale3d(unreal.Vector(scale,scale,scale))
    actor.static_mesh_component.set_collision_enabled(unreal.CollisionEnabled.NO_COLLISION)
sun=actors.spawn_actor_from_class(unreal.DirectionalLight,unreal.Vector(0,0,2000))
sun.set_actor_rotation(unreal.Rotator(pitch=-35,yaw=-45,roll=0),False)
sun.light_component.set_editor_property('intensity',4.0)
sun.light_component.set_editor_property('intensity',75000.0)
sun.light_component.set_editor_property('atmosphere_sun_light',True)
lighting=manifest.get('review_lighting',{})
if 'sun_temperature_kelvin' in lighting:
    sun.light_component.set_editor_property('use_temperature',True)
    sun.light_component.set_editor_property('temperature',lighting['sun_temperature_kelvin'])
sun.light_component.set_mobility(unreal.ComponentMobility.MOVABLE)
sky=actors.spawn_actor_from_class(unreal.SkyLight,unreal.Vector(0,0,1500))
sky.light_component.set_mobility(unreal.ComponentMobility.MOVABLE)
sky.light_component.set_editor_property('real_time_capture',True)
sky.light_component.set_editor_property('intensity',lighting.get('sky_intensity',1.5))
atmosphere=actors.spawn_actor_from_class(unreal.SkyAtmosphere,unreal.Vector())
if 'sky_luminance_factor' in lighting:
    factor=lighting['sky_luminance_factor']
    atmosphere.get_component_by_class(unreal.SkyAtmosphereComponent).set_sky_luminance_factor(
        unreal.LinearColor(factor,factor,factor,1))
sky.light_component.recapture_sky()
if manifest.get('atmosphere_trial'):
    trial=manifest['atmosphere_trial']
    cloud=actors.spawn_actor_from_class(unreal.VolumetricCloud,unreal.Vector())
    cloud.set_actor_label('ATMOSPHERE_VolumetricClouds')
    cloud_component=cloud.get_component_by_class(unreal.VolumetricCloudComponent)
    cloud_material=unreal.load_asset('/Engine/EngineSky/VolumetricClouds/m_SimpleVolumetricCloud_Inst')
    if not cloud_material:raise RuntimeError('Engine volumetric cloud material missing')
    if trial.get('native_cumulus'):
        import sys
        sys.path.insert(0,str(Path(__file__).parent))
        from create_valley_cloud_material import create_cloud_material
        cloud_material=create_cloud_material(tools,DEST+'/Materials')
    elif trial.get('clone_engine_template'):
        cloud_material=unreal.EditorAssetLibrary.duplicate_asset('/Engine/EngineSky/VolumetricClouds/m_SimpleVolumetricCloud_Inst',DEST+'/Materials/MI_Valley_Clouds')
        if not cloud_material:raise RuntimeError('Cloud-template duplication failed')
    elif 'coverage' in trial:
        instance=tools.create_asset('MI_Valley_Clouds',DEST+'/Materials',unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew())
        parent=unreal.load_asset('/Engine/EngineSky/VolumetricClouds/m_SimpleVolumetricCloud')
        unreal.MaterialEditingLibrary.set_material_instance_parent(instance,parent)
        values=[]
        for name,key in [('Cloud_GlobalCoverage','coverage'),('Layout_CloudGlobalScale','global_scale'),('Cloud_GlobalDensity','global_density')]:
            info=unreal.MaterialParameterInfo(name=name,association=unreal.MaterialParameterAssociation.GLOBAL_PARAMETER,index=-1)
            values.append(unreal.ScalarParameterValue(parameter_info=info,parameter_value=trial[key]))
        instance.set_editor_property('scalar_parameter_values',values)
        unreal.MaterialEditingLibrary.update_material_instance(instance)
        unreal.EditorAssetLibrary.save_loaded_asset(instance);cloud_material=instance
    if trial.get('cloud_scalar_overrides'):
        values=list(cloud_material.get_editor_property('scalar_parameter_values'))
        names=set(trial['cloud_scalar_overrides'])
        values=[v for v in values if str(v.parameter_info.name) not in names]
        available={str(n) for n in unreal.MaterialEditingLibrary.get_scalar_parameter_names(cloud_material)}
        for name,value in trial['cloud_scalar_overrides'].items():
            assert name in available,name
            info=unreal.MaterialParameterInfo(name=name,association=unreal.MaterialParameterAssociation.GLOBAL_PARAMETER,index=-1)
            values.append(unreal.ScalarParameterValue(parameter_info=info,parameter_value=value))
        cloud_material.set_editor_property('scalar_parameter_values',values)
    if trial.get('cloud_vector_overrides'):
        values=list(cloud_material.get_editor_property('vector_parameter_values'))
        names=set(trial['cloud_vector_overrides'])
        values=[v for v in values if str(v.parameter_info.name) not in names]
        available={str(n) for n in unreal.MaterialEditingLibrary.get_vector_parameter_names(cloud_material)}
        for name,value in trial['cloud_vector_overrides'].items():
            assert name in available,name
            info=unreal.MaterialParameterInfo(name=name,association=unreal.MaterialParameterAssociation.GLOBAL_PARAMETER,index=-1)
            values.append(unreal.VectorParameterValue(parameter_info=info,parameter_value=unreal.LinearColor(*value)))
        cloud_material.set_editor_property('vector_parameter_values',values)
    if cloud_material.get_path_name().startswith(DEST+'/'):
        if isinstance(cloud_material,unreal.MaterialInstanceConstant):unreal.MaterialEditingLibrary.update_material_instance(cloud_material)
        assert unreal.EditorAssetLibrary.save_loaded_asset(cloud_material),'Cloud material was not persisted'
    cloud_component.set_material(cloud_material)
    cloud_component.set_editor_property('layer_bottom_altitude',trial['cloud_layer_bottom_km'])
    cloud_component.set_editor_property('layer_height',trial['cloud_layer_height_km'])
    fog=actors.spawn_actor_from_class(unreal.ExponentialHeightFog,unreal.Vector(0,0,0))
    fog.set_actor_label('ATMOSPHERE_LightDistanceHaze')
    fog_component=fog.get_component_by_class(unreal.ExponentialHeightFogComponent)
    fog_component.set_editor_property('fog_density',trial['haze_density'])
    fog_component.set_editor_property('fog_height_falloff',.20)
    fog_component.set_editor_property('start_distance',6000.0)
    fog_component.set_editor_property('fog_max_opacity',.16)
    (ROOT/'atmosphere_setup.json').write_text(json.dumps({'cloud_material':cloud_material.get_path_name(),
        'trial':trial,'note':'Cloud and distance-haze additions; sun/exposure/cameras retained. Requires actual captures.'},indent=2))
pp=actors.spawn_actor_from_class(unreal.PostProcessVolume,unreal.Vector())
pp.set_editor_property('unbound',True)
settings=pp.get_editor_property('settings')
settings.set_editor_property('override_auto_exposure_method',True)
settings.set_editor_property('auto_exposure_method',unreal.AutoExposureMethod.AEM_MANUAL)
settings.set_editor_property('override_auto_exposure_bias',True)
settings.set_editor_property('auto_exposure_bias',manifest.get('review_lighting',{}).get('exposure_bias',0.0))
for key,value in [('camera_iso',100.0),('camera_shutter_speed',125.0),('depth_of_field_fstop',16.0)]:
    settings.set_editor_property('override_'+key,True)
    settings.set_editor_property(key,value)
settings.set_editor_property('override_auto_exposure_apply_physical_camera_exposure',True)
settings.set_editor_property('auto_exposure_apply_physical_camera_exposure',True)
settings.set_editor_property('override_bloom_intensity',True)
settings.set_editor_property('bloom_intensity',0.0)
pp.set_editor_property('settings',settings)
for row in manifest['cameras']:
    pos=unreal.Vector(row['position_m'][0]*100,-row['position_m'][1]*100,row['position_m'][2]*100)
    target=unreal.Vector(row['target_m'][0]*100,-row['target_m'][1]*100,row['target_m'][2]*100)
    cam=actors.spawn_actor_from_class(unreal.CameraActor,pos)
    cam.set_actor_label(row['name']);cam.set_folder_path('Review/FixedCameras')
    cam.set_actor_rotation(unreal.MathLibrary.find_look_at_rotation(pos,target),False)
    cam.camera_component.set_editor_property('field_of_view',row['fov'])
p=manifest['cameras'][0]['position_m']
actors.spawn_actor_from_class(unreal.PlayerStart,unreal.Vector(p[0]*100,-p[1]*100,p[2]*100))
level.save_current_level()
(ROOT/'ue_import.json').write_text(json.dumps({'map':MAP,'assets':manifest['assets'],
    'status':'IMPORTED_NOT_VISUALLY_ACCEPTED','cameras':manifest['cameras']},indent=2))
print('SEKAI_VALLEY_IMPORTED',MAP)
