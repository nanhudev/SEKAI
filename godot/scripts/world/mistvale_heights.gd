class_name MistvaleHeights
extends RefCounted
## Analytic height field for the Mistvale Vertical Slice Region.
##
## WHY THIS FILE EXISTS SEPARATELY: the terrain mesh builder and the greybox
## placer must agree on exactly where the ground is. If each had its own copy
## of the profile, landmark blockouts would float or sink the moment one side
## was tweaked. One field, two consumers.
##
## Authoritative design source: docs/LD-01-MISTVALE-REGION-MASTERPLAN.md
##   origin  = Market Square ground, Y = 34.0
##   +X east | -Z north | +Y up
##
## This is a GREYBOX field. It must be replaced by authored terrain before
## GATE 5 (Atmosphere). It is not art; it is the proof that the macro layout
## stands up.


# --- Region bounds -----------------------------------------------------------
const MIN_X := -330.0
const MAX_X := 330.0
const MIN_Z := -430.0
const MAX_Z := 330.0

# --- Master profile: (latitude Z, ground Y) from south (low) to north (high) --
# 21 control points. Sorted descending by Z. South edge is the East Forest
# shelf; north edge is the ridge that carries the permanent scar.
## Denser through the river approach on purpose. With only two control points
## the smoothstep blend peaked at ~28 deg on the banks, and the carve on top of
## that pushed the whole river into a >35 deg canyon — which would have killed
## the Riverbank Road crossing outright.
const PROFILE := [
	Vector2(330.0, 34.0),   # East Forest / Prologue shelf
	Vector2(300.0, 33.0),
	Vector2(250.0, 31.0),
	Vector2(230.0, 28.0),
	Vector2(205.0, 25.0),
	Vector2(185.0, 22.0),
	Vector2(170.0, 19.0),
	Vector2(160.0, 16.0),   # south bank
	Vector2(150.0, 13.5),
	Vector2(140.0, 10.5),
	Vector2(131.0, 8.0),
	Vector2(122.0, 6.0),    # river surface — lowest playable ground
	Vector2(113.0, 8.0),
	Vector2(104.0, 10.5),
	Vector2(95.0, 13.5),    # north bank
	Vector2(85.0, 16.2),
	Vector2(78.0, 18.0),    # Lower Town south edge
	Vector2(60.0, 21.5),
	Vector2(45.0, 24.5),
	Vector2(25.0, 28.5),
	Vector2(8.0, 31.5),
	Vector2(-12.0, 34.0),   # Market Square — the origin
	Vector2(-25.0, 38.0),
	Vector2(-38.0, 42.0),   # climb toward the terrace
	Vector2(-50.0, 46.0),
	Vector2(-62.0, 50.0),   # Guild Terrace
	Vector2(-75.0, 55.0),
	Vector2(-92.0, 62.0),   # Upper Town
	Vector2(-107.0, 67.0),
	Vector2(-122.0, 72.0),
	Vector2(-132.0, 76.0),
	Vector2(-142.0, 80.0),  # North Gate threshold
	Vector2(-165.0, 88.0),
	Vector2(-190.0, 96.0),
	Vector2(-210.0, 106.0), # mountain begins in earnest
	Vector2(-240.0, 117.0),
	Vector2(-270.0, 128.0),
	Vector2(-300.0, 138.0),
	Vector2(-330.0, 148.0),
	Vector2(-355.0, 152.0),
	Vector2(-380.0, 155.0), # Ruins Approach
	Vector2(-405.0, 160.0),
	Vector2(-430.0, 166.0), # Ridge / Scar
]

# --- River -------------------------------------------------------------------
const RIVER_Y := 6.0
const RIVER_FLAT := 13.0          # half-width of the carved channel
const RIVER_HALF_WIDTH := 36.0

## How far the channel drops below RIVER_Y at its centre.
##
## The bed was perfectly flat, which is a table: the water surface mesh then has
## no depth to read, the shader has nothing to shade, and the river reads as a
## blue sheet lying on a ditch. Even one metre of mid-channel deepening gives a
## visible channel, a shallow/deep gradient at the banks, and shallows the eye
## can find. 1.1 m keeps it a broad shallow valley river; the original comment's
## warning was about a V-canyon from a 13 m carve, not about a channel.
const RIVER_DEEP := 1.1

## Roads that cross the river as fords — waded, not bridged (masterplan §7).
## Indices into ROADS.
const FORDED_ROADS := [3, 5]

## How deep a forded crossing is allowed to be.
const FORD_DEPTH := 0.42

## Radius of the gravel bar each ford sits on.
const FORD_RADIUS := 40.0

