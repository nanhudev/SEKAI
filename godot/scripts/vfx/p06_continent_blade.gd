extends "res://scripts/vfx/vfx_prototype.gd"
#
# 06 · 地脉拔刀 / CONTINENT BLADE
#
# =============================================================================
# THE CLAIM
# =============================================================================
#
# The blade is swung, and the world is CUT. Not hit, not cracked — cut, the way a
# blade cuts: a single straight line, clean through the road, through the ground
# under it and through the buildings standing beside it, at every height, all at
# once. And then the cut OPENS, and there is a canyon where a street was.
#
# The rule being rewritten is that a cut can only be as big as the blade. This cut
# is the length of the world and its depth is whatever is underneath.
#
# =============================================================================
# WHY THIS NEEDS ITS OWN PRIMITIVE
# =============================================================================
#
# `carve` is a sphere. A sphere placed anywhere at any radius is a BITE — a bowl, a
# crater, a mouth — and no arrangement of spheres produces a straight line with two
# parallel edges. 06 is the only prototype in this round whose claim is directional,
# so `vfx_prop.gdshader` grew a `rift`: a point, a horizontal normal, and a half
# width, and every fragment within that half width is removed AT ANY HEIGHT. That
# last clause is the whole thing. A trench cut into the ground would be a trench; a
# cut through a building and the ground it stands on and the sky above it is a cut.
#
# =============================================================================
# WHY THERE ARE WALLS INSIDE IT
# =============================================================================
#
# A `discard` has no inside. Remove a slab of the world and you do not get a canyon,
# you get a stripe of background seen through a hole — which is legible as "a slit"
# and not as "a depth". So the prototype builds the canyon's own walls: two tall
# slabs standing in the gap, moving apart as the rift widens, and a floor far below
# with the ley light coming up off it. The rift makes the hole; the walls make the
# hole BELIEVABLE.

## The cut runs along the road: the rift's plane is x = 0, so its normal is X.
const RIFT_Z_SPAN := 620.0
## 30 m, not 46. A `discard` shows nothing on its own, so the ONLY thing that makes
## the cut read as a canyon rather than as a black stripe on the road is being able
## to see the floor and the far wall inside it. At 46 m the floor sat 42 m below a
## 1.8 m eye 31 m away — an angle of ~54°, outside a 66° lens's 48° lower edge — so
## the interior was below the frame and the canyon came back as a painted band. At
## 30 m the floor is inside the picture and the depth can be read.
const RIFT_DEPTH := 30.0
const RIFT_HALF_MAX := 5.6

const OPEN_START := 1.85
const OPEN_END := 6.30
const HERO_WIDE_END := 7.60
const CLOSE_START := 8.70
const CLOSE_END := 11.00

var wall_l: MeshInstance3D
var wall_r: MeshInstance3D
var floor_mesh: MeshInstance3D
var veins: Array = []
var half := 0.0


func build() -> void:
	super()
	t_end = 12.0
	lab.set_sky("dusk")
	lab.sun.light_energy = 0.80
	lab.player_proxy.visible = false

	var rock := world_mat(Color(0.135, 0.126, 0.112), 1.0)
	# THE WALLS. Slightly wider than the rift so no sliver of background shows along
	# their tops, and deep enough that the floor is out of the fog's reach.
	for s in [-1.0, 1.0]:
		var box := BoxMesh.new()
		box.size = Vector3(0.6, RIFT_DEPTH, RIFT_Z_SPAN)
		var w := MeshInstance3D.new()
		w.mesh = box
		w.material_override = rock
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.position = Vector3(0.0, -RIFT_DEPTH * 0.5 + 1.2, -40.0)
		stage.add_child(w)
		if s < 0.0:
			wall_l = w
		else:
			wall_r = w

	var fb := BoxMesh.new()
	fb.size = Vector3(RIFT_HALF_MAX * 4.0, 0.5, RIFT_Z_SPAN)
	floor_mesh = MeshInstance3D.new()
	floor_mesh.mesh = fb
	floor_mesh.material_override = world_mat(Color(0.215, 0.180, 0.120), 1.0)
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floor_mesh.position = Vector3(0.0, -RIFT_DEPTH + 1.0, -40.0)
	stage.add_child(floor_mesh)

	# THE LEY. Filaments rising out of the cut, at fixed intervals along it, so the
	# gap is lit from inside and the eye can measure how deep it goes.
	for i in 26:
		var z := 90.0 - float(i) * 24.0
		var m: ShaderMaterial = lab.glow_mat(Color(1.00, 0.72, 0.34), 1.5, 0.0, 0.0)
		m.set_shader_parameter("alpha", 0.0)
		var bb := BoxMesh.new()
		bb.size = Vector3(0.16, RIFT_DEPTH * 0.8, 0.16)
		var n := MeshInstance3D.new()
		n.mesh = bb
		n.material_override = m
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.position = Vector3(0.0, -RIFT_DEPTH * 0.42, z)
		stage.add_child(n)
		veins.append({"node": n, "mat": m, "z": z, "seed": float(i) * 1.7})


