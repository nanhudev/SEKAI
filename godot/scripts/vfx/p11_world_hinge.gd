extends "res://scripts/vfx/vfx_prototype.gd"
#
# 11 · 天地合页 / WORLD HINGE
#
# =============================================================================
# THE CLAIM
# =============================================================================
#
# Not the sky rotating and not the ground flipping. A BOOK. A very long, very
# bright, very straight line appears across the world and becomes the SPINE, and
# then the two things this world is made of — the earth and the sky — close along
# it like two pages. The angle between them runs 180° -> 120° -> 90° -> 45° -> 10°,
# which is the brief's own sequence, and it is the only number that matters here
# because it is the one the viewer can read off the screen.
#
# =============================================================================
# HOW THE GEOMETRY ACTUALLY WORKS, AND WHY IT IS A CLAMSHELL
# =============================================================================
#
# The tempting implementation is "rotate the ground up and the sky down about a
# line". It cannot work, and the reason is worth writing down because it is a
# mistake that takes an hour to find and looks like a bug in the maths:
#
#   Two PARALLEL planes hinged on one axis can never be brought into coincidence
#   by rotating them about that axis. Rotate the ground plane and the sky plane
#   toward each other and they stay parallel, separated by the same distance,
#   forever. There is no angle at which they meet.
#
# What closes is a CLAMSHELL: two HALF-planes that share the hinge EDGE, start
# coplanar and 180° apart, and rotate toward each other. The earth is the
# half-plane in front (-Z); the sky is the half-plane behind (+Z); the hinge is
# the line where they meet. Both rotate UP, by +θ and -θ, and at θ = 90° they
# are the same half-plane standing vertically above the hinge. That is the page
# closing, and it is exact rather than approximate.
#
# So: θ = 90° - angle/2. The brief's 180°->120°->90°->45°->10° is θ =
# 0°->30°->45°->67.5°->85°, which is the sequence the keyframes below use.
#
# THE PAGES HAVE TO BE CUT, NOT TILTED. This is the correction the second pass
# paid for. `lab.split_world()` cuts the terrain, the road and the props into two
# halves on the hinge line, and the reason is in that function's own header: a
# terrain whose MIDDLE sits on the hinge pivots about a line inside itself, so the
# eye sees ground on both sides of the line, and a line with ground on both sides
# is a ridge. A ridge is "the world tilted". It took a still frame of exactly that
# to see the difference.
#
# =============================================================================
# THE SKY PAGE IS A PAGE, NOT THE SKY
# =============================================================================
#
# The real dome stays where it is and never rotates: it is the backdrop. The thing
# that closes is a sheet carrying its own clouds, its own moon and its own hills,
# sitting ON the back half of the world at 22m — high enough that the ground's own
# hills (which reach about 20m) never poke through it — so that when it has come
# over the top the viewer sees `山在头顶`, which the brief asks for and which a
# rotating dome could never show, because a dome has no underside.
#
# =============================================================================
# THE CAMERA, AND THE ONE CONSTRAINT NOBODY GUESSES
# =============================================================================
#
# The hero read is an open book seen from above: two half-planes meeting at the
# line, one carrying the road and the buildings, one carrying the clouds. That
# needs the camera to be on the OUTSIDE of both pages, and the pages lean TOWARD
# the camera's side of the world as they close, so "outside both" is a moving
# constraint:
#
#   the sky page's plane has normal (0, cosθ, -sinθ), so being above it means
#   y > z·tanθ  —  and tanθ runs away as the book shuts (tan85° = 11.4).
#
# Which is why the camera does not simply back off: it RISES AND CLOSES IN, from
# (0, 380, 300) at 90° to (0, 700, 46) at 10°, staying a few tens of metres above
# a plane that is going vertical underneath it. The alternative — backing off —
# puts the camera inside the wedge, and inside the wedge one page always hides
# the other and the frame reads as a wall.
#
# The last beat is the brief's own: 完全闭上后只剩一条线. At 10° the pages are 5°
# off vertical and the camera is almost directly over the hinge, so both pages are
# seen nearly edge-on and the picture is a bright line and a dark world. That is
# the only frame in the clip that is allowed to be almost empty, and it is 0.6s.

## The angle between the two pages, and when. The brief's five numbers as five
## keyframes. Read down the first column: this is the whole beat structure.
const ANGLE_KEYS := [
	[2.20, 180.0],
	[3.30, 120.0],
	[4.20, 90.0],
	[5.30, 45.0],
	[6.20, 10.0],
]
const CLOSE_END := 6.20
const CLOSED_HOLD_END := 7.10
const REOPEN_END := 7.80
const VANISH_AT := 7.80
const RETURN_END := 9.30

