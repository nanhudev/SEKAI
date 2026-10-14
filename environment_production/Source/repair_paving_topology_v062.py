"""Lower complete paving solids uniformly and export clean native triangles."""
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
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import export_mesh
ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));BASE,OUT=ROOT/'v061',ROOT/'v062'
OUT.mkdir(exist_ok=True);assert not (OUT/'terrain_manifest.json').exists()
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v061.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
name='SM_VIL_Plaza_PavingAndTreeTerrace';plaza=bpy.data.objects[name]
with bpy.data.libraries.load(str(ROOT/'v060/SEKAI_Valley_Terrain_v060.blend'),link=False) as (source,target):
    target.objects=[name]
original=target.objects[0]
assert len(original.data.vertices)==len(plaza.data.vertices)
indices=set()
for poly in original.data.polygons:
    if not original.data.materials[poly.material_index].name.startswith('MV_Polish_Limestone'):continue
    if all(math.hypot(original.data.vertices[i].co.x-20,original.data.vertices[i].co.y-13)<14.2 and original.data.vertices[i].co.z<8.5 for i in poly.vertices):
        indices.update(poly.vertices)
for i in indices:
    plaza.data.vertices[i].co=original.data.vertices[i].co
    plaza.data.vertices[i].co.z-=.016
bpy.data.objects.remove(original,do_unlink=True)
plaza.data.update()
bm=bmesh.new();bm.from_mesh(plaza.data)
bmesh.ops.dissolve_degenerate(bm,dist=.000001,edges=list(bm.edges))
bmesh.ops.triangulate(bm,faces=list(bm.faces))
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
bm.to_mesh(plaza.data);bm.free();plaza.data.update()
uv=plaza.data.uv_layers.active
for poly in plaza.data.polygons:
    axis=max(range(3),key=lambda k:abs(poly.normal[k]))
    scale=1 if plaza.data.materials[poly.material_index].name.startswith('MV_Polish') else .7
    for li in poly.loop_indices:
        p=plaza.data.vertices[plaza.data.loops[li].vertex_index].co
        uv.data[li].uv=(p.y*scale,p.z*scale) if axis==0 else (p.x*scale,p.z*scale) if axis==1 else (p.x*scale,p.y*scale)
for asset in manifest['assets']:
    if asset!=name:shutil.copy2(BASE/(asset+'.fbx'),OUT/(asset+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
export_mesh(plaza,OUT/(name+'.fbx'))
manifest['geometry_source_version']='v061';manifest['stage']='BRIDGE_ROOT_SKY_REQUIRES_FIXED_REVIEW'
manifest['geometry_changes'].append('Uniformly recessed closed paving solids and repaired face/UV topology')
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'paving_topology_report.json').write_text(json.dumps({'uniformly_lowered_vertices':len(indices),
    'degenerate_faces':sum(p.area<1e-10 for p in plaza.data.polygons),'status':'REQUIRES_UE_REVIEW'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v062.blend'))
print('PAVING_TOPOLOGY_REPAIRED',len(indices))
