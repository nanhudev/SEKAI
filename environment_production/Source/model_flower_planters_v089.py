"""Stone flower beds on sampled plaza paving, with the central route kept clear."""
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
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/'v088'
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
version=args[0] if args else 'v089'
out=Path(str(_SEKAI_RUNTIME / 'Checkpoints'))/version;out.mkdir(exist_ok=False)
pass  # Checkpoints stay inside the portable project.
bpy.ops.wm.open_mainfile(filepath=str(base/'SEKAI_Valley_Terrain_v088.blend'))
m=json.loads((base/'terrain_manifest.json').read_text())
for name in m['assets']:m.setdefault('mesh_source_versions',{}).setdefault(name,'v088')
for p in base.iterdir():
    if p.suffix.lower() in ['.fbx','.png']:os.link(p,out/p.name)
    elif p.name=='material_sources.json':shutil.copy2(p,out/p.name)
deps=bpy.context.evaluated_depsgraph_get()
surfaces=[BVHTree.FromObject(bpy.data.objects[n],deps) for n in ['SM_VIL_Valley_Terrain_v009','SM_VIL_Plaza_PavingAndTreeTerrace']]
def floor(x,y):
    hits=[tree.ray_cast(Vector((x,y,160)),Vector((0,0,-1)),260)[0] for tree in surfaces]
    return max(p.z for p in hits if p is not None)
stone=MeshBuilder();mesh=MeshBuilder();rng=random.Random(26101489);layered=True
stone_indices=[stone.material('MV_Plaza_Stone_%02d'%i) for i in range(4)]
soil=stone.material('MV_PlantedSoil',(.12,.10,.065));m['material_palette']['MV_PlantedSoil']=[.12,.10,.065]
palette={k:tuple(v) for k,v in m['material_palette'].items() if k.startswith('MV_Foliage_Leaf_Understory') or k in ['MV_Foliage_Leaf_DaisyCream','MV_Foliage_Leaf_WildBlue','MV_Foliage_Leaf_PollenGold']}
indices={k:mesh.material(k,c) for k,c in palette.items()}
leaf_indices=[indices['MV_Foliage_Leaf_Understory'+s] for s in ['Deep','Mid','Sun']]
stem_index=indices['MV_Foliage_Leaf_UnderstoryStem']
tree=ast.parse((Path(__file__).parent/'rebuild_ground_plants_v049.py').read_text())
functions=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ['leaf','shrub','fern','grass']]
exec(compile(ast.Module(body=functions,type_ignores=[]),'existing_plant_geometry','exec'))

def bloom(x,y,z,blue):
    height=rng.uniform(.28,.53);head=Vector((x,y,z+height))
    mesh.tube([(x,y,z),head],[.006,.003],stem_index,5)
    leaf((x,y,z+height*.42),(1,.3,.45),.11,.038,leaf_indices[1])
    radius=rng.uniform(.065,.095);count=5 if blue else 7
    for i in range(count):
        a=i*math.tau/count
        leaf(head,(math.cos(a),math.sin(a),.16),radius,radius*.44,indices['MV_Foliage_Leaf_WildBlue' if blue else 'MV_Foliage_Leaf_DaisyCream'])
    mesh.tube([head,head+Vector((0,0,.014))],[.023,.018],indices['MV_Foliage_Leaf_PollenGold'],8)

report=[]
for label,cx,cy,w,d in [('plaza_west_front',11.8,3.2,5.4,1.85),('plaza_east_side',30.8,9.0,3.5,1.65)]:
    samples=[floor(cx+x,cy+y) for x in [-w/2,0,w/2] for y in [-d/2,0,d/2]]
    assert max(samples)-min(samples)<.45,samples
    top=max(samples)+.41;soil_top=top-.10
    stone.block((cx,cy,(min(samples)-.08+soil_top)*.5),(w-.38,d-.38,soil_top-min(samples)+.08),soil,bevel=.01)
    for sign in [-1,1]:
        for along_x,length,constant in [(True,w,cy+sign*(d/2-.16)),(False,d-.64,cx+sign*(w/2-.16))]:
            centre=cx if along_x else cy
            for course in range(2):
                cuts=[-length/2]+[t-length/2 for t in [(.34 if course else .64)+j*.64 for j in range(math.ceil(length/.64))] if t<length-.12]+[length/2]
                for left,right in zip(cuts,cuts[1:]):
                    position=centre+(left+right)*.5
                    x,y=(position,constant) if along_x else (constant,position)
                    low=floor(x,y)-.06;mid=(low+top-.08)*.5
                    bottom,upper=(low,mid) if course==0 else (mid,top-.08)
                    size=(right-left-.012,.34,upper-bottom) if along_x else (.34,right-left-.012,upper-bottom)
                    stone.block((x,y,(bottom+upper)*.5),size,rng.choice(stone_indices),bevel=.025)
            count=math.ceil(length/.8)
            for j in range(count):
                position=centre-length/2+(j+.5)*length/count
                x,y=(position,constant) if along_x else (constant,position)
                size=(length/count-.008,.4,.085) if along_x else (.4,length/count-.008,.085)
                stone.block((x,y,top-.04),size,rng.choice(stone_indices),bevel=.02)
    for j in range(9):
        x=cx+rng.uniform(-w/2+.45,w/2-.45);y=cy+rng.uniform(-d/2+.35,d/2-.35)
        shrub(x,y,soil_top-.015,rng.uniform(.35,.55),rng.uniform(.28,.42))
        fern(x,y,soil_top-.01,rng.uniform(.65,.95))
    for j in range(int(w*d*28)):
        x=cx+rng.uniform(-w/2+.23,w/2-.23);y=cy+rng.uniform(-d/2+.23,d/2-.23)
        if j%3:bloom(x,y,soil_top-.008,j%2==0)
        else:grass(x,y,soil_top-.01,rng.uniform(.8,1.2))
    report.append({'name':label,'centre':[cx,cy],'size':[w,d],'sampled_floor_m':samples,'stone_top_m':top,'soil_top_m':soil_top})
for builder,name in [(stone,'SM_VIL_Plaza_FlowerPlanters_'+version),(mesh,'SM_VIL_Planter_Planting_'+version)]:
    obj=builder.build(name);export_mesh(obj,out/(name+'.fbx'));m['assets'].append(name)
m.setdefault('noncollision_assets',[]).append('SM_VIL_Planter_Planting_'+version)
m['version']=version;m['geometry_changes']=['Sampled low two-course stone plaza flower planters with caps and white-blue blooms; central road remains open','Existing terrain, bridge, tree, houses, cameras and lighting preserved']
(out/'terrain_manifest.json').write_text(json.dumps(m,indent=2))
(out/'planter_support_report.json').write_text(json.dumps({'beds':report,'scope':'Source support only; requires native camera and route review'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(out/('SEKAI_Valley_Terrain_'+version+'.blend')))