const HINGE_SPAN := 1500.0
const THICK_MIN := 0.03
## The spine's on-screen thickness is held roughly constant by scaling its cross
## section with the distance to the camera. A 0.14m bar is 50 pixels wide at 4m
## and is not on the screen at all at 700m, and the clip uses both extremes.
const THICK_PER_M := 0.0026

## Where the world is cut, and therefore where the spine is.
const HINGE_Z := -10.0
## How far in front of the spine the player stands. Small on purpose: the spine
## has to be IN the first-person frame, and the only way a line on the ground four
## metres away is in frame is if the eye is roughly level and the frame is wide.
const FOOT_Z := -6.0
## The sky page: width, depth, and how high above the page's own ground it sits.
const SHEET_W := 900.0
const SHEET_D := 430.0
const SHEET_LIFT := 22.0
## The sheet's inner edge starts BEHIND the spine, so at rest no part of it is in
## front of the player — the page is behind them and above them until it moves.
## It starts well behind, because the 22m lift swings the inner edge (lift·sinθ)
## toward -Z as the page comes up: at 45° that is 15m of sheet hanging over the
## earth page, and at 90° it is 22m. Ninety metres of inset pays for all of it.
const SHEET_INSET := 90.0

## The earth page's own depth: half of `TERRAIN_EXTENT`, because the spine cuts the
## terrain in the middle. Every hero-camera number is derived from this rather than
## typed, so the framing survives a change of world size.
const PAGE_DEEP := 380.0
## Hero vantage: how high, how far onto the earth page's side, and how high again
## once the book is shut.
const HERO_Y := 700.0
const HERO_PULL := 50.0
const FOV_HERO := 60.0
## When the climb is finished. The 90° keyframe is at 4.20s, so arriving a little
## before it means the book is already framed when it is most open.
const HERO_AT := 4.10
## How far past the spine the hero camera aims. Positive puts the aim point on the
## SKY page's side, which is what decides which page is at the top of the frame:
## tilting toward +Z makes screen-up +Z, so the sky is above and the earth below.
## Aiming at the spine itself gives a 50/50 split with the line dead centre, which
## is a flat composition — the 40 metres lift the line into the upper third.
const HERO_AIM_PAST := 40.0

var earth: Node3D
var sky_page: Node3D
var hinge_z := HINGE_Z
var hinge_line: MeshInstance3D
var hinge_mat: ShaderMaterial
var cloud_mats: Array = []
var vanish: Array = []


func build() -> void:
	super()
	t_end = 10.8
	lab.set_sky("dusk")
	# The sun is dimmed but not moved: the drama has to be the fold and not a
	# sunset, and a light that swung during the fold would relight the whole world
	# and hide the thing being shown.
	lab.sun.light_energy = 0.95
	# The player's greybox body is not used this round — every shot in this clip is
	# either first person (where it is inside the camera) or from far enough away
	# that a 1.7m figure is a smudge. Leaving it in makes the overhead frames say
	# "there is a person on that page", which is not the sentence.
	lab.player_proxy.visible = false

	var split: Dictionary = lab.split_world(HINGE_Z)
	earth = split["front"] as Node3D
	hinge_z = float(split["z"])
	lab.set_sky("dusk")

	_build_sky_page(split["back"] as Node3D)
	_build_hinge_line()


