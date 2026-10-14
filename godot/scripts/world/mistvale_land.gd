@tool
extends Node3D
class_name MistvaleLand
## LEVEL ART PASS 02 — the land surface layer of the Mistvale region.
##
## WHAT THIS ADDS OVER mistvale_terrain.gd: terrain is the GROUND. This is
## everything that sits on it and tells you where to walk —
##
##   * road surfaces, as geometry, following the road network in
##     MistvaleHeights.ROADS (so they cannot drift away from the road paint the
##     terrain shader draws, or from the corridor the walk audits measure);
##   * a bridge, because the main road measurably crossed the river at bed
##     level and the player would have waded 38 m of their own street;
##   * the river surface;
##   * riverbank gravel.
##
## WHY ROADS ARE GEOMETRY AND NOT JUST PAINT: paint on a 3 m terrain grid has a
## ~1.5 m soft edge, cannot hold a kerb, and cannot cross water. The terrain
## shader still paints the WORN VERGE; this draws the actual road.
##
## EVERY HEIGHT COMES FROM MistvaleHeights. Nothing here authors an elevation —
## see the lesson in the masterplan: a hand-written height that disagrees with
## the field shows up later as an unwalkable wall.

@export var build_roads: bool = true
@export var build_bridge: bool = true
@export var build_water: bool = true
@export var build_banks: bool = true

## How far a road surface floats above the terrain. The terrain mesh interpolates
## between 3 m samples, so on a curved surface it deviates a few centimetres from
## the analytic field; 10 cm is invisible from eye height and removes the
## z-fighting without a depth-bias trick (Godot 4 exposes none for materials).
const LIFT := 0.10

## The market junction is a SECOND ribbon laid over the field, so its surface
## stands `LIFT` PLUS this above the analytic field - 25.8 cm in the middle of
## the square, tapering to the edge value below at the outer ring.
##
## WHY THIS IS A CONSTANT AND NOT A LITERAL INSIDE `_market_junction`, AND WHY
## THE NUMBERS ARE PUBLISHED AT ALL. Anything that wants to lie ON the square
## rather than under it has to start from this number: another paving layer, a
## decal, a prop dropped onto the ground, a review camera that means to look at
## the paving and not at the field. The plaza's own stone apron was built from
## `MistvaleHeights.height_at` plus 14 cm, which is 12 cm BELOW this ribbon, and
## it spent a whole round completely buried - drawn, correct, listed in the
## scene tree, and invisible - while the market square read as bare dirt. The
## apron's author measured the disc, confirmed every normal faced up, confirmed
## it sat above the field, and could not explain it, because the field was not
## what was being drawn.
const MARKET_PAVING_LIFT := 0.158
## What the junction's lift decays to at the outer ring, so the apron merges
## into the roads instead of ending on a 16 cm lip.
const MARKET_PAVING_EDGE := 0.018
## Rings over which the junction fades from its full lift to its edge value.
const MARKET_INNER := 12.0
const MARKET_OUTER := 20.0

## Road sampling. 2 m is fine enough for a smooth ribbon through the corners of
## a polyline whose segments are 20-90 m long.
const ROAD_STEP := 2.0

## Lateral stations across a road, as a fraction of half-width. Seven stations
## give the crown and the wheel ruts a place to live; three would not.
const STATIONS := [-1.0, -0.66, -0.34, 0.0, 0.34, 0.66, 1.0]

## Bridge deck clearance above the water surface.
const DECK_CLEAR := 2.45
## Length over which the road ramps up from the ground onto the deck.
const DECK_RAMP := 13.0
## Gentle rise on the crossing itself. The whole road and its collision follow
## this profile; the centre is 1.25 m above the spring points.
const ARCH_RISE := 1.80

const WATER_HALF := 14.6
const WATER_STEP := 4.0
const SHADER_WATER := "res://resources/shaders/mistvale_water.gdshader"
const SHADER_ROAD := "res://resources/shaders/mistvale_road.gdshader"
const SHADER_BRIDGE_STONE := "res://resources/shaders/mistvale_bridge_stone.gdshader"

## Surface look, index-aligned with MistvaleHeights.ROADS.
##
## The WIDTH lives in the field (one definition, shared with the paint and the
## corridor mask). Only the look is authored here. The size guard in _roads()
## makes an index mismatch loud instead of building a trail in plaza paving.
##
## `paved` WAS 0.85 ON THE MAIN STREET AND THAT WAS A PAVING-QUILT.
##
## The shader reads it as "how much of the sett behaviour applies", and at 0.85
## the answer was nearly all of it: the whole 7.2 m carriageway was laid stone
## with the grass creep suppressed to 28%. Combined with a per-stone shade
## spread of +/-15% and length-of-day coverage, the market square at d=440 came
## back as a patchwork quilt — light and dark flags with dark seams, reading as
## loose badly-laid tiles. §6 asks for the opposite: a path people have walked
## on for a hundred years, which is MOSTLY COMPACTED EARTH with stones surfacing
## through it. 0.58 with the shader's contrast cuts brings it back to that.
## The lanes drop proportionally; the trails were already bare earth.
const ROAD_STYLE := [
	{"tint": Color(0.455, 0.372, 0.282), "paved": 0.58, "crown": 0.09},  # 0 main street
	{"tint": Color(0.412, 0.330, 0.248), "paved": 0.34, "crown": 0.07},  # 1 forge lane
	{"tint": Color(0.428, 0.345, 0.258), "paved": 0.34, "crown": 0.07},  # 2 residential
	{"tint": Color(0.392, 0.315, 0.236), "paved": 0.24, "crown": 0.06},  # 3 ferry road
	{"tint": Color(0.402, 0.328, 0.252), "paved": 0.18, "crown": 0.06},  # 4 bank road
	{"tint": Color(0.430, 0.355, 0.272), "paved": 0.00, "crown": 0.05},  # 5 east ford
	{"tint": Color(0.352, 0.278, 0.208), "paved": 0.00, "crown": 0.05},  # 6 forest trail
	{"tint": Color(0.330, 0.272, 0.212), "paved": 0.00, "crown": 0.04},  # 7 cliff route
]

