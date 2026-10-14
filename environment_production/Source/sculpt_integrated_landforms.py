"""Sculpt cliff benches into the connected valley mesh, without overlay ribbons."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import shutil
import sys
from pathlib import Path

ROOT=Path(str(_SEKAI_ROOT / 'environment_production'))
VERSION=sys.argv[-1] if '--' in sys.argv else 'v014'
BASE=ROOT/'Terrain/v013';OUT=ROOT/'Terrain'/VERSION
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v013.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
terrain=bpy.data.objects['SM_VIL_Valley_Terrain_v009']
data=terrain.data

def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)))
    return t*t*(3-2*t)

old=[v.co.z for v in data.vertices]
for v in data.vertices:
    x,y,z=v.co;side=1 if x>0 else -1;distance=abs(x)
    # Unequal buttresses expose alternating pockets and promontories.
    front=73+5.0*math.sin(y*.052+side)+2.3*math.sin(y*.147-side*.4)
    front-=6.8*math.exp(-((y-(38 if side<0 else 61))/17)**2)
    front+=4.0*math.exp(-((y+23)/12)**2)
    if distance<front-4 or distance>119:continue
    shelf=19+.025*(y+110)+4.0*math.sin(y*.042+side*.6)
    crest=shelf+10.0+2.2*math.sin(y*.074-side)
    toe=smooth(front-3.4,front+.8,distance)
    upper=smooth(front+12.5,front+14.1,distance)
    bench=shelf+(crest-shelf)*upper
    fracture=.45*math.sin(y*.59+distance*.72)+.32*math.sin(y*.21-distance*.51)
    shaped=z*(1-toe)+(bench+fracture)*toe
    blend=(1-smooth(104,119,distance))*smooth(-130,-105,y)*(1-smooth(120,150,y))
    v.co.z=z*(1-blend)+shaped*blend
data.update()

colors=data.color_attributes['Color']
for p in data.polygons:
    a,b,c=[data.vertices[i].co for i in p.vertices[:3]]
    normal=(b-a).cross(c-a).normalized()
    p.use_smooth=normal.z>.78
    for li in p.loop_indices:
        index=data.loops[li].vertex_index
        v=data.vertices[index].co
        if abs(v.z-old[index])<.001:continue
        slope=max(0,min(1,(.86-normal.z)/.64))
        grass=(.28,.36,.13);rock=(.40,.43,.41)
        variation=1+.045*math.sin(v.y*.28+v.x*.16)
        colors.data[li].color=(*(variation*(grass[k]*(1-slope)+rock[k]*slope) for k in range(3)),1)

# The outer backdrop uses continuous slope-color blending instead of grey patches.
back=bpy.data.objects['SM_VIL_Valley_Surroundings']
back.data.materials.clear();back.data.materials.append(terrain.data.materials[0])
bc=back.data.color_attributes.get('Color') or back.data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
for p in back.data.polygons:
    p.material_index=0
    a,b,c=[back.data.vertices[i].co for i in p.vertices[:3]]
    normal=(b-a).cross(c-a).normalized()
    slope=1-smooth(.55,.93,normal.z)
    snow=smooth(88,123,sum(back.data.vertices[i].co.z for i in p.vertices)/len(p.vertices))
    for li in p.loop_indices:
        v=back.data.vertices[back.data.loops[li].vertex_index].co
        variation=1+.035*math.sin(v.x*.07+v.y*.04)
        c=[(.24,.32,.15)[k]*(1-slope)+(.42,.46,.46)[k]*slope for k in range(3)]
        bc.data[li].color=(*(variation*(c[k]*(1-snow)+(.72,.77,.80)[k]*snow) for k in range(3)),1)

assets=[]
for name in manifest['assets']:
    if name.startswith('SM_VIL_Escarpment_'):
        obj=bpy.data.objects.get(name)
        if obj:bpy.data.objects.remove(obj,do_unlink=True)
        continue
    assets.append(name)
    if name not in [terrain.name,back.name]:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for obj in [terrain,back]:
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.fbx(filepath=str(OUT/(obj.name+'.fbx')),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
manifest['assets']=assets
manifest['stage']='INTEGRATED_LANDFORM_SCULPT_NOT_VISUALLY_ACCEPTED'
manifest['geometry_changes']=['Removed both overlay escarpment ribbons',
    'Sculpted irregular steep benches directly into the continuous valley mesh',
    'Blended backdrop grass/stone/snow colors instead of hard material patches',
    'Roads, river, tavern, tree and six camera transforms unchanged']
manifest['review_lighting']={'exposure_bias':1.0,'note':'One-stop exposure calibration; geometry comparison is not lighting-isolated'}
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('SEKAI_Valley_Terrain_'+VERSION+'.blend')))
print('SEKAI_INTEGRATED_LANDFORMS_SAVED',OUT)
