from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import unreal,json
from pathlib import Path
edit=unreal.MaterialEditingLibrary
mat=unreal.load_asset('/Engine/EngineSky/VolumetricClouds/m_SimpleVolumetricCloud')
stack=[]
for name in dir(unreal.MaterialProperty):
    if name.startswith('MP_'):
        node=edit.get_material_property_input_node(mat,getattr(unreal.MaterialProperty,name))
        if node:stack.append(node)
nodes=[];seen=set()
while stack:
    n=stack.pop()
    if n is None:continue
    if n.get_path_name() in seen:continue
    seen.add(n.get_path_name());row={'class':n.get_class().get_name(),'name':n.get_name(),'desc':n.get_editor_property('desc')}
    if isinstance(n,unreal.MaterialExpressionVectorParameter):
        row['parameter']=str(n.get_editor_property('parameter_name'))
        channels=n.get_editor_property('channel_names');row['channels']={k:str(channels.get_editor_property(k)) for k in ['r','g','b','a']}
    nodes.append(row);stack.extend(edit.get_inputs_for_material_expression(mat,n))
out=Path(str(_SEKAI_RUNTIME))
(out/'cloud_layout_nodes.json').write_text(json.dumps(nodes,indent=2))
