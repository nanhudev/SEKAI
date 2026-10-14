extends SceneTree
##
## THE SAYA, PHOTOGRAPHED. (§39-A's missing half)
##
##   "/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --path F:/SEKAI/godot \
##     --resolution 1280x720 --audio-driver Dummy \
##     --script res://tools/saya_stillness_movie.gd -- <output_dir>
##
## Needs a REAL WINDOW. `--headless` disables rendering and this file only
## produces rendering.
##
## ===========================================================================
## WHY THIS FILE EXISTS AT ALL, WHEN `probe_saya_motion.gd` ALREADY PASSES
## ===========================================================================
##
## Because "刀鞘不要乱动" was answered with numbers, and numbers are not what the
## complaint was about. The probe proves the mouth travels 0.000 m during A1-A4
## and that no rendered frame shows more than 20 mm of it moving. What it cannot
## do is let anyone SEE it, and the one thing worse than an unverified fix is a
## fix that is only verified in a unit test. So this is the picture.
##
## ===========================================================================
## WHY THE CAMERA IS NOT THE PLAYER'S EYE
## ===========================================================================
##
## `sword_basic_v2_movie.gd` shoots from the eye and is right to: §35 says every
## beat has to stand up in first person before third-person work is time well
## spent. But the eye is the wrong instrument for THIS question, for two measured
## reasons:
##
##   1. The extraction runs along the saya's own axis, and that axis points
##      (-0.30, -0.73, 0.62) in camera space at the home beat — DOWN, BACK and
##      toward the player. A blade leaving a sheath along the view axis is the
##      one motion a first-person camera renders as "nothing much happened",
##      because the displacement is mostly in depth.
##
##   2. At 0.86 m in front of the eye the saya occupies the lower-left corner,
##      about 0.20 m of a 1.34 m wide frame. 0.21 m of wander is then 15% of the
##      screen — legible, but the objects are small and the reading is a guess.
##
## So the camera here is a node parented into the SAME FRAME AS THE WEAPON —
## `WeaponRoot`, which is the space `probe_saya_motion.gd` measures the mouth in.
## That is the whole design: the review camera and the instrument share a parent,
## so "the saya stands still" is the same claim in the picture as in the printout,
## and a frame in which the saya drifts is a frame in which the CAMERA did not
## drift with it.
##
## The player's own eye is still in the clip, as an inset, because the eye is
## where the sentence is authored for and a review clip that never shows it is
## answering a question nobody asked.
##
## ===========================================================================
## WHY THE FRAMING IS SOLVED AND NOT TYPED
## ===========================================================================
##
## The camera's distance and target are derived from the draw's OWN beat list —
## the blade's origin and tip and the saya's mouth and end, at every beat, read
## through `SwordBasic.equip()`. A hand-placed camera is a second copy of the
## choreography, and the day the draw is retuned the copy is silently wrong: the
## blade leaves the frame and the clip looks like a rendering fault. This one
## re-frames itself, and it prints what it solved for so a bad frame is a number.
##
## It also means the framing cannot flatter the result. A camera chosen by eye
## can be chosen to hide a 20 mm drift; one that has to contain the blade's whole
## travel cannot.
##
## ===========================================================================
## WHY THE VERDICT IS MEASURED IN THE SAME RUN
## ===========================================================================
##
## The outro prints the number the clip is about, and that number is computed
## here, from this take's own mouth track — not copied out of the probe's last
## log. A caption quoting a measurement from a different session is a claim about
## a build that may not be the one on screen, which is the failure mode the whole
## measurement discipline exists to prevent. A run in which the saya moves exits
## non-zero, so the clip can fail.
##
## Usage:
##   ... --script res://tools/saya_stillness_movie.gd -- <output_dir>

const STAGE_PATH := "res://scenes/combat/CombatSandbox.tscn"
const WEAPON_ROOT_PATH := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot"
const SHOTGUN_PATH := "CameraRig/LookPivot/MotionPivot/ShakePivot"

## `ForegroundWeaponLayer.WEAPON_LAYER`. Spelled out rather than read off the
## class because this file must keep working when the layer node is absent — a
## review tool that refuses to run because an overlay is missing is a review tool
## that gets skipped.
const WEAPON_LAYER := 1 << 19

const VIEW := Vector2i(1280, 720)
## The player's own eye, inset. Small on purpose: the eye is here to say WHERE
## the player is looking, not to be measured, and anything bigger starts
## covering the thing the clip is about.
const INSET := Vector2i(384, 216)
const INSET_PAD := 16
const INSET_BORDER := 2

## The eye's own field of view, so the inset is the frame the player lives in
## rather than a second, differently-framed camera.
const EYE_FOV := 75.0
const DETAIL_FOV := 40.0
## Room around the assembly's measured extent. 6% of a 2.2 m stage is 13 cm — a
## hand's width, enough that nothing touches the frame edge at the extremes of the
## draw and not enough to make the blade small.
const DETAIL_MARGIN := 1.06

