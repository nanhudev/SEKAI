"""Compare identical diagnostic views, including unresolved areas without calling them fixes."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageStat

root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
before,after=sys.argv[1:3]
old,new=root/before/'Hidden_Review',root/after/'Hidden_Review'
a=json.loads((old/'camera_scope.json').read_text())
b=json.loads((new/'camera_scope.json').read_text())
assert a['views']==b['views'][:len(a['views'])], 'Diagnostic camera definitions differ'
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',20)
names=['01_Bridge_East','03_River_Edge','04_Tree_RiverRear','06_Tavern_Back',
       '08_Road_Junction','09_Cliff_Foot','07_Tavern_Side','10_Plaza_Edge']
sheet=Image.new('RGB',(1600,len(names)*490),'#18202b')
draw=ImageDraw.Draw(sheet)
for i,name in enumerate(names):
    for j,(version,folder) in enumerate([(before,old),(after,new)]):
        draw.text((j*800+12,i*490+8),version+' '+name+' - INSPECTION, NOT AREA ACCEPTANCE',font=font,fill='white')
        with Image.open(folder/(name+'.png')) as im:
            sheet.paste(im.convert('RGB').resize((800,450)),(j*800,i*490+40))
sheet.save(new/'hidden_before_after.png')
rows=[]
for path in sorted(new.glob('*.png')):
    if path.stem not in {row[0] for row in b['views']}:continue
    with Image.open(path) as im:
        stats=ImageStat.Stat(im.convert('RGB'))
        rows.append({'name':path.stem,'size':list(im.size),'stddev_rgb':stats.stddev})
assert len(rows)==len(b['views'])
assert all(row['size']==[1280,720] and max(row['stddev_rgb'])>12 for row in rows)
(new/'inspection_integrity.json').write_text(json.dumps({'scope':'Pixel integrity only, not artistic or collision acceptance',
    'same_diagnostic_cameras':True,'before':before,'after':after,'images':rows},indent=2))
print('DIAGNOSTIC_COMPARISON_AND_PIXEL_INTEGRITY',len(rows))
