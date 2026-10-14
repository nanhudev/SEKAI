"""Check saved UE road actor centres against the authored valley height field."""
import json
import math
from pathlib import Path
from generate_heightmap import elevation

items = json.loads(Path(__file__).with_name("blockout_layout.json").read_text(encoding="utf-8"))
roads = [a for a in items if a["name"].startswith((
    "GoldenRoute_", "LowerMarketLoop_", "MarketEastLoop_", "RiversideStreet_",
    "UpperResidential_", "ChurchLane_", "DockTrack_"))]
errors = []
grades = []
for a in roads:
    surface = a["z"] + 0.08
    target = elevation(a["x"], a["y"])
    errors.append((abs(surface-target), a["name"]))
    grades.append((abs(a["pitch"]), a["name"]))
result = (f"road_segments={len(roads)}\n"
          f"max_centre_height_error_m={max(errors)[0]:.3f} at {max(errors)[1]}\n"
          f"max_segment_grade_deg={max(grades)[0]:.2f} at {max(grades)[1]}\n")
Path(__file__).with_name("road_audit_result.txt").write_text(result, encoding="utf-8")
print(result)
if max(errors)[0] > 0.35:
    raise SystemExit("Road/ground mismatch exceeds 0.35 m")
