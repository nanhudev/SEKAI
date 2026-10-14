"""Original SEKAI tavern, authored in metres. Run with Blender --background --python."""
import bpy
import math
import json
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
VERSION=args[args.index('--version')+1] if '--version' in args else 'v001'
REFINE=VERSION!='v001'
HERO_REFINE=VERSION not in ['v001','v002','v003']
SURFACE_REFINE=VERSION not in ['v001','v002','v003','v004']
MAIN_RISE=4.45 if SURFACE_REFINE else (5.4 if HERO_REFINE else 4.15)
OUT = ROOT / 'Versions' / VERSION
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
collections = {}
for name in ['_ARCHITECTURE', '_PROPS', '_INFRASTRUCTURE', '_HERO', '_EXPORT', '_REFERENCE']:
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    collections[name] = c
parts = []

def material(name, color, roughness, noise_scale=5, bump=.08):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    n, links = m.node_tree.nodes, m.node_tree.links
    bs = next(x for x in n if x.type == 'BSDF_PRINCIPLED')
    bs.inputs['Roughness'].default_value = roughness
    tex = n.new('ShaderNodeTexNoise')
    tex.inputs['Scale'].default_value = noise_scale
    tex.inputs['Detail'].default_value = 3
    coord = n.new('ShaderNodeTexCoord')
    if REFINE and 'Timber' in name:
        stretch=n.new('ShaderNodeVectorMath');stretch.operation='MULTIPLY'
        stretch.inputs[1].default_value=(3,3,.14)
        links.new(coord.outputs['Generated'],stretch.inputs[0])
        links.new(stretch.outputs[0],tex.inputs['Vector'])
    else:links.new(coord.outputs['Generated'], tex.inputs['Vector'])
    ramp = n.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (*[v*.76 for v in color], 1)
    ramp.color_ramp.elements[1].color = (*[min(1,v*1.12) for v in color], 1)
    links.new(tex.outputs['Fac'], ramp.inputs[0])
    links.new(ramp.outputs[0], bs.inputs['Base Color'])
    b = n.new('ShaderNodeBump')
    b.inputs['Strength'].default_value = .28
    b.inputs['Distance'].default_value = bump
    links.new(tex.outputs['Fac'], b.inputs['Height'])
    links.new(b.outputs[0], bs.inputs['Normal'])
    m.diffuse_color = (*color, 1)
    return m

plaster = material('MV_Plaster_Warm', (.68,.60,.43), .85, 7, .024)
timber = material('MV_Timber_Dark', (.15,.075,.033), .72, 9, .015)
wood = material('MV_Timber_Warm', (.32,.17,.07), .77, 12, .013)
stone = [material('MV_Stone_'+str(i), c, .9, 6, .033) for i,c in enumerate([
    (.36,.37,.34),(.43,.42,.36),(.30,.33,.33),(.49,.46,.38)])]
slate = [material('MV_Roof_Slate_'+str(i), c, .76, 7, .014) for i,c in enumerate([
    (.10,.16,.21),(.14,.21,.27),(.19,.24,.28),(.12,.18,.23),(.22,.25,.25)])]
metal = material('MV_Metal_BlackIron', (.035,.043,.047), .46, 7, .004)
next(n for n in metal.node_tree.nodes if n.type == 'BSDF_PRINCIPLED').inputs['Metallic'].default_value = .8
glass = material('MV_Window_Amber', (.6,.29,.055), .28, 3, .001)
bs = next(x for x in glass.node_tree.nodes if x.type == 'BSDF_PRINCIPLED')
bs.inputs['Emission Color'].default_value = (.9,.36,.065,1)
bs.inputs['Emission Strength'].default_value = .55

def own(o, name, mat, group='_ARCHITECTURE'):
    o.name = name
    for c in list(o.users_collection): c.objects.unlink(o)
    collections[group].objects.link(o)
    if mat: o.data.materials.append(mat)
    parts.append(o)
    return o

def box(name, center, size, mat, bevel=.015):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    o = own(bpy.context.object, name, mat)
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        b=o.modifiers.new('Crafted_Edges','BEVEL'); b.width=bevel; b.segments=2
        o.modifiers.new('Weighted_Normals','WEIGHTED_NORMAL')
    return o

