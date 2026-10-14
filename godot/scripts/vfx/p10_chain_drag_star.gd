extends "res://scripts/vfx/vfx_prototype.gd"
#
# 10 · 锁链拖星 / CHAIN DRAG STAR  ·  V2
#
# =============================================================================
# WHAT V1 GOT WRONG
# =============================================================================
#
# V1 was a big body sliding down the sky with a chain drawn between it and the
# player. Every frame was beautiful and the sentence was wrong: nothing about it
# said the CHAIN had done it. A star descending on its own and a chain that happens
# to be attached to it are indistinguishable if the chain never does anything the
# star does not immediately copy.
#
# The brief's sentence is: "他用链子真的把月亮拽下来了". The load-bearing word is 拽.
#
# =============================================================================
# V2: SIX BEATS THAT EACH PROVE SOMETHING
# =============================================================================
#
#   A · THROW     the chain is thrown, extends, thins, and is GONE into the sky.
#                 Its length is finite and honest — 74 m — so "gone into the sky"
#                 is a statement about distance, not a fade.
#   B · NOTHING   0.8 s in which nothing whatsoever moves. The audience has to be
#                 allowed to ask "did it catch anything?" and the only way to ask
#                 it is to be given the time.
#   C · TAUT      the slack goes to zero, every link near the hand snaps onto one
#                 line, and the handle is yanked up. THIS HAPPENS BEFORE THE STAR
#                 MOVES. If the star moved first the chain would be a decoration
#                 again.
#   D · SKY       the star field itself starts to drift — the player is pulling the
#                 sky, and the sky is the first thing that admits it.
#   E · DRAG      three hard pulls. Each one: pull, tension, DELAY, then the body
#                 moves. The delay is the mass. A body that moves when the hand
#                 moves weighs nothing.
#   F · RELEASE   the hand opens. The chain goes slack, the body accelerates back
#                 the way it came, and the DAMAGE is the recoil.
#
# =============================================================================
# WHY THE DAMAGE IS THE RECOIL AND NOT THE STAR
# =============================================================================
#
#   PLAYER DOES NOT HIT WITH THE MOON. PLAYER HITS WITH THE REACTION FORCE OF
#   MOVING IT.
#
# A star dropped on a village is a meteor; the chain would not have been necessary.
# What the chain actually did was accelerate something enormous, and an acceleration
# has a recoil — a line of pressure along the chain's own axis, through the target,
# arriving at the moment the load is let go. That is what this clip hits with, and
# it is why the star leaves instead of landing.
#
# =============================================================================
# WHY THE CHAIN'S LENGTH DOES NOT CHANGE
# =============================================================================
#
# The chain is 74 m long at every instant. When the anchor is further away than
# that, the chain is straight and ends in mid-air — which is what "it went into the
# sky and I cannot see the end of it" looks like when it is true. As the body is
# dragged down the same 74 m reaches further and further up the line, so the chain
# VISIBLY BECOMES LONG ENOUGH to touch it, and that moment is beat E's proof.
#
# =============================================================================
# WHY THE STAR FIELD SPINS BUT THE HORIZON DOES NOT
# =============================================================================
#
# `sky_spin` yaws the star field and nothing else. The zenith-to-horizon gradient in
# the dome is a function of ELEVATION, and rotating it about any axis other than the
# zenith would tip the sky's horizon — which is a statement about the world tilting
# (that is 05) and not about the sky sliding.

const STAR_HOME := Vector3(-118.0, 210.0, -430.0)
## Where the pull ends: high over the village and far enough out that a 28 m body
## clears the rooftops. Its RADIUS is derived from the distance it has travelled, so
## the body is one object getting closer rather than a body being resized — which
## is the whole reason its angular size is a fair measure of how far the pull got.
const STAR_HERO := Vector3(-10.0, 30.0, -46.0)
const STAR_R_HOME := 1.6

## The chain's real length. Not a max radius — a length. See the header.
const CHAIN_LEN := 74.0
const LINKS := 120
## The hand, in the EYE'S frame (see `eye_point`): right, down, forward. Low and
## close to the corner, so a 10 cm marker reads as a fist and not as a crate.
const HAND := Vector3(0.30, -0.44, -0.62)
const HAND_TAUT := Vector3(0.34, -0.30, -0.62)

