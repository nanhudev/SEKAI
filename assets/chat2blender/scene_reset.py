"""Producer step: empty the Blender scene before building a new asset.

Not modelling code. The previous asset (C2B-01 FP Sword) is already saved to its
own .blend, so wiping the scene is safe and keeps each source file clean.
"""

import bpy

removed = []
for obj in list(bpy.data.objects):
    removed.append(obj.name)
    bpy.data.objects.remove(obj, do_unlink=True)

for mesh in list(bpy.data.meshes):
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)

for mat in list(bpy.data.materials):
    if mat.users == 0:
        bpy.data.materials.remove(mat)

for col in list(bpy.data.collections):
    if col.users == 0:
        bpy.data.collections.remove(col)

print("SCENE RESET | removed objects: " + (", ".join(removed) if removed else "(none)"))
print("remaining -> objects=%d collections=%d materials=%d" % (
    len(bpy.data.objects), len(bpy.data.collections), len(bpy.data.materials)))
