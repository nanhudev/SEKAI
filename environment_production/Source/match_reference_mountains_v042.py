"""Replace rounded backdrop masses with the reference's separated angular alpine ridges."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import shutil
from pathlib import Path
from mathutils import Vector
from mathutils import noise

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
BASE,OUT=ROOT/'v041',ROOT/'v042'
OUT.mkdir(exist_ok=True)
assert not (OUT/'terrain_manifest.json').exists(), 'Do not overwrite a version'
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v041.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
obj=bpy.data.objects['SM_VIL_Valley_Surroundings'];mesh=obj.data
original=[v.co.copy() for v in mesh.vertices]

def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)

# Ground master: split peaks to left of the tree, lower saddle behind its trunk,
# another range to its right. Keep the real village / backdrop seam unchanged.
peaks=[(-300,270,153,160,180),(-180,370,177,145,175),(-375,105,123,125,175),
       (-70,460,145,145,150),(275,340,165,160,180),(360,145,129,140,170),
       (380,-175,99,140,170),(-350,-200,106,150,180)]
changed=0
for vertex,old in zip(mesh.vertices,original):
    x,y,z=old
    cx=max(-120,min(120,x));cy=max(-130,min(150,y))
    distance=math.hypot(x-cx,y-cy)
    weight=smooth(52,128,distance)
    if weight==0:continue
    target=18+8*noise.fractal(Vector((x*.012,y*.012,11.4)),1.,2.,3)
    for px,py,height,rx,ry in peaks:
        dx,dy=(x-px)/rx,(y-py)/ry
        radius=math.hypot(dx,dy)
        if radius>=1.5:continue
        angle=math.atan2(dy,dx)
        radial=radius/(1+.11*math.sin(angle*3+px*.01)+.055*math.sin(angle*7))
        ridge=max(0,1-radial/1.5)**1.25
        spur=1-.16*math.sin(angle*3+radius*.2)**2*min(1,radial)
        target=max(target,18+(height-18)*ridge*spur)
    detail=5.3*noise.fractal(Vector((x*.041,y*.041,19.9)),1.,2.,3)
    target+=detail*smooth(28,85,target)
    vertex.co.z=z*(1-weight)+target*weight
    changed+=1
mesh.update()
assert changed>6000
assert all((v.co-p).length<.00001 for v,p in zip(mesh.vertices,original)
    if math.hypot(p.x-max(-120,min(120,p.x)),p.y-max(-130,min(150,p.y)))<=52), 'Seam changed'
colors=mesh.color_attributes['Color']
for poly in mesh.polygons:
    poly.use_smooth=poly.normal.z>.82
    slope=1-smooth(.45,.84,poly.normal.z)
    for li in poly.loop_indices:
        v=mesh.vertices[mesh.loops[li].vertex_index].co
        # Snow follows exposed upper bowls and rocky ridges, rather than one horizontal band.
        waveline=129+9*math.sin(v.x*.024+v.y*.031)+6*math.sin(v.y*.056-v.x*.018)
        snow=smooth(waveline-15,waveline+14,v.z)*(1-.52*slope)
        variation=1+.065*noise.fractal(Vector((v.x*.023,v.y*.023,4.3)),1.,2.,3)
        base=[(.16,.27,.095)[k]*(1-slope)+(.235,.29,.34)[k]*slope for k in range(3)]
        colors.data[li].color=(*(variation*(base[k]*(1-snow)+(.66,.73,.78)[k]*snow) for k in range(3)),1)
for name in manifest['assets']:
    if name!=obj.name:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
bpy.ops.export_scene.fbx(filepath=str(OUT/(obj.name+'.fbx')),use_selection=True,object_types={'MESH'},
    axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
manifest['mesh_source_versions']={name:'v041' for name in manifest['assets'] if name!=obj.name}
manifest['stage']='REFERENCE_MOUNTAIN_MATCH_REQUIRES_REBAKE_AND_CAPTURE'
manifest['geometry_source_version']='v041'
manifest['geometry_changes']=['Separated angular alpine peaks and asymmetric saddles in existing surrounding mesh',
    'Terrain-slope snow exposure follows ridge shapes instead of a level white cap',
    'Village terrain, structures, river, forest positions, camera transforms and lighting unchanged']
manifest['reference_match']['mountain_control_peaks']=peaks
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'mountain_match_report.json').write_text(json.dumps({'changed_vertices':changed,'seam_preserved':True,
    'peak_controls':peaks,'target_max_height_m':max(v.co.z for v in mesh.vertices)},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v042.blend'))
print('REFERENCE_MOUNTAIN_GEOMETRY',changed)
