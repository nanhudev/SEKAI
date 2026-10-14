"""Compose grounded terrace, root and cottage gardens using existing plant leaves."""
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
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/'v086'
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
version=args[0] if args else 'v087'
out=Path(str(_SEKAI_RUNTIME / 'Checkpoints'))/version;out.mkdir(exist_ok=False)
pass  # Checkpoints stay inside the portable project.
bpy.ops.wm.open_mainfile(filepath=str(base/'SEKAI_Valley_Terrain_v086.blend'))
m=json.loads((base/'terrain_manifest.json').read_text())
for name in m['assets']:m.setdefault('mesh_source_versions',{}).setdefault(name,'v086')
for p in base.iterdir():
    if p.suffix.lower() in ['.fbx','.png']:os.link(p,out/p.name)
    elif p.name=='material_sources.json':shutil.copy2(p,out/p.name)
bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
surfaces=[BVHTree.FromObject(bpy.data.objects[n],deps) for n in ['SM_VIL_Valley_Terrain_v009','SM_VIL_Plaza_PavingAndTreeTerrace']]
mesh=MeshBuilder();rng=random.Random(26101487);layered=True
palette={k:tuple(v) for k,v in m['material_palette'].items() if k.startswith('MV_Foliage_Leaf_Understory') or k in ['MV_Foliage_Leaf_DaisyCream','MV_Foliage_Leaf_WildBlue','MV_Foliage_Leaf_PollenGold']}
indices={k:mesh.material(k,c) for k,c in palette.items()}
leaf_indices=[indices['MV_Foliage_Leaf_Understory'+s] for s in ['Deep','Mid','Sun']]
stem_index=indices['MV_Foliage_Leaf_UnderstoryStem']
old=ast.parse((Path(__file__).parent/'rebuild_ground_plants_v049.py').read_text())
functions=[n for n in old.body if isinstance(n,ast.FunctionDef) and n.name in ['leaf','shrub','fern','grass','flower']]
exec(compile(ast.Module(body=functions,type_ignores=[]),'existing_plant_geometry','exec'))
route=[Vector(p).to_2d() for p in m['route_m']]
buildings=[]
for obj in bpy.data.objects:
    if obj.type=='MESH' and 'Footings' not in obj.name and ('Home_' in obj.name or 'Tavern_Placed' in obj.name or 'OpenWorkshop' in obj.name):
        ps=[obj.matrix_world@Vector(v) for v in obj.bound_box]
        buildings.append((min(p.x for p in ps),max(p.x for p in ps),min(p.y for p in ps),max(p.y for p in ps)))

def route_distance(x,y):
    p=Vector((x,y));result=1000
    for a,b in zip(route,route[1:]):
        d=b-a;t=max(0,min(1,(p-a).dot(d)/max(.001,d.length_squared)))
        result=min(result,(p-a-d*t).length)
    return result

def surface(x,y):
    hits=[tree.ray_cast(Vector((x,y,180)),Vector((0,0,-1)),300) for tree in surfaces]
    hits=[row for row in hits if row[0] is not None and row[1].z>.68]
    if not hits:return None
    return max(row[0].z for row in hits)

def allowed(x,y):
    if route_distance(x,y)<3.2:return False
    if -5.2<x<3.2 and 23<y<39:return False
    if math.hypot(x-20,y-13)<13.2:return False
    return not any(x0-.7<x<x1+.7 and y0-.7<y<y1+.7 for x0,x1,y0,y1 in buildings)

def full_shrub(x,y,z,height,radius):
    shrub(x,y,z,height,radius)
    # Leaf sprays fill the seven existing stems; their outer tips stay irregular.
    for j in range(210):
        a=rng.random()*math.tau;r=math.sqrt(rng.random())
        p=Vector((x+math.cos(a)*radius*r,y+math.sin(a)*radius*r,z+height*(.30+.68*rng.random())*math.sqrt(1-.35*r*r)))
        length=rng.uniform(.095,.16)
        leaf(p,(math.cos(a),math.sin(a),rng.uniform(-.3,.6)),length,length*.46,rng.choices(leaf_indices,weights=[2,4,3])[0])

