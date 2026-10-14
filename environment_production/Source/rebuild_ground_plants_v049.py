"""Replace oversized angular tufts with composed, human-scale planted beds."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import random
import shutil
import sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder, export_mesh

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
source,version=args[:2] if len(args)>=2 else ('v048','v050')
layered=len(args)>2 and args[2]=='layered'
BASE,OUT=ROOT/source,ROOT/version
OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/('SEKAI_Valley_Terrain_'+source+'.blend')))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
name='SM_VIL_Plaza_Planting_v044';bpy.data.objects.remove(bpy.data.objects[name],do_unlink=True)
bpy.context.view_layer.update()
bvh=BVHTree.FromObject(bpy.data.objects['SM_VIL_Valley_Terrain_v009'],bpy.context.evaluated_depsgraph_get())
rng=random.Random(26101249);mesh=MeshBuilder()
palette={
 'MV_Foliage_Leaf_UnderstoryDeep':(.045,.125,.023),
 'MV_Foliage_Leaf_UnderstoryMid':(.12,.24,.038),
 'MV_Foliage_Leaf_UnderstorySun':(.23,.34,.067),
 'MV_Foliage_Leaf_UnderstoryStem':(.13,.17,.044),
 'MV_Foliage_Leaf_DaisyCream':(.78,.77,.64),
 'MV_Foliage_Leaf_WildBlue':(.12,.23,.48),
 'MV_Foliage_Leaf_PollenGold':(.59,.40,.026),
 'MV_PlantedSoil':(.12,.10,.065),
}
indices={k:mesh.material(k,c) for k,c in palette.items()}
manifest['material_palette'].update({k:list(v) for k,v in palette.items()})
leaf_indices=[indices[k] for k in list(palette)[:3]];stem_index=indices['MV_Foliage_Leaf_UnderstoryStem']

def ground(x,y):
    hit=bvh.ray_cast(Vector((x,y,160)),Vector((0,0,-1)),260)[0]
    assert hit is not None
    return hit.z

def leaf(base,direction,length,width,material):
    base=Vector(base);u=Vector(direction).normalized()
    helper=Vector((0,0,1)) if abs(u.z)<.95 else Vector((0,1,0))
    side=u.cross(helper).normalized();normal=side.cross(u).normalized()
    rows=[]
    for i in range(4):
        t=i/3;spine=base+u*(length*t)+normal*(.07*length*math.sin(t*math.pi))
        breadth=width*math.sin(t*math.pi)**.75
        rows.append([spine-side*breadth-normal*breadth*.12,spine+normal*.007,spine+side*breadth-normal*breadth*.12])
    # Triangular tips, rather than collapsed quads with zero-area FBX tangents.
    for i in range(3):
        a,b=rows[i],rows[i+1]
        if i==0:
            mesh.face([a[1],b[0],b[1]],material);mesh.face([a[1],b[1],b[2]],material)
        elif i==2:
            mesh.face([a[0],b[1],a[1]],material);mesh.face([a[1],b[1],a[2]],material)
        else:
            mesh.face([a[0],b[0],b[1],a[1]],material);mesh.face([a[1],b[1],b[2],a[2]],material)

def shrub(x,y,z,height,radius):
    root=Vector((x,y,z-.045))
    for branch in range(7 if layered else 9):
        angle=branch*2.399+rng.uniform(-.20,.20)
        extent=radius*rng.uniform(.5,1);tip=root+Vector((math.cos(angle)*extent,math.sin(angle)*extent,height*rng.uniform(.55,1)))
        middle=root.lerp(tip,.5)+Vector((0,0,.07))
        mesh.tube([root,middle,tip],[.014,.008,.0025],stem_index,5)
        for j in range(4 if layered else 5):
            t=.28+j*.18 if layered else .22+j*.16
            p=root.lerp(tip,t)
            length=rng.uniform(.14,.21) if layered else rng.uniform(.065,.12)*(1-.35*t)
            for side in [-1,1]:
                direction=(math.cos(angle+side*.92),math.sin(angle+side*.92),rng.uniform(.15,.7))
                leaf(p,direction,length,length*(.43 if layered else .36),rng.choice(leaf_indices))
            # Branch tips are fleshed out with additional leaflets, not empty stems.
        for k in range(4):
            a=angle+k*math.pi/2
            leaf(tip,(math.cos(a),math.sin(a),.35),.16 if layered else .072,.066 if layered else .026,rng.choice(leaf_indices))

def fern(x,y,z,scale):
    for frond in range(5):
        angle=frond*math.tau/5;u=Vector((math.cos(angle),math.sin(angle),0));cross=Vector((-u.y,u.x,0))
        root=Vector((x,y,z));points=[]
        for j in range(8):
            t=j/7;points.append(root+u*(t*scale*.50)+Vector((0,0,scale*.42*math.sin(t*math.pi*.78))))
        mesh.tube(points,[.006*(1-j/9) for j in range(8)],stem_index,4)
        for j in range(1,7):
            length=.10*scale*math.sin(j*math.pi/8)
            for side in [-1,1]:leaf(points[j],cross*side+u*.20+Vector((0,0,.15)),length,length*.28,leaf_indices[1+j%2])

def grass(x,y,z,scale):
    for blade in range(7 if layered else 10):
        a=rng.random()*math.tau;u=Vector((math.cos(a),math.sin(a),0));side=Vector((-u.y,u.x,0))
        root=Vector((x,y,z));h=scale*rng.uniform(.12,.24);lean=u*h*rng.uniform(.15,.60)
        for j in range(4):
            t=j/4;s=(j+1)/4
            p=root+Vector((0,0,h*t))+lean*t*t;q=root+Vector((0,0,h*s))+lean*s*s
            w=.011*(1-t);w2=.011*(1-s)
            if j==3:mesh.face([p-side*w,q,p+side*w],leaf_indices[blade%3])
            else:mesh.face([p-side*w,q-side*w2,q+side*w2,p+side*w],leaf_indices[blade%3])

def flower(x,y,z,blue=False):
    height=rng.uniform(.14,.29);root=Vector((x,y,z));head=root+Vector((0,0,height))
    mesh.tube([root,head],[.003,.002],stem_index,4)
    leaf(root+Vector((0,0,height*.45)),(1,.3,.6),.055,.019,leaf_indices[1])
    petal_index=indices['MV_Foliage_Leaf_WildBlue' if blue else 'MV_Foliage_Leaf_DaisyCream']
    for i in range(7 if not blue else 5):
        a=i*math.tau/(7 if not blue else 5)
        leaf(head,(math.cos(a),math.sin(a),.12),.036,.012,petal_index)
    mesh.tube([head,head+Vector((0,0,.012))],[.013,.011],indices['MV_Foliage_Leaf_PollenGold'],7)

# Beds have distinct roles: two low foreground edges, plaza-side bank,
# shaded stair beds, and shrubs along retaining-wall feet. Not a ring of equal tufts.
beds=[('foreground_west',12,-.1,3.6,.85,.30,27),('foreground_east',28.0,.8,3.0,.85,.28,23),
      ('plaza_west',7.3,9,1.0,4.4,.50,26),('plaza_east',33,18,1.2,3.1,.40,20),
      ('stair_west',-6.5,30.7,1.05,6.2,.64,28),('stair_east',4.7,30.4,1.05,5.8,.62,28),
      ('tree_wall_east',10.8,43.0,1.1,4.6,.72,23)]
if layered:
    beds=[('foreground_west',11.8,-.1,3.7,1.15,.48,35),
          ('foreground_east',29,.4,3.1,1.1,.44,29),
          ('plaza_west',7.3,9,1.25,4.4,.65,30),
          ('plaza_east',33.4,18,1.15,3.1,.55,22),
          ('stair_west',-6.5,30.7,1.1,6.2,.76,36),
          ('stair_east',4.7,30.4,1.1,5.8,.70,34),
          ('tree_wall_east',10.8,43,1.3,4.6,.85,29),
          ('tree_wall_west',-12.9,42.7,.95,3.2,.62,21)]
report=[]
for label,cx,cy,rx,ry,height,count in beds:
    # Thin original mulch beds follow the sampled ground. Nothing covers road/paving.
    center=Vector((cx,cy,ground(cx,cy)+.008));ring=[]
    for i in range(32):
        a=i*math.tau/32;r=1+.10*math.sin(a*3)+.06*math.sin(a*7+.3)
        x,y=cx+rx*r*math.cos(a),cy+ry*r*math.sin(a)
        ring.append(Vector((x,y,ground(x,y)+.008)))
    if not layered:
        for a,b in zip(ring,ring[1:]+ring[:1]):mesh.face([center,a,b],indices['MV_PlantedSoil'])
    for i in range(count):
        # Even coverage with deterministic jitter inside a deliberately authored bed.
        a=i*2.399;r=math.sqrt((i+.5)/count)*.90
        x,y=cx+rx*r*math.cos(a),cy+ry*r*math.sin(a);z=ground(x,y)
        shrub(x,y,z,height*rng.uniform(.65,1.05),rng.uniform(.29,.48) if layered else rng.uniform(.18,.32))
        if i%2==0:fern(x+.12,y-.12,ground(x+.12,y-.12),.8)
    for i in range(count*(5 if layered else 9)):
        a=rng.random()*math.tau;r=math.sqrt(rng.random())
        x,y=cx+rx*r*math.cos(a),cy+ry*r*math.sin(a);z=ground(x,y)
        if i%3:grass(x,y,z,rng.uniform(.6,1))
        else:flower(x,y,z,i%2==0)
    report.append({'bed':label,'center':[cx,cy],'radius':[rx,ry],'height_max_m':height*1.05})

if layered:
    # Ivy hangs against the existing radius-12 masonry, with the stair opening clear.
    for angle in [-2.45,-2.18,-.95,-.62,-.32,.15]:
        length=rng.uniform(1.5,2.7)
        points=[]
        for j in range(12):
            t=j/11;a=angle+.025*math.sin(t*9+angle)
            points.append(Vector((-1+12.12*math.cos(a),47+12.12*math.sin(a),13.45-length*t)))
        mesh.tube(points,[.008]*len(points),stem_index,4)
        for j,p in enumerate(points):
            tangent=Vector((-math.sin(angle),math.cos(angle),.1))
            for side in [-1,1]:
                leaf(p,tangent*side+Vector((0,0,-.25)),.15,.077,leaf_indices[(j+1)%3])
    manifest['noncollision_assets']=list(set(manifest.get('noncollision_assets',[])+[name]))

obj=mesh.build(name)
manifest['mesh_source_versions']={asset:manifest.get('mesh_source_versions',{}).get(asset,source)
                                  for asset in manifest['assets'] if asset!=name}
for asset in manifest['assets']:
    if asset!=name:shutil.copy2(BASE/(asset+'.fbx'),OUT/(asset+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
export_mesh(obj,OUT/(name+'.fbx'))
manifest['geometry_source_version']=source;manifest['stage']='COMPOSED_UNDERSTORY_REQUIRES_FIXED_UE_REVIEW'
manifest['geometry_changes']=['Replaced old oversized diamond-leaf tufts with small curved leaves, ferns, grass and daisies',
    'Seven composed terrain-following planted beds retain road and central staircase openings',
    'Existing buildings, terrain, tree, forest, six cameras and daylight retained']
if layered:
    manifest['geometry_changes']=['Broader overlapping shrub crowns with fewer fine branches, taller stair-side planting and irregular bed coverage',
        'Removed conspicuous flat mulch fan geometry; grass and flowers ground the bed margins directly',
        'Added restrained masonry-hugging ivy outside the staircase opening; all terrain, architecture, cameras and lighting retained']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'planting_report.json').write_text(json.dumps({'beds':report,'polygon_count':len(obj.data.polygons),
    'scope':'Authored bed layout with within-bed distribution; requires actual screenshot review',
    'profile':'layered' if layered else 'original',
    'status':'NOT_VISUALLY_ACCEPTED'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('SEKAI_Valley_Terrain_'+version+'.blend')))
print('COMPOSED_UNDERSTORY_SAVED',len(obj.data.polygons))