## The same ceiling as the probe, so the clip's verdict and the probe's verdict
## are the same sentence. 20 mm of travel in one rendered frame is half the width
## of the saya's own body: visible by construction.
const JUMP_LIMIT := 0.020
const IDLE_DRIFT_LIMIT := 0.012
const SPEED_WINDOW := 0.030
const CAPTURE_FPS := 30

const SwordClasses := preload("res://scripts/weapons/sword_classes.gd")

# ===========================================================================
# THE CLOCKS AND THE CAMERA RIG, AS NODES
# ===========================================================================

## Copies the review rigs' transforms onto the viewport cameras, AFTER the pose
## they belong to has been written.
##
## WHY THIS IS A NODE AND NOT A LINE IN THE CAPTURE LOOP. A `SubViewport` camera
## cannot be a descendant of `WeaponRoot`: `Node3D.get_global_transform()` walks
## up through NODE-3D parents only, so a Camera3D parented to a SubViewport that
## is itself parented to WeaponRoot has WeaponRoot's chain cut out of it and
## renders from the origin. The rigid attachment therefore has to be copied, and
## a copy is only correct if it happens in the right ORDER.
##
## `process_priority = 1000` is that order: the combat controller writes the pose
## in `_process`, the viewport renders after every `_process` in the frame has
## run, and this node sits at the end of the queue. Copying in the capture loop
## instead would be a frame late — and a frame of the draw is 85 degrees of
## assembly rotation, which is a wobble in the one camera whose whole job is to
## hold still relative to the thing being judged.
class FrameSync extends Node:
	var pairs: Array = []   # [[source Node3D, camera Camera3D], ...]

	func _process(_delta: float) -> void:
		for pair in pairs:
			var from: Node3D = pair[0]
			var to: Camera3D = pair[1]
			if is_instance_valid(from) and is_instance_valid(to):
				to.global_transform = from.global_transform


## The engine's own delta, accumulated.
##
## NOT `Time.get_ticks_usec()` and not `root.get_process_delta_time()`. The probe
## learned this the expensive way: under a real-time capture loop the wall clock
## across an `await` produced three consecutive 3-4 m/s readings on a traverse
## the authored curve caps at 0.74 m/s, and step and dt came out INVERSELY
## correlated — the signature of a jittery clock, not a jumping object. This node
## receives the same `delta` the game does, and it is added to the tree last so
## its delta belongs to the pose it is measuring.
class FrameClock extends Node:
	var total := 0.0
	func _process(delta: float) -> void:
		total += delta


# ===========================================================================
# STATE
# ===========================================================================

var out_dir := ""
var frame_index := 0
var start_ms := 0
var sandbox: Node3D
var player: CharacterBody3D
var combat: CombatController
var manager: Node
var slot: WeaponSlot

var detail_vp: SubViewport
var detail_cam: Camera3D
var eye_vp: SubViewport
var eye_cam: Camera3D
var detail_marker: Node3D
var eye_marker: Node3D
var sync: FrameSync
var clock: FrameClock

var shot_label: Label
var caption_label: Label
var note_label: Label

var _stills: Array[Dictionary] = []
var _pending_still := ""
var _wanted_stills: Array[String] = []
var _written_stills: Array[String] = []

## The mouth's own track, one entry per captured frame. This is the evidence the
## outro's caption is built from.
var _samples: Array[Dictionary] = []
var _marks: Array[Dictionary] = []
var _last_total := 0.0
var _t := 0.0

