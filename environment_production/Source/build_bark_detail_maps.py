"""Original irregular longitudinal bark texture for the existing metric trunk UVs."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import sys
from pathlib import Path
import numpy as np
from PIL import Image
out=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))/sys.argv[1]
rng=np.random.default_rng(26101361);size=1024
v,u=np.mgrid[0:size,0:size].astype(np.float32)/size
warp=.018*np.sin(v*np.pi*4)+.012*np.sin(v*np.pi*10+u*3)
grain=Image.fromarray((rng.random((64,128))*255).astype('uint8')).resize((size,size),Image.Resampling.BICUBIC)
grain=np.asarray(grain,dtype=np.float32)/255
height=.45+.12*np.sin((u+warp)*np.pi*44)+.055*np.sin((u+warp*.7)*np.pi*94)+grain*.25
pores=rng.random((size,size));height-=np.where(pores>.995,.09,0)
color=np.clip(.37+height*.79,0,1)
Image.fromarray(np.repeat((color*255).astype('uint8')[...,None],3,axis=2)).save(out/'T_Polish_BarkColor.png')
dy,dx=np.gradient(height)
n=np.stack((-dx*12,-dy*7,np.ones_like(height)),axis=2);n/=np.linalg.norm(n,axis=2)[...,None]
Image.fromarray(((n*.5+.5)*255).astype('uint8')).save(out/'T_Polish_BarkNormal.png')
print('ORIGINAL_BARK_MAPS_SAVED')