var _spans: Array = []          # planned bridges, filled by _plan_bridges()
var _missing_env := PackedStringArray()


# =============================================================================
# Build
# =============================================================================

func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_spans.clear()
	_missing_env.clear()

	_plan_bridges()
	if build_water:
		_water()
	if build_banks:
		_banks()
	if build_roads:
		_roads()
		_market_junction()
	if build_bridge:
		_bridges()

	if not _missing_env.is_empty():
		push_warning("MistvaleLand: %d environmental asset(s) missing: %s"
			% [_missing_env.size(), ", ".join(_missing_env)])


func _layer(n: String) -> Node3D:
	var node := Node3D.new()
	node.name = n
	add_child(node)
	return node


# =============================================================================
# Bridge planning — one answer for "where is the road over water"
# =============================================================================

## Which roads carry a bridge across water.
##
## ONE BRIDGE, ON THE MAIN STREET. The masterplan's three crossings are one
## bridge, one ferry and one ford (§7), and turning all three into bridges would
## erase two thirds of the river's route identity — as well as being wrong, since
## the first build put a 33 m pier bridge where the masterplan says "east ford".
## The other two crossings are made genuinely shallow by the SHOALS in
## MistvaleHeights, and the road ribbon simply continues through the shallows,
## which is exactly what a ford looks like from the saddle.
const BRIDGED_ROADS := [0]

## A crossing deeper than this that has no bridge is a hole in the route
## network, not a ford. Reported loudly rather than waded silently.
const MAX_WADE_DEPTH := 0.80


## A bridge is needed wherever a road runs below the waterline for more than a
## few metres. Both the road ribbon and the bridge structure read _spans, so the
## deck the player walks and the deck they see cannot disagree.
func _plan_bridges() -> void:
	for ri in MistvaleHeights.ROADS.size():
		var pts: Array = MistvaleHeights.ROADS[ri][0]
		var total := MistvaleHeights.route_length(pts)
		var d := 0.0
		var run_start := -1.0
		var last_wet := -1.0
		while d <= total:
			var p := MistvaleHeights.route_at(pts, d)
			var wet := MistvaleHeights.height_at(p.x, p.y) < MistvaleHeights.RIVER_Y + 0.10
			if wet:
				if run_start < 0.0:
					run_start = d
				last_wet = d
			elif run_start >= 0.0:
				_close_span(ri, pts, run_start, last_wet)
				run_start = -1.0
			d += 1.0
		if run_start >= 0.0:
			_close_span(ri, pts, run_start, last_wet)


func _close_span(ri: int, pts: Array, a: float, b: float) -> void:
	if b - a < 6.0:
		return    # a puddle in the road, not a crossing
	if not BRIDGED_ROADS.has(ri):
		_warn_if_too_deep(ri, pts, a, b)
		return
	var pa := MistvaleHeights.route_at(pts, maxf(a - DECK_RAMP, 0.0))
	var pb := MistvaleHeights.route_at(pts, b + DECK_RAMP)
	# The deck sits clear of the water and no lower than either approach road,
	# so there is never a step up onto the abutment.
	var deck_y: float = MistvaleHeights.RIVER_Y + DECK_CLEAR
	deck_y = maxf(deck_y, MistvaleHeights.height_at(pa.x, pa.y))
	deck_y = maxf(deck_y, MistvaleHeights.height_at(pb.x, pb.y))
	_spans.append({
		"road": ri, "start": a, "end": b, "deck_y": deck_y,
		"span": b - a,
	})
	print("MistvaleLand: bridge on road %d, %.0f m span, deck Y=%.2f (water %.2f)"
		% [ri, b - a, deck_y, MistvaleHeights.RIVER_Y])


## A ford has to be shallow enough to walk. If a crossing that is supposed to be
## waded is actually deep, the route network has a gap in it — fail loudly.
func _warn_if_too_deep(ri: int, pts: Array, a: float, b: float) -> void:
	var worst := 0.0
	var at := a
	var d := a
	while d <= b:
		var p := MistvaleHeights.route_at(pts, d)
		var dep := MistvaleHeights.water_depth(p.x, p.y)
		if dep > worst:
			worst = dep
			at = d
		d += 1.0
	if worst > MAX_WADE_DEPTH:
		push_error(("MistvaleLand: road %d crosses %.1f m of water at %.0f m along "
			+ "and has no bridge — the player would be swimming. Add a shoal to "
			+ "MistvaleHeights.SHOALS or add the road to BRIDGED_ROADS.")
			% [ri, worst, at])
	else:
		print("MistvaleLand: road %d fords %.0f m at up to %.2f m deep (wadeable)"
			% [ri, b - a, worst])


