# C2B:CHUNK blockout


import bpy
import math
from mathutils import Matrix


ASSET_COLLECTION = "SEKAI_FP_SWORD"
ROOT_NAME = "FP_Sword_Root"


# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------


def ensure_object_mode():
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')




def delete_collection_if_exists(name):
    col = bpy.data.collections.get(name)
    if not col:
        return


    for obj in list(col.all_objects):
        bpy.data.objects.remove(obj, do_unlink=True)


    for child in list(col.children):
        bpy.data.collections.remove(child)


    bpy.data.collections.remove(col)




def make_collection(name):
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col