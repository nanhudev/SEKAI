# Walk the golden route the way a body walks it.
#
# This replaces the earlier straight-line march. That march ran at a constant
# x = 6.0 and reported 19 "steps" -- which turned out to be two artefacts of the
# instrument, not defects in the map:
#
#   1. z = 5.5..12.5  the line ran up the ROOF of LowerEastA_House_02
#                     (x[5.37,15.80] z[4.43,12.18]). The authored town road is at
#                     x[-32.58,2.60] there, so the road is clear; my line was not
#                     on the road.
#   2. z = 280..287   the line hit HERO_NorthGate_Lintel, which spans the road
#                     overhead, and alternated between the lintel top (30.3) and
#                     the road (24.4).
#
# Both are the same mistake: casting a ray down from far above the map and
# calling whatever it lands on "the ground". A walker is not a ray from the sky.
# So this script:
#
#   * derives the path from the AUTHORED route surfaces, so "on the route" is
#     the map's own definition rather than my guess at an x coordinate;
#   * casts the ground ray from the walker's own head (prev + eye height) with a
#     finite length, so geometry ABOVE the walker can never be mistaken for the
#     surface under it;
#   * adds a forward chest-height ray, because a wall you are walking into
#     cannot be found by looking straight down at it.
#
# Failure modes reported, per step:
#   HOLE     the ground ray missed entirely            -> the player falls through
#   STEP     surface rose > 0.35 m                     -> a rise the capsule
#            (r = 0.35) cannot climb in one stride
#   BLOCKED  the forward probe hit something nearer
#            than the stride                          -> a wall across the route
#
# Run: godot --headless --path godot --script res://tools/walk_mistvale_route.gd

extends SceneTree

const SCENE := "res://scenes/world/MistvalePlayable.tscn"
const OUT := "F:/SEKAI/ue5_lab/Mistvale_Rebuild/_handoff/godot_walk_report.json"

## The authored route, south end first. These are the level's own surfaces, not
## a reconstruction: MainStoneBridge_DECK and the two handoff ramps are what the
## bridge handoff pass replaced the old ramp meshes with.
const ROUTE_SOURCES := [
	"ART_Surface_SM_Route_GoldenRoute_South",
	"SM_Handoff_BridgeSouth",
	"MainStoneBridge_DECK",
	"SM_Handoff_BridgeNorth",
	"ART_Surface_SM_Route_GoldenRoute_Town",
]

const EYE := 1.65          # standing eye height (brief §26: 1.6-1.7 m)
const REACH_DOWN := 6.0    # how far below the walker the surface may be
const STEP_LIMIT := 0.35   # capsule radius
const STRIDE := 1.0        # metres per stride
const BIN := 0.5           # z bucket for the centreline
const CLUSTER_GAP := 2.0   # x gap that separates two parallel lanes
const MIN_LANE_W := 2.0    # narrower than this is an edge loop, not a lane
const WINDOW := 2.0        # metres of z the cross-section is measured over
const ROAD_MAX_W := 22.0   # a lane wider than this is a bend, not a road
const ANCHOR_TOLERANCE := 2.0  # anchor may sit this far off the route height
const NAME_PROBE_DROP := 0.10  # name a surface by the point just underfoot

