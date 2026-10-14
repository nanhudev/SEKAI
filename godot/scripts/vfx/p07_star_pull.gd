extends "res://scripts/vfx/vfx_prototype.gd"
#
# 07 · 星坠 / STAR FALL
#
# =============================================================================
# THE CLAIM
# =============================================================================
#
# A star comes out of the sky and comes down. It falls fast — this is not 02's slow
# verdict — and then it STOPS, dead, three and a half metres above the road, and
# settles onto the ground and stays there. Nothing breaks. Nothing burns. And then
# the light in the world changes: the sun goes out and the road is lit by the thing
# that just landed on it.
#
# The rule being rewritten is not "something fell from the sky". It is that a star
# can be a BODY — that it can arrive, come to rest, and be a light source at road
# scale instead of an event. A falling star that explodes is a meteor; a falling
# star that parks is a violation.
#
# =============================================================================
# WHY THE ARRIVAL IS AN OMNILIGHT AND NOT A BRIGHTER MESH
# =============================================================================
#
# A bright ball in the dark says "there is a bright ball". A bright ball with a
# light under it says "the world's light comes from there", and that is the second
# half of the claim. So `LAB.settings` aside, this prototype adds exactly one thing
# to the lab that no other prototype adds — an `OmniLight3D` parented to the star —
# and the settle is written as a crossfade between the sun and the star: the sun's
# energy goes to 0.06 while the star's goes to 9. The world does not get darker, it
# gets RE-LIT.
#
# =============================================================================
# WHY THE STOP IS THE HERO FRAME
# =============================================================================
#
# A fast-moving bright object is legible in motion and illegible in a still. The
# frozen frame has to be the moment it is NOT moving: a star hanging in the air
# with nothing holding it, the trail still hanging above it, and the road below
# completely undamaged.

## Where the star ends up: just above the road, 19 m out.
const REST_AT := Vector3(1.20, 3.40, -19.0)
## WHERE IT STARTS IS WHERE THE SKY'S OWN BODY WAS. The night preset paints a body at
## the normalised direction (-0.46, 0.52, -0.72); the falling star begins at that
## same direction, 430 m out, so the frame where the painted body switches off and
## the real one switches on is a frame where nothing appears or disappears. The
## handoff is the whole reason this is a constant and not a guess.
const FALL_FROM := Vector3(-197.8, 223.6, -309.6)
const STAR_R := 0.95

const DETACH_START := 1.20
const DETACH_END := 2.00
const FALL_END := 3.55
const HOVER_END := 4.60
const SETTLE_END := 6.20
const RELEASE_START := 8.40
const RELEASE_END := 10.20

var star: MeshInstance3D
var halo: MeshInstance3D
var trail: MeshInstance3D
var trail_mat: ShaderMaterial
var lamp: OmniLight3D


