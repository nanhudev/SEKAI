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
##
## DERIVED FROM THE WIDEST TREAD, AND IT USED TO NOT BE. This was 2.6, which is
## a number measured against nothing: `MistvaleHeights.ROADS` declares the main
## street at 3.6 m HALF-width (7.2 m of clay edge to edge), so 2.6 m from the
## centreline is a metre INSIDE the road surface. Stones, rocks, mounds and
## scree all use this constant, so every one of them was free to sit on the
## street, and the review frame at d=120 had a 2 m grey rock lying dead in the
## middle of the lane with a shadow across it.
##
## §13 wants the road to be a VISUAL REST AREA — clean shape, edge grass, a few
## exposed stones — and a rest area is not a place you can put a boulder.
##
## 3.6 (widest half-width) + 1.0 (shoulder) = 4.6, so no stone of any family can
## touch any road surface in the region. The narrow single-file trails are
## 1.6-2.8 wide and get a wider clear verge than they need, which is free:
## nobody notices a clean verge, and everybody notices a rock in the road.
const ROAD_CLEAR := 4.6
## Trees keep a wider berth — a canopy at eye height on the street is a fight
## with the camera, not a tree. 4.2 m was measured against the trunk and is far
## too close: the crown radius reaches 2.7 m, so the first version hung foliage
## over the middle of the road and the street shot came back with a bush in the
## player's face.
const TREE_ROAD_CLEAR := 7.0
## Grasses may crowd the verge; that is what makes a road read as a road.
##
## Raised from 1.5, which put blades in the wheel ruts: at 1.5 m from the
## centreline of a 3.6 m half-width street the tuft is a third of the way across
## the clay. 3.2 leaves grass standing on the LIP — the outer 40 cm of tread for
## the widest road, the whole worn verge for the narrow ones — which is the
## "edge grass" of §13 read literally. The material is unchanged and this is a
## placement fix, so it costs nothing.
const GRASS_ROAD_CLEAR := 3.2
## Hero rocks are 3-8 m across, so they keep their distance in METRES OF ROCK,
## not in metres of centre. 11 m puts the near face of an 8 m boulder about 7 m
## off the centreline — clear of the 3.6 m tread and its verge, close enough
## that walking the road means walking BETWEEN them.
const HERO_ROAD_CLEAR := 11.0

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

## ART DIRECTION PASS 04 — the LARGE scale.
##
## ROUND 01 proved the medium scale works and immediately exposed what was still
## missing above it: 0.4-2 m rock, however well placed, is a TEXTURE. A frame
## made only of texture has no composition, and the correct fix is not more of
## it — it is a handful of objects big enough to be FORMS.
##
## HERO_SPACING is a landmark spacing, not a scatter density — but it is also
## the CANDIDATE RESOLUTION, and that is what bit the first build. `spacing`
## drives the lattice stride (`round(spacing / GRID_STEP)`), so at 52 m the whole
## 660x760 m region offered about 195 candidate cells before a single mask ran,
## and the family came back with ELEVEN hero rocks in total. Landmark spacing and
## candidate spacing are not the same number: this one only has to be coarse
## enough that the jitter (±0.9 x spacing) does not put two of them in one place.
##
## §12 is explicit that three of these are worth more than five hundred small
## stones, and the instance counts below are set from that, not from budget.
##
## 34 m WAS STILL TOO COARSE, AND IT TOOK TWO MEASUREMENTS TO SEE IT.
##
## At 34 m the stride is `round(34 / 2.3) = 15` cells, i.e. one candidate every
## 34.5 m, which is about 460 candidate cells across the region — and the band
## this family is confined to is only ~10% of the map, so ~47 of them. The
## measured count was 48. Raising `density` from 5.0 to 9.0 moved it to 48 from
## 39: a 1.8x request returned 1.23x, which is the signature of a family that
## has run out of PLACES rather than out of weight. Every candidate in the band
## was already accepted, so no density value could ever have produced a 49th.
##
## 21 m gives a stride of 9, ~1,100 candidate cells region-wide and ~115 inside
## the band, which is a boulder every ~15 m of walked line — dense enough to be
## a rhythm, and still sparse enough that `clump` (48 m period) can group them
## into formations instead of a hedge. The earlier note that this only has to
## be coarse enough to survive the jitter still holds: the jitter is ±0.9 x
## spacing, so two candidates cannot land on top of each other at any spacing,
## and the far tighter constraint is candidate AVAILABILITY.
const HERO_SPACING := 21.0
const MAX_HERO := 260