const THROW_START := 0.55
const THROW_END := 1.30
const NOTHING_END := 2.10
const TAUT_END := 2.45
const SKY_START := 2.55
const SKY_END := 3.35
## The three pulls. Each is (the hands move at `at`, the body starts moving at
## `at + LAG`, and the body finishes at `at + LAG + MOVE`).
const PULL_AT := [3.40, 4.35, 5.30]
const PULL_LAG := 0.30
const PULL_MOVE := 0.55
const STAR_SETTLED := 6.15
const HERO_END := 7.95
const RELEASE_START := 7.95
const RELEASE_END := 8.20
const RECOIL_AT := 8.20
const RECOIL_END := 8.75
const RETURN_START := 8.45
const RETURN_END := 10.30
const SCAR_GROW_END := 3.20

var star: MeshInstance3D
var anchor: Node3D
var chain_mm: MultiMeshInstance3D
var chain_mm2: MultiMeshInstance3D
var recoil: MeshInstance3D
var star_pos := STAR_HOME
var star_r := STAR_R_HOME
var fist: MeshInstance3D


func build() -> void:
	super()
	t_end = 11.0
	lab.set_sky("night")
	lab.sun.light_energy = 0.36
	lab.player_proxy.visible = false
	# A bright small body and a dense field, so the sky has something to lose and
	# something to measure a rotation against. The painted body starts OFF: the real
	# star is standing exactly where it would be, so switching it off at t = 0 is the
	# invisible handoff 07 also does.
	lab.sky_material().set_shader_parameter("star_amount", 0.92)
	lab.sky_material().set_shader_parameter("star_density", 58.0)
	lab.sky_material().set_shader_parameter("body_amount", 0.0)
	lab.env.glow_enabled = true
	lab.env.glow_intensity = 0.70
	lab.env.glow_hdr_threshold = 0.90

	var sh := Shader.new()
	sh.code = "shader_type spatial;\n" \
		+ "render_mode unshaded, fog_disabled;\n" \
		+ "uniform vec3 core : source_color = vec3(0.94, 0.97, 1.0);\n" \
		+ "void fragment() {\n" \
		+ "\tALBEDO = core * 2.8;\n" \
		+ "\tEMISSION = core * 2.8;\n" \
		+ "}\n"
	var star_mat := ShaderMaterial.new()
	star_mat.shader = sh
	star = MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	sp.radial_segments = 24
	sp.rings = 12
	star.mesh = sp
	star.material_override = star_mat
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star.position = STAR_HOME
	stage.add_child(star)

	# ---- THE ANCHOR ----------------------------------------------------------
	# What the chain is caught on. Three prongs on the body's surface, aimed back
	# down the chain — the visual answer to "is the chain actually attached to that
	# thing", which the brief makes an explicit fail condition.
	anchor = Node3D.new()
	stage.add_child(anchor)
	var hook := world_mat(Color(0.430, 0.450, 0.490), 0.40, 0.45)
	for i in 3:
		var prong := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.09, 1.5, 0.09)
		prong.mesh = pm
		prong.material_override = hook
		prong.position = Vector3(cos(float(i) * TAU / 3.0) * 0.34, -0.72,
			sin(float(i) * TAU / 3.0) * 0.34)
		prong.rotation_degrees = Vector3(
			14.0 * sin(float(i) * TAU / 3.0), 0.0,
			-14.0 * cos(float(i) * TAU / 3.0))
		prong.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		anchor.add_child(prong)

	# ---- THE CHAIN -----------------------------------------------------------
	chain_mm = _link_multimesh(true)
	chain_mm2 = _link_multimesh(false)

	# ---- THE RECOIL LINE -----------------------------------------------------
	# A long thin box on the chain's axis, hidden until the hand opens. Not a beam:
	# it is a line of pressure, and the only thing it does is grow through the
	# target at the speed the recoil would travel.
	var rsh := Shader.new()
	rsh.code = "shader_type spatial;\n" \
		+ "render_mode unshaded, cull_disabled, fog_disabled;\n" \
		+ "uniform float heat = 1.0;\n" \
		+ "void fragment() {\n" \
		+ "\tALBEDO = vec3(0.86, 0.90, 0.98) * heat * 1.6;\n" \
		+ "\tEMISSION = vec3(0.86, 0.90, 0.98) * heat * 1.6;\n" \
		+ "}\n"
	var rmat := ShaderMaterial.new()
	rmat.shader = rsh
	recoil = MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(0.16, 0.16, 1.0)
	recoil.mesh = rb
	recoil.material_override = rmat
	recoil.visible = false
	recoil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(recoil)

	# The player's fist, as a greybox marker, because a chain that starts in mid-air
	# starts nowhere.
	fist = MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.105, 0.105, 0.105)
	fist.mesh = fb
	fist.material_override = world_mat(Color(0.360, 0.345, 0.375), 0.95)
	fist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fist.position = HAND
	lab.fp_camera.add_child(fist)