def beam(name, a, b, width=.2, depth=None, mat=timber):
    a,b=Vector(a),Vector(b)
    o=box(name,(a+b)/2,(width,depth or width,(b-a).length),mat,.014)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    return o

def mesh(name, verts, faces, mat):
    data=bpy.data.meshes.new(name+'_Geometry');data.from_pydata(verts,[],faces);data.update()
    o=bpy.data.objects.new(name,data);collections['_ARCHITECTURE'].objects.link(o)
    data.materials.append(mat);parts.append(o);return o

def roof(name, cx, cy, z, w, d, rise, tile=True):
    hw=w/2
    for s in [-1,1]:
        if REFINE:
            vv=[];ff=[]
            for row in range(21):
                t=row/20;zz=z+rise*(1-t)-.24*math.sin(math.pi*t)-.025
                vv.extend([(cx+s*hw*t,cy-d/2,zz),(cx+s*hw*t,cy+d/2,zz)])
            for row in range(20):
                k=row*2;f=(k,k+2,k+3,k+1)
                ff.append(f if s==1 else tuple(reversed(f)))
            mesh(name+'_Deck_'+str(s),vv,ff,slate[0])
        else:
            mesh(name+'_Deck_'+str(s), [(cx,cy-d/2,z+rise),(cx+s*hw,cy-d/2,z),
                 (cx+s*hw,cy+d/2,z),(cx,cy+d/2,z+rise)],[(0,1,2,3)] if s==1 else [(3,2,1,0)],slate[0])
        beam(name+'_Eave_'+str(s),(cx+s*hw,cy-d/2-.15,z),(cx+s*hw,cy+d/2+.15,z),.22,mat=wood)
        for sy in [-1,1]:
            beam(name+'_Barge_'+str(s)+'_'+str(sy),(cx+s*(hw+.16),cy+sy*(d/2+.10),z-.1),
                 (cx,cy+sy*(d/2+.10),z+rise+.16),.24,mat=wood)
        if tile:
            verts=[];faces=[];mi=[]
            rows=math.ceil(math.hypot(hw,rise)/.40)
            cols=math.ceil(d/.36)
            for row in range(rows):
                lo=max(0,row/rows-.025);hi=min(1,(row+1)/rows+.015)
                for col in range(cols+1):
                    y0=cy-d/2+(col-(row%2)*.5)*d/cols
                    y0=max(cy-d/2,y0); y1=min(cy+d/2,y0+d/cols-.018)
                    if y1<=y0:continue
                    za=z+rise*(1-lo)+.028+.010*math.sin(col*3.2+row)
                    zb=z+rise*(1-hi)+.038
                    if REFINE:
                        za-=.24*math.sin(math.pi*lo)
                        zb-=.24*math.sin(math.pi*hi)
                    x0=cx+s*hw*lo; x1=cx+s*hw*hi
                    k=len(verts)
                    verts.extend([(x0,y0,za),(x1,y0,zb),(x1,y1,zb),(x0,y1,za),
                                  (x0,y0,za-.04),(x1,y0,zb-.04),(x1,y1,zb-.04),(x0,y1,za-.04)])
                    fs=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
                    if s<0:fs=[tuple(reversed(f)) for f in fs]
                    faces.extend([tuple(k+i for i in f) for f in fs]);mi.extend([(row*7+col*3)%len(slate)]*6)
            o=mesh(name+'_Individual_Slate',verts,faces,slate[0])
            for m in slate[1:]:o.data.materials.append(m)
            for p,i in zip(o.data.polygons,mi):p.material_index=i
    beam(name+'_Ridge',(cx,cy-d/2-.28,z+rise+.18),(cx,cy+d/2+.28,z+rise+.18),.26,mat=wood)

def stone_courses(name, cx, cy, bottom, w, h, depth=.32):
    rows=math.ceil(h/.28);cols=math.ceil(w/.57)
    for r in range(rows):
        for col in range(cols+1):
            l=-w/2+(col-.5*(r%2))*w/cols
            right=min(w/2,l+w/cols);l=max(-w/2,l)
            if right-l<.07:continue
            box(name+'_%02d_%02d'%(r,col),(cx+(l+right)/2,cy,bottom+(r+.5)*h/rows),
                (right-l-.018,depth,h/rows-.018),stone[(r*3+col)%4],.025)

