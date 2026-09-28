@tool
extends Node3D
class_name MistvaleFlora
## LEVEL ART — the vegetation layer of the Mistvale region.
##
## WHY THIS FILE EXISTS AT ALL: before it, the region was bare shaded ground.
## Terrain colour is not enough — the player reads a world through what GROWS on
## it. Vegetation is also the cheapest way to do the things the brief asks for
## that terrain cannot: frame a vista, hide a bad transition, close a street,
## signal water, signal wilderness.
##
## FAMILIES, NOT Tree01. Eight families, each with variants, each with its own
## rule set. A map with one tree asset reads as a map with one tree asset.
##
## PROCEDURAL BUT NOT RANDOM. Every instance survives four masks:
##
##   ROUTE      nothing grows on a walked surface, and nothing blocks the walk.
##   ZONE       bamboo in the east forest, pine on the mountain, willow at the
##              waterline — a plant out of its zone is a plant that lies.
##   SLOPE      trees need flat ground, grass tolerates a bank.
##   SETTLEMENT the village is cleared land; the wilderness is not.
##
## Plus two POSITIVE rules the brief asks for by name: density rises at the
## water's edge, and debris rises at the foot of a steep face.
##
## DETAIL FOLLOWS THE ROUTE. Scatter across all 500,000 m2 would put 90% of the
## polygons where the player never walks. Ground detail is only generated within
## a band of the road network and the water — which is where it is seen.
##
## EVERY HEIGHT COMES FROM MistvaleHeights. Nothing here authors an elevation.

@export var build_trees: bool = true
@export var build_ground: bool = true
@export var build_scree: bool = true
@export var build_collision: bool = true

## Instances are only generated within this distance of a road or the waterline.
const DETAIL_REACH := 95.0
## Nothing at all within this distance of a walked line: it is the path.
const ROAD_CLEAR := 2.6
## Trees keep a wider berth — a canopy at eye height on the street is a fight
## with the camera, not a tree. 4.2 m was measured against the trunk and is far
## too close: the crown radius reaches 2.7 m, so the first version hung foliage
## over the middle of the road and the street shot came back with a bush in the
## player's face.
const TREE_ROAD_CLEAR := 7.0
## Grasses may crowd the verge; that is what makes a road read as a road.
const GRASS_ROAD_CLEAR := 1.5

const TREE_SPACING := 8.5
const BUSH_SPACING := 5.0
const GRASS_SPACING := 2.3
const SCREE_SPACING := 6.0

## The master candidate lattice every family samples from.
##
## WHY A SHARED GRID: the first version evaluated MistvaleHeights per candidate
## per family — height_at, water_depth and slope_deg (four more height_at calls)
## for every one of ~95,000 cells, nine times over. 77 seconds per scene load,
## which is not a build time, it is a wall between the artist and the result.
##
## The field is static. So it is evaluated ONCE onto a lattice, and the nine
## families are then pure filters over numbers that are already in memory:
## 77 s -> ~3 s. Slope comes from lattice neighbours instead of four more field
## evaluations, which is where most of that saving is.
const GRID_STEP := 2.3

## Hard caps. A first-person frame budget is not negotiable and this layer is
## the one that can silently eat it.
const MAX_TREES := 9000
const MAX_BUSHES := 6000
const MAX_GRASS := 34000
const MAX_SCREE := 2600

## MultiMesh instances are bucketed into tiles of this size, one MultiMesh per
## tile per family.
##
## WHY: a MultiMesh is culled as a single object. One 4000-instance mesh for the
## whole region means every tree in Mistvale is submitted every frame regardless
## of where the camera is looking — in a first-person game that is 90% of the
## vegetation budget spent on trees behind the player's head. Bucketing by tile
## lets the existing frustum cull throw away the tiles the player is not in.
const TILE := 110.0


