"""Rasterize Blender-authored planar polygons without modifying reference images."""
import json
import sys
from PIL import Image, ImageDraw

size=int(sys.argv[2])
bitmap=Image.new('RGB',(size,size))
draw=ImageDraw.Draw(bitmap)
for points,color in json.load(sys.stdin):
    draw.polygon([tuple(p) for p in points],fill=tuple(color))
bitmap.save(sys.argv[1])
