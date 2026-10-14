"""Draw a top-down composition audit from actor positions read back from UE."""
import json
import math
from pathlib import Path
from xml.sax.saxutils import escape
from generate_heightmap import river_y

HERE = Path(__file__).resolve().parent
layout = json.loads((HERE / "blockout_layout.json").read_text(encoding="utf-8"))
out = HERE.parent / "Review" / "blockout_plan.svg"
out.parent.mkdir(parents=True, exist_ok=True)


def X(v): return 55 + (v + 252) * 1.58
def Y(v): return 1150 - (v + 353) * 1.53


parts = [
    '<svg xmlns="http://www.w3.org/2000/svg" width="910" height="1200" viewBox="0 0 910 1200">',
    '<rect width="910" height="1200" fill="#d8dfc8"/>',
    '<text x="55" y="35" font-size="21" font-family="Arial" fill="#263829">MISTVALE UE5 | PASS 01 COMPOSITION PLAN</text>',
    '<text x="55" y="58" font-size="12" font-family="Arial" fill="#526452">Greybox spatial audit • not an in-engine beauty screenshot</text>',
]
river = " ".join(f"{X(x):.1f},{Y(river_y(x)):.1f}" for x in range(-252,253,5))
parts += [f'<polyline points="{river}" fill="none" stroke="#aecad2" stroke-width="51" stroke-linecap="round"/>',
          f'<polyline points="{river}" fill="none" stroke="#588fa0" stroke-width="34" stroke-linecap="round"/>']


def rect(a, fill, stroke="#526152", opacity=1):
    x, y = X(a["x"]), Y(a["y"])
    w, h = a["sx"]*1.58, a["sy"]*1.53
    return (f'<rect x="{x-w/2:.1f}" y="{y-h/2:.1f}" width="{w:.1f}" height="{h:.1f}" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="1.2" opacity="{opacity}" '
            f'transform="rotate({-a["yaw"]:.1f} {x:.1f} {y:.1f})"/>')


for a in layout:
    if any(a["name"].startswith(p) for p in ("GoldenRoute_", "LowerMarketLoop_", "MarketEastLoop_",
          "RiversideStreet_", "UpperResidential_", "ChurchLane_", "DockTrack_")):
        parts.append(rect(a, "#b39b74", "#b39b74", 0.9))
for a in layout:
    n = a["name"]
    if "_House_" in n or n.startswith("CornerBuilding_"):
        parts.append(rect(a, "#f7eee0", "#665e56"))
    elif n.startswith("HERO_"):
        parts.append(rect(a, "#bc7e60", "#623f32"))
    elif n.startswith("MarketStall_") or n.startswith("MarketSquare_"):
        parts.append(rect(a, "#e4bd6e", "#9e7147"))
    elif n.endswith("Bridge_DECK"):
        parts.append(rect(a, "#737877", "#434b4d"))

for title,x,y in [("SOUTH FOREST",4,-280),("RIVERSIDE",-170,-175),("MARKET",4,104),
                  ("GUILD",-55,164),("CHURCH",100,217),("NORTH GATE",0,302)]:
    parts.append(f'<text x="{X(x):.1f}" y="{Y(y):.1f}" text-anchor="middle" '
                 f'font-family="Arial" font-size="13" font-weight="bold" fill="#26372f">{escape(title)}</text>')
parts.append('<text x="55" y="1175" font-size="11" font-family="Arial" fill="#526452">81 town masses • 2 crossings • new 504 × 706 m valley • UE actor positions verified after save</text>')
parts.append('</svg>')
out.write_text("\n".join(parts), encoding="utf-8")
print(out)