# --- Mountain massif ---------------------------------------------------------
const MOUNTAIN_START_Z := -130.0
const MOUNTAIN_SPAN := 280.0
## How much of the base profile the OUTER ground keeps as the massif rises.
## The base profile is the ridge line; this is the valley it stands in.
const VALLEY_FACTOR := 0.30

# --- Carved mountain routes (see masterplan §7) ------------------------------
# XZ only. The elevation is NOT authored — it is sampled from the field itself
# (see _route_profiles).
#
# WHY: an earlier version hard-coded the route heights from the ideal base
# profile. But _raise_mountain drops the flanks toward the outer valley, so the
# real ground at the Cliff Route waypoint (85, -265) is 102.5 m while the
# hard-coded route said 124 m. A 21.5 m disagreement between a corridor and the
# terrain it cuts through shows up as a 68 deg wall on the corridor edge — the
# route was, measurably, not walkable. Deriving the target removes the
# disagreement by construction instead of by hand-tuning two number lists.
const FOREST_TRAIL := [
	Vector2(0.0, -135.0),
	Vector2(-70.0, -215.0),
	Vector2(-55.0, -290.0),
	Vector2(-30.0, -345.0),
	Vector2(-10.0, -355.0),
]
const CLIFF_ROUTE := [
	Vector2(0.0, -135.0),
	Vector2(60.0, -200.0),
	Vector2(85.0, -265.0),
	Vector2(50.0, -330.0),
	Vector2(-10.0, -355.0),
]
const ROUTE_HALF_WIDTH := 11.0
## Not 1.0: a graded path still agrees a little with the ground it crosses.
const ROUTE_CARVE := 0.92


# =============================================================================
# Settlement & valley road network — LEVEL ART PASS 02
# =============================================================================
#
# WHY THIS IS HERE AND NOT IN THE TERRAIN BUILDER: three separate consumers now
# need to agree on where the road is — the terrain surface shader (paints the
# packed dirt), the relief layer (must NOT bump a road surface), and the
# vegetation scatter (roads are trodden bare at the edge and tidy at the verge).
# Three private copies of the polyline would drift, and the visible symptom
# would be grass growing through the middle of the main street.
#
# ROAD_SPINE IS THE BEAT-LEVEL MAIN STREET, not the greybox's 8-point
# simplification. The two were genuinely different lines: the greybox cut
# straight from the bridge (10,122) to the market, while the route the whole
# region is measured against goes bridge -> river stair -> lower town west ->
# forge lane -> market. Masking the relief with the simplified line left the
# real street unmasked and the audit immediately found a 50.5 deg step on a
# climb the masterplan audits at 0.0% over 45 deg. The walked line wins.
#
# MUST MATCH: `tools/audit_routes.gd` SPINE (XZ) and masterplan §7. If this list
# and that one disagree, the audit is measuring a different road than the one
# that gets built — which is exactly the bug this comment exists to prevent.

const ROAD_SPINE := [
	Vector2(200.0, 320.0),
	Vector2(155.0, 258.0),
	Vector2(140.0, 235.0),
	Vector2(120.0, 205.0),
	Vector2(85.0, 180.0),
	Vector2(45.0, 148.0),
	Vector2(10.0, 122.0),
	Vector2(-30.0, 95.0),
	Vector2(-60.0, 75.0),
	Vector2(-45.0, 45.0),
	Vector2(0.0, 0.0),
	Vector2(0.0, -45.0),
	Vector2(-20.0, -85.0),
	Vector2(-40.0, -95.0),
	Vector2(0.0, -135.0),
]

## Market → forge quarter works road (masterplan §7: 工坊巷道).
const ROAD_FORGE := [
	Vector2(0.0, 0.0),
	Vector2(-46.0, 22.0),
	Vector2(-85.0, 60.0),
]

## Market → residential lane (masterplan §7: 住宅阶梯).
const ROAD_LANE := [
	Vector2(0.0, 0.0),
	Vector2(44.0, 26.0),
	Vector2(75.0, 55.0),
]

## Lower town → ferry landing (masterplan §7: 渡口).
const ROAD_FERRY := [
	Vector2(0.0, 70.0),
	Vector2(-42.0, 82.0),
	Vector2(-78.0, 108.0),
	Vector2(-95.0, 136.0),
]

## Riverbank road, so the south bank is walkable rather than a slope nobody uses.
const ROAD_BANK := [
	Vector2(200.0, 268.0),
	Vector2(140.0, 232.0),
	Vector2(96.0, 196.0),
	Vector2(30.0, 176.0),
]

## East ford track: the third river crossing (masterplan §7).
const ROAD_FORD := [
	Vector2(96.0, 196.0),
	Vector2(118.0, 166.0),
	Vector2(126.0, 138.0),
	Vector2(112.0, 112.0),
]

