extends "res://scripts/vfx/vfx_prototype.gd"
#
# 03 · 黑日 / BLACK SUN  ·  V2
#
# =============================================================================
# THE CLAIM, RESTATED BECAUSE V1 GOT IT WRONG
# =============================================================================
#
# V1 designed a ball. It grew to a 40 m sphere, hung over the village, and shrank
# again — and the whole clip read as a black-hole spell, because a large black
# sphere is the standard grammar for "a body with an event horizon" and no amount
# of removing the accretion disc changes what the audience already knows.
#
# V2 stops designing the ball. The ball is now a MARKER: fist-sized, unshaded,
# with no material information in it at all, small enough that it is barely a dot
# at the distance it hangs. It is not the effect. It is the place where the effect
# is going to be.
#
# The effect is:
#
#   A · a dot hangs in the air, quiet
#   B · THE SCALE OF SPACE GOES WRONG around it      <- this is the clip
#   C · the dot shrinks to a single pixel
#   D · the pixel holds
#   E · the pixel goes, and THE WORLD IS MISSING A SPHERE
#
# =============================================================================
# WHY PHASE B IS THE WHOLE PROTOTYPE
# =============================================================================
#
# The sentence this clip exists to say is "世界被挖掉了一个球", and the difference
# between that and "a black ball appeared" is entirely in whether the WORLD was
# seen to be wrong BEFORE the ball did anything. Delete the world without warning
# and the audience reads a spell; make the world's own metre measurably short
# first, and the deletion lands as the end of a process rather than as a
# conjuration.
#
# So Phase B does not move the ball and does not attract debris — the brief is
# explicit that the stones must not gather yet. It changes DISTANCE. `warp` in
# `vfx_prop.gdshader` remaps radius inside a bounded falloff, so within 30 m of the
# marker the same two points are closer together than they were, and outside 30 m
# nothing has happened at all. Buildings near the marker compress along the line
# to it (their vertices are warped in world space, so the near face moves further
# than the far one), the road's surface pulls into a shallow funnel, and the
# horizon is provably untouched.
#
# The props are moved by the same function in GDScript, at their own resting
# positions. Without that they would hang in the air while the ground slid out
# from under them, which would read as a bug in the terrain rather than as space
# being wrong — and the ground sliding out from under things is precisely the
# wrong sentence.
#
# =============================================================================
# WHY THE BALL IS UNLIT AND WHY THAT IS NOW CORRECT
# =============================================================================
#
# V1 gave the ball a polished surface, for a good reason: the ball and the hole
# were the same colour and shape, so its departure was invisible. V2 does not have
# that problem, because the ball and the absence are no longer the same event. The
# ball leaves at t = 5.60 and the absence arrives 0.18 s later, as a change in the
# WORLD, at a size the ball never had. The two are separated in time and in kind,
# so the ball can go back to being pure `ALBEDO = 0` — which is the right answer
# for something whose only job is to mark a point in space.
#
# =============================================================================
# FORBIDDEN, AND STILL FORBIDDEN
# =============================================================================
#
# No accretion disc, no lensing ring, no violet glow, no infalling particles, no
# screen-space refraction. Every one of those says "a thing with an event
# horizon". The absence at the end is not black-and-glossy either: it is the
# world's own surfaces ending, and the black behind them is the viewport's clear
# colour, which `build()` sets to pure black so the wound is a wound and not a
# grey disc with a rim.

## Where the marker hangs — and, when the marker is gone, the centre of the
## absence. One constant for both, because they are the same place: the absence is
## exactly where the dot was, at exactly the size the dot was not.
##
## ITS HEIGHT IS A COMPOSITION DECISION AND NOT A PHYSICS ONE. An absence centred
## 5 m up is nearly all sky, and an absence that is nearly all sky is a black BALL
## with a village in front of it — which is the V1 reading coming back through the
## window. At y = 2.0 the sphere is half in the ground, so its lower half is the
## terrain's own surface ending and the frame has to be read as a piece of the
## WORLD being absent rather than as an object being present.
const SEED_AT := Vector3(1.60, 3.00, -18.00)

## How much of the world the sphere takes out. 11 m of radius is a 22 m hole in a
## village whose buildings are 6-10 m tall: the absence is bigger than anything
## built near it, which is the point — and small enough that its silhouette fits in
## one frame with the ground under it.
const ABSENCE_R := 11.0

## The reach of the scale error. Deliberately smaller than the eye's idea of "the
## distance to the horizon", so the wrongness has an address.
const WARP_RADIUS := 30.0

## The dot's radius before it starts disappearing. A fist is about 0.09 m, and at
## 18 m that is roughly eight pixels: small, but a thing with an edge.
const R_FIST := 0.09
## The radius it swells to while space is going wrong.
const R_SWELL := 0.20