def window(name,x,y,z,w=1.15,h=1.50):
    box(name+'_Recess',(x,y+.04,z),(w+.15,.16,h+.15),timber)
    box(name+'_Glass',(x,y-.065,z),(w-.10,.045,h-.12),glass,.005)
    for dx in [-w/2,w/2]:box(name+'_Jamb',(x+dx,y-.1,z),(.12,.17,h+.18),wood)
    for dz in [-h/2,h/2]:box(name+'_Lintel',(x,y-.1,z+dz),(w+.18,.18,.13),wood)
    beam(name+'_Mullion',(x,y-.15,z-h/2),(x,y-.15,z+h/2),.065,mat=metal)
    for dz in [-.34,.34]:box(name+'_Transom',(x,y-.15,z+dz),(w,.07,.05),metal,.006)
    for dx in [-w*.65,w*.65]:
        box(name+'_Shutter',(x+dx,y-.04,z),(.35,.13,h),wood)
        for dz in [-h*.33,h*.33]:box(name+'_Shutter_Hinge',(x+dx,y-.12,z+dz),(.36,.05,.055),metal,.004)
    box(name+'_Sill',(x,y-.18,z-h/2-.11),(w+.34,.42,.13),wood)

# A 12 x 16 metre hero envelope with a 3.2 metre clear ground floor.
# Front wall is segmented around the 1.6 x 2.4 metre door opening.
box('SM_VIL_Tavern_Foundation',(0,0,.35),(10.4,13.2,.7),stone[1],.055)
box('SM_VIL_Tavern_GroundFloor',(0,0,.72),(10,13,.18),wood)
for x in [-5,5]:box('SM_VIL_Tavern_SideWall',(x,0,2.26),(.28,13,3.02),plaster)
box('SM_VIL_Tavern_BackWall',(0,6.5,2.26),(10,.28,3.02),plaster)
for x,w in [(-2.9,4.2),(2.9,4.2)]:box('SM_VIL_Tavern_FrontWall',(x,-6.5,2.26),(w,.28,3.02),plaster)
box('SM_VIL_Tavern_DoorHeader',(0,-6.5,3.50),(1.6,.28,.60),plaster)
box('SM_VIL_Tavern_UpperFloor',(0,0,3.9),(10.6,13.6,.3),wood)
for x in [-5.3,5.3]:box('SM_VIL_Tavern_UpperSide',(x,0,5.35),(.26,13.6,2.65),plaster)
for y in [-6.8,6.8]:
    box('SM_VIL_Tavern_UpperEnd',(0,y,5.35),(10.6,.26,2.65),plaster)
    mesh('SM_VIL_Tavern_Gable', [(-5.3,y,6.70),(5.3,y,6.70),(0,y,6.78+MAIN_RISE if HERO_REFINE else 10.55)],[(0,1,2)],plaster)
for x in [-5,-2.55,0,2.55,5]:
    for y in [-6.66,6.66]:
        beam('SM_VIL_Tavern_PrimaryPost',(x,y,.72),(x,y,3.9),.25)
for x in [-5.4,-2.7,0,2.7,5.4]:
    for y in [-6.94,6.94]:
        beam('SM_VIL_Tavern_UpperPost',(x,y,3.96),(x,y,6.82),.23)
for y in [-6.98,6.98]:
    for z in [4.02,6.76]:beam('SM_VIL_Tavern_RingBeam',(-5.55,y,z),(5.55,y,z),.26)
    for x in [-4,4]:
        beam('SM_VIL_Tavern_Brace',(x-1,y,4.15),(x+1,y,6.55),.18)
    for x in [-1,1]:beam('SM_VIL_Tavern_GableRafter',(x*5.42,y,6.76),(0,y,6.88+MAIN_RISE if HERO_REFINE else 10.65),.24)
    beam('SM_VIL_Tavern_GableKingPost',(0,y,6.76),(0,y,6.93+MAIN_RISE if HERO_REFINE else 10.7),.22)
    beam('SM_VIL_Tavern_GableTie',(-3,y,8.4),(3,y,8.4),.18)