## [points, packed half-width, worn half-width].
##
## PER-ROAD WIDTH IS THE POINT. A town street and a mountain trail are not the
## same width, and painting them with one number is how a map ends up feeling
## like a racetrack. The mountain trails are single-file.
const ROADS := [
	[ROAD_SPINE, 3.6, 9.5],     # main street — wide, hard worn
	[ROAD_FORGE, 2.6, 6.5],
	[ROAD_LANE, 2.2, 6.0],
	[ROAD_FERRY, 2.8, 7.5],
	[ROAD_BANK, 2.4, 6.5],
	[ROAD_FORD, 1.8, 5.0],
	# Undefined at parse time — FOREST_TRAIL/CLIFF_ROUTE are declared above.
	[FOREST_TRAIL, 1.7, 5.0],   # west line — single file, soft underfoot
	[CLIFF_ROUTE, 1.6, 4.5],    # east line — single file, bare rock
]

## Relief is fully suppressed within this distance of any road centreline, and
## fully restored by RELIEF_CLEAR_NONE. Both are deliberately wider than any
## road's own verge: the audit samples the centreline, so the centreline has to
## be bit-for-bit the terrain the audit measured.
const RELIEF_CLEAR_FULL := 5.0
const RELIEF_CLEAR_NONE := 15.0


# =============================================================================
# Land surface queries — shared by shader input, relief and scatter
# =============================================================================

## XZ distance to the nearest road centreline, in metres.
static func path_distance(x: float, z: float) -> float:
	var best := 1e9
	for road in ROADS:
		best = minf(best, _polyline_distance(x, z, road[0]))
	return best


## 0..1 paint strength of the packed road surface. 1 on the packed tread, 0 at
## the worn verge. Takes the MAX over roads, so a junction reads as road.
static func path_factor(x: float, z: float) -> float:
	var best := 0.0
	for road in ROADS:
		var d := _polyline_distance(x, z, road[0])
		var inner: float = road[1]
		var outer: float = road[2]
		var w := 0.0
		if d <= inner:
			w = 1.0
		elif d < outer:
			w = 1.0 - smoothstep(0.0, 1.0, (d - inner) / (outer - inner))
		best = maxf(best, w)
	return best


## 0..1 "this point is part of a graded corridor". 1 means relief is suppressed
## entirely. Uses the flat-clearance band, NOT the road paint width.
static func _corridor_keep(x: float, z: float) -> float:
	var d := path_distance(x, z)
	if d <= RELIEF_CLEAR_FULL:
		return 1.0
	if d >= RELIEF_CLEAR_NONE:
		return 0.0
	return 1.0 - smoothstep(0.0, 1.0,
		(d - RELIEF_CLEAR_FULL) / (RELIEF_CLEAR_NONE - RELIEF_CLEAR_FULL))


## XZ distance to a polyline. Separate from _nearest_on_polyline, which also
## interpolates a route profile and therefore needs the profile array.
static func _polyline_distance(px: float, pz: float, pts: Array) -> float:
	var best := 1e9
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var vx := b.x - a.x
		var vz := b.y - a.y
		var len2 := vx * vx + vz * vz
		var t := 0.0
		if len2 > 1e-6:
			t = clampf(((px - a.x) * vx + (pz - a.y) * vz) / len2, 0.0, 1.0)
		var dx := px - (a.x + vx * t)
		var dz := pz - (a.y + vz * t)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best


## 0..1 "this point is inside the built-up area".
##
## The terrain shader cannot infer this from height alone: a height band would
## pave the whole 660 m width of the valley at that elevation, including the far
## ridge, which has no village on it. The village is a footprint, so it has to
## come from the roads that make it a village plus the band it sits in.
##
## Only the settlement roads count. A mountain trail is not a village, and
## letting FOREST_TRAIL into this list put paving on a wilderness switchback.
static func settlement_factor(x: float, z: float) -> float:
	var d := 1e9
	for road in [ROAD_SPINE, ROAD_FORGE, ROAD_LANE, ROAD_FERRY]:
		d = minf(d, _polyline_distance(x, z, road))
	var near := 1.0 - smoothstep(24.0, 88.0, d)
	# Lower town in the south, north gate in the north. Outside this the ground
	# is valley or mountain regardless of how close a road happens to pass.
	var band := smoothstep(104.0, 84.0, z) * smoothstep(-152.0, -132.0, z)
	return near * band


## A stable 0..1 variation seed per location.
##
## Baked into the terrain vertex stream so the surface shader can break up large
## areas of one albedo. It has to be a value the FIELD produces rather than
## something the shader invents, so that the same ground gets the same tint in
## the terrain mesh and anywhere else that samples it.
static func variation(x: float, z: float) -> float:
	return _vnoise(x * 0.0045 + 13.7, z * 0.0045 - 5.3)


