"""Render a spatial review from the saved Mistvale art-map source data.

This is a Blender review image, not a UE beauty screenshot. It uses the exact
graded terrain mesh, parcel coordinates and imported building FBX geometry.
"""
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Matrix, Vector

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
sys.path.insert(0,str(HERE))
from grade_town_ground import graded_elevation, RELOCATIONS, dims, kind_mesh
from generate_heightmap import river_y

for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj,do_unlink=True)


def simple_material(name,color,rough=.85):
    m=bpy.data.materials.new(name)
    m.diffuse_color=(*color,1)
    m.use_nodes=True
    nodes=m.node_tree.nodes
    bs=nodes.get('Principled BSDF')
    if bs is None:
        nodes.clear()
        bs=nodes.new('ShaderNodeBsdfPrincipled')
        out=nodes.new('ShaderNodeOutputMaterial')
        m.node_tree.links.new(bs.outputs['BSDF'],out.inputs['Surface'])
    bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Roughness'].default_value=rough
    return m


def house_material(name,wall,roof):
    m=bpy.data.materials.new(name)
    m.use_nodes=True
    nodes=m.node_tree.nodes
    nodes.clear()
    out=nodes.new('ShaderNodeOutputMaterial')
    bs=nodes.new('ShaderNodeBsdfPrincipled')
    bs.inputs['Roughness'].default_value=.87
    geo=nodes.new('ShaderNodeNewGeometry')
    sep=nodes.new('ShaderNodeSeparateXYZ')
    ramp=nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position=.18
    ramp.color_ramp.elements[0].color=(*wall,1)
    ramp.color_ramp.elements[1].position=.48
    ramp.color_ramp.elements[1].color=(*roof,1)
    m.node_tree.links.new(geo.outputs['Normal'],sep.inputs['Vector'])
    m.node_tree.links.new(sep.outputs['Z'],ramp.inputs['Fac'])
    m.node_tree.links.new(ramp.outputs['Color'],bs.inputs['Base Color'])
    m.node_tree.links.new(bs.outputs['BSDF'],out.inputs['Surface'])
    return m


palette=[
    house_material('russet',(.72,.63,.47),(.38,.15,.105)),
    house_material('slate',(.67,.65,.52),(.12,.20,.26)),
    house_material('moss',(.66,.61,.46),(.22,.31,.19)),
    house_material('clay',(.78,.69,.54),(.47,.28,.16)),
]
stone=simple_material('stone',(.42,.40,.34))
road=simple_material('road',(.42,.33,.23))
water=simple_material('river',(.035,.24,.29),.22)

grass=bpy.data.materials.new('graded grass')
grass.use_nodes=True
n=grass.node_tree.nodes
n.clear()
out=n.new('ShaderNodeOutputMaterial')
bs=n.new('ShaderNodeBsdfPrincipled')
bs.inputs['Roughness'].default_value=.96
tex=n.new('ShaderNodeTexNoise')
tex.inputs['Scale'].default_value=.35
tex.inputs['Detail'].default_value=3
geo=n.new('ShaderNodeTexCoord')
ramp=n.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].color=(.23,.31,.16,1)
ramp.color_ramp.elements[1].color=(.38,.43,.22,1)
grass.node_tree.links.new(geo.outputs['Generated'],tex.inputs['Vector'])
grass.node_tree.links.new(tex.outputs['Fac'],ramp.inputs['Fac'])
grass.node_tree.links.new(ramp.outputs['Color'],bs.inputs['Base Color'])
grass.node_tree.links.new(bs.outputs['BSDF'],out.inputs['Surface'])

bpy.ops.wm.obj_import(filepath=str(HERE/'Mistvale_Terrain_Art_Proxy.obj'))
terrain=[o for o in bpy.context.selected_objects if o.type=='MESH'][0]
terrain.name='Saved UE art terrain geometry'
terrain.scale=(.01,.01,.01)
terrain.data.materials.clear()
terrain.data.materials.append(grass)


def quad_mesh(name,quads,material):
    verts=[]
    faces=[]
    for quad in quads:
        i=len(verts)
        verts.extend(quad)
        faces.append((i,i+1,i+2,i+3))
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(verts,[],faces)
    mesh.materials.append(material)
    mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(obj)
    return obj

river=[]
for x in range(-250,250,5):
    x1=x+5
    y0,y1=river_y(x),river_y(x1)
    width=10.5+4.5*max(0,min(1,(x+85)/155))
    river.append([(x,y0-width,2.93),(x1,y1-width,2.93),
                  (x1,y1+width,2.93),(x,y0+width,2.93)])
quad_mesh('river surface preview',river,water)

layout=json.loads((HERE/'blockout_layout.json').read_text(encoding='utf-8'))
road_quads=[]
for r in layout:
    if r['name'].rsplit('_',2)[0] not in {
            'GoldenRoute','LowerMarketLoop','MarketEastLoop',
            'RiversideStreet','UpperResidential','ChurchLane','DockTrack'}:
        continue
    x,y=r['x'],r['y']
    angle=math.radians(r['yaw'])
    ux,uy=math.cos(angle),math.sin(angle)
    vx,vy=-uy,ux
    length,width=r['sx'],r['sy']
    corners=[]
    for along,across in ((-1,-1),(1,-1),(1,1),(-1,1)):
        px=x+ux*length/2*along+vx*width/2*across
        py=y+uy*length/2*along+vy*width/2*across
        corners.append((px,py,graded_elevation(px,py)+.045))
    road_quads.append(corners)
quad_mesh('road surfaces preview',road_quads,road)

