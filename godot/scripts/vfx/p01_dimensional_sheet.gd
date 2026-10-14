extends "res://scripts/vfx/vfx_prototype.gd"
#
# 01 · 二相簿 / DIMENSIONAL SHEET
#
# =============================================================================
# THE CLAIM
# =============================================================================
#
# The world loses its THIRD DIMENSION. Not "the world gets a filter" and not "the
# camera goes 2D" — every surface loses its DEPTH. A village of solid boxes becomes
# a row of flat cut-outs standing two centimetres off a sheet of terrain; the road
# becomes a stripe that is no longer a road to anywhere; the ground you were
# standing on is no longer under you. And the player does not go with it. The
# player's own body and the player's blade keep their volume, which is the only
# reason the frame says "the WORLD became two-dimensional" instead of "the renderer
# broke".
#
# =============================================================================
# WHY THE FLATTEN IS IN THE VERTEX SHADER
# =============================================================================
#
# `vfx_prop.gdshader` flattens by multiplying each vertex's distance to a plane by
# `flatten_squash` instead of deleting it. It is in `vertex()` and not in the
# fragment shader because the claim is about GEOMETRY: a normal-mapped flat box is
# still a box, and the moment the camera moves it gives itself away. Here the
# triangles genuinely degenerate, so there is nothing left to give anything away.
#
# The plane is a parameter of the WORLD (`flatten_origin` in world space, not in
# any object's local frame), which is what makes ONE plane take the whole world at
# once — a building rotated by its own transform flattens onto the same sheet as
# its neighbour.
#
# TWO THINGS HAD TO BE FIXED BEFORE THIS READ, AND BOTH ARE IN THE SHADER NOW:
#
#   · `flatten_squash = 0.022` instead of 0. Collapsing exactly onto the plane put
#     the terrain sheet and the buildings standing on it at the same z, and the
#     village came back as z-fighting stripes. Leaving 2 % of the depth turns the
#     world into a WAFER: cards ~2 cm thick, ordered by their original distance,
#     which is both legible and stable.
#   · `flatten_flat_light = 1`. With the world's own normals kept, a squashed
#     village is a village that has been squashed — every face still catches its
#     own light and the eye reads perspective compression, not dimension loss.
#     One normal for the whole sheet is what a printed sheet does.
#
# =============================================================================
# THE PLANE HAS TO BE IN FRONT, AND THAT WAS THE FIRST PASS'S BUG
# =============================================================================
#
# The first version put the plane at +35 m — BEHIND the player, who faces the
# village down the road at negative z. So the world collapsed behind the lens and
# the sweep still came back as a beautiful empty sky. The plane is now beyond the
# village (`-62 m`), which is the direction the player is actually looking, so the
# world collapses INTO THE FRAME.
#
# The far range is hidden for the length of the clip. A 380 m hill 400 m out, put
# on a plane 60 m away, is a 380 m wall 60 m away: depth is what made it small and
# depth is the thing being removed. A two-dimensional world is allowed to be a
# small world.
#
# =============================================================================
# THE RECEIPT
# =============================================================================
#
# The world pings back and the target does not. After the restore the target is
# still a card, standing slightly off the ground where nothing else is, and the
# last shot is a close oblique on it — because "the world came back and this did
# not" is the difference between a thing that happened and a thing that was done
# to the world, and a clip that ends with the world exactly as it started has
# spent eleven seconds to say nothing.

## The sheet. Beyond the village, on the side the player is facing.
const FLATTEN_NEAR := -46.0
const FLATTEN_FAR := -170.0
## The fraction of depth that survives at full flatten. See the header. Large
## enough that a box keeps a recognisable front face and a few centimetres of
## side, small enough that the village is unmistakably a wafer.
const SQUASH := 0.045

const SWEEP_START := 1.60
const SWEEP_END := 3.40
const HERO_CLOSE_END := 5.60
const HERO_WIDE_END := 7.20
const RESTORE_START := 8.40
const RESTORE_END := 9.70

## Where the player stands, and the 3D figure that has to stay 3D.
const PLAYER_AT := Vector3(-3.0, 0.0, -2.0)

var exempt: Array = []
var target_mats: Array = []
var hills: Array = []
var plane_z := FLATTEN_NEAR
var rim: MeshInstance3D
var rim_mat: ShaderMaterial


