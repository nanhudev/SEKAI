"""Complete existing cottage facades and grounded open-entry stone courtyards."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy,ast,json,math,random,os,sys,shutil
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder,export_mesh
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/'v092'
out=Path(str(_SEKAI_ROOT / 'environment_production/Terrain/v093'));out.mkdir(exist_ok=False)
pass  # Checkpoints stay inside the portable project.
bpy.ops.wm.open_mainfile(filepath=str(base/'SEKAI_Valley_Terrain_v092.blend'))
m=json.loads((base/'terrain_manifest.json').read_text())
for name in m['assets']:m.setdefault('mesh_source_versions',{}).setdefault(name,'v092')
for p in base.iterdir():
    if p.suffix.lower() in ['.fbx','.png']:os.link(p,out/p.name)
    elif p.name=='material_sources.json':shutil.copy2(p,out/p.name)
deps=bpy.context.evaluated_depsgraph_get();terrain=BVHTree.FromObject(bpy.data.objects['SM_VIL_Valley_Terrain_v009'],deps)
solid=MeshBuilder();plants=MeshBuilder();rng=random.Random(26101493)
wood=solid.material('MV_Home_Timber_Dark');light=solid.material('MV_Home_Timber_Light')
stone=[solid.material('MV_Home_Stone_'+str(i)) for i in range(3)]
slate=[solid.material('MV_Home_Slate_'+str(i)) for i in range(3)]
leaf_mats=[plants.material('MV_Foliage_Leaf_Understory'+s) for s in ['Deep','Mid','Sun']]
stem=plants.material('MV_Foliage_Leaf_UnderstoryStem');cream=plants.material('MV_Foliage_Leaf_DaisyCream');blue=plants.material('MV_Foliage_Leaf_WildBlue');gold=plants.material('MV_Foliage_Leaf_PollenGold')
# Reuse the established curved leaf geometry with the plant builder bound as mesh.
mesh=plants
tree=ast.parse((Path(__file__).parent/'rebuild_ground_plants_v049.py').read_text())
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='leaf'],type_ignores=[]),'existing_leaf_geometry','exec'))
reports=[]
sites=[('east_porch','v068',0,37,4,-math.pi/2,6.4,7.0),('east_balcony','v068',1,30,18,-math.pi/2,6.4,7.0),('west_porch','v078',0,-52,28,1.43,6.2,7.2),('west_balcony','v078',1,-46,73,1.78,6.4,7.0)]
for label,report_version,variant,cx,cy,angle,w,d in sites:
    data=json.loads((root/report_version/'homes_report.json').read_text());z=data['houses'][variant]['center_m'][2]
    rotation=Matrix.Rotation(angle,4,'Z');offset=Vector((cx,cy,z))
    def point(x,y,h):return rotation@Vector((x,y,h))+offset
    def ground(x,y):
        p=point(x,y,0);hit=terrain.ray_cast(Vector((p.x,p.y,160)),Vector((0,0,-1)),260)[0]
        assert hit is not None
        return hit.z-z
    def block(center,size,material,bevel=.02):
        p=point(*center);solid.block(p,size,material,angle=angle,bevel=bevel)
    def beam(a,b,width,material=wood):solid.beam(point(*a),point(*b),width,material)
    # Rear service-door canopy: actual roof plates, ground-reaching posts and braces.
    for x in [-1.45,1.45]:
        foot=ground(x,d/2+1.70)-.08
        beam((x,d/2+1.70,foot),(x,d/2+1.70,2.50),.16)
        beam((x,d/2+1.70,1.97),(x,d/2+.90,2.73),.13)
    beam((-1.65,d/2+1.70,2.46),(1.65,d/2+1.70,2.46),.18,light)
    beam((-1.65,d/2+.11,2.95),(1.65,d/2+.11,2.95),.17,light)
    for row in range(5):
        ya=d/2+.06+row*.36;yb=ya+.38;za=2.96-row*.105;zb=za-.11
        for col in range(7):
            xa=-1.70+col*.49;xb=xa+.48
            ps=[point(xa,ya,za),point(xb,ya,za),point(xb,yb,zb),point(xa,yb,zb)]
            lower=[p-Vector((0,0,.045)) for p in ps];material=slate[(row+col+variant)%3]
            solid.face(ps,material);solid.face(list(reversed(lower)),material)
            for i in range(4):j=(i+1)%4;solid.face([ps[i],lower[i],lower[j],ps[j]],material)
    # Bracket-supported upper flower boxes on both gable faces.
    for sign in [-1,1]:
        for x in [-w*.27,w*.27]:
            y=sign*(d/2+.40);bottom=3.58;top=3.84
            block((x,y,bottom+.035),(1.28,.40,.07),wood)
            for dy in [-.20,.20]:block((x,y+dy,(bottom+top)/2),(1.32,.055,top-bottom),light)
            for dx in [-.64,.64]:block((x+dx,y,(bottom+top)/2),(.055,.43,top-bottom),wood)
            for dx in [-.39,.39]:beam((x+dx,sign*(d/2+.17),3.21),(x+dx,y,3.58),.075)
            for j in range(27):
                lx=x+rng.uniform(-.55,.55);ly=y+rng.uniform(-.14,.14)
                p=point(lx,ly,3.77);head=p+Vector((0,0,rng.uniform(.17,.30)))
                plants.tube([p,head],[.004,.002],stem,4)
                for k in range(5):
                    a=k*math.tau/5;leaf(head,(math.cos(a),math.sin(a),.1),.065,.028,cream if j%2 else blue)
                leaf(p,(math.cos(j),math.sin(j),-.2),.14,.06,rng.choice(leaf_mats))
                plants.tube([head,head+Vector((0,0,.01))],[.017,.012],gold,6)
    # Small front courtyard with side stone cheeks and a broad open front entry.
    for sign in [-1,1]:
        x=sign*(w/2+.47)
        for i in range(5):
            y=-d/2-2.10-i*.64;floor=ground(x,y)-.07;top=ground(x,y)+.40
            for course in range(2):
                bottom=floor+(top-floor)*course/2;upper=floor+(top-floor)*(course+1)/2
                block((x,y,(bottom+upper)/2),(.39,.63,upper-bottom),stone[(i+course)%3],.027)
            block((x,y,top+.03),(.47,.66,.09),stone[2],.023)
    for i in range(6):
        for j in range(5):
            x=-1.65+(i+.5)*.55;y=-d/2-1.95-(j+.5)*.55;h=ground(x,y)
            block((x,y,h-.035),(.53,.53,.13),stone[(i+2*j)%3],.025)
    reports.append({'house':label,'centre_m':[cx,cy,z],'rear_posts_reach_sampled_ground':True,'courtyard_front_open':True})
for builder,name in [(solid,'SM_VIL_Home_Courtyards_v093'),(plants,'SM_VIL_Home_Flowerbox_Planting_v093')]:
    obj=builder.build(name);export_mesh(obj,out/(name+'.fbx'));m['assets'].append(name)
m.setdefault('noncollision_assets',[]).append('SM_VIL_Home_Flowerbox_Planting_v093')
m['version']='v093';m['geometry_changes']=['Four cottage rear service canopies, bracket-supported flower boxes and open-entry stone courtyards','Existing house envelopes, terrain, bridge, plaza, tree, cameras and lighting preserved']
(out/'terrain_manifest.json').write_text(json.dumps(m,indent=2));(out/'courtyard_support_report.json').write_text(json.dumps({'houses':reports,'scope':'Source attachment/support, requires native review; not full walking acceptance'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(out/'SEKAI_Valley_Terrain_v093.blend'))
