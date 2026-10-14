# Mistvale, playable. The imported UE5 town, the real first-person Player, and
# the anchors gameplay will later attach to.
#
# WHY THIS IS A NEW SCENE AND NOT A REWRITE OF MistvaleRegion.tscn:
# MistvaleRegion.tscn is the LD-01 greybox and its header says it is owned by
# the ART line. This scene replaces it as the place the region door opens; it
# does not delete it. When the UE5 art becomes the town, the greybox stops being
# the world but stays a usable blockout reference.
#
# GEOMETRY IS NOT RE-TYPED HERE. Every anchor is derived at run time from the
# world-space bounds of the named actors in the imported map, so there is
# exactly one place a position is written down -- the model -- and moving the
# model moves the anchors with it. Hand-copying a church's coordinates into a
# POI is the same class of mistake as the PlayerStart that was placed at the
# mirrored Y and ended up 24 m under the ground (see _place_player()).
#
# WHAT THIS SCRIPT DOES NOT DO: it does not touch Player.tscn, the combat
# controller, the weapon state machine or main_flow. It mounts the real Player
# and gets out of the way.

extends Node3D

const GLB := "res://models/mistvale_ue/mistvale_rebuild.glb"
const COLLISION := "res://models/mistvale_ue/mistvale_collision.res"

## The south approach, in the map's own coordinates. The handoff left
## PlayerStart_MistvaleSouth at UE (600, -31000, 157.62) cm -- which is in the
## opposite half of the map from the golden route's south end AND 24 m below the
## ground, because the height was probed with the Y axis already flipped while
## the coordinate was not. The spawn is therefore re-derived here from the route
## surface itself (see _place_player), and the depth in from its southern end is
## the only authored number.
const SPAWN_INSET := 10.0
## Where the route surfaces are read to find that start point.
const ROUTE_SOUTH_SOURCE := "ART_Surface_SM_Route_GoldenRoute_South"
## How much of a route ribbon counts as "its end" when reading the local axis.
const END_SPAN := 12.0

## Falling out of the world must not mean restarting the game. The map floor is
## at y = -3.22 (terrain minimum); anything below this is off the map.
const FALL_FLOOR := -12.0
const PLAYER_CAPSULE_HALF := 0.9

## Anchor table: name -> (source actor, how to pick a point out of its bounds).
##   "centre"     middle of the actor's world AABB
##   "south_end"  centre.x, just inside the -Z end (the approach side)
##   "north_end"  centre.x, just inside the +Z end
##   "beyond_n"   past the +Z end, i.e. where a world exit would sit
##   "beyond_s"   past the -Z end
##   "inset_sw"   half-way out toward the -X/-Z quadrant (used to step off a
##                plaza's exact centre when something is standing on it)
##   "inset_se"   the same toward +X/-Z
## The source names are the UE actor labels, preserved through the FBX and the
## glTF round trip and asserted by tools/probe_mistvale_ue.gd.
##
## BUILDINGS ARE NOT THE POI, THEIR APPROACH IS. The first version pointed
## POI_Guild at HERO_Guild_HorizontalHall and POI_Church at HERO_Church_Nave and
## put both on the roof: grounded from the actor's own TOP they read 30.32 and
## 29.61, against forecourts at 16.2-18.0 and 19.2-22.1. A POI a player cannot
## stand on is worse than no POI, so the buildings now source the forecourt that
## fronts them, and AGENTS.md's "Guild entrance" / "Church approach" is what the
## anchor actually marks.
const ANCHORS := [
	# --- POI: places gameplay will ask for by name (brief §16-23)
	{"name": "POI_SouthEntry", "source": "ART_Surface_SM_Route_GoldenRoute_South", "mode": "route_start"},
	{"name": "POI_Riverside", "source": "ART_Surface_SM_Route_RiversideStreet", "mode": "centre"},
	{"name": "POI_MainBridge", "source": "MainStoneBridge_DECK", "mode": "centre"},
	# Off-centre by half the plaza radius: MarketSquare_Well stands at exactly
	# (0.00, 100.00) and is 3 m across, so the plaza's own centre is the well.
	{"name": "POI_Market", "source": "ART_Surface_SM_Plaza_MarketSquare", "mode": "inset_sw"},
	{"name": "POI_Guild", "source": "ART_Surface_SM_Plaza_GuildForecourt", "mode": "centre"},
	{"name": "POI_GuildTraining", "source": "HERO_Guild_TrainingYard", "mode": "centre"},
	{"name": "POI_Church", "source": "ART_Surface_SM_Plaza_ChurchForecourt", "mode": "centre"},
	{"name": "POI_NorthGate", "source": "HERO_NorthGate_Lintel", "mode": "centre"},
	# --- world exits: current map is region 1; these are where the next cell
	#     attaches. No loading is implemented and none should be (brief §20-22).
	{"name": "TRG_SouthWorldExit", "source": "ART_Surface_SM_Route_GoldenRoute_South", "mode": "route_beyond_s"},
	{"name": "TRG_NorthGateExit", "source": "HERO_NorthGate_Lintel", "mode": "beyond_n"},
	{"name": "TRG_RiverRoute", "source": "ART_Surface_SM_Route_RiversideStreet", "mode": "centre"},
	# --- safe points: fall recovery targets, no UI (brief §31)
	{"name": "SAFE_South", "source": "ART_Surface_SM_Route_GoldenRoute_South", "mode": "route_start"},
	{"name": "SAFE_Bridge", "source": "MainStoneBridge_DECK", "mode": "centre"},
	{"name": "SAFE_Market", "source": "ART_Surface_SM_Plaza_MarketSquare", "mode": "inset_sw"},
	{"name": "SAFE_Guild", "source": "HERO_Guild_TrainingYard", "mode": "centre"},
	{"name": "SAFE_Church", "source": "ART_Surface_SM_Plaza_ChurchForecourt", "mode": "centre"},
	{"name": "SAFE_NorthGate", "source": "HERO_NorthGate_Lintel", "mode": "centre"},
	# --- narrative anchors: positions only. No NPCs, no story (brief §24).
	{"name": "ANCHOR_Lia_River", "source": "ART_Surface_SM_Route_RiversideStreet", "mode": "centre"},
	{"name": "ANCHOR_Oren_Workshop", "source": "HERO_Blacksmith", "mode": "centre"},
	{"name": "ANCHOR_Mira_TownEdge", "source": "ART_Surface_SM_Route_GoldenRoute_Town", "mode": "route_start"},
	{"name": "ANCHOR_Veil_Guild", "source": "ART_Surface_SM_Plaza_GuildForecourt", "mode": "inset_se"},
	{"name": "ANCHOR_Taim_SouthRoad", "source": "ART_Surface_SM_Route_GoldenRoute_South", "mode": "route_start"},
]