fbx_root=Path(r'C:\ProgramData\Epic\EpicGamesLauncher\VaultCache\FabLibrary\Slavic_Medieval_Town_Kit_-_Lite__Free_Starter_Pack_-b99a0776\fbx\fbx_extracted\FBX')
kind_file={
    'cubby':'EA03_Village_OutBuilding_Cubby_01d.fbx',
    'pent':'EA03_Village_OutBuilding_PentHouse_01a.fbx',
    'shed':'EA03_Village_OutBuilding_Shed_01a.fbx',
    'wide_shed':'EA03_Village_OutBuilding_Shed_03b.fbx',
    'admin':'EA03_Town_Building_Administrative _01a.fbx',
    'tower':'EA03_Village_Tover_01a.fbx',
    'woodroof':'EA03_Village_OutBuilding_WoodRoof_01b.fbx',
}
base_mesh={}
for kind,file in kind_file.items():
    before=set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(fbx_root/file))
    imported=set(bpy.data.objects)-before
    candidates=[o for o in imported if o.type=='MESH' and o.name.endswith('_LOD0')]
    if not candidates:
        raise RuntimeError('No LOD0 in '+file)
    base_mesh[kind]=candidates[0].data.copy()
    for obj in imported:
        bpy.data.objects.remove(obj,do_unlink=True)

placements=json.loads((HERE/'art_level_placements.json').read_text(encoding='utf-8'))
old={r['name']:r for r in layout}
foundations=[]
for row in placements:
    label,kind,scale=row['label'],row['kind'],row['scale']
    x,y=RELOCATIONS.get(label,row['position_m'])
    variant=sum(ord(c) for c in label)%4
    data=base_mesh[kind].copy()
    data.materials.clear()
    data.materials.append(palette[variant])
    obj=bpy.data.objects.new(label,data)
    bpy.context.collection.objects.link(obj)
    yaw=old.get(label,{}).get('yaw',0)
    if label in ('HERO_Church_Nave','HERO_Blacksmith','HERO_DockWarehouse'):
        yaw=90
    obj.rotation_euler=(Matrix.Rotation(math.radians(yaw),4,'Z') @
                        Matrix.Rotation(math.pi/2,4,'X')).to_euler()
    obj.scale=(scale,scale,scale)
    obj.location.x=x
    obj.location.y=y
    w,d,_=dims[kind_mesh[kind]]
    half=max(w,d)*scale/2*.8
    grounds=[graded_elevation(x,y)]
    for sx in (-1,1):
        for sy in (-1,1):
            grounds.append(graded_elevation(x+sx*half,y+sy*half))
    bottom=max(grounds)+.035
    rotated=Matrix.Rotation(math.radians(yaw),4,'Z') @ Matrix.Rotation(math.pi/2,4,'X')
    local_min=min((rotated @ Vector(v)).z for v in obj.bound_box)
    obj.location.z=bottom-local_min*scale
    if label in ('UpperWest_House_01','Riverside_House_05'):
        bpy.context.view_layer.update()
        print('PREVIEW_HEIGHT',label,'ground',round(graded_elevation(x,y),2),
              'floor',round(bottom,2),'mesh_min',round(min((obj.matrix_world @ Vector(v)).z for v in obj.bound_box),2),
              'mesh_max',round(max((obj.matrix_world @ Vector(v)).z for v in obj.bound_box),2))
    if kind!='woodroof':
        hx=w*scale*.455
        hy=d*scale*.455
        ztop=bottom
        zbase=bottom-.9
        xx=(x-hx,x+hx)
        yy=(y-hy,y+hy)
        # Visible top and four sides of the stone foundation.
        foundations.extend([
            [(xx[0],yy[0],ztop),(xx[1],yy[0],ztop),(xx[1],yy[1],ztop),(xx[0],yy[1],ztop)],
            [(xx[0],yy[0],zbase),(xx[1],yy[0],zbase),(xx[1],yy[0],ztop),(xx[0],yy[0],ztop)],
            [(xx[1],yy[0],zbase),(xx[1],yy[1],zbase),(xx[1],yy[1],ztop),(xx[1],yy[0],ztop)],
            [(xx[1],yy[1],zbase),(xx[0],yy[1],zbase),(xx[0],yy[1],ztop),(xx[1],yy[1],ztop)],
            [(xx[0],yy[1],zbase),(xx[0],yy[0],zbase),(xx[0],yy[0],ztop),(xx[0],yy[1],ztop)],
        ])
quad_mesh('stone foundations preview',foundations,stone)

world=bpy.context.scene.world
world.use_nodes=True
world.node_tree.nodes['Background'].inputs['Color'].default_value=(.57,.70,.80,1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value=.8
bpy.ops.object.light_add(type='SUN',location=(-120,-150,250))
sun=bpy.context.object
sun.rotation_euler=(math.radians(37),math.radians(-25),math.radians(-30))
sun.data.energy=2.2
sun.data.angle=math.radians(6)

def camera_render(name,location,target,scale):
    bpy.ops.object.camera_add(location=location)
    cam=bpy.context.object
    cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO'
    cam.data.ortho_scale=scale
    bpy.context.scene.camera=cam
    scene=bpy.context.scene
    scene.render.filepath=str(ROOT/'Review'/name)
    bpy.ops.render.render(write_still=True)
    print('GROUND_PREVIEW',scene.render.filepath)
    bpy.data.objects.remove(cam,do_unlink=True)

scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE'
scene.eevee.taa_render_samples=32
scene.render.resolution_x=1400
scene.render.resolution_y=900
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX'
scene.camera=None
camera_render('ground_aerial_preview.png',(0,60,520),(0,60,0),620)
camera_render('riverside_ground_preview.png',(-205,-250,115),(-100,-120,6),230)