var _art: Node3D
var _boxes: Array = []   # [{name, aabb}] for naming whatever we bump into


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var packed := load(SCENE) as PackedScene
	if packed == null:
		printerr("NO VERDICT: cannot load ", SCENE)
		quit(1)
		return
	var world := packed.instantiate() as Node3D
	get_root().add_child(world)
	for _i in 8:
		await physics_frame

	_art = world.get_node_or_null("Art") as Node3D
	if _art == null:
		printerr("NO VERDICT: scene has no Art node")
		quit(1)
		return
	_index_boxes()

	var space := world.get_world_3d().direct_space_state
	var exclude: Array = []
	var player_node := world.get_node_or_null("Player")
	if player_node != null:
		exclude.append(player_node.get_rid())   # else the first ray measures the Player

	# --- 1. the route, as the level defines it -------------------------------
	var centre := _centreline()
	if centre.size() < 10:
		printerr("NO VERDICT: centreline has only %d samples" % centre.size())
		quit(1)
		return

	# --- 2. walk it ---------------------------------------------------------
	var walk := _walk(space, centre, exclude)

	# --- 3. do the anchors agree with the route? ----------------------------
	# Measured against the WALK PROFILE, not the centreline's mesh y. The
	# centreline carries a per-bin median of the route mesh's vertices, and on
	# the bridge that mesh includes the arch soffit, so its median bounces
	# between 3.2 and 7.9 on a deck that is flat at 6.37. The profile is what the
	# ground ray actually returned, i.e. the surface a body would stand on.
	var anchor_check := _check_anchors(world, walk["profile"], _surface_refs())
	var world_report: Dictionary = world.call("report")

	var report := {
		"route_sources": ROUTE_SOURCES,
		"centreline": centre,
		"walk": walk,
		"anchors": anchor_check,
		"world_report": world_report,
	}
	var fh := FileAccess.open(OUT, FileAccess.WRITE)
	fh.store_string(JSON.stringify(report, " "))
	fh.close()

	print("WALK centreline_samples=%d  z %.1f -> %.1f"
		% [centre.size(), centre[0].z, centre[centre.size() - 1].z])
	print("WALK stride=%.1f  holes=%d  steps>%.2f=%d  blocked=%d"
		% [STRIDE, walk["holes"].size(), STEP_LIMIT, walk["steps"].size(),
			walk["blocked"].size()])
	print("WALK climbed %.2f m over %.1f m of route"
		% [walk["rise"], walk["distance"]])
	for label in ["holes", "steps", "blocked"]:
		for item in walk[label].slice(0, 8):
			print("  %-8s %s" % [label.to_upper(), JSON.stringify(item)])
	if walk["holes"].size() + walk["steps"].size() + walk["blocked"].size() == 0:
		print("WALK VERDICT: route continuous end to end")
	print("ANCHOR checked=%d suspicious=%d unverified=%d"
		% [anchor_check["count"], anchor_check["suspicious"].size(),
			anchor_check["unverified"].size()])
	for a in anchor_check["suspicious"].slice(0, 12):
		print("  SUSPECT %s" % JSON.stringify(a))
	for a in anchor_check["unverified"].slice(0, 12):
		print("  UNVERIFIED %s" % JSON.stringify(a))
	# The world's own opinion of its anchors, independent of the route check:
	# anything sitting more than ROOF_SUSPECT above its source actor's base.
	var rep: Dictionary = world_report
	if rep.has("spawn_audit"):
		print("SPAWN %s" % JSON.stringify(rep["spawn_audit"]))
	var roofs: Array = rep.get("suspect_roof", [])
	print("ANCHOR above_own_base_suspect=%d" % roofs.size())
	for a in roofs.slice(0, 12):
		print("  ON_ROOF %s" % JSON.stringify(a))
	quit(0)


# ---------------------------------------------------------------------------
# centreline
# ---------------------------------------------------------------------------

