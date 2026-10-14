"""Original tileable water normal and broken foam masks, not reference imagery."""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

out=Path(sys.argv[1]);n=512
y,x=np.mgrid[0:n,0:n]/n
gx=np.zeros_like(x);gy=np.zeros_like(x)
for amplitude,kx,ky in [(.003,2,1),(.0015,3,-2),(.001,1,4)]:
    c=np.cos(2*np.pi*(kx*x+ky*y))
    gx+=amplitude*kx*c;gy+=amplitude*ky*c
normal=np.stack([-gx,-gy,np.ones_like(x)],axis=-1)
normal/=np.linalg.norm(normal,axis=-1,keepdims=True)
Image.fromarray(np.uint8(np.clip(normal*.5+.5,0,1)*255)).save(out/'T_Valley_Water_Normal.png')
rng=np.random.default_rng(26101230)
def noise(width,height):
    grid=rng.random((height,width)).astype(np.float32)
    # Wrapped border makes the filtered random field tileable.
    grid=np.pad(grid,((0,1),(0,1)),mode='wrap')
    return np.asarray(Image.fromarray(grid,mode='F').resize((n,n),Image.Resampling.BICUBIC))
foam=noise(32,32)*.5+noise(85,85)*.3+noise(170,170)*.2
flow=noise(70,5)*.6+noise(120,14)*.25+noise(190,40)*.15
for name,field,threshold in [('Foam_Mask',foam,.56),('Fall_Flow',flow,.43)]:
    alpha=np.clip((field-threshold)*3,0,1)
    rgba=np.full((n,n,4),255,dtype=np.uint8);rgba[:,:,3]=np.uint8(alpha*255)
    Image.fromarray(rgba).save(out/('T_Valley_'+name+'.png'))
