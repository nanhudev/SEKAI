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

## The verge band, and the reason it exists.
##
## GEOMETRY PASS 01. The road had no edge. `GRASS_ROAD_CLEAR` kept every blade
## 1.5 m from the centreline and the lattice candidate is 2.3 m, so the first
## grass a player could ever see stood 4 m off the tread — and the transition
## from "packed road" to "field" was a shader gradient with nothing growing in
## it. A road that has been walked for a century does not meet a field at a
## soft-edged line in a colour ramp; it frays: bare tread, scuffed dirt, loose
## stones, then isolated tufts, then grass. That frays is geometry.
##
## VERGE_SPACING is deliberately SMALLER than GRID_STEP — it is not a candidate
## spacing, it is only used for the jitter amplitude. Density in the band comes
## from `per_cell` (see FAMILIES and `_scatter_points`), because the candidate
## lattice is capped at one point per cell and one tuft per 5.3 m2 is not a
## verge, it is a garnish.
const VERGE_SPACING := 1.35
const STONE_SPACING := 3.0
const ROCK_SPACING := 7.5
const MOUND_SPACING := 4.8

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
## Added by GEOMETRY PASS 01. Each of these is a MULTIMESH INSTANCE count, and
## each instance is a CLUSTER (a tuft, a heap of stones, a formation of three to
## five boulders) rather than a single blade or pebble — so the polygon cost per
## instance is 16-80 triangles against the old 10, and the caps are set from
## that. Measured before the pass: 16,508 instances of vegetation in the whole
## region. These four families add roughly 22,000 instances, which is affordable
## only because grass does not cast shadows and the whole layer is bucketed into
## 110 m tiles for frustum culling.
const MAX_VERGE := 12000
const MAX_STONE := 5200
const MAX_ROCK := 2400
const MAX_MOUND := 2200

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
#
# OPTIONAL KEYS
#   verge    this family is the road's frayed edge; density comes from how far
#            the road paint has faded, and it is refused on the packed tread.
#   edge     favours the road corridor but is allowed on the tread itself.
#   per_cell instances emitted per accepted lattice cell (default 1). The
#            lattice cannot go below GRID_STEP, so this is the only way to get
#            a band denser than one object per 5.3 m2.
#   sink     metres the instance is pushed below the sampled ground height.
#   cast     whether the layer casts shadows (default: everything but grass).
#
# SCALE RANGES ARE AGE. Every tree in PASS 02 was between 0.75x and 1.3x of the
# same prototype, which is a nursery, not a forest, and it is a large part of
# why a stand of them read as instanced objects. The ranges below run roughly
# 0.55x to 1.55x so a frame contains saplings and old trees.
const FAMILIES := [
	{
		"id": "broadleaf_a", "kind": "tree", "spacing": TREE_SPACING,
		"slope": [0.0, 24.0], "scale": [0.62, 1.42], "weight": 1.0,
		"zone": "valley", "bark": Color(0.584, 0.522, 0.443),
		"leaf": Color(0.522, 0.597, 0.467),
	},
	{
		"id": "broadleaf_b", "kind": "tree", "spacing": TREE_SPACING * 1.25,
		"slope": [0.0, 26.0], "scale": [0.55, 1.25], "weight": 0.8,
		"zone": "valley", "bark": Color(0.561, 0.501, 0.430),
		"leaf": Color(0.570, 0.605, 0.455),
	},
	{
		"id": "river_willow", "kind": "tree", "spacing": TREE_SPACING * 0.9,
		"slope": [0.0, 18.0], "scale": [0.68, 1.32], "weight": 1.5,
		"zone": "water", "bark": Color(0.570, 0.522, 0.455),
		"leaf": Color(0.542, 0.614, 0.501),
	},
	{
		"id": "mountain_pine", "kind": "tree", "spacing": TREE_SPACING * 0.85,
		"slope": [0.0, 33.0], "scale": [0.72, 1.55], "weight": 1.2,
		"zone": "mountain", "bark": Color(0.512, 0.461, 0.403),
		"leaf": Color(0.443, 0.522, 0.467),
	},
	{
		"id": "bamboo", "kind": "tree", "spacing": TREE_SPACING * 0.95,
		"slope": [0.0, 27.0], "scale": [0.70, 1.30], "weight": 0.85,
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
		"slope": [0.0, 40.0], "scale": [0.70, 1.45], "weight": 1.0,
		"zone": "any", "corridor": true, "bark": Color(0.584, 0.561, 0.430),
		"leaf": Color(0.601, 0.638, 0.490),
	},
	{
		"id": "reed", "kind": "grass", "spacing": GRASS_SPACING * 0.75,
		"slope": [0.0, 26.0], "scale": [0.85, 1.40], "weight": 1.6,
		"zone": "water", "bark": Color(0.618, 0.597, 0.467),
		"leaf": Color(0.630, 0.665, 0.517),
	},
	# --- GEOMETRY PASS 01 -----------------------------------------------------
	{
		# The road's frayed edge. Zone is "any" because a verge is not a
		# habitat — it is whatever survives being walked past. The band rule
		# lives in `_accept_cell` under the `verge` flag.
		"id": "verge_grass", "kind": "grass", "spacing": VERGE_SPACING,
		"slope": [0.0, 44.0], "scale": [0.80, 1.35], "weight": 1.0,
		"zone": "any", "verge": true, "per_cell": 4,
		"bark": Color(0.584, 0.561, 0.430),
		"leaf": Color(0.566, 0.617, 0.452),
	},
	{
		# Loose stones. Small, in heaps of three to five, everywhere the road
		# corridor is — including on the tread, because a stone IN a road is
		# the single cheapest way to say the road is 400 years old.
		"id": "stone", "kind": "stone", "spacing": STONE_SPACING,
		"slope": [0.0, 46.0], "scale": [0.55, 1.30], "weight": 1.0,
		"zone": "any", "edge": true, "per_cell": 2, "sink": 0.06, "cast": false,
		"leaf": Color(0.612, 0.598, 0.576),
	},
	{
		# Boulder formations. Slope-gated, because rock does not lie around on
		# flat land — it is what the flat land was cut out of. 20-45% of every
		# chunk is under the ground: a rock sitting ON the terrain is a prop,
		# a rock growing OUT of it is terrain.
		"id": "rock", "kind": "rock", "spacing": ROCK_SPACING,
		"slope": [7.0, 46.0], "scale": [0.70, 1.15], "weight": 1.0,
		"zone": "any", "per_cell": 1, "sink": 0.0, "cast": true, "corridor": true,
		"clump": 30.0, "slope_size": true,
		"leaf": Color(0.588, 0.578, 0.556),
	},
	{
		# Broken ground, soil heaps, the spoil beside a cut. The MEDIUM scale
		# the terrain shader structurally cannot carry: a heightfield with a
		# 3 m mesh has no 1 m bump in it at all.
		"id": "mound", "kind": "mound", "spacing": MOUND_SPACING,
		"slope": [2.0, 30.0], "scale": [0.70, 1.30], "weight": 0.9,
		"zone": "any", "edge": true, "per_cell": 1, "sink": 0.20, "cast": false,
		"clump": 22.0,
		"leaf": Color(0.508, 0.455, 0.372),
	},
]