## Rock shelf — the terrain module. Sparse because it is a LAND FORM: a shelf
## every 15 m along a slope is a rocky hillside, a shelf every 40 m is a
## hillside with one outcrop, and only the second one reads as designed.
const SHELF_SPACING := 30.0
const MAX_SHELF := 480

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
#   corridor favours the first ~40 m beside the road, for polygons the player
#            can actually resolve.
#   band     [lo, hi] metres from the road centreline — a bump centred between
#            the two, for families that FRAME the road rather than crowd it.
#   per_cell instances emitted per accepted lattice cell (default 1). The
#            lattice cannot go below GRID_STEP, so this is the only way to get
#            a band denser than one object per 5.3 m2.
#   sink     metres the instance is pushed below the sampled ground height.
#   cast     whether the layer casts shadows (default: everything but grass).
#   clump    metres. Thresholds a coarse noise field so the family groups
#            instead of covering evenly. See `_accept_cell`.
#   slope_size grow with local steepness (rock: the pieces that survive a
#            break are the big ones).
#   align    "slope" lays the instance on the terrain's own normal, so a shelf
#            presents its face along the hill instead of standing level on it.
#   face     "water" yaws the family toward the river, so every river tree leans
#            the same way. Random yaw on a leaning tree is a leaning tree in a
#            random direction, which is worse than no lean at all.
#
# SCALE RANGES ARE AGE. Every tree in PASS 02 was between 0.75x and 1.3x of the
# same prototype, which is a nursery, not a forest, and it is a large part of
# why a stand of them read as instanced objects. The ranges below run roughly
# 0.55x to 1.55x so a frame contains saplings and old trees.
#
# =============================================================================
# ART DIRECTION PASS 04 — COLOR GROUPING (PART B / §5)
# =============================================================================
#
# The R01 frame was a single mass of grey-green / grey-brown / grey-blue. The
# palette below is built so that the six masses the thumbnail test asks for
# (road · grass · rock · trees · town · mountain) are separable BY HUE, and so
# that the four tree species are separable FROM EACH OTHER — §9's "the player
# should know they have entered a different region without knowing botany".
#
#   valley broadleaf   fresh warm green      (hue ~100 deg)
#   river tree         cool teal-green       (hue ~150 deg)
#   mountain pine      deep blue-green       (hue ~170 deg)
#   bamboo             yellow-green          (hue ~ 80 deg)
#
# Bark carries the same split in the warm half, and the stone families are set
# to the terrain shader's own `rock` value so a boulder and the shelf it grew
# out of are visibly ONE material — §3's "the hill itself is exposing rock".
const FAMILIES := [
	{
		"id": "broadleaf_a", "kind": "tree", "spacing": TREE_SPACING,
		"slope": [0.0, 24.0], "scale": [0.62, 1.42], "weight": 1.0,
		"zone": "valley", "bark": Color(0.494, 0.404, 0.316),
		"leaf": Color(0.352, 0.548, 0.284),
	},
	{
		"id": "broadleaf_b", "kind": "tree", "spacing": TREE_SPACING * 1.25,
		"slope": [0.0, 26.0], "scale": [0.55, 1.25], "weight": 0.8,
		"zone": "valley", "bark": Color(0.455, 0.372, 0.296),
		"leaf": Color(0.312, 0.486, 0.268),
	},
	{
		# RIVER TREE, not a willow. §9 asks for SLENDER, LEANING TOWARD THE
		# WATER — the low wide dome that used to be here was a willow, and a
		# willow over every river is the single most-copied silhouette in
		# stylised fantasy. A tall narrow crown that leans out over the channel
		# reads as "the water is that way" from a hundred metres, which is the
		# navigational job it is actually doing.
		"id": "river_tree", "kind": "tree", "spacing": TREE_SPACING * 0.9,
		"slope": [0.0, 18.0], "scale": [0.68, 1.42], "weight": 1.5,
		"zone": "water", "face": "water",
		"bark": Color(0.478, 0.412, 0.336),
		"leaf": Color(0.286, 0.588, 0.420),
	},
	{
		"id": "mountain_pine", "kind": "tree", "spacing": TREE_SPACING * 0.85,
		"slope": [0.0, 33.0], "scale": [0.72, 1.60], "weight": 1.2,
		"zone": "mountain", "bark": Color(0.404, 0.348, 0.300),
		"leaf": Color(0.240, 0.428, 0.372),
	},
	{
		"id": "bamboo", "kind": "tree", "spacing": TREE_SPACING * 0.95,
		"slope": [0.0, 27.0], "scale": [0.70, 1.30], "weight": 0.85,
		"zone": "forest", "bark": Color(0.706, 0.702, 0.508),
		"leaf": Color(0.512, 0.678, 0.286),
	},
	{
		"id": "bush", "kind": "bush", "spacing": BUSH_SPACING,
		"slope": [0.0, 34.0], "scale": [0.55, 1.15], "weight": 1.0,
		"zone": "any", "bark": Color(0.455, 0.372, 0.296),
		"leaf": Color(0.352, 0.560, 0.284),
	},
	{
		"id": "river_bush", "kind": "bush", "spacing": BUSH_SPACING * 0.8,
		"slope": [0.0, 30.0], "scale": [0.60, 1.10], "weight": 1.4,
		"zone": "water", "face": "water",
		"bark": Color(0.446, 0.372, 0.312),
		"leaf": Color(0.298, 0.570, 0.382),
	},
	{
		"id": "tall_grass", "kind": "grass", "spacing": GRASS_SPACING,
		"slope": [0.0, 40.0], "scale": [0.70, 1.45], "weight": 1.0,
		"zone": "any", "corridor": true, "bark": Color(0.647, 0.588, 0.372),
		"leaf": Color(0.482, 0.628, 0.300),
	},
	{
		"id": "reed", "kind": "grass", "spacing": GRASS_SPACING * 0.75,
		"slope": [0.0, 26.0], "scale": [0.85, 1.40], "weight": 1.6,
		"zone": "water", "bark": Color(0.663, 0.620, 0.412),
		"leaf": Color(0.545, 0.667, 0.325),
	},
	# --- GEOMETRY PASS 01 -----------------------------------------------------
	{
		# The road's frayed edge. Zone is "any" because a verge is not a
		# habitat — it is whatever survives being walked past. The band rule
		# lives in `_accept_cell` under the `verge` flag.
		"id": "verge_grass", "kind": "grass", "spacing": VERGE_SPACING,
		"slope": [0.0, 44.0], "scale": [0.80, 1.35], "weight": 1.0,
		"zone": "any", "verge": true, "per_cell": 4,
		"bark": Color(0.639, 0.588, 0.372),
		"leaf": Color(0.447, 0.616, 0.298),
	},
	{
		# Loose stones. Small, in heaps of three to five, everywhere the road
		# corridor is — including on the tread, because a stone IN a road is
		# the single cheapest way to say the road is 400 years old.
		"id": "stone", "kind": "stone", "spacing": STONE_SPACING,
		"slope": [0.0, 46.0], "scale": [0.55, 1.30], "weight": 1.0,
		"zone": "any", "edge": true, "per_cell": 2, "sink": 0.06, "cast": false,
		"leaf": Color(0.585, 0.570, 0.548),
	},
	{
		# Boulder formations. Slope-gated, because rock does not lie around on
		# flat land — it is what the flat land was cut out of. 20-45% of every
		# chunk is under the ground: a rock sitting ON the terrain is a prop,
		# a rock growing OUT of it is terrain.
		"id": "rock", "kind": "rock", "spacing": ROCK_SPACING,
		"slope": [6.0, 46.0], "scale": [0.62, 1.00], "weight": 1.0,
		"zone": "any", "per_cell": 1, "sink": 0.0, "cast": true, "corridor": true,
		"clump": 30.0, "slope_size": true, "density": 0.52,
		"leaf": Color(0.472, 0.464, 0.448),
	},
	{
		# Broken ground, soil heaps, the spoil beside a cut. The MEDIUM scale
		# the terrain shader structurally cannot carry: a heightfield with a
		# 3 m mesh has no 1 m bump in it at all.
		"id": "mound", "kind": "mound", "spacing": MOUND_SPACING,
		"slope": [2.0, 30.0], "scale": [0.70, 1.30], "weight": 0.9,
		"zone": "any", "edge": true, "per_cell": 1, "sink": 0.20, "cast": false,
		"clump": 22.0,
		"leaf": Color(0.512, 0.436, 0.342),
	},
	# --- ART DIRECTION PASS 04 ------------------------------------------------
	{
		# HERO ROCK (§11/§12). The first family in this file that is designed
		# rather than scattered: one strong diagonal, one flat shelf, one
		# broken side, built as four deliberate masses. It is placed in a band
		# 14-64 m off the road so it frames the walk instead of crowding it,
		# and it clumps hard because a landmark that appears every 52 m in a
		# perfect lattice is not a landmark, it is a fencepost.
		# `slope` STARTED AT 2.0 AND THAT WAS THE REAL REASON THEY WERE ALL FAR
		# AWAY. The slope gate is correct for the `rock` and `shelf` families —
		# broken ground is where rock outcrops — but it is self-defeating for
		# hero rock, and the reason is a hard geometric one: relief is fully
		# suppressed within `RELIEF_CLEAR_FULL` (5 m) of every road centreline
		# and only restored by `RELIEF_CLEAR_NONE` (15 m). So there is no ground
		# steeper than 2 degrees closer than about 15 m to any road, anywhere in
		# the region, by construction. Demanding slope >= 2 therefore FORBIDS
		# the 11-25 m band this family is meant to live in, no matter what the
		# framing band says — which is why moving the band from a mid-centred
		# bump to a near-biased ramp moved the measured mean from 58.1 m to only
		# 57.4 m. The band was never the binding term.
		#
		# §12 does not ask for hero rock on a slope. It asks for large stone
		# bodies placed FOR COMPOSITION — environmental architecture. An erratic
		# sitting level on flat verge is exactly that, and it is the one thing
		# that was missing from every frame of the walked route.
		#
		# The upper bound stays at 26: past that the piece is on a face, which is
		# the `shelf` family's job.
		"id": "hero_rock", "kind": "hero", "spacing": HERO_SPACING,
		"slope": [0.0, 26.0], "scale": [0.75, 1.80], "weight": 1.0,
		"zone": "any", "sink": 0.0, "cast": true, "clump": 48.0,
		# `band` narrow and `density` high, together: the window says WHERE the
		# family is allowed to be composition and the density buys back the
		# count that the narrow window costs. Left at 5.0 the family measured
		# 39 instances once the far floor dropped to 0.05, which over 850 m of
		# walked line is one boulder every 22 m on both sides combined — a
		# landmark you meet, not a rhythm you walk through.
		"band": [10.0, 34.0], "align": "slope",
		"lean": 7.0, "density": 9.0,
		"leaf": Color(0.548, 0.538, 0.522),
	},
	{
		# ROCK SHELF — THE TERRAIN MODULE (§2/§3).
		#
		# §3 is the whole reason this exists: the target is not "hill PLUS
		# stones", it is "the hill itself is exposing rock". So this family is
		# placed only on real slope, and it is ROTATED ONTO THE SLOPE NORMAL
		# (`align: slope`) so its strata surface lies along the hillside and
		# only its broken face stands out of it. A shelf left level would be a
		# slab lying on a hill, which is the prop read this avoids.
		"id": "shelf", "kind": "shelf", "spacing": SHELF_SPACING,
		"slope": [16.0, 52.0], "scale": [0.60, 1.30], "weight": 1.0,
		"zone": "any", "sink": 0.45, "cast": true, "clump": 34.0,
		"align": "slope", "slope_size": true, "lean": 4.0, "density": 2.0, "max": 620,
		"leaf": Color(0.470, 0.462, 0.452),
	},
	{
		# RIVER STONES (§16). Rounded, pale, and slightly LARGER AND CLEANER
		# than life, because the brief's note is correct: the shallows are a
		# readability problem, not a fidelity one. Gated to the bank band by
		# the water zone; they only exist in the two metres either side of the
		# waterline, which is where a river puts its stones.
		"id": "river_stone", "kind": "stone", "spacing": STONE_SPACING * 1.3,
		"slope": [0.0, 40.0], "scale": [0.85, 1.70], "weight": 1.0,
		"zone": "water", "per_cell": 2, "sink": 0.10, "cast": false,
		"clump": 18.0, "density": 1.70, "max": 3600,
		"leaf": Color(0.648, 0.638, 0.618),
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
			if _family_off(f):
				continue
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
					_emit(f, _scatter_points(f, ROAD_CLEAR,
							int(f.get("max", MAX_STONE)), float(f.get("density", 0.09))),
						_stone_meshes(f["leaf"]), "Stones_" + String(f["id"]))
				"rock":
					_emit(f, _scatter_points(f, ROAD_CLEAR, MAX_ROCK,
							float(f.get("density", 0.62))),
						_rock_meshes(f["leaf"]), "Rocks_" + String(f["id"]))
				"mound":
					_emit(f, _scatter_points(f, ROAD_CLEAR, MAX_MOUND, 0.95),
						_mound_meshes(f["leaf"]), "Mounds_" + String(f["id"]))
				# --- ART DIRECTION PASS 04 -----------------------------------
				# The two families that exist to give the frame COMPOSITION
				# rather than texture. Generous per-cell acceptance, because
				# there are so few of them: a hero rock that only shows up in
				# one cell in four is a hero rock the player never sees, and
				# the caps are 260 / 2200 against 34,000 grass instances, so
				# there is budget here and none to waste.
				"hero":
					_emit(f, _scatter_points(f, HERO_ROAD_CLEAR, MAX_HERO,
							float(f.get("density", 0.72))),
						_hero_meshes(f["leaf"]), "HeroRocks")
				"shelf":
					_emit(f, _scatter_points(f, ROAD_CLEAR,
							int(f.get("max", MAX_SHELF)), float(f.get("density", 0.80))),
						_shelf_meshes(f["leaf"]), "Shelves")
	if build_trees:
		for f in FAMILIES:
			if _family_off(f):
				continue
			if f["kind"] == "tree":
				_trees(f)

	print("MistvaleFlora: %d meshes in %d ms"
		% [get_child_count(), Time.get_ticks_msec() - t0])


## ABLATION SWITCH — `FLORA_OFF=rock,mound` builds everything except those.
##
## This exists because "the frame has a giant pale sheet in it, which family
## owns it?" is not a question that can be answered by reading the scatterer.
## It was answered once that way and answered WRONG — the sheet was blamed on
## the new shelves for two passes, and the ablation (zero one family's cap at a
## time) showed it was the rock/mound layer at R01 sizes, while the shelves the
## whole round was about were not visible in the frame at all. Static reasoning
## about procedural scatter has a poor track record here; an ablation has none.
##
## Comma-separated family ids, matched against `id`. Empty or unset = build all,
## so this costs nothing in a normal run.
func _family_off(f: Dictionary) -> bool:
	if not OS.has_environment("FLORA_OFF"):
		return false
	var off := OS.get_environment("FLORA_OFF").strip_edges()
	if off.is_empty():
		return false
	return String(f["id"]) in off.split(",", false)


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
			# JITTER IS CAPPED, AND THE CAP IS NOT COSMETIC.
			#
			# The box used to be the full `spacing * 1.8` in each axis, i.e.
			# ±0.9 * spacing. That is a reasonable throw for a family on the
			# 1 m verge lattice. It is not a reasonable throw for a family on a
			# 34 m candidate spacing: the hero rocks were being displaced up to
			# 30.6 m from the cell that passed every mask, in any direction,
			# including back across the road and into the river.
			#
			# `spacing` is a CANDIDATE LATTICE PITCH. It sizes where a family is
			# allowed to be, and the jitter exists only to break the lattice's
			# regularity, not to relocate the instance. Those are different jobs,
			# and conflating them meant every distance rule in `_accept_cell`
			# — road clearance, waterline zone, framing band — was enforced at a
			# point where the object does not end up. Measured: `Rocks_rock`
			# and `HeroRocks` both came back with `path_min = 0.0`, i.e. a rock
			# on the road centreline, while the mask that forbids it was passing.
			#
			# 4 m is a little over one and a half lattice cells: enough to
			# destroy the grid read, small enough that the mask still means what
			# it says.
			var jit := minf(spacing * 0.9, 4.0)
			for k in per:
				var ks := float(k) * 13.7 + 4.9
				var jx := cell_hash(gx * 1.7 + 3.1 + ks, gz * 2.9 - 2.3 - ks)
				var jz := cell_hash(gx * 3.1 - 7.7 + ks, gz * 1.3 + 5.9 + ks)
				var px := gx + (jx - 0.5) * jit * 2.0
				var pz := gz + (jz - 0.5) * jit * 2.0
				# The throw is applied BEFORE the gate, so the gate is
				# evaluated where the instance actually is. See `_pos_ok`.
				if not _pos_ok(px, pz, road_clear):
					continue
				out.append(Vector2(px, pz))
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
## A gate evaluated where the object LANDS, not where it was proposed.
##
## `_accept_cell` judges a lattice cell centre. The instance is then jittered off
## that lattice — see the `jit` note in `_scatter_points` — and for any family on
## a coarse candidate spacing that throw used to be tens of metres. So every
## distance rule in `_accept_cell` was being enforced at a point the object does
## not occupy: the road clearance, the waterline zone and the framing band.
##
## Measured before this existed, on the built region:
##
##     Rocks_rock  n=540  path_min=0.0
##     HeroRocks   n=120  path_min=0.0
##
## A zero there is a rock standing on a road centreline. Two of them, in two
## families, one of which was carrying a nominal 11 m clearance.
##
## Only the two ABSOLUTE, position-only rules are re-tested here. Slope, tread,
## relief clearance and settlement are continuous FIELDS, and their value 4 m
## away is not meaningfully different from their value at the centre — so
## re-deriving them per instance would not change a single placement and would
## double the build. Road and river are the exceptions: they are hard edges in
## the world, they are the two things a player is guaranteed to be looking at,
## and "a boulder in the road" is the one placement error that cannot be
## forgiven as variation.
##
## The `height_at` call is the one `_emit` is going to make anyway for the
## instance origin, so this costs one `path_distance` per instance and nothing
## else.
func _pos_ok(x: float, z: float, road_clear: float) -> bool:
	if MistvaleHeights.path_distance(x, z) < road_clear:
		return false
	# Underwater is the other absolute: `_accept_cell` already rejects it at the
	# centre, and a 4 m throw across a bank should not be able to put a tuft on
	# the river bed.
	if MistvaleHeights.height_at(x, z) < MistvaleHeights.RIVER_Y - 0.55:
		return false
	return true


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
	# THE LOW END OF EVERY SLOPE RANGE WAS NEVER ENFORCED.
	#
	# Only `slope > sr[1]` was tested, so `slope: [7.0, 46.0]` accepted FLAT
	# ground — the minimum was documentation, not a rule. ROUND 01 then
	# reported the symptom without the cause: "the boulders still form a
	# continuous band along the road". Of course they did. The road corridor
	# is the one place the detail band is guaranteed to be, so with no lower
	# bound every accepted cell landed on the shoulders and the family became
	# a hedge, no matter how the clump field was tuned.
	#
	# A gate, not a fade. Trees all carry a minimum of 0.0 so nothing changes
	# for them, and for rock the gate is the whole point: rock is what the
	# ground is MADE OF where it breaks, and on level ground there is no
	# break to expose it through.
	if slope < float(sr[0]):
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
		"stone", "rock", "mound", "hero", "shelf":
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
		# open ground, so this reads "0.22x on the tread, 2.2x in the verge" —
		# which is what loose stones actually do: heaviest where the road is
		# breaking up, present but sparse in the field.
		#
		# §13 turned the tread weight down from 0.50 to 0.22. R01 argued the
		# opposite — "a stone IN a road is the cheapest way to say the road is
		# 400 years old" — and that is still true, but it is also four hundred
		# individual objects competing with the road's own SHAPE for the eye,
		# and the direction now is a clean readable road with FEW exposed
		# stones. Sparse enough to notice one, not enough to be a texture.
		p *= 0.22 + fringe * 2.0
	elif f.get("corridor", false):
		# For things that are only worth polygons where the player is. The
		# detail band is 95 m wide on both sides — 19 hectares per kilometre of
		# road — and a boulder formation at 80 m costs the same as one at 8 m
		# while contributing nothing a player standing on the road can see. The
		# corridor is 40 m, which is past the point where a 1.5 m rock is more
		# than a few pixels.
		p *= 0.12 + (1.0 - smoothstep(7.0, 42.0, _gpath[i])) * 1.7
	# --- FRAMING BAND ------------------------------------------------------
	#
	# Where a family whose job is COMPOSITION rather than habitat is allowed to
	# sit, as a distance from the road centreline. `corridor` above is a
	# monotone falloff from the road; this is a window.
	var band: Array = f.get("band", [])
	if not band.is_empty():
		var b0 := float(band[0])
		var b1 := maxf(float(band[1]), b0 + 0.001)
		# WEIGHTED TO THE NEAR EDGE, WHICH IS THE DIFFERENCE BETWEEN A
		# COMPOSITION OBJECT AND SCENERY.
		#
		# This used to be a bump centred on the middle of the window, and the
		# middle of [12, 80] is 46 m. So the hero rocks came out with a mean
		# distance from the road of 58 m — measured with the FLORA_DIAG
		# instrument, not inferred from the code. A 5 m boulder at 58 m is
		# scenery: it is inside the detail band, it is drawn, it costs its
		# triangles, and it does nothing, because at that range it is smaller
		# on screen than the tree standing next to it.
		#
		# §12 is explicit that a hero rock is for COMPOSITION, and composition
		# lives in the near and middle distance. The profile therefore peaks AT
		# `b0` and decays to `b1`, which puts the mass of the family in the
		# 11-25 m band: big on screen, and the walked line runs between the
		# pieces rather than past them.
		#
		# THE FLOOR IS THE WHOLE ARGUMENT, AND IT TOOK THREE MEASUREMENTS.
		#
		# First the profile was a bump centred on the middle of the window: mean
		# 58 m, i.e. scenery. Then it was made monotone from `b0` — and the mean
		# did not move. That is not a tuning miss, it is arithmetic: a
		# probability multiplier acts on AREA, and the area is not evenly split.
		#
		# The region is 660 x 760 m with one road through it. Cells within 34 m
		# of the centreline are a band of roughly 51,700 m^2; everything else is
		# the other 450,000 m^2. At GRID_STEP 2.3 that is ~115 candidate cells
		# against ~1,050 — a NINE TO ONE ratio. So the far field does not need
		# to be likely to win, it only has to be possible: a 0.05 floor times a
		# density of 9 is an acceptance rate of 0.45, and 1,050 x 0.45 beats 115
		# every time. Measured, twice: 39 instances at mean 30.6, then 143 at
		# mean 43.0 the moment the lattice got dense enough to give the far
		# field more candidates.
		#
		# The lesson generalises and is worth stating plainly: **a low floor is
		# not a low floor when it is multiplied by an area nine times larger,
		# and it is not a low floor when `density` scales it back up.** The
		# earlier note — "a window is a preference, not a second gate" — was
		# true of a multiplier on a comparable area. Applied to a family whose
		# entire stated purpose in §12 is COMPOSITION, and to a 9x area, the
		# honest implementation is a DOMAIN: nothing beyond twice the band, and
		# a floor small enough to survive `density`.
		var d := _gpath[i]
		if d > b1 * 2.0:
			return false
		p *= 0.02 + 2.0 * (1.0 - smoothstep(b0, b1, d))
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
		# The floor was 0.10 with the threshold at 0.40-0.70, which together
		# remove about two thirds of a family before any other mask touches it
		# — `_clump` is a smooth value noise and clusters near its own middle,
		# so it spends most of its time below 0.55. `clump` is meant to say
		# WHERE a family groups, not to be a second hard cap on how much of it
		# exists.
		p *= lerpf(0.24, 1.0,
			smoothstep(0.34, 0.66, _clump(gx, gz, clump_period)))
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
	# ---------------------------------------------------------------- DIAGNOSTIC
	#
	# Where a family ENDED UP, as opposed to where the masks say it should go.
	#
	# This exists because "the hero rocks are missing from the route" was not
	# answerable from the code. A family can pass every mask, clear the instance
	# cap and still be invisible, because the masks act on a lattice of hundreds
	# of thousands of cells while the player only ever walks a 3.6 m ribbon
	# through them: the count says 120 and the ribbon says 0, and both are true.
	# `path_distance` is the exact quantity the road masks use, so printing its
	# range over the SURVIVORS is the straight answer.
	#
	# Off by default. It is four `path_distance` calls per instance, and
	# `path_distance` walks the whole ROADS table — free at build time, but not
	# free enough to leave on for eight families of five thousand.
	if OS.has_environment("FLORA_DIAG"):
		var mn := 1e9
		var mx := -1e9
		var sm := 0.0
		for p in pts:
			var dd: float = MistvaleHeights.path_distance(p.x, p.y)
			mn = minf(mn, dd)
			mx = maxf(mx, dd)
			sm += dd
		print("[FLORA_DIAG] ", name_, " n=", pts.size(),
			" path_min=", "%.1f" % mn, " path_max=", "%.1f" % mx,
			" path_mean=", "%.1f" % (sm / float(pts.size())),
			" scale=", f["scale"])
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
	# --- ORIENTATION MODES (ART DIRECTION PASS 04) --------------------------
	#
	# `align: slope` lays the instance on the TERRAIN'S OWN NORMAL instead of
	# on the world's. A rock shelf is the module this exists for: a slab placed
	# level on a hillside is a slab lying on a hill, and it reads as a prop no
	# matter how well it is buried. Rotated onto the local normal, the same
	# polygons become strata running WITH the slope, which is what §3 means by
	# "the hill itself is exposing rock layers".
	#
	# `face: water` fixes the yaw toward the river so a family of leaning trees
	# leans the same way — out over the water. Random yaw on a leaning tree is
	# a tree leaning in a random direction, which is worse than no lean.
	var align_slope: bool = String(f.get("align", "")) == "slope"
	var face_water: bool = String(f.get("face", "")) == "water"
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
		"tree":
			lean_deg = 12.0
		"hero":
			lean_deg = 18.0
		"shelf":
			lean_deg = 14.0
	lean_deg = float(f.get("lean", lean_deg))

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
				# Vertical squash is per-instance so a stand of trees is not a
				# stand of one tree at one height.
				var ys := 0.90 + cell_hash(z * 2.1, x * 2.1) * 0.20
				var yaw := cell_hash(x * 0.31, z * 0.31) * TAU
				# A tree that is perfectly vertical in every instance is a tree
				# that reads as an instanced object. A few degrees of lean is
				# invisible individually and decisive collectively. Rock leans
				# far harder — a boulder formation all standing level is a pile
				# of boxes.
				var lean := (cell_hash(x * 0.53 - 4.0, z * 0.53 + 8.0) - 0.5)
				if face_water:
					# Toward the channel, at this longitude, always.
					var dz := MistvaleHeights.river_center_z(x) - z
					yaw = (0.0 if dz >= 0.0 else PI) \
						+ (cell_hash(x * 0.77, z * 0.77) - 0.5) * 0.72
					lean = 0.30 + 0.34 * cell_hash(x * 1.13 - 2.7, z * 1.13 + 5.1)
				var t := Transform3D()
				if align_slope:
					# Local normal from three extra samples of the height field.
					# Only the two families that ask for it pay for it.
					var hx := MistvaleHeights.height_at(x + 1.6, z) \
						- MistvaleHeights.height_at(x - 1.6, z)
					var hz := MistvaleHeights.height_at(x, z + 1.6) \
						- MistvaleHeights.height_at(x, z - 1.6)
					var nrm := Vector3(-hx, 3.2, -hz).normalized()
					var ref := Vector3.UP
					if absf(nrm.dot(ref)) > 0.995:
						ref = Vector3.RIGHT
					var ax := ref.cross(nrm).normalized()
					var az := ax.cross(nrm).normalized()
					var ca := cos(yaw)
					var sa := sin(yaw)
					var bx := ax * ca + az * sa
					var bz := -ax * sa + az * ca
					# RIGHT-MULTIPLIED by the lean, so the tilt is in the
					# instance's own frame. `Basis.rotated()` left-multiplies,
					# which rotates about a WORLD axis — correct for an upright
					# instance, wrong for one already laid on a slope.
					var b := Basis(bx * s, nrm * s * ys, bz * s) \
						* Basis(Vector3.RIGHT, deg_to_rad(lean * lean_deg))
					t.basis = b
				else:
					# LEAN FIRST, THEN YAW — the order is the whole feature.
					# `rotated()` left-multiplies, so chaining RIGHT-then-UP
					# gives `R_up * R_right`: a lean about the instance's OWN x
					# axis, then spun. Yaw-then-lean instead applies the lean
					# about world X for every instance, which points every lean
					# in a forest the same way — and a whole hillside leaning in
					# unison is a quieter version of the same tell.
					t = t.rotated(Vector3.RIGHT, deg_to_rad(lean * lean_deg))
					t = t.rotated(Vector3.UP, yaw)
					t = t.scaled(Vector3(s, s * ys, s))
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
	# ANIME STYLIZED: KILL THE PLASTIC.
	#
	# roughness 0.88 against the default metallic_specular of 0.5 lays a broad
	# sheen across every facet — and flat-shaded facets are exactly what
	# `generate_normals()` on unindexed triangles produces. Every crown lobe
	# therefore came back with a highlight on every face and the stand read as
	# polished green crystals, which is what the first ART DIRECTION render of
	# the new trees looked like. Foliage is a DIFFUSE material.
	#
	# 0.97 / 0.06 lets the sun model the MASS instead of the facet. Stone goes
	# the other way on purpose — a little sheen is most of what says "stone"
	# rather than "dirt", and §4 wants its planes and edges legible.
	#
	# Double sided only where it is needed. Foliage is single-quad shells and a
	# leaf you can see through from behind is worse than the triangle saved — but
	# a stone, a boulder and a mound are CLOSED volumes, and rendering both faces
	# of a closed volume pays the fill cost twice for geometry that is never
	# visible. GEOMETRY PASS 01 put ~8,300 closed instances on the map; they get
	# back-face culling, and the ground layer keeps its budget for things the
	# player can actually see.
	var kind := String(f["kind"])
	if kind == "tree" or kind == "bush" or kind == "grass":
		m.roughness = 0.97
		m.metallic_specular = 0.06
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		m.roughness = 0.90
		m.metallic_specular = 0.22
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
	# THE ONLY REMAINING CALL IN THIS FILE, AND IT IS DELIBERATE.
	#
	# This mesh is a self-contained 4-ring blob used by nothing but the scree
	# layer. It is built from no `_lobe` and therefore carries no analytic
	# normals of its own, so it still needs the helper. Every builder that mixes
	# primitives now writes each vertex's normal directly, because a trailing
	# call HERE overwrites them — and that is precisely what silently cancelled
	# four separate attempts to smooth the tree canopies.
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
		"river_tree":
			return _river_tree(f, v)
	return _broadleaf(f, v)


## A broadleaf: TRUNK GESTURE, BRANCH DIRECTION, and THREE CROWN MASSES.
##
## ART DIRECTION PASS 04 (§7/§8). R01 was an honest attempt at the same problem —
## a longer trunk, five limbs, seven small lobes — and it still failed the
## thumbnail test. The reason is structural: seven lobes of nearly equal size at
## nearly equal height are not a designed silhouette however much jitter is put
## on them, because the eye groups them back into one lumpy dome within a few
## metres. Jitter breaks EDGES; it cannot break SHAPE.
##
## §7's answer is a composition answer: 2-4 MAJOR masses, deliberately of
## different sizes, at deliberately different heights and lateral offsets, with
## real GAPS between them — a gap is where the sky shows through, and sky at
## three different heights is what asymmetry means in a silhouette.
##
##   MAIN  r 1.85-2.10, high, a little off-axis, the largest shape on the tree
##   SIDE  r 1.25-1.45, lower, pushed 1.5-1.9 m out to one side
##   TOP   r 0.85-1.05, above and OPPOSITE the side mass
##
## 176 triangles against the old crown's 202, and three shapes instead of one.
func _broadleaf(f: Dictionary, v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = f["bark"]
	var leaf: Color = f["leaf"]
	var tw := float(v) * 2.31
	# THE GESTURE. A trunk that leans and drifts as it rises: one direction per
	# variant, so a stand of them is not a row of posts. Three segments with
	# explicit radii at every joint — `_limb` chains leave a step at each one.
	var bx := (cell_hash(tw, 1.3) - 0.5) * 1.30
	var bz := (cell_hash(tw + 4.1, 2.7) - 0.5) * 1.30
	var h := 3.05 + 0.45 * cell_hash(tw + 7.7, 0.9)
	for sg in 3:
		var ta := float(sg) / 3.0
		var tb := float(sg + 1) / 3.0
		_taper(st, bark,
			Vector3(bx * ta * ta, h * ta, bz * ta * ta),
			Vector3(bx * tb * tb, h * tb, bz * tb * tb),
			lerpf(0.30, 0.15, ta), lerpf(0.30, 0.15, tb), 6)
	# FOUR LIMBS, unequal, reaching up and out INTO the crown. §7's "branch
	# direction" — and they stay visible as limbs because the three masses do
	# not meet.
	var fork := Vector3(bx * 0.9, h * 0.86, bz * 0.9)
	for i in 4:
		var a := TAU * float(i) / 4.0 + tw + 0.5
		var reach := 1.55 + 1.05 * cell_hash(float(i) * 2.3 + tw, 1.7)
		var rise := 1.05 + 1.05 * cell_hash(float(i) * 3.1, tw + 2.2)
		_limb(st, bark, fork,
			Vector3(bx + cos(a) * reach, h * 0.95 + rise, bz + sin(a) * reach),
			0.105)
	# --- the three masses ---------------------------------------------------
	var sa := tw * 1.9
	var mo := Vector3(cos(sa) * 0.32, 0.0, sin(sa) * 0.32)
	_lobe(st, leaf, Vector3(bx * 1.1, h + 1.30, bz * 1.1) + mo,
		1.85 + 0.25 * cell_hash(tw + 1.1, 3.3),
		1.72 + 0.16 * cell_hash(tw, 2.2), 0.30, 4, 9, tw + 0.7)
	# SIDE: low and well out. This lobe IS the asymmetry — without it the tree
	# is a ball on a stick no matter how many other lobes it has.
	var sa2 := sa + 2.2
	var sr := 1.55 + 0.35 * cell_hash(tw + 5.3, 1.9)
	_lobe(st, leaf, Vector3(bx * 0.9 + cos(sa2) * sr, h + 0.15, bz * 0.9 + sin(sa2) * sr),
		1.25 + 0.20 * cell_hash(tw + 2.9, 6.1), 1.58, 0.32, 3, 8, tw + 3.9)
	# TOP: opposite the side mass, so the two read as a counterweight instead of
	# one long smear up the middle.
	var sa3 := sa2 + PI
	var tr := 0.75 + 0.30 * cell_hash(tw + 8.1, 4.4)
	_lobe(st, leaf, Vector3(bx * 1.2 + cos(sa3) * tr, h + 2.35, bz * 1.2 + sin(sa3) * tr),
		0.85 + 0.20 * cell_hash(tw + 6.3, 1.4), 1.42, 0.34, 3, 7, tw + 7.1)
	return st.commit()


## RIVER TREE (§9): slender, and leaning out over the water.
##
## This replaced a willow. A willow is a wide low dome, which is a real tree, a
## correct silhouette and — because it is the first thing everyone reaches for —
## the single most-copied river shape in stylised fantasy. §9 asks for something
## that carries information instead: 细长, 向水侧倾斜. A thin tree leaning out
## over the channel tells a player standing three hundred metres away which way
## the water is, which is a navigational job, and it costs the same polygons.
##
## BUILT leaning, and the instance leans too (`face: water` in FAMILIES). The
## two add deliberately: the MESH gives the curve, the INSTANCE gives the common
## direction. A straight stem tipped twelve degrees reads as a mistake; a curved
## one tipped reads as growth toward light.
func _river_tree(f: Dictionary, v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = f["bark"]
	var leaf: Color = f["leaf"]
	var tw := float(v) * 1.83
	var h := 4.05 + 0.60 * cell_hash(tw + 2.3, 5.5)
	var bz := 0.95 + 0.35 * cell_hash(tw + 6.7, 1.1)
	for sg in 4:
		var ta := float(sg) / 4.0
		var tb := float(sg + 1) / 4.0
		_taper(st, bark,
			Vector3(0.0, h * ta, bz * ta * ta),
			Vector3(0.0, h * tb, bz * tb * tb),
			lerpf(0.27, 0.12, ta), lerpf(0.27, 0.12, tb), 6)
	# Three short limbs, all on the outward side.
	for i in 3:
		var a := -1.05 + float(i) * 1.05 + tw
		_limb(st, bark, Vector3(0.0, h * (0.54 + 0.14 * float(i)), bz * 0.36),
			Vector3(cos(a) * 1.20, h * (0.70 + 0.14 * float(i)),
				bz * 0.55 + sin(a) * 1.20),
			0.085)
	# A NARROW crown, stacked: three masses, each smaller and higher. Width
	# stays near 2.3 m against 6-9 m of height, which is the whole silhouette —
	# a river tree is read as a THIN vertical from a long way off.
	_lobe(st, leaf, Vector3(0.0, h + 0.30, bz * 1.25), 1.15, 1.85, 0.30, 3, 6, tw + 1.1)
	_lobe(st, leaf, Vector3(0.0, h + 1.65, bz * 1.45 + 0.15), 0.92, 1.90, 0.30, 2, 6,
		tw + 4.3)
	_lobe(st, leaf, Vector3(0.0, h + 2.65, bz * 1.60 + 0.30), 0.62, 1.90, 0.32, 2, 5,
		tw + 8.9)
	return st.commit()


## MOUNTAIN PINE (§9): 更尖，更稀疏 — sharper and sparser.
##
## Two changes, both measured against the envelope rather than the tiers. The
## old stack was 2.10 m wide at the bottom and 0.74 m at the top over 5 tiers,
## which is a 4.2 m wide crown — a broad triangle. It now runs 1.36 m to 0.40 m,
## a 2.7 m crown, so the ENVELOPE (which is the only thing visible at 300 m)
## went from 22 degrees to 14 degrees of half-angle. A conifer is the one
## silhouette that has to be unmistakable at that range, because it is what
## tells the player the mountain has begun, and sharpness is what does it.
##
## Sparser comes from a longer bare stem (2.30 m against 1.90 m), smaller tiers,
## and per-tier lateral offsets so the stack is not a lathe.
func _pine(f: Dictionary, v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = f["bark"]
	var leaf: Color = f["leaf"]
	var tw := float(v) * 1.37
	_trunk(st, bark, 8.40, 0.26, 0.12, 5)
	# SIX TIERS THAT OVERLAP, WHERE THERE USED TO BE FIVE THAT DID NOT.
	#
	# The old tiers were 2.72 m wide and 1.70 m tall, set 1.62 m apart: the
	# vertical gap was small but each tier was WIDER THAN TALL, so what a player
	# saw was a stack of separate wide discs with a dark rim on each — a pile of
	# plates, not a conifer. §9 asks for 更尖更疏, sharper and sparser, and the
	# arithmetic that gets there is tiers TALLER THAN THEY ARE WIDE with a
	# vertical overlap, so consecutive tiers fuse into one serrated triangle.
	#
	# The overlap is 1.05 m on a 1.25 m stride, which is what makes the spire
	# continuous: every tier's base is already inside the tier below it.
	#
	# `_cone` is one triangle per side, so six tiers cost 2x7 + 4x5 = 34
	# triangles against the old 29. The best silhouette-per-triangle trade in
	# this file, and it buys the mountain tree its own outline.
	for i in 6:
		var k := float(i)
		var off := Vector3((cell_hash(k * 5.1, tw) - 0.5) * 0.24, 0.0,
			(cell_hash(k * 2.7, tw + 3.3) - 0.5) * 0.24)
		var yy := 2.05 + k * (1.25 + 0.10 * tw)
		var w := (1.14 - k * 0.16) * (0.94 + 0.12 * cell_hash(k * 3.3, tw))
		var hh := (2.30 - k * 0.09) * (0.96 + 0.10 * cell_hash(k * 1.7, tw + 2.0))
		_cone(st, leaf, yy, w, hh, 7 if i < 2 else 5, off)
	return st.commit()


## BAMBOO (§9): 完全不同轮廓 — a silhouette nothing else in this file can be
## mistaken for.
##
## The old version was five canes with a large lobe two thirds of the way up
## each, which read as a small round tree standing in a bundle. What bamboo
## actually looks like is a BRUSH: eight thin parallel verticals, bare for their
## lower two thirds, with all the foliage in one tight ragged band at the top.
## Same polygons, and it stops being a tree.
func _bamboo(f: Dictionary, v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark: Color = f["bark"]
	var leaf: Color = f["leaf"]
	var tw := float(v) * 1.61
	# Fewer canes than the 6/7/8 this started with, and the budget went into the
	# foliage instead. See the `rings 3` note below — a cane is 10 triangles and
	# those ten triangles are never what bamboo looks like.
	var n := 5 + v              # 5 / 6 / 7 canes
	for i in n:
		var a := TAU * float(i) / float(n) + tw
		var r := 0.22 + cell_hash(float(i) * 3.7 + tw, 1.3) * 0.58
		var hh := 5.4 + cell_hash(float(i) * 2.7 + tw, 4.1) * 3.4
		var ox := cos(a) * r
		var oz := sin(a) * r
		_cane(st, bark, ox, oz, hh, 0.060)
		# ---- `rings` 2 -> 3, AND THIS IS THE WHOLE OF "完全不同轮廓".
		#
		# A 2-ring lobe has exactly ONE band of quads between its two poles, so
		# its silhouette is a BIPYRAMID: straight edges converging on a point
		# above and below. It is not a rounded lump that happens to look
		# angular — the shape IS a diamond, at every size, from any angle. Two
		# of them per cane, on five to eight canes, put twelve to sixteen green
		# diamonds on a stick, and that is precisely what the review frame
		# showed once smooth normals stopped hiding it (§9's "stacked diamonds"
		# is the same defect the SMOOTH-SHADING call was masking).
		#
		# A third ring adds a second band, the poles stop being the widest part,
		# and the same silhouette becomes a lumpy mass with a flat waist. Two
		# extra triangles per side, on the cheapest family in the file.
		#
		# The two masses are deliberately given different squash and different
		# radial offset so the band they form is ragged rather than a pair of
		# matching lozenges.
		_lobe(st, leaf, Vector3(ox * 1.20, hh - 0.52, oz * 1.20),
			0.74 + 0.20 * cell_hash(float(i) * 1.9, tw), 1.34, 0.52, 3, 5,
			float(i) + tw)
		_lobe(st, leaf, Vector3(ox * 1.55, hh - 1.16, oz * 1.55),
			0.52 + 0.17 * cell_hash(float(i) * 4.3, tw + 1.7), 1.18, 0.52, 3, 5,
			float(i) + tw + 3.1)
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


## §10 — CLUMP LANGUAGE: five to twenty LARGE blades, not a fuzz of small ones.
##
## R01 walked into this from both sides. Broad blades on a short clump read as
## an ALOE — a succulent that was obviously placed. So the blades were halved
## twice, which fixed the aloe and produced a tuft that dissolved into the
## ground past a few metres and contributed nothing at all to the read.
##
## Both observations are correct and the resolution is the one stylised art
## uses: FEWER, WIDER, MORE DELIBERATE blades, where the count is what makes a
## clump legible. Seven to eleven blades you can count is a clump; ninety you
## cannot is noise. Width is set just short of the aloe threshold, and the
## outward BEND is what keeps it from reading as a succulent — an aloe's leaves
## stay near-vertical, grass arcs.
##
## HEIGHT COMES FROM THE RADIUS, not from an independent per-blade hash. Inner
## blades short and upright, outer blades long and arcing. Independent heights
## give a fuzzy mound; a radial profile gives a SHAPE with a readable outline,
## which is the whole of §10's last line.
func _grass_clump(f: Dictionary, v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf: Color = f["leaf"]
	var id := String(f["id"])
	var tall := id == "reed"
	var h := 0.95 if tall else (0.52 if id == "verge_grass" else 0.42)
	var n := 7 + v * 2          # 7 / 9 / 11 blades
	var spread := 0.30 + float(v) * 0.10
	for i in n:
		var a := TAU * float(i) / float(n) + float(v) * 1.7
		var t := cell_hash(float(i) * 3.1 + float(v) * 7.7, 1.3)
		var r := spread * (0.18 + 0.82 * t)
		var ox := cos(a) * r
		var oz := sin(a) * r
		var prof := 0.46 + 0.76 * (r / maxf(spread, 0.001))
		var hh := h * prof * (0.86 + 0.30 * cell_hash(
			float(i) * 1.7 + 0.5, float(v) * 2.3 + 2.9))
		var out_amt := hh * (0.14 + 0.34 * r / maxf(spread, 0.001))
		var w := 0.022 + 0.016 * cell_hash(float(i) * 2.9, 3.7)
		_blade2(st, leaf, ox, oz, hh, cos(a) * out_amt, sin(a) * out_amt, w)
	return st.commit()


## A heap of three to five loose stones.
##
## Small stones are the cheapest credible detail in the whole environment: they
## are 10-14 triangles each, they read at any distance a player can focus on
## them, and they are what makes a road edge look walked-on rather than painted.
## A SINGLE stone is a speck; the asset is the heap.
func _stone_meshes(base: Color) -> Array:
	var out: Array = []
	for v in 3:
		out.append(_stone_cluster(v, base))
	return out


func _stone_cluster(v: int, base: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
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
func _rock_meshes(base: Color) -> Array:
	var out: Array = []
	for v in 3:
		out.append(_rock_formation(v, base))
	return out


func _rock_formation(v: int, base: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 3 + (v % 3)        # 3 / 4 / 5
	# SIZES ARE RADII AND THEY MULTIPLY. `s` is a half-extent and the
	# per-instance scale in the family is applied on top of it. The first
	# version ran 0.75..2.10 x 0.90..2.00 = up to a 4.2 m RADIUS, i.e. an
	# eight-metre boulder, and rendered the Hero Zone as a field of dark
	# broken slabs. A formation of 0.45..1.10 m chunks at 0.70..1.30 is a
	# rock group; anything past that is a landform and belongs in the field.
	var spread := 0.58 + float(v) * 0.28
	for i in n:
		var a := TAU * float(i) / float(n) + float(v) * 1.31
		var r := spread * (0.20 + 0.80 * cell_hash(float(i) * 3.7 + float(v), 2.1))
		var s := 0.30 + 0.56 * cell_hash(float(i) * 1.9 + 0.3, float(v) * 3.3)
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
		var sq := 1.30 + 0.48 * cell_hash(float(i) * 2.7, float(v) * 4.4)
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
	return st.commit()


## Broken ground: a low irregular mound of soil.
##
## This is the MEDIUM scale the terrain structurally cannot carry. The terrain
## mesh samples the analytic heightfield every 3 m and interpolates, so there is
## no 1 m feature in it anywhere, at any budget — a shader can shade a mound
## that is not there but it cannot make one. Heaps beside a cut, spoil at the
## foot of a bank and root balls are the same asset at different scales.
func _mound_meshes(base: Color) -> Array:
	var out: Array = []
	for v in 3:
		out.append(_mound(v, base))
	return out


func _mound(v: int, base: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 0.62 was a 3.3:1 plate, and `sink` then ate the last of its thickness —
	# the family rendered as dark flat discs on otherwise clean grass. 0.98 is
	# a LOW MOUND: roughly twice as wide as it is tall, which is what a heap of
	# soil beside a cut actually is. `lit_top` puts the sun on its crown.
	_lobe(st, base, Vector3.ZERO, 0.62 + float(v) * 0.20, 0.98, 0.60, 2, 6 + v,
		float(v) * 7.3, true)
	return st.commit()


# =============================================================================
# ART DIRECTION PASS 04 — the LARGE scale
# =============================================================================

## HERO ROCK (§11/§12) — the first asset in this file that is DESIGNED.
##
## R01's rock layer was correct and small: 0.4-2 m formations, buried, grouped.
## What a frame made only of those lacks is COMPOSITION — nothing in it is large
## enough to be a shape rather than a texture, so the eye has nowhere to rest and
## the thumbnail test returns noise. §12: three of these are worth more than five
## hundred small stones. That is now literal — this family is 260 instances and
## the small-stone layer is 5,200.
##
## The form is three readable masses rather than a jittered blob, because §4
## names exactly what a designed rock has:
##
##   ONE STRONG DIAGONAL — a ridge of three decreasing chunks climbing out to
##   one side. This is what the eye reads first, because it is a direction.
##   ONE FLAT SHELF      — a wide low ledge jutting the other way, which gives
##   the diagonal a horizontal to lean against. Without it the diagonal reads
##   as a lean, with it the mass reads as balanced.
##   ONE BROKEN SIDE     — three chunks torn off and dropped at the foot on the
##   downhill side, so the outline is irregular exactly where it meets the
##   ground. That contact is the difference between a boulder and a prop.
##
## Nominal 5.6 x 3.6 m, so the family's 0.72-1.70 scale covers §12's 3 m to 8 m
## classes without a special case.
func _hero_meshes(base: Color) -> Array:
	var out: Array = []
	for v in 3:
		out.append(_hero_rock(v, base))
	return out


func _hero_rock(v: int, base: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tw := float(v) * 3.7
	var flip := 1.0 if v != 1 else -1.0
	# The body. Its base plane sits 0.86 m below the ground line and it is
	# 2.17 m tall, so 40% of it is buried — §7's "ROCKS MUST ENTER THE TERRAIN"
	# at the scale where it matters most.
	_lobe(st, base * 0.94, Vector3(-flip * 0.20, -0.86, 0.0),
		2.25, 1.06, 0.20, 2, 9, tw, true)
	# The diagonal.
	for i in 3:
		var k := float(i)
		_lobe(st, base * (0.99 + 0.10 * k),
			Vector3(flip * (0.58 + k * 0.70), 0.72 + k * 0.64, 0.10 + k * 0.10),
			1.14 - k * 0.24, 1.26, 0.28, 2, 7, tw + k * 3.3 + 1.0, true)
	# The shelf.
	_lobe(st, base * 1.02, Vector3(-flip * 1.74, -0.34, -0.22),
		1.66, 0.94, 0.26, 2, 7, tw + 6.1, true)
	# The broken side.
	for i in 3:
		var a := tw + TAU * float(i) / 3.0
		var rr := 1.90 + 0.60 * cell_hash(float(i) * 2.9, tw)
		var s := 0.40 + 0.28 * cell_hash(float(i) * 3.1, tw + 2.3)
		_lobe(st, base * (0.90 + 0.14 * cell_hash(float(i) * 5.1, 1.1)),
			Vector3(cos(a) * rr, -s * 0.30, sin(a) * rr),
			s, 1.22, 0.36, 2, 6, tw + float(i) * 4.9, true)
	return st.commit()


## ROCK SHELF — THE TERRAIN MODULE (§2/§3).
##
## §3 is the whole reason this exists: the target is not "hill PLUS stones", it
## is "the hill itself is exposing rock layers". Three strata of decreasing size,
## each offset laterally from the one below, so the stack's edge is a STAIR
## rather than a circle, plus two pieces that have come away and lie on the
## slope below.
##
## THE SUCCESS OF THIS ASSET IS ENTIRELY IN THE ORIENTATION, which is not here —
## see `align: slope` in FAMILIES and the alignment branch in `_emit`. A thin
## slab in LOCAL Y is a stratum lying IN the hill only because the instance has
## already been rotated onto the hill's own normal. Left level it would be a
## slab lying on a hill, which is the prop read.
##
## `squash` 0.34 is deliberately in the range this file spent three rounds
## learning to avoid. That rule is about a ground volume whose WIDEST ring has to
## clear the ground; a stratum is supposed to be a thin sheet, and it is only
## ever seen as one member of a stack.
func _shelf_meshes(base: Color) -> Array:
	var out: Array = []
	for v in 3:
		out.append(_shelf(v, base))
	return out


func _shelf(v: int, base: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tw := float(v) * 2.9
	# SIZES ARE RADII AND THEY MULTIPLY — the same trap as `_rock_formation`,
	# one scale up, and the first build walked straight into it. A 2.05 m base
	# slab under a 1.90 family scale under a 1.40 `slope_size` is a 5.5 m
	# RADIUS plate, i.e. eleven metres across, and 472 of them turned the hero
	# frame into a mosaic of pale sheets with no road in it. A shelf is an
	# OUTCROP: 1.3 m of base radius, 1.6 to 3.4 m across after scale, is a
	# band of exposed strata you can see the ground through.
	const SLAB := 1.32
	for i in 3:
		var k := float(i)
		var o := Vector3((cell_hash(k * 3.7, tw) - 0.5) * 0.62,
			k * 0.30,
			(cell_hash(k * 5.3, tw + 2.1) - 0.5) * 0.62)
		_lobe(st, base * (0.96 + 0.07 * k), o, SLAB - k * 0.22, 0.44, 0.30, 2, 7,
			tw + k * 4.3, true)
	for i in 2:
		var a := tw + TAU * float(i) / 2.0
		var rr := SLAB + 0.40 * cell_hash(float(i) * 2.7, tw)
		var s := 0.26 + 0.16 * cell_hash(float(i) * 4.1, tw + 6.3)
		_lobe(st, base * 0.92, Vector3(cos(a) * rr, -0.08, sin(a) * rr),
			s, 0.86, 0.36, 2, 5, tw + float(i) * 7.7, true)
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
		# A tapered tube's side normal is radial plus a small axial tilt: the
		# surface leans in or out by (r0 - r1) over the height. Getting this from
		# the two radii rather than from the triangles is what makes the trunk a
		# smooth cylinder instead of a hexagonal prism.
		var tilt := (r0 - r1) / maxf(h, 1e-4)
		var n0 := Vector3(cos(a0), tilt, sin(a0)).normalized()
		var n1 := Vector3(cos(a1), tilt, sin(a1)).normalized()
		st.set_normal(n0); st.set_color(c0); st.add_vertex(b0)
		st.set_normal(n1); st.set_color(c0); st.add_vertex(b1)
		st.set_normal(n1); st.set_color(c1); st.add_vertex(t1)
		st.set_normal(n0); st.set_color(c0); st.add_vertex(b0)
		st.set_normal(n1); st.set_color(c1); st.add_vertex(t1)
		st.set_normal(n0); st.set_color(c1); st.add_vertex(t0)


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
	var len := (to - from).length()
	# Radial normal tilted by the taper (1.0 at the root to 0.55 at the tip),
	# expressed in the limb's own frame. Same reasoning as `_trunk`.
	var tilt := 0.45 * r / maxf(len, 1e-4)
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := sx * cos(a0) + sy * sin(a0)
		var d1 := sx * cos(a1) + sy * sin(a1)
		var b0 := from + d0 * r
		var b1 := from + d1 * r
		var t0 := to + d0 * r * 0.55
		var t1 := to + d1 * r * 0.55
		var n0 := (d0 + axis * tilt).normalized()
		var n1 := (d1 + axis * tilt).normalized()
		st.set_normal(n0); st.set_color(c * 0.80); st.add_vertex(b0)
		st.set_normal(n1); st.set_color(c * 0.80); st.add_vertex(b1)
		st.set_normal(n1); st.set_color(c * 1.02); st.add_vertex(t1)
		st.set_normal(n0); st.set_color(c * 0.80); st.add_vertex(b0)
		st.set_normal(n1); st.set_color(c * 1.02); st.add_vertex(t1)
		st.set_normal(n0); st.set_color(c * 1.02); st.add_vertex(t0)


func _cane(st: SurfaceTool, c: Color, ox: float, oz: float, h: float, r: float) -> void:
	var sides := 5
	# Bamboo is the one stem in this file where the taper is almost invisible
	# (1.0 -> 0.85), so the tilt term is small — but a cane is also the thinnest
	# thing rendered here and a faceted one reads as a wire.
	var tilt := 0.15 * r / maxf(h, 1e-4)
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := Vector3(ox + cos(a0) * r, 0.0, oz + sin(a0) * r)
		var b1 := Vector3(ox + cos(a1) * r, 0.0, oz + sin(a1) * r)
		var t0 := Vector3(ox + cos(a0) * r * 0.85, h, oz + sin(a0) * r * 0.85)
		var t1 := Vector3(ox + cos(a1) * r * 0.85, h, oz + sin(a1) * r * 0.85)
		var n0 := Vector3(cos(a0), tilt, sin(a0)).normalized()
		var n1 := Vector3(cos(a1), tilt, sin(a1)).normalized()
		st.set_normal(n0); st.set_color(c * 0.8); st.add_vertex(b0)
		st.set_normal(n1); st.set_color(c * 0.8); st.add_vertex(b1)
		st.set_normal(n1); st.set_color(c); st.add_vertex(t1)
		st.set_normal(n0); st.set_color(c * 0.8); st.add_vertex(b0)
		st.set_normal(n1); st.set_color(c); st.add_vertex(t1)
		st.set_normal(n0); st.set_color(c); st.add_vertex(t0)


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
	# ANALYTIC NORMALS — see the note at the emit loop. The lobe is an ellipsoid
	# of horizontal semi-axis `r` and vertical semi-axis `squash * r / 2`, so
	# the outward normal at a surface point is the gradient of that ellipsoid,
	# which is `(rel.x / a^2, rel.y / b^2, rel.z / a^2)` normalised. Computing it
	# from the FINAL jittered position means the jitter is shaded too, instead of
	# being invisible geometry.
	var nms: Array[PackedVector3Array] = []
	var ctr_y := at.y + squash * r * 0.5
	var aa := r * r
	var bb := maxf(squash * r * 0.5, 1e-4)
	bb = bb * bb
	for ri in rings + 1:
		var v := float(ri) / float(rings)
		var phi := v * PI
		var row := PackedVector3Array()
		var nrow := PackedVector3Array()
		for si in sides:
			var th := TAU * float(si) / float(sides)
			var j := 1.0 + (MistvaleHeights.variation(
				th * 4.7 + float(ri) + off, float(si) * 2.3 + off * 1.7) - 0.5) * jitter
			var rr := sin(phi) * r * j
			var p := at + Vector3(cos(th) * rr,
				cos(phi) * squash * r * j * 0.5 + squash * r * 0.5, sin(th) * rr)
			row.append(p)
			nrow.append(Vector3((p.x - at.x) / aa, (p.y - ctr_y) / bb,
				(p.z - at.z) / aa).normalized())
		pts.append(row)
		nms.append(nrow)
	for ri in rings:
		# ---- THE SHADE IS PER ROW, NOT PER QUAD, AND THAT IS THE WHOLE
		# ---- DIFFERENCE BETWEEN A CANOPY AND A CRYSTAL.
		#
		# `generate_normals()` on unindexed triangles averages a normal only
		# where the whole VERTEX — position AND colour AND uv — is
		# byte-identical. The original code evaluated the ramp inside the `si`
		# loop from the quad's LOWER row index and stamped that one value on all
		# six corners, so the vertices of row `ri + 1` carried `shade(ri)` from
		# the quad above and `shade(ri + 1)` from the quad below. Every seam
		# vertex was therefore TWO DIFFERENT VERTICES, nothing merged, and every
		# facet kept its own flat normal.
		#
		# The result was the most damaging thing in the first ART DIRECTION
		# render: a stand of trees whose crowns were polished green CRYSTALS,
		# each face taking the sun separately. That is the "Low-poly Indie" read
		# the final art direction explicitly rejects, and it was never a
		# modelling decision — it was a colour attribute silently breaking vertex
		# deduplication.
		#
		# Evaluating the ramp once per ROW makes the seam vertices identical, the
		# hash matches, the normals average, and the very same triangles come
		# back as a soft canopy mass. Cost: zero. Triangle count: unchanged.
		#
		# CANOPY ramp is the default: the underside is the face a player standing
		# under a tree actually sees, so the lobe is baked with the underside
		# brightest (ri = rings) and the crown darkest — 0.86..1.00.
		#
		# `lit_top` INVERTS IT, and every GROUND volume passes true. A boulder, a
		# cobble and a heap of soil are seen from above and from the side, never
		# from underneath, so there the crown is exactly the face the sun lands
		# on. Inheriting the canopy ramp painted every one of them at 0.86 on its
		# ONLY sunlit surface, and no colour put into `c` could win that back: it
		# is half of why the whole rock family rendered as dark shards.
		var t := float(ri) / float(rings)
		var sh_lo := 0.86 + 0.14 * t
		var sh_hi := 0.86 + 0.14 * (float(ri + 1) / float(rings))
		if lit_top:
			sh_lo = 0.90 - 0.24 * t
			sh_hi = 0.90 - 0.24 * (float(ri + 1) / float(rings))
		var c_lo := c * sh_lo
		var c_hi := c * sh_hi
		# FACETED OR SMOOTH IS A DESIGN DECISION, AND IT IS PER PRIMITIVE.
		#
		# `lit_top` was introduced as "invert the baked ramp" and it turns out to
		# be exactly the file's existing marker for a CLOSED GROUND VOLUME: every
		# boulder, cobble, soil heap, hero rock and shelf passes it true, and not
		# one canopy, bush or tree does. So it is reused here rather than adding a
		# sixth parameter to eleven call sites.
		#
		# The two want opposite shading and §4 / §7 ask for opposite things:
		#   * GROUND VOLUME -> FLAT. Large planes, explicit edges, a strong
		#     silhouette. A facet that catches the sun on one face and not the
		#     next IS the rock shape language; smoothing it turns a boulder into
		#     a pillow.
		#   * CANOPY -> SMOOTH. The crown of a tree is one mass. Faceting it is
		#     what made the first render read as polished green crystals.
		var smooth := not lit_top
		for si in sides:
			var s2 := (si + 1) % sides
			var a := pts[ri][si]
			var b := pts[ri][s2]
			var cc := pts[ri + 1][s2]
			var d := pts[ri + 1][si]
			# SMOOTH SHADING BY HAND, BECAUSE `generate_normals()` IS FLAT HERE.
			#
			# The reason this file sets normals explicitly instead of calling the
			# helper is measured, not assumed. On the d=120 frame:
			#
			#   * `generate_normals()` after per-QUAD colours  -> crystal facets
			#   * after per-ROW colours (so every shared vertex is byte-identical)
			#     -> BYTE-IDENTICAL image, md5 unchanged
			#   * after `st.index()` (explicit vertex dedup)   -> identical again
			#   * after `set_smooth_group(0)` on every vertex  -> identical again
			#   * after widening the baked ramp 0.86..1.00 to 0.50..1.00 -> changed,
			#     but still faceted
			#
			# Four independent attempts to make the helper smooth, four null
			# results. THE REASON IS THAT EVERY BUILDER CALLS IT ONCE MORE,
			# IMMEDIATELY BEFORE `commit()` — that is what the helper is for, it
			# recomputes and OVERWRITES the normal array, so all four experiments
			# were overwritten by the very line they were trying to influence.
			# The lesson is not "the helper cannot smooth" but "normals you do
			# not own, you do not control": `generate_normals()` is now gone from
			# every builder and each primitive writes its own.
			#
			# So: analytic ellipsoid normals for canopies (smooth), an outward
			# face normal per triangle for ground volumes (faceted), and the
			# choice is made where the shape language is — at the primitive.
			st.set_smooth_group(-1)
			if smooth:
				st.set_normal(nms[ri][si]);     st.set_color(c_lo); st.add_vertex(a)
				st.set_normal(nms[ri][s2]);     st.set_color(c_lo); st.add_vertex(b)
				st.set_normal(nms[ri + 1][s2]); st.set_color(c_hi); st.add_vertex(cc)
				st.set_normal(nms[ri][si]);     st.set_color(c_lo); st.add_vertex(a)
				st.set_normal(nms[ri + 1][s2]); st.set_color(c_hi); st.add_vertex(cc)
				st.set_normal(nms[ri + 1][si]); st.set_color(c_hi); st.add_vertex(d)
			else:
				# One normal per TRIANGLE, oriented outward by agreement with the
				# analytic normal at its own corners. Asking the two to agree is
				# what makes this safe: the sign of `cross()` depends on the
				# winding, the winding flips between the pole rows and the middle
				# rows, and Godot's front-face convention is one more thing not
				# worth reasoning about when the geometry will answer directly.
				var n1 := _outward_face(a, b, cc, nms[ri][si], nms[ri][s2],
					nms[ri + 1][s2])
				var n2 := _outward_face(a, cc, d, nms[ri][si], nms[ri + 1][s2],
					nms[ri + 1][si])
				st.set_normal(n1); st.set_color(c_lo); st.add_vertex(a)
				st.set_normal(n1); st.set_color(c_lo); st.add_vertex(b)
				st.set_normal(n1); st.set_color(c_hi); st.add_vertex(cc)
				st.set_normal(n2); st.set_color(c_lo); st.add_vertex(a)
				st.set_normal(n2); st.set_color(c_hi); st.add_vertex(cc)
				st.set_normal(n2); st.set_color(c_hi); st.add_vertex(d)


## The face normal of a triangle, flipped if it disagrees with the analytic
## outward direction at its corners.
##
## Written as a helper with a name rather than inlined three times because the
## flip is the part that is easy to get wrong and impossible to see: a lobe whose
## normals all point inward is lit from behind and comes back as a black blob,
## which reads as "the family is missing" and sends you looking at the scatter
## masks instead of at the normals.
static func _outward_face(
	p0: Vector3, p1: Vector3, p2: Vector3,
	n0: Vector3, n1: Vector3, n2: Vector3
) -> Vector3:
	var f := (p1 - p0).cross(p2 - p0)
	if f.length_squared() < 1e-12:
		# Degenerate triangle (a pole row collapses to a point). There is no face
		# normal; the smooth normals are the only honest answer.
		return (n0 + n1 + n2).normalized()
	f = f.normalized()
	return -f if f.dot(n0 + n1 + n2) < 0.0 else f


func _cone(
	st: SurfaceTool, c: Color, y0: float, r: float, h: float, sides: int,
	off: Vector3 = Vector3.ZERO
) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := off + Vector3(cos(a0) * r, y0, sin(a0) * r)
		var b1 := off + Vector3(cos(a1) * r, y0, sin(a1) * r)
		# The apex is offset too, by half: a tier whose tip sits over its own
		# centre is a lathe. Half the offset keeps the tier attached to the
		# trunk while making the cone lean, which is what a real branch layer
		# does and what stops a stack of them reading as one machined shape.
		var tip := off * 0.5 + Vector3(0.0, y0 + h, 0.0)
		var shade := 0.58 + 0.30 * (0.5 + 0.5 * sin(a0))
		# A cone side's normal is perpendicular to both the slant and the
		# circumference. Because the apex is OFFSET the surface is a slanted
		# ellipse rather than a circle of revolution, so the true normal is not
		# simply (cos a, r/h, sin a) — and taking the cross product of those two
		# tangents gets the lean right for free, which matters because the lean
		# is the whole reason the apex is offset.
		var n0 := _cone_side(b0, tip, a0)
		var n1 := _cone_side(b1, tip, a1)
		# Smooth cone: the apex carries the mean of its two base normals, so a
		# pine tier is a smooth cone rather than a 7-sided pyramid. A faceted
		# tier is what made the first pine read as a stack of paper cones.
		var nt := (n0 + n1).normalized()
		st.set_normal(n0); st.set_color(c * shade); st.add_vertex(b0)
		st.set_normal(n1); st.set_color(c * shade); st.add_vertex(b1)
		st.set_normal(nt); st.set_color(c * (shade + 0.28)); st.add_vertex(tip)


## Outward normal of a cone's side at a base-ring point, given the apex.
##
## `p` is on the base ring, `apex` is the tip. The two tangents of the ruled
## surface at `p` are the circumferential one and the slant one; the normal is
## their cross product. Its SIGN is settled against the radial direction rather
## than by the argument order, for the same reason `_outward_face` does it: the
## direction the apex leans in can push the cross product either way.
static func _cone_side(p: Vector3, apex: Vector3, a: float) -> Vector3:
	var tang := Vector3(-sin(a), 0.0, cos(a))
	var n := tang.cross(apex - p)
	if n.length_squared() < 1e-12:
		return Vector3(cos(a), 0.0, sin(a))
	n = n.normalized()
	var radial := Vector3(cos(a), 0.0, sin(a))
	return -n if n.dot(radial) < 0.0 else n


## A tapered segment between two rings with an explicit radius at each end.
##
## `_limb` tapers to a fixed 0.55 of its base, which is right for a branch and
## wrong for a TRUNK built as a chain: the end radius of one segment is not the
## start radius of the next, so a three-segment trunk comes back as a stack of
## cones with a visible step at every joint. The whole point of a trunk gesture
## (§7) is that it reads as ONE continuous leaning stem, so both radii have to
## be parameters.
func _taper(
	st: SurfaceTool, c: Color, a: Vector3, b: Vector3, ra: float, rb: float,
	sides: int = 6
) -> void:
	var axis := b - a
	var len := axis.length()
	if len * len < 1e-8:
		return
	axis = axis / len
	var up := Vector3(0.0, 1.0, 0.0)
	if absf(axis.dot(up)) > 0.98:
		up = Vector3(1.0, 0.0, 0.0)
	var sx := axis.cross(up).normalized()
	var sy := axis.cross(sx).normalized()
	# Radial normal tilted by the taper, in the segment's own frame. The
	# per-side ellipse jitter below is ignored here on purpose: it is at most a
	# 10% radius wobble and shading it would cost the one thing this function
	# exists for, which is a stem that reads as ONE continuous leaning shape.
	var tilt := (ra - rb) / len
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		# A slight ellipse, so a trunk is not a pipe.
		var j0 := 0.90 + 0.10 * sin(a0 * 2.0 + 1.1)
		var j1 := 0.90 + 0.10 * sin(a1 * 2.0 + 1.1)
		var d0 := sx * cos(a0) + sy * sin(a0)
		var d1 := sx * cos(a1) + sy * sin(a1)
		var n0 := (d0 + axis * tilt).normalized()
		var n1 := (d1 + axis * tilt).normalized()
		st.set_normal(n0); st.set_color(c * 0.74); st.add_vertex(a + d0 * ra * j0)
		st.set_normal(n1); st.set_color(c * 0.74); st.add_vertex(a + d1 * ra * j1)
		st.set_normal(n1); st.set_color(c * 1.00); st.add_vertex(b + d1 * rb * j1)
		st.set_normal(n0); st.set_color(c * 0.74); st.add_vertex(a + d0 * ra * j0)
		st.set_normal(n1); st.set_color(c * 1.00); st.add_vertex(b + d1 * rb * j1)
		st.set_normal(n0); st.set_color(c * 1.00); st.add_vertex(b + d0 * rb * j0)


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
	# A blade is a card, so it has ONE normal and it is perpendicular to the
	# blade's own plane: the cross product of its width direction with the
	# vertical. Written from `nx`/`nz` rather than taken per triangle because on
	# a two-segment ribbon the lower quad and the tip triangle are not coplanar,
	# and letting each facet find its own normal is exactly the mistake that
	# turned the canopies into crystals — at 3 cm of blade it is invisible, but
	# the rule is the rule and the next shape that reuses this function will be
	# larger.
	#
	# The material is CULL_DISABLED and Godot flips the normal on back faces, so
	# one normal covers both sides of the card.
	var nb := Vector3(-nx, 0.0, -nz).normalized()
	st.set_normal(nb); st.set_color(c * 0.72); st.add_vertex(b0)
	st.set_normal(nb); st.set_color(c * 0.72); st.add_vertex(b1)
	st.set_normal(nb); st.set_color(c * 0.96); st.add_vertex(m1)
	st.set_normal(nb); st.set_color(c * 0.72); st.add_vertex(b0)
	st.set_normal(nb); st.set_color(c * 0.96); st.add_vertex(m1)
	st.set_normal(nb); st.set_color(c * 0.96); st.add_vertex(m0)
	st.set_normal(nb); st.set_color(c * 0.96); st.add_vertex(m0)
	st.set_normal(nb); st.set_color(c * 0.96); st.add_vertex(m1)
	st.set_normal(nb); st.set_color(c * 1.10); st.add_vertex(tip)
