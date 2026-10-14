from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import unreal
from terrain_surface_detail import apply_terrain_detail
mat=unreal.new_object(unreal.Material)
edit=unreal.MaterialEditingLibrary
for kind in ['ComponentMask','Abs','Subtract','Multiply','Saturate','Normalize','DotProduct','Add','LinearInterpolate']:
    n=edit.create_material_expression(mat,getattr(unreal,'MaterialExpression'+kind))
    print('PIN_CHECK',kind,edit.get_material_expression_input_names(n))
baked=edit.create_material_expression(mat,unreal.MaterialExpressionTextureSample)
baked.texture=unreal.load_asset('/Game/Environment/Village/Landscape/v066/Textures/T_MV_Valley_Surface_AuthoredColor')
textures={(a,k):unreal.load_asset('/Game/Environment/Village/Landscape/v066/Textures/T_Terrain_'+a+'_'+k) for a in ['grass_ground','rock_face_03'] for k in ['Diffuse','nor_dx','Rough']}
apply_terrain_detail(mat,baked,textures)
edit.recompile_material(mat)
Path(str(_SEKAI_RUNTIME / 'terrain_graph_test.txt')).write_text('All graph pin connections succeeded; material compile requested.')
