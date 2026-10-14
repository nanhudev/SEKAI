"""Match the reference's river-facing village terraces, deriving only from v039."""
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

ROOT = Path(str(_SEKAI_ROOT / 'environment_production/Terrain'))
BASE, OUT = ROOT/'v039', ROOT/'v040'
OUT.mkdir(exist_ok=True)
assert not (OUT/'terrain_manifest.json').exists(), 'Do not overwrite a version'
bpy.ops.wm.open_mainfile(filepath=str(BASE/'SEKAI_Valley_Terrain_v039.blend'))
manifest = json.loads((BASE/'terrain_manifest.json').read_text())
terrain = bpy.data.objects['SM_VIL_Valley_Terrain_v009']
data = terrain.data
original = [v.co.copy() for v in data.vertices]
route = manifest['route_m']

def smooth(a, b, x):
    t = max(0., min(1., (x-a)/(b-a)))
    return t*t*(3-2*t)

def signed_distance(x, y, polygon):
    inside, distance = False, float('inf')
    for (ax, ay), (bx, by) in zip(polygon, polygon[1:]+polygon[:1]):
        dx, dy = bx-ax, by-ay
        t = max(0., min(1., ((x-ax)*dx+(y-ay)*dy)/(dx*dx+dy*dy)))
        distance = min(distance, math.hypot(x-ax-dx*t, y-ay-dy*t))
        if (ay > y) != (by > y) and x < ax+(y-ay)*dx/dy:
            inside = not inside
    return distance if inside else -distance