for x in [-5.42,5.42]:
    for y in [-4.5,-1.5,1.5,4.5]:
        beam('SM_VIL_Tavern_SidePost',(x,y,.72),(x,y,6.80),.23)
        beam('SM_VIL_Tavern_SideBrace',(x,y-1,4.1),(x,y+1,6.55),.18)
    for z in [3.86,6.76]:beam('SM_VIL_Tavern_SideRing',(x,-7,z),(x,7,z),.25)
roof('SM_VIL_Tavern_MainRoof',0,0,6.78,12.0,15.1,MAIN_RISE)

# Front-facing dormer and a lower side wing interrupt the primary roof silhouette.
box('SM_VIL_Tavern_DormerWall',(0,-5.60,8.28),(3,.24,2.05),plaster)
mesh('SM_VIL_Tavern_DormerGable',[(-1.5,-5.74,9.28),(1.5,-5.74,9.28),(0,-5.74,10.6)],[(0,1,2)],plaster)
roof('SM_VIL_Tavern_DormerRoof',0,-4.2,9.25,3.5,3.8,1.5)
window('SM_VIL_Tavern_DormerWindow',0,-5.80,8.35,1.05,1.25)
for x in [-3.5,0,3.5]:window('SM_VIL_Tavern_UpperWindow',x,-7.08,5.35)
for x in [-3.45,3.45]:window('SM_VIL_Tavern_GroundWindow',x,-6.88,2.18,1.20,1.45)

# Porch columns, braces and exposed joists carry the sheltered frontage.
box('SM_VIL_Tavern_PorchDeck',(0,-7.65,.72),(11.5,2.7,.20),wood)
for x in [-5.35,-2.6,2.6,5.35]:
    box('SM_VIL_Tavern_PorchFoot',(x,-8.8,.55),(.60,.60,.7),stone[2],.045)
    beam('SM_VIL_Tavern_PorchColumn',(x,-8.8,.9),(x,-8.8,3.7),.23)
    beam('SM_VIL_Tavern_PorchKnee',(x,-8.8,2.85),(x+.65,-8.8,3.62),.17)
beam('SM_VIL_Tavern_PorchFrontBeam',(-5.7,-8.8,3.72),(5.7,-8.8,3.72),.26)
for i in range(18):
    x=-5.6+i*11.2/17
    beam('SM_VIL_Tavern_PorchRafter',(x,-6.56,4.18),(x,-9.15,3.56),.12)
mesh('SM_VIL_Tavern_PorchRoof',[(-5.85,-6.45,4.25),(5.85,-6.45,4.25),(5.85,-9.35,3.55),(-5.85,-9.35,3.55)],[(0,3,2,1)],slate[2])
for row in range(7):
    for col in range(31):
        o=box('SM_VIL_Tavern_PorchSlate',(-5.65+col*.375,-6.7-row*.395,4.24-row*.095),(.355,.48,.047),slate[(row+col*3)%5],.005)
        o.rotation_euler.x=math.atan(.24)

# Stone courses stay individually readable at first-person distance.
for y in [-6.68,6.68]:stone_courses('SM_VIL_Tavern_StonePlinth',0,y,.04,10.45,.72)
for i in range(4):
    box('SM_VIL_Stair_Stone_Tavern_%02d'%i,(0,-9.3-.36*(3-i),.10+.09*i),(2.45,.38,.20+.18*i),stone[1],.035)
for i in range(8):box('SM_VIL_Tavern_DoorPlank',(-.69+i*.197,-6.69,1.96),(.183,.09,2.25),wood)
for z in [1.25,2.60]:box('SM_VIL_Tavern_DoorStrap',(0,-6.77,z),(1.48,.055,.085),metal,.008)
for x in [-.86,.86]:beam('SM_VIL_Tavern_DoorJamb',(x,-6.83,.75),(x,-6.83,3.18),.17,mat=wood)
beam('SM_VIL_Tavern_DoorLintel',(-.92,-6.83,3.18),(.92,-6.83,3.18),.19,mat=wood)
bpy.ops.mesh.primitive_torus_add(major_radius=.105,minor_radius=.018,major_segments=20,minor_segments=8,location=(.43,-6.85,1.8),rotation=(math.pi/2,0,0))
own(bpy.context.object,'SM_VIL_Tavern_DoorIronRing',metal)

