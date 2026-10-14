import bpy,json,math
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
HERE=Path(__file__).parent
exec(compile((HERE/'measure_exported_ground.py').read_text(),'ground','exec'))
def bvh(name):
 o=bpy.data.objects[name]
 return BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[list(p.vertices) for p in o.data.polygons])
bridge=bvh('MainStoneBridge_DECK')
def height(t,x,y):
 p,_,_,_=t.ray_cast(Vector((x,-y,100)),Vector((0,0,-1)),200)
 if p is None:raise RuntimeError(str((x,y)))
 return p.z
spec=[]
for name,ya,yb in [('South',-119,-102.0),('North',-68.0,-52)]:
 za=height(tree,0,ya)+.09 if name=='South' else height(bridge,0,ya)
 zb=height(bridge,0,yb) if name=='South' else height(tree,0,yb)+.09
 spec.append(('Bridge'+name,[(0,ya,za),(0,yb,zb)],5.2,False))
spec.append(('GuildChurch',[(-28,175,0),(-10,185,0),(22,185,0),(45,174,0)],3.4,True))
manifest=[]
for name,points,width,follow in spec:
 vs=[];fs=[]
 for a,b in zip(points,points[1:]):
  n=math.ceil(math.dist(a[:2],b[:2])/.5)
  dx=b[0]-a[0];dy=b[1]-a[1];l=math.hypot(dx,dy)
  for i in range(n):
   u=i/n;x=a[0]+dx*u;y=a[1]+dy*u
   for side in [-1,1]:
    px=x-dy/l*width*.5*side;py=y+dx/l*width*.5*side
    z=height(tree,px,py)+.12 if follow else a[2]+(b[2]-a[2])*u+.02
    vs.append((px,py,z))
 a=points[-2];b=points[-1];l=math.dist(a[:2],b[:2]);dx=b[0]-a[0];dy=b[1]-a[1]
 for side in [-1,1]:
  x=b[0]-dy/l*width*.5*side;y=b[1]+dx/l*width*.5*side
  vs.append((x,y,height(tree,x,y)+.12 if follow else b[2]+.02))
 for i in range(len(vs)//2-1):
  k=i*2;fs.extend([(k,k+1,k+2),(k+1,k+3,k+2)])
 path=HERE/('SM_Handoff_'+name+'.obj')
 with path.open('w') as f:
  for x,y,z in vs:f.write(f'v {x*100} {-y*100} {z*100}\n')
  for face in fs:f.write('f '+' '.join(str(v+1) for v in reversed(face))+'\n')
 manifest.append({'name':path.stem,'file':str(path)})
(HERE/'handoff_geometry.json').write_text(json.dumps({'meshes':manifest,'spawn':[600,-31000,(height(tree,6,-310)+1.1)*100],'bridge':spec[:2]},indent=2))
print('HANDOFF_GEOMETRY',manifest)


