"""Replace parallel escarpment bands with asymmetric connected mesa promontories."""
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

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
source,version=args[:2] if len(args)>=2 else ('v022','v023')
BASE=ROOT/source;OUT=ROOT/version
OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/('SEKAI_Valley_Terrain_'+source+'.blend')))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
terrain=bpy.data.objects['SM_VIL_Valley_Terrain_v009'];mesh=terrain.data
with bpy.data.libraries.load(str(ROOT/'v013'/'SEKAI_Valley_Terrain_v013.blend'),link=False) as (src,dst):
    dst.objects=['SM_VIL_Valley_Terrain_v009']
baseline=dst.objects[0]
assert len(baseline.data.vertices)==len(mesh.vertices),'Baseline topology changed'

def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)

# Their positions define alternate inward buttresses and open side valleys.
features=[(-86,-78,17,17,20),(-88,-28,25,21,26),(-80,23,30,20,27),
          (-91,70,39,23,28),(-68,113,44,26,22),
          (88,-78,18,19,22),(92,-27,25,21,25),(80,31,29,19,27),(86,91,37,25,28)]
changed=0
for index,v in enumerate(mesh.vertices):
    x,y,z=v.co;base=baseline.data.vertices[index].co
    assert abs(x-base.x)<.001 and abs(y-base.y)<.001
    if abs(x)<58:continue
    height=base.z
    for cx,cy,top,rx,ry in features:
        dx=(x-cx)/rx;dy=(y-cy)/ry
        if version=='v025':
            # Extend each inward rock nose back into its parent mountain ridge.
            dx=max(0,dx if cx<0 else -dx)
        angle=math.atan2(dy,dx)
        edge=1+.085*math.sin(angle*3+cy*.02)+.055*math.sin(angle*7-cx*.03)
        radius=math.hypot(dx,dy)/edge
        if radius>1.48:continue
        buttress=.55*math.sin(x*.18+y*.11)+.3*math.sin(y*.29-x*.09)
        mesa=top+1.1*math.sin(y*.057+x*.041)+buttress
        if version=='v025':
            mesa=top+2.1*math.sin(y*.079+cx*.037)+1.6*math.sin(x*.095-y*.083)
            mesa+=max(0,abs(x)-abs(cx))*.16
            front=1-smooth(.72,1.07,radius)
        else:
            front=1-smooth(.77,1.02,radius)
        foot=(1-smooth(.96,1.48,radius))*.20
        elevation=base.z+(max(base.z,mesa)-base.z)*max(front,foot)
        height=max(height,elevation)
    boundary=(1-smooth(104,119,abs(x)))*smooth(-130,-105,y)*(1-smooth(120,150,y))
    v.co.z=base.z*(1-boundary)+height*boundary
    changed+=1
mesh.update()
colors=mesh.color_attributes['Color']
for p in mesh.polygons:
    a,b,c=[mesh.vertices[i].co for i in p.vertices[:3]]
    n=(b-a).cross(c-a).normalized()
    slope=smooth(.12,.65,1-max(0,n.z))
    p.use_smooth=n.z>.7
    for li in p.loop_indices:
        v=mesh.vertices[mesh.loops[li].vertex_index].co
        variation=1+.05*math.sin(v.x*.061+v.y*.079)+.025*math.sin(v.x*.23-v.y*.12)
        grass=(.16,.27,.095);rock=(.31,.35,.37)
        colors.data[li].color=(*(variation*(grass[k]*(1-slope)+rock[k]*slope) for k in range(3)),1)
bpy.data.objects.remove(baseline,do_unlink=True)
for name in manifest['assets']:
    if name!=terrain.name:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for texture in manifest.get('surface_color_textures',{}).values():
    shutil.copy2(BASE/(texture+'.png'),OUT/(texture+'.png'))
bpy.ops.object.select_all(action='DESELECT');terrain.select_set(True)
bpy.context.view_layer.objects.active=terrain
bpy.ops.export_scene.fbx(filepath=str(OUT/(terrain.name+'.fbx')),use_selection=True,object_types={'MESH'},
    axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
manifest['stage']='PROMONTORY_SCULPT_REQUIRES_COLOR_REBAKE_AND_UE_REVIEW'
manifest['geometry_source_version']=source
manifest['geometry_changes']=['Replaced parallel outer cliff benches with nine asymmetrical connected promontories',
    'Retained central terrain, routes, tree platform and all fixed cameras',
    'Authored stronger grass/rock slope colors; rebake required before UE review']
if version=='v025':
    manifest['geometry_changes']=['Connected inward promontories into rear mountain ridges',
        'Replaced flat oval mesa tops with uneven sloping crests',
        'Retained central terrain, tree platform, river, camera transforms and lighting']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'promontory_sculpt_report.json').write_text(json.dumps({'changed_vertices':changed,'features':features},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('SEKAI_Valley_Terrain_'+version+'.blend')))
print('SEKAI_PROMONTORIES_SCULPTED',OUT)
