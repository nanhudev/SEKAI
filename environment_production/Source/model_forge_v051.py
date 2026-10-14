"""Original open blacksmith workshop, shaped against the existing architecture sheet."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import shutil
import sys
from pathlib import Path
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder, export_mesh

ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));BASE,OUT=ROOT/'v050',ROOT/'v051'
OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v050.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text());bpy.context.view_layer.update()
terrain=bpy.data.objects['SM_VIL_Valley_Terrain_v009']
bvh=BVHTree.FromObject(terrain,bpy.context.evaluated_depsgraph_get())
mesh=MeshBuilder()
palette={
 'MV_Forge_Timber_Weathered':(.20,.105,.047),'MV_Forge_Timber_Edge':(.31,.18,.078),
 'MV_Forge_Plaster_Lime':(.57,.52,.38),'MV_Forge_Stone_Dark':(.24,.27,.26),
 'MV_Forge_Stone_Warm':(.36,.36,.29),'MV_Forge_Stone_Light':(.44,.43,.35),
 'MV_Forge_Slate_0':(.10,.16,.20),'MV_Forge_Slate_1':(.16,.21,.23),
 'MV_Forge_Slate_2':(.21,.25,.25),'MV_Forge_Iron':(.045,.055,.06),
 'MV_Forge_Coal':(.024,.018,.014),'MV_Forge_Ember':(.72,.095,.009),
 'MV_Forge_Window':(.38,.21,.064),
}
m={name:mesh.material(name,color) for name,color in palette.items()}
wood=m['MV_Forge_Timber_Weathered'];edge=m['MV_Forge_Timber_Edge'];plaster=m['MV_Forge_Plaster_Lime']
stones=[m['MV_Forge_Stone_'+s] for s in ['Dark','Warm','Light']]
slates=[m['MV_Forge_Slate_'+str(i)] for i in range(3)];iron=m['MV_Forge_Iron']
cx,cy,rotation=63,27,-1.12
rotation_matrix=Matrix.Rotation(rotation,4,'Z')
samples=[]
for x,y in [(-5,-5),(5,-5),(-5,5),(5,5),(0,0)]:
    p=rotation_matrix@Vector((x,y,0));hit=bvh.ray_cast(Vector((cx+p.x,cy+p.y,150)),Vector((0,0,-1)),250)[0]
    assert hit is not None;samples.append(hit.z)
base=max(samples)-.08
transform=Matrix.Translation(Vector((cx,cy,base)))@rotation_matrix

def block(center,size,mat=wood,bevel=.025):mesh.block(center,size,mat,bevel=bevel)
def beam(a,b,w=.20,mat=wood):mesh.beam(a,b,w,mat)
def masonry(cx,cy,z,w,h,axis='x',depth=.29):
    rows=math.ceil(h/.31);cols=math.ceil(w/.61)
    for r in range(rows):
        for col in range(cols+1):
            a=max(-w/2,-w/2+(col-(r%2)*.5)*w/cols)
            b=min(w/2,-w/2+(col+1-(r%2)*.5)*w/cols)
            if b-a<.08:continue
            p=(cx+(a+b)*.5,cy,z+(r+.5)*h/rows) if axis=='x' else (cx,cy+(a+b)*.5,z+(r+.5)*h/rows)
            size=(b-a-.017,depth,h/rows-.018) if axis=='x' else (depth,b-a-.017,h/rows-.018)
            block(p,size,stones[(r*3+col)%3],.03)

def roof(cx,cy,z,w,d,rise):
    # Thick individual slates, staggered courses and a shallow bowed eave.
    for side in [-1,1]:
        rows=math.ceil(math.hypot(w/2,rise)/.36);cols=math.ceil(d/.40)
        for row in range(rows):
            t0=max(0,row/rows-.021);t1=min(1,(row+1)/rows+.012)
            x0=cx+side*w*.5*t0;x1=cx+side*w*.5*t1
            z0=z+rise*(1-t0)-.14*math.sin(math.pi*t0)
            z1=z+rise*(1-t1)-.14*math.sin(math.pi*t1)
            for col in range(cols+1):
                y0=max(cy-d/2,cy-d/2+(col-(row%2)*.5)*d/cols)
                y1=min(cy+d/2,cy-d/2+(col+1-(row%2)*.5)*d/cols-.016)
                if y1-y0<.02:continue
                dz=.015*math.sin(row*1.6+col*.7)
                points=[Vector((x0,y0,z0+dz)),Vector((x1,y0,z1+dz)),
                        Vector((x1,y1,z1+dz)),Vector((x0,y1,z0+dz))]
                if side<0:points.reverse()
                bottom=[p-Vector((0,0,.048)) for p in points];mat=slates[(row*5+col*2)%3]
                mesh.face(points,mat);mesh.face(list(reversed(bottom)),mat)
                for i in range(4):j=(i+1)%4;mesh.face([points[i],bottom[i],bottom[j],points[j]],mat)
        beam((cx+side*w*.5,cy-d*.5-.1,z),(cx+side*w*.5,cy+d*.5+.1,z),.24,edge)
        for end in [-1,1]:beam((cx+side*w*.5,cy+end*d*.5,z),(cx,cy+end*d*.5,z+rise),.22,edge)
    beam((cx,cy-d*.5-.25,z+rise+.15),(cx,cy+d*.5+.25,z+rise+.15),.24,edge)

def wall_gable(y):
    # Solid plaster prism. The front opens onto the forge, rather than replicating a tavern facade.
    points=[(-5,y-.13,4.35),(5,y-.13,4.35),(0,y-.13,7.02),
            (-5,y+.13,4.35),(5,y+.13,4.35),(0,y+.13,7.02)]
    for face in [(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)]:mesh.face([points[i] for i in face],plaster)
    for side in [-1,1]:beam((side*5.1,y-.19,4.35),(0,y-.19,7.05),.23,edge)
    beam((0,y-.19,4.35),(0,y-.19,7.05),.20)
    beam((-5.1,y-.19,4.35),(5.1,y-.19,4.35),.24)

# Raised stone floor and dressed foundation courses resolve uneven terrain contact.
block((0,0,.22),(10.6,10.5,.58),stones[0],.06)
block((0,-5.25,.33),(10.6,1.3,.22),stones[1],.04)
masonry(0,-5.15,-.02,10.6,.44)
masonry(-5.14,0,-.02,10.3,.54,'y');masonry(5.14,0,-.02,10.3,.54,'y')
for i in range(2):block((0,-5.85-i*.43,.16-i*.12),(7,.46,.22),stones[i%3])
for y in [-3,-.6,1.8,4.1]:
    masonry(5.0,y,.55,2.38,1.12,'y');block((5,y,2.9),(.26,2.40,2.52),plaster)
    masonry(-5.0,y,.55,2.38,1.12,'y');block((-5,y,2.9),(.26,2.40,2.52),plaster)
masonry(0,4.9,.55,10.1,1.15);block((0,4.9,2.99),(10.1,.26,2.52),plaster)
# West tool store, with a separate doorway; workshop on the east stays structurally open.
block((-3.50,-4.9,2.95),(3,.26,2.5),plaster);masonry(-3.5,-4.9,.55,3,1.15)
for x in [-5.05,-2.05,1.25,5.05]:
    block((x,-4.9,.71),(.42,.44,.38),stones[1]);beam((x,-4.9,.8),(x,-4.9,4.35),.25)
for x in [-5.13,5.13]:
    for y in [-4.9,-1.8,1.65,4.9]:
        beam((x,y,.53),(x,y,4.4),.23)
        beam((x,y,3.0),(x,y+.9,4.3),.15)
    for z in [1.67,4.30]:beam((x,-5.1,z),(x,5.1,z),.23)
beam((-5.1,-5.05,4.30),(5.1,-5.05,4.30),.29)
for x in [-4.7,-1.8,1.5,4.7]:
    beam((x,-5.05,3.30),(x+.5 if x<0 else x-.5,-5.05,4.32),.17)
wall_gable(-4.88);wall_gable(4.88);roof(0,0,4.4,11.5,11.35,2.8)

# Front lean-to roof preserves the main gable while giving the workshop an open silhouette.
for x in [-5.4,-1.8,1.8,5.4]:
    block((x,-7.1,.48),(.50,.52,.33),stones[2]);beam((x,-7.1,.65),(x,-7.1,3.16),.20)
    beam((x,-7.1,2.50),(x,-6.4,3.22),.15)
beam((-5.65,-7.16,3.12),(5.65,-7.16,3.12),.24,edge)
for row in range(8):
    y0=-4.9-row*.32;y1=y0-.34;z0=3.92-row*.10;z1=z0-.105
    for col in range(30):
        x0=-5.7+col*.38;x1=x0+.363;mat=slates[(row+col)%3]
        top=[Vector((x0,y1,z1)),Vector((x1,y1,z1)),Vector((x1,y0,z0)),Vector((x0,y0,z0))]
        mesh.face(top,mat);mesh.face([p-Vector((0,0,.04)) for p in reversed(top)],mat)
        for i in range(4):j=(i+1)%4;mesh.face([top[i],top[i]-Vector((0,0,.04)),top[j]-Vector((0,0,.04)),top[j]],mat)

# Hearth: real recess, arch voussoirs, coals and tapering chimney. Not a orange rectangle on a wall.
hx,hy=2.45,1.85
block((hx,hy,.78),(2.7,2.6,.62),stones[0],.04)
for side in [-1,1]:
    masonry(hx+side*1.05,hy-.87,1.07,.65,1.36)
    block((hx+side*1.05,hy,1.70),(.64,1.75,1.45),stones[1])
block((hx,hy+.97,1.67),(2.7,.38,1.65),stones[0])
for i in range(9):
    angle=math.pi*(i+.5)/9
    x,z=hx+1.0*math.cos(angle),2.16+1.0*math.sin(angle)
    mesh.block((x,hy-.9,z),(.41,.44,.38),stones[i%3],angle=0,bevel=.04)
block((hx,hy,3.18),(2.85,2.5,.38),stones[2],.06)
for course in range(21):
    z=3.44+course*.29;width=1.32 if course>4 else 2.35-course*.20
    for face in [-1,1]:
        masonry(hx,hy+face*width*.5,z,width,.27,depth=.22)
        masonry(hx+face*width*.5,hy,z,width,.27,'y',.22)
block((hx,hy,9.48),(1.74,1.74,.20),stones[2],.045)
for x in [-.55,.55]:
    for y in [-.55,.55]:beam((hx+x,hy+y,9.58),(hx+x,hy+y,10.05),.09,iron)
block((hx,hy,10.08),(1.84,1.84,.12),iron,.015)
for i in range(21):
    x=hx+.65*math.sin(i*2.399);y=hy-.35+.55*math.cos(i*2.399)
    block((x,y,1.20+.04*(i%3)),(.27,.21,.14),m['MV_Forge_Ember'] if i%3 else m['MV_Forge_Coal'],.026)

# Anvil silhouette with horn, hardy hole suggestion, foot and heavy wooden stump.
mesh.tube([(2,-5.95,.52),(2,-5.95,1.11)],[.43,.37],wood,12)
block((2,-5.95,1.20),(.70,.46,.14),iron,.025)
block((2,-5.95,1.42),(.39,.31,.37),iron,.023)
block((2,-5.95,1.65),(.81,.39,.17),iron,.018)
mesh.tube([(2.35,-5.95,1.65),(2.88,-5.95,1.62)],[.145,.018],iron,9)
# Workbench plus hand tools are purposeful workshop equipment, not generic prop scatter.
for x in [-.60,.80]:
    for y in [-6.7,-6.05]:beam((x,y,.49),(x,y,1.36),.12)
for plank in range(4):block((.1,-6.65+plank*.19,1.42),(1.75,.18,.11),edge,.014)
beam((-.40,-6.40,1.52),(.28,-6.40,1.52),.07,edge)
block((.31,-6.40,1.53),(.19,.15,.14),iron,.016)
for i in range(8):
    beam((-4.2+i*.19,4.67,1.80),(-4.2+i*.19,4.67,3.25),.035,iron)
    block((-4.2+i*.19,4.62,3.2),(.16,.11,.12),iron,.01)

# Tool-store door has an actual inset and planks, with forged strap hinges.
block((-3.5,-5.065,2.1),(1.2,.13,2.28),wood,.02)
for plank in range(6):block((-4.00+plank*.20,-5.15,2.1),(.185,.09,2.18),edge,.01)
for z in [1.50,2.72]:block((-3.5,-5.23,z),(1.07,.045,.07),iron,.008)
for dx in [-.68,.68]:beam((-3.5+dx,-5.22,.86),(-3.5+dx,-5.22,3.29),.13)
beam((-4.23,-5.22,3.32),(-2.77,-5.22,3.32),.17)

obj=mesh.build('SM_VIL_Forge_OpenWorkshop_v051',transform)
manifest['mesh_source_versions']={name:manifest.get('mesh_source_versions',{}).get(name,'v050') for name in manifest['assets']}
for name in manifest['assets']:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):shutil.copy2(f,OUT/f.name)
manifest['assets'].append(obj.name);export_mesh(obj,OUT/(obj.name+'.fbx'))
manifest['material_palette'].update({k:list(v) for k,v in palette.items()})
manifest['noncollision_assets']=list(set(manifest.get('noncollision_assets',[])+['SM_VIL_Plaza_Planting_v044']))
for key in palette:
    family=next((s for s in ['Timber','Stone','Plaster','Slate'] if s in key),None)
    if family:manifest.setdefault('material_properties',{})[key]={'normal_map':
        '/Game/Environment/Village/Textures/OriginalSurfaces/T_VIL_'+family+'_Normal'}
manifest.setdefault('material_properties',{})['MV_Forge_Iron']={'metallic':.82,'roughness':.46}
manifest['material_properties']['MV_Forge_Ember']={'emissive':[80,4.5,.35],'roughness':.92}
manifest['geometry_source_version']='v050';manifest['stage']='ORIGINAL_FORGE_REQUIRES_FIXED_UE_REVIEW'
manifest['geometry_changes']=['Original asymmetrical open forge with attached tool store and front lean-to',
    'Tall dressed chimney, actual recessed hearth, individual slate courses, braces and grounded stone foundation',
    'Terrain, village roads, six cameras and daylight retained']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'forge_report.json').write_text(json.dumps({'center_m':[cx,cy,base],'rotation_radians':rotation,
    'ground_samples_m':samples,'chimney_height_m':10.14,'workshop_clear_height_m':3.7,
    'polygon_count':len(obj.data.polygons),'status':'NOT_VISUALLY_ACCEPTED'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v051.blend'))
print('ORIGINAL_FORGE_SAVED',len(obj.data.polygons))