def route_distance(x, y):
    distance = float('inf')
    for a, b in zip(route, route[1:]):
        dx, dy = b[0]-a[0], b[1]-a[1]
        t = max(0., min(1., ((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy)))
        distance = min(distance, math.hypot(x-a[0]-dx*t, y-a[1]-dy*t))
    return distance

# The annotated master controls land use; the aerial support controls height hierarchy.
# Contours are in the existing village coordinate system, with the river left of plaza.
terraces = [
    ('Central plaza cliff', 8.2, [(-13,5),(-10,-3),(2,-11),(23,-13),(43,-7),
                                (49,10),(44,28),(27,34),(11,32),(-6,24)]),
    ('West lower homes', 8.6, [(-79,-12),(-62,-17),(-47,-11),(-40,1),
                             (-39,19),(-46,31),(-64,37),(-82,24)]),
    ('West upper homes', 14.2, [(-79,38),(-63,35),(-47,40),(-34,52),
                               (-31,70),(-43,81),(-64,85),(-82,67)]),
    ('Forge terrace', 10.2, [(44,10),(61,7),(78,13),(83,29),
                            (77,43),(60,47),(46,37)]),
    ('Training terrace', 16.2, [(30,67),(42,58),(60,60),(77,73),
                               (79,94),(64,103),(44,104),(31,89)]),
    ('Lower east homes', 5.6, [(18,-39),(37,-42),(52,-33),(55,-18),
                              (45,-8),(27,-10),(16,-21)]),
]
assert signed_distance(20, 13, terraces[0][2]) > 0
assert signed_distance(-100, -100, terraces[0][2]) < 0

counts = {name: 0 for name, _, _ in terraces}
protected = 0
for vertex, old in zip(data.vertices, original):
    x, y, z = old
    if abs(x)>87 or y < -58 or y > 109:
        continue
    river = -29+13*math.sin(y/38)+3.3*math.sin(y/15)
    half = 3.7+.65*math.sin(y/11)+2.8*math.exp(-((y+36)/8)**2)+3.2*math.exp(-((y-37)/9)**2)
    if abs(x-river) < half+4.2:
        protected += 1
        continue
    # Keep the actual road bed, radial paving, tree masonry and tavern foundation.
    protection = max(1-smooth(3.15,5.2,route_distance(x,y)),
                     1-smooth(13.7,16.2,math.hypot(x-20,y-13)),
                     1-smooth(15.,18.,math.hypot(x+1,y-47)))
    if 29 < x < 48 and 34 < y < 53:
        protection = 1
    if protection > .999:
        protected += 1
        continue
    target = z
    for name, level, polygon in terraces:
        distance = signed_distance(x,y,polygon)
        if distance < -3.8:
            continue
        # Narrow, uneven cliff boundaries replace smooth hills, with broad buildable tops.
        fracture = .55*math.sin(y*.71+x*.21)+.28*math.sin(x*.59-y*.39)
        weight = smooth(-2.5, .7, distance+fracture)
        crest = level+.10*math.sin(x*.19+y*.14)
        candidate = z+(max(z,crest)-z)*weight
        if candidate > target:
            target = candidate
            counts[name] += 1
    vertex.co.z = z+(target-z)*(1-protection)
data.update()
changed = sum((v.co-p).length > .001 for v,p in zip(data.vertices,original))
assert changed > 2000, 'Expected a substantial central terrace correction'
assert all((v.co-p).length < .00001 for v,p in zip(data.vertices,original)
           if abs(p.x)>87 or p.y < -58 or p.y > 109), 'Outer terrain changed'

colors = data.color_attributes['Color']
changed_indices = {i for i,(v,p) in enumerate(zip(data.vertices,original)) if (v.co-p).length > .001}
for polygon in data.polygons:
    if not any(i in changed_indices for i in polygon.vertices):
        continue
    slope = 1-smooth(.40,.84,polygon.normal.z)
    polygon.use_smooth = polygon.normal.z > .79
    for li in polygon.loop_indices:
        p = data.vertices[data.loops[li].vertex_index].co
        variation = 1+.065*math.sin(p.x*.21+p.y*.32)
        colors.data[li].color = (*(variation*((.16,.27,.095)[k]*(1-slope)+(.235,.27,.285)[k]*slope)
                                 for k in range(3)), 1)

# Re-seat existing trees only where terrain changed; do not add vegetation this pass.
bpy.context.view_layer.update()
bvh = BVHTree.FromObject(terrain, bpy.context.evaluated_depsgraph_get())
reseated = 0
for row in manifest.get('instances', []):
    x,y,z = row['position_m']
    hit = bvh.ray_cast(Vector((x,y,150)),Vector((0,0,-1)),300)[0]
    if hit is not None and abs(hit.z-z) > .05:
        row['position_m'][2] = hit.z-.025
        reseated += 1

for name in manifest['assets']:
    if name != terrain.name:
        shutil.copy2(BASE/(name+'.fbx'), OUT/(name+'.fbx'))
for f in BASE.glob('*.png'):
    shutil.copy2(f, OUT/f.name)
bpy.ops.object.select_all(action='DESELECT')
terrain.select_set(True)
bpy.context.view_layer.objects.active = terrain
bpy.ops.export_scene.fbx(filepath=str(OUT/(terrain.name+'.fbx')),use_selection=True,object_types={'MESH'},
    axis_forward='-Y',axis_up='Z',apply_unit_scale=True,bake_anim=False,mesh_smooth_type='FACE')
manifest['stage'] = 'REFERENCE_TERRACE_MATCH_REQUIRES_REBAKE_AND_UE_CAPTURE'
manifest['geometry_source_version'] = 'v039'
manifest['geometry_changes'] = ['River-facing central and residential cliff platforms aligned to reference hierarchy',
    'Forge and training platforms changed from rolling ground to separate cliff benches',
    'Road beds, tree/plaza masonry, tavern foundation, six cameras and daylight retained']
manifest['reference_match'] = {'layout_master':'MASTER/layout_annotated_20261012.png',
    'primary_ground':'MASTER/acceptance_plaza_ground_20261012.png',
    'height_support':'MASTER/valley_aerial_support_20261012.png',
    'status':'NOT_ACCEPTED', 'terrace_contours':terraces}
(OUT/'terrain_manifest.json').write_text(json.dumps(manifest,indent=2))
(OUT/'terrace_match_report.json').write_text(json.dumps({'changed_vertices':changed,
    'protected_vertices':protected,'region_selections':counts,'reseated_existing_trees':reseated,
    'camera_and_lighting_unchanged':manifest['cameras']==json.loads((BASE/'terrain_manifest.json').read_text())['cameras']
    and manifest['review_lighting']==json.loads((BASE/'terrain_manifest.json').read_text())['review_lighting']},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'SEKAI_Valley_Terrain_v040.blend'))
print('REFERENCE_TERRACE_GEOMETRY',changed,counts)
