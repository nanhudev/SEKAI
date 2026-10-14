"""Original multi-scale limestone detail maps; no reference image is sampled."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

out=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/sys.argv[1]
rng=np.random.default_rng(26101359)
size=1024
layers=[]
for coarse,weight in [(16,.30),(64,.25),(256,.22),(1024,.09)]:
    a=(rng.random((coarse,coarse))*255).astype('uint8')
    im=Image.fromarray(a).resize((size,size),Image.Resampling.BICUBIC)
    layers.append(np.asarray(im,dtype=np.float32)/255*weight)
height=sum(layers)
fine=rng.random((size,size)).astype(np.float32)
height+=np.where(fine>.995,-.15,0)
color=np.clip(.60+height*.82,0,1)
Image.fromarray(np.repeat((color*255).astype('uint8')[...,None],3,axis=2)).save(out/'T_Polish_StoneColor.png')
dy,dx=np.gradient(height)
n=np.stack((-dx*2.2,-dy*2.2,np.ones_like(height)),axis=2)
n/=np.linalg.norm(n,axis=2)[...,None]
Image.fromarray(((n*.5+.5)*255).astype('uint8')).save(out/'T_Polish_StoneNormal.png')
rough=np.clip(.72+height*.34,0,1)
Image.fromarray((rough*255).astype('uint8')).save(out/'T_Polish_StoneRoughness.png')
print('ORIGINAL_STONE_DETAIL_MAPS_SAVED')