var _rand := RandomNumberGenerator.new()
var _built := 0
var _mat_cache := {}

# --- Master candidate lattice -------------------------------------------------
var _gnx := 0
var _gnz := 0
var _gh := PackedFloat32Array()      # ground height
var _gslope := PackedFloat32Array()  # degrees
var _greach := PackedFloat32Array()  # 0..1 detail band
var _gpath := PackedFloat32Array()   # metres to nearest road centreline
var _gtread := PackedFloat32Array()  # 0..1 packed road paint (MistvaleHeights.path_factor)
var _gopen := PackedFloat32Array()   # 1 - settlement - arena


func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_built = 0
	_mat_cache.clear()
	_build_grid()
	var t0 := Time.get_ticks_msec()

	if build_scree:
		_scree()
	if build_ground:
		for f in FAMILIES:
			match String(f["kind"]):
				"grass":
					_grass(f)
				"bush":
					_bushes(f)
				# --- GEOMETRY PASS 01 ---------------------------------------
				# Clusters, not instances. One stone is a speck at 20 m; a
				# heap of four stones is a feature. Same for boulders: the
				# asset is the FORMATION, so the scatter never has to be
				# trusted to accidentally group them.
				"stone":
					_emit(f, _scatter_points(f, ROAD_CLEAR, MAX_STONE, 0.09),
						_stone_meshes(), "Stones")
				"rock":
					_emit(f, _scatter_points(f, ROAD_CLEAR, MAX_ROCK, 0.62),
						_rock_meshes(), "Rocks")
				"mound":
					_emit(f, _scatter_points(f, ROAD_CLEAR, MAX_MOUND, 0.95),
						_mound_meshes(), "Mounds")
	if build_trees:
		for f in FAMILIES:
			if f["kind"] == "tree":
				_trees(f)

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


## Smooth value noise on a coarse lattice, in 0..1, for CLUMPING.
##
## WHY THIS EXISTS. Rock has three ways to be scattered and only one of them
## looks like geology:
##
##   per-cell `cell_hash`  -> an even sprinkle at one cell's resolution. This
##                            is not a clump, it is noise, and the eye reads it
##                            as a carpet: 1,448 evenly spaced boulders across
##                            a hillside is a pattern, not a formation.
##   `variation()`         -> a 200 m field. Too long to clump anything a
##                            player standing on the road can perceive; on a
##                            100 m view it is a constant.
##   THIS                  -> features ~`period` metres across, smooth between
##                            them, and deterministic on rebuild (same hash
##                            family as everything else) so a before/after pair
##                            still compares the same world.
##
## The lattice corners are interpolated with a smoothstep, NOT taken as blocks.
## Reading the coarse hash directly would stamp `period`-metre squares with hard
## edges — the exact artefact `_accept_cell` warns about further down.
func _clump(x: float, z: float, period: float) -> float:
	var fx := x / period
	var fz := z / period
	var xi := floorf(fx)
	var zi := floorf(fz)
	var u := fx - xi
	var v := fz - zi
	u = u * u * (3.0 - 2.0 * u)
	v = v * v * (3.0 - 2.0 * v)
	var h00 := cell_hash(xi * 1.7 + 3.3, zi * 2.7 - 1.1)
	var h10 := cell_hash((xi + 1.0) * 1.7 + 3.3, zi * 2.7 - 1.1)
	var h01 := cell_hash(xi * 1.7 + 3.3, (zi + 1.0) * 2.7 - 1.1)
	var h11 := cell_hash((xi + 1.0) * 1.7 + 3.3, (zi + 1.0) * 2.7 - 1.1)
	return lerpf(lerpf(h00, h10, u), lerpf(h01, h11, u), v)


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
	_emit(f, pts, _tree_meshes(f), "Trees_" + String(f["id"]))


func _bushes(f: Dictionary) -> void:
	var pts := _scatter_points(f, ROAD_CLEAR, MAX_BUSHES, 0.40)
	_emit(f, pts, _bush_meshes(f), "Bush_" + String(f["id"]))


