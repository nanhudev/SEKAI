"""Cut planar fracture offsets into the existing connected cliff terrain."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import random
import shutil
from pathlib import Path

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
BASE=ROOT/'v035';OUT=ROOT/'v036';OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v035.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
obj=bpy.data.objects['SM_VIL_Valley_Terrain_v009'];mesh=obj.data
rng=random.Random(26101236)
field={(x,y):rng.uniform(-1,1) for x in range(-100,101) for y in range(-100,101)}

def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def planar(x,y):
    i,j=math.floor(x),math.floor(y);u,v=x-i,y-j
    a,b,c,d=[field[key] for key in [(i,j),(i+1,j),(i,j+1),(i+1,j+1)]]
    if u+v<1:return a+(b-a)*u+(c-a)*v
    return d+(c-d)*(1-u)+(b-d)*(1-v)

original=[v.co.copy() for v in mesh.vertices]
normals=[v.normal.copy() for v in mesh.vertices]
changed=0
for vertex,point,normal in zip(mesh.vertices,original,normals):
    x,y,z=point
    if abs(x)<58 or abs(x)>112 or y<-112 or y>132:continue
    weight=(1-smooth(.24,.79,normal.z))*smooth(58,64,abs(x))*(1-smooth(104,112,abs(x)))
    weight*=smooth(-112,-103,y)*(1-smooth(120,132,y))
    if weight<.02:continue
    horizontal=normal.copy();horizontal.z=0
    if horizontal.length<.01:continue
    horizontal.normalize()
    patch=planar(y/4.6,z/6.8)
    fissure=(1-smooth(.035,.16,abs((y/4.6)%1-.5)))*.75
    stratum=.40*(1-smooth(.06,.27,abs((z/6.8)%1-.5)))
    displacement=weight*(patch*2.0-fissure+stratum)
    vertex.co+=horizontal*displacement
    vertex.co.z+=weight*planar(y/7.2,z/8.5)*.50
    changed+=1
mesh.update()
colors=mesh.color_attributes['Color']
for p in mesh.polygons:
    slope=smooth(.12,.65,1-max(0,p.normal.z));p.use_smooth=p.normal.z>.74
    for li in p.loop_indices:
        v=mesh.vertices[mesh.loops[li].vertex_index].co
        variation=1+.13*planar(v.x/8.1,v.y/9.3)+.07*planar(v.y/4.6,v.z/6.8)*slope
        grass=(.16,.27,.095);rock=(.235,.27,.285)
        colors.data[li].color=(*(variation*(grass[k]*(1-slope)+rock[k]*slope) for k in range(3)),1)
assert changed>500,'Cliff sculpt selection is empty or unexpectedly small'
assert all((v.co-p).length<.00001 for v,p in zip(mesh.vertices,original) if abs(p.x)<58), 'Core terrain changed'
for name in manifest['assets']:
    if name!=obj.name:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
bpy.ops.export_scene.fbx(filepath=str(OUT/(obj.name+'.fbx')),use_selection=True,object_types={'MESH'},
    axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
manifest['stage']='JOINTED_CLIFF_SCULPT_REQUIRES_REBAKE_AND_REVIEW'
manifest['geometry_source_version']='v035'
manifest['geometry_changes']=['Sculpted connected cliff terrain with planar fracture offsets and unequal ledges',
    'Cut vertical joints without adding detached cliff assets',
    'Central terrain, roads, buildings, river, fixed cameras and daylight retained']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'cliff_sculpt_report.json').write_text(json.dumps({'changed_vertices':changed,'core_unchanged_assertion':True},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v036.blend'))
print('SEKAI_JOINTED_CLIFFS',changed)