## Bucket the authored route's vertices along z, and in each bucket keep the
## lane nearest to the lane we were already in. Continuity is what stops a bend
## from being read as a jump: at a corner two z-adjacent buckets can belong to
## two different arms of the same ribbon.
##
## x = MIDPOINT of the lane's x extent, not the median. The median is biased by
## where the modeller put vertices: on the bridge deck the vertex rows cluster on
## the parapets, so the median drifted to x = 3.2 on a deck that spans
## x[-4.79,4.79], and the walk then read the parapet top (7.674) instead of the
## deck (6.374) and called the difference a 1.3 m step. The midpoint is immune to
## sampling density. It also agrees with the level's own numbers: the south
## corridor x[-9.60,8.60] has midpoint -0.50, which is exactly POI_SouthEntry.
##
## Outliers are trimmed before measuring, so one stray weld cannot widen a lane.
func _centreline() -> Array:
	var bins := {}
	for name in ROUTE_SOURCES:
		var node := _art.find_child(name, true, false) as MeshInstance3D
		if node == null:
			print("WALK route source missing: ", name)
			continue
		var mesh: Mesh = node.mesh
		if mesh == null:
			continue
		var xf: Transform3D = node.global_transform
		for s in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var w: Vector3 = xf * v
				var key := int(floor(w.z / BIN))
				# Plain Array, not PackedVector3Array: packed arrays are value
				# types, so mutating one through a dictionary subscript is a
				# copy-semantics trap that silently loses every vertex.
				if not bins.has(key):
					bins[key] = []
				bins[key].append(w)

	var keys := bins.keys()
	keys.sort()
	if keys.is_empty():
		return []
	var first_key: int = keys[0]
	var last_key: int = keys[keys.size() - 1]
	var span := int(round(WINDOW / BIN))

	# Pass 1: measure where the mesh actually has a cross-section.
	#
	# "Actually has" is the operative word. MainStoneBridge_DECK at z=-95 holds
	# six vertices at two distinct x (-3.81, +2.61): the deck is a sparse quad
	# strip roughly 6.4 m wide centred on -0.60, and the +/-4.79 in its AABB is
	# the arch, not the walkway. A statistical centre over 2 points is an edge of
	# a different part of the mesh, which is how the crossing ended up at
	# x=-3.35 and threw five phantom 1.3 m steps off the parapet.
	var xs := []
	var ys := []
	var ok := []
	var carry := INF
	var widest := 0.0
	var key := first_key
	while key <= last_key:
		var pts: Array = []
		for k in range(key - span, key + span + 1):
			if bins.has(k):
				pts.append_array(bins[k])
		var good := false
		var mx := 0.0
		var my := 0.0
		var w := 0.0
		if not pts.is_empty():
			var lanes := _split_lanes(pts)
			var wide: Array = []
			for lane in lanes:
				if _width(lane) >= MIN_LANE_W:
					wide.append(lane)
			var pick: Array = pts
			if not wide.is_empty():
				if carry == INF:
					pick = _widest(wide)
				else:
					var best := INF
					pick = wide[0]
					for lane in wide:
						var c := _midpoint_x(lane)
						if absf(c - carry) < best:
							best = absf(c - carry)
							pick = lane
			var lo := _quantile_x(pick, 0.05)
			var hi := _quantile_x(pick, 0.95)
			w = hi - lo
			mx = (lo + hi) * 0.5
			my = _median_y(pick)
			# A cross-section needs a real spread AND several sample points.
			# Two points 6 m apart is a strip's edge pair, not a road surface.
			good = w >= MIN_LANE_W and _distinct_x(pick) >= 4
		xs.append(mx)
		ys.append(my)
		ok.append(good)
		if good:
			carry = mx
			widest = maxf(widest, w)
		key += 1

	# Pass 2: where the mesh cannot be measured, follow the straight line between
	# the last and next places it can. Across the bridge that line runs from the
	# south road's end to the town road's start, which is exactly where the road
	# goes -- and the walk then verifies it by landing on the deck.
	var n := ok.size()
	var first_ok := -1
	var last_ok := -1
	for i in n:
		if ok[i]:
			if first_ok < 0:
				first_ok = i
			last_ok = i
	if first_ok < 0:
		print("WALK centreline: nothing measurable, falling back to unsmoothed")
		var raw: Array = []
		for i in n:
			raw.append(Vector3(xs[i], ys[i], float(first_key + i) * BIN))
		return raw
	var i := 0
	while i < n:
		if ok[i]:
			i += 1
			continue
		# Find the bracket.
		var a := i - 1
		var b := i
		while b < n and not ok[b]:
			b += 1
		if a < 0:
			a = b if b < n else first_ok
		var norm: float = float(i - a) / float(maxi(b - a, 1))
		var x0: float = xs[a] if a >= 0 else xs[first_ok]
		var y0: float = ys[a] if a >= 0 else ys[first_ok]
		var j: int = b if b < n else last_ok
		xs[i] = lerpf(x0, xs[j], norm)
		ys[i] = lerpf(y0, ys[j], norm)
		i += 1

	print("WALK centreline: measurable=%d/%d  widest_lane=%.2f m"
		% [ok.count(true), n, widest])
	var out: Array = []
	for i2 in n:
		out.append(Vector3(xs[i2], ys[i2], float(first_key + i2) * BIN))
	return out