func build() -> void:
	super()
	t_end = 10.8
	lab.set_sky("night")
	# The world has to be READABLE at the start without the star, so the moon light
	# starts at a level that shows the greybox — and low enough that its removal is
	# a visible event.
	lab.sun.light_energy = 0.42
	# The night preset paints a moon-disc 8° across, and a second light source that
	# big competes with the one falling. Shrunk to a bright point so the sky holds a
	# STAR and the clip is about the one that leaves.
	lab.sky_material().set_shader_parameter("body_radius", 0.045)
	lab.sky_material().set_shader_parameter("body_glow", 1.5)
	lab.sky_material().set_shader_parameter("body_amount", 2.4)
	# BLOOM. `gl_compatibility` supports `env.glow` and this is the one prototype
	# whose subject is a light source, so it is the one prototype that turns it on.
	#
	# AND IT IS TUNED TO STAY A POINT. The first pass ran the glow at 0.85 rising to
	# 1.55 with a threshold of 0.92, and the star that landed was a two-hundred-pixel
	# white disc with a halo wider than a house — a light bulb, not a star, and its
	# own size hid the street it was supposed to be lighting. The threshold is now
	# above 1.0, so only the core blooms, and the halo mesh is smaller and dimmer.
	lab.env.glow_enabled = true
	lab.env.glow_intensity = 0.42
	lab.env.glow_bloom = 0.18
	lab.env.glow_hdr_threshold = 1.06

	lab.player_proxy.visible = false

	# THE STAR. Unshaded and bright beyond 1.0, so the bloom is what makes it a light
	# rather than a sphere.
	var sh := Shader.new()
	sh.code = "shader_type spatial;\n" \
		+ "render_mode unshaded, fog_disabled;\n" \
		+ "uniform vec3 core : source_color = vec3(1.0, 0.94, 0.78);\n" \
		+ "void fragment() {\n" \
		+ "\tALBEDO = core * 4.6;\n" \
		+ "\tEMISSION = core * 4.6;\n" \
		+ "}\n"
	var star_mat := ShaderMaterial.new()
	star_mat.shader = sh
	star = MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = STAR_R
	sp.height = STAR_R * 2.0
	sp.radial_segments = 24
	sp.rings = 12
	star.mesh = sp
	star.material_override = star_mat
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(star)

	# THE HALO. A bigger, dimmer, additive sphere around the core. A bloom alone gives
	# an object a soft edge; this gives it an ATMOSPHERE, which is what separates a
	# light in the air from a glowing ball.
	halo = MeshInstance3D.new()
	var hp := SphereMesh.new()
	hp.radius = STAR_R
	hp.height = STAR_R * 2.0
	hp.radial_segments = 20
	hp.rings = 10
	halo.mesh = hp
	halo.material_override = lab.glow_mat(Color(1.00, 0.86, 0.62), 0.85, 0.0, 0.0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(halo)

	# THE TRAIL. Not a particle system: one tapered box lying along the fall's own
	# direction, taller than the fall, whose length and alpha are driven by how far
	# behind the star its own path is. A still frame then contains the whole history
	# of the fall instead of a single bright dot.
	trail_mat = lab.glow_mat(Color(1.00, 0.82, 0.56), 1.05, 0.0, 0.0)
	trail_mat.set_shader_parameter("alpha", 0.0)
	trail = MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(STAR_R * 0.85, 1.0, STAR_R * 0.85)
	trail.mesh = tb
	trail.material_override = trail_mat
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(trail)

	# THE LAMP. One light, parented to the star, off until it lands.
	lamp = OmniLight3D.new()
	lamp.light_energy = 0.0
	lamp.omni_range = 54.0
	lamp.light_color = Color(1.00, 0.90, 0.72)
	lamp.shadow_enabled = false
	star.add_child(lamp)


func apply(t: float) -> void:
	# ---- the descent, as one curve through three states ------------------------
	var fall := ease_in_cubic(span(t, DETACH_END, FALL_END))
	# THE STOP IS A DEDICATED SEGMENT AND NOT THE END OF THE EASE. If the fall curve
	# were simply clamped at `FALL_END` the object would arrive with its velocity
	# already spent, which reads as "slowed down". It arrives at speed and is then
	# held: `fall` reaches 1.0 and stops advancing, and the star's position after
	# that comes from `settle`, which is a different and much slower motion.
	var settle := ease_out_quint(span(t, HOVER_END, SETTLE_END))
	var rest_y := lerpf(FALL_FROM.y, REST_AT.y + 2.4, fall)
	rest_y = lerpf(rest_y, REST_AT.y, settle)
	var rest := FALL_FROM.lerp(REST_AT + Vector3(0.0, 2.4, 0.0), fall)
	rest.y = rest_y
	# The release: it goes back. The path out is the path in, reversed and faster —
	# a star that left a mark would be a different clip.
	var release := ease_in_cubic(span(t, RELEASE_START, RELEASE_END))
	rest = rest.lerp(FALL_FROM, release)

	star.position = rest
	halo.position = rest
	var pulse := 0.94 + 0.06 * sin(t * 2.1)
	halo.scale = Vector3.ONE * (2.05 * pulse) * (1.0 - release * 0.9)

	# ---- the trail -------------------------------------------------------------
	var travel: Vector3 = rest - FALL_FROM
	var len := travel.length()
	trail.visible = len > 1.5
	# The trail is drawn from the star BACK along the descent, and it fades out over
	# the last of the three quarters of a second, so the still at the top of the
	# hover has a full trail and the still half a second later has a short one.
	var trail_fade := 1.0 - ease_out_cubic(span(t, FALL_END + 0.35, HOVER_END))
	trail_fade *= 1.0 - release
	trail.position = rest - travel * 0.5
	trail.scale = Vector3(1.0, maxf(len, 0.01), 1.0)
	trail.rotation = Vector3.ZERO
	if len > 0.01:
		var up := Vector3.UP
		var dir := -travel / len
		trail.basis = Basis(Quaternion(up, dir)).scaled(
			Vector3(1.0 + 0.5 * (1.0 - trail_fade), maxf(len, 0.01),
				1.0 + 0.5 * (1.0 - trail_fade)))
		trail.position = rest + dir * (len * 0.5)
	trail_mat.set_shader_parameter("alpha",
		clampf(0.30 + 0.55 * (1.0 - fall), 0.0, 1.0) * trail_fade)

	# ---- the sky's star leaves with it ----------------------------------------
	var gone := ease_in_out(span(t, DETACH_START, DETACH_END + 0.6))
	gone *= 1.0 - release
	lab.sky_material().set_shader_parameter("body_amount", lerpf(2.6, 0.0, gone))
	lab.sky_material().set_shader_parameter("star_amount", lerpf(0.85, 0.45, gone * 0.8))

	# ---- and the world is RE-LIT rather than dimmed ---------------------------
	var lit := ease_in_out(span(t, HOVER_END, SETTLE_END + 0.6))
	lit *= 1.0 - release
	lamp.light_energy = 6.0 * lit
	lab.sun.light_energy = lerpf(0.42, 0.055, lit)
	lab.env.glow_intensity = lerpf(0.42, 0.72, lit)

	lab.weapon_root.visible = t < RELEASE_END
	_camera(t, rest, release)
	_weapon(t)


func _camera(t: float, rest: Vector3, release: float) -> void:
	if t < FALL_END + 0.75:
		# FIRST PERSON, LOOKING UP. The star has to be seen arriving from above, and
		# the only eye that can look up at it AND be under its light afterwards is
		# the player's.
		lab.review_off()
		var eye := Vector3(0.40, lab.ground_height(0.40, -1.0) + 1.76, -1.0)
		camera(eye, Vector3(rest.x * 0.5, maxf(rest.y * 0.45, 8.0), rest.z), 62.0,
			sin(t * 0.31) * 0.012)
		return

	if t < SETTLE_END:
		# The aim comes down with it, so the frame ends on the road the star is
		# standing over rather than in the sky it came from.
		lab.review_off()
		var u := ease_in_out(span(t, FALL_END + 0.75, SETTLE_END))
		var eye2 := Vector3(0.40, lab.ground_height(0.40, -1.0) + 1.76, -1.0)
		camera(eye2, Vector3(rest.x, lerpf(rest.y, 2.60, u), lerpf(rest.z, -22.0, u)),
			lerpf(62.0, 56.0, u), 0.0)
		return

	if t < RELEASE_START:
		# THE HERO, FROM THE SIDE. "It is a light source at road scale" is a claim
		# about the road, and a camera looking at the star cannot see the road it is
		# lighting. This one placement spends the beat on the lit street with the
		# thing hanging over it, out of focus and out of the way.
		lab.review_off()
		# SETTLED BY 7.30 AND THEN STILL UNTIL 8.40. This beat is the whole claim —
		# a road, lit, by something the size of a fist hanging over it — and V1 slid
		# the camera across it for 2.2 s so there was no frame to pause on.
		var u2 := ease_in_out(span(t, SETTLE_END, 7.30))
		camera(Vector3(24.0, 6.4, -2.0).lerp(Vector3(30.0, 5.2, 6.0), u2),
			Vector3(rest.x - 1.0, 2.40, rest.z - 4.0), 44.0, 0.0)
		return

	# Back to the eye for the release, so the clip closes on the same road it opened
	# on — with the sky quietly holding one more star than it did.
	lab.review_off()
	var eye3 := Vector3(0.40, lab.ground_height(0.40, -1.0) + 1.76, -1.0)
	camera(eye3, Vector3(rest.x * 0.6, lerpf(3.0, 22.0, release), rest.z * 0.6), 62.0, 0.0)


func _weapon(t: float) -> void:
	# The blade is what points at it, and it is put away as the star lands.
	var up := ease_in_out(span(t, 0.30, 1.30))
	up *= 1.0 - ease_in_out(span(t, SETTLE_END - 0.4, SETTLE_END + 0.9))
	lab.weapon_blend(Vector3(0.16, -0.10, -0.72), Vector3(-84.0, -12.0, 2.0), 0.90, up)


func phase_name(t: float) -> String:
	if t < DETACH_START:
		return "起手 · 天上少了一颗星"
	if t < FALL_END:
		return "星坠"
	if t < HOVER_END:
		return "停住了 · 没有砸下来"
	if t < RELEASE_START:
		return "它落在路上 · 世界由它照亮"
	if t < RELEASE_END:
		return "还回天上"
	return "回到原来的夜"
