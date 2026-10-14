from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import unreal
import json
from pathlib import Path
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain/v007'))
rows=[]
for name in ['SM_VIL_Valley_Terrain_v007','SM_VIL_Valley_Cliff_00','SM_VIL_Terrace_Face_Tree']:
    mesh=unreal.load_asset('/Game/Environment/Village/Landscape/v007/'+name)
    bounds=mesh.get_bounds()
    slots=[]
    for slot in mesh.get_editor_property('static_materials'):
        mat=slot.get_editor_property('material_interface')
        slots.append({'slot':str(slot.get_editor_property('imported_material_slot_name')),
            'material':mat.get_path_name() if mat else None,
            'expressions':unreal.MaterialEditingLibrary.get_num_material_expressions(mat) if mat else 0})
    rows.append({'name':name,'origin':[bounds.origin.x,bounds.origin.y,bounds.origin.z],
        'extent':[bounds.box_extent.x,bounds.box_extent.y,bounds.box_extent.z],'slots':slots})
(root/'ue_audit.json').write_text(json.dumps(rows,indent=2))
print('SEKAI_AUDIT',json.dumps(rows))
