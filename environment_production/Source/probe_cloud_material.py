from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import unreal,json
from pathlib import Path
edit=unreal.MaterialEditingLibrary
paths=['/Engine/EngineSky/VolumetricClouds/m_SimpleVolumetricCloud_Inst','/Game/Environment/Village/Landscape/v078/Materials/MI_Valley_Clouds']
data={}
for path in paths:
    instance=unreal.load_asset(path)
    if not instance:
        data[path]={'exists':False};continue
    parent=instance.get_editor_property('parent')
    row={'parent':parent.get_path_name(),'scalars':{},'vectors':{},'textures':{}}
    for n in edit.get_scalar_parameter_names(instance):row['scalars'][str(n)]=instance.get_scalar_parameter_value(n)
    for n in edit.get_vector_parameter_names(instance):
        v=instance.get_vector_parameter_value(n);row['vectors'][str(n)]=[v.r,v.g,v.b,v.a]
    for n in edit.get_texture_parameter_names(instance):
        t=instance.get_texture_parameter_value(n);row['textures'][str(n)]=t.get_path_name() if t else None
    data[path]=row
data['console']={n:unreal.SystemLibrary.get_console_variable_int_value(n) for n in ['r.VolumetricCloud','r.SupportSkyAtmosphere','sg.EffectsQuality','r.VolumetricCloud.ViewRaySampleMaxCount']}
Path(str(_SEKAI_RUNTIME / 'cloud_material_probe.json')).write_text(json.dumps(data,indent=2))