func build() -> void:
	super()
	t_end = 11.0
	lab.set_sky("day")
	lab.sun.light_energy = 1.20

	# THE VOID UNDERNEATH, PREPARED IN ADVANCE. The sky dome's own ground colour is
	# the only thing that can show below the sheet once the terrain is no longer
	# there, and the day preset's is a grey-blue that reads as haze — i.e. as
	# ground. Near-black makes it read as absence, and the reveal is a bonus: the
	# darkness is already loaded at t = 0 and the terrain hides it until the
	# instant the terrain goes flat.
	lab.sky_material().set_shader_parameter("ground_color", Color(0.018, 0.021, 0.030))

	# HILLS OUT. See the header.
	var hid := 0
	for e in lab.group("hill"):
		(e["node"] as Node3D).visible = false
		hills.append(e["node"])
		hid += 1
	print("二相簿: %d far masses hidden (a two-dimensional world has no range)" % hid)

	# THE ONE THING THE RULE DOES NOT REACH, collected before the first `apply` so
	# a frame can never be rendered with the exemption missing.
	exempt = lab.materials_under(lab.player_proxy)
	target_mats = lab.materials_under(lab.target)

	lab.player_proxy.global_position = Vector3(
		PLAYER_AT.x, lab.ground_height(PLAYER_AT.x, PLAYER_AT.z), PLAYER_AT.z)
	lab.player_proxy.rotation_degrees = Vector3(0.0, 184.0, 0.0)

	# THE SHEET'S EDGE. A hairline drawn where the flattened world stops being
	# the ground and starts being a thing — the bottom of the wafer. Without it
	# the sheet's lower boundary is a colour step against the void and reads as a
	# horizon rather than as an edge.
	rim_mat = lab.glow_mat(Color(0.68, 0.84, 1.00), 1.1, 0.0, 0.0)
	rim_mat.set_shader_parameter("alpha", 0.0)
	rim = MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(760.0, 0.06, 0.06)
	rim.mesh = rm
	rim.material_override = rim_mat
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(rim)


func apply(t: float) -> void:
	var u := ease_in_out(span(t, SWEEP_START, SWEEP_END))
	# The restore is deliberately faster than the press and snaps rather than
	# eases out of flat: a world that pings back has a spring in it, and a world
	# that eases back reads as a dissolve being turned down.
	var back := ease_out_cubic(span(t, RESTORE_START, RESTORE_END))
	var flat := u * (1.0 - back)
	# The plane travels in and stays: it is the plane's POSITION that makes the
	# sheet arrive rather than the world silently becoming thin where it stands.
	# It does not travel back out, because at `flat = 0` the plane has no effect
	# at all — `depth_left` is 1 and the projection is the identity — so a return
	# journey would be eleven seconds of animation with nothing in it. Holding it
	# at the near position is also what keeps the target's card where the village
	# is for the receipt shot.
	plane_z = lerpf(FLATTEN_FAR, FLATTEN_NEAR, u)

	lab.broadcast("flatten_origin", Vector3(0.0, 0.0, plane_z))
	lab.broadcast("flatten_normal", Vector3(0.0, 0.0, 1.0))
	lab.broadcast("flatten_squash", SQUASH)
	lab.broadcast("flatten_flat_light", 1.0)
	lab.broadcast("flatten", flat)
	lab.broadcast("flatten_glow", flat * 0.55)

	# THE EXEMPTIONS, RE-ASSERTED EVERY FRAME. The broadcast above runs over the
	# exempt materials too — they are ordinary world materials — so they are
	# written back to solid here, and the order matters.
	for m in exempt:
		(m as ShaderMaterial).set_shader_parameter("flatten", 0.0)
	for m in target_mats:
		# THE THING THAT STAYS FLAT. After the world has come back, the target is
		# still a cut-out.
		(m as ShaderMaterial).set_shader_parameter("flatten", 1.0 if t > RESTORE_END else flat)

	# The sheet's lower edge, tracking the wafer's actual bottom. The wafer's
	# bottom in y is the terrain's own lowest profile `0.020 * z` sampled at its
	# deepest z within the corridor; -8.4 is that number, and it is derived from
	# `ground_height` rather than guessed.
	rim.visible = flat > 0.02
	rim.position = Vector3(0.0, -8.4, plane_z)
	rim_mat.set_shader_parameter("alpha", clampf(flat * 1.3, 0.0, 1.0) * 0.75)

	# The blade is on camera for the first-person beats and hidden for the two
	# external ones.
	lab.weapon_root.visible = t < SWEEP_END + 0.35 or t > HERO_WIDE_END
	_camera(t)
	_weapon(t)


