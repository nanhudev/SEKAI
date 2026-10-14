from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import sys,json
from pathlib import Path
from PIL import Image,ImageChops,ImageStat
folder=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/sys.argv[1]/(sys.argv[2] if len(sys.argv)>2 else 'Water_Isolated_Deterministic')
frames=[Image.open(folder/('phase_%02d.png'%i)).convert('RGB') for i in range(5)]
boxes={'water':(450,490,850,670),'static_building':(300,160,570,240)}
rows=[]
for i in range(1,5):
    diff=ImageChops.difference(frames[0],frames[i])
    rows.append({'phase_index':i,**{key:sum(ImageStat.Stat(diff.crop(box)).mean)/3 for key,box in boxes.items()}})
control=rows[0]
verified=all(r['water']>max(.5,control['water']*3) and r['static_building']<.2 for r in rows[1:]) and control['static_building']<.2
(folder/'motion_inspection.json').write_text(json.dumps({'scope':'Isolated rendered shader response, not fluid simulation or bank intersection acceptance','control':control,'comparisons':rows,'rois':boxes,'independent_water_motion_verified':verified},indent=2))
frames[0].save(folder/'water_phase_preview.gif',save_all=True,append_images=frames[2:],duration=500,loop=0)
print('INDEPENDENT_MOTION_VERIFIED',verified,rows)