## A per-metre grain, in 0..1. HIGH frequency — the opposite of variation().
##
## variation() has a noise period of 200 m, which is right for breaking up
## albedo over a field and completely wrong for surface texture. The road
## ribbon used it for its discolouration and therefore had none: the entire
## street was the same colour from one end to the other, and at a grazing angle
## that reads as poured concrete. Anything that needs to change metre to metre
## uses this.
static func grain(x: float, z: float) -> float:
	return _hash2(x, z)


## Ground gradient in degrees, sampled over `h` metres. Used by the vegetation
## scatter (slope decides what grows) and by the terrace audit.
static func slope_deg(x: float, z: float, h: float = 1.5) -> float:
	var dx := height_at(x + h, z) - height_at(x - h, z)
	var dz := height_at(x, z + h) - height_at(x, z - h)
	return rad_to_deg(atan2(sqrt(dx * dx + dz * dz), 2.0 * h))


## Public wrapper. The river's centre at this longitude; the water surface mesh
## and the riverbank dressing both follow this exact curve.
static func river_center_z(x: float) -> float:
	return _river_center_z(x)


# =============================================================================
# Public field
# =============================================================================

## ORDER IS LOAD-BEARING: base -> routes -> arenas -> relief.
##
## Arenas must be applied LAST of the three shaping layers. With routes carved
## afterwards the trail re-sloped finished pads: C07 Forest Clearing sits 4.6 m
## from the Forest Trail centreline, and the carve put 48 deg and a 10.8 m
## spread back into a space that had just been levelled. A combat pad is
## authored; a path passing through it should flatten into the pad, not cut
## through it.
##
## RELIEF comes after everything and is masked to zero inside every corridor
## and pad, so it can add small ground brokenness without moving a single metre
## of the audited walk.
static func height_at(x: float, z: float) -> float:
	return _relief(_flatten_arenas(_carve_routes(_height_base(x, z), x, z), x, z), x, z)


## River + massif + erosion, before any path or pad is cut into it.
static func _height_base(x: float, z: float) -> float:
	return _height_smooth(x, z) + _erosion(x, z)


## How much of the erosion term survives inside the river channel.
##
## APPLIED HERE AND NOT IN _erosion BECAUSE ORDER IS THE BUG. _height_smooth
## carves the channel and _height_base then ADDS erosion on top of it, so an
## unmasked erosion term lands directly on the river bed. In the East Forest
## band that term is +/-2.2 m — against a channel that is deliberately only
## 1.1 m deep. The measured result was that the two derived fords waded 0.76 m
## and 1.08 m, i.e. the shoals were being erased by noise and the "wadeable
## crossing" was chest deep.
##
## 0.12 keeps a little silt unevenness for the water shader to read without
## moving the bed more than a hand's breadth.
const CHANNEL_EROSION := 0.12


## Large-scale ground only: no erosion bumps, no path, no pad. A pad's tilt is
## taken from this, so it follows the mountainside rather than fighting it.
static func _height_smooth(x: float, z: float) -> float:
	var h := _base_profile(z)
	h = _carve_river(h, x, z)
	h = _raise_mountain(h, x, z)
	return h


# =============================================================================
# Layers — applied in the order above
# =============================================================================

static func _base_profile(z: float) -> float:
	# PROFILE is sorted by descending Z; walk it and smoothstep each segment so
	# the ground rolls instead of creasing at every control point.
	if z >= PROFILE[0].x:
		return PROFILE[0].y
	# PROFILE is an untyped const Array, so GDScript cannot infer the element
	# type — it has to be stated.
	for i in PROFILE.size() - 1:
		var a: Vector2 = PROFILE[i]
		var b: Vector2 = PROFILE[i + 1]
		if z <= a.x and z >= b.x:
			var t: float = (a.x - z) / maxf(a.x - b.x, 0.0001)
			return lerpf(a.y, b.y, smoothstep(0.0, 1.0, t))
	return PROFILE[-1].y


static func _river_center_z(x: float) -> float:
	# A river that is dead straight reads as a canal. Two low-frequency sines
	# give it a believable meander at region scale.
	return 122.0 + 14.0 * sin(x * 0.008) + 8.0 * sin(x * 0.021 + 1.3)


