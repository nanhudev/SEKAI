from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import sys
from pathlib import Path
from PIL import Image,ImageDraw
folder=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/sys.argv[1]/'UE_Review'
paths=sorted(folder.glob('CAM*.png'))
sheet=Image.new('RGB',(1400,1260),'#18202b')
for i,p in enumerate(paths):
    x=(i%2)*700;y=(i//2)*420
    ImageDraw.Draw(sheet).text((x+10,y+5),p.stem,fill='white')
    with Image.open(p) as im:sheet.paste(im.resize((700,393)),(x,y+27))
sheet.save(folder/'six_views_contact.png')
