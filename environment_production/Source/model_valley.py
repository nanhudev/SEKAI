"""Original 180 x 220 metre starter-valley terrain and continuous route prototype."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import math
import json
import sys
from pathlib import Path
from mathutils import Vector
from mathutils import noise as natural_noise

ROOT=Path(str(_SEKAI_ROOT / 'environment_production'))
VERSION=sys.argv[-1] if '--' in sys.argv else 'v001'
REFINE=VERSION!='v001'
OUT=ROOT/'Terrain'/VERSION
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'
scene.unit_settings.scale_length=1
collection=bpy.data.collections.new('SEKAI_VALLEY_TERRAIN')
scene.collection.children.link(collection)

def material(name,color,roughness=.9):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1)
    bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Roughness'].default_value=roughness
    noise=m.node_tree.nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=2.3
    coord=m.node_tree.nodes.new('ShaderNodeTexCoord')
    m.node_tree.links.new(coord.outputs['Object'],noise.inputs['Vector'])
    ramp=m.node_tree.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position=.22
    ramp.color_ramp.elements[0].color=(*(v*.65 for v in color),1)
    ramp.color_ramp.elements[1].position=.78
    ramp.color_ramp.elements[1].color=(*(min(1,v*1.24) for v in color),1)
    m.node_tree.links.new(noise.outputs['Fac'],ramp.inputs[0])
    m.node_tree.links.new(ramp.outputs['Color'],bs.inputs['Base Color'])
    bump=m.node_tree.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.25;bump.inputs['Distance'].default_value=.06
    m.node_tree.links.new(noise.outputs['Fac'],bump.inputs['Height']);m.node_tree.links.new(bump.outputs[0],bs.inputs['Normal'])
    return m

grass=material('MV_Valley_Grass',(.24,.31,.12))
rock=material('MV_Valley_Cliff',(.31,.34,.33))
dirt=material('MV_Valley_Dirt',(.38,.30,.19))
wet=material('MV_Valley_WetBank',(.15,.19,.16),.74)
water=material('MV_Valley_Water_Prototype',(.025,.22,.24),.18)
stone=material('MV_Valley_Paving',(.39,.40,.34))
foam=material('MV_Valley_Foam',(.78,.84,.80),.42)

def smooth(a,b,t):
    t=max(0,min(1,(t-a)/(b-a)));return t*t*(3-2*t)

def geology(x,y,scale=1):
    return natural_noise.fractal(Vector((x*scale,y*scale,7.31)),1.0,2.0,3)

def river_x(y):return -29+13*math.sin(y/38)+3.3*math.sin(y/15)

def water_z(y):return -.4+.019*(y+100)+2.7*smooth(-30,-28.5,y)+2.4*smooth(43,44.5,y)

def river_half(y):
    return 3.7+.65*math.sin(y/11)+2.8*math.exp(-((y+36)/8)**2)+3.2*math.exp(-((y-37)/9)**2)

# Asymmetric terraces have distinct land uses; the perimeter remains mountainous.
pads=[('Plaza',20,13,27,24,8.2),('Tavern',38,42,21,17,11.3),
      ('Forge',61,27,16,17,10.2),('Tree',-1,47,17,16,13.4),
      ('WestResidential',-57,15,21,24,8.6),('UpperResidential',-48,63,20,24,14.2),
      ('EastResidential',38,-24,19,15,5.6),('Farm',65,-33,18,23,4.9),
      ('Training',51,81,27,21,16.2),('Entrance',-57,-88,16,18,1.9)]

def ungraded_height(x,y):
    h=1.0+.049*(y+100)+.22*math.sin(x/15)*math.sin(y/19)
    if REFINE:
        h=1.7+.012*(y+100)+.35*geology(x,y,.055)
        shelf=-8+.07*x+6*math.sin(x/18)
        upper=34+.23*(x-12)+4*math.sin(x/16)
        high=71-.20*x+4*math.sin(x/22)
        h+=2.0*smooth(shelf-1.7,shelf+1.7,y)
        h+=3.0*smooth(upper-1.3,upper+1.3,y)
        h+=3.5*smooth(high-1.8,high+1.8,y)
    for name,px,py,rx,ry,z in pads:
        angle=math.atan2((y-py)/ry,(x-px)/rx)
        shape=1+.055*math.sin(angle*3+.6)+.033*math.sin(angle*7+px)
        radius=(abs((x-px)/rx)**3+abs((y-py)/ry)**3)**(1/3)/shape
        mix=1-smooth(.80,1.22,radius) if REFINE else 1-smooth(.91,1.05,radius)
        h=h*(1-mix)+(z+.045*math.sin(x*.43)*math.sin(y*.38))*mix
    rim=smooth(69,95,abs(x))
    h+=rim*(17+8*geology(x,y,.025))+smooth(98,135,y)*20
    d=abs(x-river_x(y))
    bank=2.0*math.sin(y*.24)+.9*math.sin(y*.71)
    channel=1-smooth(river_half(y)+.3,river_half(y)+7.5+bank if REFINE else 9.5,d)
    bed=water_z(y)-1.3+.13*math.sin(x*.5+y*.15)
    h=h*(1-channel)+bed*channel
    if VERSION not in ['v001','v002']:
        exposed=smooth(.15,.8,channel)*(1-channel)
        rim_detail=smooth(58,88,abs(x))
        h+=exposed*3.8*geology(x,y,.18)+rim_detail*3.0*geology(x,y,.09)
    return h

route=[(-58,-99,1.9),(-56,-77,2.1),(-48,-58,2.5),(-46,-45,3.0),
       (-18,-42,3.0),(0,-23,4.7),(18,-6,7.3),(20,16,8.2),
       (18,40,11.6),(30,59,14.0),(46,80,16.2),(57,101,17.0)]

def nearest_route(x,y):
    best=(1e9,0)
    for a,b in zip(route,route[1:]):
        dx,dy=b[0]-a[0],b[1]-a[1]
        t=max(0,min(1,((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy)))
        d=math.hypot(x-a[0]-t*dx,y-a[1]-t*dy)
        if d<best[0]:best=(d,a[2]+t*(b[2]-a[2]))
    return best

def height(x,y):
    h=ungraded_height(x,y)
    d,z=nearest_route(x,y)
    bridge=abs(x-river_x(y))<8.5 and -49<y<-38
    if not bridge and abs(x-river_x(y))>7:
        mix=1-smooth(2.6,5.4,d);h=h*(1-mix)+(z-.06)*mix
    return h

def mesh(name,verts,faces,materials):
    name=name.replace('_v001','_'+VERSION)
    data=bpy.data.meshes.new(name+'_Geometry');data.from_pydata(verts,[],faces);data.update()
    o=bpy.data.objects.new(name,data);collection.objects.link(o)
    for m in materials:data.materials.append(m)
    return o

nx,ny=241,281
verts=[];faces=[]
for j in range(ny):
    y=-130+j
    for i in range(nx):
        x=-120+i;verts.append((x,y,height(x,y)))
for j in range(ny-1):
    for i in range(nx-1):
        k=j*nx+i;faces.extend([(k,k+1,k+nx+1),(k,k+nx+1,k+nx)])
terrain=mesh('SM_VIL_Valley_Terrain_v001',verts,faces,[grass,rock,dirt,wet])
for p in terrain.data.polygons:
    x,y=p.center.x,p.center.y
    if abs(x-river_x(y))<10:p.material_index=3
    elif p.normal.z<.76:p.material_index=1
    elif nearest_route(x,y)[0]<4:p.material_index=2
    else:p.material_index=0
    p.use_smooth=True

if VERSION not in ['v001','v002','v003','v004']:
    surface=material('MV_Valley_Surface',(.24,.31,.12))
    bs=next(n for n in surface.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    attribute=surface.node_tree.nodes.new('ShaderNodeVertexColor');attribute.layer_name='Color'
    surface.node_tree.links.new(attribute.outputs['Color'],bs.inputs['Base Color'])
    terrain.data.materials.clear();terrain.data.materials.append(surface)
    colors=terrain.data.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
    for p in terrain.data.polygons:
        p.material_index=0
        for li in p.loop_indices:
            v=terrain.data.vertices[terrain.data.loops[li].vertex_index].co
            dx=(height(v.x+.5,v.y)-height(v.x-.5,v.y))
            dy=(height(v.x,v.y+.5)-height(v.x,v.y-.5))
            slope=1/math.sqrt(1+dx*dx+dy*dy)
            stone_mix=1-smooth(.62,.92,slope)
            color=[grass.diffuse_color[k]*(1-stone_mix)+rock.diffuse_color[k]*stone_mix for k in range(3)]
            trail_mix=1-smooth(2.2,4.8,nearest_route(v.x,v.y)[0])
            color=[color[k]*(1-trail_mix)+dirt.diffuse_color[k]*trail_mix for k in range(3)]
            variation=1+.15*geology(v.x,v.y,.25)
            colors.data[li].color=(*(c*variation for c in color),1)

# The river descends over two modeled ledges; opaque water is only a prototype.
wv=[];wf=[]
for j in range(281):
    y=-130+j;cx=river_x(y);half=river_half(y)
    for i in range(9):
        x=cx-half+2*half*i/8;wv.append((x,y,water_z(y)+.035*math.sin(i*1.3+j*.4)))
for j in range(280):
    for i in range(8):
        k=j*9+i;wf.append((k,k+1,k+10,k+9))
stream=mesh('SM_VIL_Valley_Stream_v001',wv,wf,[water,foam])
for p in stream.data.polygons:
    y=p.center.y
    falling=abs(water_z(y+.5)-water_z(y-.5))>.35
    if falling:p.material_index=1

# Continuous road ribbon; bridge owns the stream crossing instead of terrain.
rv=[];rf=[]
route_normals=[]
for index,point in enumerate(route):
    before=route[max(0,index-1)];after=route[min(len(route)-1,index+1)]
    dx,dy=after[0]-before[0],after[1]-before[1]
    length=math.hypot(dx,dy);route_normals.append((-dy/length,dx/length))
for segment,(a,b) in enumerate(zip(route,route[1:])):
    dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy)
    steps=math.ceil(length/.75);normal=(-dy/length,dx/length)
    start=len(rv)
    for n in range(steps+1):
        t=n/steps;x=a[0]+dx*t;y=a[1]+dy*t
        normal=tuple(route_normals[segment][k]*(1-t)+route_normals[segment+1][k]*t for k in range(2))
        for side in [-1,1]:
            px=x+normal[0]*2.5*side;py=y+normal[1]*2.5*side
            z=a[2]+(b[2]-a[2])*t if segment==3 else height(px,py)+.065
            rv.append((px,py,z))
    for n in range(steps):
        k=start+n*2;rf.append((k,k+2,k+3,k+1))
road=mesh('SM_VIL_Valley_CriticalRoute_v001',rv,rf,[dirt,stone])
for p in road.data.polygons:p.material_index=1 if p.center.y>-12 else 0

# Geology is concentrated at exposed ledges rather than scattered across paths.
def cliff(name,x,y,w,d,h,angle):
    vv=[];ff=[];rings=7;segments=11
    base=height(x,y)-h*.72
    for r in range(rings):
        t=r/(rings-1)
        for i in range(segments):
            a=i*math.tau/segments+angle
            radius=(1.20-.37*t)*(1+.20*geology(i,r,.63))
            vv.append((x+math.cos(a)*w*.5*radius,y+math.sin(a)*d*.5*radius,
                       base+t*h+.55*geology(i,r,.83)))
    for r in range(rings-1):
        for i in range(segments):
            a=r*segments+i;b=r*segments+(i+1)%segments
            ff.append((a,b,b+segments,a+segments))
    ff.append(tuple((rings-1)*segments+i for i in range(segments)))
    return mesh(name,vv,ff,[rock])

crags=[]
for i,(x,y,w,d,h) in enumerate([(-72,41,14,11,9),(-65,56,12,11,11),(-68,75,13,12,13),
    (-17,46,9,11,9),(-13,59,9,8,7),(-52,30,7,9,7),(55,7,9,8,7),
    (74,55,12,10,12),(77,79,16,13,15),(-79,-43,18,14,13),(81,-79,18,15,14)]):
    crags.append(cliff('SM_VIL_Valley_Cliff_%02d'%i,x,y,w,d,h,i*.38))
if VERSION in ['v003','v004','v005','v006']:
    for j,y in enumerate(range(-78,99,13)):
        y+=3.4*geology(j,4,.7)
        for side in [-1,1]:
            if -51<y<-34:continue
            x=river_x(y)+side*(9.8+2.4*geology(j,side,.8))
            h=max(2.8,height(x,y)-water_z(y)+1.8)
            crags.append(cliff('SM_VIL_River_Outcrop_%02d_%s'%(j,'E' if side>0 else 'W'),
                x,y,9+3.8*geology(j,3,.7),11+3.6*geology(j,7,.5),h,j*.43))

if VERSION not in ['v001','v002','v003','v004','v005','v006']:
    # Connected, stratified faces replace the isolated river-edge rock tokens.
    for side in [-1,1]:
        vv=[];ff=[];rows=10;columns=185
        for j in range(columns):
            y=-90+j
            half=river_half(y)
            outer=river_x(y)+side*(half+6.2+1.25*geology(y,side,.18))
            top=height(outer,y)+.1;bottom=water_z(y)-.6
            for r in range(rows):
                t=r/(rows-1)
                fractured=.30*geology(y,r,.7)+.22*math.sin(r*2.8)
                x=river_x(y)+side*(half+.5+(abs(outer-river_x(y))-half-.5)*t+fractured)
                z=bottom+(top-bottom)*t+.24*geology(y,r,.5)*math.sin(math.pi*t)
                vv.append((x,y,z))
        for j in range(columns-1):
            y=-90+j
            if -51<y<-36:continue
            for r in range(rows-1):
                k=j*rows+r;face=(k,k+rows,k+rows+1,k+1)
                ff.append(face if side<0 else tuple(reversed(face)))
        crags.append(mesh('SM_VIL_River_Bank_'+('East' if side>0 else 'West'),vv,ff,[rock]))
    ledges=[('WestHomes',[(-77,-2),(-67,-6),(-53,-7),(-40,-2)],2.8),
        ('UpperHomes',[(-70,44),(-58,43),(-46,46),(-35,54)],8.1),
        ('Tree',[(-14,33),(-6,30),(4,31),(12,38)],8.0),
        ('Training',[(29,64),(40,62),(57,63),(73,70)],10.9)]
    for name,points,bottom in ledges:
        vv=[];ff=[];rows=10
        for a,b in zip(points,points[1:]):
            dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy)
            steps=math.ceil(length/.8);start=len(vv)
            for j in range(steps+1):
                u=j/steps;x=a[0]+dx*u;y=a[1]+dy*u;top=height(x,y)-.05
                for r in range(rows):
                    t=r/(rows-1);out=(1-t)*1.8+.25*geology(x+r,y,.6)*math.sin(math.pi*t)
                    vv.append((x+dy/length*out,y-dx/length*out,bottom+(top-bottom)*t))
            for j in range(steps):
                for r in range(rows-1):
                    k=start+j*rows+r;ff.append((k,k+rows,k+rows+1,k+1))
        crags.append(mesh('SM_VIL_Terrace_Face_'+name,vv,ff,[rock]))

surroundings=[]
if VERSION not in ['v001','v002','v003','v004','v005','v006','v007','v008']:
    vv=[];ff=[];count=101
    for j in range(count):
        y=-500+j*10
        for i in range(count):
            x=-500+i*10;cx=max(-120,min(120,x));cy=max(-130,min(150,y))
            distance=math.hypot(x-cx,y-cy)
            elevation=10+12*geology(x,y,.008)
            elevation+=85*math.exp(-((y-315)/115)**2)*(1+.42*geology(x,y,.013))
            elevation+=65*math.exp(-((abs(x)-315)/105)**2)*(1+.35*geology(x,y,.018))
            blend=smooth(0,100,distance)
            z=height(cx,cy)*(1-blend)+elevation*blend
            vv.append((x,y,z))
    for j in range(count-1):
        for i in range(count-1):
            x=-500+i*10+5;y=-500+j*10+5
            if -120<x<120 and -130<y<150:continue
            k=j*count+i;ff.append((k,k+1,k+count+1,k+count))
    backdrop=mesh('SM_VIL_Valley_Surroundings',vv,ff,[grass,rock])
    for p in backdrop.data.polygons:
        p.use_smooth=True;p.material_index=1 if p.normal.z<.8 or p.center.z>70 else 0
    surroundings.append(backdrop)
assets=[terrain,stream,road]+crags+surroundings
for o in assets:
    uv=o.data.uv_layers.new(name='UV_Metric')
    for p in o.data.polygons:
        axis=max(range(3),key=lambda i:abs(p.normal[i]))
        for li in p.loop_indices:
            v=o.data.vertices[o.data.loops[li].vertex_index].co
            a,b=((v.y,v.z) if axis==0 else ((v.x,v.z) if axis==1 else (v.x,v.y)))
            uv.data[li].uv=(a*.35,b*.35)
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
    bpy.ops.export_scene.fbx(filepath=str(OUT/(o.name+'.fbx')),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')

cameras=[]
for name,x,y,tx,ty in [('CAM_01_Entrance',-58,-100,-45,-48),('CAM_02_Bridge',-46,-45,18,12),
 ('CAM_03_Plaza',20,-3,-1,47),('CAM_04_Residential',-56,20,20,13),('CAM_05_Exit',50,85,20,13)]:
    z=height(x,y)+1.7
    if name=='CAM_02_Bridge':z=4.7
    cameras.append({'name':name,'position_m':[x,y,z],'target_m':[tx,ty,height(tx,ty)+3.0],'fov':75})
cameras.append({'name':'CAM_06_Aerial','position_m':[190,-285,250],'target_m':[0,15,6],'fov':50})
manifest={'stage':'TERRAIN_PROTOTYPE_NOT_VISUALLY_ACCEPTED','core_extent_m':[180,220],
 'assets':[o.name for o in assets],'pads':[{'name':p[0],'center_m':[p[1],p[2],p[5]],'radius_m':[p[3],p[4]]} for p in pads],
 'cameras':cameras,'route_m':route,'known_gaps':['reference visual comparison','walkability verification',
 'native Landscape conversion','water material and foam','cliff smoothing and rock textures','landmarks and architecture']}
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('SEKAI_Valley_Terrain_'+VERSION+'.blend')))

bpy.ops.object.light_add(type='SUN',location=(-60,-90,100));sun=bpy.context.object;sun.name='REVIEW_MorningSun'
sun.data.energy=2.5;sun.data.angle=.09;sun.rotation_euler=(.60,-.32,-.65)
world=bpy.data.worlds.new('REVIEW_World');scene.world=world;world.use_nodes=True
bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.45,.57,.73,1);bg.inputs[1].default_value=.5
bpy.ops.object.camera_add(location=(190,-285,250));cam=bpy.context.object;cam.name='CAM_06_Aerial'
cam.rotation_euler=(Vector((0,15,6))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=42;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=20;scene.cycles.use_denoising=False
scene.render.threads_mode='FIXED';scene.render.threads=6
scene.render.resolution_x=1500;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUT/('Terrain_Blender_Aerial_'+VERSION+'.png'))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('SEKAI_Valley_Review_'+VERSION+'.blend')))
bpy.ops.render.render(write_still=True)
print('SEKAI_VALLEY_MODELED',str(OUT))
