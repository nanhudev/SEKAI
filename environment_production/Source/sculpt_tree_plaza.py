"""Fuse the ancient tree and rebuild its plaza with bevelled structural stone."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import bmesh
import json
import math
import random
import shutil
import sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(str(_SEKAI_ROOT / 'environment_production'))
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
source,version=args[:2] if len(args)>=2 else ('v015','v016')
BASE=ROOT/'Terrain'/source;OUT=ROOT/'Terrain'/version
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(BASE/('SEKAI_Valley_Terrain_'+source+'.blend')))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
terrain=bpy.data.objects['SM_VIL_Valley_Terrain_v009']
def approach_distance(x,y):
    # Closest distance to the direct plaza/stair-foot approach.
    ax,ay=11.0,18.0;dx,dy=-12.0,6.0
    t=max(0,min(1,((x-ax)*dx+(y-ay)*dy)/(dx*dx+dy*dy)))
    return math.hypot(x-ax-t*dx,y-ay-t*dy)

if version in ['v021','v022']:
    for v in terrain.data.vertices:
        distance=approach_distance(v.co.x,v.co.y)
        if distance<4.2:
            weight=min(1,max(0,(4.2-distance)/1.1))
            v.co.z=v.co.z*(1-weight)+8.2*weight
    terrain.data.update()
if version=='v019':
    # Grade the actual heightfield around the built platform, not a new overlay.
    for v in terrain.data.vertices:
        x,y,z=v.co;r=math.hypot(x+1,y-47)
        if y<46 and 11.6<r<19:
            weight=min(1,max(0,(19-r)/3))*min(1,max(0,(r-11.6)/.65))
            v.co.z=z*(1-weight)+min(z,8.18)*weight
        if -4.9<x<2.9 and 24.5<y<35.8:
            step=max(0,min(25,math.floor((y-24.8)/.4)))
            v.co.z=min(v.co.z,8.48+step*.20-.24)
        distance=math.hypot(x-20,y-13)
        if distance<14.2:
            weight=min(1,max(0,(14.2-distance)/1.4))
            v.co.z=v.co.z*(1-weight)+8.2*weight
    terrain.data.update()
    route=bpy.data.objects['SM_VIL_Valley_CriticalRoute_v009']
    for v in route.data.vertices:
        radius=math.hypot(v.co.x-20,v.co.y-13)
        if radius<14.2:
            weight=min(1,max(0,(14.2-radius)/1.5))
            v.co.z=v.co.z*(1-weight)+8.05*weight
    route.data.update()
bvh=BVHTree.FromObject(terrain,bpy.context.evaluated_depsgraph_get())

def ground(x,y):
    hit=bvh.ray_cast(Vector((x,y,120)),Vector((0,0,-1)),200)[0]
    return hit.z if hit else 0

tree=bpy.data.objects['SM_VIL_Hero_AncientTree_Wood']
bpy.ops.object.select_all(action='DESELECT');tree.select_set(True);bpy.context.view_layer.objects.active=tree
if source=='v015':
    bm=bmesh.new();bm.from_mesh(tree.data)
    bmesh.ops.holes_fill(bm,edges=[e for e in bm.edges if e.is_boundary],sides=0)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(tree.data);bm.free()
    tree.data.remesh_voxel_size=.16
    bpy.ops.object.voxel_remesh()
    smooth=tree.modifiers.new('Organic_branch_junctions','SMOOTH');smooth.factor=.65;smooth.iterations=4
    bpy.ops.object.modifier_apply(modifier=smooth.name)

# Broad vertical bark flutes follow the central trunk rather than random bumps.
for v in tree.data.vertices:
    p=v.co;radial=Vector((p.x+1,p.y-47,0));radius=radial.length
    if radius<.05:continue
    angle=math.atan2(radial.y,radial.x)
    mask=max(0,1-(radius/5.5)**2)*max(0,1-(max(0,p.z-27)/11)**2)
    flute=(.10*math.sin(angle*17+p.z*.11)+.06*math.sin(angle*9-p.z*.19))*mask
    if source=='v015':v.co += radial.normalized()*flute
for p in tree.data.polygons:p.use_smooth=True
uv=tree.data.uv_layers.active or tree.data.uv_layers.new(name='UV_Bark_Metric')
for p in tree.data.polygons:
    for li in p.loop_indices:
        v=tree.data.vertices[tree.data.loops[li].vertex_index].co
        uv.data[li].uv=((math.atan2(v.y-47,v.x+1)/math.tau)*6,v.z*.28)
tree.data.update()

old=bpy.data.objects['SM_VIL_Plaza_PavingAndTreeTerrace']
materials=list(old.data.materials)
collection=old.users_collection[0]
bpy.data.objects.remove(old,do_unlink=True)
vertices=[];faces=[];indices=[]
rng=random.Random(261012)

def stone(center,size,angle=0,index=0,bevel=.035):
    cx,cy,cz=center;w,d,h=size;w*=.5;d*=.5
    cut=min(bevel,w*.3,d*.3,h*.25)
    outline=[(-w+cut,-d),(w-cut,-d),(w,-d+cut),(w,d-cut),
             (w-cut,d),(-w+cut,d),(-w,d-cut),(-w,-d+cut)]
    start=len(vertices)
    for inset,z in [(cut,cz-h*.5),(0,cz-h*.5+cut),(0,cz+h*.5-cut),(cut,cz+h*.5)]:
        for x,y in outline:
            x-=math.copysign(inset,x);y-=math.copysign(inset,y)
            vertices.append((cx+x*math.cos(angle)-y*math.sin(angle),cy+x*math.sin(angle)+y*math.cos(angle),z))
    faces.append(tuple(start+i for i in reversed(range(8))));indices.append(index)
    faces.append(tuple(start+24+i for i in range(8)));indices.append(index)
    for row in range(3):
        for i in range(8):
            faces.append((start+row*8+i,start+row*8+(i+1)%8,
                start+(row+1)*8+(i+1)%8,start+(row+1)*8+i));indices.append(index)

# Thin fitted pavers sit mostly below grade; their tops are not floating slabs.
for ring in range(1,18):
    radius=ring*.73;count=math.ceil(math.tau*radius/.88)
    for i in range(count):
        a=i*math.tau/count+(ring%2)*math.pi/count
        x=20+radius*math.cos(a);y=13+radius*math.sin(a)
        h=.08 if version in ['v021','v022'] else .10
        z=ground(x,y)-(.028 if version in ['v021','v022'] else .018)+rng.uniform(-.006,.006)
        stone((x,y,z),(.70,math.tau*radius/count-.028,h),a+rng.uniform(-.016,.016),rng.randrange(4),.024)
stone((20,13,ground(20,13)-.018),(1.1,1.1,.10),0,2,.028)
if version in ['v021','v022']:
    for row in range(15):
        y=16+row*.64
        for col in range(24):
            x=-4.8+col*.78+(row%2)*.39
            if approach_distance(x,y)>2.65 or math.hypot(x-20,y-13)<12.6:continue
            stone((x,y,ground(x,y)-.026+rng.uniform(-.004,.004)),(.76,.62,.08),
                  0,(row+col)%4,.025)

# A wide, solid staircase connects plaza grade to the tree retaining platform.
for i in range(26):
    y=25+i*.40;top=8.48+i*.20;bottom=min(top-.20,ground(-1,y)-.06)
    if version in ['v021','v022']:bottom=min(8.02,ground(-1,y)-.2)
    stone((-1,y,(top+bottom)*.5),(7.0,.43,top-bottom),0,i%4,.026)
    for side in [-1,1]:
        stone((-1+side*3.62,y,top+.08),(.32,.45,.28),0,(i+1)%4,.035)
        if version in ['v021','v022']:
            foundation=min(8.0,math.floor((ground(-1+side*3.62,y)-.2)/.4)*.4)
            for course in range(math.ceil((top-foundation)/.40)):
                lower=foundation+course*.40;upper=min(top,lower+.4)
                stone((-1+side*3.62,y,(lower+upper)*.5),(.36,.405,upper-lower-.012),
                      0,(course+i)%4,.025)

tx,ty=-1,47;radius=12.0
for i in range(78):
    a=i*math.tau/78;x=tx+radius*math.cos(a);y=ty+radius*math.sin(a)
    if y<35.9 and abs(x-tx)<3.8:continue
    base=ground(x,y)-.18;top=13.48
    if version in ['v021','v022']:
        base=min(7.98,math.floor((ground(x,y)-.25)/.4)*.4)
        # Continuous dark core behind dressed courses, also below terrain grade.
        stone((x,y,(base+13.4)*.5),(math.tau*radius/78+.015,.62,13.4-base),
              a+math.pi/2,2,0)
    courses=max(0,math.ceil((top-base)/.40))
    for course in range(courses):
        lower=base+course*.40;upper=min(top,lower+.40)
        if upper-lower<.04:continue
        stagger=(course%2)*(math.pi/78 if version in ['v021','v022'] else .018)
        angle=a+stagger
        px=tx+radius*math.cos(angle);py=ty+radius*math.sin(angle)
        if version in ['v021','v022'] and py<35.95 and abs(px-tx)<3.85:continue
        stone((px,py,(lower+upper)*.5),(math.tau*radius/78-.025,.75,upper-lower-.018),
            angle+math.pi/2,(i+course)%4,.045)
    stone((x,y,13.55),(math.tau*radius/78-.015,.95,.18),a+math.pi/2,(i+2)%4,.035)

data=bpy.data.meshes.new('Tree_Plaza_StructuralStone');data.from_pydata(vertices,[],faces);data.update()
plaza=bpy.data.objects.new('SM_VIL_Plaza_PavingAndTreeTerrace',data);collection.objects.link(plaza)
for m in materials:data.materials.append(m)
for i,p in enumerate(data.polygons):p.material_index=indices[i]
uv=data.uv_layers.new(name='UV_Stone_Metric')
for p in data.polygons:
    a,b,c=[data.vertices[i].co for i in p.vertices[:3]]
    normal=(b-a).cross(c-a).normalized()
    axis=max(range(3),key=lambda i:abs(normal[i]))
    for li in p.loop_indices:
        v=data.vertices[data.loops[li].vertex_index].co
        x,y=(v.y,v.z) if axis==0 else ((v.x,v.z) if axis==1 else (v.x,v.y))
        uv.data[li].uv=(x*.7,y*.7)

changed=[tree,plaza]+([terrain,route] if version=='v019' else ([terrain] if version in ['v021','v022'] else []))
for name in manifest['assets']:
    if name not in [obj.name for obj in changed]:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for texture in manifest.get('surface_color_textures',{}).values():
    shutil.copy2(BASE/(texture+'.png'),OUT/(texture+'.png'))
for obj in changed:
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.fbx(filepath=str(OUT/(obj.name+'.fbx')),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
manifest['stage']='TREE_PLAZA_SCULPT_NOT_VISUALLY_ACCEPTED'
manifest['ground_acceptance_reference']='SEKAI_REFERENCES/MASTER/acceptance_plaza_ground_20261012.png'
manifest['geometry_changes']=['Fused root/trunk/branch junctions with voxel sculpt',
    'Added broad vertical trunk flutes','Rebuilt thin bevelled plaza pavers',
    'Widened tree stairs to seven metres and modeled solid supporting risers',
    'Bevelled staggered retaining-wall blocks and coping; retained fixed cameras']
if version=='v019':
    manifest['geometry_source_version']=source
    manifest['geometry_changes']=['Lowered tree approach to expose structural retaining wall',
        'Cut stair bed beneath solid step risers','Graded radial plaza to a level 8.2-m datum',
        'Recessed overlapping road below radial paving; cameras and lighting unchanged']
if version in ['v021','v022']:
    manifest['geometry_source_version']=source
    manifest['geometry_changes']=['Added continuous retaining-wall core and globally aligned masonry courses',
        'Rebuilt stairs with full solid foundation and coursed cheek walls',
        'Recessed plaza pavers and added graded continuous paving to stair foot',
        'Existing tree, cameras, review lighting and river unchanged']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('SEKAI_Valley_Terrain_'+version+'.blend')))
print('SEKAI_TREE_PLAZA_SCULPT_SAVED',OUT)