# =============================================================================
# Families
# =============================================================================
#
# [id, spacing, min_slope, max_slope, zone_fn, colour, scale range]
# Zone is expressed as a callable so the rule lives next to the plant that must
# obey it rather than in a switch twenty lines away.
const FAMILIES := [
	{
		"id": "broadleaf_a", "kind": "tree", "spacing": TREE_SPACING,
		"slope": [0.0, 24.0], "scale": [0.85, 1.30], "weight": 1.0,
		"zone": "valley", "bark": Color(0.584, 0.522, 0.443),
		"leaf": Color(0.522, 0.597, 0.467),
	},
	{
		"id": "broadleaf_b", "kind": "tree", "spacing": TREE_SPACING * 1.25,
		"slope": [0.0, 26.0], "scale": [0.75, 1.10], "weight": 0.8,
		"zone": "valley", "bark": Color(0.561, 0.501, 0.430),
		"leaf": Color(0.570, 0.605, 0.455),
	},
	{
		"id": "river_willow", "kind": "tree", "spacing": TREE_SPACING * 0.9,
		"slope": [0.0, 18.0], "scale": [0.80, 1.20], "weight": 1.5,
		"zone": "water", "bark": Color(0.570, 0.522, 0.455),
		"leaf": Color(0.542, 0.614, 0.501),
	},
	{
		"id": "mountain_pine", "kind": "tree", "spacing": TREE_SPACING * 0.85,
		"slope": [0.0, 33.0], "scale": [0.90, 1.45], "weight": 1.2,
		"zone": "mountain", "bark": Color(0.512, 0.461, 0.403),
		"leaf": Color(0.443, 0.522, 0.467),
	},
	{
		"id": "bamboo", "kind": "tree", "spacing": TREE_SPACING * 0.95,
		"slope": [0.0, 27.0], "scale": [0.80, 1.25], "weight": 0.85,
		"zone": "forest", "bark": Color(0.676, 0.684, 0.542),
		"leaf": Color(0.597, 0.665, 0.490),
	},
	{
		"id": "bush", "kind": "bush", "spacing": BUSH_SPACING,
		"slope": [0.0, 34.0], "scale": [0.55, 1.15], "weight": 1.0,
		"zone": "any", "bark": Color(0.547, 0.490, 0.417),
		"leaf": Color(0.532, 0.597, 0.455),
	},
	{
		"id": "river_bush", "kind": "bush", "spacing": BUSH_SPACING * 0.8,
		"slope": [0.0, 30.0], "scale": [0.60, 1.10], "weight": 1.4,
		"zone": "water", "bark": Color(0.542, 0.490, 0.424),
		"leaf": Color(0.575, 0.638, 0.501),
	},
	{
		"id": "tall_grass", "kind": "grass", "spacing": GRASS_SPACING,
		"slope": [0.0, 40.0], "scale": [0.70, 1.35], "weight": 1.0,
		"zone": "any", "bark": Color(0.584, 0.561, 0.430),
		"leaf": Color(0.601, 0.638, 0.490),
	},
	{
		"id": "reed", "kind": "grass", "spacing": GRASS_SPACING * 0.75,
		"slope": [0.0, 26.0], "scale": [0.85, 1.40], "weight": 1.6,
		"zone": "water", "bark": Color(0.618, 0.597, 0.467),
		"leaf": Color(0.630, 0.665, 0.517),
	},
]

var _rand := RandomNumberGenerator.new()
var _built := 0

# --- Master candidate lattice -------------------------------------------------
var _gnx := 0
var _gnz := 0
var _gh := PackedFloat32Array()      # ground height
var _gslope := PackedFloat32Array()  # degrees
var _greach := PackedFloat32Array()  # 0..1 detail band
var _gpath := PackedFloat32Array()   # metres to nearest road centreline
var _gopen := PackedFloat32Array()   # 1 - settlement - arena


func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_built = 0
	_build_grid()
	var t0 := Time.get_ticks_msec()

	if build_scree:
		_scree()
	if build_ground:
		for f in FAMILIES:
			if f["kind"] == "grass":
				_grass(f)
	if build_trees:
		for f in FAMILIES:
			if f["kind"] == "tree":
				_trees(f)
	if build_ground:
		for f in FAMILIES:
			if f["kind"] == "bush":
				_bushes(f)

	print("MistvaleFlora: %d meshes in %d ms"
		% [get_child_count(), Time.get_ticks_msec() - t0])


func _layer(n: String) -> Node3D:
	var node := Node3D.new()
	node.name = n
	add_child(node)
	return node


# =============================================================================
# Masks — the rules every instance must survive
# =============================================================================

## A per-cell hash, in 0..1.
##
## NOT MistvaleHeights.variation(). That function is a LOW-frequency field —
## its noise period is over 200 m, which is exactly what makes it right for
## breaking up large areas of albedo and exactly what makes it useless as a
## jitter. Used as a jitter it returns nearly the same value for every cell in
## a neighbourhood, so the "jittered grid" was not jittered at all and the
## aerial review came back with the trees standing in visible diagonal rows
## across the whole valley — the single most damning shot in the pass.
static func cell_hash(x: float, z: float) -> float:
	var s := sin(x * 127.1 + z * 311.7) * 43758.5453
	return s - floorf(s)


## 0..1 how much detail this point deserves. Only near a road or the water.
static func detail_reach(x: float, z: float) -> float:
	var d := minf(MistvaleHeights.path_distance(x, z),
		absf(z - MistvaleHeights.river_center_z(x)))
	return 1.0 - smoothstep(DETAIL_REACH * 0.55, DETAIL_REACH, d)


## 0..1 membership of the family's zone.
##
## ZONE IS A RULE AND NOT A COLOUR PICK. The east forest is bamboo because the
## masterplan says 青竹林; the mountain is pine because nothing else survives at
## 150 m; the waterline is willow and reed because that is how you READ water
## from 80 m away with no shader trick at all.
static func zone_factor(zone: String, x: float, z: float, y: float) -> float:
	var wet := absf(z - MistvaleHeights.river_center_z(x))
	match zone:
		"any":
			return 1.0
		"valley":
			# Town band and the lower valley floor, running on into the forest
			# edge. The first version stopped this at z = 92 while the bamboo
			# rule did not start until 118 — a 26 m treeless band straight
			# across the south of the region, which read as a logging scar.
			return (smoothstep(138.0, 118.0, z) * smoothstep(-146.0, -126.0, z)
				* smoothstep(6.0, 13.0, wet))
		"water":
			# The near margin: dense at the waterline, gone by 30 m.
			return smoothstep(30.0, 9.0, wet) * smoothstep(1.5, 5.0, wet)
		"mountain":
			return smoothstep(-118.0, -168.0, z)
		"forest":
			return smoothstep(92.0, 126.0, z)
	return 1.0