static func _carve_river(h: float, x: float, z: float) -> float:
	var d := absf(z - _river_center_z(x))
	if d >= RIVER_HALF_WIDTH:
		return h
	var bed := RIVER_Y
	if d <= RIVER_FLAT:
		# Parabolic channel, deepest mid-stream. u=1 gives back exactly RIVER_Y,
		# so the waterline stays precisely at RIVER_FLAT and every consumer that
		# already assumed that (the bridge abutments, the bank dressing) is
		# unaffected by the deepening.
		var u := d / RIVER_FLAT
		bed = RIVER_Y - RIVER_DEEP * (1.0 - u * u)
	bed = _shoal(x, z, bed)
	if d <= RIVER_FLAT:
		return bed
	# LINEAR blend, not smoothstep. smoothstep peaks at 1.5x the average
	# gradient and that peak is what turned the banks into an unwalkable wall.
	var t := (RIVER_HALF_WIDTH - d) / (RIVER_HALF_WIDTH - RIVER_FLAT)
	# min() so the carve can only cut down, never build a raised bed on ground
	# that is already below the waterline. The bed is clamped to RIVER_Y so a
	# shoal cannot raise the dry bank either.
	return minf(h, lerpf(h, minf(bed, RIVER_Y), t))


## Raise the channel toward wadeable depth inside a shoal.
##
## THE SHOALS ARE DERIVED, NOT HAND-PLACED. The first version authored them at
## the masterplan's crossing landmarks — the ferry landing at (-95,136) and the
## east ford at (120,150) — and both roads still waded 1.2-1.4 m, because those
## landmarks are ON THE BANK. The ferry road actually crosses the channel 17 m
## upstream of its own landing. Authoring "roughly there" put a gravel bar in
## dry gravel and left the real crossing deep.
##
## So the site is computed: for each forded road, find the point along it that
## is closest to the channel centre. That is the crossing, whatever the
## landmark names say.
static func _shoal(x: float, z: float, bed: float) -> float:
	for s in _shoal_sites():
		var ds := Vector2(x - s[0], z - s[1]).length()
		if ds < s[2]:
			var w := 1.0 - smoothstep(0.0, 1.0, ds / s[2])
			bed = maxf(bed, lerpf(bed, RIVER_Y - FORD_DEPTH, w))
	return bed


static var _ford_sites: Array = []


static func _shoal_sites() -> Array:
	if _ford_sites.is_empty():
		for ri in FORDED_ROADS:
			var pts: Array = ROADS[ri][0]
			var total := route_length(pts)
			var d := 0.0
			var best_d := 0.0
			var best_off := 1e9
			while d <= total:
				var p := route_at(pts, d)
				# Distance from the channel centreline, not from the waterline:
				# the deepest water is mid-channel.
				var off := absf(p.y - _river_center_z(p.x))
				if off < best_off:
					best_off = off
					best_d = d
				d += 1.0
			if best_off < RIVER_HALF_WIDTH:
				var c := route_at(pts, best_d)
				_ford_sites.append([c.x, c.y, FORD_RADIUS])
	return _ford_sites


## Where the fords ended up, for tooling and for the audit.
static func ford_sites() -> Array:
	return _shoal_sites()


## Water depth at a point: positive under the surface, negative on dry land.
## The water surface mesh bakes this into its vertex stream (see
## mistvale_water.gdshader for why depth is baked rather than read back).
static func water_depth(x: float, z: float) -> float:
	return RIVER_Y - height_at(x, z)


static func _raise_mountain(h: float, x: float, z: float) -> float:
	if z > MOUNTAIN_START_Z:
		return h
	var t := clampf((MOUNTAIN_START_Z - z) / MOUNTAIN_SPAN, 0.0, 1.0)

	# The massif does not run straight north; it drifts, which is why the two
	# routes can take genuinely different lines up it.
	var cx := -8.0 + 48.0 * sin((z + 130.0) * 0.0052)
	var halfw := lerpf(250.0, 140.0, t)
	var lat := absf(x - cx) / halfw
	var fall := smoothstep(0.0, 1.0, clampf(lat, 0.0, 1.0))

	# The base profile already IS the ridge line. So the massif is built by
	# dropping the flanks toward an outer valley, not by inventing a second,
	# competing ridge — an earlier quantised version did the latter and
	# produced region-wide vertical cliffs that read as rice terraces.
	var outer := 78.0 + (h - 78.0) * VALLEY_FACTOR
	var ridge := h

	# ONE cliff break, and it winds. A feature for the Cliff Route to hug is
	# worth more than six shelves nobody can cross.
	# The mask keeps it on the east half: the Forest Trail must not be forced
	# over it, or "safe west / exposed east" is a lie the player will notice.
	var cliff_mask := smoothstep(0.0, 1.0, clampf((x + 45.0) / 60.0, 0.0, 1.0))
	var break_z := -232.0 + 30.0 * sin(x * 0.0105 + 0.6)
	var db := absf(z - break_z)
	if db < 8.0:
		ridge += 10.0 * fall * cliff_mask * (1.0 - db / 8.0)

	# Two low benches. Amplitude is deliberately small: they only have to READ
	# as shelves, and a bench you cannot walk up is just another wall.
	ridge += 4.0 * fall * _bench(z, -178.0 + 22.0 * sin(x * 0.008 - 0.4))
	ridge += 3.0 * fall * _bench(z, -305.0 + 26.0 * sin(x * 0.007 + 1.9))

	return lerpf(ridge, outer, fall)


