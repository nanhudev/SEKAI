extends SceneTree
## LEVEL ART PASS 02 — field measurements.
##
## Answers questions the terrain pass must not guess at:
##   1. Does the main road actually cross the river, or does it dive into it?
##   2. How wide and how steep is the riverbank on each side?
##   3. What does the road's own longitudinal profile look like (walkable?)
##   4. Where is the town shelf flat enough to build on?
##
## Every number comes from MistvaleHeights itself. A Python re-implementation
## would drift the moment the field is edited, and then the audit would be
## measuring a terrain that no longer exists.
##
## Run:
##   Godot --headless --path F:/SEKAI/godot --script res://tools/audit_land_field.gd
##
## Output: F:/SEKAI/assets_source/review/land_field_audit.txt  (plus stdout)

const OUT := "F:/SEKAI/assets_source/review/land_field_audit.txt"

## Route to profile. Duplicated from the masterplan by design — if the
## masterplan's spine moves, this table moves with it and the mismatch is
## visible in the report rather than hidden.
const SPINE := [
	Vector2(200.0, 320.0),
	Vector2(155.0, 258.0),
	Vector2(120.0, 205.0),
	Vector2(85.0, 180.0),
	Vector2(10.0, 122.0),
	Vector2(0.0, 0.0),
	Vector2(0.0, -45.0),
	Vector2(0.0, -135.0),
]

var _lines := PackedStringArray()


func _initialize() -> void:
	_say("MISTVALE FIELD AUDIT — %s" % Time.get_datetime_string_from_system())
	_say("")

	_river_crossing()
	_river_banks()
	_road_profile()
	_town_shelf()
	_summary()

	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("cannot open %s" % OUT)
		quit(1)
		return
	f.store_string("\n".join(_lines))
	f.close()
	print("WROTE %s" % OUT)
	quit(0)


func _say(t: String) -> void:
	_lines.append(t)
	print(t)


# -----------------------------------------------------------------------------
# 1. River crossing
# -----------------------------------------------------------------------------
## Walk the spine and find every sample where the ground is at or below the
## water surface. Anything below RIVER_Y is a stretch of road the player would
## wade through.
func _river_crossing() -> void:
	_say("=== 1. RIVER CROSSING (spine vs water) ===")
	var water: float = MistvaleHeights.RIVER_Y
	_say("water surface Y = %.2f m" % water)
	var total := MistvaleHeights.route_length(SPINE)
	_say("spine length (XZ) = %.1f m" % total)
	_say("")
	_say("  dist      x        z     ground    vs water   state")

	var wet := PackedFloat32Array()
	var d := 0.0
	while d <= total:
		var p := MistvaleHeights.route_at(SPINE, d)
		var g := MistvaleHeights.height_at(p.x, p.y)
		var delta := g - water
		var state := "OK"
		if delta < 0.0:
			wet.append(d)
			state = "*** UNDERWATER ***"
		elif delta < 0.35:
			state = "at waterline"
		if d < 20.0 or d > 130.0:
			_say("  %5.1f  %7.1f  %7.1f   %6.2f     %+6.2f    %s"
				% [d, p.x, p.y, g, delta, state])
		d += 2.0

	_say("")
	if wet.is_empty():
		_say("RESULT: the spine never dips to the water surface. No ford needed.")
	else:
		_say("RESULT: %d samples below waterline, from %.0f m to %.0f m along the spine."
			% [wet.size(), wet[0], wet[-1]])
		_say("        -> the main road is submerged for ~%.0f m of its length."
			% (wet[-1] - wet[0] + 2.0))
		_say("        -> this is a BRIDGE / FORD requirement, not a cosmetic issue.")
	_say("")


# -----------------------------------------------------------------------------
# 2. Riverbank
# -----------------------------------------------------------------------------
## Cut a section across the river at three longitudes and report the width of
## the walkable bank on each side. A bank that is walkable in 3 m is a wall.
func _river_banks() -> void:
	_say("=== 2. RIVERBANK SECTIONS ===")
	_say("walkable := slope <= 25 deg. Terrain beyond the bank is what the")
	_say("player can actually stand on, so the bank width is a playability number.")
	_say("")
	_say("   x     centre z   bank N (m)  bank S (m)   max slope")
	for x in [-200.0, -100.0, 0.0, 100.0, 200.0]:
		# Centre of the river channel at this longitude.
		var cz := 0.0
		var best := 1e9
		# Cheap scan: the bed is flat, so find the flattest z.
		var s := 60.0
		while s <= 190.0:
			var a := MistvaleHeights.height_at(x, s - 2.0)
			var b := MistvaleHeights.height_at(x, s)
			var c := MistvaleHeights.height_at(x, s + 2.0)
			var curv: float = absf(a - 2.0 * b + c)
			var near: float = absf(b - MistvaleHeights.RIVER_Y)
			var score := curv + near * 0.5
			if score < best and absf(b - MistvaleHeights.RIVER_Y) < 0.6:
				best = score
				cz = s
			s += 1.0

		var north_w := _bank_width(x, cz, -1.0)
		var south_w := _bank_width(x, cz, 1.0)
		var slope := _max_slope_along(x, cz - 60.0, cz + 60.0)
		_say("  %5.0f    %6.1f      %6.1f       %6.1f      %5.1f deg"
			% [x, cz, south_w, north_w, slope])
	_say("")