var _fails: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path(
		"res://../.render/saya_stillness")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_clear_frames()

	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	Engine.max_fps = CAPTURE_FPS

	var packed: PackedScene = load(STAGE_PATH)
	sandbox = packed.instantiate()
	root.add_child(sandbox)
	await _warm(14)

	player = sandbox.get_node("Player")
	combat = player.get_node("CombatController")
	manager = player.get_node("WeaponManager")
	slot = player.get_node("WeaponSlot")
	var weapon_root: Node3D = player.get_node(WEAPON_ROOT_PATH)
	if combat.saya_rig == null or manager == null or weapon_root == null:
		print("FAIL: the sword line is not wired into this stage")
		quit(1)
		return

	_quiet_the_stage()
	_build_rigs(weapon_root)
	clock = FrameClock.new()
	clock.name = "MovieClock"
	root.add_child(clock)
	_last_total = clock.total

	print("window=%s  detail=%s  eye=%s  out=%s" % [root.size, VIEW, INSET, out_dir])
	start_ms = Time.get_ticks_msec()

	await _shot("THE SAYA · 刀鞘不要乱动", "Left: the sword and the sheath, seen from the weapon's own frame. Inset: the player's eye.", 1.5)
	await _take_idle()

	await _shot("PUT AWAY · 收刀", "The last beat of the draw, run backwards. Watch the mouth, not the blade.", 0.9)
	await _take_put_away()

	await _shot("DRAW · 拔刀 · 五拍", "Beat 1-4: ONE AXIS, pure translation. Beat 5: the wrist turns. The saya is held, not dragged.", 0.9)
	await _take_draw()

	await _shot("A1 · 小居合 · 右划", "The blade goes to the mouth and leaves again. The mouth does not move.", 0.9)
	await _take_beat(0, "a1_settle")

	await _shot("A2 · 左划上挑", "Same two anchors as A1, different exit. The mouth still does not move.", 0.9)
	await _take_beat(1, "a2_settle")

	await _shot("A3 · 小居合领域", "The blade comes home for real, three cuts, and leaves. The mouth is a fixity.", 0.9)
	await _take_beat(2, "a3_settle")

	await _shot("A4 · 周身优弧横斩", "270 degrees, one cut. The largest motion in the sentence, and the saya is still in it.", 0.9)
	await _take_beat(3, "a4_settle")

	await _shot("TO THE CHAIN · 换武器", "The blade goes home first. The seam the 128.9 mm teleport used to live in.", 0.9)
	await _take_switch_out()

	await _outro()

	var elapsed := float(Time.get_ticks_msec() - start_ms) / 1000.0
	var fps := float(frame_index) / maxf(elapsed, 0.001)
	print("frames=%d  wall=%.2fs  -> ENCODE_FPS=%.3f" % [frame_index, elapsed, fps])
	_write_fps(fps)

	_report()

	root.remove_child(sync)
	sync.free()
	root.remove_child(clock)
	clock.free()

	var missing: Array[String] = []
	for tag in _wanted_stills:
		if not _written_stills.has(tag):
			missing.append(tag)
	print("stills wanted=%d written=%d" % [_wanted_stills.size(), _written_stills.size()])
	if not missing.is_empty():
		push_error("stills missing: %s" % ", ".join(missing))
	if frame_index <= 0:
		push_error("no frames were captured at all")
	if frame_index <= 0 or not missing.is_empty() or not _fails.is_empty():
		print("FAIL: take is incomplete or the saya moved")
		quit(1)
		return
	print("PASS: %d frames, %d stills, in %s" % [
		frame_index, _written_stills.size(), out_dir])
	quit()


# ===========================================================================
#  THE RIGS
# ===========================================================================

## Takes the developer furniture off. The same list, and the same reasons, as
## `sword_basic_v2_movie.gd`: these are the lab talking to the person at the
## keyboard, and a clip about a scabbard should not be captioned with a key list.
##
## `ForegroundWeaponLayer` is NOT in the list here either, for a different reason
## than in the delivery take: this file never reads the root window's texture as
## its main image, so the layer only matters to the inset — and the inset is
## drawn by a camera of this file's own on the weapon's own render layer. The
## layer node itself is left alone.
func _quiet_the_stage() -> void:
	for ui_name in ["DeveloperPanel", "ParryDebugOverlay", "CombatHUD"]:
		var ui := sandbox.get_node_or_null(ui_name)
		if ui != null:
			ui.set("visible", false)
	var lab := sandbox.get_node_or_null("ChainLab")
	if lab != null and lab.has_method("set_legend_visible"):
		lab.call("set_legend_visible", false)
	var chain_dir := player.get_node_or_null("ChainDirector")
	if chain_dir != null:
		chain_dir.set("debug_readout", false)
	var key_row := manager.get_node_or_null("WeaponIndicator/Keys")
	if key_row != null:
		key_row.set("visible", false)
	# The arena's own wandering dummy is a second, unscripted subject.
	var stray := sandbox.get_node_or_null("TechnicalDummy") as Node3D
	if stray != null:
		stray.visible = false
		stray.set_process(false)
		stray.set_physics_process(false)


