"""Model the principal three-arch Mistvale river bridge in metres."""
import bpy
import math
from pathlib import Path

root = Path(__file__).resolve().parents[1]
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb,1)
    m.use_nodes = True
    node = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    node.inputs["Base Color"].default_value = (*rgb,1)
    node.inputs["Roughness"].default_value = .91
    return m


limestone = mat("MV_Bridge_CreamLimestone", (.57,.53,.44))
archstone = mat("MV_Bridge_ArchVoussoir", (.68,.62,.51))
wetstone = mat("MV_Bridge_WetStone", (.24,.27,.25))
coping = mat("MV_Bridge_Coping", (.71,.66,.53))
paving = mat("MV_Bridge_Paving", (.44,.44,.40))
all_objects = []


def box(name, loc, dims, material, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj=bpy.context.object
    obj.name=name
    obj.dimensions=dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    if bevel:
        mod=obj.modifiers.new("Soft stone edge","BEVEL")
        mod.width=bevel
        mod.segments=2
        obj.modifiers.new("Weighted normals","WEIGHTED_NORMAL")
    all_objects.append(obj)
    return obj


def extruded_profile(name, path, x0, x1, material):
    n=len(path)
    verts=[(x0,y,z) for y,z in path]+[(x1,y,z) for y,z in path]
    faces=[]
    # Side faces are triangulated as a fan by Blender's mesh tessellator.
    faces.append(tuple(range(n)))
    faces.append(tuple(range(2*n-1,n-1,-1)))
    for i in range(n):
        j=(i+1)%n
        faces.append((i,j,j+n,i+n))
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(verts,[],faces)
    mesh.materials.append(material)
    mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(obj)
    all_objects.append(obj)
    return obj


# Traversable stone deck; its top is 6.3 m above the original world datum.
box("Bridge_CrownDeck",(0,0,6.02),(7.4,37.2,.56),limestone,.09)
box("Bridge_PavedRoad",(0,0,6.33),(5.75,36.6,.12),paving,.035)
for y in range(-16,17,4):
    box("Bridge_RoadJoint",(0,y,6.404),(5.68,.07,.035),wetstone,.01)

# Three readable arch openings face the river flow. Each opening has two
# spandrel faces and a continuous stone barrel vault between them.
for arch_idx,(lo,hi) in enumerate(((-18,-6),(-6,6),(6,18))):
    centre=(lo+hi)/2
    radius=(hi-lo)/2
    curve=[]
    for i in range(17):
        y=lo+(hi-lo)*i/16
        u=(y-centre)/radius
        z=3.03+2.25*math.sqrt(max(0,1-u*u))
        curve.append((y,z))
    profile=[(lo,5.73),(hi,5.73)]+list(reversed(curve))
    for side in (-1,1):
        xa,xb=(-3.7,-2.72) if side<0 else (2.72,3.7)
        extruded_profile(f"Bridge_ArchSpandrel_{arch_idx}_{side}",profile,xa,xb,limestone)
        # A ring follows the curve and reads as individually set arch stone.
        for j in range(16):
            ya,za=curve[j]
            yb,zb=curve[j+1]
            length=math.hypot(yb-ya,zb-za)
            rib=box(f"Bridge_Voussoir_{arch_idx}_{side}_{j}",
                    ((xa+xb)/2,(ya+yb)/2,(za+zb)/2+.12),
                    (1.22,length+.08,.42),archstone,.045)
            rib.rotation_euler[0]=math.atan2(zb-za,yb-ya)
    for j in range(16):
        ya,za=curve[j]
        yb,zb=curve[j+1]
        vault=box(f"Bridge_Vault_{arch_idx}_{j}",
                  (0,(ya+yb)/2,(za+zb)/2+.24),
                  (5.5,math.hypot(yb-ya,zb-za)+.06,.42),limestone,.025)
        vault.rotation_euler[0]=math.atan2(zb-za,yb-ya)

# Pier noses split current and expose a dark wet band at water level.
for y in (-18,-6,6,18):
    box("Bridge_Pier",(0,y,3.18),(7.45,1.45,5.25),limestone,.12)
    box("Bridge_PierWetBand",(0,y,2.84),(7.58,1.56,1.15),wetstone,.06)
    for side in (-1,1):
        nose=box("Bridge_Cutwater",(side*4.05,y,3.1),(.95,1.15,2.1),limestone,.08)
        nose.rotation_euler[2]=math.pi/4

# Parapets contain openings and thick caps, avoiding a featureless solid rail.
for side in (-1,1):
    x=side*3.4
    box("Bridge_RailPlinth",(x,0,6.58),(.65,37.3,.5),limestone,.05)
    box("Bridge_RailCap",(x,0,7.55),(.85,37.7,.28),coping,.10)
    for y in range(-18,19,3):
        box("Bridge_Baluster",(x,y,7.10),(.63,.43,1.04),limestone,.045)
    for y in (-18.7,18.7):
        box("Bridge_EndPier",(x,y,7.12),(1.2,1.2,1.65),archstone,.09)
        box("Bridge_EndCoping",(x,y,8.02),(1.45,1.45,.31),coping,.07)

bpy.ops.object.select_all(action="DESELECT")
for obj in all_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active=all_objects[0]
bpy.ops.object.convert(target="MESH")
bpy.ops.object.join()
bpy.context.object.name="SM_Mistvale_StoneBridge"
out=root/"Source"/"SM_Mistvale_StoneBridge.fbx"
bpy.ops.export_scene.fbx(filepath=str(out),use_selection=True,apply_unit_scale=True,
                         mesh_smooth_type="FACE",add_leaf_bones=False)
bpy.ops.wm.save_as_mainfile(filepath=str(root/"Source"/"Mistvale_StoneBridge.blend"))
print("BRIDGE_EXPORT",out,out.stat().st_size,"VERTS",len(bpy.context.object.data.vertices))
