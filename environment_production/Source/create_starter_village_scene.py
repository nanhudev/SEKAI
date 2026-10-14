from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
from pathlib import Path
root=Path(str(_SEKAI_ROOT / 'godot/scenes/world'))
source=(root/'MistvalePlayable.tscn').read_text(encoding='utf-8')
target=root/'StarterVillagePlayable.tscn'
assert not target.exists()
source=source.replace('res://scripts/world/mistvale_playable.gd','res://scripts/world/starter_village_playable.gd')
source=source.replace('[node name="MistvalePlayable" type="Node3D"]','[node name="StarterVillagePlayable" type="Node3D"]')
source=source[:source.index('; MISTVALE PLAYABLE')]+ '; Starter village v068. Preserve the existing Player/director siblings.\n\n'+source[source.index('[ext_resource'):]
target.write_text(source,encoding='utf-8')