func _bank_width(x: float, centre_z: float, dir: float) -> float:
	## Walk outward from the waterline until the ground is both high enough to
	## be dry and flat enough to stand on.
	## dir = +1 walks south (+Z), -1 walks north (-Z).
	var w := 0.0
	var z := centre_z
	for _i in 200:
		z += dir * 0.5
		w += 0.5
		var g := MistvaleHeights.height_at(x, z)
		if g - MistvaleHeights.RIVER_Y < 1.2:
			continue
		var a := MistvaleHeights.height_at(x, z - 2.0)
		var b := MistvaleHeights.height_at(x, z + 2.0)
		var slope := rad_to_deg(atan2(absf(a - b), 4.0))
		if slope <= 25.0:
			return w
	return -1.0


func _max_slope_along(x: float, z0: float, z1: float) -> float:
	var worst := 0.0
	var z := z0
	while z <= z1:
		var a := MistvaleHeights.height_at(x, z - 2.0)
		var b := MistvaleHeights.height_at(x, z + 2.0)
		var s := rad_to_deg(atan2(absf(a - b), 4.0))
		worst = maxf(worst, s)
		z += 2.0
	return worst


# -----------------------------------------------------------------------------
# 3. Road profile
# -----------------------------------------------------------------------------
func _road_profile() -> void:
	_say("=== 3. ROAD LONGITUDINAL PROFILE (spine) ===")
	_say("A road the player must run along cannot exceed ~25 deg sustained.")
	_say("")
	_say("  dist    ground   rise/2m   slope    band")
	var total := MistvaleHeights.route_length(SPINE)
	var d := 0.0
	var prev := MistvaleHeights.height_at(SPINE[0].x, SPINE[0].y)
	var worst := 0.0
	var steep_len := 0.0
	while d <= total:
		var p := MistvaleHeights.route_at(SPINE, d + 2.0)
		var g := MistvaleHeights.height_at(p.x, p.y)
		var rise := g - prev
		var slope := rad_to_deg(atan2(absf(rise), 2.0))
		worst = maxf(worst, slope)
		if slope > 25.0:
			steep_len += 2.0
		if int(d) % 20 == 0:
			_say("  %5.0f   %6.2f    %+6.2f   %5.1f    %s"
				% [d, g, rise, slope, _band(g)])
		prev = g
		d += 2.0
	_say("")
	_say("worst slope on spine = %.1f deg ; length above 25 deg = %.0f m"
		% [worst, steep_len])
	_say("")


func _band(y: float) -> String:
	if y < 12.0:
		return "river"
	if y < 30.0:
		return "valley / lower town"
	if y < 52.0:
		return "market"
	if y < 78.0:
		return "upper town"
	if y < 140.0:
		return "mountain"
	return "ruins"


# -----------------------------------------------------------------------------
# 4. Town shelf
# -----------------------------------------------------------------------------
## The buildable question: over the town footprint, where is the ground flat
## enough that a building can sit without a 3 m plinth?
func _town_shelf() -> void:
	_say("=== 4. TOWN SHELF FLATNESS (2 m sample) ===")
	_say("Reported as the slope a 6x6 m building pad would sit on.")
	_say("")
	_say("   zone            x      z    ground   pad slope   verdict")
	var pods := [
		["Z-05 Market", 0.0, 0.0],
		["Z-06 Guild", 0.0, -45.0],
		["Z-04 Lower Town", 0.0, 70.0],
		["Z-04a Forge", -85.0, 60.0],
		["Z-04b Residential", 75.0, 55.0],
		["Z-07 Upper Town", -10.0, -90.0],
		["Z-07a Bell Tower", -40.0, -95.0],
		["Z-07b Temple", 55.0, -100.0],
		["Z-08 North Gate", 0.0, -135.0],
	]
	for p in pods:
		var x: float = p[1]
		var z: float = p[2]
		var g := MistvaleHeights.height_at(x, z)
		# Worst slope across the pad footprint.
		var worst := 0.0
		for dz in [-3.0, 0.0, 3.0]:
			for dx in [-3.0, 0.0, 3.0]:
				var a := MistvaleHeights.height_at(x + dx - 1.0, z + dz)
				var b := MistvaleHeights.height_at(x + dx + 1.0, z + dz)
				var c := MistvaleHeights.height_at(x + dx, z + dz - 1.0)
				var e := MistvaleHeights.height_at(x + dx, z + dz + 1.0)
				worst = maxf(worst, rad_to_deg(atan2(absf(a - b), 2.0)))
				worst = maxf(worst, rad_to_deg(atan2(absf(c - e), 2.0)))
		var verdict := "buildable"
		if worst > 12.0:
			verdict = "needs terrace / plinth"
		if worst > 25.0:
			verdict = "NOT buildable as-is"
		_say("  %-15s %6.0f %6.0f   %6.2f     %5.1f     %s"
			% [p[0], x, z, g, worst, verdict])
	_say("")


func _summary() -> void:
	_say("=== SUMMARY ===")
	_say("Region bounds: X %.0f..%.0f  Z %.0f..%.0f  (%.0f x %.0f m)"
		% [MistvaleHeights.MIN_X, MistvaleHeights.MAX_X,
		   MistvaleHeights.MIN_Z, MistvaleHeights.MAX_Z,
		   MistvaleHeights.MAX_X - MistvaleHeights.MIN_X,
		   MistvaleHeights.MAX_Z - MistvaleHeights.MIN_Z])
	_say("Water Y = %.1f  River flat bed half-width = %.1f m"
		% [MistvaleHeights.RIVER_Y, MistvaleHeights.RIVER_FLAT])
	_say("")
