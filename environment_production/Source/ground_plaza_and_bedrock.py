"""Embed the radial paving in a graded bed and break up cascade divider silhouettes."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import shutil
from pathlib import Path

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
BASE=ROOT/'v030';OUT=ROOT/'v031';OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v030.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
terrain=bpy.data.objects['SM_VIL_Valley_Terrain_v009']
for v in terrain.data.vertices:
    r=math.hypot(v.co.x-20,v.co.y-13)
    if r<16:
        t=max(0,min(1,(16-r)/1.7));t=t*t*(3-2*t)
        v.co.z=v.co.z*(1-t)+8.2*t
terrain.data.update()
plaza=bpy.data.objects['SM_VIL_Plaza_PavingAndTreeTerrace']
data=plaza.data
for start in range(0,len(data.vertices),32):
    group=list(data.vertices[start:start+32])
    if len(group)!=32:continue
    cx=sum(v.co.x for v in group)/32;cy=sum(v.co.y for v in group)/32
    bottom=min(v.co.z for v in group);top=max(v.co.z for v in group)
    if math.hypot(cx-20,cy-13)<13.6 and top-bottom<.15:
        for v in group:v.co.z+=8.207-top

# A dirt bedding surface occupies stone joints instead of bright grass.
verts=[tuple(v.co) for v in data.vertices];faces=[tuple(p.vertices) for p in data.polygons]
indices=[p.material_index for p in data.polygons];mats=list(data.materials)
mats.append(bpy.data.materials['MV_Valley_Dirt']);material_index=len(mats)-1
start=len(verts);verts.append((20,13,8.202))
for i in range(128):
    a=i*math.tau/128;verts.append((20+13.16*math.cos(a),13+13.16*math.sin(a),8.202))
for i in range(128):faces.append((start,start+1+i,start+1+(i+1)%128));indices.append(material_index)
mesh=bpy.data.meshes.new('Embedded_Plaza_Masonry');mesh.from_pydata(verts,[],faces);mesh.update()
for m in mats:mesh.materials.append(m)
for p,index in zip(mesh.polygons,indices):p.material_index=index
uv=mesh.uv_layers.new(name='UV_Stone_Metric')
for p in mesh.polygons:
    axis=max(range(3),key=lambda i:abs(p.normal[i]))
    for li in p.loop_indices:
        v=mesh.vertices[mesh.loops[li].vertex_index].co
        x,y=(v.y,v.z) if axis==0 else ((v.x,v.z) if axis==1 else (v.x,v.y))
        uv.data[li].uv=(x*.7,y*.7)
plaza.data=mesh
rocks=bpy.data.objects['SM_VIL_Cascade_Bedrock_v030']
for start in range(0,len(rocks.data.vertices),21):
    group=list(rocks.data.vertices[start:start+21]);cx=sum(v.co.x for v in group)/21;cy=sum(v.co.y for v in group)/21
    for j,v in enumerate(group):
        level=j//7;corner=j%7
        sx=[2.7,1.8,.9][level];sy=[3.1,2.2,1.2][level]
        v.co.x=cx+(v.co.x-cx)*sx+.17*math.sin(corner*2+level)
        v.co.y=cy+(v.co.y-cy)*sy+.12*math.cos(corner*3)
        if level==2:v.co.z-=.25+.18*math.sin(corner*2)
rocks.data.update()
changed=[terrain,plaza,rocks]
for name in manifest['assets']:
    if name not in [o.name for o in changed]:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
for obj in changed:
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.fbx(filepath=str(OUT/(obj.name+'.fbx')),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
manifest['stage']='GROUNDED_PLAZA_AND_BEDROCK_REVIEW_NOT_ACCEPTED'
manifest['geometry_changes']=['Extended level plaza grading beyond outer paving corners',
    'Embedded paver tops at 7 mm above grade and added dirt bedding at joints',
    'Widened cascade rock feet and broke their straight column silhouettes',
    'Fixed cameras, daylight, tree and tavern unchanged']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v031.blend'))
