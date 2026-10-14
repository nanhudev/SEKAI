"""Make fixed-camera before/after sheets and explicitly unregistered reference overlays."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(str(_SEKAI_ROOT / 'environment_production'))
before, after = sys.argv[1:3]
old, new = ROOT/'Terrain'/before, ROOT/'Terrain'/after
out = new/'UE_Review'
bm = json.loads((old/'terrain_manifest.json').read_text())
am = json.loads((new/'terrain_manifest.json').read_text())
assert bm['cameras'] == am['cameras'], 'Fixed cameras changed'
same_lighting=bm['review_lighting'] == am['review_lighting']
assert same_lighting or '--allow-lighting-change' in sys.argv[3:], 'Lighting changed; acknowledge explicitly'
font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 20)

def panel(path, title):
    frame = Image.new('RGB', (700,430), '#18202b')
    with Image.open(path) as im:
        frame.paste(im.convert('RGB').resize((700,393)), (0,37))
    ImageDraw.Draw(frame).text((12,8), title, font=font, fill='white')
    return frame

sheet = Image.new('RGB',(2100,860),'#18202b')
for row, (ref, camera, label) in enumerate([
    ('acceptance_plaza_ground_20261012.png','CAM_03_Plaza','PLAZA'),
    ('valley_aerial_support_20261012.png','CAM_06_Aerial','VALLEY'),
]):
    for column, frame in enumerate([
        panel(ROOT/'SEKAI_REFERENCES/MASTER'/ref, label+' - EXISTING REFERENCE'),
        panel(old/'UE_Review'/(camera+'.png'),label+' - '+before+' BEFORE'),
        panel(out/(camera+'.png'),label+' - '+after+' AFTER, SAME CAMERA'),
    ]):
        sheet.paste(frame,(column*700,row*430))
sheet.save(out/'reference_before_after.png')

overlay_sheet = Image.new('RGB',(1400,860),'#18202b')
for row, (ref,camera) in enumerate([
    ('acceptance_plaza_ground_20261012.png','CAM_03_Plaza'),
    ('valley_aerial_support_20261012.png','CAM_06_Aerial'),
]):
    with Image.open(ROOT/'SEKAI_REFERENCES/MASTER'/ref) as reference:
        target = reference.convert('RGB').resize((700,393))
    with Image.open(old/'UE_Review'/(camera+'.png')) as b, Image.open(out/(camera+'.png')) as a:
        baseline=b.convert('RGB').resize((700,393))
        actual=a.convert('RGB').resize((700,393))
    for col,(im,title) in enumerate([
        (Image.blend(baseline,actual,.5),'FIXED CAMERA: BEFORE / AFTER 50% OVERLAY'),
        (Image.blend(target,actual,.5),'REFERENCE / UE OVERLAY: PROJECTION UNREGISTERED'),
    ]):
        x,y=col*700,row*430
        ImageDraw.Draw(overlay_sheet).text((x+12,y+8),title,font=font,fill='white')
        overlay_sheet.paste(im,(x,y+37))
overlay_sheet.save(out/'reference_overlays.png')
(out/'comparison_scope.json').write_text(json.dumps({
    'before':before,'after':after,'same_fixed_cameras':True,'same_manifest_lighting':same_lighting,
    'atmosphere_changed':bm.get('atmosphere_trial')!=am.get('atmosphere_trial'),
    'reference_overlay':'Aspect-resized only. No perspective registration, no pixel match score.',
    'acceptance':'NOT_ACCEPTED',
},indent=2))
print('REFERENCE_COMPARISON_WRITTEN',out)