## 0..1 ramp across a 26 m band centred on `center`.
static func _bench(z: float, center: float) -> float:
	return smoothstep(0.0, 1.0, clampf(1.0 - absf(z - center) / 26.0, 0.0, 1.0))


# --- Combat spaces (masterplan §12) ------------------------------------------
# [x, z, flat radius, rim blend width].
#
# WHY THESE ARE FLATTENED: the first audit measured every arena against the raw
# field and all eight came back UNEVEN — C02 Riverbank Flats hit 41.7 deg and
# C08 Ruins Forecourt varied 20.7 m across its 32 m radius. A fight on a 42 deg
# slope is not a fight, it is a slide. The masterplan says the terrain must
# serve combat, so the arena pads are authored, not hoped for.
#
# C05 Guild Stair is deliberately ABSENT: it is supposed to be sloped. Fighting
# up a staircase is the entire point of that space.
## [x, z, flat radius, rim blend width, flatness]
##
## FLATNESS is the important column. Forcing every arena to one absolute height
## is earthworks, not level design: a flat 20 m disc cut into a 15 deg
## mountainside needs a retaining bank, and that bank was itself measuring 43-48
## deg — steep enough that the walk failed on the very trails leading to it.
##
## What combat actually needs is EVEN ground, not LEVEL ground. So an arena's
## target is the natural smoothed terrain tilted toward its centre height by
## `flatness`: 0.9 is a plaza, 0.55 is a clearing that still reads as a slope.
## Less earth moved, no artificial bank, and the approach grades gently.
const ARENAS := [
	[120.0, 205.0, 15.0, 18.0, 0.90],   # C01 caravan ambush — a road, near flat
	[30.0, 175.0, 15.0, 18.0, 0.85],    # C02 riverbank flats
	[0.0, 0.0, 22.0, 22.0, 0.90],       # C03 market square — a plaza
	[-85.0, 60.0, 14.0, 16.0, 0.90],    # C04 forge yard — a yard
	[85.0, -262.0, 13.0, 16.0, 0.85],   # C06 cliff ledge
	[-62.0, -232.0, 20.0, 24.0, 0.68],  # C07 forest clearing — keeps its slope
	[-10.0, -355.0, 32.0, 30.0, 0.70],  # C08 ruins forecourt — a stone platform
]
## Not 1.0: a mathematically level disc reads as CG.
const ARENA_FLAT := 0.97


## Ground with pads levelled but no path cut yet. This is what the route
## profiles are sampled from.
static func _height_pre_route(x: float, z: float) -> float:
	return _flatten_arenas(_height_base(x, z), x, z)


static var _arena_targets := PackedFloat32Array()


static func _arena_heights() -> PackedFloat32Array:
	if _arena_targets.is_empty():
		var out := PackedFloat32Array()
		for a in ARENAS:
			out.append(_height_base(a[0], a[1]))
		_arena_targets = out
	return _arena_targets


## Which pad owns this point, and how strongly. Returns Vector2(weight, index);
## index is -1 when the point is outside every pad and rim.
##
## Split out of _flatten_arenas so the relief layer can reuse the SAME falloff
## instead of keeping a second copy of the maths. A second copy would drift, and
## the drift would show up as relief bumps appearing inside pads that had just
## been levelled flat.
static func _arena_pick(x: float, z: float) -> Vector2:
	var best_w := 0.0
	var best_i := -1
	for i in ARENAS.size():
		var a: Array = ARENAS[i]
		var r: float = a[2]
		var rim: float = a[3]
		var d := Vector2(x - a[0], z - a[1]).length()
		var w := 0.0
		if d <= r:
			w = 1.0
		elif d < r + rim:
			w = 1.0 - smoothstep(0.0, 1.0, (d - r) / rim)
		if w > best_w:
			best_w = w
			best_i = i
	return Vector2(best_w, float(best_i))


## How flat this point is required to stay, 0..1. The relief layer multiplies by
## (1 - this).
static func _arena_weight(x: float, z: float) -> float:
	return _arena_pick(x, z).x


