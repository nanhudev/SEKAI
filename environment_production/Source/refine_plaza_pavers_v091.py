"""Replace only the lower plaza flags with smaller fitted closed stone cells."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy,bmesh,json,math,random,os,sys,shutil
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder,export_mesh
root=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));base=root/'v090'
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
version=args[0] if args else 'v091'
out=Path(str(_SEKAI_RUNTIME / 'Checkpoints'))/version;out.mkdir(exist_ok=False)
pass  # Checkpoints stay inside the portable project.
bpy.ops.wm.open_mainfile(filepath=str(base/'SEKAI_Valley_Terrain_v090.blend'))
m=json.loads((base/'terrain_manifest.json').read_text());name='SM_VIL_Plaza_PavingAndTreeTerrace';plaza=bpy.data.objects[name]
for asset in m['assets']:
    if asset==name:m['mesh_source_versions'].pop(asset,None)
    else:m.setdefault('mesh_source_versions',{}).setdefault(asset,'v090')
for p in base.iterdir():
    if p.suffix.lower() in ['.fbx','.png'] and p.stem!=name:os.link(p,out/p.name)
    elif p.name=='material_sources.json':shutil.copy2(p,out/p.name)
bm=bmesh.new();bm.from_mesh(plaza.data);remove=[]
for face in bm.faces:
    material=plaza.data.materials[face.material_index].name
    if material.startswith(('MV_Polish_Limestone','MV_Polish_Mortar')) and all(math.hypot(v.co.x-20,v.co.y-13)<14.2 and v.co.z<8.5 for v in face.verts):remove.append(face)
assert remove
bmesh.ops.delete(bm,geom=remove,context='FACES');bm.to_mesh(plaza.data);bm.free()
mesh=MeshBuilder();stones=[mesh.material('MV_Polish_Limestone_'+str(i)) for i in range(5)];mortar=mesh.material('MV_Polish_Mortar')
rng=random.Random(26101491);seeds=[Vector((20,13))]
for row in range(1,12):
    radius=row*.39;count=round(math.tau*radius/.51)
    for i in range(count):
        a=(i+.5*(row%2))*math.tau/count
        seeds.append(Vector((20+radius*math.cos(a),13+radius*math.sin(a))))
for row in range(-23,24):
    for col in range(-23,24):
        x=col*.58+(row%2)*.29+rng.uniform(-.07,.07);y=row*.56+rng.uniform(-.07,.07)
        if 4.65<math.hypot(x,y)<12.98:seeds.append(Vector((20+x,13+y)))
boundary=[Vector((20+13.05*(1+.008*math.sin(i*.51))*math.cos(i*math.tau/96),13+13.05*(1+.008*math.sin(i*.51))*math.sin(i*math.tau/96))) for i in range(96)]
def clip(poly,n,k):
    result=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        da=a.dot(n)-k;db=b.dot(n)-k
        if da<=0:result.append(a)
        if (da<0)!=(db<0):result.append(a+(b-a)*(da/(da-db)))
    return result
# A continuous recessed support volume keeps the joints and perimeter closed.
mesh.face([(p.x,p.y,8.202) for p in boundary],mortar)
mesh.face([(p.x,p.y,8.08) for p in reversed(boundary)],mortar)
for a,b in zip(boundary,boundary[1:]+boundary[:1]):mesh.face([(a.x,a.y,8.08),(b.x,b.y,8.08),(b.x,b.y,8.202),(a.x,a.y,8.202)],mortar)
for seed in seeds:
    poly=boundary[:]
    for other in sorted((p for p in seeds if p is not seed),key=lambda p:(p-seed).length_squared)[:32]:
        poly=clip(poly,other-seed,(other.length_squared-seed.length_squared)*.5)
        if len(poly)<3:break
    if len(poly)<3:continue
    centre=sum(poly,Vector((0,0)))/len(poly)
    outline=[centre+(p-centre)*(1-.006/max(.1,(p-centre).length)) for p in poly]
    top=8.230+rng.uniform(-.004,.005);material=rng.choices(stones,[3,5,4,3,1])[0]
    rings=[]
    for inset,z in [(0,8.085),(0,top-.009),(.008,top)]:
        rings.append([Vector((centre.x+(p.x-centre.x)*(1-inset/max(.1,(p-centre).length)),centre.y+(p.y-centre.y)*(1-inset/max(.1,(p-centre).length)),z)) for p in outline])
    mesh.face(list(reversed(rings[0])),material);mesh.face(rings[-1],material)
    for a,b in zip(rings,rings[1:]):
        for i in range(len(a)):
            j=(i+1)%len(a);mesh.face([a[i],a[j],b[j],b[i]],material)
new=mesh.build('Plaza_SmallFlags_v091')
new.data.uv_layers[0].name=plaza.data.uv_layers[0].name
bpy.ops.object.select_all(action='DESELECT');plaza.select_set(True);new.select_set(True);bpy.context.view_layer.objects.active=plaza;bpy.ops.object.join()
bm=bmesh.new();bm.from_mesh(plaza.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bad=[f for f in bm.faces if f.calc_area()<1e-9]
if bad:bmesh.ops.delete(bm,geom=bad,context='FACES')
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(plaza.data);bm.free();plaza.data.update()
export_mesh(plaza,out/(name+'.fbx'))
m['version']=version;m['geometry_changes']=['Smaller fitted plaza stone flags, narrow joints and subtle heights on closed backing; matching UV0 layer restores stone detail','Existing retaining walls, stairs, planters, tree, bridge, houses, cameras and lighting preserved']
(out/'terrain_manifest.json').write_text(json.dumps(m,indent=2))
(out/'paving_rebuild_report.json').write_text(json.dumps({'removed_old_faces':len(remove),'new_stone_seeds':len(seeds),'removed_degenerate_triangles':len(bad),'top_height_range_m':[8.226,8.235],'scope':'Source geometry; requires native review'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(out/('SEKAI_Valley_Terrain_'+version+'.blend')))
