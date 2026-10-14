"""Author reference-led terrace rails and planted edges on the preserved v043 scene."""
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

ROOT = Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
BASE, OUT = ROOT/'v043', ROOT/'v044'
OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v043.blend'))
manifest = json.loads((BASE/'terrain_manifest.json').read_text())
bpy.context.view_layer.update()
terrain = bpy.data.objects['SM_VIL_Valley_Terrain_v009']
bvh = BVHTree.FromObject(terrain, bpy.context.evaluated_depsgraph_get())
rng = random.Random(26101244)
palette = {
    'MV_Plaza_Timber_Rail': (.24,.115,.043),
    'MV_Plaza_Stone_Edge': (.32,.35,.30),
    'MV_Plaza_Stone_Light': (.42,.43,.35),
    'MV_Plaza_Lantern_Frame': (.07,.055,.035),
    'MV_Plaza_Lantern_Glass': (.72,.36,.07),
    'MV_Foliage_Leaf_GroundDark': (.065,.16,.024),
    'MV_Foliage_Leaf_GroundLight': (.19,.32,.045),
    'MV_Foliage_Leaf_FlowerWhite': (.75,.78,.62),
    'MV_Foliage_Leaf_FlowerBlue': (.12,.20,.48),
    'MV_Foliage_Leaf_FlowerGold': (.58,.38,.04),
}
manifest['material_palette'].update({k:list(v) for k,v in palette.items()})
materials=[]
for name, rgb in palette.items():
    material=bpy.data.materials.new(name);material.diffuse_color=(*rgb,1)
    materials.append(material)
names=list(palette)