func _distinct_x(pts: Array) -> int:
	var xs := PackedFloat32Array()
	for v in pts:
		xs.append(v.x)
	xs.sort()
	var n := 0
	var last := INF
	for x in xs:
		if absf(x - last) > 0.02:
			n += 1
			last = x
	return n


func _width(pts: Array) -> float:
	var lo := INF
	var hi := -INF
	for v in pts:
		lo = minf(lo, v.x)
		hi = maxf(hi, v.x)
	return hi - lo


func _widest(lanes: Array) -> Array:
	var best: Array = lanes[0]
	var best_w := -1.0
	for lane in lanes:
		var w := _width(lane)
		if w > best_w:
			best_w = w
			best = lane
	return best


## Split one z bucket's vertices into x-separated lanes.
func _split_lanes(pts: Array) -> Array:
	var sorted := pts.duplicate()
	sorted.sort_custom(func(a, b): return a.x < b.x)
	var lanes: Array = []
	var lane: Array = []
	for v in sorted:
		if lane.is_empty():
			lane.append(v)
			continue
		if v.x - lane[lane.size() - 1].x > CLUSTER_GAP:
			lanes.append(lane)
			lane = []
		lane.append(v)
	if not lane.is_empty():
		lanes.append(lane)
	return lanes


func _midpoint_x(pts: Array) -> float:
	# Untrimmed midpoint, used only for lane continuity matching.
	var lo := INF
	var hi := -INF
	for v in pts:
		lo = minf(lo, v.x)
		hi = maxf(hi, v.x)
	return (lo + hi) * 0.5


func _quantile_x(pts: Array, q: float) -> float:
	var xs := PackedFloat32Array()
	for v in pts:
		xs.append(v.x)
	xs.sort()
	var idx := int(round(q * float(xs.size() - 1)))
	return xs[clampi(idx, 0, xs.size() - 1)]


func _median_y(pts: Array) -> float:
	var ys := PackedFloat32Array()
	for v in pts:
		ys.append(v.y)
	ys.sort()
	return ys[ys.size() / 2]


# ---------------------------------------------------------------------------
# the walk
# ---------------------------------------------------------------------------

