"""Complete the existing service wing, preserving its roof and village layout."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import os
import sys
from pathlib import Path
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder, export_mesh

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
BASE,OUT=ROOT/'v056',ROOT/'v057'
OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v056.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
bpy.context.view_layer.update()
terrain=BVHTree.FromObject(bpy.data.objects['SM_VIL_Valley_Terrain_v009'],bpy.context.evaluated_depsgraph_get())
transform=Matrix.Translation(Vector((38,42,11.3)))@Matrix.Rotation(-.35,4,'Z')
mesh=MeshBuilder()
wood=mesh.material('MV_Timber_Dark');light=mesh.material('MV_Timber_Warm')
stone=[mesh.material('MV_Stone_'+str(i)) for i in range(3)]
glass=mesh.material('MV_Window_Amber')

def ground(x,y):
    p=transform@Vector((x,y,0))
    hit=terrain.ray_cast(Vector((p.x,p.y,160)),Vector((0,0,-1)),260)[0]
    assert hit is not None
    return hit.z-11.3

# Stone plinth reaches the actual slope; exposed courses remain under the wall.
supports=[]
for axis in ['side','rear']:
    length=5.55 if axis=='side' else 4.05
    count=math.ceil(length/.56)
    for i in range(count):
        a=-.55+i*length/count if axis=='side' else 5.35+i*length/count
        b=a+length/count
        x,y=(9.43,(a+b)*.5) if axis=='side' else ((a+b)*.5,5.03)
        bottom=min(ground(x,y),ground(x-.1,y-.1))-.15
        supports.append(bottom)
        top=.79
        if top<=bottom:continue
        mesh.block((x,y,(top+bottom)*.5),(.30,b-a,top-bottom) if axis=='side' else (b-a,.30,top-bottom),stone[0],bevel=0)
        for course in range(math.ceil((top-bottom)/.25)):
            lo=bottom+course*.25;hi=min(top,lo+.25)
            if hi-lo<.025:continue
            center=(x+.045,y,(lo+hi)*.5) if axis=='side' else (x,y+.04,(lo+hi)*.5)
            mesh.block(center,(.32,b-a-.015,hi-lo-.014) if axis=='side' else (b-a-.015,.32,hi-lo-.014),stone[(i+course)%3],bevel=.023)

# The formerly blank side receives a full timber frame and framed glazed windows.
for y in [-.47,1.32,3.15,4.92]:
    mesh.beam((9.57,y,.77),(9.57,y,3.61),.19,wood)
for z in [.85,3.55]:mesh.beam((9.57,-.62,z),(9.57,5.06,z),.22,wood)
for y in [1.3,3.15]:mesh.beam((9.58,y-.73,.98),(9.58,y+.68,1.66),.14,wood)
for y in [.43,4.02]:
    z=2.30
    mesh.block((9.61,y,z),(.08,1.04,1.17),glass,bevel=.006)
    for dy in [-.59,.59]:mesh.block((9.67,y+dy,z),(.14,.13,1.43),light)
    for dz in [-.66,.66]:mesh.block((9.67,y,z+dz),(.15,1.29,.13),light)
    mesh.block((9.70,y,z),(.08,.057,1.20),wood,bevel=.006)
    mesh.block((9.70,y,z),(.08,1.04,.055),wood,bevel=.006)
    mesh.block((9.82,y,z-.81),(.43,1.46,.17),light)
    for side in [-1,1]:
        for plank in range(3):
            mesh.block((9.62,y+side*.85+(plank-1)*.10,z),(.11,.09,1.22),light,bevel=.008)

# Rear service door, eave beam and diagonal braces complete the third elevation.
for x in [5.48,7.37,9.36]:mesh.beam((x,5.15,.77),(x,5.15,3.47),.18,wood)
for z in [.84,3.44]:mesh.beam((5.37,5.15,z),(9.49,5.15,z),.20,wood)
for x in [5.5,8.05]:mesh.beam((x,5.16,2.6),(x+.64,5.16,3.4),.13,wood)
for i in range(7):mesh.block((6.48+(i-3)*.16,5.21,1.84),(.147,.11,1.98),light,bevel=.011)
for x in [5.88,7.08]:mesh.beam((x,5.27,.79),(x,5.27,2.94),.14,wood)
mesh.beam((5.82,5.27,2.94),(7.14,5.27,2.94),.18,wood)
for z in [1.12,2.49]:mesh.block((6.48,5.29,z),(1.05,.06,.068),wood,bevel=.008)
# Two ground-supported service steps; no floating boxes on the sloping apron.
for i in range(2):
    x,y=6.48,5.53+i*.38;top=.70-i*.18;bottom=ground(x,y)-.14
    if top>bottom+.05:mesh.block((x,y,(top+bottom)*.5),(1.7,.41,top-bottom),stone[1+i],bevel=.025)

obj=mesh.build('SM_VIL_Tavern_ServiceWing_v057',transform)
export_mesh(obj,OUT/(obj.name+'.fbx'))
aliases=manifest.get('mesh_source_versions',{})
manifest['mesh_source_versions']={name:aliases.get(name,'v056') for name in manifest['assets']
    if name in aliases or (BASE/'ue_import.json').exists()}
for name in manifest['assets']:os.link(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):os.link(f,OUT/f.name)
manifest['assets'].append(obj.name)
manifest['geometry_source_version']='v056'
manifest['stage']='LAYERED_PLANTING_AND_SERVICE_WING_REQUIRES_UE_REVIEW'
manifest['geometry_changes']+=['Completed existing tavern service wing with side windows/shutters, timber braces, rear door and terrain-supported masonry and steps']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'service_wing_report.json').write_text(json.dumps({'polygon_count':len(obj.data.polygons),
    'foundation_bottoms_local_m':supports,'existing_roof_and_walls_retained':True,
    'status':'MODELED_NOT_VISUALLY_ACCEPTED'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v057.blend'))
print('SERVICE_WING_SAVED',len(obj.data.polygons))