## Builds the detail camera, the eye inset camera, and the node that keeps the
## two of them welded to the frames they are reporting on.
func _build_rigs(weapon_root: Node3D) -> void:
	var plan := _plan_detail_camera()

	# The aim is SOLVED, not asked for. `Node3D.look_at_from_position()` is the
	# obvious call and it is a trap here: it reads its target in GLOBAL coordinates
	# and this node has to be set up before it is in the tree, so the target would
	# be interpreted in the wrong frame and the camera would end up looking at the
	# world origin from inside a transform it had not been given yet.
	# `Basis.looking_at()` is the same rotation and takes no position at all.
	var aim: Vector3 = plan["target"] - plan["position"]
	detail_marker = Node3D.new()
	detail_marker.name = "SayaReviewMarker"
	detail_marker.transform = Transform3D(
		Basis.looking_at(aim, Vector3.UP), plan["position"])
	weapon_root.add_child(detail_marker)

	detail_vp = SubViewport.new()
	detail_vp.name = "SayaDetailViewport"
	detail_vp.size = VIEW
	detail_vp.transparent_bg = false
	detail_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	detail_vp.handle_input_locally = false
	sandbox.add_child(detail_vp)
	detail_cam = Camera3D.new()
	detail_cam.name = "SayaDetailCamera"
	detail_cam.fov = DETAIL_FOV
	detail_cam.near = 0.03
	detail_cam.far = 60.0
	detail_cam.current = true
	# THE WEAPON'S OWN LAYER IS THE POINT. In the world tree the blade and the
	# saya are ordinary meshes that `ForegroundWeaponLayer` has moved onto a
	# private render layer so the world camera cannot see them. A camera that
	# does not include that bit photographs an empty stage and reports a clean
	# take, which is the worst possible failure: nothing was verified and every
	# line of output reads like success.
	detail_cam.cull_mask = 1 | WEAPON_LAYER
	detail_vp.add_child(detail_cam)

	eye_marker = Node3D.new()
	eye_marker.name = "EyeMarker"
	var shotgun: Node3D = player.get_node(SHOTGUN_PATH)
	shotgun.add_child(eye_marker)

	eye_vp = SubViewport.new()
	eye_vp.name = "SayaEyeViewport"
	eye_vp.size = INSET
	eye_vp.transparent_bg = false
	eye_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	eye_vp.handle_input_locally = false
	sandbox.add_child(eye_vp)
	eye_cam = Camera3D.new()
	eye_cam.name = "SayaEyeCamera"
	eye_cam.fov = EYE_FOV
	eye_cam.near = 0.03
	eye_cam.far = 400.0
	eye_cam.current = true
	# Same inclusion, so the inset contains the sword the player is holding.
	# Without it the inset would be a first-person view of a hand with no sword
	# in it — an artefact of the foreground layer that reads as a bug in the
	# clip. At this camera's distance from the assembly nothing can clip.
	eye_cam.cull_mask = 1 | WEAPON_LAYER
	eye_vp.add_child(eye_cam)

	sync = FrameSync.new()
	sync.name = "SayaFrameSync"
	sync.process_priority = 1000
	sync.pairs = [[detail_marker, detail_cam], [eye_marker, eye_cam]]
	root.add_child(sync)

	_build_overlay()

	print("")
	print("── the review frame, solved from the draw's own beats")
	print("   bore axis      (%+.3f, %+.3f, %+.3f)  at %.1f deg above horizontal" % [
		plan["bore"].x, plan["bore"].y, plan["bore"].z, plan["elevation_deg"]])
	print("   stage extent   %.3f m across the bore x %.3f m up" % [
		plan["extent_w"], plan["extent_h"]])
	print("   camera         %s  looking at %s  from %.3f m" % [
		_v3(plan["position"]), _v3(plan["target"]), plan["distance"]])


## Where the detail camera goes, derived from the choreography.
##
## The camera is placed PERPENDICULAR TO THE BORE with the world's own up as its
## up, so the blade's travel maps across the frame and the extraction cannot be
## hidden in depth. Roll is deliberately zero: a roll would be a second, unstated
## piece of framing on top of a question that is already about a transform, and
## the 17 degrees the carry sits above horizontal is information, not a mistake.
func _plan_detail_camera() -> Dictionary:
	var move := SwordBasic.equip()
	var blade := SwordClasses.blade_reach(SwordBasic.WEAPON_ID)
	var body := SwordClasses.saya_body_len(SwordBasic.WEAPON_ID)
	var points: Array[Vector3] = []
	for i in move.beat_times.size():
		var o: Vector3 = move.beat_positions[i]
		var tip := o + Basis.from_euler(move.beat_rotations[i]) * Vector3.UP * blade
		points.append(o)
		points.append(tip)
		var m: Vector3 = move.saya_positions[i]
		var butt := m + Basis.from_euler(move.saya_rotations[i]) * Vector3.UP * body
		points.append(m)
		points.append(butt)

	var bore: Vector3 = SwordBasic.NE_CARRY_DIR.normalized()
	# The bore, flattened onto the horizontal plane, is the camera's RIGHT. The
	# vertical component is left out of the BASIS and kept in the picture: the
	# blade then lies at the 17 degrees the brief authors it at, which is a fact
	# about the carry rather than a fact about the camera.
	var right := Vector3(bore.x, 0.0, bore.z).normalized()
	var up := Vector3.UP
	var back := right.cross(up)          # the camera's +Z; it looks along -back

	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		var flat := Vector2(p.dot(right), p.dot(up))
		lo = lo.min(flat)
		hi = hi.max(flat)
	var mean := Vector3.ZERO
	for p in points:
		mean += p
	mean /= float(points.size())
	# The target is the point on the plane through the mean whose camera-plane
	# coordinates are the MIDDLE OF THE EXTREMES. Not the mean itself: the mean is
	# the centre of mass of a beat list, and a draw's beat list is not symmetric —
	# two of its seven beats are the same point on purpose.
	var target := mean + right * ((lo.x + hi.x) * 0.5 - mean.dot(right)) \
		+ up * ((lo.y + hi.y) * 0.5 - mean.dot(up))

	# THE DISTANCE IS SOLVED AGAINST THE PROJECTION, NOT AGAINST A BOX.
	#
	# The first version framed the assembly's world AABB and asked how far back a
	# frame of that size needs to be. It is the obvious thing and it is wrong here,
	# because this assembly spans 2.17 m ACROSS and 0.6 m IN DEPTH: the extreme
	# point of the AABB is the scabbard's butt when the sword is home, which is the
	# FARTHEST point from the camera, and a far point projects small. Framed that
	# way the take put the blade in the upper right and filled a third of the
	# frame with empty floor.
	#
	# So each point is asked its own question. With the camera at `target + back*d`,
	# a point's view depth is `d - (p - target)·back`, so the constraint
	# `|lateral| <= k * depth` solves for `d` in one step, per point, exactly.
	var tan_half := tan(deg_to_rad(DETAIL_FOV * 0.5))
	var kx := tan_half * (float(VIEW.x) / float(VIEW.y))
	var ky := tan_half
	var distance := _solve_distance(points, target, right, up, back, kx, ky)

	# ...AND THEN IT IS CENTRED, WHICH THE DISTANCE ALONE DOES NOT DO.
	#
	# `distance` is the smallest frame that CONTAINS the assembly, and what it
	# contains is not the same as what it centres: this stage is the blade's tip
	# at Beat 5 reaching up and to the right, and the saya's butt at Beat 1
	# reaching down and to the left, at two different depths. Solving for the
	# smallest containing frame therefore leaves the subject high and right with a
	# third of the frame empty, which is what the first two takes looked like.
	#
	# Shifting the target and re-solving converges in a few rounds: moving the
	# target by `right * d` moves every point's lateral coordinate by `-d`, so the
	# correction is the midpoint of the projected extremes, scaled back out of
	# screen space. Three rounds take the residual under a pixel.
	for _round in 3:
		var lo_s := Vector2(INF, INF)
		var hi_s := Vector2(-INF, -INF)
		for p in points:
			var rel: Vector3 = p - target
			var depth := distance - rel.dot(back)
			if depth <= 0.02:
				continue
			var s := Vector2(rel.dot(right) / (kx * depth), rel.dot(up) / (ky * depth))
			lo_s = lo_s.min(s)
			hi_s = hi_s.max(s)
		var mid := (lo_s + hi_s) * 0.5
		target += right * (mid.x * kx * distance) + up * (mid.y * ky * distance)
		distance = _solve_distance(points, target, right, up, back, kx, ky)

	var position := target + back * distance
	return {
		"position": position,
		"target": target,
		"distance": distance,
		"extent_w": hi.x - lo.x,
		"extent_h": hi.y - lo.y,
		"bore": bore,
		"elevation_deg": rad_to_deg(asin(clampf(bore.y, -1.0, 1.0))),
	}