## Plants are cleared from settlement and from combat pads.
static func open_factor(x: float, z: float) -> float:
	var s := MistvaleHeights.settlement_factor(x, z)
	var pad := MistvaleHeights._arena_weight(x, z)
	return clampf(1.0 - s * 0.82 - pad * 0.55, 0.0, 1.0)


# =============================================================================
# Scatter
# =============================================================================

## One MultiMesh per family. Placement is a jittered grid, not a Poisson loop:
## a grid is O(cells) instead of O(candidates) and the jitter is enough that no
## row is legible from the ground.
func _trees(f: Dictionary) -> void:
	var pts := _scatter_points(f, TREE_ROAD_CLEAR, MAX_TREES, 0.92)
	_emit(f, pts, _tree_mesh(f), "Trees_" + String(f["id"]))


func _bushes(f: Dictionary) -> void:
	var pts := _scatter_points(f, ROAD_CLEAR, MAX_BUSHES, 0.40)
	_emit(f, pts, _bush_mesh(f), "Bush_" + String(f["id"]))


func _grass(f: Dictionary) -> void:
	var pts := _scatter_points(f, GRASS_ROAD_CLEAR, MAX_GRASS, 0.30)
	_emit(f, pts, _grass_mesh(f), "Grass_" + String(f["id"]))


func _scatter_points(
	f: Dictionary, road_clear: float, cap: int, density: float
) -> Array:
	var spacing: float = f["spacing"]
	var stride := maxi(1, int(round(spacing / GRID_STEP)))
	# A per-family offset into the lattice. Without it every family would pick
	# the same cells and the grass would grow in a visible lattice around the
	# base of every single tree.
	var off := int(String(f["id"]).hash() % 97)
	var out: Array = []
	var iz := off % stride
	while iz < _gnz:
		var ix := (off / stride) % stride
		while ix < _gnx:
			var i := iz * _gnx + ix
			ix += stride
			if out.size() >= cap:
				break
			if not _accept_cell(f, i, road_clear, density):
				continue
			# Jitter off the lattice, deterministically: a re-build must produce
			# the same forest, or before/after shots compare two forests.
			var gx := MistvaleHeights.MIN_X + float(ix - stride) * GRID_STEP
			var gz := MistvaleHeights.MIN_Z + float(iz) * GRID_STEP
			var jx := cell_hash(gx * 1.7 + 3.1, gz * 2.9 - 2.3)
			var jz := cell_hash(gx * 3.1 - 7.7, gz * 1.3 + 5.9)
			# Full spacing of jitter, not half: at half, the hash has to land in
			# the middle of its range every time or the rows come back.
			out.append(Vector2(gx + (jx - 0.5) * spacing * 1.8,
				gz + (jz - 0.5) * spacing * 1.8))
		iz += stride
		if out.size() >= cap:
			break
	return out


## Pure filter over the precomputed lattice — no field evaluation in here.
func _accept_cell(f: Dictionary, i: int, road_clear: float, density: float) -> bool:
	var reach := _greach[i]
	if reach < 0.02:
		return false
	# Underwater: nothing but reeds, and reeds only in the shallows.
	if _gh[i] < MistvaleHeights.RIVER_Y - 0.55:
		return false
	if _gpath[i] < road_clear:
		return false
	var slope := _gslope[i]
	var sr: Array = f["slope"]
	if slope > float(sr[1]):
		return false
	var gx := MistvaleHeights.MIN_X + float(i % _gnx) * GRID_STEP
	var gz := MistvaleHeights.MIN_Z + float(i / _gnx) * GRID_STEP
	var zone := zone_factor(String(f["zone"]), gx, gz, _gh[i])
	if zone < 0.02:
		return false
	# Slope also thins the stand: a tree on a 20 deg bank is the last one before
	# the scree, not a forest.
	var slope_fade := 1.0 - smoothstep(float(sr[1]) * 0.55, float(sr[1]), slope)
	var p := float(f["weight"]) * zone * reach * slope_fade * _gopen[i] * density
	# Grass responds to settlement differently: a village lawn is mown, not
	# removed, so grass keeps more of itself inside town than a tree does.
	if f["kind"] == "grass":
		p *= 1.0 + (1.0 - clampf(_gopen[i], 0.0, 1.0)) * 0.55
	# A per-cell hash, NOT the low-frequency variation field: a low-frequency
	# acceptance field does not thin a forest, it carves it into blocks hundreds
	# of metres across with a hard edge between them.
	var seed_v := cell_hash(gx * 0.91 + 3.1, gz * 0.77 - 2.3)
	return seed_v < clampf(p, 0.0, 1.0)