## Where a player actually stands at this XZ: the highest walkable surface.
##
## WHY THIS IS PUBLIC AND WHY IT IS NOT height_at: at the bridge crest the
## ground is the river bed, 3 m BELOW the deck the player walks on. The review
## camera sampled MistvaleHeights.height_at, so the "V2 Bridge Crest" shot was
## taken from underneath the bridge looking at its own underside and a pier.
## Any tool that wants to stand where the player stands has to ask this.
func surface_height(x: float, z: float) -> float:
	var best := MistvaleHeights.height_at(x, z)
	for s in _spans:
		var ri: int = s["road"]
		var pts: Array = MistvaleHeights.ROADS[ri][0]
		var halfw: float = MistvaleHeights.ROADS[ri][1]
		var total := MistvaleHeights.route_length(pts)
		var d := maxf(float(s["start"]) - DECK_RAMP, 0.0)
		while d <= float(s["end"]) + DECK_RAMP:
			var c := MistvaleHeights.route_at(pts, d)
			if Vector2(c.x - x, c.y - z).length() < halfw + 1.4:
				var w := _span_weight(d, float(s["start"]), float(s["end"]))
				if w > 0.0:
					best = maxf(best, lerpf(best, _bridge_top(s, d) + LIFT, w))
			d += 1.5
	return best


## How far the market junction's paving stands above `surface_height` at this
## XZ. Falls to `MARKET_PAVING_EDGE` outside the junction's footprint.
##
## THE INVERSE IS EXACT, NOT A FUDGE. `_market_junction` builds its footprint as
## a superellipse - `x = sgn(cos a)|cos a|^0.55 r` and `z = sgn(sin a)|sin a|^0.55
## (0.82 r)` - and that pair eliminates the angle: normalising each component and
## using `cos^2 + sin^2 = 1` leaves `(|x|^k + (|z|/0.82)^k) = r^k` with
## `k = 2/0.55`. A point's ring is that expression's k-th root, so re-tuning the
## junction re-tunes this with it, and no second hand-written number has to be
## kept in agreement with the first.
## `static`, so a layer that has not been given a `MistvaleLand` node can still
## ask the height field the right question. Every input is a constant.
static func market_paving_lift(x: float, z: float) -> float:
	const K := 2.0 / 0.55
	var ring := pow(pow(absf(x), K) + pow(absf(z) / 0.82, K), 1.0 / K)
	return (MARKET_PAVING_LIFT - MARKET_PAVING_EDGE) \
			* (1.0 - smoothstep(MARKET_INNER, MARKET_OUTER, ring)) \
			+ MARKET_PAVING_EDGE


## Where the market square's paving actually is, in world units.
##
## `surface_height` PLUS THE JUNCTION RIBBON, and this - not `surface_height`,
## and certainly not `MistvaleHeights.height_at` - is what a prop, a paving
## layer, or a camera that means to sit on the square has to ask for. Asking
## `height_at` there answers with the bare field, 26 cm low, which is exactly how
## the plaza's stone apron came to be built, drawn, and buried.
func paving_height(x: float, z: float) -> float:
	return surface_height(x, z) + LIFT + market_paving_lift(x, z)


## Road height at a point that is `along` metres down road `ri`.
## Ground, unless a bridge span is carrying it.
func _road_y(x: float, z: float, ri: int, along: float) -> float:
	var base := MistvaleHeights.height_at(x, z) + LIFT
	for s in _spans:
		if s.road != ri:
			continue
		var w := _span_weight(along, s.start, s.end)
		if w > 0.0:
			base = lerpf(base, _bridge_top(s, along) + LIFT, w)
	return base


func _bridge_top(s: Dictionary, along: float) -> float:
	var u := clampf((along - float(s["start"])) / maxf(float(s["span"]), 0.01), 0.0, 1.0)
	return float(s["deck_y"]) + ARCH_RISE * (1.0 - pow(2.0 * u - 1.0, 2.0))


## 0 outside the ramps, 1 across the whole deck, smooth in between.
func _span_weight(along: float, a: float, b: float) -> float:
	if along < a - DECK_RAMP or along > b + DECK_RAMP:
		return 0.0
	if along >= a and along <= b:
		return 1.0
	if along < a:
		return smoothstep(0.0, 1.0, 1.0 - (a - along) / DECK_RAMP)
	return smoothstep(0.0, 1.0, 1.0 - (along - b) / DECK_RAMP)


# =============================================================================
# Roads
# =============================================================================

func _roads() -> void:
	var root := _layer("Roads")
	if MistvaleHeights.ROADS.size() != ROAD_STYLE.size():
		push_error("MistvaleLand: ROAD_STYLE has %d entries but MistvaleHeights.ROADS has %d — a road would be built with the wrong surface"
			% [ROAD_STYLE.size(), MistvaleHeights.ROADS.size()])
	for ri in MistvaleHeights.ROADS.size():
		var road: Array = MistvaleHeights.ROADS[ri]
		var pts: Array = road[0]
		var halfw: float = road[1]
		var style: Dictionary = ROAD_STYLE[ri] if ri < ROAD_STYLE.size() else ROAD_STYLE[0]
		var mesh := _road_mesh(pts, halfw, style, ri)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Road_%02d" % ri
		mi.mesh = mesh
		mi.material_override = _road_material(ri == 0)
		# A road surface is a decal lying 10 cm above the ground. If it casts,
		# it shadows itself: the whole street came back as a black wedge under a
		# dense moire, which is the single most alarming thing this pass
		# produced and took three bisect renders to attribute. Ground-hugging
		# sheets do not cast.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


