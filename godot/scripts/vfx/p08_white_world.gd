extends "res://scripts/vfx/vfx_prototype.gd"
#
# 08 · 白界 / WHITE WORLD
#
# =============================================================================
# THE CLAIM
# =============================================================================
#
# A fire goes through the world and burns the COLOUR off it. Nothing is destroyed.
# Every building is still standing, every tree is still in the same place with the
# same silhouette, every stone is still a stone — and none of them have a colour any
# more. What is left is a world made of information instead of matter: white, fully
# rough, and faintly luminous, like a plaster model of the street you were standing
# in.
#
# =============================================================================
# WHY THE FIRE HAS TO TRAVEL
# =============================================================================
#
# `whiten` on its own is a 0-to-1 number, and a 0-to-1 number on a whole world is a
# DISSOLVE: everything loses its colour in the same frame and the audience reads a
# filter being turned up. The claim is a fire, so the colour has to leave first where
# the fire is. `whiten_spread` turns the uniform into the FRONT of a wave — `whiten`
# is the wave's height, the spread is where its front currently is, and every
# fragment asks how far it is from the origin.
#
# That single clause is also what makes the hero still work. Half a street of colour
# and half a street of white, with the burnt zone arriving through the middle of the
# frame, is a picture of a thing happening. An entirely white world is a picture of
# a thing that already happened.
#
# =============================================================================
# THE TWO THINGS THE FIRE DOES NOT REACH
# =============================================================================
#
# The player's own blade, which stays coloured for the whole clip — because "the
# world lost its colour" and "the screen lost its colour" are different sentences
# and only one of them is the claim. And the target, which is still white at the end
# of the clip after everything else has come back: the same receipt as 01 二相簿, for
# the same reason. A restore that restores everything is a clip that said nothing.

## Metres. The wave's front, and how soft its edge is.
const SPREAD_END := 700.0
const SOFT := 17.0
## BEFORE THE FIRE, THE FRONT IS AT -60, NOT AT 0. `whiten_spread = 0` is the
## shader's documented GLOBAL mode — passing it here as "nothing yet" selected that
## branch and bleached the entire world from frame one. A negative spread is a wave
## whose own soft rim has not reached the nearest fragment yet, which is exactly
## "the fire has not started".
const SPREAD_BEFORE := -60.0
## The origin sits just in front of the player, so the first frame of the burn is
## the road at their feet and not the inside of their own head.
const ORIGIN := Vector3(0.40, 1.10, -3.20)

const BURN_START := 1.45
const BURN_END := 5.00
const HOLD_END := 6.40
const RETURN_END := 8.70

var front: MeshInstance3D
var front_mat: ShaderMaterial
var blade_mats: Array = []
var target_mats: Array = []
var spread := 0.0


func build() -> void:
	super()
	t_end = 10.6
	# A high, flat, slightly overcast day: the world has plenty of colour to lose, and
	# a whitened world against a whitened sky is the clip's second half.
	lab.set_sky("day")
	lab.sun.light_energy = 1.05
	lab.player_proxy.visible = false

	blade_mats = lab.materials_under(lab.weapon_root)
	target_mats = lab.materials_under(lab.target)

	# THE FRONT, ON THE GROUND. The whiten wave is a SPHERE, so its intersection with
	# the ground is a circle that travels outward — and a circle travelling outward
	# needs something drawn on it or the only evidence of the fire's position is a
	# soft gradient. Warm white and additive: it is the fire, not the ash.
	front_mat = lab.glow_mat(Color(1.00, 0.90, 0.72), 1.85, 0.0, 0.0)
	front_mat.set_shader_parameter("alpha", 0.0)
	front = MeshInstance3D.new()
	var tor := TorusMesh.new()
	# NOT 1.0 / 1.0. Godot's TorusMesh refuses equal radii and leaves the mesh
	# unbuilt (two console errors and a null surface) — and the ring is not drawn
	# until `apply` writes the real radii anyway, so the placeholder only has to be
	# a VALID torus. The tube is rewritten every frame from the current spread.
	tor.inner_radius = 0.999
	tor.outer_radius = 1.0
	tor.rings = 72
	tor.ring_segments = 6
	front.mesh = tor
	front.material_override = front_mat
	front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(front)