## Evaluate the field once onto the lattice.
func _build_grid() -> void:
	_gnx = int((MistvaleHeights.MAX_X - MistvaleHeights.MIN_X) / GRID_STEP) + 1
	_gnz = int((MistvaleHeights.MAX_Z - MistvaleHeights.MIN_Z) / GRID_STEP) + 1
	var n := _gnx * _gnz
	_gh.resize(n)
	_gslope.resize(n)
	_greach.resize(n)
	_gpath.resize(n)
	_gopen.resize(n)

	for iz in _gnz:
		var z := MistvaleHeights.MIN_Z + float(iz) * GRID_STEP
		for ix in _gnx:
			var x := MistvaleHeights.MIN_X + float(ix) * GRID_STEP
			_gh[iz * _gnx + ix] = MistvaleHeights.height_at(x, z)

	# Slope from lattice neighbours. Four extra height_at calls per cell was the
	# single most expensive thing in the original scatter; neighbours are free.
	for iz in _gnz:
		for ix in _gnx:
			var i := iz * _gnx + ix
			var xl := _gh[iz * _gnx + maxi(ix - 1, 0)]
			var xr := _gh[iz * _gnx + mini(ix + 1, _gnx - 1)]
			var zl := _gh[maxi(iz - 1, 0) * _gnx + ix]
			var zr := _gh[mini(iz + 1, _gnz - 1) * _gnx + ix]
			var dx := xr - xl
			var dz := zr - zl
			# Central difference: xl..xr span 2*GRID_STEP metres, so the
			# denominator is that span, not twice it. Getting this wrong halves
			# every gradient, which silently disabled the scree rule — 11 stones
			# on a mountain that should have been littered with them.
			var span := 2.0 * GRID_STEP * (1.0 if ix > 0 and ix < _gnx - 1 else 0.5)
			var gx2 := dx / span
			var gz2 := dz / span
			_gslope[i] = rad_to_deg(atan(sqrt(gx2 * gx2 + gz2 * gz2)))

	for iz in _gnz:
		var z := MistvaleHeights.MIN_Z + float(iz) * GRID_STEP
		for ix in _gnx:
			var x := MistvaleHeights.MIN_X + float(ix) * GRID_STEP
			var i := iz * _gnx + ix
			var pd := MistvaleHeights.path_distance(x, z)
			_gpath[i] = pd
			var wet := absf(z - MistvaleHeights.river_center_z(x))
			_greach[i] = 1.0 - smoothstep(
				DETAIL_REACH * 0.55, DETAIL_REACH, minf(pd, wet))
			_gopen[i] = clampf(1.0 - MistvaleHeights.settlement_factor(x, z) * 0.82
				- MistvaleHeights._arena_weight(x, z) * 0.55, 0.0, 1.0)