# Chimney crosses the roof; the shaft starts at the hearth footprint.
box('SM_VIL_Tavern_ChimneyCore',(3.65,3.3,5.7),(1.1,1.08,10.5),stone[2],.04)
for r in range(16):
    for side in [-1,1]:
        stone_courses('SM_VIL_Tavern_ChimneyStone',3.65,3.3+side*.55,7+r*.27,1.12,.26,.17)
box('SM_VIL_Tavern_ChimneyCap',(3.65,3.3,11.36),(1.45,1.4,.24),stone[0],.04)
for x in [3.38,3.93]:box('SM_VIL_Tavern_ChimneyPot',(x,3.3,11.64),(.3,.4,.5),timber,.04)

# Balcony extends from upper joists and remains supported by porch columns.
box('SM_VIL_Tavern_BalconyFloor',(3.8,-7.8,4.02),(3.2,1.65,.20),wood)
for x in [2.3,3.05,3.8,4.55,5.3]:
    beam('SM_VIL_Tavern_BalconySpindle',(x,-8.6,4.14),(x,-8.6,5.02),.09,mat=wood)
beam('SM_VIL_Tavern_BalconyHandrail',(2.2,-8.6,5.06),(5.45,-8.6,5.06),.14,mat=wood)
beam('SM_VIL_Tavern_SignBracket',(-5.1,-7,5.72),(-7.25,-7,5.72),.17,mat=wood)
beam('SM_VIL_Tavern_SignBrace',(-5.1,-7,6.25),(-6.75,-7,5.72),.13)
for x in [-6.45,-7.05]:beam('SM_VIL_Tavern_SignChain',(x,-7,5.70),(x,-7,5.05),.035,mat=metal)
box('SM_VIL_Tavern_HangingSign',(-6.75,-7,4.68),(1.02,.18,.82),wood,.055)
for x in [-7.3,-6.2]:box('SM_VIL_Tavern_SignFrame',(x,-7,4.68),(.08,.24,.95),timber)

if REFINE:
    # An actual projecting cross gable replaces the buried first-pass dormer.
    for o in list(parts):
        if 'Dormer' in o.name:
            parts.remove(o);bpy.data.objects.remove(o,do_unlink=True)
    box('SM_VIL_Tavern_CrossGableWall',(0,-8.34,7.70),(3.8,.26,2.15),plaster)
    mesh('SM_VIL_Tavern_CrossGableTriangle',[(-1.9,-8.48,8.78),(1.9,-8.48,8.78),(0,-8.48,12.32 if SURFACE_REFINE else 11.63)],[(0,1,2)],plaster)
    roof('SM_VIL_Tavern_CrossGableRoof',0,-6.3,8.72,4.5,4.9,3.75 if SURFACE_REFINE else 3.06)
    for x in [-1.98,1.98]:
        beam('SM_VIL_Tavern_CrossGablePost',(x,-8.53,6.72),(x,-8.53,8.79),.22)
        beam('SM_VIL_Tavern_CrossGableRafter',(x,-8.53,8.79),(0,-8.53,12.45 if SURFACE_REFINE else 11.7),.22,mat=wood)
    beam('SM_VIL_Tavern_CrossGableTie',(-2.05,-8.53,8.79),(2.05,-8.53,8.79),.21)
    beam('SM_VIL_Tavern_CrossGableKing',(0,-8.53,8.79),(0,-8.53,12.48 if SURFACE_REFINE else 11.73),.18)
    window('SM_VIL_Tavern_CrossGableWindow',0,-8.57,7.76,1.25,1.45)
    for y in [-4,-.8,2.4,5.2]:
        before=len(parts)
        window('SM_VIL_Tavern_EastUpperWindow',0,0,5.31,1.15,1.5)
        for o in parts[before:]:
            px,py,pz=o.location
            o.location=(5.60-py,y+px,pz)
            o.rotation_euler.z+=math.pi/2
    # Offset delivery wing and visible structural roof support.
    box('SM_VIL_Tavern_DeliveryWingBase',(7.38,2.65,.39),(4.0,6.6,.78),stone[0],.05)
    box('SM_VIL_Tavern_DeliveryWingWall',(7.4,5.8,2.03),(3.9,.24,2.55),plaster)
    box('SM_VIL_Tavern_DeliveryWingSide',(9.35,2.65,2.03),(.25,6.6,2.55),plaster)
    roof('SM_VIL_Tavern_DeliveryWingRoof',7.4,2.65,3.36,4.6,7.25,1.72)
    for x in [5.55,9.32]:
        beam('SM_VIL_Tavern_DeliveryPost',(x,-.65,.8),(x,-.65,3.39),.22)
        beam('SM_VIL_Tavern_DeliveryBrace',(x,-.65,2.51),(x+.52,-.65,3.30),.15)
    beam('SM_VIL_Tavern_DeliveryFrontBeam',(5.35,-.65,3.32),(9.55,-.65,3.32),.23)
    # Curved door crown is geometric, rather than a painted pattern.
    for i in range(13):
        angle=math.pi*i/12
        x=.97*math.cos(angle);z=2.67+.97*math.sin(angle)
        o=box('SM_VIL_Tavern_DoorArchVoussoir',(x,-6.91,z),(.25,.32,.34),stone[(i+1)%4],.025)
        o.rotation_euler.y=math.pi/2-angle
    for x in [-.98,.98]:stone_courses('SM_VIL_Tavern_DoorPier',x,-6.88,.73,.32,1.94,.29)
    # Purposeful window planter timber; vegetation remains a subsequent task.
    for x in [-3.5,0,3.5]:
        box('SM_VIL_Tavern_PlanterFront',(x,-7.57,4.4),(1.48,.12,.26),wood)
        box('SM_VIL_Tavern_PlanterBottom',(x,-7.4,4.26),(1.48,.44,.10),wood)
        for dx in [-.7,.7]:box('SM_VIL_Tavern_PlanterEnd',(x+dx,-7.4,4.4),(.10,.44,.25),wood)

