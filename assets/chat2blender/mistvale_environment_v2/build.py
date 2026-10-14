"""Mistvale authored foliage and rock kit. Run with Blender --background --python build.py -- --version=1|2."""
import bpy
import math
import random
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "assets_source" / "environment" / "mistvale" / "vegetation_v2"
VERSION = 3 if "--version=3" in sys.argv else (2 if "--version=2" in sys.argv else 1)
OUT = ROOT / "godot" / "models" / "environment" / "mistvale" / f"vegetation_v{VERSION}"
SOURCE.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
random.seed(1927)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def painted_image(name, rgb):
    size=128
    img=bpy.data.images.new(name+"_paint", width=size, height=size)
    kind="bark" if "bark" in name else ("leaf" if "leaf" in name else ("grass" if "grass" in name else "stone"))
    seed=sum((i+1)*ord(c) for i,c in enumerate(name))
    pixels=[]
    for y in range(size):
        for x in range(size):
            u=x/size;v=y/size
            broad=.55*math.sin(u*8.0+seed*.01)+.45*math.cos(v*9.0-u*3.0)
            fleck=math.sin(u*22.0+v*6.0+seed*.03)*math.cos(v*19.0-u*7.0)
            if kind=="bark":
                marks=math.sin(u*63.0+math.sin(v*17.0)*1.3)+.35*math.sin(u*121.0-v*5.0)
                f=.86+.11*broad+.10*marks
            elif kind=="leaf":
                marks=max(0.0, math.sin(u*22.0+v*7.0)*math.cos(v*19.0-u*5.0))
                f=.97+.075*broad+.09*marks+.018*fleck
            elif kind=="grass":
                f=.72+.28*v+.075*math.sin(u*43.0+v*12.0)
            else:
                f=.96+.07*broad+.035*fleck
            # PNGs are decoded from sRGB by Blender / glTF; encode the intended
            # linear material color here or every V3 asset becomes too dark.
            pixels.extend([min(1.0,max(0.0,rgb[0]*f))**(1/2.2),
                           min(1.0,max(0.0,rgb[1]*f))**(1/2.2),
                           min(1.0,max(0.0,rgb[2]*f))**(1/2.2),1.0])
    img.pixels[:]=pixels
    path=SOURCE/"textures"/(name+"_paint.png")
    path.parent.mkdir(parents=True,exist_ok=True)
    img.filepath_raw=str(path)
    img.file_format='PNG'
    img.save()
    return img

def mat(name, rgb, rough=0.88):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    m.use_backface_culling = False
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = rough
    if VERSION>=3:
        tex=m.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image=painted_image(name,rgb)
        m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
    return m

BARK = mat("warm_bark", (0.28, 0.205, 0.145))
BARK_RIVER = mat("river_bark", (0.36, 0.29, 0.205))
LEAF = [mat("broadleaf_light", (0.27, 0.46, 0.18)), mat("broadleaf_mid", (0.19, 0.36, 0.15)), mat("broadleaf_shadow", (0.13, 0.27, 0.13))]
RIVER_LEAF = [mat("river_leaf_light", (0.27, 0.43, 0.25)), mat("river_leaf_mid", (0.19, 0.34, 0.21)), mat("river_leaf_shadow", (0.13, 0.26, 0.17))]
PINE_LEAF = [mat("mountain_leaf_light", (0.040, 0.115, 0.078)), mat("mountain_leaf_mid", (0.030, 0.086, 0.065)), mat("mountain_leaf_shadow", (0.022, 0.061, 0.050))]
GRASS = [mat("grass_fresh", (0.24, 0.40, 0.15)), mat("grass_dark", (0.16, 0.31, 0.13)), mat("grass_dry", (0.40, 0.37, 0.19)), mat("grass_river", (0.20, 0.36, 0.23))]
ROCK = [mat("rock_warm", (0.43, 0.425, 0.40)), mat("rock_mid", (0.35, 0.36, 0.36)), mat("rock_shadow", (0.29, 0.32, 0.32))]

assets = {}