## The smallest camera distance at which every point projects inside the frame,
## solved per point rather than from a bounding box.
##
## The first version framed the assembly's world AABB and asked how far back a
## frame of that size needs to be. It is the obvious thing and it is wrong here,
## because this assembly spans 2.17 m ACROSS and 0.6 m IN DEPTH: the extreme point
## of the AABB is the scabbard's butt when the sword is home, which is the
## FARTHEST point from the camera, and a far point projects small.
##
## With the camera at `target + back*d`, a point's view depth is `d - (p-target)·back`,
## so the constraint `|lateral| <= k * depth` solves for `d` in one step per point,
## exactly.
func _solve_distance(points: Array[Vector3], target: Vector3, right: Vector3,
		up: Vector3, back: Vector3, kx: float, ky: float) -> float:
	var distance := 0.2
	for p in points:
		var rel: Vector3 = p - target
		var behind := rel.dot(back)
		distance = maxf(distance,
			maxf(absf(rel.dot(right)) / kx, absf(rel.dot(up)) / ky) + behind)
	return distance * DETAIL_MARGIN


# ===========================================================================
#  THE TAKES
# ===========================================================================

func _take_idle() -> void:
	await _ensure_idle()
	_silence()
	_set_note("Blade out. Nothing is being asked of the sheath.")
	await _capture_for(1.4)
	_set_note("")
	await _capture_for(0.4)


## The seam at the far end of the draw. Put the sword away and then take it out
## again, continuously, because the teleport this file was written to look at
## happens at the INSTANT the choreographed beats stop being asked for.
func _take_put_away() -> void:
	await _ensure_idle()
	_silence()
	_set_note("Sword goes home. This is Beat 5 to Beat 1, backwards.")
	manager.call("equip_weapon", slot.CHAIN)
	await _capture_for(2.2)
	_set_note("")
	await _capture_for(0.5)


func _take_draw() -> void:
	await _ensure_idle()
	_silence()
	_arm_stills([
		{"tag": "draw_1_carry", "when": Callable(self, "_draw_past").bind(0.21)},
		{"tag": "draw_2_partial", "when": Callable(self, "_draw_past").bind(0.43)},
		{"tag": "draw_3_glint", "when": Callable(self, "_draw_past").bind(0.61)},
		{"tag": "draw_4_clear", "when": Callable(self, "_draw_past").bind(0.80)},
		{"tag": "draw_5_stance", "when": Callable(self, "_draw_home")},
	])
	_set_note("The off hand brings it up. From here the mouth is a fixity.")
	manager.call("equip_weapon", slot.SWORD)
	await _capture_until_drawn()
	_set_note("")
	await _capture_for(0.6)


