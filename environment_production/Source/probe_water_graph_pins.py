from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import unreal,json
from pathlib import Path
edit=unreal.MaterialEditingLibrary
mat=unreal.new_object(unreal.Material)
panner=edit.create_material_expression(mat,unreal.MaterialExpressionPanner)
time=edit.create_material_expression(mat,unreal.MaterialExpressionTime)
sample=edit.create_material_expression(mat,unreal.MaterialExpressionTextureSample)
data={'panner_inputs':list(edit.get_material_expression_input_names(panner)),
      'sample_inputs':list(edit.get_material_expression_input_names(sample)),
      'time_to_panner':edit.connect_material_expressions(time,'',panner,'Time'),
      'panner_to_texture':edit.connect_material_expressions(panner,'',sample,'Coordinates')}
asset=unreal.load_asset('/Game/Environment/Village/Landscape/v074/Materials/MV_Valley_Water_Prototype')
data['parameters']=[str(n) for n in edit.get_scalar_parameter_names(asset)]
data['normal_connection']=edit.connect_material_property(sample,'RGB',unreal.MaterialProperty.MP_NORMAL)
Path(str(_SEKAI_RUNTIME / 'water_graph_pins.json')).write_text(json.dumps(data,indent=2))
