extends "res://scripts/vfx/vfx_prototype.gd"
#
# 05 · 海啸但水不动 / TIDAL TILT  ·  V2
#
# =============================================================================
# THE CLAIM
# =============================================================================
#
# The world tips over into the sea and the SEA DOES NOT MOVE. Not "a wall of water
# rises" — the water is a perfectly flat, perfectly still surface for the entire
# clip, and the land is what comes to it. A tsunami is loud; this one is silent, and
# the silence is the rule being rewritten: water at this scale is supposed to
# churn, and this water has no ripples, no crests, no foam, no motion of any kind.
#
#   · THE WORLD IS PARENTED AND THE CAMERA IS NOT. `lab.world_root` holds every
#     greybox object in the scene, so rotating it tips the terrain, the road, the
#     village and the trees in one assignment, while the camera keeps its own
#     level — which is the read. The player does not fall over; the world does.
#   · THE SEA IS A MIRROR AND NOT A WAVE. `vfx_water.gdshader` has no time uniform
#     at all, by construction. It gives back the sky's own gradient by reflecting
#     the view ray, so the picture in the water changes only when the CAMERA moves.
#
# =============================================================================
# WHAT V2 ADDS, AND WHY EACH ONE IS A CAUSE RATHER THAN A DECORATION
# =============================================================================
#
# V1 got the two big decisions right and then under-committed, twice.
#
# 1 · COMPENSATION, AND WHY IT IS THE WHOLE ILLUSION.
#     V1 left the eye at the ground's UNROTATED height, so as the world went over
#     the ground sank away from a camera that was no longer standing on anything.
#     It read as a tilt, and it also read as the player hovering.
#
#     V2 attaches the eye to the world — the head rides the ground it is standing
#     on, and keeps a LEVEL horizon while it does. Those two facts together are the
#     entire claim: the eye goes down with the land, the horizon does not, and the
#     only available explanation is that the WORLD rotated and the player did not.
#     A camera that stayed put says "the ground sank"; a camera that rolled with
#     the world says "I tilted my head". Only the combination says "the world is
#     falling into the sea and I am standing on it".
#
# 2 · THE PLAYER FIGURE IS COUNTER-ROTATED, AND IT IS THE SIGNATURE IMAGE.
#     `player_proxy` lives under `world_root`, so it tips with everything else. V2
#     rotates it back by exactly the world's angle, about its own feet, every
#     frame. The result is a figure standing bolt upright on a 60° slope, and that
#     one detail does more for the sentence than any amount of camera work: a
#     person cannot stand like that unless the world moved.
#
# 3 · DEBRIS OBEYS THE NEW GRAVITY.
#     The brief asks for loose stones sliding toward the sea, and the reason is not
#     spectacle — it is that a crate sliding downhill is the world's own statement
#     about which way is down now. Nothing else in the frame says "gravity has a
#     new direction"; the tilted terrain could be a modelling error. A crate
#     halfway down a slope, having slid there, cannot be.
#
# =============================================================================
# WHY THE SEA LEVEL IS 26 METRES DOWN
# =============================================================================
#
# The water has to be invisible at the start or the "cause" frame is already a
# flooded world. The visible ground inside the road corridor is within a metre of
# level, and the terrain only drops to -14 m at its far western edge, so a sea at
# -26 m is completely hidden by the ground at t = 0 and starts to show the moment
# the world tips. From then on the WATERLINE IS THE CLOCK: the ground at distance
# `d` has fallen to `-d·sin θ`, so at 10° the sea reaches out to 150 m, at 30° to
# 52 m, and at 60° to 30 m — it eats its way in from the horizon toward the player,
# and it never once breaks.
#
# =============================================================================
# WHY THE PLANE IS ONLY 700 m ACROSS
# =============================================================================
#
# 380 m is where the terrain ends. A sea larger than that pokes out past the land
# on the horizon from the first frame, which turns "the world is pouring into the
# sea" into "the world is an island", and the clip is about a change of state.

