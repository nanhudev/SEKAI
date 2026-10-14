"""Author a twisted rooted ancient tree with spreading branches and layered foliage."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import random
import shutil
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
BASE=ROOT/'v031';OUT=ROOT/'v032';OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v031.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
wood_name='SM_VIL_Hero_AncientTree_Wood';leaf_name='SM_VIL_Hero_AncientTree_Foliage'
collection=bpy.data.objects[wood_name].users_collection[0]
wood_materials=list(bpy.data.objects[wood_name].data.materials)
leaf_materials=list(bpy.data.objects[leaf_name].data.materials)
for name in [wood_name,leaf_name]:bpy.data.objects.remove(bpy.data.objects[name],do_unlink=True)
origin=Vector((-1,47,13.4));rng=random.Random(26101232)
vertices=[];faces=[]

def tube(points,radii,sides=20):
    points=[Vector(p)+origin for p in points]
    samples=[];sizes=[]
    for i in range(len(points)-1):
        a=points[max(0,i-1)];b=points[i];c=points[i+1];d=points[min(len(points)-1,i+2)]
        steps=max(4,math.ceil((c-b).length/.35))
        for j in range(steps):
            t=j/steps
            samples.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
            sizes.append(radii[i]*(1-t)+radii[i+1]*t)
    samples.append(points[-1]);sizes.append(radii[-1]);start=len(vertices)
    for j,p in enumerate(samples):
        tangent=(samples[min(len(samples)-1,j+1)]-samples[max(0,j-1)]).normalized()
        helper=Vector((0,1,0)) if abs(tangent.y)<.95 else Vector((1,0,0))
        right=tangent.cross(helper).normalized();up=right.cross(tangent).normalized()
        for i in range(sides):
            a=i*math.tau/sides
            r=sizes[j]*(1+.10*math.sin(a*7+p.z*.15)+.035*math.sin(a*13-p.z*.23))
            vertices.append(tuple(p+r*(right*math.cos(a)+up*math.sin(a))))
    faces.append(tuple(start+i for i in reversed(range(sides))))
    for j in range(len(samples)-1):
        for i in range(sides):
            k=start+j*sides+i;l=start+j*sides+(i+1)%sides
            faces.append((k,l,l+sides,k+sides))
    faces.append(tuple(start+(len(samples)-1)*sides+i for i in range(sides)))

tube([(0,0,-.3),(.7,.1,3),(-.6,.7,6),(.1,-.6,10),(1,.1,14),(1.6,.6,18),(.4,1,23)],
     [3.8,3.15,2.65,2.25,1.7,1.15,.22],36)
for i in range(10):
    a=i*math.tau/10+.16;dx,dy=math.cos(a),math.sin(a);reach=7.7+(i%3)*.9
    tube([(dx*1.1,dy*1.1,2.8),(dx*3.3,dy*3.3,1.05),
          (dx*5.7,dy*5.7,.36),(dx*reach,dy*reach,-.08)], [1.25,.85,.37,.055],20)

crowns=[]
for i in range(9):
    a=i*math.tau/9+.33;dx,dy=math.cos(a),math.sin(a)
    reach=11.8+(i%3)*1.1;lift=18.8+(i%4)*1.1;side=Vector((-dy,dx,0))
    controls=[(.35,0,5.8+(i%3)*1.9),(dx*3,dy*3,10.0+(i%3)),
              (dx*7+side.x,dy*7+side.y,lift-4.1),(dx*reach,dy*reach,lift)]
    tube(controls,[1.23,.88,.48,.12],24)
    end=Vector(controls[-1]);mid=Vector(controls[-2])
    for sign in [-1,1]:
        fork=end+side*(sign*3.1)+Vector((dx*1.1,dy*1.1,2.6))
        tube([tuple(mid),tuple(end+side*sign*.5),tuple(fork)],[.40,.22,.035],14)
        crowns.append((fork+origin,Vector((4.2,3.4,2.15))))
    crowns.append((end+origin+Vector((0,0,1.4)),Vector((4.8,4.2,2.1))))
crowns.extend([(origin+Vector((1,0,23.9)),Vector((6.7,5.3,2.8))),
               (origin+Vector((-4,1,22.4)),Vector((5.7,4.7,2.5)))])

mesh=bpy.data.meshes.new('AncientTree_CurvedSkeleton');mesh.from_pydata(vertices,[],faces);mesh.update()
wood=bpy.data.objects.new(wood_name,mesh);collection.objects.link(wood)
for mat in wood_materials:mesh.materials.append(mat)
bpy.ops.object.select_all(action='DESELECT');wood.select_set(True);bpy.context.view_layer.objects.active=wood
wood.data.remesh_voxel_size=.11;bpy.ops.object.voxel_remesh()
smooth=wood.modifiers.new('Fused_Branch_Collars','SMOOTH');smooth.factor=.42;smooth.iterations=3
bpy.ops.object.modifier_apply(modifier=smooth.name)
uv=wood.data.uv_layers.new(name='UV_Bark_Metric')
for p in wood.data.polygons:
    p.use_smooth=True
    for li in p.loop_indices:
        v=wood.data.vertices[wood.data.loops[li].vertex_index].co
        uv.data[li].uv=(math.atan2(v.y-47,v.x+1)/math.tau*7,v.z*.20)

lv=[];lf=[];indices=[]
for center,radii in crowns:
    for i in range(1350):
        a=rng.random()*math.tau;r=math.sqrt(rng.random());height=rng.uniform(-1,1)
        point=center+Vector((math.cos(a)*radii.x*r,math.sin(a)*radii.y*r,
                             height*radii.z*math.sqrt(max(.02,1-r*r))))
        heading=rng.random()*math.tau;tilt=rng.uniform(-.8,.8)
        right=Vector((math.cos(heading),math.sin(heading),tilt)).normalized()
        cross=right.cross(Vector((0,0,1))).normalized()
        length=rng.uniform(.22,.38);width=length*rng.uniform(.40,.58);start=len(lv)
        for x,y,z in [(-1,0,0),(-.45,-1,.018),(.38,-.85,.04),(1,0,0),(.40,.85,.035),(-.43,1,.016)]:
            lv.append(tuple(point+right*x*length+cross*y*width+Vector((0,0,z))))
        index=rng.choices(range(5),weights=[2,4,3,1,3])[0]
        for face in [(0,1,2),(0,2,3),(0,3,4),(0,4,5)]:lf.append(tuple(start+k for k in face));indices.append(index)
mesh=bpy.data.meshes.new('AncientTree_LayeredLeafSprays');mesh.from_pydata(lv,[],lf);mesh.update()
leaves=bpy.data.objects.new(leaf_name,mesh);collection.objects.link(leaves)
for mat in leaf_materials:mesh.materials.append(mat)
for p,index in zip(mesh.polygons,indices):p.material_index=index
for i,color in enumerate([(.16,.31,.055),(.24,.40,.07),(.34,.46,.09),(.11,.26,.065),(.27,.40,.06)]):
    manifest['material_palette']['MV_Foliage_Leaf_%02d'%i]=list(color)

terrain=bpy.data.objects['SM_VIL_Valley_Terrain_v009']
bvh=BVHTree.FromObject(terrain,bpy.context.evaluated_depsgraph_get())
road=bpy.data.objects['SM_VIL_Valley_CriticalRoute_v009']
for v in road.data.vertices:
    x,y,z=v.co
    if -49<y<-38:continue
    hit=bvh.ray_cast(Vector((x,y,120)),Vector((0,0,-1)),200)[0]
    if hit:v.co.z=hit.z+.012
road.data.update()
changed=[wood,leaves,road]
for name in manifest['assets']:
    if name not in [o.name for o in changed]:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
for obj in changed:
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.fbx(filepath=str(OUT/(obj.name+'.fbx')),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
manifest['stage']='ANCIENT_TREE_REBUILD_REVIEW_NOT_ACCEPTED'
manifest['geometry_changes']=['New curved twisted trunk, fused spreading branch collars and buttress roots',
    'Layered broad asymmetric crown attached to actual branch forks',
    'Reprojected non-bridge critical road to current terrain to remove suspended ribbon edges',
    'Camera positions, daylight, tavern and cascade geometry unchanged']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v032.blend'))