def tube(name, points, radii, material, sides=8):
    verts, faces = [], []
    for i, point in enumerate(points):
        p = Vector(point)
        tangent = Vector(points[min(i+1, len(points)-1)]) - Vector(points[max(i-1,0)])
        tangent.normalize()
        u = tangent.cross(Vector((0,0,1)))
        if u.length < 0.01: u = Vector((1,0,0))
        u.normalize()
        v = tangent.cross(u).normalized()
        for j in range(sides):
            a = j * math.tau/sides
            q = p + (u*math.cos(a)+v*math.sin(a))*radii[i]
            verts.append(q)
    for i in range(len(points)-1):
        for j in range(sides):
            n = (j+1)%sides
            faces.append((i*sides+j,i*sides+n,(i+1)*sides+n,(i+1)*sides+j))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((len(points)-1)*sides+j for j in range(sides)))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    uv=mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        wraps=any(mesh.loops[li].vertex_index%sides==sides-1 for li in poly.loop_indices)
        for li in poly.loop_indices:
            vi=mesh.loops[li].vertex_index;j=vi%sides;k=vi//sides
            uv.data[li].uv=(1.0 if wraps and j==0 else j/sides,k/max(1,len(points)-1))
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob);ob.data.materials.append(material)
    return ob

def crown(name, center, radii, material, seed, profile="round"):
    rng=random.Random(seed)
    seg=11 if VERSION>=2 else 10
    levels=6
    verts=[]; faces=[]
    phase=rng.uniform(0,6.28)
    for k in range(levels+1):
        theta=math.pi*k/levels
        rr=max(0.012,math.sin(theta))
        if VERSION>=2 and profile=="round":
            rr=[.18,.55,.89,1.12,1.04,.73,.17][k]
        if profile=="spire": rr*=0.88+0.42*math.cos(theta)
        for j in range(seg):
            a=math.tau*j/seg
            scallop=1+0.17*math.sin(3*a+phase)+0.11*math.sin(5*a-phase*0.6)
            if VERSION>=2: scallop+=0.09*math.sin(7*a+theta*2+phase)
            x=center[0]+math.cos(a)*radii[0]*rr*scallop+0.10*math.sin(theta*2+phase)
            y=center[1]+math.cos(theta)*radii[2]*(.50 if VERSION>=2 and profile=="round" else 1.0)+0.12*math.cos(4*a+phase)*rr
            z=center[2]+math.sin(a)*radii[1]*rr*scallop
            verts.append((x,y,z))
    for k in range(levels):
        for j in range(seg):
            n=(j+1)%seg; a=k*seg+j; b=k*seg+n; c=(k+1)*seg+n; d=(k+1)*seg+j
            faces.append((a,b,c,d))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    uv=mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            co=mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv=((co.x-center[0])/(2.8*radii[0])+.5,(co.z-center[2])/(2.8*radii[1])+.5)
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob);ob.data.materials.append(material)
    for p in mesh.polygons:p.use_smooth=(VERSION==1)
    return ob

def canopy_fringe(name, center, radii, material, seed, count=18):
    rng=random.Random(seed);verts=[];faces=[]
    for i in range(count):
        a=math.tau*i/count+rng.uniform(-.13,.13)
        r=rng.uniform(.74,.95)
        root=Vector((center[0]+math.cos(a)*radii[0]*r,
                     center[1]+rng.uniform(-.12,.23),
                     center[2]+math.sin(a)*radii[1]*r))
        tangent=Vector((-math.sin(a),0,math.cos(a)))
        width=rng.uniform(.17,.30)
        reach=rng.uniform(.30,.55)
        tip=root+Vector((math.cos(a)*reach,rng.uniform(-.16,.24),math.sin(a)*reach))
        mid=root.lerp(tip,.58)+Vector((0,.10,0))
        j=len(verts)
        verts.extend([root,mid+tangent*width,tip,mid-tangent*width])
        faces.extend([(j,j+1,j+2),(j,j+2,j+3)])
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    uv=mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            vi=mesh.loops[li].vertex_index%4
            uv.data[li].uv=((.5,0.0,.5,1.0)[vi],(0.0,.50,1.0,.50)[vi])
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob);mesh.materials.append(material)
    return ob