func _market_junction() -> void:
	# The three road crowns meet in a flat civic space. Their raw overlapping
	# ribbons form a V-shaped seam, so this terrain-following paved apron binds
	# them into one readable market surface. A rounded rectangle gives it an
	# intentional civic footprint rather than a circular decal.
	var radii: Array[float] = [0.0, 5.0, 10.0, 15.0, 20.0]
	var sides := 48
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	for ring: float in radii:
		for i in sides:
			var a := TAU * float(i) / float(sides)
			var ca := cos(a)
			var sa := sin(a)
			var x: float = signf(ca) * pow(absf(ca), 0.55) * ring
			var z: float = signf(sa) * pow(absf(sa), 0.55) * ring * 0.82
			var lift := (MARKET_PAVING_LIFT - MARKET_PAVING_EDGE) \
					* (1.0 - smoothstep(MARKET_INNER, MARKET_OUTER, ring)) \
					+ MARKET_PAVING_EDGE
			verts.append(Vector3(x, MistvaleHeights.height_at(x, z) + LIFT + lift, z))
			cols.append(Color(0.45, 0.38, 0.30, 0.43))
			uvs.append(Vector2((x + 30.0) / 6.0, clampf((z + 17.0) / 34.0, 0.0, 1.0)))
	var idxs := PackedInt32Array()
	for ring in radii.size() - 1:
		for i in sides:
			var n := (i + 1) % sides
			var a := ring * sides + i
			var b := ring * sides + n
			var c := (ring + 1) * sides + i
			var d := (ring + 1) * sides + n
			idxs.append_array(PackedInt32Array([a, d, c, a, b, d]))
	var mi := MeshInstance3D.new()
	mi.name = "MarketJunctionPlaza"
	mi.mesh = _finish(verts, cols, uvs, idxs)
	mi.material_override = _road_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_node("Roads").add_child(mi)


func _road_material(paint_main_route: bool = false) -> Material:
	# A real road shader, not a tint.
	#
	# WHY: the vertex stream can only carry one colour per vertex, and the road
	# is sampled every 2 m along and 7 stations across. Every square metre
	# between those vertices was a flat interpolation of one earth colour, so
	# the surface had no ruts, no verge, no aggregate and no wet patches — it
	# measured rgb(161,161,160), a grey slipway. The surface detail has to be
	# per-pixel; that means a shader.
	#
	# The vertex colour is still the road's own tint, and its ALPHA now carries
	# `paved`, which tells the shader how much of its behaviour applies: a civic
	# street keeps its ruts and its setts, a mountain footpath lets grass grow
	# back into the middle of it.
	var sh := load(SHADER_ROAD) as Shader
	if sh == null:
		push_error("MistvaleLand: road shader missing at %s" % SHADER_ROAD)
		var fb := StandardMaterial3D.new()
		fb.vertex_color_use_as_albedo = true
		fb.roughness = 1.0
		fb.specular = 0.10
		fb.cull_mode = BaseMaterial3D.CULL_DISABLED
		return fb
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("paint_main_route", 1.0 if paint_main_route else 0.0)
	m.set_shader_parameter("packed_dirt_paint",
		load("res://textures/environment/foundation_v2/mv_packed_dirt_paint_albedo.png"))
	return m


func _road_mesh(pts: Array, halfw: float, style: Dictionary, ri: int) -> ArrayMesh:
	var total := MistvaleHeights.route_length(pts)
	if total <= 0.0:
		return null
	var n := int(total / ROAD_STEP) + 1
	var ns := STATIONS.size()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(n * ns)
	cols.resize(n * ns)
	uvs.resize(n * ns)

	var tint: Color = style["tint"]
	var crown: float = style["crown"]
	var paved: float = style["paved"]

	for i in n:
		var along := minf(float(i) * ROAD_STEP, total)
		var c := MistvaleHeights.route_at(pts, along)
		var tan := MistvaleHeights.route_tangent(pts, along)
		# Left-hand perpendicular in XZ (Y is up).
		var nrm := Vector2(-tan.y, tan.x)
		for si in ns:
			var s: float = STATIONS[si]
			# Edge irregularity: a road is never two clean parallel lines. The
			# offset is deterministic per (road, metre) so repeated builds and
			# review renders agree.
			var edge := 1.0
			if absf(s) > 0.9:
				edge += (MistvaleHeights.variation(along * 1.7 + float(ri) * 31.0, s * 11.0) - 0.5) * 0.30
			var lat := s * halfw * edge
			var px := c.x + nrm.x * lat
			var pz := c.y + nrm.y * lat
			var y := _road_y(px, pz, ri, along) + crown * (1.0 - s * s)
			var idx := i * ns + si
			verts[idx] = Vector3(px, y, pz)
			uvs[idx] = Vector2(along / 6.0, s * 0.5 + 0.5)

			# ONLY the large-scale dry/muddy field is baked here now.
			#
			# The ruts, the aggregate, the puddles and the verge all moved into
			# mistvale_road.gdshader, because they are per-PIXEL phenomena and
			# this mesh has vertices every 2 m along and 7 stations across:
			# a wheel rut baked into vertex colour is a 2 m wide dark smear with
			# soft edges, which is not a rut. Baking the fine per-metre hash here
			# as well made it worse — it aliased against the shader's grit and
			# produced a visible beat down the length of every straight.
			#
			# What is left is one low-frequency field, tens of metres across,
			# which says where this stretch of road is clay and where it is dust.
			var coarse := MistvaleHeights.grain(px * 0.21 + 5.0, pz * 0.21 - 2.0)
			var shade := 0.86 + coarse * 0.30
			# Paved roads are paler and greyer than bare earth tracks.
			var c2 := tint.lerp(Color(0.708, 0.701, 0.687), paved * 0.40)
			# ALPHA CARRIES `paved`. The shader needs it: a civic street keeps
			# its crown and its setts, a mountain footpath lets grass grow back
			# into the middle of it, and that difference cannot be inferred from
			# a colour.
			cols[idx] = Color(c2.r * shade, c2.g * shade, c2.b * shade, paved)

	var idxs := PackedInt32Array()
	idxs.resize((n - 1) * (ns - 1) * 6)
	var k := 0
	# WINDING IS LOAD-BEARING. (a, c3, b) — stepping "along" before "across" —
	# gives a normal of along x across, which in this frame is straight DOWN.
	# The road was therefore lit from underneath: zero sun contribution, ambient
	# only, and it rendered as a black asphalt ribbon lying across a green
	# valley. `finish()` accumulates normals from the winding, so the winding is
	# what decides whether the road exists visually or not.
	for i in n - 1:
		for si in ns - 1:
			var a := i * ns + si
			var b := a + 1
			var c3 := a + ns
			var d := c3 + 1
			idxs[k] = a
			idxs[k + 1] = b
			idxs[k + 2] = c3
			idxs[k + 3] = b
			idxs[k + 4] = d
			idxs[k + 5] = c3
			k += 6

	return _finish(verts, cols, uvs, idxs)