func _take_beat(index: int, still: String) -> void:
	await _ensure_idle()
	_silence()
	var expected: StringName = combat.moveset.light_chain[index]
	if index > 0:
		# From idle the sentence restarts at A1, so the earlier beats are played
		# quickly and the capture is set up on the beat being reviewed.
		for i in index:
			if not await _advance_to_cancel():
				break
	await _ensure_idle()
	for i in index:
		combat.request(&"light")
		if not await _advance_to_cancel():
			break
	combat.request(&"light")
	_arm_stills([{"tag": still, "when": func() -> bool:
		return combat.active_move_id == expected and _past_settle(expected)}])
	await _capture_until_idle()
	await _capture_for(0.5)


func _take_switch_out() -> void:
	await _ensure_idle()
	_silence()
	_set_note("To the chain: the blade sheathes first, and the mouth has to be where the blade comes back to.")
	manager.call("equip_weapon", slot.CHAIN)
	await _capture_for(2.4)
	_set_note("")
	await _capture_for(0.5)


func _outro() -> void:
	shot_label.text = "THE SAYA · MEASURED IN THIS TAKE"
	caption_label.text = _verdict_line()
	note_label.text = "Same instrument as probe_saya_motion.gd. A frame that moved more than %.0f mm would have failed this run." % (JUMP_LIMIT * 1000.0)
	await _capture_for(2.6)


# ===========================================================================
#  CAPTURE
# ===========================================================================

func _capture_for(seconds: float) -> void:
	var until := float(Time.get_ticks_msec()) + seconds * 1000.0
	while float(Time.get_ticks_msec()) < until:
		await _capture_one()


func _capture_until_idle() -> void:
	var guard := 0
	while combat.state != CombatController.State.IDLE and guard < 900:
		await _capture_one()
		guard += 1
	await _capture_for(0.25)


func _capture_until_drawn() -> void:
	var guard := 0
	while float(combat.equip_blend) < 0.999 and guard < 900:
		await _capture_one()
		guard += 1
	await _capture_for(0.25)


## Captures until `seconds` of GAME time have passed. Game time, not wall time:
## the shot titles are timed against the sentence's own clock, and this file runs
## at whatever rate the two viewports and the PNG encoder allow.
func _capture_game(seconds: float) -> void:
	var until := combat.combat_time + seconds
	var guard := 0
	while combat.combat_time < until and guard < 900:
		await _capture_one()
		guard += 1


func _capture_one() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var big := detail_vp.get_texture().get_image()
	if big == null:
		push_error("the detail viewport returned no image at frame %d" % frame_index)
		return
	var small := eye_vp.get_texture().get_image()
	if small == null:
		push_error("the eye viewport returned no image at frame %d" % frame_index)
		return

	# COMPOSITED IN IMAGE SPACE, NOT WITH A TextureRect.
	#
	# Two reasons and both are the same reason. A `TextureRect` holding the root
	# window's own texture inside the root window is a self-reference, and the
	# frame the composite is read from then depends on the order the canvas is
	# drawn in relative to the readback — i.e. whether the inset is one frame
	# behind is a question about the renderer rather than about the take. Blitting
	# two images that have already been read is exact and cannot be half a frame
	# wrong.
	_paste(big, small)
	if big.save_png("%s/frame_%04d.png" % [out_dir, frame_index]) != OK:
		push_error("save_png failed at frame %d" % frame_index)
		return
	# COUNTED ONLY WHEN A PICTURE REACHED THE DISK. `frame_index` is the NAME of
	# the file, not a count of attempts; the delivery tool had this increment one
	# indent out and wrote 700 frames to `frame_0000.png` while reporting success.
	frame_index += 1
	_sample()
	_pump_stills()
	if frame_index % 60 == 0:
		print("    frame %d  game=%.2fs" % [frame_index, combat.combat_time])


## The inset, with a hairline so a bright arena behind a bright blade cannot make
## the two views look like one.
func _paste(big: Image, small: Image) -> void:
	var origin := Vector2i(
		VIEW.x - INSET.x - INSET_PAD,
		VIEW.y - INSET.y - INSET_PAD - INSET_PAD)
	var frame := Rect2i(
		origin - Vector2i(INSET_BORDER, INSET_BORDER),
		INSET + Vector2i(INSET_BORDER * 2, INSET_BORDER * 2))
	big.fill_rect(frame, Color(0.05, 0.05, 0.07, 0.85))
	# The two viewports are the same size nowhere and the same format only by
	# convention. `blit_rect` refuses a mismatched source with an error and an
	# unchanged rectangle, which would ship a clip whose inset silently is not
	# there — so the format is made to match rather than assumed.
	if small.get_format() != big.get_format():
		small.convert(big.get_format())
	big.blit_rect(small, Rect2i(Vector2i.ZERO, INSET), origin)


# --- stills ----------------------------------------------------------------

func _arm_stills(rules: Array) -> void:
	_stills.clear()
	for rule in rules:
		rule["done"] = false
		_stills.append(rule)
		_want_still(String(rule["tag"]))


func _want_still(tag: String) -> void:
	if not _wanted_stills.has(tag):
		_wanted_stills.append(tag)