if HERO_REFINE:
    for o in list(parts):
        if o.name.startswith(('SM_VIL_Tavern_DoorPlank','SM_VIL_Tavern_DoorLintel')):
            parts.remove(o);bpy.data.objects.remove(o,do_unlink=True)
    for i in range(8):
        x=-.69+i*.197
        top=2.67+math.sqrt(max(0,.80**2-x*x))
        box('SM_VIL_Tavern_ArchedDoorPlank',(x,-6.74,(.78+top)/2),(.183,.12,top-.78),wood)
    # A curved timber frame follows the stone crown and carries the door leaf.
    verts=[];faces=[]
    for i in range(25):
        t=math.pi*i/24
        for radius,y in [(.78,-6.92),(.93,-6.92),(.78,-6.77),(.93,-6.77)]:
            verts.append((radius*math.cos(t),y,2.67+radius*math.sin(t)))
    for i in range(24):
        k=i*4
        faces.extend([(k,k+4,k+5,k+1),(k+2,k+3,k+7,k+6),(k,k+2,k+6,k+4),(k+1,k+5,k+7,k+3)])
    mesh('SM_VIL_Tavern_ArchedDoorFrame',verts,faces,timber)
    # Compress the long elevation using geometry coordinates, preserving unit scale.
    for o in parts:
        transform=o.matrix_world.copy()
        for v in o.data.vertices:
            p=transform@v.co;p.y*=.84
            v.co=transform.inverted()@p
        o.data.update()

