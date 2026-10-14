extends "res://scripts/vfx/vfx_prototype.gd"
#
# 09 · 神罚雷 / DIVINE THUNDER CORRIDOR  ·  V2
#
# =============================================================================
# THE RULING THAT CHANGES EVERYTHING
# =============================================================================
#
#   THE CORRIDOR IS THE EFFECT. LIGHTNING IS ONLY THE CONFIRMATION.
#
# V1 built nine glowing lanes, a soft core and a lit disc on the ground — a bright
# shaft. It was the most conventional prototype in the set and it earned that: a
# bright column of light from the sky is standard thunder-magic grammar, and no
# amount of narrowing the lanes makes it stop being a beam.
#
# V2 inverts the construction. What arrives between the sky and the target is not
# light. It is EMPTINESS: the air inside a cylinder 15 m across is cleared — the
# haze, the dust, the motes, everything that made that volume visible — and what the
# audience sees is the shape of a thing that is no longer in the way.
#
# =============================================================================
# HOW YOU PHOTOGRAPH AN ABSENCE OF AIR
# =============================================================================
#
# You cannot, unless the air was visible to begin with. So the first job of this
# prototype is to PUT SOMETHING IN THE AIR: seven wide, faint horizontal haze strata
# hanging over the village between 7 m and 88 m. They are the medium. Without them
# the corridor would be a claim with no evidence, which is the failure mode this
# whole pass exists to fix.
#
# The strata are one shared shader and a `discard` in the fragment stage: any
# fragment of haze within `corridor_radius` of the corridor's axis is simply not
# drawn. As the radius opens from 0 to 7.4 m the village acquires a perfectly
# circular tunnel of clear air standing straight up out of it, with a soft lit rim
# exactly where the haze stops — and that rim is not decoration, it is the only
# evidence of where the haze used to be.
#
# =============================================================================
# THE STRIKE IS 1.5 PIXELS AND THAT IS THE POINT
# =============================================================================
#
# After the corridor has been open and silent for 0.65 s, one line appears between
# the sky and the target for 90 ms. It is 45 mm across, which at the corridor's own
# range is about 1.5 px: a hairline, not a beam, and it does not glow.
#
# The feedback is in the SURROUNDINGS. A fraction of a second later the buildings
# and the ground around the corridor erupt in short arcs — because the audience has
# to be told WHAT passed through, and the honest way to tell them is not to draw the
# thing bigger but to show everything near it recoiling.
#
# =============================================================================
# WHY THE SKY IS DUSK
# =============================================================================
#
# The corridor has to be punched through something with something to lose. A night
# sky turns a bright column into a picture of a torch; a day sky has no depth to
# lose. Dusk gives the haze a colour to be seen against and gives the hole in the
# sky a field of stars to show through.

const CORRIDOR_AT := Vector3(-3.0, 0.0, -33.0)
## The corridor's radius. 7.4 m is a 15 m tunnel: wider than any building in the
## village and narrower than the road is long, so it reads as a cut rather than as a
## scale.
const CORE_R := 7.4
## Where the haze hangs. Low enough to be in frame from an eye at 1.7 m looking up,
## high enough that the corridor's whole length is strata rather than ground.
const HAZE_HEIGHTS := [6.0, 10.0, 15.0, 21.0, 28.0, 36.0, 45.0, 55.0, 66.0, 78.0, 88.0]
const HAZE_SIZE := 520.0
const HAZE_ALPHA := 0.085
const SKY_Y := 620.0

const AIM_START := 0.60
const OPEN_START := 0.95
const OPEN_END := 2.30
const STRIKE_AT := 2.95
const STRIKE_LEN := 0.09
const ARC_END := 4.40
const HERO_END := 8.20
const FAR_START := 5.60
const CLOSE_START := 8.20
const CLOSE_END := 10.60

var haze_mat: ShaderMaterial
var strike: MeshInstance3D
var arcs: Array = []


func build() -> void:
	super()
	t_end = 11.4
	lab.set_sky("dusk")
	lab.sun.light_energy = 0.78

	_build_haze()
	_build_strike()
	_build_arcs()


