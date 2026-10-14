"""Grounded irregular grass/fern/shrub margins using the existing plant geometry."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy,ast,json,math,random,os,sys,shutil
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder,export_mesh
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/'v071'
target=Path(str(_SEKAI_ROOT / 'environment_production/Terrain/v072'));target.mkdir(exist_ok=False)
out=root/'v072';pass  # Checkpoints stay inside the portable project.
bpy.ops.wm.open_mainfile(filepath=str(base/'SEKAI_Valley_Terrain_v071.blend'))
manifest=json.loads((base/'terrain_manifest.json').read_text())
for name in manifest['assets']:manifest.setdefault('mesh_source_versions',{}).setdefault(name,'v071')
for p in base.iterdir():
    if p.suffix.lower() in ['.fbx','.png']:os.link(p,target/p.name)
if (base/'material_sources.json').exists():shutil.copy2(base/'material_sources.json',out/'material_sources.json')
bpy.context.view_layer.update()
bvh=BVHTree.FromObject(bpy.data.objects['SM_VIL_Valley_Terrain_v009'],bpy.context.evaluated_depsgraph_get())
mesh=MeshBuilder();rng=random.Random(26101472);layered=True
palette={k:tuple(v) for k,v in manifest['material_palette'].items() if k.startswith('MV_Foliage_Leaf_Understory') or k in ['MV_Foliage_Leaf_DaisyCream','MV_Foliage_Leaf_WildBlue','MV_Foliage_Leaf_PollenGold']}
indices={k:mesh.material(k,c) for k,c in palette.items()}
leaf_indices=[indices['MV_Foliage_Leaf_Understory'+s] for s in ['Deep','Mid','Sun']]
stem_index=indices['MV_Foliage_Leaf_UnderstoryStem']
# Reuse only the established geometry functions, without executing the old stage.
old=ast.parse((Path(__file__).parent/'rebuild_ground_plants_v049.py').read_text())
functions=[n for n in old.body if isinstance(n,ast.FunctionDef) and n.name in ['leaf','shrub','fern','grass','flower']]
exec(compile(ast.Module(body=functions,type_ignores=[]),'existing_plant_geometry','exec'))
buildings=[]
for ob in bpy.data.objects:
    if ob.type=='MESH' and ('Home_' in ob.name or 'Tavern_Placed' in ob.name or 'OpenWorkshop' in ob.name):
        corners=[ob.matrix_world@Vector(v) for v in ob.bound_box]
        buildings.append((min(v.x for v in corners)-.45,max(v.x for v in corners)+.45,min(v.y for v in corners)-.45,max(v.y for v in corners)+.45))
route=[Vector(p) for p in manifest['route_m']];counts={'grass':0,'fern':0,'shrub':0,'flower':0}
for segment,(a,b) in enumerate(zip(route,route[1:])):
    if segment==3:continue
    direction=(b-a).to_2d().normalized();side=Vector((-direction.y,direction.x))
    length=(b-a).to_2d().length
    for station in range(int(length/.52)):
        t=(station+.5)/max(1,int(length/.52));center=a.lerp(b,t)
        # Broken coverage, broader clusters, and open gaps avoid a hedge ribbon.
        if rng.random()>.68+.18*math.sin(station*.31+segment):continue
        for sign in [-1,1]:
            for band in range(rng.choice([2,3,4])):
                offset=sign*(3.0+band*.56+rng.uniform(-.16,.22))
                x=center.x+side.x*offset+direction.x*rng.uniform(-.23,.23)
                y=center.y+side.y*offset+direction.y*rng.uniform(-.23,.23)
                if math.hypot(x-20,y-13)<13.8:continue
                if any(x0<x<x1 and y0<y<y1 for x0,x1,y0,y1 in buildings):continue
                hit,normal,_,_=bvh.ray_cast(Vector((x,y,180)),Vector((0,0,-1)),300)
                if hit is None or normal.z<.65 or abs(hit.z-center.z)>1.5:continue
                grass(x,y,hit.z-.014,rng.uniform(.75,1.5));counts['grass']+=1
                if band>0 and rng.random()<.065:
                    shrub(x,y,hit.z,rng.uniform(.30,.65),rng.uniform(.28,.48));counts['shrub']+=1
                elif band>0 and rng.random()<.12:
                    fern(x,y,hit.z-.01,rng.uniform(.55,1.15));counts['fern']+=1
                if rng.random()<.065:flower(x,y,hit.z,rng.random()<.5);counts['flower']+=1
ob=mesh.build('SM_VIL_Route_Planting_v072');export_mesh(ob,out/(ob.name+'.fbx'))
manifest['assets'].append(ob.name);manifest.setdefault('noncollision_assets',[]).append(ob.name)
manifest['version']='v072';manifest['geometry_changes']=['Grounded grass, fern, shrub and wildflower route margins; terrain, houses, bridge, cameras and lighting preserved']
(out/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(out/'planting_report.json').write_text(json.dumps({'counts':counts,'scope':'Source placement only; requires actual fixed and near-route review'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(out/'SEKAI_Valley_Terrain_v072.blend'))
print('ROUTE_PLANTING_SAVED',counts)