func _link_multimesh(flat: bool) -> MultiMeshInstance3D:
	var mm := MultiMeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.12
	tor.outer_radius = 0.24
	tor.rings = 8
	tor.ring_segments = 5
	if flat:
		tor.outer_radius = 0.28
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.mesh = tor
	m.instance_count = LINKS
	mm.multimesh = m
	tor.surface_set_material(0, world_mat(Color(0.335, 0.345, 0.375), 0.46, 0.42))
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(mm)
	return mm


## How far the pull has actually got, in 0..1 — and the three lags are the whole
## reason this is a function rather than a lerp. Each pull contributes a third, and
## each third starts MOVING `PULL_LAG` after the hand did.
func _drag(t: float) -> float:
	var moved := 0.0
	for i in PULL_AT.size():
		var at := float(PULL_AT[i])
		moved += ease_out_cubic(span(t, at + PULL_LAG, at + PULL_LAG + PULL_MOVE)) \
			/ float(PULL_AT.size())
	return moved


## How far the chain has been thrown out, in metres. The chain's total length never
## changes; what changes is how much of it has left the hand.
func _thrown(t: float) -> float:
	return CHAIN_LEN * ease_out_cubic(span(t, THROW_START, THROW_END))


func apply(t: float) -> void:
	var drag := _drag(t)
	var back := ease_in_out(span(t, RETURN_START, RETURN_END))
	var out := drag * (1.0 - back)
	star_pos = STAR_HOME.lerp(STAR_HERO, out)
	# THE BODY IS ONE OBJECT GETTING CLOSER, so its radius follows its distance and
	# its angular size is a fair measure of the pull. A body that is merely resized
	# lies about how far it has come, which is the one thing this clip is about.
	var d0 := STAR_HOME.length()
	var d := maxf(star_pos.length(), 1.0)
	star_r = STAR_R_HOME * (d0 / d)
	star.position = star_pos
	star.scale = Vector3.ONE * star_r

	# ---- D · THE SKY ADMITS IT FIRST ----------------------------------------
	# Before the body moves at all, the star field drifts. The player is pulling the
	# SKY, and the sky is the first thing that admits it — a small rotation over
	# 0.8 s, which in a field of 58 stars per unit is unmistakable and which nothing
	# else in the frame can explain.
	var sky_aware := ease_in_out(span(t, SKY_START, SKY_END))
	lab.sky_material().set_shader_parameter("sky_spin", -0.30 * sky_aware * (1.0 - back))
	lab.sky_material().set_shader_parameter("star_amount", lerpf(0.92, 0.86, sky_aware))

	# ---- THE SCAR ------------------------------------------------------------
	# A small black cone where the star was taken from: not a ring, not a lens, a
	# HOLE, with a hairline torn edge so that an absence in a near-black sky has a
	# shape at all. Driven by `drag` and not by `out`: once the chain has pulled, the
	# sky is torn for the rest of the take, and "the star went home and the hole
	# stayed" is the sentence this clip exists to say.
	var scar := clampf(ease_in_out(span(t, SKY_START, SCAR_GROW_END)), 0.0, 1.0)
	if scar > 0.01:
		var eye: Vector3 = lab.cam_eye
		lab.sky_material().set_shader_parameter(
			"void_direction", (STAR_HOME - eye).normalized())
		lab.sky_material().set_shader_parameter("void_cos", cos(0.055 * scar + 0.006))
		lab.sky_material().set_shader_parameter("void_rim", 1.6 * scar)
	else:
		lab.sky_material().set_shader_parameter("void_cos", -1.0)
		lab.sky_material().set_shader_parameter("void_rim", 0.0)

	# ---- C · TAUT ------------------------------------------------------------
	# The handle is yanked up and the chain loses all of its sag. Both are functions
	# of the same number, so the hand and the chain cannot disagree about whether the
	# thing on the other end has weight.
	var taut := ease_out_cubic(span(t, NOTHING_END, TAUT_END))

	_place_chain(t, taut, out, back)

	# ---- F · THE RECOIL ------------------------------------------------------
	# The damage. A line of pressure along the chain's own axis, travelling out
	# through the target at the instant the load is released — because what the
	# player did was accelerate something enormous, and an acceleration has a recoil.
	var recoil_u := span(t, RECOIL_AT, RECOIL_END)
	recoil.visible = recoil_u > 0.001 and recoil_u < 0.999
	if recoil.visible:
		var head: Vector3 = lab.fp_camera.global_transform * HAND
		var dir := (star_pos - head).normalized()
		var reach := 4.0 + 46.0 * ease_out_cubic(recoil_u)
		var mat := recoil.material_override as ShaderMaterial
		mat.set_shader_parameter("heat", 1.0 - recoil_u)
		recoil.position = head + dir * (reach + 26.0) * 0.5
		recoil.look_at(head + dir * (reach + 27.0), Vector3.UP)
		recoil.scale = Vector3(1.0, 1.0, reach)
	# The target is removed by the recoil, and by nothing else. No explosion, no
	# scorch: the thing that was in the way is simply not there afterwards.
	lab.target.visible = t < RECOIL_AT or t > RECOIL_END + 0.9

	lab.weapon_root.visible = false
	_camera(t, out, taut)
	_weapon(t)


