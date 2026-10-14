"""Re-seat new buildings on measured continuous land within their assigned zones."""
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
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder, export_mesh

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));BASE,OUT=ROOT/'v052',ROOT/'v055';OUT.mkdir(exist_ok=True)
assert not (OUT/'terrain_manifest.json').exists(), 'Never overwrite a completed checkpoint'
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v052.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text());bpy.context.view_layer.update()
bvh=BVHTree.FromObject(bpy.data.objects['SM_VIL_Valley_Terrain_v009'],bpy.context.evaluated_depsgraph_get())
forge=json.loads((ROOT/'v051/forge_report.json').read_text())
homes=json.loads((BASE/'homes_report.json').read_text())['houses']
rows=[('SM_VIL_Forge_OpenWorkshop_v051',forge['center_m'],-1.12,[50.5,20],-math.pi/2,10.6,10.5),
      ('SM_VIL_Home_PorchCottage_v052',homes[0]['center_m'],1.43,[-51,5],1.43,9,12),
      ('SM_VIL_Home_BalconySaltbox_v052',homes[1]['center_m'],1.78,[-49,58],1.78,9.8,11.8)]
reports=[];changed=[]
for name,old_center,old_angle,new_center,angle,w,d in rows:
    rotation=Matrix.Rotation(angle,4,'Z');heights=[]
    for x in [-w/2,0,w/2]:
        for y in [-d/2,0,d/2]:
            p=rotation@Vector((x,y,0));hit=bvh.ray_cast(Vector((new_center[0]+p.x,new_center[1]+p.y,180)),Vector((0,0,-1)),300)[0]
            assert hit is not None;heights.append(hit.z)
    assert max(heights)-min(heights)<(.65 if 'Forge' in name else .35),(name,heights)
    # Forge front-center crosses the bench's narrow lip; the ground-reaching
    # court below supports that lip. The other core points must be continuous.
    if 'Forge' in name:
        core=[h for index,h in enumerate(heights) if index!=3]
        assert max(core)-min(core)<.25,(name,core)
    base=max(heights)-.13
    old=Matrix.Translation(Vector(old_center))@Matrix.Rotation(old_angle,4,'Z')
    new=Matrix.Translation(Vector((*new_center,base)))@rotation
    delta=new@old.inverted();obj=bpy.data.objects[name]
    for v in obj.data.vertices:v.co=delta@v.co
    obj.data.update();export_mesh(obj,OUT/(name+'.fbx'));changed.append(name)
    reports.append({'name':name,'old_center_m':old_center,'new_center_m':[*new_center,base],
        'rotation_radians':angle,'support_height_range_m':max(heights)-min(heights),
        'ground_samples_m':heights,'status':'GEOMETRY_GROUNDED_REQUIRES_UE_REVIEW'})
    manifest['instances']=[row for row in manifest.get('instances',[]) if
        math.hypot(row['position_m'][0]-new_center[0],row['position_m'][1]-new_center[1])>max(w,d)*.60+2.7]
    if 'Forge' in name:
        court=MeshBuilder()
        mats=[court.material('MV_Forge_Stone_'+label) for label in ['Dark','Warm','Light']]
        def local_ground(x,y):
            p=new@Vector((x,y,0));hit=bvh.ray_cast(Vector((p.x,p.y,180)),Vector((0,0,-1)),300)[0]
            assert hit is not None
            return hit.z-base
        # The porch projects off the natural bench. A solid forecourt supports
        # every post and the anvil/workbench; its face has real masonry courses.
        for column in range(18):
            x=-5.45+column*.64
            for row in range(5):
                y=-7.45+row*.56;bottom=local_ground(x,y)-.18;top=.40
                court.block((x,y,(bottom+top)*.5),(.66,.58,top-bottom),mats[0],bevel=0)
            bottom=local_ground(x,-7.72)-.19;course_count=math.ceil((.43-bottom)/.27)
            for course in range(course_count):
                lo=bottom+course*.27;hi=min(.43,lo+.27)
                if hi-lo>.025:court.block((x,-7.76,(lo+hi)*.5),(.62,.29,hi-lo-.01),mats[(column+course)%3],bevel=.023)
        for step in range(12):
            y=-8.02-step*.39;top=.4-.17*step;bottom=local_ground(0,y)-.15
            if top<bottom+.12:break
            court.block((0,y,(top+bottom)*.5),(3.2,.41,top-bottom),mats[step%3],bevel=.025)
        court_obj=court.build('SM_VIL_Forge_Forecourt_v055',new)
        manifest['assets'].append(court_obj.name);changed.append(court_obj.name)
        export_mesh(court_obj,OUT/(court_obj.name+'.fbx'))
        reports[-1]['forecourt_support']='Ground-reaching solid masonry court and descending steps'
manifest['mesh_source_versions']={name:manifest.get('mesh_source_versions',{}).get(name,'v052')
                                  for name in manifest['assets'] if name not in changed}
for name in manifest['assets']:
    if name not in changed:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
manifest['geometry_source_version']='v052';manifest['stage']='GROUNDED_NEW_BUILDINGS_REQUIRES_REVIEW'
manifest['geometry_changes']=['Corrected forge placement onto its existing lower terrace, rather than across the high cliff',
    'Shifted each new home four metres within its existing residential zone to continuous ground',
    'Building geometry, terrain, village route and original six cameras/daylight retained']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'building_grounding_report.json').write_text(json.dumps(reports,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v055.blend'))
print('BUILDINGS_GROUNDED',reports)
