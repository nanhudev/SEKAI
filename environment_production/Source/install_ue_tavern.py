"""Import the original tavern into its isolated UE review map."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import unreal
import json
import os
from pathlib import Path

ROOT=Path(str(_SEKAI_ROOT / 'environment_production'))
VERSION=os.environ.get('SEKAI_REVIEW_VERSION','v001')
NAME='SM_VIL_Hero_Tavern_'+VERSION
DEST='/Game/Environment/Village/Hero'
MAP='/Game/Environment/Village/Review/L_Tavern_'+VERSION
tools=unreal.AssetToolsHelpers.get_asset_tools()
task=unreal.AssetImportTask()
task.filename=str(ROOT/'Versions'/VERSION/(NAME+'.fbx'))
task.destination_path=DEST
task.destination_name=NAME
task.automated=True
task.replace_existing=False
task.save=True
options=unreal.FbxImportUI()
options.import_mesh=True
options.import_materials=False
options.import_textures=False
options.import_as_skeletal=False
options.mesh_type_to_import=unreal.FBXImportType.FBXIT_STATIC_MESH
options.static_mesh_import_data.combine_meshes=True
options.static_mesh_import_data.import_uniform_scale=1.0
task.options=options
mesh=unreal.load_asset(DEST+'/'+NAME) if unreal.EditorAssetLibrary.does_asset_exist(DEST+'/'+NAME) else None
if not mesh:tools.import_asset_tasks([task])
paths=task.imported_object_paths
mesh=mesh or next((unreal.load_asset(p) for p in paths if isinstance(unreal.load_asset(p),unreal.StaticMesh)),None)
if not mesh:raise RuntimeError('No imported tavern mesh: '+str(paths))
palette={
 'MV_Plaster_Warm':((.68,.60,.43),.85,0),
 'MV_Timber_Dark':((.15,.075,.033),.72,0),
 'MV_Timber_Warm':((.32,.17,.07),.77,0),
 'MV_Metal_BlackIron':((.035,.043,.047),.46,.8),
 'MV_Window_Amber':((.6,.29,.055),.28,0),
}
for i,c in enumerate([(.36,.37,.34),(.43,.42,.36),(.30,.33,.33),(.49,.46,.38)]):palette['MV_Stone_'+str(i)]=(c,.9,0)
for i,c in enumerate([(.10,.16,.21),(.14,.21,.27),(.19,.24,.28),(.12,.18,.23),(.22,.25,.25)]):palette['MV_Roof_Slate_'+str(i)]=(c,.76,0)
materials={}
surface_textures={}
if VERSION not in ['v001','v002','v003','v004']:
    texture_tasks=[]
    for family in ['Timber','Stone','Plaster','Slate']:
        for kind in ['Color','Normal','ORM']:
            name='T_VIL_'+family+'_'+kind
            folder='/Game/Environment/Village/Textures/OriginalSurfaces'
            tex=unreal.load_asset(folder+'/'+name) if unreal.EditorAssetLibrary.does_asset_exist(folder+'/'+name) else None
            if not tex:
                t=unreal.AssetImportTask();t.filename=str(ROOT/'Materials'/'v001'/(name+'.png'))
                t.destination_path=folder;t.destination_name=name;t.automated=True;t.save=True
                texture_tasks.append(t)
    if texture_tasks:tools.import_asset_tasks(texture_tasks)
    for family in ['Timber','Stone','Plaster','Slate']:
        for kind in ['Color','Normal','ORM']:
            tex=unreal.load_asset('/Game/Environment/Village/Textures/OriginalSurfaces/T_VIL_'+family+'_'+kind)
            if not tex:raise RuntimeError('Missing original surface texture')
            tex.set_editor_property('srgb',kind=='Color')
            if kind=='Normal':tex.set_editor_property('compression_settings',unreal.TextureCompressionSettings.TC_NORMALMAP)
            elif kind=='ORM':tex.set_editor_property('compression_settings',unreal.TextureCompressionSettings.TC_MASKS)
            unreal.EditorAssetLibrary.save_loaded_asset(tex)
            surface_textures[(family,kind)]=tex
for name,(rgb,rough,metallic) in palette.items():
    folder='/Game/Environment/Village/Materials/'+('OriginalPBR_v001' if surface_textures else 'Review')
    mat=unreal.load_asset(folder+'/'+name)
    if not mat:
        mat=tools.create_asset(name,folder,unreal.Material,unreal.MaterialFactoryNew())
        color=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionConstant3Vector,-350,0)
        color.constant=unreal.LinearColor(*rgb,1)
        unreal.MaterialEditingLibrary.connect_material_property(color,'',unreal.MaterialProperty.MP_BASE_COLOR)
        for prop,value,y in [(unreal.MaterialProperty.MP_ROUGHNESS,rough,180),(unreal.MaterialProperty.MP_METALLIC,metallic,300)]:
            n=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionConstant,-350,y)
            n.r=value;unreal.MaterialEditingLibrary.connect_material_property(n,'',prop)
        if name=='MV_Window_Amber':unreal.MaterialEditingLibrary.connect_material_property(color,'',unreal.MaterialProperty.MP_EMISSIVE_COLOR)
        family=next((f for f in ['Timber','Stone','Plaster','Slate'] if f in name),None)
        if family and surface_textures:
            samples={}
            for j,kind in enumerate(['Color','Normal','ORM']):
                sample=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionTextureSample,-800,j*240)
                sample.set_editor_property('texture',surface_textures[(family,kind)])
                sample.set_editor_property('sampler_type',unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL if kind=='Normal' else (unreal.MaterialSamplerType.SAMPLERTYPE_MASKS if kind=='ORM' else unreal.MaterialSamplerType.SAMPLERTYPE_COLOR))
                samples[kind]=sample
            multiply=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionMultiply,-200,0)
            unreal.MaterialEditingLibrary.connect_material_expressions(samples['Color'],'RGB',multiply,'A')
            unreal.MaterialEditingLibrary.connect_material_expressions(color,'',multiply,'B')
            unreal.MaterialEditingLibrary.connect_material_property(multiply,'',unreal.MaterialProperty.MP_BASE_COLOR)
            unreal.MaterialEditingLibrary.connect_material_property(samples['Normal'],'RGB',unreal.MaterialProperty.MP_NORMAL)
            unreal.MaterialEditingLibrary.connect_material_property(samples['ORM'],'G',unreal.MaterialProperty.MP_ROUGHNESS)
            unreal.MaterialEditingLibrary.connect_material_property(samples['ORM'],'R',unreal.MaterialProperty.MP_AMBIENT_OCCLUSION)
        unreal.MaterialEditingLibrary.recompile_material(mat)
        unreal.EditorAssetLibrary.save_loaded_asset(mat)
    materials[name]=mat
slots=[]
static_materials=mesh.get_editor_property('static_materials')
for i,slot in enumerate(static_materials):
    name=str(slot.get_editor_property('imported_material_slot_name'))
    matching=next((k for k in palette if name==k or name.endswith(k)),None)
    if not matching:raise RuntimeError('Unknown material slot: '+name)
    slot.set_editor_property('material_interface',materials[matching]);slots.append(name)
mesh.set_editor_property('static_materials',static_materials)
mesh.get_editor_property('body_setup').set_editor_property('collision_trace_flag',unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
unreal.EditorAssetLibrary.save_loaded_asset(mesh)
level=unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
if unreal.EditorAssetLibrary.does_asset_exist(MAP):raise RuntimeError('Review version already exists; create another version.')
if not level.new_level(MAP):raise RuntimeError('Unable to create review map')
actors=unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
hero=actors.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(0,0,0))
hero.set_actor_label(NAME);hero.set_folder_path('Village/Hero/Tavern')
hero.static_mesh_component.set_static_mesh(mesh)
floor=actors.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(0,0,-15))
floor.set_actor_label('REVIEW_Ground');floor.static_mesh_component.set_static_mesh(unreal.load_asset('/Engine/BasicShapes/Cube'))
floor.set_actor_scale3d(unreal.Vector(100,100,.2));floor.static_mesh_component.set_material(0,materials['MV_Stone_1'])
sun=actors.spawn_actor_from_class(unreal.DirectionalLight,unreal.Vector(0,0,2000))
sun.set_actor_label('REVIEW_MorningSun');sun.set_actor_rotation(unreal.Rotator(pitch=-35,yaw=-35,roll=0),False)
sun.light_component.set_editor_property('intensity',4.0)
sky=actors.spawn_actor_from_class(unreal.SkyLight,unreal.Vector(0,0,1500))
sky.light_component.set_editor_property('real_time_capture',True)
sky.light_component.set_editor_property('intensity',1.0)
actors.spawn_actor_from_class(unreal.SkyAtmosphere,unreal.Vector(0,0,0))
pp=actors.spawn_actor_from_class(unreal.PostProcessVolume,unreal.Vector(0,0,0))
pp.set_editor_property('unbound',True)
settings=pp.get_editor_property('settings')
settings.set_editor_property('override_auto_exposure_method',True)
settings.set_editor_property('auto_exposure_method',unreal.AutoExposureMethod.AEM_MANUAL)
settings.set_editor_property('override_auto_exposure_bias',True)
settings.set_editor_property('auto_exposure_bias',9.0)
settings.set_editor_property('override_bloom_intensity',True)
settings.set_editor_property('bloom_intensity',0.0)
pp.set_editor_property('settings',settings)
cameras=[('CAM_HERO_01_ThreeQuarter',(2100,-3000,1600),(0,-100,500)),
         ('CAM_HERO_02_Front',(0,-2850,650),(0,-100,530)),
         ('CAM_HERO_03_FirstPerson',(550,-1850,170),(0,-650,310)),
         ('CAM_HERO_04_Door_Close',(260,-1040,170),(0,-670,180)),
         ('CAM_HERO_05_Roof',(2100,-1000,1300),(0,0,760))]
for name,pos,target in cameras:
    cam=actors.spawn_actor_from_class(unreal.CameraActor,unreal.Vector(*pos))
    cam.set_actor_label(name);cam.set_folder_path('Review/FixedCameras')
    cam.set_actor_rotation(unreal.MathLibrary.find_look_at_rotation(unreal.Vector(*pos),unreal.Vector(*target)),False)
    cam.camera_component.set_editor_property('field_of_view',50.0 if 'FirstPerson' not in name else 75.0)
level.save_current_level()
report={'version':VERSION,'map':MAP,'mesh':mesh.get_path_name(),'material_slots':slots,'original_pbr_maps':bool(surface_textures),
        'status':'STRUCTURE_REVIEW_NOT_FINAL','cameras':[r[0] for r in cameras]}
(ROOT/'Versions'/VERSION/'ue_import.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('SEKAI_IMPORT_OK',json.dumps(report))
