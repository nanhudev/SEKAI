# C2B:CHUNK export
import bpy
import os
import re

COLLECTION_NAME = "SEKAI_MISTVALE_KIT"
EXPORT_DIR = r"F:\SEKAI\assets\models\mistvale"

MODULE_NAMES = (
    "WallPlain", "WallWindow", "WallDoor", "Beam",
    "RoofSlope", "Door", "Window", "Foundation",
    "Fence", "Stair", "Chimney", "Sign",
)

kit = bpy.data.collections.get(COLLECTION_NAME)
if kit is None:
    raise RuntimeError(f"Missing collection: {COLLECTION_NAME}")

objects = []
for name in MODULE_NAMES:
    obj = kit.objects.get(name)
    if obj is None or obj.type != 'MESH':
        raise RuntimeError(f"Missing mesh module: {name}")
    objects.append(obj)

os.makedirs(EXPORT_DIR, exist_ok=True)

def safe_filename(name):
    s = re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()
    s = re.sub(r'[^a-z0-9_-]+', '_', s).strip('_')
    return s

previous_active = bpy.context.view_layer.objects.active
previous_selection = list(bpy.context.selected_objects)
original_locations = {obj: obj.location.copy() for obj in objects}

results = []
total_tris = 0

try:
    for obj in objects:
        obj.data.calc_loop_triangles()
        tris = len(obj.data.loop_triangles)
        total_tris += tris

        filename = safe_filename(obj.name) + ".glb"
        filepath = os.path.join(EXPORT_DIR, filename)

        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj

        obj.location = (0.0, 0.0, 0.0)
        bpy.context.view_layer.update()

        try:
            bpy.ops.export_scene.gltf(
                filepath=filepath,
                export_format='GLB',
                use_selection=True,
                export_apply=True,
                export_materials='EXPORT',
                export_yup=True,
            )

            size_bytes = os.path.getsize(filepath) if os.path.isfile(filepath) else 0
            results.append((obj.name, filepath, size_bytes, tris))

        finally:
            obj.location = original_locations[obj]
            bpy.context.view_layer.update()

finally:
    for obj in objects:
        obj.location = original_locations[obj]

    bpy.ops.object.select_all(action='DESELECT')

    for obj in previous_selection:
        if obj and obj.name in bpy.data.objects:
            obj.select_set(True)

    if previous_active and previous_active.name in bpy.data.objects:
        bpy.context.view_layer.objects.active = previous_active

    bpy.context.view_layer.update()

print("=" * 80)
print("SEKAI / MISTVALE GLB EXPORT")
print("=" * 80)

for name, filepath, size_bytes, tris in results:
    print(
        f"{name:12s} | "
        f"{tris:5d} tris | "
        f"{size_bytes / 1024.0:8.1f} KB | "
        f"{filepath}"
    )

print("-" * 80)
print(f"Exported: {len(results)}/{len(objects)} files")
print(f"Total triangles: {total_tris}")
print(f"Directory: {EXPORT_DIR}")
print("=" * 80)

# C2B:END
