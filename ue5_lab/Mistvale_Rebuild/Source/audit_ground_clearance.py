"""Fast plan-view check for building foundation and road overlap."""
import json
import math
import sys
from pathlib import Path

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from grade_town_ground import RELOCATIONS, kind_mesh, dims

layout=json.loads((HERE/"blockout_layout.json").read_text(encoding="utf-8"))
roads=[r for r in layout if "_" in r["name"] and
       r["name"].rsplit("_",2)[0] in {
           "GoldenRoute","LowerMarketLoop","MarketEastLoop",
           "RiversideStreet","UpperResidential","ChurchLane","DockTrack"}]
placements=json.loads((HERE/"art_level_placements.json").read_text(encoding="utf-8"))
collisions=[]
boxes=[]
for p in placements:
    if p["kind"]=="woodroof":
        continue
    x,y=RELOCATIONS.get(p["label"],p["position_m"])
    w,d,_=dims[kind_mesh[p["kind"]]]
    hx=w*p["scale"]*.455
    hy=d*p["scale"]*.455
    boxes.append((p["label"],x,y,hx,hy))
    # 1.82 times imported half extent: actual foundation size. Only test
    # occupied floor; a little overlap at a corner is tolerable.
    nearest=(1e9,None)
    for road in roads:
        dx=max(0,abs(road["x"]-x)-hx)
        dy=max(0,abs(road["y"]-y)-hy)
        clear=math.hypot(dx,dy)-road["sy"]/2
        if clear<nearest[0]:nearest=(clear,road["name"])
    if nearest[0]<.5:
        collisions.append({"building":p["label"],
                           "road":nearest[1],"clearance_m":round(nearest[0],2)})
building_pairs=[]
for i,a in enumerate(boxes):
    for b in boxes[i+1:]:
        ox=a[3]+b[3]-abs(a[1]-b[1])
        oy=a[4]+b[4]-abs(a[2]-b[2])
        if ox>.5 and oy>.5:
            building_pairs.append((a[0],b[0],round(ox,2),round(oy,2)))
report={"road_segments":len(roads),"buildings":len(placements)-8,
        "foundation_road_conflicts":len(collisions),
        "foundation_foundation_overlaps":building_pairs,
        "worst":sorted(collisions,key=lambda r:r["clearance_m"])[:30]}
(HERE/"ground_clearance_audit.json").write_text(
    json.dumps(report,indent=2),encoding="utf-8")
print("GROUND_CLEARANCE",json.dumps(report))