## THE SKY PAGE. Hung on the back half's own pivot, so it is carried by the same
## rotation that carries the ground behind the player — one node, one angle, and
## the two never disagree.
func _build_sky_page(back: Node3D) -> void:
	sky_page = back

	# NO SOLID BACKING UNDER THE CLOUDS. The first version had an opaque sheet and
	# it was the bug that made this clip unreadable: an opaque page lying on the
	# ground is an opaque floor laid over the world the clip is supposed to be
	# folding. `inner_fade` plus a page that starts behind the player is the fix,
	# and the backing is simply gone.
	#
	# Three cloud layers at three scales and three alphas. One layer reads as a
	# texture; three read as DEPTH, which is what makes the page a place rather
	# than a panel — and when the page has come over the top, the layering is the
	# only thing that stops it from being a blue rectangle.
	for spec in [
		[Color(0.230, 0.270, 0.385), Color(0.120, 0.150, 0.235), 1.00, 2.4, 2.9],
		[Color(0.380, 0.425, 0.545), Color(0.200, 0.240, 0.345), 0.70, 5.4, 1.9],
		[Color(0.585, 0.625, 0.720), Color(0.330, 0.375, 0.480), 0.40, 11.0, 1.4],
	]:
		var s: Array = spec
		var mat: ShaderMaterial = lab.cloud_mat(s[0], s[1], float(s[2]), float(s[3]), 0.0, 0.0)
		# A PAGE HAS TO BE OPAQUE. The shader's whole design is a band you can
		# almost see through — correct for a cloud and wrong for a page of the
		# world, because a hole in the sky page is a hole through which the dome
		# shows, and the first pass's 45° still had a black band across it exactly
		# where the sheet's noise happened to be thin. The base layer is pushed to
		# full density; the two detail layers keep the soft alpha they want.
		mat.set_shader_parameter("contrast", float(s[4]))
		# The near edge fades: the page's inner edge is close to the camera and
		# must not be visible as a straight seam while the page is still low.
		mat.set_shader_parameter("inner_fade", 0.05)
		cloud_mats.append(mat)
		var layer := _plane(SHEET_W, SHEET_D, mat)
		layer.position = Vector3(
			0.0, SHEET_LIFT + 1.8 * float(cloud_mats.size() - 1),
			# A child of the back pivot, so local +Z is measured from the spine.
			SHEET_INSET + SHEET_D * 0.5)
		back.add_child(layer)

	# THE MOON AND THE MOUNTAINS, ON THE PAGE. These are what convert the sheet
	# from "a blue plane" into "the sky", and they are what the viewer sees
	# overhead once the page has come over the top.
	var moon_mat := StandardMaterial3D.new()
	moon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	moon_mat.albedo_color = Color(0.88, 0.89, 0.84)
	moon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var moon := _disc(46.0, moon_mat)
	moon.position = Vector3(-190.0, SHEET_LIFT + 3.0, 300.0 + SHEET_INSET)
	back.add_child(moon)

	# NO HILLS ON THE SKY PAGE, AND NO HILLS ON THE EARTH PAGE EITHER.
	#
	# The mountains were the right idea and the wrong geometry, and the 45° still
	# is what settled it: a folded page is a NEAR-VERTICAL sheet, so everything on
	# it ends up a few hundred metres under a camera that is 700m up — a 300m hill
	# four hundred metres away covers a third of the picture and reads as a rock
	# in the lens, not as a landmark. The distant range also belongs to the world
	# BEYOND the page (it stands at 420-760m out, past the terrain's own 380m), so
	# a hill that came up with the fold was never part of the page to begin with.
	#
	# So the claim is carried by the two surfaces themselves: the road, the village
	# and the terrain's own roll on one page, cloud and moon on the other. `山在头顶`
	# was an embellishment of mine and it does not survive the camera.
	for e in lab.group("hill"):
		(e["node"] as Node3D).visible = false


## The back pivot's own origin sits at the hinge, so a child's local +Z is already
## measured from the spine.
func _build_hinge_line() -> void:
	# THE SPINE. It is drawn before anything folds, grows from the middle outward,
	# and stays the brightest thing in the frame for the whole clip — because it is
	# the only element that explains what the two pages are closing AGAINST.
	hinge_mat = lab.glow_mat(Color(0.74, 0.87, 1.00), 3.2, 0.0, 0.0)
	hinge_line = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(HINGE_SPAN, THICK_MIN, THICK_MIN)
	hinge_line.mesh = mesh
	hinge_line.material_override = hinge_mat
	hinge_line.position = Vector3(0.0, 0.05, 0.0)
	hinge_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# It is a child of the EARTH page, on the hinge line itself. A point on the
	# hinge does not move when the page rotates, so the spine stays exactly where
	# the two pages meet no matter which page carries it — and the fold's own edges
	# are what it has to line up with.
	earth.add_child(hinge_line)


func _plane(w: float, h: float, mat: Material) -> MeshInstance3D:
	var m := PlaneMesh.new()
	m.size = Vector2(w, h)
	m.subdivide_width = 1
	m.subdivide_depth = 1
	var node := MeshInstance3D.new()
	node.mesh = m
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _disc(radius: float, mat: Material) -> MeshInstance3D:
	# A FLAT CYLINDER, NOT A SQUASHED SPHERE. The moon sits on the sky page with its
	# face along the page's normal (the cylinder's own axis), so it is a full disc
	# when the page is flat and still a full disc when the page has come over the
	# top. A squashed sphere would be seen edge-on at exactly the moment it matters.
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = 1.4
	m.radial_segments = 28
	var node := MeshInstance3D.new()
	node.mesh = m
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _dome(width: float, height: float) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = width * 0.5
	m.height = height
	m.radial_segments = 16
	m.rings = 8
	var node := MeshInstance3D.new()
	node.mesh = m
	node.material_override = null
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