# =============================================================================
# Water
# =============================================================================

func _water() -> void:
	var root := _layer("Water")
	var sh := load(SHADER_WATER) as Shader
	if sh == null:
		push_error("MistvaleLand: water shader missing at %s" % SHADER_WATER)
		return

	var x0: float = MistvaleHeights.MIN_X
	var x1: float = MistvaleHeights.MAX_X
	var n := int((x1 - x0) / WATER_STEP) + 1
	var ns := 9
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(n * ns)
	cols.resize(n * ns)
	uvs.resize(n * ns)

	for i in n:
		var x: float = x0 + float(i) * WATER_STEP
		var cz := MistvaleHeights.river_center_z(x)
		for si in ns:
			var s := float(si) / float(ns - 1) * 2.0 - 1.0
			var z := cz + s * WATER_HALF
			var idx := i * ns + si
			verts[idx] = Vector3(x, MistvaleHeights.RIVER_Y, z)
			uvs[idx] = Vector2(x, z) / 12.0
			# Depth is baked, not read from a depth buffer: this project runs
			# gl_compatibility, which has no dependable screen-depth read in a
			# spatial shader.
			var depth: float = MistvaleHeights.water_depth(x, z)
			var dn := clampf(depth / (MistvaleHeights.RIVER_DEEP + 0.35), 0.0, 1.0)
			# Flow: fastest mid-channel, slack at the edges.
			var flow := clampf(1.0 - absf(s) * absf(s) * 1.15, 0.0, 1.0)
			cols[idx] = Color(dn, flow, 0.0)

	# Same winding correction as the road: this mesh also steps "along" before
	# "across", so its normals were pointing at the river bed.
	var idxs := PackedInt32Array()
	idxs.resize((n - 1) * (ns - 1) * 6)
	var k := 0
	for i in n - 1:
		for si in ns - 1:
			var a := i * ns + si
			var b := a + 1
			var c := a + ns
			var d := c + 1
			idxs[k] = a
			idxs[k + 1] = b
			idxs[k + 2] = c
			idxs[k + 3] = b
			idxs[k + 4] = d
			idxs[k + 5] = c
			k += 6

	var mi := MeshInstance3D.new()
	mi.name = "RiverSurface"
	var mesh := _finish(verts, cols, uvs, idxs)
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mi.material_override = mat
	# Drawn after the ground so the transparent edges do not fight it.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# =============================================================================
# Riverbank gravel
# =============================================================================

## Stones along the waterline. Placed by rule, not scattered randomly: they hug
## the shallow margin, they get denser where the bed is shallow (bars and
## shoals), and there are none in the deep channel.
func _banks() -> void:
	var root := _layer("Banks")
	var body := MultiMesh.new()
	body.transform_format = MultiMesh.TRANSFORM_3D
	body.mesh = _pebble_mesh()

	var xf := []
	var x0: float = MistvaleHeights.MIN_X
	var x1: float = MistvaleHeights.MAX_X
	var z0: float = MistvaleHeights.MIN_Z
	var x := x0
	while x <= x1:
		var cz := MistvaleHeights.river_center_z(x)
		for k in 5:
			var z := cz + (float(k) - 2.0) * 7.2
			z += (MistvaleHeights.variation(x * 0.7, z * 0.7) - 0.5) * 3.0
			if z < z0:
				continue
			var depth := MistvaleHeights.water_depth(x, z)
			# The margin: shallow water or the first half metre of dry bank.
			if depth > 0.30 or depth < -1.1:
				continue
			var s := MistvaleHeights.variation(x * 3.1, z * 3.1)
			var scale := 0.30 + s * 0.85
			var t := Transform3D()
			t = t.rotated(Vector3.UP, s * TAU)
			t = t.scaled(Vector3(scale, scale * (0.55 + s * 0.4), scale))
			t.origin = Vector3(x, MistvaleHeights.height_at(x, z) + scale * 0.20, z)
			xf.append(t)
		x += 3.4

	body.instance_count = xf.size()
	for i in xf.size():
		body.set_instance_transform(i, xf[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = "BankGravel"
	mi.multimesh = body
	mi.material_override = _stone_material()
	root.add_child(mi)
	print("MistvaleLand: bank gravel instances = %d" % xf.size())


func _pebble_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A low, chunked stone: a tapered irregular prism. Deliberately rough; this
	# is river gravel seen from a road, not a hero prop.
	# [radius, height] from top of the stone down to its base.
	var rings: Array = [
		Vector2(0.0, 1.00),
		Vector2(0.62, 0.74),
		Vector2(0.88, 0.30),
		Vector2(0.74, 0.00),
	]
	var sides := 7
	for r in rings.size() - 1:
		var ra: Vector2 = rings[r]
		var rb: Vector2 = rings[r + 1]
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			# Irregular radii so the stone is not a cylinder.
			var ja := 0.82 + 0.18 * sin(a0 * 3.0 + float(r))
			var jb := 0.82 + 0.18 * sin(a1 * 3.0 + float(r))
			var p00 := Vector3(cos(a0) * ra.x * ja, ra.y, sin(a0) * ra.x * ja)
			var p01 := Vector3(cos(a1) * ra.x * jb, ra.y, sin(a1) * ra.x * jb)
			var p10 := Vector3(cos(a0) * rb.x * ja, rb.y, sin(a0) * rb.x * ja)
			var p11 := Vector3(cos(a1) * rb.x * jb, rb.y, sin(a1) * rb.x * jb)
			st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)
	# Bottom cap so the stone is not hollow when seen at a shallow angle.
	var rr: float = rings[-1].x
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		st.add_vertex(Vector3(0.0, 0.0, 0.0))
		st.add_vertex(Vector3(cos(a1) * rr, 0.0, sin(a1) * rr))
		st.add_vertex(Vector3(cos(a0) * rr, 0.0, sin(a0) * rr))
	st.generate_normals()
	return st.commit()


func _stone_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.618, 0.614, 0.601)
	m.roughness = 0.94
	return m