func _walk(space: PhysicsDirectSpaceState3D, centre: Array, exclude: Array) -> Dictionary:
	# The route's south end is open meadow, so a full-height cast is safe for the
	# ONE bootstrap sample; every sample after it is relative to the previous one.
	var start: Vector3 = centre[0]
	var seed_hit := _down(space, Vector3(start.x, start.y + 60.0, start.z),
		start.y - 40.0, exclude)
	var y: float = seed_hit["position"].y if not seed_hit.is_empty() else start.y

	var holes: Array = []
	var steps: Array = []
	var blocked: Array = []
	var profile: Array = []
	var distance := 0.0
	var lowest := y
	var highest := y
	var prev := Vector3(start.x, y, start.z)
	profile.append({"i": 0, "p": [start.x, y, start.z]})

	var i := 1
	while i < centre.size():
		var target: Vector3 = centre[i]
		var here := Vector3(target.x, prev.y, target.z)
		var flat := Vector2(target.x - prev.x, target.z - prev.z).length()
		distance += flat
		if flat < 1e-4:
			i += 1
			continue

		# Ground: from the walker's own head downward. Anything at or above head
		# height is by definition not underfoot, so a gate lintel spanning the
		# road cannot be mistaken for the road.
		var hit := _down(space, Vector3(target.x, prev.y + EYE, target.z),
			prev.y + EYE - REACH_DOWN, exclude)
		if hit.is_empty():
			holes.append({"i": i, "z": snappedf(target.z, 0.01),
				"x": snappedf(target.x, 0.01), "prev_y": snappedf(prev.y, 0.001)})
			# Do not advance prev: a hole is a hole, not a new floor level.
			i += 1
			continue

		var gy: float = hit["position"].y
		# Forward: chest height, only as far as the next stride. A wall across the
		# route is invisible to a downward ray and obvious to this one.
		var fwd := _forward(space, Vector3(prev.x, prev.y + 1.0, prev.z),
			Vector3(target.x, prev.y + 1.0, target.z), flat + 0.6, exclude)
		if not fwd.is_empty():
			blocked.append({"i": i, "z": snappedf(target.z, 0.01),
				"x": snappedf(target.x, 0.01),
				"blocker": _name_at(fwd["position"]),
				"at": _rv(fwd["position"])})

		var rise := gy - prev.y
		if absf(rise) > STEP_LIMIT:
			steps.append({"i": i, "z": snappedf(target.z, 0.01),
				"x": snappedf(target.x, 0.01), "delta": snappedf(rise, 0.001),
				"from_y": snappedf(prev.y, 0.001), "to_y": snappedf(gy, 0.001),
				"on": _name_at(Vector3(target.x, gy, target.z))})

		y = gy
		lowest = minf(lowest, y)
		highest = maxf(highest, y)
		prev = Vector3(target.x, y, target.z)
		profile.append({"i": i, "p": [prev.x, prev.y, prev.z]})
		i += 1

	return {
		"holes": holes,
		"steps": steps,
		"blocked": blocked,
		"distance": snappedf(distance, 0.01),
		"rise": snappedf(highest - lowest, 0.01),
		"lowest_y": snappedf(lowest, 0.01),
		"highest_y": snappedf(highest, 0.01),
		"end": _rv(prev),
		"profile": profile,
	}


func _down(space: PhysicsDirectSpaceState3D, from: Vector3, to_y: float,
		exclude: Array) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, to_y, from.z))
	q.collide_with_areas = false
	q.exclude = exclude
	return space.intersect_ray(q)


func _forward(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		length: float, exclude: Array) -> Dictionary:
	var dir := (to - from)
	dir.y = 0.0
	if dir.length() < 1e-4:
		return {}
	dir = dir.normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * length)
	q.collide_with_areas = false
	q.exclude = exclude
	return space.intersect_ray(q)


# ---------------------------------------------------------------------------
# naming whatever we hit
# ---------------------------------------------------------------------------

## The baked collision is one ConcavePolygonShape3D under one StaticBody3D, so
## every ray hit reports the same collider name and tells us nothing. Naming is
## recovered from the art, whose 226 pieces are still individual nodes.
func _index_boxes() -> void:
	for node in _art.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		_boxes.append({"name": mi.name, "aabb": mi.global_transform * mi.get_aabb()})