def canopy_group(name, center, radii, palette, seed):
    parts=[crown(name+"_body",center,radii,palette[seed%3],seed)]
    if VERSION>=3:
        rng=random.Random(seed+71)
        for k in range(5):
            a=math.tau*k/5+rng.uniform(-.24,.24)
            c=(center[0]+math.cos(a)*radii[0]*.72,
               center[1]+rng.uniform(-.14,.23),
               center[2]+math.sin(a)*radii[1]*.72)
            r=(radii[0]*rng.uniform(.33,.43),radii[1]*rng.uniform(.32,.42),radii[2]*.34)
            parts.append(crown(name+f"_lobe{k}",c,r,palette[(seed+k+1)%3],seed+k+51))
        parts.append(canopy_fringe(name+"_fringe",center,radii,palette[(seed+1)%3],seed+343))
    return parts

def pine_tier(name, center, radius, height, material, seed):
    rng=random.Random(seed);seg=12;verts=[];faces=[]
    for level,(width,rise) in enumerate(((.72,0.0),(1.0,.18),(.76,.48),(.06,1.0))):
        for j in range(seg):
            a=math.tau*j/seg
            tooth=1.0+(.12 if j%3==0 else -.08)+rng.uniform(-.035,.035)
            verts.append((center[0]+math.cos(a)*radius*width*tooth,
                          center[1]+height*rise+(.12 if j%3==0 else -.05),
                          center[2]+math.sin(a)*radius*width*tooth))
    for level in range(3):
        for j in range(seg):
            k=(j+1)%seg;a=level*seg+j;b=level*seg+k;c=(level+1)*seg+k;d=(level+1)*seg+j
            faces.append((a,b,c,d))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    uv=mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            vi=mesh.loops[li].vertex_index
            uv.data[li].uv=((vi%seg)/seg,(vi//seg)/3)
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob);mesh.materials.append(material)
    return ob

def join(name, parts):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in parts: ob.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join()
    ob=parts[0];ob.name=name;ob.data.name=name+"_mesh";assets[name]=ob
    if VERSION>=3 and len(ob.data.materials)>1:
        atlas_single_material(ob,name)
    return ob

def atlas_single_material(ob, name):
    mats=list(ob.data.materials)
    size=128;count=len(mats)
    atlas=bpy.data.images.new(name+"_atlas",width=size*count,height=size)
    dst=[0.0]*(size*size*count*4)
    for tile,m in enumerate(mats):
        images=[n.image for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image]
        if not images: continue
        src=list(images[0].pixels[:])
        for y in range(size):
            for x in range(size):
                di=(y*size*count+tile*size+x)*4
                si=(y*size+x)*4
                dst[di:di+4]=src[si:si+4]
    atlas.pixels[:]=dst
    path=SOURCE/"textures"/(name+"_atlas.png")
    atlas.filepath_raw=str(path);atlas.file_format='PNG';atlas.save()
    uv=ob.data.uv_layers.active
    for poly in ob.data.polygons:
        tile=poly.material_index
        for li in poly.loop_indices:
            u,v=uv.data[li].uv
            uv.data[li].uv=((min(.999,max(.001,u))+tile)/count,min(.999,max(.001,v)))
        poly.material_index=0
    ob.data.materials.clear()
    m=bpy.data.materials.new(name+"_atlas_mat")
    m.use_nodes=True;m.use_backface_culling=False
    bsdf=m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value=.91
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=atlas
    m.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
    ob.data.materials.append(m)

def bamboo_fan(name, center, material, seed):
    rng=random.Random(seed);verts=[];faces=[]
    for k in range(8):
        a=k*math.tau/8+rng.uniform(-.16,.16)
        length=rng.uniform(.80,1.38);w=rng.uniform(.08,.14)
        start=Vector(center)+Vector((0,-.12,0))
        mid=start+Vector((math.cos(a)*length*.52,rng.uniform(.10,.27),math.sin(a)*length*.52))
        tip=start+Vector((math.cos(a)*length,rng.uniform(-.15,.18),math.sin(a)*length))
        v=len(verts)
        verts.extend([start,mid+Vector((-math.sin(a)*w,0,math.cos(a)*w)),mid-Vector((-math.sin(a)*w,0,math.cos(a)*w)),tip])
        faces.extend([(v,v+1,v+3),(v,v+3,v+2)])
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    uv=mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            co=mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv=((co.x-center[0])*.25+.5,(co.z-center[2])*.25+.5)
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob);mesh.materials.append(material)
    return ob