static func _flatten_arenas(h: float, x: float, z: float) -> float:
	var pick := _arena_pick(x, z)
	var best_w := pick.x
	var best_i := int(pick.y)
	if best_i < 0:
		return h
	var targets := _arena_heights()
	var flatness: float = ARENAS[best_i][4]
	# Tilt toward the pad height instead of snapping to it: the pad keeps as
	# much of the local slope as its flatness allows, so there is no bank to
	# build and nothing for the approach trails to climb over.
	var target := lerpf(_height_smooth(x, z), targets[best_i], flatness)
	return lerpf(h, target, best_w * ARENA_FLAT)


# =============================================================================
# Micro-relief — LEVEL ART PASS 02 (§A3)
# =============================================================================
#
# WHAT THIS IS FOR: the region mesh is sampled every 3 m, so between samples the
# ground is a plane. On a slope that reads as a clean CG sheet — no small
# bumps, no little breaks, no scuffed edge. Real ground is never that tidy.
#
# WHAT IT MUST NOT DO: move the audited walk. Every metre that audit_routes
# measured has to stay identical, or a re-run of the slope audit is measuring a
# different terrain than the one the player gets. So the relief is multiplied
# by (1 - corridor) * (1 - pad): exactly zero on every road centreline, on the
# routes, and inside every combat pad.
#
# Amplitude is deliberately small. This is the ground being *not flat*, not
# features.

## How broken the ground is allowed to get, by band. The town must stay
## buildable — a market you cannot lay a stall on is a failure.
static func _relief_amp(z: float, y: float) -> float:
	if y < 9.0:
		return 0.10       # river bed: silt, nearly smooth
	if y < 17.0:
		return 0.45       # banks: scoured, uneven
	if z > 95.0:
		return 0.55       # east forest: soft, rolling
	if z > -140.0:
		return 0.22       # town band: nearly smooth
	return 0.85           # mountain: broken


static func _relief(h: float, x: float, z: float) -> float:
	var keep := maxf(_corridor_keep(x, z), _arena_weight(x, z))
	if keep >= 0.999:
		return h
	var amp := _relief_amp(z, h)
	if amp <= 0.0:
		return h
	# Two octaves: the broad one gives mounds, the fine one gives the crumb.
	var broad := _vnoise(x * 0.055, z * 0.055) - 0.5
	var fine := _vnoise(x * 0.185 + 31.0, z * 0.185 - 17.0) - 0.5
	# A third, sharper term only on broken ground: this is the little scarp
	# edges and slumped steps, not a smooth dune.
	var crisp := absf(_vnoise(x * 0.34 - 5.0, z * 0.34 + 9.0) - 0.5) - 0.25
	return h + (broad * 0.72 + fine * 0.28 + crisp * 0.35) * 2.0 * amp * (1.0 - keep)


## Lazily-built walking profiles: the un-carved ground height at each waypoint.
## Computed once; the field is static, so there is nothing to invalidate.
static var _profiles: Array = []


static func _route_profiles() -> Array:
	if _profiles.is_empty():
		_profiles = [
			_profile_along(FOREST_TRAIL),
			_profile_along(CLIFF_ROUTE),
		]
	return _profiles


