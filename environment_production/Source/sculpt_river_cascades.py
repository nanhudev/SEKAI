"""Replace white waterfall slabs with dense curved water and broken foam trails."""
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

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
version=sys.argv[-1] if '--' in sys.argv else 'v030'
BASE=ROOT/'v029';OUT=ROOT/version;OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v029.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def river_x(y):return -29+13*math.sin(y/38)+3.3*math.sin(y/15)
def water_z(y):return -.4+.019*(y+100)+2.7*smooth(-29.45,-28.95,y)+2.4*smooth(43.4,43.9,y)
def flow_z(y,u):
    offset=.38*math.sin(u*9)+.16*math.sin(u*23)
    return -.4+.019*(y+100)+2.7*smooth(-29.45+offset,-28.95+offset,y)+2.4*smooth(43.4+offset,43.9+offset,y)
def river_half(y):return 3.7+.65*math.sin(y/11)+2.8*math.exp(-((y+36)/8)**2)+3.2*math.exp(-((y-37)/9)**2)
name='SM_VIL_Valley_Stream_v009';old=bpy.data.objects[name];collection=old.users_collection[0]
bpy.data.objects.remove(old,do_unlink=True)
materials=[]
for key in ['MV_Valley_Water_Prototype','MV_Valley_FallingWater','MV_Valley_Foam_Detail']:
    materials.append(bpy.data.materials.get(key) or bpy.data.materials.new(key))
vertices=[];faces=[];indices=[];uvs=[]
ys=sorted(set([round(-130+i*.5,3) for i in range(561)]+
    [round(-30.2+i*.04,3) for i in range(61)]+[round(42.7+i*.04,3) for i in range(51)]))
columns=65
for y in ys:
    for i in range(columns):
        u=i/(columns-1);x=river_x(y)+(u*2-1)*river_half(y)
        z=flow_z(y,u)+.025*math.sin(u*23+y*.71)+.012*math.sin(u*41-y*.47)
        vertices.append((x,y,z));uvs.append((u*1.7,y*.06+flow_z(y,u)*.12))
for j in range(len(ys)-1):
    for i in range(columns-1):
        u=(i+.5)/(columns-1)
        falling=abs(flow_z(ys[j+1],u)-flow_z(ys[j],u))/(ys[j+1]-ys[j])>.7
        # Solid rock noses divide the ledge into unequal spillways.
        if falling and any(abs(u-center)<width for center,width in [(.22,.028),(.57,.035),(.83,.02)]):continue
        k=j*columns+i;faces.append((k,k+1,k+columns+1,k+columns));indices.append(1 if falling else 0)

# Foam follows the two impact pools and narrows downstream, never a whole white sheet.
rng=random.Random(26101228)
for lip in [-29.45,43.4]:
    for trail in range(42):
        lateral=rng.uniform(-.85,.85);start=lip-rng.uniform(.2,3.3)
        length=rng.uniform(.7,5.0);width=rng.uniform(.06,.26)
        offset=len(vertices)
        for j in range(9):
            t=j/8;y=start-length*t
            x=river_x(y)+lateral*river_half(y)+.18*math.sin(t*7+trail)
            taper=math.sin(math.pi*(.08+t*.84))
            for side in [-1,1]:
                vertices.append((x+side*width*taper,y,water_z(y)+.065))
                uvs.append((side*.5+.5,t*2+trail*.37))
        for j in range(8):
            k=offset+j*2;faces.append((k,k+1,k+3,k+2));indices.append(2)
mesh=bpy.data.meshes.new('River_Cascades_AndFoam');mesh.from_pydata(vertices,[],faces);mesh.update()
stream=bpy.data.objects.new(name,mesh);collection.objects.link(stream)
for mat in materials:mesh.materials.append(mat)
uv=mesh.uv_layers.new(name='UV_Flow_Metric')
for p,index in zip(mesh.polygons,indices):
    p.material_index=index;p.use_smooth=index!=2
    for li in p.loop_indices:uv.data[li].uv=uvs[mesh.loops[li].vertex_index]
terrain=bpy.data.objects['SM_VIL_Valley_Terrain_v009']
for v in terrain.data.vertices:
    x,y,z=v.co
    if abs(x-river_x(y))<river_half(y)*.96:v.co.z=min(z,water_z(y)-.8)
terrain.data.update()
rock_vertices=[];rock_faces=[]
for lip,height in [(-29.2,2.7),(43.65,2.4)]:
    for center,width in [(.22,.028),(.57,.035),(.83,.02)]:
        x=river_x(lip)+(2*center-1)*river_half(lip)
        offset=.38*math.sin(center*9)+.16*math.sin(center*23)
        y=lip+offset;upper=flow_z(y+.7,center);lower=upper-height-.6
        radius=river_half(lip)*width*2.4
        start=len(rock_vertices)
        for level,z in enumerate([lower,upper-.9,upper+.15]):
            for corner in range(7):
                angle=corner*math.tau/7
                r=radius*(1+.17*math.sin(corner*3+center*15+level))
                rock_vertices.append((x+r*math.cos(angle),y+.48*math.sin(angle),z+.12*math.sin(corner*2+level)))
        for level in range(2):
            for corner in range(7):
                a=start+level*7+corner;b=start+level*7+(corner+1)%7
                rock_faces.append((a,b,b+7,a+7))
        rock_faces.append(tuple(start+14+i for i in range(7)))
rock_mesh=bpy.data.meshes.new('Cascade_Anchored_Bedrock');rock_mesh.from_pydata(rock_vertices,[],rock_faces);rock_mesh.update()
rocks=bpy.data.objects.new('SM_VIL_Cascade_Bedrock_v030',rock_mesh);collection.objects.link(rocks)
rock_mesh.materials.append(bpy.data.materials.get('MV_Valley_Cliff'))
manifest['assets'].append(rocks.name)
changed=[stream,terrain,rocks]
for asset in manifest['assets']:
    if asset not in [o.name for o in changed]:shutil.copy2(BASE/(asset+'.fbx'),OUT/(asset+'.fbx'))
for texture in manifest.get('surface_color_textures',{}).values():shutil.copy2(BASE/(texture+'.png'),OUT/(texture+'.png'))
for obj in changed:
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.fbx(filepath=str(OUT/(obj.name+'.fbx')),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
manifest['material_palette'].update({'MV_Valley_FallingWater':[.24,.48,.51],
    'MV_Valley_Foam_Detail':[.72,.82,.79]})
manifest['water_material_trial']=True
manifest['water_flow_texture']=True
manifest['stage']='RIVER_CASCADE_REVIEW_NOT_VISUALLY_ACCEPTED'
manifest['geometry_changes']=['Irregular staggered cascade lips and three anchored bedrock dividers per ledge',
    'Lowered river bed beneath new falls','Authored broken downstream impact foam ribbons',
    'River bank meshes, fixed cameras and daylight unchanged']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('SEKAI_Valley_Terrain_'+version+'.blend')))
print('SEKAI_RIVER_CASCADES_SAVED',OUT)