## =============================================================================
## THE CHAIN
## =============================================================================
##
## Straight while the anchor is further off than the chain is long; a sagged curve
## once the same 74 m can reach it. The transition is not animated — it is what the
## geometry does, and it happens at the moment the chain becomes long enough, which
## is the beat the brief calls VISIBLE CONNECTION.
func _place_chain(t: float, taut: float, out: float, back: float) -> void:
	var hand_local := HAND.lerp(HAND_TAUT, taut)
	fist.position = hand_local
	var head: Vector3 = lab.fp_camera.global_transform * hand_local
	var to_star := star_pos - head
	var dist := to_star.length()
	var dir := to_star / maxf(dist, 0.001)
	# The surface point of the body that faces the player: the chain is attached to
	# the body, not to its centre.
	var surface := star_pos - dir * star_r
	# Reachable length of the chain right now: never more than it is long, and never
	# more than has been thrown out.
	var thrown := _thrown(t)
	var span := minf(dist, CHAIN_LEN)
	if t < THROW_END:
		span = minf(span, thrown)
	var slack := maxf(CHAIN_LEN - span, 0.0)
	# Sag from the slack, and killed by `taut` — a chain under impossible load is a
	# straight line, and the straightness is the visual proof of the load.
	var sag := minf(slack * 0.34, 6.0) * (1.0 - taut)

	var tail: Vector3 = (surface if span >= dist - 0.05 else head + dir * span)
	anchor.visible = span >= dist - 0.05
	if anchor.visible:
		anchor.position = surface
		# The prongs face back down the chain, because they are what the chain is
		# caught on and a hook that faces the wrong way is a decoration.
		anchor.look_at(head, Vector3.UP)

	var a := chain_mm.multimesh
	var b := chain_mm2.multimesh
	var pitch := CHAIN_LEN / float(LINKS - 1)
	var prev := head
	for i in LINKS:
		var along := float(i) * pitch
		var u := clampf(along / maxf(span, 0.001), 0.0, 1.0)
		var p := head.lerp(tail, u) + Vector3.DOWN * (sag * 4.0 * u * (1.0 - u))
		# THE TAPER IS THE THINNING. A chain 74 m long seen from a hand is four links
		# across at the far end, so it does not fade out — it genuinely runs out of
		# resolution, and the last links shrink to nothing rather than being hidden.
		var fade := 1.0
		if along > span - 10.0:
			fade = clampf((span - along) / 10.0, 0.0, 1.0)
		var tangent := (p - prev)
		if tangent.length() < 0.0001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		var basis := Basis(Quaternion(Vector3.UP, tangent))
		if i % 2 == 0:
			basis = basis.rotated(tangent, PI * 0.5)
		# ONE METRE OF CHAIN IS ONE METRE AT EVERY DISTANCE — a real link's scale,
		# not a function of the span, so the chain does not change size when the pull
		# changes and the sag is the only thing that moves.
		var xf := Transform3D(basis.scaled(Vector3.ONE * fade), p)
		if i % 2 == 0:
			a.set_instance_transform(i, xf)
			b.set_instance_transform(i, Transform3D())
		else:
			b.set_instance_transform(i, xf)
			a.set_instance_transform(i, Transform3D())
		prev = p