func _grass(f: Dictionary) -> void:
	var cap: int = MAX_VERGE if f.get("verge", false) else MAX_GRASS
	# The verge band wants a higher base acceptance than open ground: most of
	# its cells are in the fringe anyway, and the modifier in `_accept_cell` is
	# what decides the shape of the band, not this number.
	var density: float = 0.60 if f.get("verge", false) else 0.30
	var pts := _scatter_points(f, GRASS_ROAD_CLEAR, cap, density)
	_emit(f, pts, _grass_meshes(f), "Grass_" + String(f["id"]))


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
	# A SOFT limit, not the cap. The hard cap is applied after the sweep, by
	# deterministic thinning — see the end of this function.
	#
	# Breaking out of the sweep at the cap truncates by ITERATION ORDER, and the
	# iteration order is z. So hitting a cap does not "drop the least important
	# instances", it deletes everything north of some line: half the region gets
	# stones and the other half gets none, with a perfectly straight edge between
	# them. GEOMETRY PASS 01 hit this on all three new families at once (stones,
	# mounds and rocks all came back exactly at their caps) and it would have
	# read as a z-dependent bug in the terrain, not in the scatterer.
	var soft := cap * 4
	var iz := off % stride
	while iz < _gnz:
		var ix := (off / stride) % stride
		while ix < _gnx:
			var i := iz * _gnx + ix
			ix += stride
			if out.size() >= soft:
				break
			if not _accept_cell(f, i, road_clear, density):
				continue
			# Jitter off the lattice, deterministically: a re-build must produce
			# the same forest, or before/after shots compare two forests.
			var gx := MistvaleHeights.MIN_X + float(ix - stride) * GRID_STEP
			var gz := MistvaleHeights.MIN_Z + float(iz) * GRID_STEP
			# PER-CELL INSTANCE COUNT. The candidate lattice is one point per
			# 2.3 m cell, so the densest a band can be by spacing alone is one
			# object per 5.3 m2 — which for a 0.5 m tuft is a garnish, not a
			# verge. Emitting k instances per accepted cell, each with its own
			# hash offset, is the only way to get a band denser than the
			# lattice without shrinking GRID_STEP (whose cost is quadratic).
			var per: int = int(f.get("per_cell", 1))
			for k in per:
				var ks := float(k) * 13.7 + 4.9
				var jx := cell_hash(gx * 1.7 + 3.1 + ks, gz * 2.9 - 2.3 - ks)
				var jz := cell_hash(gx * 3.1 - 7.7 + ks, gz * 1.3 + 5.9 + ks)
				# Full spacing of jitter, not half: at half, the hash has to
				# land in the middle of its range every time or the rows come
				# back. For the verge families `spacing` is smaller than the
				# lattice, which is the point — it keeps the sub-instances of
				# one cell together instead of smearing them a cell apart.
				out.append(Vector2(gx + (jx - 0.5) * spacing * 1.8,
					gz + (jz - 0.5) * spacing * 1.8))
				if out.size() >= soft:
					break
			if out.size() >= soft:
				break
		iz += stride
		if out.size() >= soft:
			break
	if out.size() <= cap:
		return out
	# Deterministic thinning, applied to a uniformly-swept candidate set.
	#
	# Every candidate keeps a hash-driven chance of surviving, so the survivors
	# stay evenly spread across the whole region instead of being the first
	# `cap` in z order. Same hash family as everything else in this file, so a
	# rebuild thins identically and a before/after pair still compares the same
	# world.
	var keep := float(cap) / float(out.size())
	var thinned: Array = []
	for p in out:
		if cell_hash(p.x * 7.13 + 0.7, p.y * 4.31 - 1.9) < keep:
			thinned.append(p)
	return thinned


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

	# THE SETTLEMENT MASK IS FOR TREES. IT IS NOT FOR GROUND.
	#
	# PASS 02 applied one `_gopen` to every family, which is right for a tree —
	# you clear the village of trees — and wrong for every family that IS the
	# ground. Measured in the Hero Zone, which is the guild terrace, where
	# settlement_factor is ~1: the mask left 18% of the stones, 18% of the
	# boulders, 18% of the mounds and 18% of the verge tufts. The entire first
	# geometry pass was therefore invisible in exactly the hundred metres the
	# brief asks to be finished first, and the frame looked unchanged for a
	# reason that had nothing to do with the geometry being wrong.
	#
	# A village is not a car park. Its streets have stones in them, its verges
	# have grass on them, and its slopes have whatever the slope always had.
	# What settlement removes is TREES and, to a lesser degree, bushes.
	var openness := _gopen[i]
	var open_resp := openness
	match String(f["kind"]):
		"stone", "rock", "mound":
			open_resp = 0.62 + openness * 0.38
		"grass":
			# A village lawn is mown, not removed.
			open_resp = 0.34 + openness * 0.66
	var p := float(f["weight"]) * zone * reach * slope_fade * open_resp * density

	# --- The road's frayed edge -------------------------------------------
	#
	# GEOMETRY PASS 01. `_gtread` is MistvaleHeights.path_factor — 1 on the
	# packed tread, 0 out in the open. THE VERGE IS THE BAND IN BETWEEN, and
	# until this pass nothing was ever placed in it, which is why the road had
	# a painted edge and no geometry.
	#
	# The two ramps are deliberately asymmetric. The outer one (fringe -> 0 by
	# tread 0.06) makes the verge fade into the field instead of stopping at a
	# line; the inner one (fringe -> 0 at tread 0.80) is what keeps grass off
	# the tread itself. For the main street — half-width 3.6 m, verge to
	# 9.5 m — that window is roughly 4.0 m to 9.3 m from the centreline, i.e.
	# exactly the scuffed strip the shader has been painting since PASS 02 and
	# nothing has been standing in.
	var tread := _gtread[i]
	var fringe := smoothstep(0.80, 0.45, tread) * (1.0 - smoothstep(0.34, 0.06, tread))
	if f.get("verge", false):
		# Nothing at all on the packed tread. Not thinned — refused: a tuft in
		# the middle of a street is worse than no verge at all.
		if tread > 0.80:
			return false
		# sqrt, not the raw band: `fringe` only reaches 1 in the middle of the
		# verge, so a linear ramp made a dense line down the centre of the band
		# with bare ground either side of it. The square root widens the part of
		# the band that saturates, so the verge is a verge and not a hedgerow.
		p *= 0.05 + sqrt(fringe) * 9.0
	elif f.get("edge", false):
		# A PREFERENCE, not a band. `fringe` is 0 both on the tread and out in
		# open ground, so this reads "0.5x everywhere, 2x in the verge" — which
		# is what loose stones actually do: heaviest where the road is breaking
		# up, present but sparse in the field.
		p *= 0.50 + fringe * 1.6
	elif f.get("corridor", false):
		# For things that are only worth polygons where the player is. The
		# detail band is 95 m wide on both sides — 19 hectares per kilometre of
		# road — and a boulder formation at 80 m costs the same as one at 8 m
		# while contributing nothing a player standing on the road can see. The
		# corridor is 40 m, which is past the point where a 1.5 m rock is more
		# than a few pixels.
		p *= 0.12 + (1.0 - smoothstep(7.0, 42.0, _gpath[i])) * 1.7
	# --- CLUMPING: the difference between a scatter and a formation ---------
	#
	# Only the two families that are supposed to read as GEOLOGY rather than as
	# planting opt in with `clump`. A smooth ~30 m field is thresholded hard, so
	# the family is dense at the centre of a patch and absent between patches —
	# which is what rock and broken ground actually do, and what a uniform
	# density gradient never does no matter how it is tuned.
	#
	# Trees deliberately do NOT opt in. Thinning a forest with a field of this
	# period puts a visible line around every clearing.
	var clump_period: float = float(f.get("clump", 0.0))
	if clump_period > 0.0:
		p *= lerpf(0.10, 1.0,
			smoothstep(0.40, 0.70, _clump(gx, gz, clump_period)))
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
	_gtread.resize(n)
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
			# The packed-road paint, which knows each road's OWN half-width and
			# verge width. Needed because GRID_STEP is 2.3 m and the main street
			# is 7.2 m wide: a lattice cannot resolve a verge by distance alone,
			# it needs the field to say where the tread stops.
			_gtread[i] = MistvaleHeights.path_factor(x, z)
			var wet := absf(z - MistvaleHeights.river_center_z(x))
			_greach[i] = 1.0 - smoothstep(
				DETAIL_REACH * 0.55, DETAIL_REACH, minf(pd, wet))
			_gopen[i] = clampf(1.0 - MistvaleHeights.settlement_factor(x, z) * 0.82
				- MistvaleHeights._arena_weight(x, z) * 0.55, 0.0, 1.0)


