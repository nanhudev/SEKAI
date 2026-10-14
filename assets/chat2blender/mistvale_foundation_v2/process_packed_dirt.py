"""Turn the approved paint source into a tileable, color-matched PBR sample."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import numpy as np
from pathlib import Path

SOURCE = Path(str(_SEKAI_ROOT / 'assets_source/environment/mistvale/materials_v2/mv_packed_dirt_source_v1.png'))
OUT = Path(str(_SEKAI_ROOT / 'godot/textures/environment/foundation_v2'))
OUT.mkdir(parents=True, exist_ok=True)
N = 1024

img = bpy.data.images.load(str(SOURCE), check_existing=False)
img.scale(N, N)
pixels = np.empty(N * N * 4, dtype=np.float32)
img.pixels.foreach_get(pixels)
paint = pixels.reshape(N, N, 4)[:, :, :3]

# The half-tile offset makes outer edges join because they come from the
# original image's continuous centre. Heal only the new centre cross with the
# original. Blending the whole tile made four obvious repeated quadrants.
shifted = np.roll(np.roll(paint, N // 2, axis=0), N // 2, axis=1)
coord = np.arange(N, dtype=np.float32)
distance = np.minimum(np.abs(coord - N / 2), N / 2)
band = np.clip((N * .19 - distance) / (N * .19), 0, 1)
band = band * band * (3 - 2 * band)
heal = np.maximum(band[:, None], band[None, :])[:, :, None]
tile = shifted * (1 - heal) + paint * heal

# Blender image pixels and saved PNG samples are both display-domain here.
# Match the road palette directly; using linear target values made it black.
target = np.array((.53, .45, .36), dtype=np.float32)
mean = tile.mean(axis=(0, 1))
tile = np.clip((tile - mean) * .82 + target, 0, 1)

def save(name, rgb):
    image = bpy.data.images.new(name, width=N, height=N, alpha=True, float_buffer=False)
    rgba = np.empty((N, N, 4), dtype=np.float32)
    rgba[:, :, :3] = rgb
    rgba[:, :, 3] = 1
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw = str(OUT / (name + ".png"))
    image.file_format = 'PNG'
    image.save()
    bpy.data.images.remove(image)

save("mv_packed_dirt_paint_albedo", tile)

luma = tile[:, :, 0] * .25 + tile[:, :, 1] * .63 + tile[:, :, 2] * .12
smooth = luma.copy()
for offset in (1, 2):
    smooth += np.roll(luma, offset, axis=0)
    smooth += np.roll(luma, -offset, axis=0)
    smooth += np.roll(luma, offset, axis=1)
    smooth += np.roll(luma, -offset, axis=1)
smooth /= 9.0
dx = (np.roll(smooth, -1, axis=1) - np.roll(smooth, 1, axis=1)) * 2.0
dy = (np.roll(smooth, -1, axis=0) - np.roll(smooth, 1, axis=0)) * 2.0
normal = np.stack((-.5 * dx + .5, -.5 * dy + .5,
                   np.sqrt(np.maximum(1.0 - dx * dx - dy * dy, 0.0)) * .5 + .5), axis=2)
save("mv_packed_dirt_paint_normal", normal)
rough = np.clip(.88 + (luma - luma.mean()) * .10, .77, .96)
save("mv_packed_dirt_paint_roughness", np.repeat(rough[:, :, None], 3, axis=2))
print("packed dirt source mean", mean, "target", target)