def tree(name, style, variant):
    rng=random.Random(400+variant*37+{"broad":0,"river":100,"pine":200,"bamboo":300}[style])
    parts=[]
    if style=="broad":
        h=[4.1,4.8,3.8][variant]
        drift=[(0.3,0.15),(-0.7,0.25),(0.65,-0.4)][variant]
        trunk=[(0,0,0),(0.05,h*.35,0),(drift[0]*.55,h*.72,drift[1]*.55),(drift[0],h,drift[1])]
        parts.append(tube(name+"_trunk",trunk,[.43,.34,.23,.15],BARK))
        masses=[((drift[0],h+1.15,drift[1]),(1.78 if VERSION>=2 else 2.0,1.55,1.45)),
                ((drift[0]-(2.45 if VERSION>=2 else 1.95),h+.16,drift[1]+.45),(1.42,1.30,1.08)),
                ((drift[0]+(2.15 if VERSION>=2 else 1.63),h+.62,drift[1]-.52),(1.23,1.12,1.13)),
                ((drift[0]+1.22 if VERSION>=2 else drift[0]+.48,h+2.37,drift[1]-.65),(1.02,.96,.83))]
        if variant==1: masses[1]=((drift[0]-2.35,h+.05,drift[1]+.18),(1.65,1.40,1.05))
        if variant==2: masses[2]=((drift[0]+2.0,h+.1,drift[1]-.6),(1.43,1.12,1.02))
        fork=Vector(trunk[-2])
        for j,(cen,rad) in enumerate(masses[:3]):
            c=Vector(cen);start=fork if j else Vector(trunk[-1])
            parts.append(tube(name+f"_branch{j}",[start,start.lerp(c,.54),c], [.17,.125,.06],BARK,6))
        for j,(cen,rad) in enumerate(masses):parts.extend(canopy_group(name+f"_mass{j}",cen,rad,LEAF,rng.randint(0,9999)))
    elif style=="river":
        h=[5.25,5.75][variant]; lean=[1.6,2.0][variant]
        trunk=[(0,0,0),(0,h*.35,.16),(0,h*.70,lean*.52),(.25,h,lean)]
        parts.append(tube(name+"_trunk",trunk,[.34,.28,.20,.13],BARK_RIVER))
        masses=[((.25,h+.65,lean+.15),(1.05,1.18,1.08)),
                ((-1.55 if VERSION>=2 else -1.0,h+.18,lean+1.20),(1.22,1.29,.98)),
                ((1.20 if VERSION>=2 else .85,h+1.45,lean+1.42),(1.00,1.11,1.06)),
                ((-.48 if VERSION>=2 else .0,h+2.58,lean+.38),(.72,.78,.76))]
        for j,(cen,rad) in enumerate(masses[:3]):
            c=Vector(cen);s=Vector(trunk[2] if j!=2 else trunk[3])
            parts.append(tube(name+f"_branch{j}",[s,s.lerp(c,.58),c],[.13,.09,.04],BARK_RIVER,6))
        for j,(cen,rad) in enumerate(masses):parts.extend(canopy_group(name+f"_mass{j}",cen,rad,RIVER_LEAF,rng.randint(0,9999)))
    elif style=="pine":
        h=[7.8,9.0][variant]
        trunk=[(0,0,0),(.08,h*.35,0),(.18,h*.7,-.12),(.27,h,-.19)]
        parts.append(tube(name+"_trunk",trunk,[.32,.25,.15,.045],BARK))
        for j in range(4):
            side=-1 if j%2 else 1; yy=2.8+j*1.18; out=side*(1.15-j*.15)
            start=Vector((.08,yy-.15,0));end=Vector((out,yy+.45,(-1)**j*.30))
            parts.append(tube(name+f"_branch{j}",[start,start.lerp(end,.58),end],[.13,.10,.04],BARK,6))
            if VERSION>=3:
                parts.append(pine_tier(name+f"_mass{j}",tuple(end),1.42-j*.14,1.35,PINE_LEAF[j%3],rng.randint(0,9999)))
            else:
                parts.append(crown(name+f"_mass{j}",tuple(end),(0.9-j*.09,.64,.92),PINE_LEAF[j%3],rng.randint(0,9999),"spire"))
        if VERSION>=3:
            parts.append(pine_tier(name+"_top",(.27,h-1.0,-.19),.68,1.55,PINE_LEAF[1],rng.randint(0,9999)))
        else:
            parts.append(crown(name+"_top",(.27,h-.55,-.19),(.62,.57,1.45),PINE_LEAF[1],rng.randint(0,9999),"spire"))
    else:
        for j in range(5+variant):
            a=j*2.4;off=(math.cos(a)*(.28+j*.03),math.sin(a)*(.28+j*.03));h=6.2+j*.37
            parts.append(tube(name+f"_cane{j}",[(off[0],0,off[1]),(off[0]+.05,h*.6,off[1]),(off[0]+.20,h,off[1]+.1)],[.08,.06,.025],BARK_RIVER,5))
            for k in range(3 if VERSION>=3 else 2):
                if VERSION>=2:
                    parts.append(bamboo_fan(name+f"_fan{j}_{k}",(off[0]+(.24 if k%2 else -.20),h-.24-k*(.78 if VERSION>=3 else .48),off[1]),LEAF[(j+k)%3],rng.randint(0,9999)))
                else:
                    parts.append(crown(name+f"_leaf{j}_{k}",(off[0]+(.32 if k else -.30),h-.28-k*.52,off[1]),(.55,.45,.42),LEAF[(j+k)%3],rng.randint(0,9999)))
    return join(name,parts)