const APPEAR_END := 1.30
const WRONG_START := 1.30
const WRONG_END := 3.30
const SHRINK_START := 3.30
const SHRINK_END := 5.00
const DOT_HOLD_END := 5.60
const GONE_AT := 5.60
const BITE_END := 5.78
## The reveal finishes here and then HOLDS. Two attempts at a later value both
## missed: past ~7 s the absence has shrunk in frame AND the hill ridge has begun
## to eat its lower arc, so the black reads as a disc behind the mountains again —
## i.e. as an object, which is the exact failure this prototype exists to avoid.
## Stopped at 6.70 while the void still fills the sky, still has a clean circular
## edge, and is still visibly cutting chunks out of the rooflines below it.
const REVEAL_END := 6.40
const HERO_END := 8.60
const HEAL_END := 9.80

var orb: MeshInstance3D


func build() -> void:
	super()
	t_end = 11.0
	lab.set_sky("day")
	lab.sun.light_energy = 1.15
	# NOTHING INSTEAD OF SOMETHING. The dome's hole is a `discard`, so what shows
	# through is the viewport's clear colour, and the clear colour has to be black
	# or the absence is a grey disc with a hard edge — which is a painted circle.
	lab.env.background_color = Color(0.0, 0.0, 0.0)

	orb = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	orb.mesh = sphere
	orb.material_override = _marker_material()
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.position = SEED_AT
	stage.add_child(orb)


## NO MATERIAL INFORMATION. Not a shaded black ball, not a glossy one — `unshaded`
## with `ALBEDO = 0`, so the marker is a hole in the picture at every size and its
## only visible property is the edge where the world stops. That edge is enough:
## against a lit village and a bright sky, a two-pixel unshaded black dot at 18 m
## is unmistakable, and it is unmistakable for the right reason.
##
## `cull_back` and `depth_draw_opaque` because it is a solid object occupying
## space; `fog_disabled` so distance cannot tint it, which would be material
## information arriving by the back door.
func _marker_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\n" \
		+ "render_mode unshaded, cull_back, depth_draw_opaque, fog_disabled;\n" \
		+ "void fragment() {\n" \
		+ "\tALBEDO = vec3(0.0);\n" \
		+ "}\n"
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## The radius of a sphere that covers exactly one pixel of the frame, from the
## camera's own distance and the camera's own fov. Derived rather than typed in,
## because "1 pixel" is a claim about the LENS and a hardcoded 0.02 m would be
## one pixel at one distance and nothing at another.
func _one_pixel_radius(distance: float, fov: float) -> float:
	var h := float(lab.get_viewport().get_visible_rect().size.y)
	return maxf(distance * tan(deg_to_rad(fov * 0.5)) * 2.0 / maxf(h, 1.0), 0.0005)


## The same remapping the shader does, in GDScript, so a crate can be moved to
## agree with the ground it is standing on. Written once and used by both the
## shader (in GLSL, over vertices) and here (over rest positions) — the two are
## allowed to disagree by a few centimetres, because the residue IS the
## compression we are after, but they are not allowed to disagree about where the
## ground went.
func _warp_point(p: Vector3, amount: float) -> Vector3:
	if amount <= 0.0001:
		return p
	var wd := p - SEED_AT
	var wr := wd.length()
	if wr < 0.001:
		return p
	var wf := 1.0 - smoothstep(0.0, WARP_RADIUS, wr)
	return SEED_AT + wd * (1.0 - amount * wf * wf * 0.62)