if SURFACE_REFINE:
    # Metric UVs retain physical texel scale; timber length follows beam-local Z.
    for o in parts:
        uv=o.data.uv_layers.active or o.data.uv_layers.new(name='UV_Surface_Metric')
        for p in o.data.polygons:
            mat=o.data.materials[p.material_index]
            axis=max(range(3),key=lambda i:abs(p.normal[i]))
            for li in p.loop_indices:
                v=o.data.vertices[o.data.loops[li].vertex_index].co
                a,b=((v.y,v.z) if axis==0 else ((v.x,v.z) if axis==1 else (v.x,v.y)))
                uv.data[li].uv=(a*.7,b*(.35 if 'Timber' in mat.name else .7))
    for mat in list(bpy.data.materials):
        family=next((f for f in ['Timber','Stone','Plaster','Slate'] if f in mat.name),None)
        if not family:continue
        n,links=mat.node_tree.nodes,mat.node_tree.links
        bs=next(v for v in n if v.type=='BSDF_PRINCIPLED')
        maps={}
        for kind in ['Color','Normal','ORM']:
            tex=n.new('ShaderNodeTexImage')
            tex.image=bpy.data.images.load(str(ROOT/'Materials'/'v001'/('T_VIL_'+family+'_'+kind+'.png')),check_existing=True)
            if kind!='Color':tex.image.colorspace_settings.name='Non-Color'
            maps[kind]=tex
        tint=n.new('ShaderNodeMixRGB');tint.blend_type='MULTIPLY';tint.inputs[0].default_value=1
        tint.inputs[2].default_value=mat.diffuse_color
        links.new(maps['Color'].outputs['Color'],tint.inputs[1]);links.new(tint.outputs[0],bs.inputs['Base Color'])
        split=n.new('ShaderNodeSeparateXYZ');links.new(maps['ORM'].outputs['Color'],split.inputs[0])
        links.new(split.outputs['Y'],bs.inputs['Roughness'])
        flip=n.new('ShaderNodeVectorMath');flip.operation='MULTIPLY';flip.inputs[1].default_value=(1,-1,1)
        offset=n.new('ShaderNodeVectorMath');offset.operation='ADD';offset.inputs[1].default_value=(0,1,0)
        normal=n.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.55
        links.new(maps['Normal'].outputs['Color'],flip.inputs[0]);links.new(flip.outputs[0],offset.inputs[0])
        links.new(offset.outputs[0],normal.inputs['Color']);links.new(normal.outputs[0],bs.inputs['Normal'])

# Export a separate named mesh, while the master keeps its editable components.
bpy.ops.object.select_all(action='DESELECT')
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=parts[0]
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('SEKAI_VillageKit_'+VERSION+'.blend')))
bpy.ops.export_scene.fbx(filepath=str(OUT/('SM_VIL_Hero_Tavern_'+VERSION+'.fbx')),use_selection=True,
    object_types={'MESH'},axis_forward='-Y',axis_up='Z',apply_unit_scale=True,
    use_mesh_modifiers=True,bake_anim=False,path_mode='AUTO',mesh_smooth_type='FACE')
(OUT/'tavern_manifest.json').write_text(json.dumps({
    'status':'MODELED_NOT_VISUALLY_ACCEPTED','units':'metres','objects':len(parts),
    'hero_envelope_m':[16,18,12], 'door_clearance_m':[1.6,2.4],
    'materials':[m.name for m in bpy.data.materials],
    'known_gaps':['UE PBR texture baking','arched door and curved ridge refinement',
                  'window openings on upper storey','wood grain direction','weathering','hero reference review']
},indent=2),encoding='utf-8')

# Clay/material review is explicitly a Blender preview, never UE evidence.
bpy.ops.object.light_add(type='AREA',location=(-8,-12,16))
key=bpy.context.object;key.name='REVIEW_Key';key.data.energy=2600;key.data.shape='DISK';key.data.size=9
key.rotation_euler=(Vector((0,0,4))-key.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.light_add(type='AREA',location=(10,-1,13))
fill=bpy.context.object;fill.name='REVIEW_Fill';fill.data.energy=1900;fill.data.size=8
fill.rotation_euler=(Vector((0,0,4))-fill.location).to_track_quat('-Z','Y').to_euler()
world=bpy.data.worlds.new('REVIEW_World');scene.world=world;world.use_nodes=True
world.node_tree.nodes.get('Background').inputs[0].default_value=(.32,.39,.48,1)
world.node_tree.nodes.get('Background').inputs[1].default_value=.6
bpy.ops.mesh.primitive_plane_add(size=200)
floor=bpy.context.object;floor.name='REVIEW_Ground';floor.location.z=-.08;floor.data.materials.append(stone[1])
bpy.ops.object.camera_add(location=(21,-30,16))
camera=bpy.context.object;camera.name='REVIEW_Tavern_ThreeQuarter'
camera.rotation_euler=(Vector((0,-1,5))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.lens=47;scene.camera=camera
scene.render.engine='CYCLES';scene.cycles.samples=24
scene.cycles.use_denoising=False
scene.render.threads_mode='FIXED';scene.render.threads=6
scene.render.resolution_x=1400;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUT/('Tavern_Blender_Preview_'+VERSION+'.png'))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('SEKAI_Tavern_Review_'+VERSION+'.blend')))
bpy.ops.render.render(write_still=True)
print('SEKAI_TAVERN_DONE',len(parts),str(OUT))