# =============================================================================
# TIME
# =============================================================================

## The angle between the two pages, in degrees, at time `t`.
func page_angle(t: float) -> float:
	if t <= float(ANGLE_KEYS[0][0]):
		return 180.0
	for i in ANGLE_KEYS.size() - 1:
		var a: Array = ANGLE_KEYS[i]
		var b: Array = ANGLE_KEYS[i + 1]
		if t <= float(b[0]):
			var u := ease_in_out(span(t, float(a[0]), float(b[0])))
			return lerpf(float(a[1]), float(b[1]), u)
	if t <= CLOSED_HOLD_END:
		return 10.0
	if t <= REOPEN_END:
		# Opening is deliberately much faster than closing. The close is the
		# ceremony; the open is the RECEIPT, and a receipt that takes as long as
		# the thing it is a receipt for reads as a second ceremony.
		var u := ease_in_out(span(t, CLOSED_HOLD_END, REOPEN_END))
		return lerpf(10.0, 180.0, u)
	return 180.0


## θ: how far each page has rotated about the hinge, in degrees.
func theta_of(angle_deg: float) -> float:
	return 90.0 - angle_deg * 0.5


func theta(t: float) -> float:
	return theta_of(page_angle(t))


func apply(t: float) -> void:
	var th := deg_to_rad(theta(t))
	earth.rotation = Vector3(th, 0.0, 0.0)
	if sky_page != null:
		sky_page.rotation = Vector3(-th, 0.0, 0.0)

	# The spine grows outward from the middle: at t=0 it is not there, and by the
	# time anything folds it runs past both edges of the frame.
	var drawn := ease_out_cubic(span(t, 0.25, 1.80))
	hinge_line.visible = drawn > 0.01
	hinge_line.scale.x = maxf(drawn, 0.001)

	# The world darkens as the book shuts, so the closed frame is a bright line in
	# a dark picture rather than a bright line in a normal dusk. This is the whole
	# of "完全闭上后只剩一条线": the line is not made brighter, everything else is
	# made to go away.
	var shut := ease_in_out(span(t, 4.6, CLOSE_END))
	var reopen := ease_in_out(span(t, CLOSED_HOLD_END, REOPEN_END + 0.9))
	var dark := lerpf(1.0, 0.14, shut)
	dark = lerpf(dark, 1.0, reopen)
	lab.sky_material().set_shader_parameter("energy", 1.05 * dark)
	lab.sun.light_energy = 0.95 * dark

	# It brightens as the pages approach, so the last few degrees have a light on
	# them and the closed frame is not an empty one.
	var nearing := 1.0 - clampf(page_angle(t) / 180.0, 0.0, 1.0)
	hinge_mat.set_shader_parameter("intensity", 2.8 + nearing * 4.6)
	hinge_mat.set_shader_parameter("travel", fmod(t * 0.30, 1.0))
	hinge_mat.set_shader_parameter("travel_width", 0.32)

	# The clouds drift the whole time, faster as the page closes, so the sheet is
	# never a still image and the fold is read against something moving.
	var fold := ease_in_out(span(t, 1.0, 3.2))
	for i in cloud_mats.size():
		var m: ShaderMaterial = cloud_mats[i]
		var rate := 0.030 + 0.020 * float(i)
		m.set_shader_parameter("drift", Vector2(t * rate, t * rate * 0.35))
		m.set_shader_parameter("inner_fade", lerpf(0.05, 0.008, fold))

	_hide_target_area(t)
	# The player's own blade is on the camera, so it is in frame for every shot
	# including the ones taken from 600m up — where a 1m blade is a white bar the
	# size of a building. It is hidden exactly while the camera is not the eye.
	lab.weapon_root.visible = t < 2.85 or t > t_end - 1.25
	_camera(t)
	_spine_thickness()


