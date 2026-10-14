"""Layer the existing ancient crown around attached secondary branches."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy,json,math,os,random,sys,shutil
from pathlib import Path
from mathutils import Vector
from mathutils.kdtree import KDTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder,export_mesh

root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/'v085'
out=Path(str(_SEKAI_ROOT / 'environment_production/Terrain/v086'));out.mkdir(exist_ok=False)
pass  # Checkpoints stay inside the portable project.
bpy.ops.wm.open_mainfile(filepath=str(base/'SEKAI_Valley_Terrain_v085.blend'))
m=json.loads((base/'terrain_manifest.json').read_text())
wood=bpy.data.objects['SM_VIL_Hero_AncientTree_Wood']
leaves=bpy.data.objects['SM_VIL_Hero_AncientTree_Foliage']
changed={wood.name,leaves.name}
for name in m['assets']:
    if name in changed:m['mesh_source_versions'].pop(name,None)
    else:m.setdefault('mesh_source_versions',{}).setdefault(name,'v085')
for p in base.iterdir():
    if p.suffix.lower() in ['.fbx','.png'] and p.stem not in changed:os.link(p,out/p.name)
    elif p.name=='material_sources.json':shutil.copy2(p,out/p.name)

# Preserve the roots and branch structure; carve continuous flutes into the trunk.
for v in wood.data.vertices:
    p=v.co;radial=Vector((p.x+1,p.y-47,0));r=radial.length
    if .05<r<5.2 and 13.5<p.z<28:
        a=math.atan2(radial.y,radial.x)
        weight=min(1,(p.z-13.5)/1.5)*min(1,(28-p.z)/3)*max(0,1-r/5.2)
        v.co+=radial.normalized()*weight*(.22*math.sin(a*13+p.z*.19)+.09*math.sin(a*23-p.z*.31))
wood.data.update()
kd=KDTree(len(wood.data.vertices))
for i,v in enumerate(wood.data.vertices):kd.insert(v.co,i)
kd.balance()

lv=[tuple(v.co) for v in leaves.data.vertices]
lf=[tuple(p.vertices) for p in leaves.data.polygons]
li=[p.material_index for p in leaves.data.polygons]
# Thicken the original crown vertically without moving the tree's centre.
lv=[(-1+(x+1)*1.07,47+(y-47)*1.07,35.8+(z-35.8)*1.32) for x,y,z in lv]
rng=random.Random(26101486);builder=MeshBuilder();bark=builder.material('MV_Tree_Bark')
clusters=[];anchors=[]
for i in range(16):
    a=i*math.tau/16+.22;dx,dy=math.cos(a),math.sin(a)
    desired=Vector((-1+dx*10,47+dy*10,32+(i%3)))
    anchor,_,distance=kd.find(desired)
    end=Vector((-1+dx*(15+(i%3)*.8),47+dy*(15+(i%3)*.8),30.7+(i%5)*1.2))
    middle=anchor.lerp(end,.58)+Vector((0,0,.5))
    builder.tube([anchor-rng.uniform(.12,.22)*(end-anchor).normalized(),middle,end],[.28,.16,.035],bark,10)
    clusters.append((end,Vector((3.8,3.1,2.7))))
    clusters.append((end.lerp(middle,.5)+Vector((0,0,1.2)),Vector((3.2,2.8,2.9))))
    anchors.append({'anchor':list(anchor),'tip':list(end),'nearest_existing_surface_distance':distance})

for center,radii in clusters:
    for j in range(700):
        a=rng.random()*math.tau;r=math.sqrt(rng.random());h=rng.uniform(-1,1)
        p=center+Vector((math.cos(a)*r*radii.x,math.sin(a)*r*radii.y,h*radii.z*math.sqrt(max(.01,1-r*r))))
        heading=rng.random()*math.tau
        u=Vector((math.cos(heading),math.sin(heading),rng.uniform(-.85,.85))).normalized()
        v=u.cross(Vector((0,0,1))).normalized()
        length=rng.uniform(.19,.32);width=length*rng.uniform(.42,.58);start=len(lv)
        for x,y,z in [(-1,0,0),(-.45,-1,.018),(.38,-.85,.04),(1,0,0),(.4,.85,.035),(-.43,1,.016)]:
            lv.append(tuple(p+u*x*length+v*y*width+Vector((0,0,z))))
        index=rng.choices(range(5),weights=[2,5,3,2,3])[0]
        for face in [(0,1,2),(0,2,3),(0,3,4),(0,4,5)]:lf.append(tuple(start+k for k in face));li.append(index)
mesh=bpy.data.meshes.new('AncientTree_LayeredDroopingCrown_v086');mesh.from_pydata(lv,[],lf);mesh.update()
for mat in leaves.data.materials:mesh.materials.append(mat)
for p,index in zip(mesh.polygons,li):p.material_index=index
old=leaves.data;leaves.data=mesh
if old.users==0:bpy.data.meshes.remove(old)
twigs=builder.build('Tree_SecondaryBranches_v086')
bpy.ops.object.select_all(action='DESELECT');wood.select_set(True);twigs.select_set(True);bpy.context.view_layer.objects.active=wood
bpy.ops.object.join()
for p in wood.data.polygons:p.use_smooth=True
for i,color in enumerate([(.13,.24,.08),(.22,.38,.09),(.40,.51,.13),(.11,.23,.10),(.35,.45,.08)]):
    m['material_palette']['MV_Foliage_Leaf_%02d'%i]=list(color)
    leaves.data.materials[i].diffuse_color=(*color,1)
for obj in [wood,leaves]:export_mesh(obj,out/(obj.name+'.fbx'))
m['version']='v086';m['geometry_changes']=['Attached secondary branches and layered drooping ancient-tree crown','Longitudinal trunk flutes; original roots, tree centre, buildings, bridge, cameras and lights preserved']
(out/'terrain_manifest.json').write_text(json.dumps(m,indent=2))
(out/'tree_crown_report.json').write_text(json.dumps({'scope':'Source geometry only; requires native six-camera review','branches':anchors,'original_tree_centre_m':[-1,47,13.4]},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(out/'SEKAI_Valley_Terrain_v086.blend'))
