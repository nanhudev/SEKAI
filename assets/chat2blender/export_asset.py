"""Producer export step for C2B-01 FP Sword.

Not modelling code: it strips review-only objects, saves the .blend source, and
writes a GLB containing only the asset hierarchy.

Blend  -> F:/SEKAI/assets_source/weapons/fp_sword.blend
GLB    -> F:/SEKAI/assets/models/weapons/fp_sword.glb
"""

import bpy
import os

COLLECTION = "SEKAI_FP_SWORD"
ROOT = "FP_Sword_Root"
BLEND_PATH = "F:/SEKAI/assets_source/weapons/fp_sword.blend"
GLB_PATH = "F:/SEKAI/assets/models/weapons/fp_sword.glb"

REVIEW_ONLY = ["ReviewCam", "ReviewKey"]
EXPORT_NAMES = [
    "FP_Sword_Root",
    "Blade",
    "Guard",
    "Guard_Motif",
    "Grip",
    "Pommel",
    "blade_tip",
    "blade_mid",
    "hilt",
    "cutting_edge_center",
]

for name in REVIEW_ONLY:
    obj = bpy.data.objects.get(name)
    if obj is not None:
        bpy.data.objects.remove(obj, do_unlink=True)

# Remove the leftover startup objects so the source file is clean.
for name in ["Cube"]:
    obj = bpy.data.objects.get(name)
    if obj is not None:
        bpy.data.objects.remove(obj, do_unlink=True)

os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)

# Select only the asset hierarchy for the GLB.
bpy.ops.object.select_all(action='DESELECT')
missing = []
present = []
for name in EXPORT_NAMES:
    obj = bpy.data.objects.get(name)
    if obj is None:
        missing.append(name)
        continue
    obj.select_set(True)
    present.append(name)

root = bpy.data.objects.get(ROOT)
if root is not None:
    bpy.context.view_layer.objects.active = root

if missing:
    print("EXPORT WARNING missing objects: " + ", ".join(missing))

print("exporting: " + ", ".join(present))

bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

bpy.ops.export_scene.gltf(
    filepath=GLB_PATH,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
    export_yup=True,
)

print("saved blend: " + BLEND_PATH)
print("exported glb: " + GLB_PATH)
print("glb bytes: " + str(os.path.getsize(GLB_PATH)))
