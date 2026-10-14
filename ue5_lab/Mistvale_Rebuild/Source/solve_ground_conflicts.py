"""Move the few foundation footprints that cut through town roads."""
import json
import math
import sys
from pathlib import Path

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from grade_town_ground import kind_mesh, dims

roads=[r for r in json.loads((HERE/"blockout_layout.json").read_text(encoding="utf-8"))
       if r["name"].rsplit("_",2)[0] in {
           "GoldenRoute","LowerMarketLoop","MarketEastLoop",
           "RiversideStreet","UpperResidential","ChurchLane","DockTrack"}]
rows=json.loads((HERE/"art_level_placements.json").read_text(encoding="utf-8"))
seed={}
for i,x in enumerate((-175,-160,-145,-130,-115,-85,-70,-55,-40),1):
    if x<=-120: street_y=-141+(x+174)*8/54
    elif x<=-70: street_y=-133+(x+120)*7/50
    else: street_y=-126+(x+70)*9/70
    seed[f"Riverside_House_{i:02d}"]=[x,round(street_y-11.5,2)]
pieces={}
for row in rows:
    if row["kind"]=="woodroof":continue
    x,y=seed.get(row["label"],row["position_m"])
    w,d,_=dims[kind_mesh[row["kind"]]]
    pieces[row["label"]]=[x,y,w*row["scale"]*.455,d*row["scale"]*.455]


def road_clear(x,y,hx,hy,r):
    dx=max(0,abs(r["x"]-x)-hx)
    dy=max(0,abs(r["y"]-y)-hy)
    return math.hypot(dx,dy)-r["sy"]/2


def nearest_road(piece):
    x,y,hx,hy=piece
    return min(((road_clear(x,y,hx,hy,r),r) for r in roads),
               key=lambda a:a[0])


def score(label,x,y):
    _,_,hx,hy=pieces[label]
    penalty=0.0
    for r in roads:
        if abs(r["x"]-x)>hx+r["sy"]/2+5 or abs(r["y"]-y)>hy+r["sy"]/2+5:
            continue
        penetration=max(0,1.0-road_clear(x,y,hx,hy,r))
        penalty += penetration*penetration*4.0
    for other,(ox,oy,ohx,ohy) in pieces.items():
        if other==label:continue
        px=max(0,hx+ohx+1.0-abs(x-ox))
        py=max(0,hy+ohy+1.0-abs(y-oy))
        penalty += px*py*8.0
    ox,oy=original[label]
    penalty += .09*((x-ox)**2+(y-oy)**2)
    return penalty


original={name:(p[0],p[1]) for name,p in pieces.items()}
for _ in range(3):
    offenders=sorted((nearest_road(p)[0],name) for name,p in pieces.items()
                     if name not in seed)
    for clear,name in offenders:
        if clear>=.75:continue
        x,y,hx,hy=pieces[name]
        _,r=nearest_road(pieces[name])
        angle=math.radians(r["yaw"])
        nx,ny=-math.sin(angle),math.cos(angle)
        best=(score(name,x,y),x,y)
        for step in range(-40,41):
            shift=step*.5
            cx,cy=x+nx*shift,y+ny*shift
            ox,_=original[name]
            # Keep street walls in their named districts. Crossing to the
            # opposite side would clear geometry but destroy the town plan.
            if "West" in name and cx>ox+.1:continue
            if "East" in name and cx<ox-.1:continue
            if name in ("HERO_Church_Nave","CornerBuilding_04") and cx<ox-.1:
                continue
            value=score(name,cx,cy)
            if value<best[0]:best=(value,cx,cy)
        pieces[name][0:2]=best[1:3]

# Two plots sat directly on the east market loop. Give them the quieter east
# edge of town, preserving a clear loop and the centre of the market square.
pieces["MarketEast_House_01"][0:2]=[45.0,62.0]
pieces["MarketEast_House_02"][0:2]=[68.0,62.0]
pieces["HERO_Church_Nave"][0] += 1.0

moves={}
for name,(x,y,_,_) in pieces.items():
    if math.hypot(x-original[name][0],y-original[name][1])>.25:
        moves[name]=[round(x,2),round(y,2)]
remaining=[(round(nearest_road(p)[0],2),name) for name,p in pieces.items()
           if nearest_road(p)[0]<.5]
report={"moves":moves,"count":len(moves),
        "remaining_road_conflicts":sorted(remaining),
        "max_move_m":round(max((math.dist(original[n],p) for n,p in moves.items()),default=0),2)}
(HERE/"ground_relocations.json").write_text(json.dumps(moves,indent=2),encoding="utf-8")
(HERE/"ground_relocation_report.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
print("GROUND_RELOCATION",json.dumps(report))