func _pump_stills() -> void:
	if _pending_still != "":
		_copy_still(_pending_still)
		_pending_still = ""
	for rule in _stills:
		if rule["done"]:
			continue
		var when: Callable = rule["when"]
		if not when.call():
			continue
		rule["done"] = true
		_copy_still(String(rule["tag"]))


func _copy_still(tag: String) -> void:
	if frame_index <= 0:
		push_error("still '%s' asked for before any frame was saved" % tag)
		return
	if _written_stills.has(tag):
		return
	var from := "%s/frame_%04d.png" % [out_dir, frame_index - 1]
	var to := "%s/still_%s.png" % [out_dir, tag]
	if DirAccess.copy_absolute(
			ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to)) != OK:
		push_error("still '%s' failed to copy from %s" % [tag, from])
		return
	_written_stills.append(tag)


# ===========================================================================
#  MEASUREMENT · the same figure the probe prints, from this take's own track
# ===========================================================================

func _sample() -> void:
	var delta := clock.total - _last_total
	_last_total = clock.total
	_t = clock.total
	_samples.append({"pos": _mouth(), "dt": delta, "t": _t, "live": _blade_is_out()})


## TRUE WHEN THE SHEATH HAS NO BUSINESS MOVING, which is the only window in which
## "the mouth did not move" is a claim rather than a restatement.
##
## The first version of this measured the worst single-frame step across the WHOLE
## take and failed itself at 0.0337 m — during the CARRY, where the off hand is
## deliberately bringing the mouth 0.104 m up to the front. A take that fails
## itself for doing what it was authored to do is not a strict test, it is a
## mis-specified one: at this file's capture rate a frame is 68 ms, and 0.5 m/s
## over 68 ms is 33 mm of perfectly smooth motion.
##
## So the window is stated in the terms the fix was made in: the blade is out
## (`equip_blend` home), no draw is running, and no sheathe is running. That
## covers the idle gaps AND all four attack beats — which is the whole of the
## complaint, since A1-A4 were the segments that used to drag the saya 0.21 m.
func _blade_is_out() -> bool:
	if float(combat.equip_blend) < 0.999:
		return false
	if bool(manager.get("drawing_in")):
		return false
	return float(manager.get("_sheathe_left")) <= 0.0


func _mouth() -> Vector3:
	if combat.saya_rig == null or not is_instance_valid(combat.saya_rig):
		return Vector3.ZERO
	return combat.saya_rig.mouth_point()


## The worst single-update step taken while the sheath has no business moving, and
## only between two updates that BOTH qualify — a sample either side of the draw's
## first frame is a step across a window the sheath was allowed to move in.
func _idle_drift() -> float:
	var worst := 0.0
	for i in range(1, _samples.size()):
		if not bool(_samples[i - 1]["live"]) or not bool(_samples[i]["live"]):
			continue
		var a: Vector3 = _samples[i - 1]["pos"]
		var b: Vector3 = _samples[i]["pos"]
		worst = maxf(worst, a.distance_to(b))
	return worst


func _peak_speed() -> Dictionary:
	var best := {"speed": 0.0, "t": 0.0}
	for i in _samples.size():
		var j := i + 1
		while j < _samples.size() and _samples[j]["t"] - _samples[i]["t"] < SPEED_WINDOW:
			j += 1
		if j >= _samples.size():
			break
		var span: float = _samples[j]["t"] - _samples[i]["t"]
		if span <= 0.0:
			continue
		var speed: float = _samples[i]["pos"].distance_to(_samples[j]["pos"]) / span
		if speed > float(best["speed"]):
			best = {"speed": speed, "t": _samples[i]["t"]}
	return best


func _report() -> void:
	var fastest := _peak_speed()
	var drift := _idle_drift()
	var live := 0
	for s in _samples:
		if bool(s["live"]):
			live += 1
	print("")
	print("   frames sampled %d over %.2fs of engine time (%d of them with the blade out "
		% [_samples.size(), _t, live] + "and the sheath unasked)")
	print("   fastest mouth window %.2f m/s  =  %.1f mm per 60 Hz frame  (at t=%.2f)" % [
		fastest["speed"], float(fastest["speed"]) / 60.0 * 1000.0, fastest["t"]])
	print("   worst single-update step while the sheath is unasked %.4f m (limit %.4f)" % [
		drift, IDLE_DRIFT_LIMIT])
	_judge(float(fastest["speed"]) < JUMP_LIMIT * 60.0,
		"no rendered frame carries the mouth more than %.0f mm (worst %.2f m/s at t=%.2f)"
			% [JUMP_LIMIT * 1000.0, fastest["speed"], fastest["t"]])
	_judge(drift < IDLE_DRIFT_LIMIT,
		"with the blade out and nothing asked of it, the mouth steps at most %.4f m (limit %.4f) across %d updates"
			% [drift, IDLE_DRIFT_LIMIT, live])


func _verdict_line() -> String:
	var fastest := _peak_speed()
	return "worst frame %.1f mm · fastest window %.2f m/s · %d frames" % [
		float(fastest["speed"]) / 60.0 * 1000.0, fastest["speed"], _samples.size()]