## `mesh` is either a single ArrayMesh or an Array of them.
##
## MULTIPLE VARIANTS COST NOTHING. Every instance still uses exactly one mesh, so
## N variants is N meshes and the same instance count — the triangle total does
## not move. What it buys is that a stand of twenty trees is twenty trees and not
## the same tree twenty times, which is the loudest remaining "procedural" tell
## once the individual asset is decent.
func _emit(f: Dictionary, pts: Array, mesh, name_: String) -> void:
	if pts.is_empty():
		return
	var meshes: Array = mesh if mesh is Array else [mesh]
	var vn := meshes.size()
	if vn == 0:
		return
	var sr: Array = f["scale"]
	var kind := String(f["kind"])
	var sink: float = float(f.get("sink", 0.10))
	# The cast default is the old rule: everything but grass. Families that are
	# partly bury themselves opt out explicitly (see `cast` in FAMILIES) —
	# ground-hugging sheets must not cast, because the terrain has
	# `cast_shadow = OFF` and anything below grade that casts is projected from
	# a receiver that is, in the real scene, uphill of it. That is the ghost
	# shadow that once dropped a street 37 m from the guild hall to 21.
	var cast: bool = bool(f.get("cast", kind != "grass"))
	# STEEPER GROUND -> BIGGER ROCK (addendum §9). Rock is not sprinkled evenly
	# across a slope: it is what the slope is made of, and where the terrain
	# breaks hardest the pieces that survive the break are the big ones. Applied
	# as a per-instance multiplier on the family's scale range, so the size
	# ordering survives whatever the range is set to.
	#
	# Costs four more `height_at` calls per instance, and only for families that
	# ask for it — the rock layer is ~1,400 instances, not 95,000.
	var slope_size: bool = bool(f.get("slope_size", false))
	var lean_deg := 9.0
	match kind:
		"rock":
			lean_deg = 24.0
		"stone":
			lean_deg = 30.0
		"mound":
			lean_deg = 5.0
		"grass":
			lean_deg = 13.0

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
		# Split the tile by variant before building anything, so each MultiMesh
		# holds one mesh. Assigning by hash and not by index: the assignment has
		# to be stable across rebuilds or a before/after pair compares two
		# different forests.
		var groups: Array = []
		groups.resize(vn)
		for gi in vn:
			groups[gi] = []
		for p in bucket:
			var vi := int(cell_hash(p.x * 5.13 + 1.7, p.y * 3.71 - 0.9) * float(vn)) % vn
			(groups[vi] as Array).append(p)
		for vi in vn:
			var group: Array = groups[vi]
			if group.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[vi]
			mm.instance_count = group.size()
			var i := 0
			for p in group:
				var x: float = p.x
				var z: float = p.y
				# PER-INSTANCE values must come from the per-cell hash. Driving them
				# from the low-frequency variation field gave every tree within
				# 200 m the same scale, the same spin and the same lean, which is
				# why the first aerial read as one grid of one cloned tree.
				var s := lerpf(float(sr[0]), float(sr[1]), cell_hash(x * 1.7, z * 1.7))
				if slope_size:
					s *= 0.78 + 0.62 * smoothstep(
						8.0, 38.0, MistvaleHeights.slope_deg(x, z))
				var t := Transform3D()
				t = t.rotated(Vector3.UP, cell_hash(x * 0.31, z * 0.31) * TAU)
				# A tree that is perfectly vertical in every instance is a tree that
				# reads as an instanced object. A few degrees of lean is invisible
				# individually and decisive collectively. Rock leans far harder —
				# a boulder formation all standing level is a pile of boxes.
				var lean := (cell_hash(x * 0.53 - 4.0, z * 0.53 + 8.0) - 0.5)
				t = t.rotated(Vector3.RIGHT, deg_to_rad(lean * lean_deg))
				t = t.scaled(Vector3(s, s * (0.90 + cell_hash(z * 2.1, x * 2.1) * 0.20), s))
				t.origin = Vector3(x, MistvaleHeights.height_at(x, z) - sink, z)
				mm.set_instance_transform(i, t)
				i += 1
			var mi := MultiMeshInstance3D.new()
			mi.name = "%s_v%d_t%02d_%02d" % [name_, vi, key.x + 8, key.y + 8]
			mi.multimesh = mm
			mi.material_override = _foliage_material(f)
			mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			root.add_child(mi)
			_built += 1

	if build_collision and kind == "tree":
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
	var key := String(f["id"])
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.88
	# Double sided only where it is needed. Foliage is single-quad shells and a
	# leaf you can see through from behind is worse than the triangle saved — but
	# a stone, a boulder and a mound are CLOSED volumes, and rendering both faces
	# of a closed volume pays the fill cost twice for geometry that is never
	# visible. GEOMETRY PASS 01 put ~8,300 closed instances on the map; they get
	# back-face culling, and the ground layer keeps its budget for things the
	# player can actually see.
	var kind := String(f["kind"])
	if kind == "tree" or kind == "bush" or kind == "grass":
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		m.cull_mode = BaseMaterial3D.CULL_BACK
	# One material per family, not one per tile per variant. With variants that
	# was 3x the material count for no benefit — the family is the only thing
	# that decides the material, and every instance in it shares one.
	_mat_cache[key] = m
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

