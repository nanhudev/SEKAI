"""Small shared mesh authoring helpers for original village assets, in metres."""
import bpy
import math
from mathutils import Vector

class MeshBuilder:
    def __init__(self):
        self.vertices=[];self.faces=[];self.material_indices=[];self.materials=[];self.vertex_indices={}
    def material(self,name,color=None):
        mat=bpy.data.materials.get(name) or bpy.data.materials.new(name)
        if color is not None:mat.diffuse_color=(*color,1)
        if mat not in self.materials:self.materials.append(mat)
        return self.materials.index(mat)
    def face(self,points,material):
        face=[]
        for point in points:
            key=tuple(point)
            index=self.vertex_indices.get(key)
            if index is None:
                index=len(self.vertices);self.vertex_indices[key]=index;self.vertices.append(key)
            face.append(index)
        self.faces.append(tuple(face));self.material_indices.append(material)
    def block(self,center,size,material,angle=0,bevel=.025):
        x,y,z=center;w,d,h=size;w/=2;d/=2;h/=2
        cut=min(bevel,w*.25,d*.25,h*.4)
        if cut==0:
            rings=[]
            for dz in [-h,h]:
                rings.append([Vector((x+px*math.cos(angle)-py*math.sin(angle),
                                      y+px*math.sin(angle)+py*math.cos(angle),z+dz))
                              for px,py in [(-w,-d),(w,-d),(w,d),(-w,d)]])
            self.face(list(reversed(rings[0])),material);self.face(rings[1],material)
            for i in range(4):
                j=(i+1)%4;self.face([rings[0][i],rings[0][j],rings[1][j],rings[1][i]],material)
            return
        outline=[(-w+cut,-d),(w-cut,-d),(w,-d+cut),(w,d-cut),
                 (w-cut,d),(-w+cut,d),(-w,d-cut),(-w,-d+cut)]
        rings=[]
        for inset,dz in [(cut,-h),(0,-h+cut),(0,h-cut),(cut,h)]:
            ring=[]
            for px,py in outline:
                px-=math.copysign(inset,px);py-=math.copysign(inset,py)
                ring.append(Vector((x+px*math.cos(angle)-py*math.sin(angle),
                                    y+px*math.sin(angle)+py*math.cos(angle),z+dz)))
            rings.append(ring)
        self.face(list(reversed(rings[0])),material);self.face(rings[-1],material)
        for a,b in zip(rings,rings[1:]):
            for i in range(8):
                j=(i+1)%8;self.face([a[i],a[j],b[j],b[i]],material)
    def tube(self,points,radii,material,sides=8):
        points=[Vector(p) for p in points];rings=[]
        for j,(p,r) in enumerate(zip(points,radii)):
            tangent=(points[min(j+1,len(points)-1)]-points[max(j-1,0)]).normalized()
            helper=Vector((0,1,0)) if abs(tangent.y)<.94 else Vector((1,0,0))
            u=tangent.cross(helper).normalized();v=tangent.cross(u).normalized()
            rings.append([p+r*(u*math.cos(i*math.tau/sides)+v*math.sin(i*math.tau/sides)) for i in range(sides)])
        self.face(list(reversed(rings[0])),material);self.face(rings[-1],material)
        for a,b in zip(rings,rings[1:]):
            for i in range(sides):
                j=(i+1)%sides;self.face([a[i],a[j],b[j],b[i]],material)
    def beam(self,a,b,width,material,depth=None):
        a,b=Vector(a),Vector(b);axis=(b-a).normalized()
        helper=Vector((0,1,0)) if abs(axis.y)<.94 else Vector((1,0,0))
        u=axis.cross(helper).normalized()*width*.5
        v=axis.cross(u).normalized()*(depth or width)*.5
        rings=[[p-u-v,p+u-v,p+u+v,p-u+v] for p in [a,b]]
        self.face(list(reversed(rings[0])),material);self.face(rings[-1],material)
        for i in range(4):
            j=(i+1)%4;self.face([rings[0][i],rings[0][j],rings[1][j],rings[1][i]],material)
    def build(self,name,transform=None):
        points=self.vertices if transform is None else [tuple(transform@Vector(p)) for p in self.vertices]
        mesh=bpy.data.meshes.new(name+'_Authored');mesh.from_pydata(points,[],self.faces);mesh.update()
        for mat in self.materials:mesh.materials.append(mat)
        for poly,index in zip(mesh.polygons,self.material_indices):poly.material_index=index
        # Metric face projections: avoids stretching stone/timber maps across a whole building.
        uv=mesh.uv_layers.new(name='UV_AuthoredMetric')
        for poly in mesh.polygons:
            normal=poly.normal;axis=max(range(3),key=lambda k:abs(normal[k]))
            for li in poly.loop_indices:
                p=mesh.vertices[mesh.loops[li].vertex_index].co
                uv.data[li].uv=((p.y,p.z) if axis==0 else (p.x,p.z) if axis==1 else (p.x,p.y))
        obj=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(obj)
        return obj

def export_mesh(obj,path):
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.export_scene.fbx(filepath=str(path),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