func apply(t: float) -> void:
	var burn := ease_out_cubic(span(t, BURN_START, BURN_END))
	var back := ease_in_out(span(t, HOLD_END, RETURN_END))
	spread = lerpf(SPREAD_BEFORE, SPREAD_END, burn)
	# THE COLOUR COMES BACK FROM THE EDGES, not from the centre: the front retreats,
	# so the last thing to be white is the ground at the player's feet. A restore that
	# started at the centre would read as a second fire in the opposite direction.
	spread = lerpf(spread, SPREAD_BEFORE, back)

	lab.broadcast("whiten_origin", ORIGIN)
	lab.broadcast("whiten", 1.0)
	lab.broadcast("whiten_spread", spread)
	lab.broadcast("whiten_soft", SOFT)
	lab.broadcast("whiten_tint", Color(0.945, 0.945, 0.965))

	# THE BLADE KEEPS ITS COLOUR. Re-asserted every frame because the broadcast above
	# runs over these very materials.
	for m in blade_mats:
		(m as ShaderMaterial).set_shader_parameter("whiten", 0.0)
	for m in target_mats:
		# The target is the one thing still white after the world has its colour back.
		if t > RETURN_END:
			(m as ShaderMaterial).set_shader_parameter("whiten_spread", 0.0)
		else:
			(m as ShaderMaterial).set_shader_parameter("whiten_spread", spread)

	# The sky loses its colour once the front has passed the horizon, and not before:
	# a sky that went white first would take the frame with it and leave the ground
	# burning against nothing.
	lab.sky_material().set_shader_parameter("whiten",
		clampf((spread - 120.0) / 260.0, 0.0, 1.0) * (1.0 - back))

	# The front ring: its tube is a fixed 2.2 m as seen in the world, so the MESH's
	# own inner/outer radii are rewritten from the current spread instead of scaling
	# the node — scaling the node would scale the tube along with the ring and the
	# front would get fatter as it travelled.
	front.visible = spread > 6.0
	front.position = Vector3(ORIGIN.x, lab.ground_height(ORIGIN.x, ORIGIN.z) + 0.45, ORIGIN.z)
	var tube := 2.2 / maxf(spread, 0.001)
	front.scale = Vector3(maxf(spread, 0.001), 1.0, maxf(spread, 0.001))
	(front.mesh as TorusMesh).inner_radius = 1.0 - tube
	(front.mesh as TorusMesh).outer_radius = 1.0 + tube
	front_mat.set_shader_parameter("alpha",
		clampf(burn * 1.5, 0.0, 1.0) * (1.0 - back) * clampf(1.0 - spread / SPREAD_END, 0.0, 1.0))

	lab.weapon_root.visible = true
	_camera(t)
	_weapon(t)


func _camera(t: float) -> void:
	if t < HOLD_END:
		# FIRST PERSON, DOWN THE ROAD, ON THE AXIS OF THE FIRE. The wave is a circle
		# centred on the player, so looking along the road is looking along its
		# radius — which is the only angle at which the FRONT is a line across the
		# frame instead of a ring around the lens.
		lab.review_off()
		var eye := Vector3(0.40, lab.ground_height(0.40, 0.0) + 1.76, 0.0)
		camera(eye, Vector3(0.0, lerpf(2.20, 3.60, span(t, BURN_START, BURN_END)), -30.0),
			70.0, sin(t * 0.27) * 0.009)
		return

	# ONE EXTERNAL BEAT, and it is the one the clip needs: from inside, "the world is
	# white" and "the renderer gave up" look identical. From outside, with the road,
	# the buildings and the trees all still in their places and all still readable as
	# shapes, the geometry is visibly intact.
	lab.review_off()
	# SETTLED BY 7.40, THEN STILL THROUGH THE RETURN. The external frame is where
	# "the geometry survived" is provable, so it must be held while the white
	# recedes — a camera still travelling through the restore reads as motion
	# blur being cleaned up, not as the world becoming readable again.
	var u := ease_in_out(span(t, HOLD_END, 7.40))
	camera(Vector3(26.0, 12.0, 24.0).lerp(Vector3(34.0, 16.0, 30.0), u),
		Vector3(-2.0, 3.0, -34.0), lerpf(50.0, 46.0, u), 0.0)


func _weapon(t: float) -> void:
	# A sweep, not a point: the fire is carried outward by the blade.
	var swing := ease_in_out(span(t, 0.40, 1.45))
	swing *= 1.0 - ease_in_out(span(t, BURN_END, RETURN_END))
	var arc := sin(swing * PI * 0.5)
	lab.weapon_blend(Vector3(0.30 + 0.34 * arc, -0.30 + 0.16 * arc, -0.70),
		Vector3(-26.0 - 40.0 * arc, -58.0 + 96.0 * arc, 6.0 - 14.0 * arc), 0.90, swing)


func phase_name(t: float) -> String:
	if t < BURN_START:
		return "起手 · 刀扫过世界"
	if t < BURN_END:
		return "颜色被烧掉 %.0f m" % spread
	if t < HOLD_END:
		return "白界 · 东西都还在，颜色没有了"
	if t < RETURN_END:
		return "颜色从边上回来"
	return "目标还留在白里"
