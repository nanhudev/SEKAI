"""Replace detached rock markers with two authored, continuous cliff massifs."""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import bpy
import json
import math
import shutil
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(str(_SEKAI_ROOT / 'environment_production'))
BASE=ROOT/'Terrain/v011'
OUT=ROOT/'Terrain/v012'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v011.blend'))
manifest=json.loads((BASE/'terrain_manifest.json').read_text())
terrain=bpy.data.objects['SM_VIL_Valley_Terrain_v009']
bvh=BVHTree.FromObject(terrain,bpy.context.evaluated_depsgraph_get())

def ground(x,y):
    hit=bvh.ray_cast(Vector((x,y,150)),Vector((0,0,-1)),250)[0]
    return hit.z if hit else 0

def mat(name,color):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Roughness'].default_value=.94
    manifest['material_palette'][name]=list(color)
    return m

rock=[mat('MV_Escarpment_Stone_%d'%i,c) for i,c in enumerate([
    (.39,.43,.43),(.32,.37,.38),(.45,.46,.40),(.29,.33,.33)])]
turf=mat('MV_Escarpment_Turf',(.27,.35,.13))
collection=bpy.data.collections.new('SEKAI_SCULPTED_ESCARPMENTS')
bpy.context.scene.collection.children.link(collection)

# Keep the successful route, water, and landmark geometry exactly in place.
retained=[]
for name in manifest['assets']:
    if name.startswith('SM_VIL_Valley_Cliff_'):
        obj=bpy.data.objects.get(name)
        if obj:bpy.data.objects.remove(obj,do_unlink=True)
    else:
        retained.append(name);shutil.copy2(BASE/(name+'.fbx'),OUT/(name+'.fbx'))
manifest['assets']=retained

for side,control in [(-1,[(-80,-110),(-77,-83),(-79,-55),(-71,-28),(-78,0),(-75,28),(-72,58),(-66,84),(-77,118)]),
                     (1,[(90,-110),(86,-78),(83,-50),(85,-18),(82,12),(81,40),(88,66),(84,99),(87,125)])]:
    points=[]
    for a,b in zip(control,control[1:]):
        steps=math.ceil(math.dist(a,b)/2.6)
        for j in range(steps):
            t=j/steps;points.append((a[0]*(1-t)+b[0]*t,a[1]*(1-t)+b[1]*t))
    points.append(control[-1])
    vertices=[];faces=[];indices=[];rows=8
    for j,(x,y) in enumerate(points):
        base=ground(x,y)-1.5
        crest=base+14+3.2*math.sin(y*.065)+2.0*math.sin(y*.17+side)
        fissure=.70*math.sin(j*1.37)+.35*math.cos(j*.71)
        for r in range(rows):
            # Three chipped ledges and a broad grassy bench form the section.
            offset=[-2.5,-1.6,-.4,-1.1,.9,.3,1.7,23][r]
            level=[-.8,.08,.35,.39,.68,.72,1,1][r]
            v=(x+side*(offset+fissure*(1-r/9)),y,
               base+(crest-base)*level+.25*math.sin(j*.59+r))
            vertices.append(v)
    for j in range(len(points)-1):
        for r in range(rows-1):
            a=j*rows+r
            face=(a,a+rows,a+rows+1,a+1)
            # Interior face normals point into the village; top normals face up.
            faces.append(face if side<0 else tuple(reversed(face)))
            indices.append(4 if r==rows-2 else (j//4+r//2)%4)
    name='SM_VIL_Escarpment_'+('West' if side<0 else 'East')
    data=bpy.data.meshes.new(name+'_Geometry');data.from_pydata(vertices,[],faces);data.update()
    obj=bpy.data.objects.new(name,data);collection.objects.link(obj)
    for m in rock+[turf]:data.materials.append(m)
    for i,p in enumerate(data.polygons):
        p.material_index=indices[i];p.use_smooth=False
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    # Opposite wall windings require explicitly upward-facing grassy caps.
    import bmesh
    bm=bmesh.new();bm.from_mesh(data)
    for face in bm.faces:
        if face.material_index==4 and face.normal.z<0:face.normal_flip()
    bm.to_mesh(data);bm.free();data.update()
    uv=data.uv_layers.new(name='UV_Metric')
    for p in data.polygons:
        for li in p.loop_indices:
            v=data.vertices[data.loops[li].vertex_index].co
            uv.data[li].uv=(v.y*.25,v.z*.25)
    bpy.ops.export_scene.fbx(filepath=str(OUT/(name+'.fbx')),use_selection=True,object_types={'MESH'},
        axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
    manifest['assets'].append(name)

manifest['stage']='SCULPTED_ESCARPMENTS_NOT_VISUALLY_ACCEPTED'
manifest['geometry_changes']=['Removed eleven detached cliff markers',
    'Authored continuous east and west chipped escarpments with grassy benches',
    'Existing water, roads, landmarks and six camera transforms unchanged']
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v012.blend'))
print('SEKAI_ESCARPMENTS_SAVED',OUT)
