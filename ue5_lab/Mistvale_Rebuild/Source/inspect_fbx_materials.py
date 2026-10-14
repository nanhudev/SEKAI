import bpy
import json
import sys
from pathlib import Path

path = Path(sys.argv[sys.argv.index('--') + 1])
bpy.ops.import_scene.fbx(filepath=str(path))
rows = []
for obj in bpy.context.scene.objects:
    if obj.type != 'MESH':
        continue
    mats = []
    for m in obj.data.materials:
        if not m:
            continue
        images = []
        if m.use_nodes:
            images = [str(n.image.filepath) for n in m.node_tree.nodes
                      if n.type == 'TEX_IMAGE' and n.image]
        mats.append({'name': m.name, 'diffuse': list(m.diffuse_color),
                     'images': images})
    colors=[]
    for attr in obj.data.color_attributes:
        first=[tuple(round(c,3) for c in e.color) for e in list(attr.data)[:500]]
        colors.append({'name':attr.name,'unique_sample':list(dict.fromkeys(first))[:8]})
    rows.append({'name': obj.name, 'faces': len(obj.data.polygons),
                 'color_attributes': colors,
                 'materials': mats})
print('FBX_MATERIAL_AUDIT', json.dumps(rows))
