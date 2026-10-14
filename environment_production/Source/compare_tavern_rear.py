"""Compare actual exit-camera captures; keep full frames and original review settings."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
versions=sys.argv[1:]
assert len(versions)==3
manifests=[json.loads((root/v/'terrain_manifest.json').read_text()) for v in versions]
assert all(m['cameras']==manifests[0]['cameras'] for m in manifests)
assert all(m['review_lighting']==manifests[0]['review_lighting'] for m in manifests)
sheet=Image.new('RGB',(1400,3*835),'#18202b')
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',24)
for i,version in enumerate(versions):
    path=root/version/'UE_Review/CAM_05_Exit.png'
    with Image.open(path) as im:
        assert im.size==(1400,787)
        sheet.paste(im.convert('RGB'),(0,i*835+48))
    ImageDraw.Draw(sheet).text((18,i*835+10),version+' - SAME EXIT CAMERA / SAME LIGHTING',font=font,fill='white')
out=root/versions[-1]/'UE_Review'
sheet.save(out/'tavern_rear_before_after.png')
(out/'tavern_comparison_scope.json').write_text(json.dumps({'versions':versions,
    'camera':'CAM_05_Exit','same_camera_and_lighting':True,'full_frame':True,
    'acceptance':'NOT_ACCEPTED'},indent=2))
print('TAVERN_REAR_COMPARISON_SAVED')