def grass_clump(name, count, height, width, material, seed):
    rng=random.Random(seed);verts=[];faces=[]
    for i in range(count):
        a=math.tau*i/count+rng.uniform(-.14,.14);r=rng.uniform(.02,.24)
        x,z=math.cos(a)*r,math.sin(a)*r
        hh=height*rng.uniform(.70,1.2);bend=hh*rng.uniform(.16,.38)
        w=width*rng.uniform(.7,1.3);v=len(verts)
        verts.extend([(x-math.sin(a)*w,0,z+math.cos(a)*w),
                      (x+math.sin(a)*w,0,z-math.cos(a)*w),
                      (x+math.cos(a)*bend*.55,hh*.55,z+math.sin(a)*bend*.55),
                      (x+math.cos(a)*bend,hh,z+math.sin(a)*bend)])
        faces.extend([(v,v+1,v+2),(v+1,v+3,v+2)])
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    uv=mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            vi=mesh.loops[li].vertex_index
            uv.data[li].uv=((0.0,1.0,0.36,0.7)[vi%4],(0.0,0.0,.52,1.0)[vi%4])
    ob=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(ob);mesh.materials.append(material)
    assets[name]=ob;return ob

def rock_group(name, scale, seed):
    rng=random.Random(seed);parts=[]
    for i in range(3):
        ang=i*2.2;off=(math.cos(ang)*scale*.23,math.sin(ang)*scale*.18)
        r=scale*[.52,.37,.31][i];h=scale*[.65,.43,.38][i]
        verts=[];faces=[];sides=7
        for lev,(radius,y) in enumerate(((.72,-.12),(1,.30),(.79,h))):
            for j in range(sides):
                a=j*math.tau/sides;bias=1+.13*math.sin(j*2.7+i)
                verts.append((off[0]+math.cos(a)*r*radius*bias, y, off[1]+math.sin(a)*r*radius*bias))
        for lev in range(2):
            for j in range(sides):faces.append((lev*sides+j,lev*sides+(j+1)%sides,(lev+1)*sides+(j+1)%sides,(lev+1)*sides+j))
        faces.append(tuple(range(2*sides,3*sides)))
        mesh=bpy.data.meshes.new(name+f"_{i}");mesh.from_pydata(verts,[],faces);mesh.update()
        uv=mesh.uv_layers.new(name="UVMap")
        for poly in mesh.polygons:
            for li in poly.loop_indices:
                co=mesh.vertices[mesh.loops[li].vertex_index].co
                uv.data[li].uv=(co.x/max(1.0,scale)+.5,co.z/max(1.0,scale)+.5)
        ob=bpy.data.objects.new(name+f"_{i}",mesh);bpy.context.collection.objects.link(ob);mesh.materials.append(ROCK[i]);parts.append(ob)
    return join(name,parts)