func apply(t: float) -> void:
	# ---- A/B · THE MARKER, AND THE SCALE ERROR -------------------------------
	var wrong := ease_in_out(span(t, WRONG_START, WRONG_END))
	lab.broadcast("warp_center", SEED_AT)
	lab.broadcast("warp_radius", WARP_RADIUS)
	lab.broadcast("warp_amount", wrong)

	# Everything that stands on the ground has to agree with it. Buildings are in
	# here too: their roots move by the warp at their own centre, which leaves the
	# building's own vertices to supply the compression for free.
	var movers: Array = lab.group("building") + lab.group("crate") \
		+ lab.group("rock") + lab.group("tree")
	for e in movers:
		var node: Node3D = e["node"]
		node.position = _warp_point(e["home_pos"], wrong)

	# ---- C · THE DOT GETS SMALLER, IN THREE VISIBLE STEPS --------------------
	var eye: Vector3 = lab.cam_eye
	var d := eye.distance_to(SEED_AT)
	var one_px := _one_pixel_radius(d, 62.0)
	var r := R_FIST
	r = lerpf(r, R_SWELL, wrong)
	var s := span(t, SHRINK_START, SHRINK_END)
	if s < 0.34:
		r = lerpf(R_SWELL, 0.050, s / 0.34)
	elif s < 0.67:
		r = lerpf(0.050, 0.012, (s - 0.34) / 0.33)
	else:
		r = lerpf(0.012, one_px, (s - 0.67) / 0.33)
	orb.scale = Vector3.ONE * r
	orb.visible = t < GONE_AT

	# ---- E · THE WORLD IS MISSING A SPHERE -----------------------------------
	# It arrives in 0.18 s, which is fast enough to be a deletion and slow enough
	# to have a frame that is neither before nor after. The absence is BIGGER than
	# the ball ever was, and that difference is the clip's whole sentence.
	var bite := ABSENCE_R * ease_out_cubic(span(t, GONE_AT, BITE_END))

	lab.broadcast("carve_center", SEED_AT)
	lab.broadcast("carve_radius", bite)
	lab.broadcast("carve_keep_inside", 0.0)
	lab.broadcast("carve_soft", 0.0)

	# ---- the sky's half of the same hole, reconciled from the lens ------------
	if bite > 0.01:
		var half := atan(bite / maxf(eye.distance_to(SEED_AT), 0.001))
		lab.sky_material().set_shader_parameter(
			"void_direction", (SEED_AT - eye).normalized())
		lab.sky_material().set_shader_parameter("void_cos", cos(half))
	else:
		lab.sky_material().set_shader_parameter("void_cos", -1.0)

	# ---- RESTORE: the space heals, the absence does not ----------------------
	# The two are separated on purpose. `wrong` walks back to zero over the last
	# second and the village's own metre becomes correct again — and the sphere is
	# still gone, because a rate of change is not a hole.
	lab.weapon_root.visible = t < GONE_AT - 0.5
	_camera(t, wrong, bite)


func _camera(t: float, wrong: float, bite: float) -> void:
	# The reveal starts AT THE MOMENT THE PIXEL GOES, not when the dot reaches one
	# pixel. `SHRINK_END` and `DOT_HOLD_END` are half a second apart and that half
	# second is the quietest thing in the clip; starting the pull-back at
	# `SHRINK_END` — which the first V2 pass did — spent it on a camera move and
	# threw away the beat the brief asks for by name.
	var u := ease_in_out(span(t, DOT_HOLD_END, REVEAL_END))

	if u <= 0.0:
		# FIRST PERSON, ON THE ROAD, WITH THE VILLAGE BEHIND THE MARKER. A dot
		# against empty sky is a star that has wandered low; the same dot with a
		# roofline under it is a place in the world.
		lab.review_off()
		var step := ease_in_out(span(t, 0.70, SHRINK_END))
		var eye := Vector3(-1.20, lab.ground_height(-1.20, -4.0) + 1.72, -4.0 - 1.6 * step)
		camera(eye, SEED_AT, 62.0, sin(t * 0.37) * 0.008)
		return

	# THE ABSENCE IS A SHAPE AND A SHAPE IS SEEN FROM THE SIDE.
	#
	# The first V2 pass revealed it from above and behind, and an absence looked at
	# from above is an ELLIPSE — which does not read as a sphere of the world being
	# missing, it reads as a pool of black liquid lying on the ground. The whole
	# claim depends on the silhouette being a CIRCLE, and a circle is only a circle
	# from a camera at the absence's own height.
	#
	# So the reveal is a retreat along the ground: the eye drops from the player's
	# head to about 4 m and travels 30 m out and sideways, finishing nearly level
	# with the centre of the hole. The height it gains (2.2 m) is small on purpose —
	# any more and the ellipse comes back.
	# THE RETREAT IS A LATERAL DOLLY, NOT A WALK BACKWARDS, AND THAT IS THE FIX.
	# V2's second pass retreated 25 m along +z as well as sideways; z = +10 put the
	# village's own hill ridge BETWEEN the lens and the hole, so the lower arc of the
	# circle was eaten by a silhouette and the absence came back as a black crescent
	# hanging over the mountains — an object again. Staying on the hole's own z and
	# moving only in x keeps the view near-horizontal (so the silhouette stays a
	# circle, not an ellipse) and leaves the hole in front of the village instead of
	# behind it, at ~26 m: close enough that an 11 m sphere still fills the frame,
	# far enough that it does not overrun it.
	var eye2 := Vector3(-1.20, lab.ground_height(-1.20, -4.0) + 1.72, -5.6).lerp(
		Vector3(-21.0, 3.90, -6.0), u)
	camera(eye2, SEED_AT, lerpf(58.0, 52.0, u), 0.0)


func phase_name(t: float) -> String:
	if t < APPEAR_END:
		return "一个点悬在路上方"
	if t < WRONG_END:
		return "空间尺度错误 %.0f%%" % (100.0 * span(t, WRONG_START, WRONG_END))
	if t < SHRINK_END:
		return "萎缩"
	if t < GONE_AT:
		return "一个像素"
	if t < HERO_END:
		return "世界少了一块球形"
	return "空间复原 · 空缺留下"
