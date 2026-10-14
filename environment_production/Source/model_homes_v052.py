"""Two designed residential silhouettes, complete on all four sides."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import os
import shutil
import sys
from pathlib import Path
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from village_geometry import MeshBuilder, export_mesh

args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
source,version=args[:2] if len(args)>=2 else ('v051','v052')
ROOT=Path(str(_SEKAI_ROOT / 'environment_production/Terrain'));BASE,OUT=ROOT/source,ROOT/version
if args:
    target=Path(str(_SEKAI_RUNTIME / 'Checkpoints'))/version;target.mkdir(exist_ok=False)
    pass  # Checkpoints stay inside the portable project.
else:OUT.mkdir(exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(BASE/('SEKAI_Valley_Terrain_'+source+'.blend')))
manifest=json.loads((BASE/'terrain_manifest.json').read_text());bpy.context.view_layer.update()
bvh=BVHTree.FromObject(bpy.data.objects['SM_VIL_Valley_Terrain_v009'],bpy.context.evaluated_depsgraph_get())
palette={
 'MV_Home_Timber_Dark':(.16,.083,.037),'MV_Home_Timber_Light':(.29,.175,.085),
 'MV_Home_Plaster_Cream':(.62,.57,.44),'MV_Home_Plaster_Cool':(.48,.50,.42),
 'MV_Home_Stone_0':(.28,.32,.29),'MV_Home_Stone_1':(.39,.40,.34),'MV_Home_Stone_2':(.45,.44,.37),
 'MV_Home_Slate_0':(.09,.15,.20),'MV_Home_Slate_1':(.15,.21,.26),'MV_Home_Slate_2':(.22,.25,.26),
 'MV_Home_Glass':(.22,.29,.29),'MV_Home_Iron':(.065,.072,.076),
}
manifest['material_palette'].update({k:list(v) for k,v in palette.items()})
for key in palette:
    family=next((s for s in ['Timber','Stone','Plaster','Slate'] if s in key),None)
    if family:manifest.setdefault('material_properties',{})[key]={'normal_map':
        '/Game/Environment/Village/Textures/OriginalSurfaces/T_VIL_'+family+'_Normal'}
manifest['material_properties']['MV_Home_Iron']={'metallic':.75,'roughness':.5}
manifest['noncollision_assets']=list(set(manifest.get('noncollision_assets',[])+['SM_VIL_Plaza_Planting_v044']))
manifest['mesh_source_versions']={name:manifest.get('mesh_source_versions',{}).get(name,source) for name in manifest['assets']}
for name in manifest['assets']:
    if args:os.link(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
    else:shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):
    if args:os.link(f,OUT/f.name)
    else:shutil.copy2(f,OUT/f.name)
if (BASE/'material_sources.json').exists():shutil.copy2(BASE/'material_sources.json',OUT/'material_sources.json')
reports=[]

sites=[
    (-55,5,1.43,7.8,9.2,5.9,3.1,0),
    (-53,58,1.78,8.6,8.2,5.7,3.0,-1.2),
]
if args:sites=[(37,4,-math.pi/2,6.4,7.0,5.3,2.55,0),(30,18,-math.pi/2,6.4,7.0,5.3,2.55,-.7)]
if len(args)>2 and args[2]=='west':sites=[(-52,22,1.43,6.2,7.2,5.1,2.4,-.3),(-46,73,1.78,6.4,7.0,5.3,2.9,.5)]
for variant,(cx,cy,angle,w,d,eave,rise,ridge_x) in enumerate(sites):
    builder=MeshBuilder();mat={k:builder.material(k,c) for k,c in palette.items()}
    wood=mat['MV_Home_Timber_Dark'];light=mat['MV_Home_Timber_Light']
    plaster=mat['MV_Home_Plaster_Cream' if variant==0 else 'MV_Home_Plaster_Cool']
    stone=[mat['MV_Home_Stone_'+str(i)] for i in range(3)]
    slate=[mat['MV_Home_Slate_'+str(i)] for i in range(3)];glass=mat['MV_Home_Glass'];iron=mat['MV_Home_Iron']
    rotate=Matrix.Rotation(angle,4,'Z');samples=[]
    for x in [-w*.48,w*.48]:
        for y in [-d*.48,d*.48]:
            p=rotate@Vector((x,y,0));hit=bvh.ray_cast(Vector((cx+p.x,cy+p.y,150)),Vector((0,0,-1)),260)[0]
            assert hit is not None;samples.append(hit.z)
    if args:assert max(samples)-min(samples)<.5,('Home footprint requires support',samples)
    base=max(samples)-.05
    transform=Matrix.Translation(Vector((cx,cy,base)))@rotate
    def ground_local(x,y):
        p=transform@Vector((x,y,0));hit=bvh.ray_cast(Vector((p.x,p.y,180)),Vector((0,0,-1)),300)[0]
        assert hit is not None;return hit.z-base
    def block(p,size,material=wood,bevel=.025):builder.block(p,size,material,bevel=bevel)
    def beam(a,b,width=.18,material=wood):builder.beam(a,b,width,material)
    def foundation(y):
        count=math.ceil(w/.64)
        for row in range(3):
            for col in range(count+1):
                x0=max(-w/2,-w/2+(col-(row%2)*.5)*w/count)
                x1=min(w/2,-w/2+(col+1-(row%2)*.5)*w/count)
                if x1-x0<.08:continue
                block(((x0+x1)/2,y,.12+row*.22),(x1-x0-.016,.29,.21),stone[(row+col)%3])
    def window(x,y,z,back=False,width=1.0,height=1.32):
        sign=1 if back else -1
        block((x,y+sign*.035,z),(width+.20,.12,height+.17),wood,.014)
        block((x,y+sign*.106,z),(width-.12,.045,height-.10),glass,.008)
        for dx in [-width*.5,width*.5]:block((x+dx,y+sign*.15,z),(.10,.13,height+.19),light,.012)
        for dz in [-height*.5,height*.5]:block((x,y+sign*.15,z+dz),(width+.20,.15,.12),light,.012)
        block((x,y+sign*.17,z),(.047,.07,height-.04),wood,.006)
        block((x,y+sign*.27,z-height*.5-.12),(width+.40,.41,.13),light,.012)
        for side in [-1,1]:
            block((x+side*(width*.5+.24),y+sign*.08,z),(.32,.10,height+.02),light,.013)
            for dz in [-height*.3,height*.3]:block((x+side*(width*.5+.24),y+sign*.15,z+dz),(.32,.04,.055),iron,.005)
    def roof(rx,ry,z,width,depth,lift,ridge=0):
        for side in [-1,1]:
            edge_x=rx+side*width*.5;ridge_world=rx+ridge
            span=abs(edge_x-ridge_world);rows=math.ceil(math.hypot(span,lift)/.38);cols=math.ceil(depth/.39)
            for row in range(rows):
                a=max(0,row/rows-.02);b=min(1,(row+1)/rows+.01)
                xa=ridge_world+(edge_x-ridge_world)*a;xb=ridge_world+(edge_x-ridge_world)*b
                za=z+lift*(1-a)-.16*math.sin(a*math.pi);zb=z+lift*(1-b)-.16*math.sin(b*math.pi)
                for col in range(cols+1):
                    ya=max(ry-depth*.5,ry-depth*.5+(col-(row%2)*.5)*depth/cols)
                    yb=min(ry+depth*.5,ry-depth*.5+(col+1-(row%2)*.5)*depth/cols-.015)
                    if yb-ya<.025:continue
                    points=[Vector((xa,ya,za)),Vector((xb,ya,zb)),Vector((xb,yb,zb)),Vector((xa,yb,za))]
                    if side<0:points.reverse()
                    lower=[p-Vector((0,0,.042)) for p in points];material=slate[(row*3+col*5+variant)%3]
                    builder.face(points,material);builder.face(list(reversed(lower)),material)
                    for i in range(4):j=(i+1)%4;builder.face([points[i],lower[i],lower[j],points[j]],material)
            beam((edge_x,ry-depth*.5-.10,z),(edge_x,ry+depth*.5+.10,z),.21,light)
            for end in [-1,1]:beam((edge_x,ry+end*depth*.5,z),(ridge_world,ry+end*depth*.5,z+lift),.23,light)
        beam((rx+ridge,ry-depth*.5-.2,z+lift+.13),(rx+ridge,ry+depth*.5+.2,z+lift+.13),.25,light)
    # Closed wall envelope, foundation courses and all four elevations.
    if args:
        bottom=min(ground_local(x,y) for x in [-w/2,0,w/2] for y in [-d/2,0,d/2])-.18
        block((0,0,(bottom+.55)/2),(w+.40,d+.40,.55-bottom),stone[0],.05)
    else:block((0,0,.25),(w+.40,d+.40,.60),stone[0],.05)
    block((0,0,3.18),(w,.29,eave-.54),plaster)  # internal spine, obscured by envelope
    for x in [-w/2,w/2]:block((x,0,(eave+.56)*.5),(.26,d,eave-.56),plaster)
    for y in [-d/2,d/2]:
        block((0,y,(eave+.56)*.5),(w,.26,eave-.56),plaster)
        foundation(y)
        vertices=[(-w/2,y-.13,eave),(w/2,y-.13,eave),(ridge_x,y-.13,eave+rise-.06),
                  (-w/2,y+.13,eave),(w/2,y+.13,eave),(ridge_x,y+.13,eave+rise-.06)]
        for face in [(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)]:builder.face([vertices[i] for i in face],plaster)
        sign=1 if y>0 else -1;out=y+sign*.20
        for x in [-w/2,-w/4,0,w/4,w/2]:beam((x,out,.54),(x,out,eave+.10),.20)
        for z in [.63,3.04,eave]:beam((-w/2-.12,out,z),(w/2+.12,out,z),.24)
        for side in [-1,1]:beam((side*w*.5,out,eave),(ridge_x,out,eave+rise),.22)
        beam((ridge_x,out,eave),(ridge_x,out,eave+rise),.18)
        for x in [-w*.35,w*.35]:beam((x-.52,out,3.14),(x+.52,out,eave-.10),.15)
        for x in [-w*.27,w*.27]:
            window(x,y+sign*.18,4.38,y>0)
            if y>0:window(x,y+.18,1.78,True,.88,1.16)
    for x in [-w/2-.19,w/2+.19]:
        for y in [-d/2,-d/4,0,d/4,d/2]:
            beam((x,y,.52),(x,y,eave+.05),.19)
            if abs(y)<d/2-.5:beam((x,y-.65,3.14),(x,y+.65,eave-.15),.14)
        for z in [.60,3.04,eave]:beam((x,-d/2-.1,z),(x,d/2+.1,z),.22)
        # Side window details are turned 90 degrees as a group of original geometry.
        sign=1 if x>0 else -1
        for y in [-d*.24,d*.24]:
            for z in [1.8,4.35]:
                block((x+sign*.06,y,z),(.10,.94,1.21),wood,.014)
                block((x+sign*.12,y,z),(.04,.76,1.08),glass,.008)
                for dy in [-.49,.49]:block((x+sign*.16,y+dy,z),(.11,.10,1.35),light,.012)
                for dz in [-.60,.60]:block((x+sign*.16,y,z+dz),(.12,1.06,.11),light,.012)
                block((x+sign*.25,y,z-.71),(.39,1.24,.13),light,.012)
    roof(0,0,eave+.05,w+1.15,d+1.25,rise,ridge_x)
    # Different fronts: porch/dormer cottage versus supported balcony saltbox.
    door_x=-.80 if variant==0 else 1.05
    block((door_x,-d/2-.20,1.67),(1.20,.15,2.12),wood,.018)
    for i in range(6):block((door_x-.5+i*.2,-d/2-.30,1.67),(.183,.06,2.02),light,.01)
    for dx in [-.68,.68]:beam((door_x+dx,-d/2-.33,.56),(door_x+dx,-d/2-.33,2.85),.15)
    beam((door_x-.75,-d/2-.33,2.85),(door_x+.75,-d/2-.33,2.85),.18)
    for z in [1.05,2.23]:block((door_x,-d/2-.36,z),(1.08,.045,.065),iron,.006)
    for step in range(3):
        y=-d/2-.65-step*.37;top=.58-step*.13
        if args:
            bottom=min(ground_local(door_x+dx,y+dy) for dx in [-1.125,0,1.125] for dy in [-.20,.20])-.15
            block((door_x,y,(top+bottom)/2),(2.25,.40,top-bottom),stone[step%3])
        else:block((door_x,y,.48-step*.13),(2.25,.40,.20),stone[step%3])
    if variant==0:
        for x in [-2.3,2.3]:
            foot=ground_local(x,-d/2-1.35)-.08 if args else .2
            beam((x,-d/2-1.35,foot),(x,-d/2-1.35,2.92),.19)
            beam((x,-d/2-1.35,2.3),(x,-d/2-.7,2.9),.15)
        beam((-2.5,-d/2-1.4,2.90),(2.5,-d/2-1.4,2.90),.21)
        roof(0,-d/2-.80,2.95,5.6,2.2,.85)
        # A compact projecting attic gable avoids a tavern-style grand cross-gable.
        block((.55,-d/2-.17,eave+.65),(2.1,.22,1.28),plaster)
        window(.55,-d/2-.30,eave+.7,False,.85,1.0)
        roof(.55,-d/2+.10,eave+1.30,2.5,2.0,1.08)
    else:
        for i in range(12):block((.7,-d/2-.4-i*.14,3.08),(5.2,.13,.13),light,.011)
        for x in [-1.85,3.2]:
            foot=ground_local(x,-d/2-1.93)-.08 if args else .18
            beam((x,-d/2-1.93,foot),(x,-d/2-1.93,3.0),.19)
            beam((x,-d/2-.2,1.4),(x,-d/2-1.75,3.0),.19)
        for i in range(10):beam((-1.85+i*.56,-d/2-1.90,3.14),(-1.85+i*.56,-d/2-1.90,4.13),.08)
        for z in [3.23,4.15]:beam((-2.02,-d/2-1.90,z),(3.37,-d/2-1.90,z),.12,light)
    # Small chimneys and a rear service door make the buildings legible behind.
    for course in range(8):
        z=eave+rise*.5+course*.25
        block((-w*.29,d*.24,z),(.92,.94,.23),stone[course%3],.027)
    block((-w*.29,d*.24,eave+rise*.5+1.92),(1.10,1.12,.16),stone[2],.026)
    block((0,d/2+.24,1.50),(.93,.13,1.9),wood,.016)
    for i in range(5):block((-.37+i*.185,d/2+.33,1.50),(.17,.05,1.83),light,.01)
    name=('SM_VIL_Home_PorchCottage_' if variant==0 else 'SM_VIL_Home_BalconySaltbox_')+version
    obj=builder.build(name,transform);export_mesh(obj,OUT/(name+'.fbx'));manifest['assets'].append(name)
    # Remove only forest instances that would physically intersect the new roof envelope.
    old_count=len(manifest.get('instances',[]))
    manifest['instances']=[row for row in manifest.get('instances',[]) if
        math.hypot(row['position_m'][0]-cx,row['position_m'][1]-cy)>max(w,d)*.65+3.8]
    reports.append({'name':name,'center_m':[cx,cy,base],'ground_samples_m':samples,
        'removed_intersecting_tree_instances':old_count-len(manifest['instances']),
        'polygon_count':len(obj.data.polygons),'height_m':eave+rise})

manifest['version']=version;manifest['geometry_source_version']=source;manifest['stage']='DESIGNED_HOMES_REQUIRES_FIXED_AND_FREE_CAMERA_REVIEW'
manifest['geometry_changes']=['Lower terrace porch/dormer cottage and upper terrace balcony saltbox with different designed silhouettes',
    'All four elevations carry stone foundations, framed side/rear windows and service doors',
    'Only intersecting forest instances removed; existing terrain, road, six cameras and daylight unchanged']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'homes_report.json').write_text(json.dumps({'houses':reports,'status':'NOT_VISUALLY_ACCEPTED'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('SEKAI_Valley_Terrain_'+version+'.blend')))
print('DESIGNED_HOMES_SAVED',reports)