func _camera(t: float, out: float, taut: float) -> void:
	var eye := Vector3(0.40, lab.ground_height(0.40, 0.0) + 1.76, 0.0)

	if t < RELEASE_START:
		# FIRST PERSON, LOOKING UP THE CHAIN, ALL THE WAY THROUGH. The chain leaves
		# the bottom of the frame from the player's own hand, so the line from the
		# hand to the body IS the composition — and in the hold the body is 41 % of
		# the frame with the anchor prongs visible at the far end of that line.
		lab.review_off()
		var up := ease_in_out(span(t, THROW_START, SKY_END))
		# The aim climbs with the chain and then comes back down with the body: the
		# subject moves from the sky to something at the end of a rope.
		var aim := star_pos.lerp(star_pos.lerp(Vector3.ZERO, 0.35), 0.0)
		aim = aim if out < 0.02 else star_pos.lerp(
			head_or(eye, Vector3.ZERO), 0.0)
		var look := Vector3(
			lerpf(star_pos.x, star_pos.x * 0.4, 0.0),
			lerpf(lerpf(120.0, star_pos.y, up), star_pos.y, out),
			lerpf(star_pos.z, star_pos.z * 0.6, 0.0))
		# A slight jolt on `taut`: the handle being yanked up.
		camera(eye, look, lerpf(72.0, 66.0, out),
			-0.030 * taut + sin(t * 0.27) * 0.010)
		return

	# THE ONE EXTERNAL, AND IT IS THERE FOR THE RECOIL. A line of pressure along the
	# chain's axis cannot be seen from somewhere on that axis; it needs a camera off
	# to one side, looking across it, with the village behind so the audience can see
	# what the line passed through.
	lab.review_off()
	var u := ease_in_out(span(t, RELEASE_START, RETURN_START))
	camera(Vector3(30.0, 15.0, 34.0).lerp(Vector3(38.0, 21.0, 44.0), u),
		Vector3(-2.0, 9.0, -26.0), lerpf(62.0, 56.0, u), 0.0)


func head_or(eye: Vector3, fallback: Vector3) -> Vector3:
	if lab.fp_camera == null:
		return fallback
	return lab.fp_camera.global_transform * HAND


func _weapon(t: float) -> void:
	# The player's other hand is empty by design: this clip is about the chain, and a
	# blade in frame would compete with it for the word "weapon".
	pass


func phase_name(t: float) -> String:
	if t < THROW_START:
		return "起手 · 手里有一条链"
	if t < THROW_END:
		return "甩出去"
	if t < NOTHING_END:
		return "……勾到什么了吗"
	if t < TAUT_END:
		return "链子突然绷直"
	if t < SKY_END:
		return "天在动"
	if t < STAR_SETTLED:
		return "一下 · 一下 · 一下"
	if t < RELEASE_START:
		return "星星就在头顶 · 链子连着它"
	if t < RECOIL_END:
		return "松手 · 反作用力穿过村子"
	if t < RETURN_END:
		return "星弹回天上"
	return "星星回去了 · 洞还在"
