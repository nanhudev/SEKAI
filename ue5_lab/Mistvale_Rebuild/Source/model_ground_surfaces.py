"""Continuous ground-following roads/plazas and seam-free river for UE OBJ import."""
import math,sys,json
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from grade_town_ground import graded_elevation
from generate_heightmap import river_y,smooth

def ground(x,y):
    # Match the actual 2 m triangulated terrain, rather than an analytic guess.
    ix=math.floor((x+252)/2);iy=math.floor((y+353)/2)
    ax=-252+ix*2;ay=-353+iy*2
    u=(x-ax)/2;v=(y-ay)/2
    a=graded_elevation(ax,ay);b=graded_elevation(ax+2,ay)
    c=graded_elevation(ax,ay+2);d=graded_elevation(ax+2,ay+2)
    if u+v<=1:return a+(b-a)*u+(c-a)*v
    return d+(c-d)*(1-u)+(b-d)*(1-v)

def write(name,verts,faces):
    path=HERE/(name+'.obj')
    with path.open('w',encoding='ascii') as f:
        f.write('# UE OBJ handedness preconversion: Y reflected, winding reversed\n')
        for x,y,z in verts:f.write(f'v {x*100:.4f} {-y*100:.4f} {z*100:.4f}\n')
        for x,y,z in verts:f.write(f'vt {x/3:.5f} {y/3:.5f}\n')
        for face in faces:f.write('f '+' '.join(f'{i+1}/{i+1}' for i in reversed(face))+'\n')
    return {'name':name,'file':str(path),'vertices':len(verts),'triangles':len(faces)}

routes=[
 ('GoldenRoute_South',[(6,-320),(5,-235),(-7,-165),(0,-115)],5.2),
 ('GoldenRoute_Town',[(0,-55),(-9,-20),(-5,34),(0,72),(-8,117),(-30,155),(-16,205),(0,265),(0,330)],5.2),
 ('LowerMarketLoop',[(-75,38),(-54,60),(-31,71),(-21,88),(-27,119),(-63,137),(-90,117),(-75,38)],3.3),
 ('MarketEastLoop',[(24,73),(47,72),(73,102),(55,132),(27,131),(24,73)],3.2),
 ('RiversideStreet',[(-174,-141),(-120,-133),(-70,-126),(0,-117),(71,-113),(155,-116)],3.2),
 ('UpperResidential',[(-84,160),(-66,199),(-52,234),(-25,252),(15,253),(61,231),(81,201)],3.3),
 ('ChurchLane',[(8,165),(45,174),(89,194),(104,219)],2.8),
 ('DockTrack',[(-158,-117),(-131,-103),(-98,-87),(-67,-74)],2.7)]
output=[]
for name,points,width in routes:
    samples=[]
    for a,b in zip(points,points[1:]):
        n=max(1,math.ceil(math.dist(a,b)/.75))
        samples.extend([(a[0]+(b[0]-a[0])*i/n,a[1]+(b[1]-a[1])*i/n) for i in range(n)])
    samples.append(points[-1])
    cols=math.ceil(width/.75)+1
    verts=[];faces=[]
    for i,(x,y) in enumerate(samples):
        a=samples[max(0,i-1)];b=samples[min(len(samples)-1,i+1)]
        dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy)
        nx,ny=-dy/length,dx/length
        for j in range(cols):
            off=width*(j/(cols-1)-.5);px=x+nx*off;py=y+ny*off
            verts.append((px,py,ground(px,py)+.075))
    for i in range(len(samples)-1):
        for j in range(cols-1):
            a=i*cols+j;b=a+1;c=a+cols;d=c+1
            faces.extend([(a,b,c),(b,d,c)])
    output.append(write('SM_Route_'+name,verts,faces))

for name,cx,cy,hx,hy in [('MarketSquare',0,100,15,16),
                         ('GuildForecourt',-30,163,10,17),
                         ('ChurchForecourt',104,211,5,14)]:
    verts=[];faces=[]
    nx=math.ceil(hx*2/.75)+1;ny=math.ceil(hy*2/.75)+1
    for iy in range(ny):
        y=cy-hy+2*hy*iy/(ny-1)
        for ix in range(nx):
            x=cx-hx+2*hx*ix/(nx-1)
            verts.append((x,y,ground(x,y)+.105))
    for iy in range(ny-1):
        for ix in range(nx-1):
            a=iy*nx+ix;b=a+1;c=a+nx;d=c+1
            if name=='MarketSquare':
                mx=(verts[a][0]+verts[d][0])/2;my=(verts[a][1]+verts[d][1])/2
                if ((mx-cx)/hx)**2+((my-cy)/hy)**2>1:continue
            faces.extend([(a,b,c),(b,d,c)])
    output.append(write('SM_Plaza_'+name,verts,faces))

verts=[];faces=[]
for i in range(501):
    x=-250+i;y=river_y(x);w=10.5+4.5*smooth(-85,70,x)
    verts.extend([(x,y-w,2.94),(x,y+w,2.94)])
for i in range(500):
    a=i*2;faces.extend([(a,a+2,a+1),(a+2,a+3,a+1)])
output.append(write('SM_River_Continuous',verts,faces))
(HERE/'ground_surface_manifest.json').write_text(json.dumps(output,indent=2))
print('GROUND_SURFACES',len(output),'TRIANGLES',sum(r['triangles'] for r in output))
