"""Fit stone outlines closer together while retaining their real recessed volumes."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import bmesh
import json
import math
import shutil
import sys
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import export_mesh
ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));BASE,OUT=ROOT/'v062',ROOT/'v063'
OUT.mkdir(exist_ok=True);assert not (OUT/'terrain_manifest.json').exists()
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v062.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text());existing={m.name:m for m in bpy.data.materials}
name='SM_VIL_Plaza_PavingAndTreeTerrace';plaza=bpy.data.objects[name]
with bpy.data.libraries.load(str(ROOT/'v060/SEKAI_Valley_Terrain_v060.blend'),link=False) as (source,target):
    target.objects=[name]
original=target.objects[0];data=original.data.copy()
for i,mat in enumerate(data.materials):
    base=mat.name.rsplit('.',1)[0] if mat.name.rsplit('.',1)[-1].isdigit() else mat.name
    data.materials[i]=existing[base]
plaza.data=data;bpy.data.objects.remove(original,do_unlink=True)
eligible=set()
for poly in data.polygons:
    if not data.materials[poly.material_index].name.startswith('MV_Polish_Limestone'):continue
    if all(math.hypot(data.vertices[i].co.x-20,data.vertices[i].co.y-13)<14.2 and data.vertices[i].co.z<8.5 for i in poly.vertices):eligible.update(poly.vertices)
links={i:[] for i in eligible}
for edge in data.edges:
    a,b=edge.vertices
    if a in eligible and b in eligible:links[a].append(b);links[b].append(a)
seen=set();cells=0
for start in eligible:
    if start in seen:continue
    todo=[start];component=[];seen.add(start)
    while todo:
        i=todo.pop();component.append(i)
        for j in links[i]:
            if j not in seen:seen.add(j);todo.append(j)
    points=[data.vertices[i].co for i in component]
    low=min(p.z for p in points);top=max(p.z for p in points)
    bottom=[p for p in points if abs(p.z-low)<1e-5]
    center=sum((Vector((p.x,p.y)) for p in bottom),Vector((0,0)))/len(bottom)
    for p in points:
        delta=Vector((p.x,p.y))-center
        if delta.length>1e-5:
            delta=delta.normalized()*(.027 if abs(p.z-top)<1e-5 else .012)
            p.x+=delta.x;p.y+=delta.y
        p.z-=.016
    cells+=1
data.update()
bm=bmesh.new();bm.from_mesh(data)
bmesh.ops.triangulate(bm,faces=list(bm.faces))
bad=[face for face in bm.faces if face.calc_area()<1e-9]
if bad:bmesh.ops.delete(bm,geom=bad,context='FACES')
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
bm.to_mesh(data);bm.free();data.update()
uv=data.uv_layers.active
for poly in data.polygons:
    axis=max(range(3),key=lambda k:abs(poly.normal[k]))
    scale=1 if data.materials[poly.material_index].name.startswith('MV_Polish') else .7
    for li in poly.loop_indices:
        p=data.vertices[data.loops[li].vertex_index].co
        uv.data[li].uv=(p.y*scale,p.z*scale) if axis==0 else (p.x*scale,p.z*scale) if axis==1 else (p.x*scale,p.y*scale)
for asset in manifest['assets']:
    if asset!=name:shutil.copy2(BASE/(asset+'.fbx'),OUT/(asset+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
export_mesh(plaza,OUT/(name+'.fbx'))
manifest['mesh_source_versions']={asset:manifest.get('mesh_source_versions',{}).get(asset,'v062') for asset in manifest['assets'] if asset!=name}
manifest['atmosphere_trial'].update({'coverage':-.34,'global_scale':256.0,'global_density':.006})
manifest['geometry_source_version']='v062';manifest['stage']='FITTED_STONE_JOINTS_AND_CLOUD_TRIAL_REQUIRES_REVIEW'
manifest['geometry_changes']=['Narrower fitted plaza-stone joints and smaller edge chamfers; closed solids remain recessed',
    'Existing bridge/root/estate geometry unchanged; cloud coverage trial on original engine pattern scale']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'paving_fit_report.json').write_text(json.dumps({'fitted_cells':cells,'removed_zero_area_triangles':len(bad),
    'degenerate_faces_remaining':sum(p.area<1e-10 for p in data.polygons),'status':'REQUIRES_UE_REVIEW'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v063.blend'))
print('FITTED_STONE_JOINTS_SAVED',cells)