func _judge(condition: bool, reason: String) -> void:
	print("   %s %s" % ["ok  " if condition else "FAIL", reason])
	if not condition:
		_fails.append(reason)


# ===========================================================================
#  HARNESS
# ===========================================================================

func _shot(title: String, caption: String, seconds: float) -> void:
	shot_label.text = title
	caption_label.text = caption
	note_label.text = ""
	await _capture_game(seconds)


func _set_note(text: String) -> void:
	note_label.text = text


## Stands every zone target down. This clip is about the weapon and the sheath,
## so nothing else may move: a body walking through the frame is a second subject
## and a second clock.
func _silence() -> void:
	var zone := sandbox.get_node_or_null("SwordComboZone")
	if zone == null:
		return
	for node in zone.call("all_targets"):
		(node as Node3D).visible = false


## The draw's own predicate, as a METHOD taking the blend it is waiting for, and
## bound rather than written as a lambda.
##
## `--check-only` on the sibling delivery tool segfaults (signal 11, no
## diagnostic) on a multi-line lambda that declares a local and on a bare method
## reference used as a value inside a dictionary array literal. `Callable(self,
## "name").bind(...)` is neither, and it also lets one predicate serve five stills
## instead of five closures.
##
## The thresholds are `equip_blend`, which `CombatController.advance_draw` sets to
## `elapsed / DRAW_SECONDS` — so the blend IS the draw's normalised clock and the
## beats land on it exactly: 0.35/1.75 = 0.20, 0.75/1.75 = 0.43, 1.07/1.75 = 0.61,
## 1.40/1.75 = 0.80. A still is therefore a picture of a named beat and not of
## whichever frame the machine happened to manage.
func _draw_past(blend: float) -> bool:
	var now := float(combat.equip_blend)
	return bool(manager.get("drawing_in")) and now >= blend and now < 0.999


## Beat 5, the instant the choreographed beats stop being asked for — the seam the
## 128.9 mm teleport used to live in, and the only frame in this clip where the
## mouth's authority changes hands.
##
## THE DRAW IS NOT THE CONDITION. Written as "`drawing_in` and blend at home" it
## reports a missing still, because `WeaponManager` clears `drawing_in` in the same
## `_process` that pushes the blend to 1.0 — so the one frame that satisfies both
## is a frame that may never be captured. "The draw has finished" is the honest
## predicate and it is what the still is actually of.
func _draw_home() -> bool:
	return float(combat.equip_blend) >= 0.999 and not bool(manager.get("drawing_in"))


func _past_settle(move_id: StringName) -> bool:
	var move := combat.moveset.get_move(move_id)
	if move == null or combat.active_move == null:
		return false
	return combat.state_time >= move.startup + move.strike * 0.55


func _ensure_idle() -> void:
	combat.finish_action()
	await _capture_for(0.2)


func _advance_to_cancel() -> bool:
	var guard := 0
	while guard < 300:
		if combat.state == CombatController.State.IDLE:
			return false
		if combat.active_move != null and bool(combat.call("_can_cancel", &"light")):
			return true
		await _capture_one()
		guard += 1
	return false


func _warm(frames: int) -> void:
	for i in frames:
		await physics_frame


# ===========================================================================
#  OVERLAY · drawn into the DETAIL viewport, not the window
# ===========================================================================
#
# A `CanvasLayer` added to the root would be composited into the root window's
# texture — the inset — and the titles would end up 384 pixels wide, inside the
# picture they are titling. The composite's main image is the detail viewport, so
# the titles go where the main image is.

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DetailOverlay"
	layer.layer = 4
	detail_vp.add_child(layer)

	shot_label = _label(26)
	shot_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	shot_label.position = Vector2(48, 40)
	layer.add_child(shot_label)

	caption_label = _label(17)
	caption_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	caption_label.position = Vector2(48, 76)
	caption_label.modulate = Color(0.86, 0.93, 0.97, 0.92)
	layer.add_child(caption_label)

	note_label = _label(15)
	note_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	note_label.position = Vector2(48, -64)
	note_label.modulate = Color(0.78, 0.88, 0.94, 0.92)
	note_label.size = Vector2(float(VIEW.x - INSET.x - INSET_PAD * 3), 60.0)
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(note_label)


func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	# Shadowed rather than panelled: this has to stay readable over a bright
	# arena without turning the review frame into an interface.
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _v3(v: Vector3) -> String:
	return "(%+.3f, %+.3f, %+.3f)" % [v.x, v.y, v.z]


func _clear_frames() -> void:
	var dir := DirAccess.open(out_dir)
	if dir == null:
		return
	for file in dir.get_files():
		if file.begins_with("frame_") or file.begins_with("still_") or file == "fps.txt":
			dir.remove(file)


func _write_fps(fps: float) -> void:
	var file := FileAccess.open("%s/fps.txt" % out_dir, FileAccess.WRITE)
	if file == null:
		push_error("could not write fps.txt")
		return
	file.store_string("%.4f\n" % fps)