## Grounding the anchors. The reference height differs by what the source is,
## and getting that wrong is what put five anchors on roofs:
##
## OBSTACLES (buildings, props, the gate) are referenced from their BASE, because
## a building's base is at grade and its roof is not:
##
##   HERO_Guild_HorizontalHall  base 16.74 (its forecourt is 16.19-18.00),
##                              roof 36.96
##   HERO_Church_Nave           base 20.81 (forecourt 19.16-22.05), roof 34.57
##   HERO_Blacksmith            base 12.90, roof 21.00
##
## SURFACES (the route ribbons, plazas, decks, ramps) are referenced from their
## nearest VERTEX, because neither end of their AABB is local. The main bridge
## deck's AABB runs y 0.54..8.17: 0.54 is the arch soffit over the water and 8.17
## is a parapet, while the walkway is 6.374. Referencing it from its base put
## POI_MainBridge 5.8 m under the bridge, in the river. The south road's AABB
## climbs 0.40..5.88 over 205 m, so neither its base nor its top is local either.
##
## How to tell them apart is not a guess: the level names its own walking surface
## actors ART_Surface_*. Everything else is an obstacle.
const SURFACE_TOKENS := ["ART_Surface_", "SM_Handoff_", "ServiceBridge_", "StoneBridge_DECK"]

const PROBE_UP := 1.2
const PROBE_DOWN := 8.0
## An anchor this far above its own actor's base is on something, not on ground.
const ROOF_SUSPECT := 2.0

@onready var player: CharacterBody3D = $Player

var _safe_points: Array[Vector3] = []
var _missing_anchors: Array[String] = []
var _missing_sources: Array[String] = []
var _anchor_audit: Array = []
var _spawn_audit: Dictionary = {}


func _ready() -> void:
	_build_art()
	_build_collision()
	_build_anchors()
	# Collision added this frame is not queryable until physics has stepped, and
	# the spawn is a raycast, so it waits two frames rather than trusting a
	# hand-written height. This is the difference between "spawns on the road"
	# and "spawns 24 m inside the hill".
	await get_tree().physics_frame
	await get_tree().physics_frame
	_place_player()