func _emit(f: Dictionary, pts: Array, mesh: ArrayMesh, name_: String) -> void:
	if pts.is_empty():
		return
	var sr: Array = f["scale"]

	# --- bucket by tile ----------------------------------------------------
	var tiles := {}
	for p in pts:
		var key := Vector2i(int(floorf(p.x / TILE)), int(floorf(p.y / TILE)))
		if not tiles.has(key):
			tiles[key] = []
		(tiles[key] as Array).append(p)

	var root := _layer(name_)
	for key in tiles:
		var bucket: Array = tiles[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = bucket.size()
		var i := 0
		for p in bucket:
			var x: float = p.x
			var z: float = p.y
			# PER-INSTANCE values must come from the per-cell hash. Driving them
			# from the low-frequency variation field gave every tree within
			# 200 m the same scale, the same spin and the same lean, which is
			# why the first aerial read as one grid of one cloned tree.
			var s := lerpf(float(sr[0]), float(sr[1]), cell_hash(x * 1.7, z * 1.7))
			var t := Transform3D()
			t = t.rotated(Vector3.UP, cell_hash(x * 0.31, z * 0.31) * TAU)
			# A tree that is perfectly vertical in every instance is a tree that
			# reads as an instanced object. A few degrees of lean is invisible
			# individually and decisive collectively.
			var lean := (cell_hash(x * 0.53 - 4.0, z * 0.53 + 8.0) - 0.5)
			t = t.rotated(Vector3.RIGHT, deg_to_rad(lean * 9.0))
			t = t.scaled(Vector3(s, s * (0.90 + cell_hash(z * 2.1, x * 2.1) * 0.20), s))
			t.origin = Vector3(x, MistvaleHeights.height_at(x, z) - 0.10, z)
			mm.set_instance_transform(i, t)
			i += 1
		var mi := MultiMeshInstance3D.new()
		mi.name = "%s_t%02d_%02d" % [name_, key.x + 8, key.y + 8]
		mi.multimesh = mm
		mi.material_override = _foliage_material(f)
		# Trees and bushes cast; grass does not. A forest floor with no shadows
		# under the trees is the flattest thing in the frame, and a grass field
		# casting 12,000 shadow casters is a frame budget nobody agreed to.
		var heavy: bool = String(f["kind"]) != "grass"
		mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if heavy
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		root.add_child(mi)
		_built += 1

	if build_collision and f["kind"] == "tree":
		_trunk_collision(pts, f, name_)


## One trimesh for every trunk in the family, not one body per tree.
##
## 2600 StaticBodies is a physics frame nobody gets back. A single
## ConcavePolygonShape3D built from hexagonal prisms is one shape, and a tree
## you can walk through is worse than no tree at all — in first person the trunk
## is at eye height and the lie is unmissable.
func _trunk_collision(pts: Array, f: Dictionary, name_: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sr: Array = f["scale"]
	var sides := 6
	for p in pts:
		var x: float = p.x
		var z: float = p.y
		var s := lerpf(float(sr[0]), float(sr[1]), MistvaleHeights.variation(x * 1.7, z * 1.7))
		var gy := MistvaleHeights.height_at(x, z)
		var r := 0.26 * s
		var top := _trunk_top(f) * s
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var b0 := Vector3(x + cos(a0) * r, gy, z + sin(a0) * r)
			var b1 := Vector3(x + cos(a1) * r, gy, z + sin(a1) * r)
			var t0 := Vector3(x + cos(a0) * r * 0.8, gy + top, z + sin(a0) * r * 0.8)
			var t1 := Vector3(x + cos(a1) * r * 0.8, gy + top, z + sin(a1) * r * 0.8)
			st.add_vertex(b0); st.add_vertex(b1); st.add_vertex(t1)
			st.add_vertex(b0); st.add_vertex(t1); st.add_vertex(t0)
	var mesh := st.commit()
	if mesh == null:
		return
	var body := StaticBody3D.new()
	body.name = name_ + "_Trunks"
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)


func _trunk_top(f: Dictionary) -> float:
	match String(f["id"]):
		"bamboo":
			return 5.0
		"mountain_pine":
			return 6.5
	return 3.2


func _foliage_material(f: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.88
	# Double sided: foliage is single-quad shells and a leaf you can see through
	# from behind is worse than the triangle saved.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# =============================================================================
# Scree — debris at the foot of steep ground
# =============================================================================
#
# The brief names this specifically (崖底：碎石增加). It is also the cheapest
# possible way to make a cliff read as a cliff: the ground at the bottom of one
# is never clean.
func _scree() -> void:
	var pts: Array = []
	var stride := maxi(1, int(round(SCREE_SPACING / GRID_STEP)))
	var iz := 0
	while iz < _gnz and pts.size() < MAX_SCREE:
		var ix := 0
		while ix < _gnx and pts.size() < MAX_SCREE:
			var i := iz * _gnx + ix
			ix += stride
			var gx := MistvaleHeights.MIN_X + float(ix - stride) * GRID_STEP
			var gz := MistvaleHeights.MIN_Z + float(iz) * GRID_STEP
			if _greach[i] < 0.05 or _gpath[i] < ROAD_CLEAR:
				continue
			var rocky := smoothstep(24.0, 38.0, _gslope[i])
			if rocky < 0.05:
				continue
			var jx := cell_hash(gx * 1.31 + 9.0, gz * 0.97 - 4.0)
			var jz := cell_hash(gx * 0.83 - 2.0, gz * 1.41 + 1.0)
			if jx < rocky * 0.55:
				pts.append(Vector2(gx + (jx - 0.5) * SCREE_SPACING * 1.7,
					gz + (jz - 0.5) * SCREE_SPACING * 1.7))
		iz += stride

	if pts.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _rock_mesh()
	mm.instance_count = pts.size()
	for i in pts.size():
		var p: Vector2 = pts[i]
		var s := 0.45 + cell_hash(p.x * 2.7, p.y * 2.7) * 1.5
		var t := Transform3D()
		t = t.rotated(Vector3.UP, cell_hash(p.x * 0.7, p.y * 0.7) * TAU)
		t = t.rotated(Vector3.RIGHT, (cell_hash(p.x * 1.9, p.y * 1.9) - 0.5) * 0.6)
		t = t.scaled(Vector3(s, s * 0.62, s))
		t.origin = Vector3(p.x, MistvaleHeights.height_at(p.x, p.y) - s * 0.18, p.y)
		mm.set_instance_transform(i, t)
	var mi := MultiMeshInstance3D.new()
	mi.name = "Scree"
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.646, 0.638, 0.622)
	mat.roughness = 0.95
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_layer("Scree").add_child(mi)


func _rock_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := [Vector2(0.0, 1.0), Vector2(0.70, 0.66), Vector2(0.92, 0.22), Vector2(0.60, 0.0)]
	var sides := 6
	for r in rings.size() - 1:
		var ra: Vector2 = rings[r]
		var rb: Vector2 = rings[r + 1]
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var ja := 0.78 + 0.22 * sin(a0 * 2.0 + float(r) * 1.7)
			var jb := 0.78 + 0.22 * sin(a1 * 2.0 + float(r) * 1.7)
			st.add_vertex(Vector3(cos(a0) * ra.x * ja, ra.y, sin(a0) * ra.x * ja))
			st.add_vertex(Vector3(cos(a1) * ra.x * jb, ra.y, sin(a1) * ra.x * jb))
			st.add_vertex(Vector3(cos(a1) * rb.x * jb, rb.y, sin(a1) * rb.x * jb))
			st.add_vertex(Vector3(cos(a0) * ra.x * ja, ra.y, sin(a0) * ra.x * ja))
			st.add_vertex(Vector3(cos(a1) * rb.x * jb, rb.y, sin(a1) * rb.x * jb))
			st.add_vertex(Vector3(cos(a0) * rb.x * ja, rb.y, sin(a0) * rb.x * ja))
	st.generate_normals()
	return st.commit()


# =============================================================================
# Mesh builders — one variant per instance, baked from a per-instance seed
# =============================================================================

func _tree_mesh(f: Dictionary) -> ArrayMesh:
	match String(f["id"]):
		"mountain_pine":
			return _pine(f)
		"bamboo":
			return _bamboo(f)
		"river_willow":
			return _willow(f)
	return _broadleaf(f)


func _broadleaf(f: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = f["bark"]
	var leaf: Color = f["leaf"]
	# A SHORT TRUNK, FOUR VISIBLE LIMBS, ROUNDED CROWNS.
	#
	# PASS 02 grew a 3.4 m bare pole with a 1.8 m tall canopy pancake balanced
	# on top of it. From EYE HEIGHT — which is where a first-person game is
	# always seen from, and therefore the only height that matters — the player
	# looked straight at the flat underside of that pancake. A stand of them
	# read as a field of dark mushrooms on sticks, which is exactly the
	# complaint. Both halves were wrong:
	#
	#   * the crown started at 4 m, above the eyeline, so there was nothing to
	#     see but pole and shadow;
	#   * `_lobe(squash = 0.86)` made a 4.1 m wide, 1.8 m tall disc. `squash` is
	#     the vertical half-axis — at 0.86 the "canopy" had a 2.3:1 flatness
	#     ratio, i.e. it was literally a pancake.
	#
	# Now: trunk to 2.5 m, four limbs carrying the crown out and up, and crowns
	# at squash 1.10-1.35 so they are roughly as deep as they are wide. The
	# limbs also break the silhouette, which is most of what makes a tree read
	# as a tree rather than as a lollipop.
	_trunk(st, bark, 2.5, 0.34, 0.20, 6)
	_limb(st, bark, Vector3(0.0, 1.95, 0.0), Vector3(1.15, 3.45, -0.40), 0.14)
	_limb(st, bark, Vector3(0.0, 1.95, 0.0), Vector3(-1.30, 3.05, 0.80), 0.13)
	_limb(st, bark, Vector3(0.0, 2.20, 0.0), Vector3(0.40, 3.90, 0.50), 0.11)
	_limb(st, bark, Vector3(0.0, 2.20, 0.0), Vector3(-0.35, 3.60, -1.05), 0.10)
	# Three lobes at different heights and offsets, not one ball: one ball is
	# the single most recognisable "procedural tree" silhouette there is.
	# The primary lobe gets the full ring count — it is the silhouette. The two
	# secondary lobes are the ones seen twenty-at-a-time.
	_lobe(st, leaf, Vector3(0.20, 3.15, -0.20), 1.85, 1.35, 0.78, 3, 7)
	_lobe(st, leaf, Vector3(-1.20, 2.70, 0.75), 1.30, 1.12, 0.80, 2, 6)
	_lobe(st, leaf, Vector3(1.25, 3.00, -0.60), 1.20, 1.08, 0.82, 2, 6)
	st.generate_normals()
	return st.commit()


func _willow(f: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = f["bark"]
	var leaf: Color = f["leaf"]
	# Low, wide, drooping: the crown sits BELOW eye level and spreads, which is
	# what makes a waterline read as a waterline from across the valley.
	#
	# It is also the one tree whose flatness is correct — a willow really is a
	# wide low dome — but at squash 1.05 over a 2.45 m radius the underside was
	# a ceiling. Kept wide, given depth, and dropped so the eye passes over the
	# top of it.
	_trunk(st, bark, 2.0, 0.36, 0.24, 6)
	_limb(st, bark, Vector3(0.0, 1.55, 0.0), Vector3(1.55, 2.35, 0.65), 0.15)
	_limb(st, bark, Vector3(0.0, 1.55, 0.0), Vector3(-1.45, 2.45, -0.80), 0.15)
	_lobe(st, leaf, Vector3(0.0, 2.55, 0.0), 2.35, 1.12, 1.00)
	_lobe(st, leaf, Vector3(1.40, 2.15, 0.60), 1.30, 0.92, 0.90)
	_lobe(st, leaf, Vector3(-1.30, 2.20, -0.75), 1.25, 0.90, 0.92)
	st.generate_normals()
	return st.commit()


func _pine(f: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = f["bark"]
	var leaf: Color = f["leaf"]
	_trunk(st, bark, 6.2, 0.26, 0.17, 5)
	# Stacked cones, widest low. A conifer is the one silhouette that must be
	# unmistakable at 300 m, because it is what tells the player the mountain
	# has begun.
	_cone(st, leaf, 1.90, 2.10, 2.05, 6)
	_cone(st, leaf, 3.35, 1.65, 2.00, 6)
	_cone(st, leaf, 4.70, 1.25, 1.90, 6)
	_cone(st, leaf, 5.85, 0.85, 1.70, 6)
	_cone(st, leaf, 6.80, 0.45, 1.40, 5)
	st.generate_normals()
	return st.commit()


func _bamboo(f: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = f["bark"]
	var leaf: Color = f["leaf"]
	# A clump, not a tree: bamboo is read as many thin verticals in one place.
	# The crown clusters are deliberately large relative to the cane: at 0.62 m
	# they did not exist at any distance a player stands at, and the grove came
	# back as a field of bare sticks.
	for i in 5:
		var a := TAU * float(i) / 5.0
		var r := 0.30 + MistvaleHeights.variation(a * 3.1, float(i)) * 0.34
		var hh := 4.2 + MistvaleHeights.variation(float(i) * 2.7, 1.3) * 2.6
		var ox := cos(a) * r
		var oz := sin(a) * r
		_cane(st, bark, ox, oz, hh, 0.075)
		_lobe(st, leaf, Vector3(ox, hh - 0.55, oz), 1.05, 1.35, 0.85, 2, 5)
		_lobe(st, leaf, Vector3(ox * 1.6, hh - 1.75, oz * 1.6), 0.80, 1.00, 0.85, 2, 5)
	st.generate_normals()
	return st.commit()


func _bush_mesh(f: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf: Color = f["leaf"]
	_lobe(st, leaf, Vector3(0.0, 0.62, 0.0), 0.95, 0.72, 1.0, 2, 6)
	_lobe(st, leaf, Vector3(0.58, 0.45, 0.30), 0.62, 0.52, 0.9, 2, 6)
	_lobe(st, leaf, Vector3(-0.50, 0.40, -0.36), 0.55, 0.46, 0.9, 2, 6)
	st.generate_normals()
	return st.commit()


func _grass_mesh(f: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf: Color = f["leaf"]
	var tall: bool = String(f["id"]) == "reed"
	var h := 1.15 if tall else 0.62
	# Five crossed blades. A billboard would be cheaper and would face the wrong
	# way the moment the sun moves behind it.
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.4
		_blade(st, leaf, a, h * (0.75 + 0.25 * sin(float(i) * 2.1)), 0.085 if tall else 0.115)
	st.generate_normals()
	return st.commit()


func _trunk(st: SurfaceTool, c: Color, h: float, r0: float, r1: float, sides: int) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		# Slightly irregular radius: a perfectly circular trunk reads as a tube.
		var j0 := 0.88 + 0.12 * sin(a0 * 2.0 + 1.1)
		var j1 := 0.88 + 0.12 * sin(a1 * 2.0 + 1.1)
		var b0 := Vector3(cos(a0) * r0 * j0, 0.0, sin(a0) * r0 * j0)
		var b1 := Vector3(cos(a1) * r0 * j1, 0.0, sin(a1) * r0 * j1)
		var t0 := Vector3(cos(a0) * r1 * j0, h, sin(a0) * r1 * j0)
		var t1 := Vector3(cos(a1) * r1 * j1, h, sin(a1) * r1 * j1)
		# Vertex colour darkens toward the base — the cheapest ambient occlusion
		# there is, and it is what stops a trunk looking like a pipe.
		var c0 := c * 0.70
		var c1 := c * 1.05
		st.set_color(c0); st.add_vertex(b0)
		st.set_color(c0); st.add_vertex(b1)
		st.set_color(c1); st.add_vertex(t1)
		st.set_color(c0); st.add_vertex(b0)
		st.set_color(c1); st.add_vertex(t1)
		st.set_color(c1); st.add_vertex(t0)


## A tapered limb from `from` to `to`.
##
## This exists because the silhouette is the whole job at the distances a tree
## is seen from, and a bare vertical pole has no silhouette: it is one line. Six
## triangles per limb, four limbs per broadleaf, is a 24-triangle cost for the
## difference between a lollipop and a tree.
func _limb(st: SurfaceTool, c: Color, from: Vector3, to: Vector3, r: float) -> void:
	var axis := (to - from).normalized()
	var up := Vector3(0.0, 1.0, 0.0)
	if absf(axis.dot(up)) > 0.98:
		up = Vector3(1.0, 0.0, 0.0)
	var sx := axis.cross(up).normalized()
	var sy := axis.cross(sx).normalized()
	var sides := 5
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := sx * cos(a0) + sy * sin(a0)
		var d1 := sx * cos(a1) + sy * sin(a1)
		var b0 := from + d0 * r
		var b1 := from + d1 * r
		var t0 := to + d0 * r * 0.55
		var t1 := to + d1 * r * 0.55
		st.set_color(c * 0.80); st.add_vertex(b0)
		st.set_color(c * 0.80); st.add_vertex(b1)
		st.set_color(c * 1.02); st.add_vertex(t1)
		st.set_color(c * 0.80); st.add_vertex(b0)
		st.set_color(c * 1.02); st.add_vertex(t1)
		st.set_color(c * 1.02); st.add_vertex(t0)


func _cane(st: SurfaceTool, c: Color, ox: float, oz: float, h: float, r: float) -> void:
	var sides := 5
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := Vector3(ox + cos(a0) * r, 0.0, oz + sin(a0) * r)
		var b1 := Vector3(ox + cos(a1) * r, 0.0, oz + sin(a1) * r)
		var t0 := Vector3(ox + cos(a0) * r * 0.85, h, oz + sin(a0) * r * 0.85)
		var t1 := Vector3(ox + cos(a1) * r * 0.85, h, oz + sin(a1) * r * 0.85)
		st.set_color(c * 0.8); st.add_vertex(b0)
		st.set_color(c * 0.8); st.add_vertex(b1)
		st.set_color(c); st.add_vertex(t1)
		st.set_color(c * 0.8); st.add_vertex(b0)
		st.set_color(c); st.add_vertex(t1)
		st.set_color(c); st.add_vertex(t0)


## A flattened, faceted blob. Facets, not a sphere: a smooth canopy catches the
## light like plastic and reads as a balloon.
##
## `rings` / `sides` are parameters because a canopy and a bush clump are not
## the same budget. A bush is seen in the middle of a crowd of bushes, twenty in
## one frame; a tree canopy is the silhouette of the tree. Spending 42 triangles
## on a bush put 277k triangles into the shrub layer alone.
func _lobe(
	st: SurfaceTool, c: Color, at: Vector3, r: float, squash: float, jitter: float,
	rings: int = 3, sides: int = 7
) -> void:
	# Typed: an untyped nested Array makes every indexed read a Variant, and
	# GDScript refuses to infer a type for `var a := pts[ri][si]`.
	var pts: Array[PackedVector3Array] = []
	for ri in rings + 1:
		var v := float(ri) / float(rings)
		var phi := v * PI
		var row := PackedVector3Array()
		for si in sides:
			var th := TAU * float(si) / float(sides)
			var j := 1.0 + (MistvaleHeights.variation(th * 4.7 + float(ri), float(si) * 2.3) - 0.5) * jitter
			var rr := sin(phi) * r * j
			row.append(at + Vector3(cos(th) * rr, cos(phi) * squash * r * j * 0.5 + squash * r * 0.5,
				sin(th) * rr))
		pts.append(row)
	for ri in rings:
		for si in sides:
			var s2 := (si + 1) % sides
			var a := pts[ri][si]
			var b := pts[ri][s2]
			var cc := pts[ri + 1][s2]
			var d := pts[ri + 1][si]
			# Top of the lobe catches light, underside is in shadow. Baked, so
			# it costs nothing at runtime.
			#
			# 0.62 at the bottom was too dark for the only angle that matters:
			# from eye height the player sees the UNDERSIDE of every nearby
			# canopy, so the base shade is what a tree actually looks like when
			# you walk under it. At 0.62 that was a black ceiling. 0.74 keeps
			# the form readable without pretending the underside is lit.
			var shade := 0.74 + 0.26 * (float(ri) / float(rings))
			st.set_color(c * shade); st.add_vertex(a)
			st.set_color(c * shade); st.add_vertex(b)
			st.set_color(c * shade); st.add_vertex(cc)
			st.set_color(c * shade); st.add_vertex(a)
			st.set_color(c * shade); st.add_vertex(cc)
			st.set_color(c * shade); st.add_vertex(d)


func _cone(
	st: SurfaceTool, c: Color, y0: float, r: float, h: float, sides: int
) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := Vector3(cos(a0) * r, y0, sin(a0) * r)
		var b1 := Vector3(cos(a1) * r, y0, sin(a1) * r)
		var tip := Vector3(0.0, y0 + h, 0.0)
		var shade := 0.58 + 0.30 * (0.5 + 0.5 * sin(a0))
		st.set_color(c * shade); st.add_vertex(b0)
		st.set_color(c * shade); st.add_vertex(b1)
		st.set_color(c * (shade + 0.28)); st.add_vertex(tip)


func _blade(st: SurfaceTool, c: Color, a: float, h: float, w: float) -> void:
	var dx := cos(a) * w
	var dz := sin(a) * w
	var bend := 0.22 * h
	var b0 := Vector3(-dx, 0.0, -dz)
	var b1 := Vector3(dx, 0.0, dz)
	var t0 := Vector3(-dx * 0.5 + bend, h, -dz * 0.5)
	var t1 := Vector3(dx * 0.5 + bend, h, dz * 0.5)
	st.set_color(c * 0.62); st.add_vertex(b0)
	st.set_color(c * 0.62); st.add_vertex(b1)
	st.set_color(c); st.add_vertex(t1)
	st.set_color(c * 0.62); st.add_vertex(b0)
	st.set_color(c); st.add_vertex(t1)
	st.set_color(c); st.add_vertex(t0)
