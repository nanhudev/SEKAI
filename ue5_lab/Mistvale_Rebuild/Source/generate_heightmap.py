"""Author a new 505-square R16 river-valley Landscape source for Mistvale.

World coordinates are metres: X east, Y north. UE Landscape origin is
(-25200, -35300, 0) cm, XY scale (100, 140) cm, Z scale 25 cm.
"""
import math
import struct
from pathlib import Path

SIZE = 505
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Source" / "Mistvale_Valley_505.r16"


def river_y(x):
    return -88.0 + 13.0 * math.sin((x + 25.0) / 105.0) + 4.0 * math.sin(x / 39.0)


def smooth(a, b, v):
    t = max(0.0, min(1.0, (v - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def elevation(x, y):
    # South forest hills, low floodplain, settled terrace, north ridge.
    base = 6.0 + 0.024 * (y + 100.0)
    forest = 2.5 * math.sin(x / 67.0) * math.sin((y + 250.0) / 59.0)
    base += forest * (1.0 - smooth(-175.0, -90.0, y))
    base += 4.2 * smooth(20.0, 100.0, y)
    base += 4.0 * smooth(155.0, 240.0, y)
    base += 3.5 * smooth(245.0, 350.0, y)
    # Wider working bank at the docks; narrower upstream in the forest.
    axis = river_y(x)
    width = 10.5 + 4.5 * smooth(-85.0, 70.0, x)
    dist = abs(y - axis)
    channel = 1.0 - smooth(width - 3.0, width + 8.0, dist)
    bed = 2.2 + 0.6 * (dist / max(width, 1.0)) ** 2
    base = base * (1.0 - channel) + bed * channel
    # River approaches ease into the channel; the city side has a terrace.
    town = smooth(axis + 24.0, axis + 46.0, y)
    base += 1.5 * town * (1.0 - smooth(axis + 92.0, axis + 112.0, y))
    # Break the northern skyline while leaving the town's buildable ground.
    ridge = smooth(250.0, 350.0, y)
    base += ridge * (1.6 * math.sin(x / 36.0) + 0.9 * math.sin(x / 17.0))
    return base


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("wb") as file:
        for row in range(SIZE):
            y = -353.0 + row * 1.4
            pixels = []
            for col in range(SIZE):
                x = -252.0 + col
                h = elevation(x, y)
                # UE R16 at Z scale 25: one code is 25/128 centimetres.
                raw = round(32768 + h * 12800.0 / 25.0)
                pixels.append(max(0, min(65535, raw)))
            file.write(struct.pack("<" + "H" * SIZE, *pixels))
    print(f"WROTE {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
