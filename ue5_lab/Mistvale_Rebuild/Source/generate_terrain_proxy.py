"""Low-resolution editable-review proxy for the authored Landscape heightmap."""
from pathlib import Path
from generate_heightmap import elevation

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Source" / "Mistvale_Terrain_Proxy.obj"
NX, NY = 127, 177


def main():
    with OUT.open("w", encoding="ascii") as f:
        f.write("# TEMPORARY proxy for Mistvale_Valley_505.r16\n")
        for iy in range(NY):
            y = -353.0 + iy * 706.0 / (NY - 1)
            for ix in range(NX):
                x = -252.0 + ix * 504.0 / (NX - 1)
                f.write(f"v {x*100:.3f} {y*100:.3f} {elevation(x,y)*100:.3f}\n")
        for iy in range(NY):
            for ix in range(NX):
                f.write(f"vt {ix/(NX-1):.5f} {iy/(NY-1):.5f}\n")
        for iy in range(NY - 1):
            for ix in range(NX - 1):
                a = iy * NX + ix + 1
                b = a + 1
                c = a + NX
                d = c + 1
                f.write(f"f {a}/{a} {b}/{b} {c}/{c}\n")
                f.write(f"f {b}/{b} {d}/{d} {c}/{c}\n")
    print(f"WROTE {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