# =============================================================================
# Bridge structures
# =============================================================================

func _bridges() -> void:
	if _spans.is_empty():
		return
	var root := _layer("Bridges")
	for s in _spans:
		_bridge(root, s)


func _bridge(root: Node3D, s: Dictionary) -> void:
	var ri: int = s["road"]
	var pts: Array = MistvaleHeights.ROADS[ri][0]
	var halfw: float = MistvaleHeights.ROADS[ri][1]
	var deck_y: float = s["deck_y"]
	var a: float = s["start"]
	var b: float = s["end"]
	var node := Node3D.new()
	node.name = "Bridge_%02d" % ri
	root.add_child(node)

	# --- Deck ---------------------------------------------------------------
	# Segmented so it can follow the polylines of the approach road, and so the
	# planks read at a slight camber rather than as one slab.
	var segs := int((b - a) / 2.0) + 1
	var deck_w := halfw + 1.35
	for i in segs:
		var along := lerpf(a, b, float(i) / float(maxf(segs - 1, 1)))
		var c := MistvaleHeights.route_at(pts, along)
		var tan := MistvaleHeights.route_tangent(pts, along)
		var slab := BoxMesh.new()
		slab.size = Vector3(deck_w * 2.0, 0.34, 2.05)
		var mi := MeshInstance3D.new()
		mi.name = "Deck_%02d" % i
		mi.mesh = slab
		mi.material_override = _timber_material()
		mi.position = Vector3(c.x, _bridge_top(s, along) - 0.14, c.y)
		mi.basis = _bridge_basis(s, along, tan)
		# THE DECK DOES NOT CAST. It sits 7 cm under the road ribbon that is the
		# actual walking surface, which is inside the shadow map's depth
		# resolution at any usable bias: the deck was shadowing the road that
		# lies on it, and the whole bridge came back from review point R04 at
		# luminance 29 against 87 with shadows off. Ground-hugging sheets do not
		# cast — same rule as the terrain, the roads and the water. The posts
		# and piers still do; they are what make the bridge read as a bridge.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)

	# --- Parapets ----------------------------------------------------------
	var parapet_mat := StandardMaterial3D.new()
	parapet_mat.albedo_color = Color(0.29, 0.225, 0.165)
	parapet_mat.roughness = 0.9
	var parapet_surface := SurfaceTool.new()
	parapet_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var pl := PackedVector3Array()
		for i in segs:
			var along := lerpf(a, b, float(i) / float(maxf(segs - 1, 1)))
			var c := MistvaleHeights.route_at(pts, along)
			var tan := MistvaleHeights.route_tangent(pts, along)
			var nrm := Vector2(-tan.y, tan.x)
			pl.append(Vector3(
				c.x + nrm.x * (deck_w + 0.16),
				_bridge_top(s, along) + 0.52,
				c.y + nrm.y * (deck_w + 0.16)))
			pl.append(Vector3(
				c.x + nrm.x * (deck_w + 0.16),
				_bridge_top(s, along) - 0.30,
				c.y + nrm.y * (deck_w + 0.16)))
		# Posts alone read as loose stakes from the player camera. Two connected
		# rails make the crossing legible as a built bridge and keep the river view.
		var rail := _rail_gaps(pl)
		for i in rail.size():
			_bridge_box(parapet_surface, rail[i], Vector3(0.16, 1.06, 0.16), 0.0)
		for i in rail.size() - 1:
			var from := rail[i]
			var to := rail[i + 1]
			var delta := to - from
			var flat := Vector2(delta.x, delta.z)
			for height in [0.16, 0.43]:
				_bridge_box(parapet_surface,
					(from + to) * 0.5 + Vector3(0.0, height, 0.0),
					Vector3(0.15, 0.13, flat.length() + 0.04), atan2(flat.x, flat.y))
	parapet_surface.generate_normals()
	var parapet := MeshInstance3D.new()
	parapet.name = "TimberParapet"
	parapet.mesh = parapet_surface.commit()
	parapet.material_override = parapet_mat
	parapet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(parapet)

	# A continuous stone spandrel with an elliptical lower edge makes the
	# crossing read as one open arch instead of a row of square piers.
	var stone := ShaderMaterial.new()
	stone.shader = load(SHADER_BRIDGE_STONE) as Shader
	for side in [-1.0, 1.0]:
		var wall := MeshInstance3D.new()
		wall.name = "StoneArch_%d" % int(side)
		wall.mesh = _arch_wall_mesh(pts, s, side, deck_w, segs)
		wall.material_override = stone
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(wall)
		var joints := MeshInstance3D.new()
		joints.name = "ArchStoneJoints_%d" % int(side)
		joints.mesh = _arch_joints_mesh(pts, s, side, deck_w)
		var mortar := StandardMaterial3D.new()
		mortar.albedo_color = Color(0.34, 0.33, 0.31)
		mortar.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mortar.cull_mode = BaseMaterial3D.CULL_DISABLED
		joints.material_override = mortar
		joints.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(joints)
		var rim := MeshInstance3D.new()
		rim.name = "VoussoirRim_%d" % int(side)
		rim.mesh = _arch_ring_mesh(pts, s, side, deck_w)
		var rim_mat := StandardMaterial3D.new()
		rim_mat.albedo_color = Color(0.54, 0.53, 0.49)
		rim_mat.roughness = 0.94
		rim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		rim.material_override = rim_mat
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(rim)

	# Two masonry cutwaters carry the spandrel at the stations between the
	# three vaults. The older side wall tapered to a point at the waterline,
	# leaving the whole 51 m crossing looking like a thin suspended sheet.
	for station in [1, 2]:
		var along := lerpf(a, b, float(station) / 3.0)
		var c := MistvaleHeights.route_at(pts, along)
		var tan := MistvaleHeights.route_tangent(pts, along)
		var pier_bottom := MistvaleHeights.RIVER_Y - 1.25
		var pier_height := _bridge_top(s, along) - 0.35 - pier_bottom
		var pier_mesh := _bridge_cutwater_mesh(deck_w, pier_height)
		var pier := MeshInstance3D.new()
		pier.name = "Cutwater_%d" % station
		pier.mesh = pier_mesh
		pier.material_override = stone
		pier.position = Vector3(c.x, pier_bottom, c.y)
		pier.rotation.y = atan2(tan.x, tan.y)
		pier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(pier)
		var pier_body := StaticBody3D.new()
		pier_body.name = "CutwaterCollision_%d" % station
		pier_body.position = pier.position
		pier_body.rotation.y = pier.rotation.y
		var pier_shape := CollisionShape3D.new()
		pier_shape.shape = pier_mesh.create_convex_shape()
		pier_body.add_child(pier_shape)
		node.add_child(pier_body)

	# Collision: the deck has to be walkable, and the player must not be able to
	# fall through the gap between the two parapets.
	var body := StaticBody3D.new()
	body.name = "BridgeBody"
	for i in segs:
		var along := lerpf(a, b, float(i) / float(maxf(segs - 1, 1)))
		var c := MistvaleHeights.route_at(pts, along)
		var tan := MistvaleHeights.route_tangent(pts, along)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(deck_w * 2.0, 0.34, 2.15)
		cs.shape = box
		cs.position = Vector3(c.x, _bridge_top(s, along) - 0.14, c.y)
		cs.basis = _bridge_basis(s, along, tan)
		body.add_child(cs)
	node.add_child(body)