## Sampled from the PAD-LEVELLED field, not the raw one.
##
## This is the fix for the route/arena conflict. When the profile came from the
## raw field, a trail crossing a levelled pad was pulled two ways at once — the
## carve wanted its linear profile, the pad wanted one height — and the ground
## had to reconcile two contradictory targets. Widening the pad rim only spread
## the argument over more metres. Sampling the profile after levelling means the
## trail already agrees with the pad before the carve runs, so there is nothing
## left to reconcile.
static func _profile_along(pts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p: Vector2 in pts:
		out.append(_height_pre_route(p.x, p.y))
	return out


static func _carve_routes(h: float, x: float, z: float) -> float:
	var profs := _route_profiles()
	var a := _nearest_on_polyline(x, z, FOREST_TRAIL, profs[0])
	var b := _nearest_on_polyline(x, z, CLIFF_ROUTE, profs[1])
	# Vector2(distance, walking height). Vector3 was wrong here — it has no .w,
	# and a missing member silently parsed as a different symbol than intended.
	var near := a if a.x <= b.x else b
	if near.x > ROUTE_HALF_WIDTH:
		return h
	var t := smoothstep(0.0, 1.0, 1.0 - near.x / ROUTE_HALF_WIDTH)
	return lerpf(h, near.y, t * ROUTE_CARVE)


static func _erosion(x: float, z: float) -> float:
	# Amplitude is zone-dependent on purpose. The town must stay buildable — a
	# market you cannot lay a stall on is a failure — while the mountain wants
	# to look like it has been rained on for ten thousand years.
	var amp := 0.0
	if z > 95.0:
		amp = 2.2      # East Forest: soft, rolling
	elif z > -140.0:
		amp = 0.45     # Town band: nearly flat, just enough to kill the CG feel
	else:
		amp = 5.0      # Mountain: broken
	# The channel is authored, not eroded: see CHANNEL_EROSION.
	var d := absf(z - _river_center_z(x))
	var wet := smoothstep(RIVER_HALF_WIDTH, RIVER_HALF_WIDTH + 30.0, d)
	amp *= lerpf(CHANNEL_EROSION, 1.0, wet)
	return (_fbm(x * 0.011, z * 0.011) - 0.5) * 2.0 * amp


# =============================================================================
# Noise — deterministic, no dependency on a library
# =============================================================================

static func _hash2(x: float, z: float) -> float:
	var s := sin(x * 127.1 + z * 311.7) * 43758.5453
	return s - floorf(s)


static func _vnoise(x: float, z: float) -> float:
	var xi := floorf(x)
	var zi := floorf(z)
	var xf := x - xi
	var zf := z - zi
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := zf * zf * (3.0 - 2.0 * zf)
	var a := _hash2(xi, zi)
	var b := _hash2(xi + 1.0, zi)
	var c := _hash2(xi, zi + 1.0)
	var d := _hash2(xi + 1.0, zi + 1.0)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


static func _fbm(x: float, z: float) -> float:
	var sum := 0.0
	var amp := 0.5
	var freq := 1.0
	for _i in 3:
		sum += _vnoise(x * freq, z * freq) * amp
		amp *= 0.5
		freq *= 2.03
	return sum


# =============================================================================
# Geometry helper — distance and interpolated height to a polyline
# =============================================================================

## Returns Vector2(distance, walking height) for the closest point on `pts`,
## where `profile` holds the ground height at each waypoint.
static func _nearest_on_polyline(
	px: float, pz: float, pts: Array, profile: PackedFloat32Array
) -> Vector2:
	var best := Vector2(1e9, 0.0)
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var vx := b.x - a.x
		var vz := b.y - a.y
		var len2 := vx * vx + vz * vz
		var t := 0.0
		if len2 > 1e-6:
			t = clampf(((px - a.x) * vx + (pz - a.y) * vz) / len2, 0.0, 1.0)
		var cx := a.x + vx * t
		var cz := a.y + vz * t
		var dx := px - cx
		var dz := pz - cz
		var d := sqrt(dx * dx + dz * dz)
		if d < best.x:
			best = Vector2(d, lerpf(profile[i], profile[i + 1], t))
	return best


## Ground height at an arbitrary point on a route, for marker placement.
static func route_height(pts: Array, profile: PackedFloat32Array, x: float, z: float) -> float:
	return _nearest_on_polyline(x, z, pts, profile).y


# =============================================================================
# Public route sampling — shared by the blockout placer and every audit tool
# =============================================================================
#
# These exist so that "where is the path at metre 243" has ONE answer. The
# blockout, the slope audit and the composition audit all walk the same
# polyline through these functions; if any of them re-implemented the walk, a
# half-metre disagreement would show up as a staircase placed off the trail.

## Point on a route at `dist` metres from its start. XZ only.
static func route_at(pts: Array, dist: float) -> Vector2:
	var acc := 0.0
	for i in pts.size() - 1:
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[i + 1]
		var seg := p.distance_to(q)
		if acc + seg >= dist:
			return p.lerp(q, (dist - acc) / maxf(seg, 0.0001))
		acc += seg
	var last: Vector2 = pts[-1]
	return last


## Unit tangent of a route at `dist`, pointing in the direction of travel.
static func route_tangent(pts: Array, dist: float) -> Vector2:
	var a := route_at(pts, maxf(dist - 1.0, 0.0))
	var b := route_at(pts, dist + 1.0)
	var d := b - a
	if d.length() < 0.0001:
		return Vector2(0.0, -1.0)
	return d.normalized()


## Total XZ length of a route.
static func route_length(pts: Array) -> float:
	var acc := 0.0
	for i in pts.size() - 1:
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[i + 1]
		acc += p.distance_to(q)
	return acc


# =============================================================================
# Review helper — colour bands match the masterplan colour story (§13)
# =============================================================================

## Warm settlement low on the valley, cold ancient stone up on the mountain.
static func band_color(y: float) -> Color:
	if y < 12.0:
		return Color(0.24, 0.33, 0.36)      # river — cold, wet
	if y < 30.0:
		return Color(0.36, 0.42, 0.33)      # valley floor — humid green
	if y < 52.0:
		return Color(0.52, 0.48, 0.41)      # town — warm, lived in
	if y < 80.0:
		return Color(0.47, 0.46, 0.45)      # upper town — stone
	if y < 140.0:
		return Color(0.38, 0.39, 0.42)      # mountain — desaturating
	return Color(0.40, 0.46, 0.50)         # ruins — restrained cyan drift
