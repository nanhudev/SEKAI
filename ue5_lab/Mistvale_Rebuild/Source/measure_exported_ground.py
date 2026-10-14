import bpy,json,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from cycles.properties import CyclesLightSettings
CyclesLightSettings.cast_shadow=bpy.props.BoolProperty(default=True)
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from grade_town_ground import graded_elevation
for o in list(bpy.data.objects):bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.import_scene.fbx(filepath=str(HERE/'Mistvale_ActualScene_Review.fbx'))
o=bpy.data.objects['ART_Graded_Terrain_Proxy']
verts=[o.matrix_world @ v.co for v in o.data.vertices]
tree=BVHTree.FromPolygons(verts,[list(p.vertices) for p in o.data.polygons])
rows=[]
for x,y in [(0,-88),(0,100),(-55,165),(-115,-143.8),(115.43,207.74),(0,283)]:
    p,_,_,_=tree.ray_cast(Vector((x,-y,100)),Vector((0,0,-1)),200)
    rows.append({'ue_xy':[x,y],'mesh_z':p.z if p else None,
        'expected_z':graded_elevation(x,y),'mirrored_source_z':graded_elevation(x,-y)})
(HERE/'actual_ground_sample.json').write_text(json.dumps(rows,indent=2))
print('ACTUAL_GROUND',json.dumps(rows))
