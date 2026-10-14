"""Contact sheet of actual route-camera captures, not a locomotion test."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import sys
from pathlib import Path
from PIL import Image,ImageDraw
folder=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/sys.argv[1]/'Hidden_Review'
paths=sorted(folder.glob('ROUTE*.png'))+sorted(folder.glob('SIDE*.png'))
sheet=Image.new('RGB',(1280,((len(paths)+1)//2)*390),'#18202b')
for i,p in enumerate(paths):
    x=(i%2)*640;y=(i//2)*390
    ImageDraw.Draw(sheet).text((x+8,y+8),p.stem,fill='white')
    with Image.open(p) as im:sheet.paste(im.resize((640,360)),(x,y+30))
sheet.save(folder/'route_contact.png')
print(len(paths),'camera views')