patches=[]
# Masonry foot and stair cheeks: clear the broad central stair opening.
for i in range(38):
    a=math.tau*i/38+.11;r=13.2+rng.uniform(-.1,.6)
    x,y=-1+r*math.cos(a),47+r*math.sin(a)
    if y<39 and -7<x<5:continue
    patches.append(('terrace_foot',x,y,.85,1.0,rng.uniform(.5,.9)))
for x in [-7.2,5.4]:
    for y in [25.5,28.2,31,33.5]:patches.append(('stair_cheek',x,y,.8,1.05,.7))
# Foreground plaza rim: overlapping pockets connect the stone edge to the stairs.
for y in [-1,2,5,8,11,14,17,20,23]:
    patches.append(('plaza_west_rim',4.7+.5*math.sin(y*.31),y,1.4,1.85,.75))
for y in [5,8,11,14,17,20]:
    patches.append(('plaza_east_rim',35.3+.4*math.sin(y*.4),y,1.3,1.7,.72))
# Roots at the top, mainly side and rear pockets with the front entrance open.
for i in range(18):
    a=.1+i*math.tau/18
    x,y=-1+8.2*math.cos(a),47+8.2*math.sin(a)
    if y<44 and -7<x<5:continue
    patches.append(('root_pocket',x,y,.8,.8,.45))
# Gardens sit beyond actual building bounds; middle door/porch approaches stay open.
for x0,x1,y0,y1 in buildings:
    for x,y in [(x0-1.4,y0-1.5),(x1+1.5,y0-1.4),(x0-1.4,y1+1.4)]:
        patches.append(('cottage_corner',x,y,1.15,1.0,.7))

report=[]
for label,cx,cy,rx,ry,height in patches:
    if not allowed(cx,cy):continue
    z=surface(cx,cy)
    if z is None:continue
    shrubs=0;flowers=0
    for j in range(4):
        a=j*2.399+.25;r=math.sqrt((j+.4)/4)*.8
        x,y=cx+math.cos(a)*rx*r,cy+math.sin(a)*ry*r
        if not allowed(x,y):continue
        h=surface(x,y)
        if h is None or abs(h-z)>.5:continue
        full_shrub(x,y,h-.012,height*rng.uniform(.7,1.15),rng.uniform(.38,.58));shrubs+=1
    for j in range(48):
        a=rng.random()*math.tau;r=math.sqrt(rng.random())*1.12
        x,y=cx+math.cos(a)*rx*r,cy+math.sin(a)*ry*r
        if not allowed(x,y):continue
        h=surface(x,y)
        if h is None or abs(h-z)>.55:continue
        if j%3==0:flower(x,y,h-.008,j%2==0);flowers+=1
        else:grass(x,y,h-.008,rng.uniform(.8,1.6))
        if j%13==0:fern(x,y,h-.012,rng.uniform(.85,1.3))
    report.append({'kind':label,'centre_m':[cx,cy,z],'shrubs':shrubs,'flowers':flowers})
obj=mesh.build('SM_VIL_Terrace_Gardens_'+version);export_mesh(obj,out/(obj.name+'.fbx'))
m['assets'].append(obj.name);m.setdefault('noncollision_assets',[]).append(obj.name)
m['version']=version;m['geometry_changes']=['Grounded dense terrace/root/cottage plant pockets and connected foreground plaza rims with open route and stair clearance','Buildings, tree, bridge, terrain, cameras and lighting unchanged']
(out/'terrain_manifest.json').write_text(json.dumps(m,indent=2))
(out/'garden_placement_report.json').write_text(json.dumps({'patches':report,'route_centre_clearance_m':3.2,'scope':'Source placement; requires native review, not walking acceptance'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(out/('SEKAI_Valley_Terrain_'+version+'.blend')))
