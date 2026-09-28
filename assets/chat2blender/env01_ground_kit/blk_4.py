mesh = obj.data if obj.type == 'MESH' else None
bpy.data.objects.remove(obj, do_unlink=True)

if mesh is not None and mesh.users == 0:
    bpy.data.meshes.remove(mesh)