func _build_art() -> void:
	var packed := load(GLB) as PackedScene
	if packed == null:
		push_error("Mistvale art missing: %s" % GLB)
		return
	var art := packed.instantiate()
	art.name = "Art"
	# The map carries its own node transforms and must not be re-scaled or
	# rotated: the export was verified against the UE world AABBs to 0.1 mm and
	# any "correction" here would reintroduce exactly the axis flip that was
	# ruled out by measurement.
	add_child(art)


func _build_collision() -> void:
	var shape := load(COLLISION) as ConcavePolygonShape3D
	if shape == null:
		push_error("Mistvale collision missing: %s" % COLLISION)
		return
	var body := StaticBody3D.new()
	body.name = "Ground"
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


## Turn the anchor table into named Node3D markers under Anchors/.
func _build_anchors() -> void:
	var art := get_node_or_null("Art") as Node3D
	var root := Node3D.new()
	root.name = "Anchors"
	add_child(root)
	if art == null:
		return
	var by_name := {}
	for node in art.find_children("*", "MeshInstance3D", true, false):
		by_name[node.name] = node

	for row in ANCHORS:
		var source: String = row["source"]
		var node := by_name.get(source) as MeshInstance3D
		if node == null:
			_missing_sources.append(source)
			_missing_anchors.append(row["name"])
			continue
		var aabb: AABB = node.global_transform * node.get_aabb()
		var point: Vector3
		# Modes that need the ribbon's own local axis rather than its AABB centre.
		# A route actor's AABB centre is meaningless along its length: the south
		# road's AABB centres on x = -0.50 while its centre at the south end is
		# x = +6.0, because the AABB spans 205 m of the road's swing.
		match row["mode"]:
			"route_start":
				point = Vector3(_end_axis_x(node, true), aabb.position.y,
					aabb.position.z + 6.0)
			"route_end":
				point = Vector3(_end_axis_x(node, false), aabb.position.y,
					aabb.end.z - 6.0)
			"route_beyond_s":
				point = Vector3(_end_axis_x(node, true), aabb.position.y,
					aabb.position.z - 6.0)
			_:
				point = _anchor_point(aabb, row["mode"])
		# Ground the marker. Casting from just above the local reference makes the
		# roof unreachable; see PROBE_UP.
		var base := aabb.position.y
		var ref := _local_ref_y(node, aabb, point.x, point.z)
		point.y = _ground_y(point.x, point.z, ref)
		var marker := Node3D.new()
		marker.name = row["name"]
		marker.position = point
		root.add_child(marker)
		if str(row["name"]).begins_with("SAFE_"):
			_safe_points.append(point)
		# Say out loud which ones ended up above their own actor's base, so a
		# roof can never again pass as ground without appearing in the report.
		_anchor_audit.append({
			"name": str(row["name"]), "source": source, "mode": str(row["mode"]),
			"x": snappedf(point.x, 0.01), "y": snappedf(point.y, 0.01),
			"z": snappedf(point.z, 0.01),
			"base_y": snappedf(base, 0.01),
			"above_base": snappedf(point.y - base, 0.01),
			# Only meaningful for obstacles. A surface's "base" is not ground --
			# the bridge deck's base is the arch soffit, so its walkway is
			# legitimately 5.8 m above it. Flagging that would train the reader to
			# ignore the flag, which is worse than not having one.
			"suspect_roof": (not _is_surface_name(source)) and (point.y - base) > ROOF_SUSPECT,
		})


func _is_surface_name(actor_name: String) -> bool:
	for token in SURFACE_TOKENS:
		if token in actor_name:
			return true
	return false


func _anchor_point(aabb: AABB, mode: String) -> Vector3:
	var centre := aabb.position + aabb.size * 0.5
	var hx := aabb.size.x * 0.25
	var hz := aabb.size.z * 0.25
	match mode:
		"centre":
			return centre
		"south_end":
			return Vector3(centre.x, centre.y, aabb.position.z + 4.0)
		"north_end":
			return Vector3(centre.x, centre.y, aabb.end.z - 4.0)
		"beyond_n":
			return Vector3(centre.x, centre.y, aabb.end.z + 6.0)
		"beyond_s":
			return Vector3(centre.x, centre.y, aabb.position.z - 6.0)
		"inset_sw":
			return Vector3(centre.x - hx, centre.y, centre.z - hz)
		"inset_se":
			return Vector3(centre.x + hx, centre.y, centre.z - hz)
		_:
			return centre


