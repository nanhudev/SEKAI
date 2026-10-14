import bpy
from pathlib import Path
root=Path(r"C:\ProgramData\Epic\EpicGamesLauncher\VaultCache\FabLibrary\Slavic_Medieval_Town_Kit_-_Lite__Free_Starter_Pack_-b99a0776\fbx\fbx_extracted\FBX")
bpy.ops.import_scene.fbx(filepath=str(root/"EA03_Village_OutBuilding_Cubby_01d.fbx"))
for o in bpy.context.scene.objects:
    if o.type=='MESH' and 'LOD0' in o.name:
        print('DIMENSION',o.name,list(o.dimensions),list(o.location),list(o.scale))
        print('BOUNDS',[(round(min(v.co[i] for v in o.data.vertices),3),round(max(v.co[i] for v in o.data.vertices),3)) for i in range(3)])
