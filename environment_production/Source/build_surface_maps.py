"""Original tiling PBR maps; these are material data, not reference images."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
from pathlib import Path
import json
import numpy as np
from PIL import Image

OUT=Path(str(_SEKAI_ROOT / 'environment_production/Materials/v001'))
OUT.mkdir(parents=True,exist_ok=True)
SIZE=1024
y,x=np.mgrid[0:SIZE,0:SIZE]/SIZE
tau=2*np.pi

def coherent(phase=0):
    return (np.sin(tau*(3*x+2*y)+phase)*.34+
            np.sin(tau*(11*x-7*y)+phase)*.21+
            np.sin(tau*(29*x+31*y)+phase)*.13+
            np.sin(tau*(79*x-61*y)+phase)*.08)

def save(family,height,variation,roughness,normal_strength):
    h=height.astype(np.float32)
    dx=(np.roll(h,-1,axis=1)-np.roll(h,1,axis=1))*SIZE*.5*normal_strength
    dy=(np.roll(h,-1,axis=0)-np.roll(h,1,axis=0))*SIZE*.5*normal_strength
    normal=np.stack([-dx,-dy,np.ones_like(dx)],axis=-1)
    normal/=np.linalg.norm(normal,axis=-1,keepdims=True)
    # Unreal uses the DirectX green-channel convention.
    normal[:,:,1]*=-1
    rgb=np.repeat(np.clip(variation[...,None],0,1),3,axis=-1)
    orm=np.stack([np.ones_like(x),np.clip(roughness,0,1),np.zeros_like(x)],axis=-1)
    maps={'Color':rgb,'Normal':normal*.5+.5,'ORM':orm}
    for kind,array in maps.items():
        Image.fromarray(np.round(array*255).astype(np.uint8),'RGB').save(OUT/('T_VIL_'+family+'_'+kind+'.png'))

# Growth-ring drift and local knot distortion, periodic along both tile axes.
drift=.013*np.sin(tau*2*y)+.006*np.sin(tau*(3*y+x))
knot=np.sin(tau*x)*np.exp(-((np.sin(tau*y)/.34)**2))*.037
grain=np.sin(tau*(44*(x+drift+knot)))
fine=np.sin(tau*(131*(x+drift*.35)))
wood_height=grain*.35+fine*.10+coherent()*.09
save('Timber',wood_height,.69+.12*grain+.055*coherent(),.73+.08*grain,.003)
stone=coherent(.7)+np.sin(tau*(151*x+137*y))*.035
pores=np.maximum(0,np.sin(tau*113*x)*np.sin(tau*97*y)-.72)
save('Stone',stone-pores*.6,.72+.12*stone,.83+.06*stone,.009)
plaster=coherent(1.4)*.15+np.sin(tau*211*x)*np.sin(tau*173*y)*.045
save('Plaster',plaster,.85+.045*coherent(1.4),.86+plaster*.14,.003)
strata=np.sin(tau*(9*x+2*y)+.9*np.sin(tau*4*y))
slate=strata*.23+coherent(2.1)*.20
save('Slate',slate,.76+.065*strata+.04*coherent(2.1),.71+.08*slate,.004)
(OUT/'manifest.json').write_text(json.dumps({
    'resolution':[SIZE,SIZE], 'normal_convention':'DirectX',
    'color_space':{'Color':'sRGB','Normal':'linear','ORM':'linear'},
    'ORM_channels':['ambient_occlusion','roughness','metallic'],
    'families':['Timber','Stone','Plaster','Slate'],
    'source':'Original deterministic surface fields; no external or generated reference art',
    'status':'MATERIAL_DATA_NOT_VISUALLY_ACCEPTED'
},indent=2),encoding='utf-8')
print('SEKAI_SURFACE_MAPS',str(OUT))