class Geometry:
    def __init__(self): self.vertices=[];self.faces=[];self.indices=[]
    def face(self, points, material):
        start=len(self.vertices);self.vertices.extend(tuple(p) for p in points)
        self.faces.append(tuple(range(start,start+len(points))));self.indices.append(material)
    def tube(self, a, b, ra, rb, material, sides=8):
        a,b=Vector(a),Vector(b);axis=(b-a).normalized()
        helper=Vector((0,0,1)) if abs(axis.z)<.95 else Vector((0,1,0))
        u=axis.cross(helper).normalized();v=axis.cross(u).normalized()
        rings=[[p+r*(u*math.cos(i*math.tau/sides)+v*math.sin(i*math.tau/sides))
                for i in range(sides)] for p,r in [(a,ra),(b,rb)]]
        self.face(list(reversed(rings[0])),material);self.face(rings[1],material)
        for i in range(sides):
            j=(i+1)%sides;self.face([rings[0][i],rings[0][j],rings[1][j],rings[1][i]],material)
    def stone(self, x,y,z,w,d,h,angle=0,material=1):
        cut=min(.06,w*.17,d*.17);outline=[(-w/2+cut,-d/2),(w/2-cut,-d/2),
            (w/2,-d/2+cut),(w/2,d/2-cut),(w/2-cut,d/2),(-w/2+cut,d/2),
            (-w/2,d/2-cut),(-w/2,-d/2+cut)]
        rings=[]
        for inset,dz in [(.035,0),(0,.035),(0,h-.035),(.035,h)]:
            ring=[]
            for px,py in outline:
                px-=math.copysign(inset,px);py-=math.copysign(inset,py)
                ring.append(Vector((x+px*math.cos(angle)-py*math.sin(angle),
                                    y+px*math.sin(angle)+py*math.cos(angle),z+dz)))
            rings.append(ring)
        self.face(list(reversed(rings[0])),material);self.face(rings[-1],material)
        for lower,upper in zip(rings,rings[1:]):
            for i in range(8):
                j=(i+1)%8;self.face([lower[i],lower[j],upper[j],upper[i]],material)
    def export(self,name):
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(self.vertices,[],self.faces);mesh.update()
        obj=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(obj)
        for material in materials:mesh.materials.append(material)
        for p,index in zip(mesh.polygons,self.indices):p.material_index=index
        bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
        bpy.ops.export_scene.fbx(filepath=str(OUT/(name+'.fbx')),use_selection=True,object_types={'MESH'},
            axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
        manifest['assets'].append(name)
        return len(mesh.polygons)

def ground(x,y):
    hit=bvh.ray_cast(Vector((x,y,200)),Vector((0,0,-1)),400)[0]
    assert hit is not None, (x,y)
    return hit.z

structure,plants=Geometry(),Geometry()
def lamp(x,y,z):
    structure.stone(x,y,z,.64,.64,.35,material=2)
    structure.stone(x,y,z+.35,.46,.46,.58,material=1)
    structure.stone(x,y,z+.93,.62,.62,.15,material=2)
    low=z+1.08;high=low+.67
    structure.stone(x,y,low+.06,.36,.36,.49,material=4)
    for dx in [-.23,.23]:
        for dy in [-.23,.23]:structure.tube((x+dx,y+dy,low),(x+dx,y+dy,high),.026,.026,3)
    structure.stone(x,y,high,.62,.62,.10,material=3)
    structure.tube((x,y,high+.10),(x,y,high+.36),.44,.06,3,4)

# Set rails on the existing masonry cap. The stair mouth remains seven metres wide.
rail_points=[]
for i in range(29):
    angle=-math.pi/2+i*math.tau/28
    x,y=-1+11.72*math.cos(angle),47+11.72*math.sin(angle)
    if y<37 and abs(x+1)<4.1:rail_points.append(None);continue
    z=13.48
    structure.stone(x,y,z,.44,.44,.22,angle,2)
    structure.tube((x,y,z+.14),(x,y,z+1.25),.105,.08,0)
    structure.tube((x,y,z+1.25),(x,y,z+1.39),.14,.055,0)
    rail_points.append((x,y,z))
for a,b in zip(rail_points,rail_points[1:]):
    if a is None or b is None:continue
    for height in [.57,1.05]:
        structure.tube((a[0],a[1],a[2]+height),(b[0],b[1],b[2]+height),.065,.065,0)
for x in [-5.6,3.6]:lamp(x,35.8,13.48)
for x in [-5.5,3.5]:lamp(x,24.3,ground(x,24.3)-.05)

def leaf(center,heading,length,width,index):
    center=Vector(center);u=Vector((math.cos(heading),math.sin(heading),rng.uniform(.15,.5)))
    v=Vector((-math.sin(heading),math.cos(heading),0))
    points=[center-u*length,center-v*width,center+u*length,center+v*width]
    raised=center+Vector((0,0,.045))
    for i in range(4):plants.face([points[i],points[(i+1)%4],raised],index)

def planting(x,y,z,radius):
    # Branched shrubs and cupped leaves, rather than spherical canopy tokens.
    for stem in range(rng.randint(8,13)):
        angle=rng.random()*math.tau;reach=radius*rng.uniform(.2,.8);height=rng.uniform(.3,.85)
        tip=Vector((x+reach*math.cos(angle),y+reach*math.sin(angle),z+height))
        start=Vector((x,y,z-.06));plants.tube(start,tip,.022,.007,5,5)
        for j in range(7):
            t=.25+.1*j;point=start.lerp(tip,t)
            for side in [-1,1]:leaf(point,angle+side*1.0,rng.uniform(.10,.19),.065,5+(stem+j)%2)
    for stem in range(rng.randint(7,12)):
        a=rng.random()*math.tau;r=radius*math.sqrt(rng.random())
        px,py=x+r*math.cos(a),y+r*math.sin(a);height=rng.uniform(.23,.55)
        plants.tube((px,py,z),(px,py,z+height),.007,.005,5,5)
        leaf((px,py,z+height*.4),a,.11,.045,6)
        center=Vector((px,py,z+height));flower=rng.choices([7,8,9],[5,4,2])[0]
        for petal in range(5):
            pa=petal*math.tau/5;u=Vector((math.cos(pa),math.sin(pa),.3))
            v=Vector((-math.sin(pa),math.cos(pa),0))
            plants.face([center,center+u*.12-v*.044,center+u*.17,
                         center+u*.12+v*.044],flower)
        plants.tube(center,center+Vector((0,0,.02)),.028,.023,9,6)

# Several loose planted patches break the otherwise perfect plaza ring.
# Leave east road, southwest bridge access and the central stair approach open.
patches=[]
for i in range(46):
    a=i*math.tau/46
    if -.25<a<.58 or 2.15<a<2.8 or 3.35<a<4.02:continue
    radius=13.45+.65*math.sin(a*5)+rng.uniform(-.25,.25)
    x,y=20+radius*math.cos(a),13+radius*math.sin(a)
    if -5<x<5 and y>22:continue
    z=ground(x,y);patches.append((x,y,z))
    planting(x,y,z,.65)
    if i%3==0:
        structure.stone(x+math.cos(a)*.65,y+math.sin(a)*.65,z-.08,.8,.5,.24,a,1+i%2)
for side in [-1,1]:
    for i in range(16):
        x=-1+side*(4.55+rng.uniform(0,.65));y=24+i*.76
        planting(x,y,ground(x,y),.60)
for i in range(19):
    a=-math.pi+.1+i*math.pi/19
    x,y=-1+12.7*math.cos(a),47+12.7*math.sin(a)
    if abs(x+1)<4.8 and y<38:continue
    planting(x,y,ground(x,y),.75)

new_names=['SM_VIL_Plaza_RailsAndLanterns_v044','SM_VIL_Plaza_Planting_v044']
manifest['mesh_source_versions']={name:manifest.get('mesh_source_versions',{}).get(name,'v043')
                                  for name in manifest['assets']}
for name in manifest['assets']:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
counts=[structure.export(new_names[0]),plants.export(new_names[1])]
manifest['stage']='PLAZA_EDGE_DETAIL_REQUIRES_FIXED_UE_REVIEW'
manifest['geometry_source_version']='v043'
manifest['geometry_changes']=['Timber terrace railing follows existing stone cap and retains stair opening',
    'Four original framed lanterns at stair landings; no camera or light changes',
    'Ground-projected leaf/flower patches soften plaza outline and stair-side masonry',
    'All previous terrain, mountain, road, water, architecture and tree meshes retained']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'plaza_edge_report.json').write_text(json.dumps({'source':'v043','new_meshes':new_names,
    'polygon_counts':counts,'plaza_patch_count':len(patches),'status':'MODELED_NOT_VISUALLY_ACCEPTED'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v044.blend'))
print('PLAZA_EDGE_DETAIL_SAVED', counts)
