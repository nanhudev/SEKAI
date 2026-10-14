"""Read built-in function pins before authoring the terrain material graph."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
from pathlib import Path
import unreal
out={}
for name in ['WorldAlignedTexture','WorldAlignedNormal']:
    path='/Engine/Functions/Engine_MaterialFunctions01/Texturing/'+name
    fn=unreal.load_asset(path)
    assert fn,path
    expressions=unreal.MaterialEditingLibrary.get_material_function_expressions(fn)
    out[name]={'asset':path,'inputs':[str(e.get_editor_property('input_name')) for e in expressions if isinstance(e,unreal.MaterialExpressionFunctionInput)],
        'outputs':[str(e.get_editor_property('output_name')) for e in expressions if isinstance(e,unreal.MaterialExpressionFunctionOutput)]}
Path(str(_SEKAI_RUNTIME / 'world_aligned_pins.json')).write_text(json.dumps(out,indent=2))
print('WORLD_ALIGNED_PINS',json.dumps(out))