func _tree_meshes(f: Dictionary) -> Array:
	var out: Array = []
	for v in 3:
		out.append(_tree_mesh(f, v))
	return out


func _tree_mesh(f: Dictionary, v: int) -> ArrayMesh:
	match String(f["id"]):
		"mountain_pine":
			return _pine(f, v)
		"bamboo":
			return _bamboo(f, v)
		"river_willow":
			return _willow(f, v)
	return _broadleaf(f, v)


## A broadleaf, built as a carrier and a crowd.
##
## WHAT WAS WRONG WITH THREE LOBES. PASS 02 and PASS 03 both built the crown
## from three overlapping lobes of radius 1.2-1.85 with a per-vertex radius
## jitter of 0.78-0.82. That combination is not "an irregular canopy", it is ONE
## crumpled dome: three spheres of nearly equal size at nearly equal height are
## a sphere, and at ±39% radius jitter every facet becomes a fold. Photographed
## from the forest road (the only angle a first-person camera has — a low one)
## it came back as a FLAT CRUMPLED PARASOL on a bare pole, held above the
## player's head with a bright lit top and a dark rim, and it is the most
## instantly recognisable "procedural tree" there is.
##
## So: a longer trunk, five limbs that actually carry the crown out and up, and
## a crown of SIX TO EIGHT SMALL LOBES at four different heights with a jitter
## of 0.34. The silhouette then has notches in it. A notch is the whole
## difference between a tree and a balloon, because it is where the sky shows
## through, and it costs no extra polygons — the same lobes, made smaller and
## spread out.
func _broadleaf(f: Dictionary, v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = f["bark"]
	var leaf: Color = f["leaf"]
	var tw := float(v) * 2.31
	_trunk(st, bark, 2.60, 0.31, 0.19, 6)
	var fork := Vector3(0.0, 2.25, 0.0)
	for i in 5:
		var a := TAU * float(i) / 5.0 + tw
		var reach := 1.00 + 0.72 * cell_hash(float(i) * 2.3 + tw, 1.7)
		var rise := 1.00 + 0.90 * cell_hash(float(i) * 3.1, tw + 2.2)
		_limb(st, bark, fork, Vector3(cos(a) * reach, 3.25 + rise, sin(a) * reach), 0.115)
	# One lobe sits LOW and out to one side. That single lobe is what stops the
	# tree reading as a lollipop at a glance, because it breaks the symmetry the
	# eye uses to identify an object as manufactured.
	var n := 7
	for i in n:
		var a := TAU * float(i) / float(n) + tw * 1.7
		var rr := 0.45 + 1.15 * cell_hash(float(i) * 1.9, tw + 5.1)
		var yy := 3.70 + 1.15 * cell_hash(float(i) * 2.7, tw + 3.3)
		if i == 6:
			rr = 1.55
			yy = 2.95
		var lr := 0.80 + 0.52 * cell_hash(float(i) * 1.3, tw + 7.7)
		_lobe(st, leaf, Vector3(cos(a) * rr, yy, sin(a) * rr),
			lr, 1.55 + 0.55 * cell_hash(float(i) * 0.7, tw), 0.34, 2, 5,
			float(i) * 5.1 + tw)
	st.generate_normals()
	return st.commit()


## A willow: low, wide, and drooping over water. Its flatness is CORRECT — a
## willow really is a wide low dome — but it is built the same way as the
## broadleaf, from small lobes at several heights, so that it is a wide low dome
## with texture rather than a wide low ceiling.
func _willow(f: Dictionary, v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = f["bark"]
	var leaf: Color = f["leaf"]
	var tw := float(v) * 1.83
	_trunk(st, bark, 1.95, 0.36, 0.24, 6)
	for i in 4:
		var a := TAU * float(i) / 4.0 + tw
		var reach := 1.25 + 0.60 * cell_hash(float(i) * 2.9 + tw, 3.1)
		_limb(st, bark, Vector3(0.0, 1.50, 0.0),
			Vector3(cos(a) * reach, 2.35 + 0.45 * cell_hash(float(i) * 1.7, tw), sin(a) * reach), 0.14)
	var n := 6
	for i in n:
		var a := TAU * float(i) / float(n) + tw * 1.4
		var rr := 0.35 + 1.35 * cell_hash(float(i) * 2.1, tw + 4.3)
		var yy := 2.10 + 0.80 * cell_hash(float(i) * 1.3, tw + 6.1)
		_lobe(st, leaf, Vector3(cos(a) * rr, yy, sin(a) * rr),
			0.85 + 0.50 * cell_hash(float(i) * 1.1, tw), 1.15 + 0.35 * cell_hash(float(i), tw + 2.9),
			0.36, 2, 5, float(i) * 4.7 + tw)
	st.generate_normals()
	return st.commit()


func _pine(f: Dictionary, v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = f["bark"]
	var leaf: Color = f["leaf"]
	var tw := float(v) * 1.37
	_trunk(st, bark, 6.2, 0.26, 0.17, 5)
	# Stacked cones, widest low. A conifer is the one silhouette that must be
	# unmistakable at 300 m, because it is what tells the player the mountain
	# has begun. The variant shifts the stack's spacing and width rather than
	# its shape: a pine that is not a cone is not a pine.
	for i in 5:
		var k := float(i)
		var yy := 1.90 + k * (1.28 + 0.16 * tw)
		var w := (2.10 - k * 0.34) * (0.90 + 0.16 * cell_hash(k * 3.3, tw))
		var hh := (2.05 - k * 0.14) * (0.92 + 0.18 * cell_hash(k * 1.7, tw + 2.0))
		_cone(st, leaf, yy, w, hh, 6 if i < 4 else 5)
	st.generate_normals()
	return st.commit()


func _bamboo(f: Dictionary, v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = f["bark"]
	var leaf: Color = f["leaf"]
	var tw := float(v) * 1.61
	# A clump, not a tree: bamboo is read as many thin verticals in one place.
	# The crown clusters are deliberately large relative to the cane: at 0.62 m
	# they did not exist at any distance a player stands at, and the grove came
	# back as a field of bare sticks.
	for i in 5:
		var a := TAU * float(i) / 5.0 + tw
		var r := 0.30 + MistvaleHeights.variation(a * 3.1, float(i) + tw) * 0.34
		var hh := 4.2 + MistvaleHeights.variation(float(i) * 2.7 + tw, 1.3) * 2.6
		var ox := cos(a) * r
		var oz := sin(a) * r
		_cane(st, bark, ox, oz, hh, 0.075)
		_lobe(st, leaf, Vector3(ox, hh - 0.55, oz), 1.05, 1.60, 0.55, 2, 5, float(i) + tw)
		_lobe(st, leaf, Vector3(ox * 1.6, hh - 1.75, oz * 1.6), 0.80, 1.20, 0.55, 2, 5, float(i) + tw + 3.1)
	st.generate_normals()
	return st.commit()


func _bush_meshes(f: Dictionary) -> Array:
	var out: Array = []
	for v in 3:
		out.append(_bush_mesh(f, v))
	return out


func _bush_mesh(f: Dictionary, v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf: Color = f["leaf"]
	# Three lobes, but not the SAME three lobes in every instance. Varying only
	# the lobe offsets (not the count or the budget) is enough to stop a hedge
	# reading as one repeated object, and it costs nothing.
	var sp := 0.85 + float(v) * 0.16
	var tw := float(v) * 2.1
	_lobe(st, leaf, Vector3(0.0, 0.60, 0.0), 0.95 * sp, 1.25, 1.0, 2, 6, tw)
	_lobe(st, leaf, Vector3(0.58 * sp, 0.45, 0.30 * sp), 0.62 * sp, 0.95, 0.9, 2, 6, tw + 3.3)
	_lobe(st, leaf, Vector3(-0.50 * sp, 0.40, -0.36 * sp), 0.55 * sp, 0.88, 0.9, 2, 6, tw + 7.1)
	st.generate_normals()
	return st.commit()


## Grass, as a TUFT.
##
## GEOMETRY PASS 01. Every grass instance in PASS 02 was FIVE CROSSED BLADES on
## a 2.3 m lattice inside a 95 m band — worked out over the band's area that is
## roughly one blade per seven square metres. The layer was not sparse, it was
## absent; what the player saw was bare ground with occasional decorative spikes,
## which is exactly why adding noise to the terrain shader could never fix it.
##
## A clump is the unit that reads. Seven to eleven blades inside a 0.3-0.5 m
## radius, at three different heights, with the outer ones leaning out: from
## eye height that is a tuft with a silhouette, and a few thousand of them along
## a verge is grass. The blade count per INSTANCE goes up, the instance count
## goes down (see `per_cell` in FAMILIES), and the polygon total barely moves.
func _grass_meshes(f: Dictionary) -> Array:
	var out: Array = []
	for v in 3:
		out.append(_grass_clump(f, v))
	return out


func _grass_clump(f: Dictionary, v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf: Color = f["leaf"]
	var id := String(f["id"])
	var tall := id == "reed"
	# Heights came down as the blades got thinner. A tuft is ground cover, and
	# ground cover that is nearly knee high and one metre wide is a shrub. 0.58 m
	# for the verge and 0.46 m for the field puts a tuft below the eye-line at
	# every distance the player actually reads the ground from.
	var h := 0.95 if tall else (0.48 if id == "verge_grass" else 0.38)
	var n := 9 + v * 2          # 9 / 11 / 13 blades
	var spread := 0.26 + float(v) * 0.10
	for i in n:
		var a := TAU * float(i) / float(n) + float(v) * 1.7
		# Inner blades short and upright, outer ones long and leaning out: the
		# clump needs a profile, not a hemisphere of identical spikes.
		var t := cell_hash(float(i) * 3.1 + float(v) * 7.7, 1.3)
		var r := spread * (0.22 + 0.78 * t)
		var ox := cos(a) * r
		var oz := sin(a) * r
		var hh := h * (0.55 + 0.70 * cell_hash(float(i) * 1.7 + 0.5, float(v) * 2.3 + 2.9))
		# NARROW BLADES, AND NOT MUCH LEAN.
		#
		# The first version used 6.2-8.8 cm blades — for a 0.74 m tuft that is a
		# 1:9 aspect ratio. Rendered, a tuft of those came back as an ALOE:
		# fat, upright, succulent, and unmistakably a plant that was placed
		# there. Grass is 3 cm across and 60 cm tall and bends; the whole read
		# is in the fineness. Halved the width and dropped the outward lean
		# from 0.56 to 0.30 of the height, which is a settle, not a splay.
		var out_amt := hh * (0.09 + 0.24 * r / maxf(spread, 0.001))
		var w := 0.019 + 0.013 * cell_hash(float(i) * 2.9, 3.7)
		_blade2(st, leaf, ox, oz, hh, cos(a) * out_amt, sin(a) * out_amt, w)
	st.generate_normals()
	return st.commit()


## A heap of three to five loose stones.
##
## Small stones are the cheapest credible detail in the whole environment: they
## are 10-14 triangles each, they read at any distance a player can focus on
## them, and they are what makes a road edge look walked-on rather than painted.
## A SINGLE stone is a speck; the asset is the heap.
func _stone_meshes() -> Array:
	var out: Array = []
	for v in 3:
		out.append(_stone_cluster(v))
	return out


func _stone_cluster(v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(0.560, 0.548, 0.526)
	var n := 3 + v              # 3 / 4 / 5
	for i in n:
		var a := TAU * float(i) / float(n) + float(v) * 0.9
		var r := 0.20 + 0.36 * cell_hash(float(i) * 4.1 + float(v) * 2.7, 0.7)
		var s := 0.19 + 0.23 * cell_hash(float(i) * 2.3, float(v) * 5.1)
		# The same trap as the boulders, one scale down. A squash of 0.60 on a
		# 0.19..0.42 m radius is a 3.3:1 disc sunk a third of a radius into the
		# ground — a flat film a player reads as a texture, never as a cobble.
		# 1.25 gives a 1.6:1 cobble, and the burial is a fraction of the
		# cobble's own height so the widest ring always clears the ground.
		var sq := 1.25
		var hgt := sq * s
		var bury := hgt * (0.26 + 0.18 * cell_hash(float(i) * 5.9, float(v) * 2.1))
		# `rings` MUST BE >= 2 OR THIS PRODUCES NOTHING AT ALL.
		#
		# `_lobe` lays its rows at phi = v * PI, and the horizontal radius of a
		# row is sin(phi) * r. With rings = 1 the two rows land on phi = 0 and
		# phi = PI, where sin() is ZERO — so every vertex collapses onto the
		# vertical axis and the "cobble" is a zero-width sliver with no area.
		# The whole stone family (3,474 instances) shipped invisible for
		# exactly this reason: the scatter, the masks and the counts were all
		# correct and the geometry was a line.
		_lobe(st, base * (0.86 + 0.30 * cell_hash(float(i) * 1.1, 2.2)),
			Vector3(cos(a) * r, -bury, sin(a) * r),
			s, sq, 0.34, 2, 5, float(i) * 4.3 + float(v) * 9.1, true)
	st.generate_normals()
	return st.commit()


## A formation of three to five boulders.
##
## The failure mode this exists to avoid is the one every first attempt makes:
## a smooth ball sitting ON the terrain. Two rules fix it, and neither is a
## shader trick —
##
##   BURY IT. 25-45% of each chunk is below the sampled ground. A rock that
##   grows out of the ground reads as terrain; a rock that rests on it reads as
##   an asset. The heightfield is the large form; rock is the medium one.
##
##   GROUP IT. Rock does not occur evenly. Three to five chunks of different
##   sizes at different angles, from 0.4 m to 2 m, overlapping, is a formation.
##   The same polygons spread evenly is a scatter, and a scatter is the tell.
func _rock_meshes() -> Array:
	var out: Array = []
	for v in 3:
		out.append(_rock_formation(v))
	return out


func _rock_formation(v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(0.500, 0.492, 0.476)
	var n := 3 + (v % 3)        # 3 / 4 / 5
	# SIZES ARE RADII AND THEY MULTIPLY. `s` is a half-extent and the
	# per-instance scale in the family is applied on top of it. The first
	# version ran 0.75..2.10 x 0.90..2.00 = up to a 4.2 m RADIUS, i.e. an
	# eight-metre boulder, and rendered the Hero Zone as a field of dark
	# broken slabs. A formation of 0.45..1.10 m chunks at 0.70..1.30 is a
	# rock group; anything past that is a landform and belongs in the field.
	var spread := 0.70 + float(v) * 0.35
	for i in n:
		var a := TAU * float(i) / float(n) + float(v) * 1.31
		var r := spread * (0.20 + 0.80 * cell_hash(float(i) * 3.7 + float(v), 2.1))
		var s := 0.36 + 0.68 * cell_hash(float(i) * 1.9 + 0.3, float(v) * 3.3)
		# SQUAT OR TENT — AND THE APEX IS WHAT DECIDES WHICH.
		#
		# `_lobe` terminates both poles in a single point, so the cap above the
		# widest ring is always a cone; whether that reads as "stone" or as "a
		# tent" is the cone's SLOPE, and the slope is set by two things at once:
		#
		#   how tall the lobe is (squash), and
		#   how much of that height the cap owns (rings).
		#
		# With `rings = 2` the cap owns the whole upper half, so squash 1.45..2.30
		# gave a 43-degree apex and the pass produced a hillside of evenly spaced
		# white TENTS. With `rings = 3`, below, the cap owns only the top quarter
		# and the same height gives a ~20-degree cap — a rounded top on a barrel.
		#
		# So the height can and should come back up: at 1.55..2.20 against a
		# height-independent width of 1.73 s, these are 0.90..1.27 wide-to-tall
		# boulders — chunks with volume — rather than the low pale pancakes that
		# the first correction overshot into.
		var sq := 1.55 + 0.65 * cell_hash(float(i) * 2.7, float(v) * 4.4)
		# BURY IS A FRACTION OF THIS CHUNK'S OWN HEIGHT, NOT OF ITS RADIUS.
		#
		# `_lobe` spans `squash * r` vertically and `2r` horizontally, so the
		# height here is `sq * s` and the half-width is `s`. The previous
		# `bury = s * (0.52..0.86)` was measured against the RADIUS while the
		# thing being sunk was only `sq * s` tall. At sq = 1.25 that is 1.25 s of
		# height under as much as 0.86 s of burial: two thirds of the boulder
		# went under, the widest ring went under WITH it, and what stayed above
		# ground was the narrow top of the cone — a dark flat triangle with the
		# sun never touching it. That is the exact shape in every frame of the
		# first pass, and it is why the family read as paper shards lying on the
		# road rather than rock growing out of it.
		#
		# Kept under half the height so the WIDEST RING — the ring that makes it
		# read as stone at all — always clears the ground.
		var hgt := sq * s
		var bury := hgt * (0.18 + 0.16 * cell_hash(float(i) * 5.3, 1.7))
		# `rings = 3` and not 2: three bands give the barrel-with-a-low-cap
		# profile that stone has, instead of one hard 45-degree cone.
		_lobe(st, base * (0.80 + 0.42 * cell_hash(float(i) * 2.7, 4.4)),
			Vector3(cos(a) * r, -bury, sin(a) * r),
			s, sq, 0.34, 3, 7, float(i) * 3.7 + float(v) * 11.0, true)
	st.generate_normals()
	return st.commit()


## Broken ground: a low irregular mound of soil.
##
## This is the MEDIUM scale the terrain structurally cannot carry. The terrain
## mesh samples the analytic heightfield every 3 m and interpolates, so there is
## no 1 m feature in it anywhere, at any budget — a shader can shade a mound
## that is not there but it cannot make one. Heaps beside a cut, spoil at the
## foot of a bank and root balls are the same asset at different scales.
func _mound_meshes() -> Array:
	var out: Array = []
	for v in 3:
		out.append(_mound(v))
	return out


func _mound(v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var soil := Color(0.560, 0.512, 0.434)
	# 0.62 was a 3.3:1 plate, and `sink` then ate the last of its thickness —
	# the family rendered as dark flat discs on otherwise clean grass. 0.98 is
	# a LOW MOUND: roughly twice as wide as it is tall, which is what a heap of
	# soil beside a cut actually is. `lit_top` puts the sun on its crown.
	_lobe(st, soil, Vector3.ZERO, 0.62 + float(v) * 0.20, 0.98, 0.60, 2, 6 + v,
		float(v) * 7.3, true)
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
## THE SIZE CONVENTION, WRITTEN DOWN BECAUSE IT HAS COST THIS FILE THREE
## ROUNDS: the blob is `2r` WIDE and `squash * r` TALL, and its base plane sits
## at `at.y` (the crown is at `at.y + squash * r`, the widest ring at
## `at.y + squash * r / 2`). So `squash` is TWICE the height-to-width ratio:
##
##     squash 2.0  ->  as tall as it is wide          (a ball)
##     squash 1.0  ->  twice as wide as it is tall    (a disc / pancake)
##     squash 0.6  ->  3.3x wider than tall           (a plate)
##
## Every "flat parasol crown", "slate slab" and "dark flat triangle" artefact
## in this file's history traces back to a `squash` between 0.6 and 1.3 being
## read as if it were a ratio rather than twice one.
##
## `rings` / `sides` are parameters because a canopy and a bush clump are not
## the same budget. A bush is seen in the middle of a crowd of bushes, twenty in
## one frame; a tree canopy is the silhouette of the tree. Spending 42 triangles
## on a bush put 277k triangles into the shrub layer alone.
func _lobe(
	st: SurfaceTool, c: Color, at: Vector3, r: float, squash: float, jitter: float,
	rings: int = 3, sides: int = 7, off: float = 0.0, lit_top: bool = false
) -> void:
	# Clamped, not asserted. `rings < 2` is not a smaller lobe, it is NO lobe:
	# the row radius is sin(phi) * r and the two rows of a rings = 1 lobe sit
	# on phi = 0 and phi = PI, where sin() is zero. Every vertex lands on the
	# vertical axis and the mesh has no area. The stone family shipped that way
	# once — 3,474 instances of nothing — so the floor is enforced here rather
	# than trusted to every caller.
	rings = maxi(rings, 2)
	# Typed: an untyped nested Array makes every indexed read a Variant, and
	# GDScript refuses to infer a type for `var a := pts[ri][si]`.
	#
	# `off` shifts the jitter field. Without it every lobe with the same
	# rings/sides/jitter has IDENTICAL vertex offsets — which is fine for a
	# canopy and fatal for rock, where three boulders in one formation would be
	# three copies of one boulder. It is the difference between a formation and
	# a scatter, and it costs one float.
	var pts: Array[PackedVector3Array] = []
	for ri in rings + 1:
		var v := float(ri) / float(rings)
		var phi := v * PI
		var row := PackedVector3Array()
		for si in sides:
			var th := TAU * float(si) / float(sides)
			var j := 1.0 + (MistvaleHeights.variation(
				th * 4.7 + float(ri) + off, float(si) * 2.3 + off * 1.7) - 0.5) * jitter
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
			# CANOPY ramp is the default: the underside is the face a player
			# standing under a tree actually sees, so the lobe is baked with
			# the underside brightest (ri = rings) and the crown darkest.
			#
			# `lit_top` INVERTS IT, and every GROUND volume passes true. A
			# boulder, a cobble and a heap of soil are seen from above and from
			# the side — never from underneath — so there the crown is exactly
			# the face the sun lands on. Inheriting the canopy ramp painted
			# every one of them at 0.74 on its only sunlit surface, and no
			# colour put into `c` could win that back: it is half of why the
			# whole rock family rendered as dark shards.
			var shade := 0.74 + 0.26 * (float(ri) / float(rings))
			if lit_top:
				# 0.90..0.66, not 1.00..0.74. The wide ramp put a near-white cap
				# on a near-black body once the sun multiplied the top facet, and
				# the result read as a dark boulder wearing a hat. Stone is one
				# material: the crown should be the brightest part of it, not a
				# separate object.
				shade = 0.90 - 0.24 * (float(ri) / float(rings))
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


## A two-segment grass blade: base -> mid -> tapered tip, leaning by (lx, lz) at
## the top. Three triangles instead of the old two-segment-free two, and it is
## the difference between a spike and a blade — the curve is what the eye reads
## at one to three metres, which is exactly the range the first-person camera
## spends all its time at.
##
## The ribbon's width is carried PERPENDICULAR to the lean, not along world X.
## A blade that is always a card in the X plane disappears when it is leaning
## along X and read edge-on, and a tuft of them reads as extruded paper.
func _blade2(
	st: SurfaceTool, c: Color, ox: float, oz: float, h: float,
	lx: float, lz: float, w: float
) -> void:
	var ll := sqrt(lx * lx + lz * lz)
	var nx := 1.0
	var nz := 0.0
	if ll > 1e-4:
		nx = -lz / ll
		nz = lx / ll
	var mid_x := ox + lx * 0.45
	var mid_z := oz + lz * 0.45
	var mh := h * 0.58
	var b0 := Vector3(ox - nx * w, 0.0, oz - nz * w)
	var b1 := Vector3(ox + nx * w, 0.0, oz + nz * w)
	var m0 := Vector3(mid_x - nx * w * 0.60, mh, mid_z - nz * w * 0.60)
	var m1 := Vector3(mid_x + nx * w * 0.60, mh, mid_z + nz * w * 0.60)
	var tip := Vector3(ox + lx, h, oz + lz)
	# VERTEX SHADE IS NOT JUST SHAPE, IT IS THE LIGHTING MODEL.
	#
	# A blade is a near-vertical surface, so its normal is near-horizontal and it
	# takes far less sun than the flat ground beside it. That is physically
	# correct and it is why the first tufts — baked 0.54 at the base — came back
	# as DARK SPIKY SHRUBS sitting on a bright field, which reads as a plant that
	# was placed rather than as ground cover. Real grass is translucent: light
	# comes through the blade, so a tuft is very nearly as bright as the ground
	# it grows out of, and it is BRIGHTER at the tips where the blade is one
	# cell thick.
	#
	# So: lift the base to 0.78 and the tip past 1.0. The tuft then sits in the
	# ground's own value range and reads as texture with volume rather than as
	# an object.
	st.set_color(c * 0.72); st.add_vertex(b0)
	st.set_color(c * 0.72); st.add_vertex(b1)
	st.set_color(c * 0.96); st.add_vertex(m1)
	st.set_color(c * 0.72); st.add_vertex(b0)
	st.set_color(c * 0.96); st.add_vertex(m1)
	st.set_color(c * 0.96); st.add_vertex(m0)
	st.set_color(c * 0.96); st.add_vertex(m0)
	st.set_color(c * 0.96); st.add_vertex(m1)
	st.set_color(c * 1.10); st.add_vertex(tip)