func apply(t: float) -> void:
	half = RIFT_HALF_MAX * ease_in_out(span(t, OPEN_START, OPEN_END))
	half *= 1.0 - ease_in_out(span(t, CLOSE_START, CLOSE_END))

	lab.broadcast("rift_origin", Vector3(0.0, 0.0, 0.0))
	lab.broadcast("rift_normal", Vector3(1.0, 0.0, 0.0))
	lab.broadcast("rift_width", half)

	# The canyon furniture only exists while there is a canyon.
	var open := half > 0.05
	wall_l.visible = open
	wall_r.visible = open
	floor_mesh.visible = open
	wall_l.position.x = -(half + 0.28)
	wall_r.position.x = half + 0.28
	# The walls are TALL ENOUGH TO REACH THROUGH THE GROUND: their tops are above
	# the terrain so no sky shows between the rift's edge and the wall's edge.
	for w in [wall_l, wall_r]:
		(w as MeshInstance3D).position.y = -RIFT_DEPTH * 0.5 + 1.2

	var glow := clampf(half / RIFT_HALF_MAX, 0.0, 1.0)
	for v in veins:
		var n: MeshInstance3D = v["node"]
		var seed: float = v["seed"]
		# Each filament rises and falls on its own phase, but the phase is a pure
		# function of `t` and its index — nothing is stored between frames.
		var pulse := 0.45 + 0.55 * (0.5 + 0.5 * sin(t * 1.35 + seed))
		n.scale.x = 1.0 + 2.4 * glow * pulse
		n.scale.z = 1.0 + 2.4 * glow * pulse
		(v["mat"] as ShaderMaterial).set_shader_parameter(
			"alpha", glow * (0.46 + 0.55 * pulse))

	lab.weapon_root.visible = t < HERO_WIDE_END + 0.6
	_camera(t)
	_weapon(t)


func _camera(t: float) -> void:
	if t < HERO_WIDE_END:
		# FIRST PERSON, STANDING OFF THE LINE OF THE CUT. The first version stood on
		# the axis so the cut would run straight away from the lens — and that is
		# exactly what made it illegible, because a rift seen straight down its own
		# plane shows you its EDGE and not its WALLS: the still came back as a dark
		# stripe painted on the road. 6.5 m to the side puts the near wall, the far
		# wall and the lit floor of the canyon into the same frame, which is the
		# difference between a crack and a canyon.
		lab.review_off()
		var eye := Vector3(6.60, 0.0, 1.40)
		eye.y = lab.ground_height(eye.x, eye.z) + 1.78
		# HELD FROM 4.60. The canyon keeps widening until 6.30 but the camera stops
		# at 4.60, so the last 1.7 s of the opening is a motionless frame holding
		# both rims, both walls and the lit floor at once — the beat you can pause
		# on. V1 tracked the widening for its whole duration and so never held.
		var down := ease_in_out(span(t, OPEN_START, 4.60))
		camera(eye, Vector3(-0.6, lerpf(1.40, -6.40, down), -22.0),
			lerpf(72.0, 66.0, down), sin(t * 0.29) * 0.008)
		return

	# ONE EXTERNAL BEAT, from high and off-axis, because by now the claim is a
	# SHAPE — a line across the world with two edges — and a camera standing beside
	# a cut cannot see the cut.
	lab.review_off()
	var u := ease_in_out(span(t, HERO_WIDE_END, HERO_WIDE_END + 0.5))
	var eye2 := Vector3(46.0, 30.0, 40.0).lerp(Vector3(62.0, 44.0, 66.0), u)
	camera(eye2, Vector3(-1.0, -6.0, -44.0), 52.0, 0.0)


func _weapon(t: float) -> void:
	# A single overhead cut: up, then through. `weapon_blend` is a pose lerp, so the
	# arc is written as its two ends and the curve between them.
	var up := ease_in_out(span(t, 0.35, 1.45))
	var through := ease_in_out(span(t, 1.45, 2.35))
	var pose := up - through
	lab.weapon_blend(Vector3(0.10, 0.15 - 0.55 * through, -0.70),
		Vector3(-8.0 - 62.0 * (1.0 - through), -40.0 + 30.0 * through, -18.0 + 26.0 * through),
		0.95, pose)


func phase_name(t: float) -> String:
	if t < OPEN_START:
		return "起手 · 一刀从头顶落下"
	if t < OPEN_END:
		return "地脉裂开 %.0f%%" % (100.0 * ease_in_out(span(t, OPEN_START, OPEN_END)))
	if t < HERO_WIDE_END:
		return "裂缝里升起地脉的光"
	if t < CLOSE_START:
		return "裂到最宽"
	if t < CLOSE_END:
		return "地面合上"
	return "世界回到原样"