for i in range(3):tree(f"Broadleaf_{chr(65+i)}","broad",i)
for i in range(2):tree(f"RiverTree_{chr(65+i)}","river",i)
for i in range(2):tree(f"MountainTree_{chr(65+i)}","pine",i)
for i in range(2):tree(f"Bamboo_{chr(65+i)}","bamboo",i)
grass_clump("ShortGrass_A",11,.48,.045,GRASS[0],11)
grass_clump("ShortGrass_B",15,.55,.038,GRASS[1],12)
grass_clump("TallGrass_A",13,1.10,.055,GRASS[0],13)
grass_clump("TallGrass_B",17,1.24,.045,GRASS[1],14)
grass_clump("RiverGrass_A",14,1.45,.041,GRASS[3],15)
grass_clump("DryGrass_A",12,.74,.046,GRASS[2],16)
rock_group("HeroRock_A",3.2,21)
rock_group("HeroRock_B",5.0,22)

if VERSION>=2:
    for name,ob in assets.items():
        bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
        bpy.ops.export_scene.gltf(filepath=str(OUT/(name+".glb")), export_format='GLB', use_selection=True, export_apply=True)

# Contact sheet: tree silhouettes get their own readable 3 x 3 frame.
for j,(name,ob) in enumerate(assets.items()):
    if j<9:
        col=j%3;row=j//3;ob.location=(col*9,row*10,0)
    else: ob.hide_render=True
bpy.ops.mesh.primitive_plane_add(size=200,location=(9,10,-.18))
bpy.context.object.name="StudioGround";bpy.context.object.data.materials.append(mat("studio",(.48,.50,.49)))
world=bpy.context.scene.world;world.use_nodes=True
world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.62,.68,.70,1)
world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.65
bpy.ops.object.light_add(type='AREA',location=(-12,-16,28));bpy.context.object.data.energy=3800;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=20
bpy.ops.object.light_add(type='AREA',location=(24,24,18));bpy.context.object.data.energy=1900;bpy.context.object.data.size=18
bpy.ops.object.camera_add(location=(10,-28,21));cam=bpy.context.object
direction=Vector((9,10,3.3))-cam.location;cam.rotation_euler=direction.to_track_quat('-Z','Y').to_euler()
bpy.context.scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=31
scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=1600;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(SOURCE/f"trees_contact_v{VERSION}.png")
scene.view_settings.view_transform='Standard'
scene.view_settings.look='Medium High Contrast'
bpy.ops.render.render(write_still=True)
for j,(name,ob) in enumerate(list(assets.items())[9:]):
    ob.hide_render=False;ob.location=((j%4)*5,(j//4)*6,0)
    ob.scale=(3,3,3) if "Grass" in name else (1,1,1)
for name,ob in list(assets.items())[:9]:ob.hide_render=True
cam.location=(8,-24,18);cam.rotation_euler=(Vector((7,4,1))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=25
scene.render.filepath=str(SOURCE/f"ground_contact_v{VERSION}.png")
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/f"mistvale_environment_v{VERSION}.blend"))
print(f"BUILT V{VERSION}: {len(assets)} assets -> {OUT}")