## The spine's cross section, sized so it is about three pixels wide from wherever
## the camera happens to be. Read off the camera the prototype just set, so it is
## a function of `t` like everything else.
func _spine_thickness() -> void:
	var eye: Vector3 = lab.cam_eye
	var dist := eye.distance_to(Vector3(0.0, 0.0, hinge_z))
	var thick := clampf(dist * THICK_PER_M, THICK_MIN, 2.0)
	var s := thick / THICK_MIN
	hinge_line.scale.y = s
	hinge_line.scale.z = s


## THE THING THAT STAYS GONE.
##
## The brief asks for the closed book to reopen onto a world the target area has
## been removed from — "目标区域消失，只剩玩家". A handful of props that stood in the
## fold are hidden at the moment of the reopen and NOT brought back. It is the only
## permanent consequence in the clip, and it is what separates "a world was folded
## and unfolded" from "a world was folded and something was taken".
func _hide_target_area(t: float) -> void:
	if t < VANISH_AT:
		return
	if vanish.is_empty():
		for entry in lab.group("crate"):
			var p: Vector3 = (entry["home_pos"] as Vector3)
			if p.z < hinge_z - 2.0 and p.z > hinge_z - 40.0 and absf(p.x) < 15.0:
				vanish.append(entry["node"])
		vanish.append(lab.target)
		print("  天地合页: %d props removed from the folded region" % vanish.size())
	for node in vanish:
		if is_instance_valid(node):
			(node as Node3D).visible = false


func _camera(t: float) -> void:
	var foot := Vector3(0.34, lab.ground_height(0.34, FOOT_Z) + 1.74, FOOT_Z)
	var foot_look := Vector3(0.0, 2.10, FOOT_Z - 30.0)

	# WHERE THE LENS HAS TO BE, AND THE TWO NUMBERS THAT DECIDE IT.
	#
	# The earth page and the sky page lean AWAY from each other as they close, so
	# there is no position in front of or behind the spine that sees both faces at
	# once — each one's face points into the other's region, and whichever page is
	# nearer hides the far one. That is measured, not assumed: the 45° still taken
	# from behind the hinge came back as a wall of cloud, and the one from in front
	# as a blue dome behind a dark band.
	#
	# Directly above the spine is the only place both pages are below the lens, and
	# the altitude is then fixed by the FOV, because a page five degrees off
	# vertical is a band whose width is (page depth)·cos(page angle):
	#
	#   at 45° between the pages the earth page leans 67.5° and spans 19° of view;
	#   the sky sheet leans the other way and spans another 29°;
	#   at 10° between the pages both collapse into the same 2½ degrees.
	#
	# 700m up with a 60° lens holds all of that with room to spare, and it is why
	# the camera does NOT keep climbing: the `只剩一条线` frame is not achieved by
	# getting above the pages, it is achieved by the pages themselves going
	# vertical. The lens only has to stay still and wide enough.
	var hero_eye := Vector3(0.0, HERO_Y, hinge_z - HERO_PULL)
	var look_hero := Vector3(0.0, 0.0, hinge_z + HERO_AIM_PAST)

	var eye := foot
	var look := foot_look
	var fov := 70.0

	if t < HERO_AT:
		if t < 2.85:
			# A small living drift, so a camera that is about to be left behind
			# does not read as a locked-off plate.
			eye += Vector3(sin(t * 0.62) * 0.13, sin(t * 0.44) * 0.03, 0.0)
		else:
			var u := ease_out_cubic(span(t, 2.85, HERO_AT))
			eye = foot.lerp(hero_eye, u)
			look = foot_look.lerp(look_hero, u)
			fov = lerpf(70.0, FOV_HERO, u)
	elif t < RETURN_END:
		eye = hero_eye + Vector3(sin(t * 0.55) * 5.0, sin(t * 0.38) * 3.0, 0.0)
		look = look_hero
		fov = FOV_HERO
	else:
		var u := ease_in_out(span(t, RETURN_END, t_end - 0.9))
		eye = hero_eye.lerp(foot, u)
		look = look_hero.lerp(foot_look, u)
		fov = lerpf(FOV_HERO, 72.0, u)

	camera(eye, look, fov, sin(t * 0.37) * 0.008)


func phase_name(t: float) -> String:
	if t < 2.20:
		return "起手 · 合页线亮起"
	if t < CLOSE_END:
		return "天地闭合 %.0f°" % page_angle(t)
	if t < CLOSED_HOLD_END:
		return "闭合 10° · 只剩一条线"
	if t < REOPEN_END:
		return "重新打开"
	if t < RETURN_END:
		return "落回世界"
	return "目标区域消失 · 只剩玩家"