func _name_at(p: Vector3) -> String:
	# Probe a hair BELOW the reported surface. A road ribbon is a thin sheet, so
	# a point exactly on it sits on the AABB boundary and may fall outside; and a
	# point on a parapet top (8.163 against a deck AABB ending at 8.170) resolved
	# to "the terrain proxy" purely because 8.213 had been pushed past the deck's
	# own bound by a +0.05 fudge. Node bounds checked from the wrong side name the
	# wrong actor, which is worse than naming none.
	var q := Vector3(p.x, p.y - NAME_PROBE_DROP, p.z)
	var best := ""
	var best_v := INF
	for b in _boxes:
		var aabb: AABB = b["aabb"]
		if aabb.has_point(q):
			# Several boxes can contain a point (the terrain proxy contains the
			# whole map); the smallest is the most specific description of what
			# is underfoot.
			var v: float = aabb.size.x * aabb.size.y * aabb.size.z
			if v < best_v:
				best_v = v
				best = b["name"]
	return best if best != "" else "(no art actor contains this point)"


# ---------------------------------------------------------------------------
# anchors vs the route
# ---------------------------------------------------------------------------

## The assertion the first version of the world script was missing. It grounded
## every anchor with a ray from +120 m above the actor, so:
##   POI_Guild      landed on the guild ROOF at y=30.32 (forecourt is 16.2-18.0)
##   POI_Church     landed on the nave roof at y=29.61, and at x=114.82, which
##                  is outside the church forecourt x[99,109] altogether
##   POI_NorthGate  landed on the gate lintel at y=35.14, while a POI taken from
##                  the SAME actor beyond its bounds correctly read 24.71
## Every one of those passed silently. An anchor is only usable if it is on the
## walkable surface, so now each one is measured against it.
##
## The reference is the walk profile PLUS every vertex of every authored walking
## surface, not the profile alone: five anchors (the guild training yard, the
## church forecourt, the blacksmith) are legitimately 40 m or more off the golden
## route and a route-only check would have to write them all off as "unverified".
func _check_anchors(world: Node3D, profile: Array, refs: Array) -> Dictionary:
	var root := world.get_node_or_null("Anchors")
	var suspicious: Array = []
	var unverified: Array = []
	var count := 0
	if root == null:
		return {"count": 0, "suspicious": [], "unverified": []}
	var all: Array = []
	all.append_array(profile)
	all.append_array(refs)
	for child in root.get_children():
		if not (child is Node3D):
			continue
		count += 1
		var p: Vector3 = (child as Node3D).position
		var near := _nearest(all, p)
		if near.is_empty():
			unverified.append({"name": str(child.name), "reason": "no walkable surface within 60 m",
				"y": snappedf(p.y, 0.01)})
			continue
		var dy: float = p.y - near["y"]
		if absf(dy) > ANCHOR_TOLERANCE:
			suspicious.append({
				"name": str(child.name), "y": snappedf(p.y, 0.01),
				"route_y": snappedf(near["y"], 0.01), "dy": snappedf(dy, 0.01),
				"dist_xz": snappedf(near["dist"], 0.01),
			})
	return {"count": count, "suspicious": suspicious, "unverified": unverified}


## Every vertex of every actor the level names as a walking surface.
func _surface_refs() -> Array:
	var out: Array = []
	for b in _boxes:
		var name: String = b["name"]
		var is_surface := false
		for token in ["ART_Surface_", "SM_Handoff_", "ServiceBridge_", "StoneBridge_DECK"]:
			if token in name:
				is_surface = true
				break
		if not is_surface:
			continue
		var node := _art.find_child(name, true, false) as MeshInstance3D
		if node == null or node.mesh == null:
			continue
		var xf: Transform3D = node.global_transform
		for s in node.mesh.get_surface_count():
			var verts: PackedVector3Array = node.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var w: Vector3 = xf * v
				out.append({"p": [w.x, w.y, w.z]})
	return out


func _nearest(refs: Array, p: Vector3) -> Dictionary:
	var best := INF
	var y := 0.0
	for s in refs:
		var q: Array = s["p"]
		var dz: float = q[2] - p.z
		var dx: float = q[0] - p.x
		var d: float = sqrt(dx * dx + dz * dz)
		if d < best:
			best = d
			y = q[1]
	if best > 60.0:
		return {}
	return {"y": y, "dist": best}


func _rv(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