## THE MEDIUM. Seven faint horizontal sheets, one shared material, nothing else.
##
## `depth_draw_never` because haze is not a surface and must never occlude; the
## falling-off alpha near each sheet's own edge is what keeps a 520 m rectangle from
## announcing itself as a rectangle on the horizon.
func _build_haze() -> void:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\n" \
		+ "render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;\n" \
		+ "uniform vec3 axis_xz = vec3(0.0);\n" \
		+ "uniform float corridor_radius = 0.0;\n" \
		+ "uniform float sheet_size = 520.0;\n" \
		+ "uniform vec3 haze_color : source_color = vec3(0.62, 0.68, 0.80);\n" \
		+ "uniform float haze_alpha = 0.085;\n" \
		+ "varying vec3 wpos;\n" \
		+ "void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }\n" \
		+ "void fragment() {\n" \
		+ "\tvec2 wp = wpos.xz - axis_xz.xz;\n" \
		+ "\tfloat d = length(wp);\n" \
		+ "\tif (corridor_radius > 0.01 && d < corridor_radius) { discard; }\n" \
		+ "\tfloat a = haze_alpha;\n" \
		+ "\t// A lit rim exactly where the haze stops: the only evidence of where it\n" \
		+ "\t// was. Gaussian, so it has no edge of its own to read as an outline.\n" \
		+ "\ta *= 1.0 + 0.34 * exp(-pow((d - corridor_radius) / 1.7, 2.0));\n" \
		+ "\ta *= 1.0 - smoothstep(sheet_size * 0.20, sheet_size * 0.46, d);\n" \
		+ "\tALBEDO = haze_color;\n" \
		+ "\tALPHA = a;\n" \
		+ "}\n"
	haze_mat = ShaderMaterial.new()
	haze_mat.shader = sh
	haze_mat.set_shader_parameter("axis_xz", CORRIDOR_AT)
	haze_mat.set_shader_parameter("sheet_size", HAZE_SIZE)
	haze_mat.set_shader_parameter("haze_alpha", HAZE_ALPHA)
	haze_mat.set_shader_parameter("corridor_radius", 0.0)

	for i in HAZE_HEIGHTS.size():
		var q := PlaneMesh.new()
		q.size = Vector2(HAZE_SIZE, HAZE_SIZE)
		var m := MeshInstance3D.new()
		m.name = "Haze%d" % i
		m.mesh = q
		m.material_override = haze_mat
		m.position = Vector3(CORRIDOR_AT.x, float(HAZE_HEIGHTS[i]), CORRIDOR_AT.z)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stage.add_child(m)


## THE STRIKE. One hairline box, sky to ground, white and unshaded. Its thickness is
## a constant and not a derived quantity, because "1-3 px" only has to be true at one
## distance, and the corridor's distance is fixed.
func _build_strike() -> void:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\n" \
		+ "render_mode unshaded, cull_disabled, fog_disabled;\n" \
		+ "void fragment() { ALBEDO = vec3(1.0); EMISSION = vec3(1.0); }\n"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var b := BoxMesh.new()
	b.size = Vector3(0.045, SKY_Y, 0.045)
	strike = MeshInstance3D.new()
	strike.name = "Strike"
	strike.mesh = b
	strike.material_override = mat
	strike.position = Vector3(CORRIDOR_AT.x, SKY_Y * 0.5, CORRIDOR_AT.z)
	strike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strike.visible = false
	stage.add_child(strike)


## THE SURROUNDINGS. Short arcs on the things near the corridor, each with its own
## delay, so what the audience sees after the strike is the NEIGHBOURHOOD reacting
## rather than the bolt being drawn thicker.
##
## Sources are the real props — buildings, crates, rocks within 46 m of the axis —
## and every delay, angle and length is a hash of the index. Deterministic
## throughout: the same frame in the still and in the take.
func _build_arcs() -> void:
	var sources: Array = []
	for e in lab.group("building") + lab.group("crate") + lab.group("rock"):
		var home: Vector3 = e["home_pos"]
		if Vector2(home.x - CORRIDOR_AT.x, home.z - CORRIDOR_AT.z).length() > 46.0:
			continue
		sources.append(home)
	if sources.is_empty():
		return
	var mat: ShaderMaterial = lab.glow_mat(Color(0.86, 0.92, 1.00), 3.4, 0.0, 0.0)
	for i in 18:
		var base: Vector3 = sources[i % sources.size()]
		var s := float(i)
		var ang := n1(s * 7.3, 0.0) * TAU
		var at := Vector3(
			base.x + cos(ang) * 4.0,
			lab.ground_height(base.x, base.z) + 1.2 + 7.0 * n1(s * 4.1, 0.0),
			base.z + sin(ang) * 4.0)
		# A thin box, so it has an edge-on face from any angle and cannot vanish.
		var b := BoxMesh.new()
		b.size = Vector3(0.075, 1.0, 0.075)
		var m := MeshInstance3D.new()
		m.mesh = b
		m.material_override = mat
		m.position = at
		m.rotation_degrees = Vector3(
			n_signed(s * 3.3, 0.0) * 34.0,
			n1(s * 1.9, 0.0) * 360.0,
			n_signed(s * 8.1, 0.0) * 34.0)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		stage.add_child(m)
		arcs.append({
			"node": m,
			"delay": 0.06 + 0.55 * n1(s * 9.4, 0.0),
			"len": 1.6 + 3.4 * n1(s * 5.7, 0.0),
		})


func apply(t: float) -> void:
	# ---- A · THE AIM ---------------------------------------------------------
	var aim := ease_in_out(span(t, AIM_START, OPEN_START))

	# ---- B · THE WORLD MAKES WAY --------------------------------------------
	# The corridor is not summoned, it is CLEARED. The radius opens with a slow
	# start, so the first thing the audience notices is that the air above the target
	# has gone thin — and only then that the thinness has a shape.
	var open := ease_in_out(span(t, OPEN_START, OPEN_END))
	var close := ease_in_out(span(t, CLOSE_START, CLOSE_END))
	var radius: float = CORE_R * open * (1.0 - close)
	haze_mat.set_shader_parameter("corridor_radius", radius)

	# ---- C · THE HAIRLINE ---------------------------------------------------
	var since := t - STRIKE_AT
	strike.visible = since >= 0.0 and since < STRIKE_LEN
	if strike.visible:
		# Full width for an instant and then a rapid narrowing: a line that has
		# already passed, not a beam being held.
		var k := 1.0 - clampf(since / STRIKE_LEN, 0.0, 1.0)
		strike.scale = Vector3(1.0 + 3.2 * k, 1.0, 1.0 + 3.2 * k)

	# ---- D · THE NEIGHBOURHOOD ANSWERS --------------------------------------
	for a in arcs:
		var node: MeshInstance3D = a["node"]
		var delay: float = a["delay"]
		var u := span(t, STRIKE_AT + delay, STRIKE_AT + delay + 0.62)
		# An arc is a spike: instant, then gone. `pulse` is exactly that shape.
		var k := pulse(u, 0.0, 1.0)
		node.visible = k > 0.02
		if node.visible:
			node.scale = Vector3(1.0, float(a["len"]) * k, 1.0)

	# ---- the sky's half, reconciled from the lens ---------------------------
	# The corridor is a vertical cylinder and the sky is at infinity, so the hole it
	# makes in the sky is a circle whose radius is the angle the cylinder subtends
	# from the camera — aimed at the point where the axis meets the sky.
	if radius > 0.05:
		var eye: Vector3 = lab.cam_eye
		var axis_dist := Vector2(CORRIDOR_AT.x - eye.x, CORRIDOR_AT.z - eye.z).length()
		var upward := Vector3(CORRIDOR_AT.x, SKY_Y, CORRIDOR_AT.z) - eye
		lab.sky_material().set_shader_parameter("void_direction", upward.normalized())
		lab.sky_material().set_shader_parameter(
			"void_cos", cos(atan(radius / maxf(axis_dist, 0.001))))
	else:
		lab.sky_material().set_shader_parameter("void_cos", -1.0)

	lab.weapon_root.visible = t < OPEN_END + 1.2 or t > CLOSE_START
	_camera(t)
	_weapon(t, aim)


## =============================================================================
## THE CAMERA · AND WHY IT IS MOSTLY POINTED UP
## =============================================================================
##
## A corridor running from the sky to the ground can only be seen along its own
## length, and looking up that length is also the only frame in which the sky's hole
## and the ground's circle are the same shape. So the first-person beats are a neck
## craned back and the corridor is the picture.
##
## The far beat inside the hold exists for the one thing the up-shot cannot say: the
## SHAPE of the cleared volume, which only reads from far enough away for the haze
## strata to be seen as strata rather than as a field.
func _camera(t: float) -> void:
	lab.review_off()

	if t < CLOSE_START:
		var climb := ease_in_out(span(t, AIM_START, FAR_START))
		var far := ease_in_out(span(t, FAR_START, HERO_END))
		var eye := Vector3(0.30, lab.ground_height(0.30, 0.0) + 1.74, -2.0)
		eye = eye.lerp(Vector3(-40.0, 25.0, 28.0), far)
		camera(eye, Vector3(CORRIDOR_AT.x, lerpf(15.0, 52.0, climb), CORRIDOR_AT.z),
			lerpf(70.0, 56.0, far), sin(t * 0.29) * 0.007)
		return

	# THE CLOSE. Back to the player's own scale, because the last thing the clip says
	# is not about the sky: it is a road, with a circle of clear air standing on it
	# that was not there before.
	var back := ease_in_out(span(t, CLOSE_START, t_end - 0.60))
	var eye2 := Vector3(-40.0, 25.0, 28.0).lerp(
		Vector3(0.30, lab.ground_height(0.30, 0.0) + 1.74, -2.0), back)
	camera(eye2, Vector3(CORRIDOR_AT.x, lerpf(52.0, 12.0, back), CORRIDOR_AT.z),
		lerpf(56.0, 66.0, back), 0.0)


## The blade comes up and points at the sky — the aim is the cause, and it is the
## only thing in the clip the player does.
func _weapon(t: float, aim: float) -> void:
	lab.weapon_blend(Vector3(0.50, -0.30, -0.80), Vector3(-62.0, -18.0, 8.0), 0.94, aim)


func phase_name(t: float) -> String:
	if t < OPEN_START:
		return "起手 · 刀指向天空"
	if t < OPEN_END:
		return "空气被清空 %.0f%%" % (100.0 * span(t, OPEN_START, OPEN_END))
	if t < STRIKE_AT:
		return "走廊打开 · 一片寂静"
	if t < ARC_END:
		return "一条白线过去了 · 周围在炸"
	if t < CLOSE_START:
		return "走廊还在"
	if t < CLOSE_END:
		return "走廊在闭合"
	return "地上留着一个圆圈"
