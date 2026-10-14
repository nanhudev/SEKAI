"""Bake authored slope colors to planar terrain textures for reproducible UE shading."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
source,version=args[:2] if len(args)>=2 else ('v017','v018')
BASE=ROOT/source;OUT=ROOT/version
OUT.mkdir(exist_ok=True)
assert not (OUT/'terrain_manifest.json').exists(), 'Target already contains a version'
bpy.ops.wm.open_mainfile(filepath=str(BASE/('SEKAI_Valley_Terrain_'+source+'.blend')))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
bindings={}
reports=[]
for name,material_name in [('SM_VIL_Valley_Terrain_v009','MV_Valley_Surface'),
                           ('SM_VIL_Valley_Surroundings','MV_Valley_BackdropSurface')]:
    # These meshes are exported below; do not let UE reuse an older mesh/UV binding.
    manifest.get('mesh_source_versions',{}).pop(name,None)
    obj=bpy.data.objects[name];mesh=obj.data
    colors=mesh.color_attributes['Color']
    xmin=min(v.co.x for v in mesh.vertices);xmax=max(v.co.x for v in mesh.vertices)
    ymin=min(v.co.y for v in mesh.vertices);ymax=max(v.co.y for v in mesh.vertices)
    size=2048
    raster=[]
    uv=mesh.uv_layers.active or mesh.uv_layers.new(name='UV_LandformColor')
    for poly in mesh.polygons:
        points=[];rgb=[0.,0.,0.]
        for li in poly.loop_indices:
            v=mesh.vertices[mesh.loops[li].vertex_index].co
            u=(v.x-xmin)/(xmax-xmin);w=(v.y-ymin)/(ymax-ymin)
            uv.data[li].uv=(u,w)
            points.append((u*(size-1),(1-w)*(size-1)))
            for k in range(3):rgb[k]+=colors.data[li].color[k]/len(poly.loop_indices)
        raster.append([points,[round(max(0,min(1,c))*255) for c in rgb]])
    texture_name='T_'+material_name+'_AuthoredColor'
    subprocess.run([_sekai_os.environ.get('PYTHON_BIN', 'python'),
        str(ROOT.parent/'Source'/'raster_landform_colors.py'),str(OUT/(texture_name+'.png')),str(size)],
        input=json.dumps(raster),text=True,check=True)
    material=bpy.data.materials.get(material_name) or bpy.data.materials.new(material_name)
    mesh.materials.clear();mesh.materials.append(material)
    for p in mesh.polygons:p.material_index=0
    bindings[material_name]=texture_name
    manifest.setdefault('material_palette',{})[material_name]=[.3,.4,.2]
    reports.append({'mesh':name,'texture':texture_name,'resolution':size,
                    'encoding':'linear RGB stored in PNG; UE sRGB disabled',
                    'bounds_xy':[xmin,xmax,ymin,ymax]})
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
    bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.fbx(filepath=str(OUT/(name+'.fbx')),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
for name in manifest['assets']:
    if name not in [r['mesh'] for r in reports]:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for texture in BASE.glob('*.png'):
    if not (OUT/texture.name).exists():shutil.copy2(texture,OUT/texture.name)
manifest['surface_color_textures']=bindings
manifest['stage']='AUTHORED_LANDFORM_COLOR_BAKE_NOT_VISUALLY_ACCEPTED'
manifest['geometry_source_version']=source
manifest['import_changes']=['Baked existing authored grass/rock/snow colors to linear planar textures',
                            'Terrain and backdrop use separate UV0 textures; geometry and cameras unchanged']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'color_bake_report.json').write_text(json.dumps(reports,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('SEKAI_Valley_Terrain_'+version+'.blend')))
print('SEKAI_LANDFORM_COLOR_BAKE_SAVED',OUT)
