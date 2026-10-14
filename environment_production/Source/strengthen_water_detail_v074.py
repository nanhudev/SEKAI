from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json,os,shutil
from pathlib import Path
import numpy as np
from PIL import Image
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/'v073'
out=Path(str(_SEKAI_ROOT / 'environment_production/Terrain/v074'));out.mkdir(exist_ok=False)
pass  # Checkpoints stay inside the portable project.
m=json.loads((base/'terrain_manifest.json').read_text())
for name in m['assets']:m.setdefault('mesh_source_versions',{}).setdefault(name,'v073')
for p in base.iterdir():
    if p.suffix.lower() in ['.fbx','.png'] and p.name!='T_Valley_Water_Normal.png':os.link(p,out/p.name)
    elif p.name in ['material_sources.json','planting_report.json']:shutil.copy2(p,out/p.name)
shutil.copy2(base/'SEKAI_Valley_Terrain_v073.blend',out/'SEKAI_Valley_Terrain_v074.blend')
n=512;y,x=np.mgrid[0:n,0:n]/n;gx=np.zeros_like(x);gy=np.zeros_like(x)
for amplitude,kx,ky in [(.035,2,1),(.018,3,-2),(.012,1,4)]:
    c=np.cos(2*np.pi*(kx*x+ky*y));gx+=amplitude*kx*c;gy+=amplitude*ky*c
normal=np.stack([-gx,-gy,np.ones_like(x)],axis=-1);normal/=np.linalg.norm(normal,axis=-1,keepdims=True)
Image.fromarray(np.uint8(np.clip(normal*.5+.5,0,1)*255)).save(out/'T_Valley_Water_Normal.png')
m['version']='v074';m['water_detail_change']='Increase authored flowing normal slopes; previous near-flat normal did not produce independently readable movement.'
(out/'terrain_manifest.json').write_text(json.dumps(m,indent=2))
