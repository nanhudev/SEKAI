from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import unreal,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from create_valley_cloud_material import create_cloud_material
mat=create_cloud_material(unreal.AssetToolsHelpers.get_asset_tools(),'/Game/Environment/Village/Landscape/CloudGraphProbe/Materials')
Path(str(_SEKAI_RUNTIME / 'native_cloud_graph.txt')).write_text(mat.get_path_name())
