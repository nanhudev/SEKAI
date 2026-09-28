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

const WATER_HALF := 14.6
const WATER_STEP := 4.0
const SHADER_WATER := "res://resources/shaders/mistvale_water.gdshader"
const SHADER_ROAD := "res://resources/shaders/mistvale_road.gdshader"

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
					best = maxf(best, lerpf(best, float(s["deck_y"]) + LIFT, w))
			d += 1.5
	return best


## Road height at a point that is `along` metres down road `ri`.
## Ground, unless a bridge span is carrying it.
func _road_y(x: float, z: float, ri: int, along: float) -> float:
	var base := MistvaleHeights.height_at(x, z) + LIFT
	for s in _spans:
		if s.road != ri:
			continue
		var w := _span_weight(along, s.start, s.end)
		if w > 0.0:
			base = lerpf(base, s.deck_y + LIFT, w)
	return base


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
		mi.material_override = _road_material()
		# A road surface is a decal lying 10 cm above the ground. If it casts,
		# it shadows itself: the whole street came back as a black wedge under a
		# dense moire, which is the single most alarming thing this pass
		# produced and took three bisect renders to attribute. Ground-hugging
		# sheets do not cast.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


func _road_material() -> Material:
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
		var yaw := atan2(tan.x, tan.y)
		var slab := BoxMesh.new()
		slab.size = Vector3(deck_w * 2.0, 0.34, 2.05)
		var mi := MeshInstance3D.new()
		mi.name = "Deck_%02d" % i
		mi.mesh = slab
		mi.material_override = _timber_material()
		mi.position = Vector3(c.x, deck_y - 0.14, c.y)
		mi.rotation.y = -yaw
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
	for side in [-1.0, 1.0]:
		var pl := PackedVector3Array()
		for i in segs:
			var along := lerpf(a, b, float(i) / float(maxf(segs - 1, 1)))
			var c := MistvaleHeights.route_at(pts, along)
			var tan := MistvaleHeights.route_tangent(pts, along)
			var nrm := Vector2(-tan.y, tan.x)
			pl.append(Vector3(
				c.x + nrm.x * (deck_w + 0.16),
				deck_y + 0.52,
				c.y + nrm.y * (deck_w + 0.16)))
			pl.append(Vector3(
				c.x + nrm.x * (deck_w + 0.16),
				deck_y - 0.30,
				c.y + nrm.y * (deck_w + 0.16)))
		# A run of posts is cheaper and reads better at distance than a wall.
		var rail := _rail_gaps(pl)
		for i in rail.size():
			var mi := MeshInstance3D.new()
			var post := BoxMesh.new()
			post.size = Vector3(0.16, 1.06, 0.16)
			mi.mesh = post
			mi.material_override = _timber_material()
			mi.position = rail[i]
			node.add_child(mi)

	# --- Piers -------------------------------------------------------------
	# Down to the actual bed, sampled from the field, so a pier is never floating.
	var pier_count := maxi(2, int((b - a) / 11.0))
	for i in pier_count:
		var along := lerpf(a + 1.5, b - 1.5, float(i) / float(maxf(pier_count - 1, 1)))
		var c := MistvaleHeights.route_at(pts, along)
		var bed := MistvaleHeights.height_at(c.x, c.y)
		var h := maxf(deck_y - 0.30 - bed, 0.5)
		var pier := BoxMesh.new()
		pier.size = Vector3(1.05, h, 1.05)
		var mi := MeshInstance3D.new()
		mi.name = "Pier_%02d" % i
		mi.mesh = pier
		mi.material_override = _stone_material()
		mi.position = Vector3(c.x, bed + h * 0.5, c.y)
		node.add_child(mi)

	# Collision: the deck has to be walkable, and the player must not be able to
	# fall through the gap between the two parapets.
	var body := StaticBody3D.new()
	body.name = "BridgeBody"
	for i in segs:
		var along := lerpf(a, b, float(i) / float(maxf(segs - 1, 1)))
		var c := MistvaleHeights.route_at(pts, along)
		var tan := MistvaleHeights.route_tangent(pts, along)
		var yaw := atan2(tan.x, tan.y)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(deck_w * 2.0, 0.34, 2.15)
		cs.shape = box
		cs.position = Vector3(c.x, deck_y - 0.14, c.y)
		cs.rotation.y = -yaw
		body.add_child(cs)
	node.add_child(body)


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
