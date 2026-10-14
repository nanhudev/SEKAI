"""Grade actual building pads into the new Mistvale art terrain.

Writes an art-only R16 and 2 m terrain mesh. The untouched Pass 01 heightmap
and blockout terrain remain available for comparison.
"""
import json
import math
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_heightmap import elevation, smooth

HERE = Path(__file__).resolve().parent
rows = json.loads((HERE / "art_level_placements.json").read_text(encoding="utf-8"))
# The original vertical Riverside row crossed the actual river channel.
# Recompose it as a street wall on the south bank, with a clear walking road.
RELOCATIONS = {}
for i, x in enumerate((-175,-160,-145,-130,-115,-85,-70,-55,-40), 1):
    # Riverside Street runs from (-174,-141) through (-120,-133), (-70,-126)
    # to (0,-117). Keep the buildings about 11.5 m south of its centre.
    if x <= -120:
        street_y = -141 + (x+174)*8/54
    elif x <= -70:
        street_y = -133 + (x+120)*7/50
    else:
        street_y = -126 + (x+70)*9/70
    RELOCATIONS[f"Riverside_House_{i:02d}"] = (x, round(street_y-11.5,2))
extra_path = HERE / "ground_relocations.json"
if extra_path.exists():
    RELOCATIONS.update(json.loads(extra_path.read_text(encoding="utf-8")))
if "HERO_Church_Nave" in RELOCATIONS:
    nx,ny = RELOCATIONS["HERO_Church_Nave"]
    RELOCATIONS["HERO_Church_BellTower"] = (nx, ny+17)
dims = {r["name"]: r["size_m"] for r in json.loads(
    (HERE / "slavic_mesh_dimensions.json").read_text(encoding="utf-8"))}
kind_mesh = {
    "cubby": "EA03_Village_OutBuilding_Cubby_01d_LOD0",
    "pent": "EA03_Village_OutBuilding_PentHouse_01a_LOD0",
    "shed": "EA03_Village_OutBuilding_Shed_01a_LOD0",
    "wide_shed": "EA03_Village_OutBuilding_Shed_03b_LOD0",
    "admin": "EA03_Town_Building_Administrative__01a_LOD0",
    "tower": "EA03_Village_Tover_01a_LOD0",
    "woodroof": "EA03_Village_OutBuilding_WoodRoof_01b_LOD0",
}

# Pads: x, y, half width, half depth, centre elevation.
pads = []
for row in rows:
    if row["kind"] == "woodroof":
        continue  # Open market shelters follow the square, not private pads.
    x, y = RELOCATIONS.get(row["label"], row["position_m"])
    w, d, _ = dims[kind_mesh[row["kind"]]]
    half = max(w, d) * row["scale"] / 2 + .55
    pads.append((x, y, half, half, elevation(x, y), row["label"]))

# Larger authored public platforms need the same ground contact as houses.
for x, y, w, d, label in [
    (-55, 165, 36, 29, "Guild"),
    (-82, 162, 22, 19, "GuildYard"),
    (*RELOCATIONS.get("HERO_Church_BellTower",(99,234)), 9, 9, "ChurchTower"),
    (0, 283, 15, 10, "NorthGate"),
]:
    pads.append((x, y, w/2+.4, d/2+.4, elevation(x, y), label))

FEATHER = 4.0
CELL = 20.0
bucket = {}
for p in pads:
    x, y, hx, hy, _, _ = p
    for ix in range(math.floor((x-hx-FEATHER)/CELL),
                    math.floor((x+hx+FEATHER)/CELL)+1):
        for iy in range(math.floor((y-hy-FEATHER)/CELL),
                        math.floor((y+hy+FEATHER)/CELL)+1):
            bucket.setdefault((ix, iy), []).append(p)


def graded_elevation(x, y):
    natural = elevation(x, y)
    hits = bucket.get((math.floor(x/CELL), math.floor(y/CELL)), ())
    weighted = 0.0
    total = 0.0
    maximum = 0.0
    for px, py, hx, hy, target, _ in hits:
        dx = max(0.0, abs(x-px)-hx)
        dy = max(0.0, abs(y-py)-hy)
        if dx >= FEATHER or dy >= FEATHER:
            continue
        w = 1.0 - smooth(0.0, FEATHER, math.hypot(dx, dy))
        weighted += w * target
        total += w
        maximum = max(maximum, w)
    if total == 0:
        return natural
    return natural*(1-maximum) + weighted/total*maximum


def write_r16():
    path = HERE / "Mistvale_Valley_Art_505.r16"
    with path.open("wb") as f:
        for iy in range(505):
            y = -353 + iy*1.4
            values = []
            for ix in range(505):
                x = -252 + ix
                raw = round(32768 + graded_elevation(x,y)*12800/25)
                values.append(max(0,min(65535,raw)))
            f.write(struct.pack("<505H", *values))
    return path


def write_proxy():
    path = HERE / "Mistvale_Terrain_Art_Proxy.obj"
    nx, ny = 253, 354  # 2 m pitch in X and almost 2 m in Y.
    with path.open("w", encoding="ascii") as f:
        f.write("# Art terrain with graded building pads; metres to UE cm\n")
        for iy in range(ny):
            y = -353 + iy*706/(ny-1)
            for ix in range(nx):
                x = -252 + ix*504/(nx-1)
                f.write(f"v {x*100:.3f} {y*100:.3f} {graded_elevation(x,y)*100:.3f}\n")
        for iy in range(ny):
            for ix in range(nx):
                f.write(f"vt {ix/(nx-1):.6f} {iy/(ny-1):.6f}\n")
        for iy in range(ny-1):
            for ix in range(nx-1):
                a = iy*nx + ix + 1
                b,c,d = a+1,a+nx,a+nx+1
                f.write(f"f {a}/{a} {b}/{b} {c}/{c}\n")
                f.write(f"f {b}/{b} {d}/{d} {c}/{c}\n")
    return path


if __name__ == "__main__":
    r16 = write_r16()
    obj = write_proxy()
    sample = []
    for x,y,hx,hy,target,label in pads:
        corners = [(x+sx*hx,y+sy*hy) for sx in (-1,1) for sy in (-1,1)]
        before = max(abs(elevation(a,b)-target) for a,b in corners)
        after = max(abs(graded_elevation(a,b)-target) for a,b in corners)
        sample.append((before,after,label))
    report = {"pads":len(pads),"r16":str(r16),"proxy":str(obj),
              "riverside_relocations":RELOCATIONS,
              "max_corner_gap_before_m":round(max(v[0] for v in sample),3),
              "max_corner_gap_after_m":round(max(v[1] for v in sample),3),
              "largest_before":sorted(sample,reverse=True)[:10]}
    (HERE/"ground_grade_report.json").write_text(
        json.dumps(report,indent=2),encoding="utf-8")
    print("GROUND_GRADE",json.dumps(report))