func _bridge_basis(s: Dictionary, along: float, tan: Vector2) -> Basis:
	var before := _bridge_top(s, along - 0.5)
	var after := _bridge_top(s, along + 0.5)
	var forward := Vector3(tan.x, after - before, tan.y).normalized()
	var right := Vector3(tan.y, 0.0, -tan.x).normalized()
	return Basis(right, forward.cross(right).normalized(), forward).orthonormalized()


func _bridge_cutwater_mesh(deck_w: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bottom := PackedVector3Array([
		Vector3(-deck_w + 0.35, 0.0, -0.96),
		Vector3(deck_w - 0.35, 0.0, -0.96),
		Vector3(deck_w + 0.72, 0.0, 0.0),
		Vector3(deck_w - 0.35, 0.0, 0.96),
		Vector3(-deck_w + 0.35, 0.0, 0.96),
		Vector3(-deck_w - 0.72, 0.0, 0.0),
	])
	var top := PackedVector3Array()
	for p in bottom:
		top.append(Vector3(p.x * 0.96, height, p.z * 0.78))
	for i in bottom.size():
		var next := (i + 1) % bottom.size()
		_bridge_quad(st, bottom[i], bottom[next], top[next], top[i])
	for i in range(1, bottom.size() - 1):
		for p in [top[0], top[i], top[i + 1]]:
			st.add_vertex(p)
	st.generate_normals()
	return st.commit()


func _arch_wall_mesh(pts: Array, s: Dictionary, side: float, deck_w: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a: float = s.start
	var b: float = s.end
	for i in segs - 1:
		var d0 := lerpf(a, b, float(i) / float(segs - 1))
		var d1 := lerpf(a, b, float(i + 1) / float(segs - 1))
		var p0 := _arch_section(pts, s, side, deck_w, d0)
		var p1 := _arch_section(pts, s, side, deck_w, d1)
		_bridge_quad(st, p0[0], p0[1], p1[1], p1[0]) # outside
		_bridge_quad(st, p0[2], p1[2], p1[3], p0[3]) # inside
		_bridge_quad(st, p0[1], p0[3], p1[3], p1[1]) # curved soffit
		_bridge_quad(st, p0[0], p1[0], p1[2], p0[2]) # under deck
	st.generate_normals()
	return st.commit()


func _arch_joints_mesh(pts: Array, s: Dictionary, side: float, deck_w: float) -> ArrayMesh:
	# One batched mesh, sparse vertical joints only on the solid spandrel.
	# They follow the curved lower edge and never put geometry across the opening.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a: float = s.start
	var b: float = s.end
	var count := int((b - a) / 2.3)
	for i in range(1, count):
		var d := lerpf(a, b, float(i) / float(count))
		var p0 := _arch_section(pts, s, side, deck_w, d - 0.055)
		var p1 := _arch_section(pts, s, side, deck_w, d + 0.055)
		var tan := MistvaleHeights.route_tangent(pts, d)
		var outward := Vector3(-tan.y, 0.0, tan.x) * side * 0.035
		_bridge_quad(st, p0[0] + outward, p0[1] + outward,
			p1[1] + outward, p1[0] + outward)
	st.generate_normals()
	return st.commit()


func _arch_ring_mesh(pts: Array, s: Dictionary, side: float, deck_w: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := int(float(s.span) / 0.7) + 1
	for i in count - 1:
		var d0 := lerpf(float(s.start), float(s.end), float(i) / float(count - 1))
		var d1 := lerpf(float(s.start), float(s.end), float(i + 1) / float(count - 1))
		var p0 := _arch_section(pts, s, side, deck_w, d0)
		var p1 := _arch_section(pts, s, side, deck_w, d1)
		var tan0 := MistvaleHeights.route_tangent(pts, d0)
		var tan1 := MistvaleHeights.route_tangent(pts, d1)
		var out0 := Vector3(-tan0.y, 0.0, tan0.x) * side * 0.075
		var out1 := Vector3(-tan1.y, 0.0, tan1.x) * side * 0.075
		_bridge_quad(st, p0[1] + out0, p1[1] + out1,
			p1[1] + out1 + Vector3.UP * 0.48, p0[1] + out0 + Vector3.UP * 0.48)
	st.generate_normals()
	return st.commit()


func _arch_section(pts: Array, s: Dictionary, side: float, deck_w: float, along: float) -> Array:
	var c := MistvaleHeights.route_at(pts, along)
	var tan := MistvaleHeights.route_tangent(pts, along)
	var nrm := Vector2(-tan.y, tan.x) * side
	var u := clampf((along - float(s.start)) / float(s.span), 0.0, 1.0)
	var top := _bridge_top(s, along) - 0.23
	# Three continuous open vaults create the bridge's long-range silhouette.
	# The support stations touch the waterline; each crest stays below the deck.
	var local_u := fposmod(u * 3.0, 1.0)
	if u >= 1.0:
		local_u = 1.0
	var vault := MistvaleHeights.RIVER_Y + 0.28 + 2.65 * sqrt(maxf(0.0,
		1.0 - pow(2.0 * local_u - 1.0, 2.0)))
	vault = minf(vault, top - 0.45)
	var outer := Vector2(c.x, c.y) + nrm * deck_w
	var inner := Vector2(c.x, c.y) + nrm * (deck_w - 0.78)
	return [Vector3(outer.x, top, outer.y), Vector3(outer.x, vault, outer.y),
		Vector3(inner.x, top, inner.y), Vector3(inner.x, vault, inner.y)]


func _bridge_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for p in [a, b, c, a, c, d]:
		st.add_vertex(p)


func _bridge_box(st: SurfaceTool, center: Vector3, size: Vector3, yaw: float) -> void:
	var half := size * 0.5
	var rotation := Basis(Vector3.UP, yaw)
	var corners := PackedVector3Array()
	for y in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			for x in [-1.0, 1.0]:
				corners.append(center + rotation * Vector3(x * half.x, y * half.y, z * half.z))
	for face in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1],
			[2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_bridge_quad(st, corners[face[0]], corners[face[1]],
			corners[face[2]], corners[face[3]])


## Turn a (top, bottom, top, bottom...) vertex run into a list of post positions.
func _rail_gaps(pl: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var i := 0
	while i < pl.size():
		out.append(pl[i].lerp(pl[i + 1], 0.5))
		i += 2
	return out


func _timber_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.542, 0.467, 0.389)
	m.roughness = 0.88
	return m


# =============================================================================
# Mesh finishing — shared normal accumulation
# =============================================================================

func _finish(
	verts: PackedVector3Array, cols: PackedColorArray,
	uvs: PackedVector2Array, idxs: PackedInt32Array
) -> ArrayMesh:
	var count := verts.size()
	var normals := PackedVector3Array()
	normals.resize(count)
	for i in count:
		normals[i] = Vector3.ZERO
	for i in range(0, idxs.size(), 3):
		var i0 := idxs[i]
		var i1 := idxs[i + 1]
		var i2 := idxs[i + 2]
		var n := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
		normals[i0] += n
		normals[i1] += n
		normals[i2] += n
	for i in count:
		var n := normals[i]
		normals[i] = n.normalized() if n.length_squared() > 1e-12 else Vector3.UP

	# --- the guard ---------------------------------------------------------
	# A flat horizontal sheet whose winding steps "along" before "across" gets
	# DOWNWARD normals, is lit from beneath, and renders black. Nothing about
	# the code looks wrong; the symptom appears only in a render, as a road that
	# looks like wet asphalt. So it is checked here, mechanically, on every
	# build: a horizontal surface's mean normal must have +Y.
	var up := 0.0
	for n2 in normals:
		up += n2.y
	up /= maxf(float(normals.size()), 1.0)
	if up < 0.3 and up > -0.3:
		pass    # not horizontal (a bank, a cut face) — nothing to say
	elif up < -0.3:
		push_error(("MistvaleLand: finished mesh has DOWNWARD normals (mean n.y = "
			+ "%.2f). A horizontal surface built with this winding order is lit "
			+ "from below and renders black. Check the index order.") % up)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