## The local ground reference for an anchor source. See SURFACE_TOKENS.
func _local_ref_y(node: MeshInstance3D, aabb: AABB, x: float, z: float) -> float:
	if not _is_surface_name(node.name):
		return aabb.position.y
	var mesh: Mesh = node.mesh
	if mesh == null:
		return aabb.position.y
	var xf: Transform3D = node.global_transform
	var best := INF
	var y := aabb.position.y
	for s in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			var w: Vector3 = xf * v
			var d := Vector2(w.x - x, w.z - z).length_squared()
			if d < best:
				best = d
				y = w.y
	return y if best != INF else aabb.position.y


## Raycast the finished collision for the surface under (x, z).
##
## ref_y is the local reference height (a base, or a surface vertex). Probing
## from just above it means the ray can only find a surface at or below it, which
## is what "the ground here" means; probing from far above finds whatever the
## actor put overhead instead.
func _ground_y(x: float, z: float, ref_y: float) -> float:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, ref_y + PROBE_UP, z), Vector3(x, ref_y - PROBE_DOWN, z))
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return ref_y
	return hit["position"].y


## Put the real Player on the south approach, facing the town.
##
## The x comes from the route ribbon's own southern end, not from a constant.
## The road's whole-actor AABB centres on x = -0.50, but that AABB spans the
## road's entire 205 m swing; the ribbon is actually 6 m wide and its centre at
## the south end is x = +6.0. Spawning on the AABB centre would have put the
## player on the verge, 6.5 m west of the road, for the sake of a number that
## looked authoritative.
func _place_player() -> void:
	var art := get_node_or_null("Art") as Node3D
	var road: MeshInstance3D = null
	if art != null:
		road = art.find_child(ROUTE_SOUTH_SOURCE, true, false) as MeshInstance3D
	if road == null:
		push_error("Mistvale spawn: no %s to read the route from" % ROUTE_SOUTH_SOURCE)
		return
	var aabb: AABB = road.global_transform * road.get_aabb()
	var x := _end_axis_x(road, true)
	var z := aabb.position.z + SPAWN_INSET
	var ground_y := _ground_y(x, z, _local_ref_y(road, aabb, x, z))
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, ground_y + 3.0, z), Vector3(x, ground_y - 3.0, z))
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		push_error("Mistvale spawn: nothing solid under (%.1f, %.1f)" % [x, z])
		return
	player.global_position = Vector3(x, hit["position"].y + PLAYER_CAPSULE_HALF + 0.05, z)
	# The golden route runs toward +Z; Godot's forward is -Z, so facing the town
	# is a half turn. Facing the bridge at spawn is the point of the approach.
	player.rotation.y = PI
	_spawn_audit = {"x": snappedf(x, 0.01), "y": snappedf(player.global_position.y, 0.01),
		"z": snappedf(z, 0.01), "ground_y": snappedf(hit["position"].y, 0.01)}


## Midpoint of one end of a route ribbon: the x centre of its southern (or
## northern) END_SPAN metres. Midpoint rather than median because the median is
## biased by where the modeller put vertex rows -- on the bridge deck that put
## the centre on the parapet, which is why the walk tool measures it this way too.
func _end_axis_x(node: MeshInstance3D, southern: bool) -> float:
	var mesh: Mesh = node.mesh
	if mesh == null:
		return 0.0
	var xf: Transform3D = node.global_transform
	var aabb: AABB = xf * node.get_aabb()
	var lo := INF
	var hi := -INF
	for s in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			var w: Vector3 = xf * v
			var near := false
			if southern:
				near = w.z <= aabb.position.z + END_SPAN
			else:
				near = w.z >= aabb.end.z - END_SPAN
			if not near:
				continue
			lo = minf(lo, w.x)
			hi = maxf(hi, w.x)
	if lo > hi:
		return aabb.get_center().x
	return (lo + hi) * 0.5


## Fall recovery (brief §30). One collision bug must not cost a restart.
func _physics_process(_delta: float) -> void:
	if player == null or _safe_points.is_empty():
		return
	if player.global_position.y > FALL_FLOOR:
		return
	var here := player.global_position
	var best := _safe_points[0]
	var best_d := INF
	for p in _safe_points:
		var d := here.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = p
	player.global_position = best + Vector3(0, PLAYER_CAPSULE_HALF + 0.1, 0)
	player.velocity = Vector3.ZERO


func report() -> Dictionary:
	var suspect: Array = []
	for a in _anchor_audit:
		if a["suspect_roof"]:
			suspect.append(a)
	return {
		"safe_points": _safe_points.size(),
		"missing_sources": _missing_sources,
		"missing_anchors": _missing_anchors,
		"player_spawn": player.global_position if player else null,
		"spawn_audit": _spawn_audit,
		"anchor_audit": _anchor_audit,
		"suspect_roof": suspect,
	}