func _camera(t: float) -> void:
	if t < SWEEP_END + 0.30:
		# FIRST PERSON. Level, on the road, looking at the village — which is where
		# the compression arrives from and therefore where it reads. This frame has
		# to look completely NORMAL until 1.60 s or the reveal has nothing to
		# reveal against.
		lab.review_off()
		lab.player_proxy.visible = false
		var eye := Vector3(PLAYER_AT.x + 0.30, 0.0, PLAYER_AT.z)
		eye.y = lab.ground_height(eye.x, eye.z) + 1.72
		# A small push in as the sheet closes, so it ends closer than the shot
		# started.
		eye.z += -3.2 * ease_in_out(span(t, SWEEP_START, SWEEP_END))
		eye += Vector3(sin(t * 0.71) * 0.10, sin(t * 0.53) * 0.03, 0.0)
		camera(eye, Vector3(0.6, 2.4, -54.0), 68.0, sin(t * 0.41) * 0.010)
		return

	if t < HERO_CLOSE_END:
		# THE HERO FRAME OF 01 IS AN EXTERNAL ONE, and the brief says so: "the
		# player is still 3D and the world is not" is a statement about a
		# RELATIONSHIP, and a first-person camera cannot show a relationship it is
		# standing inside.
		#
		# Close, just behind and to the side of the figure, so what is being
		# compared is at the same scale in the same frame: a body with volume in
		# the near ground and a printed sheet 60 m past it.
		lab.review_off()
		lab.player_proxy.visible = true
		# SETTLED BY 4.30, THEN MOTIONLESS. The brief's most important beat is the
		# hero hold — one frame you can pause on and still explain — and V1 had
		# none: the camera was in motion from 3.7 s through 7.2 s, so this clip
		# never had a single frame that WAS the statement. 4.30-5.60 is now static.
		var h1 := ease_in_out(span(t, SWEEP_END + 0.30, 4.30))
		var e1 := Vector3(-7.4, 2.55, 4.6).lerp(Vector3(-6.2, 2.35, 2.4), h1)
		camera(e1, Vector3(-2.2, 1.75, -26.0), 44.0, 0.0)
		return

	if t < HERO_WIDE_END:
		# THE OBLIQUE. 46 degrees off the sheet's normal, which is the only angle
		# at which the cards show their EDGES: face-on, a cut-out and a solid box
		# are the same picture, which is exactly why the previous pass's hero frame
		# was not evidence of anything.
		lab.review_off()
		lab.player_proxy.visible = true
		# Also held: reaching the oblique by 6.30 and then still until 7.20 gives
		# the second half of the hold, because face-on the cards hide their edges
		# and the oblique is where a wafer looks like a wafer.
		var h2 := ease_in_out(span(t, HERO_CLOSE_END, 6.30))
		var e2 := Vector3(22.0, 4.0, 2.0).lerp(Vector3(32.0, 5.4, -2.0), h2)
		# AIMED SO THE FIGURE STAYS IN THE PICTURE. The oblique views the sheet from
		# ~55° off its normal (the only angle at which a wafer shows its edges), and
		# the first placement of it looked so far along +x that the player fell off
		# the left of the frame — which quietly deleted the comparison the shot
		# exists to make. Holding the aim nearer the player keeps them at the frame's
		# left edge, small, still standing, still solid.
		var aim2 := Vector3(-6.0, 2.2, -26.0).lerp(Vector3(-11.0, 2.6, -34.0), h2)
		camera(e2, aim2, lerpf(58.0, 52.0, h2), 0.0)
		return

	if t < RESTORE_END + 0.10:
		# BACK TO THE PLAYER'S EYE as the world pings open, so the receipt and the
		# restore are one movement and the last thing the first person sees is the
		# world reassembling in front of them.
		lab.review_off()
		lab.player_proxy.visible = false
		var e3 := Vector3(PLAYER_AT.x + 0.30, 0.0, PLAYER_AT.z - 3.2)
		e3.y = lab.ground_height(e3.x, e3.z) + 1.72
		camera(e3, Vector3(1.6, 2.2, -40.0), 66.0, sin(t * 0.37) * 0.008)
		return

	# THE RECEIPT. Down the road, on the axis, at the distance the target's card is
	# actually at — 0.7 m wide and 2.1 m tall, which is a sliver from five metres
	# away and unmistakable from sixteen. Everything around it is solid again.
	lab.review_off()
	lab.player_proxy.visible = false
	var target_z: float = plane_z + (lab.target.global_position.z - plane_z) * SQUASH
	var tx: float = lab.target.global_position.x
	var eye6 := Vector3(0.0, lab.ground_height(0.0, -30.0) + 2.00, -30.0)
	camera(eye6, Vector3(tx, 1.15, target_z), 30.0, 0.0)


## The blade, drawn and held out toward the sheet the way the cause describes it.
func _weapon(t: float) -> void:
	var up := ease_in_out(span(t, 0.30, 1.50)) * (1.0 - ease_in_out(span(t, RESTORE_START, RESTORE_END)))
	lab.weapon_blend(Vector3(0.34, -0.30, -0.66), Vector3(-70.0, -16.0, 4.0), 0.86, up)


func phase_name(t: float) -> String:
	if t < SWEEP_START:
		return "起手 · 举刀指向薄面"
	if t < SWEEP_END:
		return "塌陷中 %.0f%%" % (100.0 * ease_in_out(span(t, SWEEP_START, SWEEP_END)))
	if t < HERO_CLOSE_END:
		return "外侧 · 玩家仍然有体积"
	if t < HERO_WIDE_END:
		return "斜看 · 世界只有纸边"
	if t < RESTORE_END:
		return "世界弹回"
	return "目标留在了二维"
