"""Compare actual native frames where only the water clock is advanced."""
import json,sys
from pathlib import Path
from PIL import Image,ImageChops,ImageStat
folder=Path(sys.argv[1]);frames=[Image.open(folder/('water_%02d.png'%i)).convert('RGB') for i in range(4)]
water=(450,490,850,670);static=(820,140,1240,260)
rows=[]
for i in range(1,4):
    diff=ImageChops.difference(frames[0],frames[i])
    rows.append({'frame':i,'water_mean_difference':sum(ImageStat.Stat(diff.crop(water)).mean)/3,
        'static_mean_difference':sum(ImageStat.Stat(diff.crop(static)).mean)/3})
assert all(r['water_mean_difference']>.5 and r['static_mean_difference']<.1 for r in rows),rows
frames[0].save(folder/'water_flow_preview.gif',save_all=True,append_images=frames[1:],duration=500,loop=0)
(folder/'flow_verification.json').write_text(json.dumps({'scope':'Native rendered water responds to isolated flow-time changes. No fluid simulation or full edge-intersection acceptance.','water_roi':water,'static_roi':static,'comparisons':rows},indent=2))
print(rows)