## The brief's 0 / 10 / 30 / 45 / 60 / 90. The 90° key is short on purpose: at a
## full 90° the village is directly below the pivot, and the beat exists to prove
## how far it went rather than to be looked at for long.
const TILT_KEYS := [
	[1.80, 0.0], [3.10, 10.0], [4.30, 30.0], [5.40, 45.0], [6.30, 60.0], [7.00, 90.0],
]
const HOLD_END := 7.90
const RESTORE_END := 10.40
## Where the player's eye hands over to the outside eye. Just before 45°, which is
## the last angle at which the village is still in front of a level head rather
## than below it: at 45° the aim has already run into its own clamp and the thing
## being drowned is out of frame.
const FP_END := 4.90
const SEA_Y := -26.0
const SEA_SIZE := 700.0
## Debris starts moving once the slope is steep enough to matter, and the slope that
## matters is about 15°.
const SLIDE_START_TILT := 15.0
const SLIDE_FULL_TILT := 70.0

var sea: MeshInstance3D
var sea_mat: ShaderMaterial
var sliders: Array = []


func build() -> void:
	super()
	t_end = 11.6
	lab.set_sky("dusk")
	# A smaller, dimmer body than the preset's: the sunset at the size the preset
	# gives it is a 40-degree white lamp, and in a clip whose second half is half
	# water and half sky that lamp is the whole frame.
	lab.sky_material().set_shader_parameter("body_amount", 1.5)
	lab.sky_material().set_shader_parameter("body_radius", 0.042)
	lab.sky_material().set_shader_parameter("body_glow", 1.0)
	lab.sun.light_energy = 0.92
	# THE PLAYER IS IN THIS FILM. In V1 they were switched off because every shot
	# was first person; in V2 the hero frame is a figure standing upright on a
	# slope, so the proxy has to exist and has to be findable.
	lab.player_proxy.visible = true

	_collect_sliders()

	# The sea. A single quad, no subdivisions, no normal map, no vertex animation —
	# there is nothing for them to do.
	sea_mat = ShaderMaterial.new()
	sea_mat.shader = load("res://vfx/vfx_water.gdshader")
	# Read off the SAME preset the dome got, so the reflection and the sky agree —
	# and then pulled COOL. The dusk sky's horizon is a warm tan, and a mirror is
	# obliged to return it, which is how a sea at sunset turns into a desert.
	sea_mat.set_shader_parameter("zenith_color", Vector3(0.075, 0.115, 0.215))
	sea_mat.set_shader_parameter("horizon_color", Vector3(0.340, 0.290, 0.330))
	sea_mat.set_shader_parameter("horizon_sharpness", 3.0)
	sea_mat.set_shader_parameter("energy", 1.05)
	# THE WATER'S OWN COLOUR, AND WHY IT IS NOT IN THE SKY'S PALETTE. Everything above
	# is the sky seen in the water; this is the water.
	sea_mat.set_shader_parameter("body_color", Vector3(0.062, 0.104, 0.156))
	sea_mat.set_shader_parameter("body", 0.46)
	sea_mat.set_shader_parameter("sun_dir", Vector3(-0.30, 0.14, -0.94).normalized())
	sea_mat.set_shader_parameter("glint", 2.6)
	sea_mat.set_shader_parameter("glint_color", Color(1.00, 0.86, 0.66))
	sea = MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(SEA_SIZE, SEA_SIZE)
	sea.mesh = q
	sea.material_override = sea_mat
	sea.position = Vector3(0.0, SEA_Y, 0.0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(sea)


## Which loose things will slide, and how far down the slope each one gets. Only
## crates and rocks: they are the two kinds in this village that are not attached
## to anything, and a sliding building would be a different and much louder claim.
##
## The slide is applied in `world_root`'s own frame along LOCAL -Z, because that is
## the downhill direction once the slab rotates about X — the far side of the world
## goes under, so the far side is down.
func _collect_sliders() -> void:
	for e in lab.group("crate") + lab.group("rock"):
		var home: Vector3 = e["home_pos"]
		# Only things far enough out to have room to slide, and not so far that they
		# would leave the terrain.
		if home.z > -18.0 or home.z < -80.0:
			continue
		var size: Vector3 = e["size"]
		sliders.append({
			"node": e["node"],
			"home": home,
			"kind": String(e["kind"]),
			"half": size.y,
			# Deterministic stagger, so they do not all leave on the same frame.
			"bias": n1(home.x * 3.1 + home.z * 1.7, 0.0),
		})


func apply(t: float) -> void:
	var tilt := _tilt(t)
	lab.world_root.rotation = Vector3(deg_to_rad(-tilt), 0.0, 0.0)
	# THE COMPENSATION, as a rotation: undo the world, about the figure's own feet.
	# Written as a positive X rotation of exactly the world's negative one, so the
	# two can never drift apart — a hardcoded lean would be right at one angle.
	lab.player_proxy.rotation = Vector3(deg_to_rad(tilt), 0.0, 0.0)

	_slide(tilt)
	lab.weapon_root.visible = true
	_camera(t, tilt)


## The debris. Distance travelled is a ramp on the tilt — the world has to be
## steeply inclined before anything with friction starts moving — and each item
## carries a deterministic bias so the slide is a scatter rather than a chorus.
func _slide(tilt: float) -> void:
	if tilt <= SLIDE_START_TILT:
		return
	var f := ease_in_out(span(tilt, SLIDE_START_TILT, SLIDE_FULL_TILT))
	for s in sliders:
		var node: Node3D = s["node"]
		var home: Vector3 = s["home"]
		var bias: float = s["bias"]
		var reach := (3.0 + 9.0 * bias) * f
		var z := home.z - reach
		# It has to stay ON the terrain it is sliding down, or the crate hangs in
		# the air and the shot reads as broken physics rather than as sliding.
		var y: float = lab.ground_height(home.x, z) + float(s["half"]) * 0.5
		node.position = Vector3(home.x + 0.9 * bias * f, y, z)
		# A slight lean down the slope, so it reads as carried rather than placed.
		node.rotation = Vector3(deg_to_rad(-34.0 * f), node.rotation.y, 0.0)


## The brief's numbers as a curve, with the 90° key restored by `RESTORE_END`.
func _tilt(t: float) -> float:
	var angle := 0.0
	for i in range(TILT_KEYS.size() - 1):
		var a: Array = TILT_KEYS[i]
		var b: Array = TILT_KEYS[i + 1]
		if t >= float(b[0]):
			angle = float(b[1])
			continue
		angle = lerpf(float(a[1]), float(b[1]),
			ease_in_out(span(t, float(a[0]), float(b[0]))))
		break
	var last: Array = TILT_KEYS[TILT_KEYS.size() - 1]
	if t >= float(last[0]):
		angle = float(last[1])
	angle *= 1.0 - ease_in_out(span(t, HOLD_END, RESTORE_END))
	return angle


## =============================================================================
## THE CAMERA, AND THE ONE THING IT MUST NEVER DO
## =============================================================================
##
## It must never roll. The camera lives outside `world_root`, so a level eye is not
## a lock — it is the statement. A camera that rolled with the world would have said
## "the world tilted" and thrown away the only part that is impossible.
##
## The eye RIDES the world (V2's addition) and the horizon does not. Between them
## those two facts are the whole clip, and neither works alone.
##
## Then there are three ranges, because no single range can carry both halves of the
## claim. A level plane's horizon sits at the EYE'S OWN HEIGHT, so the only way to
## hold a horizon and a 60° slab in one frame is to be far enough that the slab is
## small — and at that range a 1.8 m figure is a few pixels. So:
##
##   · the PLAYER'S EYE holds up to 30°, where the village leaning, the road under
##     the player and the sea's level horizon can all be in one frame;
##   · a MID shot holds 45-60° at ~70 m, which is close enough for the upright
##     figure to be read and far enough for the waterline to cross the frame;
##   · a FAR pull-back at ~300 m holds the whole slab, for the 90° beat, where the
##     subject is "how far did it go" and nothing else is legible anyway.
func _camera(t: float, tilt: float) -> void:
	lab.review_off()
	var brace := ease_in_out(span(t, 1.60, HOLD_END))
	# THE HEAD RIDES THE GROUND. A point on the world, put through the same rotation
	# the world just went through.
	var local_eye := Vector3(0.40, lab.ground_height(0.40, 0.0) + 1.76, -2.4 * brace)
	var eye: Vector3 = lab.world_root.transform * local_eye

	if t < FP_END:
		# The village centre, in the world's own frame, and then in the world's
		# current orientation — so the camera keeps looking at the place that is
		# being poured into the sea for as long as there is a place to look at.
		var aim_w: Vector3 = lab.world_root.transform * Vector3(0.0, 0.60, -26.0)
		var flat := Vector3(aim_w.x - eye.x, 0.0, aim_w.z - eye.z)
		var hd := maxf(flat.length(), 0.01)
		# Clamped at 30°: any steeper and the sea's horizon leaves the top of the
		# frame, and with it goes the only fixed thing in the shot.
		var pitch := clampf(atan2(aim_w.y - eye.y, hd), deg_to_rad(-16.0), deg_to_rad(3.0))
		camera(eye, Vector3(aim_w.x, eye.y + tan(pitch) * hd, aim_w.z),
			72.0, -0.012 * brace)
		return

	if t < 7.30:
		# THE MID SHOT · THE HERO FRAME. Close enough that the upright figure reads,
		# and framed so the waterline cuts across the picture rather than filling the
		# bottom of it. This is the frame the brief is describing: a person standing
		# normally, a town at 60°, a sea that has not moved.
		var u := ease_in_out(span(t, FP_END, 6.40))
		# THE HERO FRAME IS A PORTRAIT OF THE FIGURE, AND IT HAS TO BE.
		#
		# V2's first attempt kept the wide "look at the world" shot here and it came
		# back as a wall of hillside, for a reason that is pure geometry: the world
		# rotates about its own origin, so at 60° the terrain at the camera's own z
		# has swung UP by 1.732·z — 52 m at z = 30 — and the eye at y = 11 was 41 m
		# BURIED under the plate. There is no altitude that fixes this, because the
		# 760 m slab has by then become a 658 m wall; from anywhere near it, it fills
		# the frame and takes the horizon with it.
		#
		# So the shot stops being a view of the world and becomes a portrait of the
		# one thing that stayed upright. The eye rides the world's own frame — the
		# same trick as the compensation, applied to the camera — and stays a few
		# metres off the plate's surface, while its ORIENTATION stays level. The
		# result is the signature frame: a vertical body, a leaning village behind it,
		# and a ground that is obviously not where a ground should be.
		var local_eye2 := Vector3(2.0, 3.6, 8.0).lerp(Vector3(4.5, 4.6, 12.0), u)
		var eye2: Vector3 = lab.world_root.transform * local_eye2
		var aim2: Vector3 = lab.world_root.transform * Vector3(-4.0, 1.2, -12.0)
		camera(eye2, aim2, lerpf(50.0, 42.0, u), 0.0)
		return

	# THE FAR PULL-BACK GOES OUT OVER THE SEA, NOT BACK OVER THE LAND, and that is
	# not a preference — it is the only direction in which the 90° beat exists at
	# all. Rotating the world about its origin swings the terrain at +z UP by
	# 1.732·z, so by 90° the 760 m slab is a 658 m wall and the old retreat, which
	# flew backwards over the land, spent the beat underneath it: every frame came
	# back as an unreadable wall of hillside. Out over the water the slab has sunk
	# instead of risen, the camera is ~550 m clear of it, and what the frame finally
	# holds is the thing this prototype is actually about — a level, motionless sea,
	# and a country standing on end above it.
	var pull := ease_in_out(span(t, 7.30, 8.30))
	var back := ease_in_out(span(t, 9.00, RESTORE_END))
	pull *= 1.0 - back
	var eye3 := Vector3(96.0, 46.0, 86.0).lerp(Vector3(210.0, 96.0, -260.0), pull)
	var hd2 := Vector2(eye3.x, eye3.z).length()
	camera(eye3, Vector3(0.0, eye3.y - tan(deg_to_rad(6.5)) * hd2, -14.0),
		lerpf(56.0, 50.0, pull), 0.0)


func _weapon(t: float) -> void:
	pass


func phase_name(t: float) -> String:
	if t < 1.80:
		return "起手 · 世界还是平的"
	if t < HOLD_END:
		return "世界倾覆 %.0f°" % _tilt(t)
	if t < RESTORE_END:
		return "世界立回来"
	return "海面在下面"
