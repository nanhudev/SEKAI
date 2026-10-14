"""Image integrity only: never promotes captures to visual acceptance."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
import sys
from pathlib import Path
from PIL import Image, ImageStat

root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/sys.argv[1]/'UE_Review'
names=['CAM_01_Entrance','CAM_02_Bridge','CAM_03_Plaza','CAM_04_Residential','CAM_05_Exit','CAM_06_Aerial']
report=[]
for name in names:
    with Image.open(root/(name+'.png')) as image:
        image=image.convert('RGB')
        stats=ImageStat.Stat(image)
        row={'camera':name,'dimensions':list(image.size),'mean_rgb':stats.mean,'stddev_rgb':stats.stddev}
        row['nonblank']=max(stats.stddev)>12 and image.width>=1000 and image.height>=700
        report.append(row)
(root/'image_integrity.json').write_text(json.dumps({'scope':'FILE_AND_PIXEL_INTEGRITY_NOT_VISUAL_ACCEPTANCE','images':report},indent=2))
if not all(row['nonblank'] for row in report):raise RuntimeError('Blank or undersized camera image')
print('SIX_FIXED_UE_IMAGES_NONBLANK')
