extends SceneTree
##
## SAYA CONTROLLED STILLNESS · PASS 02 · THE STILLNESS TAKE (§31)
##
##   "/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --path F:/SEKAI/godot \
##     --resolution 1280x720 --audio-driver Dummy \
##     --script res://tools/saya_controlled_stillness_movie.gd -- <output_dir>
##
## Needs a REAL WINDOW. `--headless` disables rendering and this file only
## produces rendering.
##
## ===========================================================================
## WHAT THIS SHOWS THAT PASS 01's TAKE DID NOT
## ===========================================================================
## Pass 01's clip (`tools/saya_stillness_movie.gd`) answered "刀鞘不要乱动" and
## answered it: the mouth did not move, and the number said so. Pass 02's brief
## says that answer was the WRONG ONE -- §0 lists it as regression "F", a
## scabbard welded to the camera -- and replaces the claim with
##
##   §1   FOLLOW THE LEFT HAND, WITH CONTROLLED STABILIZATION
##   §29  Saya moves only when it has a reason.
##
## So this take is built to show the DIFFERENCE between the two failures, which
## is the only thing the picture can add to the numbers:
##
##   IDLE       the mouth BREATHES (§5, 0.5-1.5 cm). Framed tight, because 9 mm
##              of breath in a 2.6 m frame is two pixels, and a clip in which the
##              claim is unreadable has verified nothing.
##   DRAW       seven beats, and the mouth is HELD across the extraction. Two
##              frames of the same act: one where the hand carries it (alive) and
##              one where the blade is in the bore (dead still).
##   A1         §7-§9   counter-pull: the left hand pulls the mouth 3-6 cm back
##                      along the bore and HOLDS it while the blade is out.
##   A2         §10-§11 CLEAR THE BLADE PATH -- left, down, in.
##   A3         §12-§15 the anchor, the partial returns, and the reciprocation:
##                      the mouth goes DOWN the blade as it leaves and UP it as it
##                      comes home, once per partial return. Replayed at 0.25x,
##                      because 15 mm of receiving motion inside four frames is
##                      not something a person can see at speed.
##   A4         §16-§17 GET OUT OF THE WAY: the blade expands, the saya contracts.
##   IAIDO      §21-§26 ONE controlled rotation, and the mouth catch. Also 0.25x.
##
## ===========================================================================
## THE FRAMING IS SOLVED PER ACT, AND IT SAYS SO
## ===========================================================================
## Pass 01 used ONE camera for the whole clip, solved from the draw's own beats.
## That was right for a clip about the draw and it is wrong here, because the
## acts differ by a factor of four in size: A4 sweeps 270 degrees and 2.4 m, the
## idle breath is 9 mm. One frame cannot contain both at a readable scale.
##
## So each act solves its OWN camera from its OWN authored data -- the blade's
## origin and tip and the saya's mouth and end, at every beat of every act, plus
## a 60 Hz walk of the sampled trajectory for the four cuts. The solved extent is
## PRINTED for every shot and drawn on the caption. A camera chosen by eye can be
## chosen to hide a 9 mm drift; one that has to contain the act's measured extent
## cannot, and one that states the extent lets the reader do the division.
##
## The camera is then FIXED for the whole shot. Within an act nothing follows the
## motion, which is the property that makes "the mouth did not move" the same
## claim in the picture as in `probe_saya_control.gd`.
##
## ===========================================================================
## THE VERDICT IS MEASURED IN THE SAME RUN
## ===========================================================================
## The outro prints the number the clip is about, computed from THIS take's own
## mouth track. A caption quoting a measurement from a different session is a
## claim about a build that may not be the one on screen.
##
## Usage:
##   ... --script res://tools/saya_controlled_stillness_movie.gd -- <output_dir>

const STAGE_PATH := "res://scenes/combat/CombatSandbox.tscn"
const WEAPON_ROOT_PATH := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot"
const SHOTGUN_PATH := "CameraRig/LookPivot/MotionPivot/ShakePivot"
const SWORD_PATH := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual"

## `ForegroundWeaponLayer.WEAPON_LAYER`. Spelled out rather than read off the
## class because this file has to keep working when the layer node is absent.
const WEAPON_LAYER := 1 << 19
## §32's mode draws the review body and ONE ground plane, and nothing else.
##
## The first body clip culled the world in and got the arena: `side_wide` and
## `rear_left` both stand among the sandbox's pillars, and the A4 frame arrived with
## a black column across a quarter of the picture. The detail camera had already
## solved this exact problem by going the other way -- it drops bit 0 and puts a card
## behind the subject -- but dropping bit 0 here takes the ground with it, and a body
## with no ground has no scale and no floor to be connected to (§30).
##
## So: no world, one plane at the measured floor height, one layer for the two of
## them. The sky still renders, because the environment is not a mesh and no cull
## mask removes it.
##
## THE VALUE IS NOT USED DIRECTLY. The body declares its own layer
## (`SayaReviewBody.REVIEW_LAYER`) and the take asks for it, because this constant
## was written twice -- once here and once in the instrument -- and the second body
## clip is what happens when the two disagree: the camera culled bit 0, the body
## was on bit 0, and the frame came back with a floor, a sword, a scabbard and no
## figure at all, with every gate green.
var _body_layer := 1 << 17

## THE REVIEW BACKDROP'S OWN BIT, so it reaches the detail camera and nothing
## else. See `_build_backdrop`.
const BACKDROP_LAYER := 1 << 18

const VIEW := Vector2i(1280, 720)
const INSET := Vector2i(384, 216)
const INSET_PAD := 16
const INSET_BORDER := 2
const EYE_FOV := 75.0
const DETAIL_FOV := 40.0
## Room around an act's measured extent. 8% of a 1.2 m stage is 10 cm.
const DETAIL_MARGIN := 1.08

## THE INSET OWNS THE BOTTOM-RIGHT CORNER, SO THE SOLVER IS TOLD ABOUT IT.
##
## The first take of this clip framed the saya dead centre -- and then drew the
## 384x216 eye inset straight over it. `_diag()` put the mouth at screen
## (939, 437) and the butt at (989, 690) while the inset occupies
## x 880-1264, y 456-688: the scabbard was in the frame and behind the
## picture-in-picture, and no amount of looking at the code would have said so.
##
## A review frame has two jobs -- show the act, and show where the player was
## looking -- and the second must not eat the first. So the framing is solved
## against the area the inset does NOT own, and the safe band is placed at the
## TOP of the frame where the subject then lands.
const SAFE_H := VIEW.y - INSET.y - INSET_PAD * 3

## §15, as a number rather than as an adjective. The sword's own VFX is damped to
## a tenth: enough that the ribbon still marks WHEN the cut happened -- which is
## half of what a Motion QA clip is for -- and not enough to lay a bright band
## across the two objects the clip is about.
const QA_VFX_INTENSITY := 0.10

## The same ceiling as `probe_saya_control.gd`, so the clip and the probe agree.
const JUMP_LIMIT := 0.020
## §5's band, the other way round. Pass 01 gated this from ABOVE only
## (`IDLE_DRIFT_LIMIT := 0.012`) and Pass 02 fails it from BOTH sides: a mouth
## that does not breathe is regression F.
const BREATH_FLOOR := 0.005
const BREATH_CEIL := 0.015
## ...AND OVER A BREATH'S OWN LENGTH OF TIME, WHICH IS THE PART THE FIRST DRAFT
## MISSED. See `_breath_excursion`.
const BREATH_WINDOW := 2.0
const SPEED_WINDOW := 0.030
const CAPTURE_FPS := 30
## The nominal delivery rate, used only to PRINT the clip's length in seconds.
## The realised rate is measured (`ENCODE_FPS`) and is what the encoder is given.
const DELIVERY_RENDER_FPS := 120

## §33. The one ratio this pass is allowed to have opinions about.
const SLOW_SCALE := 0.25

# ===========================================================================
# §32 · THE THIRD-PERSON CAMERAS
# ===========================================================================
#
# Three positions, offsets in `CameraRig` space. `CameraRig`'s origin IS the eye
# (`Player` puts it at y = +0.65 and the capsule under that is centred on the
# player's origin), forward is -Z -- the same sign `SwordBasic.SAYA_MOUTH.z` is
# negative in -- and +X is the character's RIGHT, because `IDLE_POSITION.x` is
# +0.52 and that is the sword hand.
#
# THE BODY IS PARENTED TO `CameraRig` AND SO ARE THESE MARKERS, and that is not a
# convenience. `Player` turns by YAW and everything below `CameraRig` is identity,
# so a marker placed here rides the player's facing and is deaf to the mouse
# pitch, the gait bob and the recoil shake. A camera parented under `LookPivot`
# would swing every time the reviewer's view moved, and a motion clip whose camera
# moves with the subject cannot be used to judge the subject's movement.
#
# WHY THERE ARE FIVE AND NOT THE TWO §32 ASKS FOR. Each act is filmed from the
# position that can see the thing the act is about, and the acts are not the same
# size: the scabbard breathes 9 mm during the idle and the sword sweeps a 4 m arc
# during A4. One framing cannot hold both, and the choice is between a clip where
# the idle's breath is four pixels and a clip where A3's cut leaves the frame.
#
#   front_left   the only position that sees the left hand AND the scabbard
#                during a cut. Tight, for the acts that are about the hand.
#   side_right   the blade's sweep plane edge-on, so "clear the path" reads as a
#                distance rather than as a coincidence.
#   rear_left    where the body's own ROTATION is legible. From the front a yaw
#                and a camera move are the same picture.
#   front_wide   A3. The act's whole claim is "the hand holds, the sword cuts",
#                and the sword is well over a metre from the hand at that instant.
#                It does not fit the tight frame, and a shot of a holding hand with
#                no sword in it proves the opposite of what the shot is for.
#   side_wide    A4. The saya's whole job in that act is to leave, and it leaves to
#                somewhere the tight side view does not cover.
#
# The fourth element is the camera's own vertical `fov`, because
# `Camera3D.keep_aspect` defaults to `KEEP_HEIGHT`.
const BODY_CAMS := [
	["front_left", Vector3(-1.65, -0.34, -1.95), Vector3(-0.20, -0.45, -0.55), 50.0],
	["side_right", Vector3(2.15, -0.34, -0.40), Vector3(0.0, -0.45, -0.40), 50.0],
	["rear_left", Vector3(-1.35, -0.30, 1.75), Vector3(-0.20, -0.45, -0.35), 50.0],
	["front_wide", Vector3(-2.25, -0.28, -2.65), Vector3(-0.20, -0.38, -0.55), 55.0],
	["side_wide", Vector3(3.05, -0.28, -0.75), Vector3(0.0, -0.42, -0.40), 55.0],
]
## Used when a camera's own entry does not name a fov. 50 degrees over a 2.0-2.4 m
## distance covers a 1.70 m figure with air above and below; the detail camera's 40
## was chosen for a subject a metre across and would crop a standing body's feet.
const BODY_FOV := 50.0

const SwordClasses := preload("res://scripts/weapons/sword_classes.gd")
const SwordPoseSampler := preload("res://scripts/combat/sword_pose_sampler.gd")
const ReviewBody := preload("res://tools/saya_review_body.gd")

# ===========================================================================
# NODES
# ===========================================================================

## Copies the review rigs' transforms onto the viewport cameras, AFTER the pose
## they belong to has been written.
##
## A `SubViewport` camera cannot be a descendant of `WeaponRoot`:
## `Node3D.get_global_transform()` walks up through NODE-3D parents only, so a
## camera under a SubViewport that is itself under WeaponRoot has WeaponRoot's
## chain cut out of it and renders from the origin. The rigid attachment has to
## be copied, and a copy is only correct if it happens in the right ORDER.
class FrameSync extends Node:
	var pairs: Array = []

	func _process(_delta: float) -> void:
		for pair in pairs:
			var from: Node3D = pair[0]
			var to: Camera3D = pair[1]
			if is_instance_valid(from) and is_instance_valid(to):
				to.global_transform = from.global_transform


## The engine's own delta, accumulated. NOT `Time.get_ticks_usec()`: under a real
## capture loop the wall clock across an `await` produced 3-4 m/s readings on a
## traverse the authored curve caps at 0.74 m/s, and step and dt came out
## inversely correlated -- the signature of a jittery clock.
class FrameClock extends Node:
	var total := 0.0
	func _process(delta: float) -> void:
		total += delta


## Hands the rig's own hand points to the review body, every frame, in the ONE
## window where both are true.
##
## The chain of process priorities in this project is: `SayaHandDriver` at -10
## writes the scabbard's seat, the weapon controller at 0 writes the sword's pose,
## and `SayaReviewBody` at +20 solves the arms. So a reader at +5 sees the final
## hand points for this frame and writes them in time for the body to solve against
## them in the SAME frame.
##
## Reading them anywhere else is off by one frame, and off by one frame is
## invisible in a still and wrong in a clip: the arm would trail the scabbard by
## 16 mm at a walk and by considerably more during A3's reciprocation, which is
## precisely the motion §12-§15 is about.
class BodyTargets extends Node:
	var combat: CombatController
	var sword: Node3D
	var body: Node3D

	func _process(_delta: float) -> void:
		if combat == null or body == null or not is_instance_valid(body):
			return
		var hand: Node3D = combat.saya_hand
		if hand != null and is_instance_valid(hand):
			body.set("left_target", hand.global_position)
		if sword != null and is_instance_valid(sword):
			body.set("right_target", sword.global_position)


# ===========================================================================
# STATE
# ===========================================================================

var out_dir := ""
## Second CLI argument. `smoke` runs two short takes and stops, so a framing or
## wiring fault costs ten seconds instead of the four minutes a full take costs.
## Nothing about the delivered clip runs through it: in smoke mode the takes are
## the same code with the holds divided by `SMOKE_DIVISOR`.
var smoke := false
const SMOKE_DIVISOR := 8.0
## §32's mode. Same takes, same order, same requests -- a different camera, a
## different caption, no inset, full frame. It is a MODE rather than a second tool
## for one reason: the bug this file has already paid for was the ORDER of the
## takes, and two tools would mean two orders to keep in step, with the failure
## mode being a delivered clip that quietly films the wrong act.
var body_mode := false
var body_vp: SubViewport
var body_cam: Camera3D
var body_marker: Node3D
var body: Node3D
## The act key the takes hand to `_shot`. The body captions are looked up by it, so
## it is also the switch: empty means the act's own detail captions are used.
var _act_key := ""
## Which of `BODY_CAMS` the current act is filmed from.
var _body_cam := ""
## Every camera §32's mode actually used, in the order they were first reached.
## §32 asks for AT LEAST TWO positions, and "the file names three" is not the same
## claim as "three were used" -- a table of positions that all resolve to one entry
## would pass a reading of the code and deliver a single-angle clip.
var _body_cams_used: Array[String] = []
## The worst the rig's geometry ever asked the review body for, in metres, and
## where. See `_sample` -- a single frame is not the claim.
var _shortfall_l := 0.0
var _shortfall_r := 0.0
var _shortfall_l_at := "nowhere"
var _shortfall_r_at := "nowhere"
## What the floor measurement was taken from, carried into the caption so that a
## wrong one is visible in the picture instead of only in this file.
var _floor_source := ""
## The measured eye-to-floor distance, kept because the ground plane and the body's
## legs must be built from the SAME number -- two calls to `_measure_floor` would be
## two chances for a body standing one millimetre inside or above its own floor.
var _measured_floor := 0.0
var frame_index := 0
var start_ms := 0
var sandbox: Node3D
var player: CharacterBody3D
var combat: CombatController
var manager: Node
var slot: WeaponSlot
var weapon_root: Node3D
var sword: Node3D
var director: Node

var detail_vp: SubViewport
var detail_cam: Camera3D
var eye_vp: SubViewport
var eye_cam: Camera3D
var detail_marker: Node3D
var backdrop: MeshInstance3D
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
## Move ids the current take has played, for `_check_armed`.
var _seen_moves: Array[String] = []

var _samples: Array[Dictionary] = []
var _marks: Array[Dictionary] = []
var _last_total := 0.0
var _t := 0.0
var _shot_extent := Vector2.ZERO
var _diag_pending := ""

var _fails: Array[String] = []
## §22's figure, accumulated over the TURN window only, and -- as context -- the
## whole ceremony's orientation travel, which is a different and much larger
## number. See `_sample`.
var _ai_rot_deg := 0.0
var _ai_rot_all := 0.0
var _ai_rot_prev := Quaternion.IDENTITY
var _ai_have_prev := false
## The turn's own window in ceremony time, set by `_take_recovery` from the
## director's tuning so it cannot drift from the ceremony it measures.
var _turn_from := 0.0
var _turn_to := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path(
		"res://../.render/saya_pass02")
	# `smoke` / `body` / `body_smoke`. The combined word exists because the body
	# path has its own wiring -- a second viewport, a marker the sync does not know
	# about until it is appended, a node that reads the pose at a priority between
	# two other nodes -- and every one of those is a place this file has already
	# been wrong once. A mode that can only be exercised by a four-minute run is a
	# mode that gets exercised once.
	var mode_arg := args[1].strip_edges() if args.size() > 1 else ""
	body_mode = mode_arg == "body" or mode_arg == "body_smoke"
	smoke = mode_arg == "smoke" or mode_arg == "body_smoke"
	DirAccess.make_dir_recursive_absolute(out_dir)
	_clear_frames()

	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# HOW FAST THE RENDERER IS ALLOWED TO RUN IS A MEASUREMENT DECISION.
	#
	# The clip is played back at the rate this run MEASURES, so the cap cannot
	# change how fast anything looks -- it changes only how many distinct pictures
	# per second the reader gets. At 30 the renderer is the limiter and each
	# capture costs two of its frames, which lands the take near 9 fps: a 0.385 s
	# beat of the draw arrives as three pictures, and §18's whole claim is about
	# the arc BETWEEN two beats. With the cap lifted the capture is bounded by the
	# texture readback and the PNG write instead -- measured 19.8 fps, and the same
	# draw beat is eight pictures. `SEKAI_RENDER_FPS` overrides it for a cheap run.
	#
	# vsync goes off with the cap, because a 60 Hz window would put the ceiling
	# straight back where it was.
	var render_env := OS.get_environment("SEKAI_RENDER_FPS")
	var render_cap := float(DELIVERY_RENDER_FPS)
	if render_env != "":
		render_cap = float(render_env.to_int())
	Engine.max_fps = int(render_cap)
	if render_cap > 60.0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.time_scale = 1.0
	print("render cap %d fps · vsync %d" % [
		int(render_cap), int(DisplayServer.window_get_vsync_mode())])

	var packed: PackedScene = load(STAGE_PATH)
	sandbox = packed.instantiate()
	root.add_child(sandbox)
	await _warm(14)

	player = sandbox.get_node("Player")
	combat = player.get_node("CombatController")
	manager = player.get_node("WeaponManager")
	slot = player.get_node("WeaponSlot")
	weapon_root = player.get_node(WEAPON_ROOT_PATH)
	sword = player.get_node_or_null(SWORD_PATH)
	director = sandbox.get_node_or_null("IaidoDirector")
	if combat.saya_rig == null or manager == null or weapon_root == null \
			or sword == null or director == null:
		print("FAIL: the sword line is not wired into this stage")
		quit(1)
		return

	_quiet_the_stage()
	_build_rigs()
	clock = FrameClock.new()
	clock.name = "Pass02Clock"
	root.add_child(clock)
	_last_total = clock.total

	print("window=%s  detail=%s  eye=%s  out=%s" % [root.size, VIEW, INSET, out_dir])
	if body_mode:
		print("MODE body · §32 · %d cameras, full frame, no inset: %s" % [
			BODY_CAMS.size(),
			", ".join(BODY_CAMS.map(func(p): return String(p[0])))])
	else:
		print("MODE detail · §31 · one solved camera plus the eye inset")
	print("vfx intensity %.2f · pane split=%s crack=%s glass=%s" % [
		QA_VFX_INTENSITY, str(OS.get_environment("SEKAI_NO_PANE_SPLIT") != ""),
		str(OS.get_environment("SEKAI_NO_CRACK") != ""),
		str(OS.get_environment("SEKAI_NO_GLASS") != "")])
	start_ms = Time.get_ticks_msec()

	if smoke:
		# THE SMOKE RUN IS THE WHOLE STATE CHAIN, SHORTENED -- not two acts that
		# happened to be cheap. The first draft's smoke run was `idle` then `A4`,
		# and it passed while the delivered clip had four acts missing: the fault
		# lived in the ORDER of the takes (blade in, blade out), and a smoke run
		# that does not walk that order cannot see it.
		await _take_idle()
		await _take_put_away()
		await _take_draw()
		await _take_cut(2, "SMOKE · A3", "framing and wiring only", "smoke_a3", false)
		await _take_recovery()
		await _outro()
		Engine.time_scale = 1.0
		var smoke_wall := float(Time.get_ticks_msec() - start_ms) / 1000.0
		# The count is taken against the SHOT LIST, not against everything written.
		# Smoke arms stills the delivery run never asks for, so a bare
		# `written/wanted` printed 13/8 and read as a fault in the run rather than
		# as a property of the mode.
		var wanted_hit := 0
		for tag in _wanted_stills:
			if _written_stills.has(tag):
				wanted_hit += 1
		print("SMOKE: %d frames in %.1fs (%.2f fps) · %d/%d shot-list stills · %d written" % [
			frame_index, smoke_wall, float(frame_index) / maxf(smoke_wall, 0.001),
			wanted_hit, _wanted_stills.size(), _written_stills.size()])
		quit()
		return

	# THE ORDER OF THESE TAKES IS NOT EDITORIAL. IT IS A PRE- AND POST-CONDITION
	# CHAIN, AND THE FIRST DRAFT OF THIS FILE GOT IT WRONG IN A WAY THAT COST THE
	# WHOLE CLIP.
	#
	# `CombatController._start` refuses `light`, `heavy`, `iaido` and `ultimate`
	# outright while `equip_blend < 1.0` (§19/§20: the blade has to be out). So:
	#
	#   IDLE       needs the blade OUT, which is the sandbox's opening state.
	#   PUT AWAY   needs it out, and leaves it IN.
	#   DRAW       needs it IN, and leaves it out.  <- only this order works
	#   CUTS       need it out.
	#   IAIDO      needs it out.
	#
	# The first draft ran `draw` then `put_away` then the cuts. That put the blade
	# away and then asked for four light attacks, and every one of them returned
	# false in silence: `_capture_until_idle()` then exited on its own first
	# iteration (the state it waits to leave was IDLE already), so the take
	# reported success with four acts missing and ten stills unwritten.
	#
	# Drawing the sword again before the cuts would also work and would put a
	# second, redundant draw on screen. This order costs nothing and keeps the
	# put-away and the draw ADJACENT, which is where §20's claim lives: the same
	# seven beats, read in the two directions.
	await _take_idle()
	await _take_put_away()
	await _take_draw()
	await _take_cut(0, "A1 · 小居合 · COUNTER PULL",
		"§7-§9: the LEFT HAND pulls the mouth 3-6 cm back along the bore and HOLDS it while the blade is out.",
		"a1_counter_pull", false)
	await _take_cut(1, "A2 · 左划上挑 · CLEAR THE BLADE PATH",
		"§10-§11: LEFT / DOWN / IN, 3-8 cm. The mouth moves because the blade needs the room.",
		"a2_clear", false)
	await _take_cut(2, "A3 · 小居合领域 · PARTIAL RETURN · 1.0x",
		"§12-§13: an ANCHOR pose and three partial returns. The mouth is off the hip entirely.",
		"a3_anchor", false)
	await _take_cut(2, "A3 · MECHANICAL RECIPROCATION · 0.25x",
		"§14: 15 mm down the blade as it leaves, 15 mm back up it as it comes home -- ONCE PER PARTIAL RETURN. One frame at full speed is 6 mm.",
		"a3_receive", true)
	await _take_cut(3, "A4 · 周身优弧横斩 · GET OUT OF THE WAY",
		"§16-§17: the blade EXPANDS, the saya CONTRACTS. Nothing else is being asked of it.",
		"a4_clear", false)
	await _take_recovery()
	await _outro()

	Engine.time_scale = 1.0
	var elapsed := float(Time.get_ticks_msec() - start_ms) / 1000.0
	var fps := float(frame_index) / maxf(elapsed, 0.001)
	print("frames=%d  wall=%.2fs  -> ENCODE_FPS=%.3f" % [frame_index, elapsed, fps])
	# Played back at the rate it was measured at, the clip is exactly the wall
	# time -- which is the only reading of "20-35 s" that means anything, because
	# the alternative is a clip whose speed is an artefact of the capture rig.
	print("clip length at the measured rate = %.1f s (real time)" % [
		float(frame_index) / maxf(fps, 0.001)])
	_write_fps(fps)
	_report()
	# THE FAILURE LIST IS PRINTED, NOT JUST COUNTED. The first draft's last line
	# said "FAIL: take is incomplete" and nothing said WHICH four acts were
	# missing -- the reasons were accumulated into `_fails` and then never read,
	# which is a gate that fires without ever saying what it caught.
	if not _fails.is_empty():
		print("")
		for reason in _fails:
			print("   !! %s" % reason)

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
		print("FAIL: take is incomplete, or the saya is frozen, or it moved without a reason")
		quit(1)
		return
	print("PASS: %d frames, %d stills, in %s" % [
		frame_index, _written_stills.size(), out_dir])
	if body_mode:
		print("      body mechanics · cameras used: %s" % ", ".join(_body_cams_used))
	quit()


# ===========================================================================
# THE RIGS
# ===========================================================================

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
	var stray := sandbox.get_node_or_null("TechnicalDummy") as Node3D
	if stray != null:
		stray.visible = false
		stray.set_process(false)
		stray.set_physics_process(false)
	# §15. The sword's VFX is the one layer that can hide the relationship this
	# clip exists to show, and §15 allows it to be LOWERED OR SWITCHED OFF.
	#
	# Damping to a tenth is not always enough. A3's marks are windows in SPACE --
	# a wedge `trace_half_len_tan` wide and `trace_half_thick_tan` thick extending
	# to the move's full reach -- which is a 21 m band at 15 m, and the QA camera
	# sits 4 m from a subject 1 m across. At any alpha that wedge crosses the
	# frame; at the alpha that makes it a cut in the air it is the loudest thing
	# in it. So the plane is OFF for this pass and the ribbon stays damped: the
	# ribbon is the part that says WHEN, which is half of what a motion clip is
	# for, and the plane is the part that covers the two objects it is about.
	var full_vfx := OS.get_environment("SEKAI_QA_VFX") == "on"
	var vfx: Node = combat.get("sword_vfx")
	if vfx == null:
		vfx = sandbox.get_node_or_null("SwordCombatVFX")
	if vfx == null:
		push_warning("no SwordCombatVFX found; §15's damping was not applied")
	elif full_vfx:
		vfx.set("intensity", 1.0)
		print("§15: sword VFX left at FULL strength (SEKAI_QA_VFX=on)")
	else:
		vfx.set("intensity", QA_VFX_INTENSITY)
		if vfx.has_method("set_scars_enabled"):
			vfx.call("set_scars_enabled", false)
			print("§15: sword VFX damped to %.2f and the Spatial Cut planes switched off"
				% QA_VFX_INTENSITY)
		else:
			print("§15: sword VFX damped to %.2f (no plane switch on this build)"
				% QA_VFX_INTENSITY)
	# ...AND THE SWORD'S OWN RIBBON, WHICH IS THE OTHER LARGE PLANE AND IS NOT A
	# CHILD OF THE VFX NODE. Measured: A3's still carried a pale band a metre
	# across, the detail camera's own cull list named nine meshes and all nine were
	# expected, and hiding three of them one at a time found the band was part of
	# `TempSwordVisual` -- the swept tip trail. §15's "lowered or switched off"
	# applies to it for the same reason it applies to the marks in space: it is
	# drawn over the two objects the clip is about.
	#
	# THE VALUE THAT IS PRINTED IS THE VALUE THAT WAS PASSED. The first version of
	# these three lines read the environment a second time for the message and
	# INVERTED THE COMPARISON in the call, so with `SEKAI_QA_VFX` unset the log
	# said `blade ribbon OFF` while the flag it actually set was `true`. A frame
	# dump at the A3 still then caught it: `trail_visible=true history=13`, a
	# 3.14 m ribbon, second-largest mesh in the frame -- on a build whose log
	# claimed the ribbon was off. Nothing looked wrong from either end alone,
	# which is what an inverted boolean in a single-use comparison does. One read,
	# one variable, used in both places.
	if sword != null and sword.has_method("set_trail_enabled"):
		sword.call("set_trail_enabled", full_vfx)
		print("§15: blade ribbon %s" % [
			"ON (SEKAI_QA_VFX=on)" if full_vfx else "OFF"])


func _build_rigs() -> void:
	detail_marker = Node3D.new()
	detail_marker.name = "SayaReviewMarker"
	detail_marker.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -0.4, -1.6))
	weapon_root.add_child(detail_marker)
	_build_backdrop()

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
	# private render layer so the world camera cannot see them. A camera that does
	# not include that bit photographs an empty stage and reports a clean take,
	# which is the worst possible failure: nothing was verified and every line of
	# output reads like success.
	# THE WORLD LAYER (bit 0) IS DELIBERATELY ABSENT FROM THE MAIN IMAGE.
	#
	# Not for tidiness. The solved camera sits BELOW the eye -- the scabbard rests
	# 0.79 m under it -- so the near floor comes up between the lens and the
	# backdrop: at a 0.76 m lens height the frame's bottom edge meets the ground
	# 2.1 m away, while the card is 4.6 m away, and the 2.5 m of arena in between
	# draws over it. Measured, on the take that made this comment: the bottom
	# third of the frame was floor and two long cast shadows that read as a second
	# phantom blade.
	#
	# So the measurement view is the WEAPON BIT AND THE CARD, and nothing else --
	# which is also §15, where the sword's own VFX (which defaults to layer 0) is
	# asked to be off in a Motion QA clip. The eye inset below keeps the whole
	# world, because where the player was looking is half of what it is for.
	detail_cam.cull_mask = WEAPON_LAYER | BACKDROP_LAYER
	detail_vp.add_child(detail_cam)

	eye_marker = Node3D.new()
	eye_marker.name = "EyeMarker"
	(player.get_node(SHOTGUN_PATH) as Node3D).add_child(eye_marker)

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
	eye_cam.cull_mask = 1 | WEAPON_LAYER
	eye_vp.add_child(eye_cam)

	sync = FrameSync.new()
	sync.name = "SayaFrameSync"
	sync.process_priority = 1000
	sync.pairs = [[detail_marker, detail_cam], [eye_marker, eye_cam]]
	if body_mode:
		_build_body_rig()
	root.add_child(sync)

	_build_overlay()


## §32's third-person rig: a review body, a camera that orbits it, and the floor
## the body has to stand on.
##
## THE FLOOR IS MEASURED FROM THE COLLISION SHAPE, NOT WRITTEN DOWN. `SayaReviewBody`
## was written against an eye 1.58 m up; the rig's actual figure is 0.65 + half the
## capsule, and the two differ by 30 mm. A body drawn 30 mm off the ground is not
## obviously wrong in a still -- it reads as a slightly odd stance -- so the error
## would survive review. Deriving it means re-tuning the capsule moves the body
## with it, and failing to find the capsule leaves the body legless and SAYS SO
## rather than drawing legs to a guessed height.
func _build_body_rig() -> void:
	body = ReviewBody.new()
	body.name = "SayaReviewBody"
	var rig := player.get_node_or_null("CameraRig") as Node3D
	if rig == null:
		_fails.append("the body mechanics mode needs `CameraRig` and it is not in this stage")
		return
	# UNDER `CameraRig`, deliberately: the body inherits the player's FACING and
	# nothing below it. See the header of `BODY_CAMS`.
	rig.add_child(body)
	# ASKED FOR, NOT RESTATED. See `_body_layer`.
	_body_layer = int(body.call("review_layer"))
	_measured_floor = _measure_floor()
	body.call("set_floor_drop", _measured_floor, _floor_source)
	print("body: %s" % str(body.call("floor_line")))

	body_marker = Node3D.new()
	body_marker.name = "SayaBodyMarker"
	rig.add_child(body_marker)

	body_vp = SubViewport.new()
	body_vp.name = "SayaBodyViewport"
	body_vp.size = VIEW
	body_vp.transparent_bg = false
	body_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	body_vp.handle_input_locally = false
	sandbox.add_child(body_vp)
	body_cam = Camera3D.new()
	body_cam.name = "SayaBodyCamera"
	body_cam.fov = BODY_FOV
	body_cam.near = 0.03
	body_cam.far = 400.0
	body_cam.current = true
	# NO WORLD, ONE FLOOR PLANE. See `_body_layer`: the arena's pillars end up
	# in front of the subject from half these positions, and the A4 frame arrived
	# with a black column across a quarter of it. The backdrop card stays out too --
	# it is the detail camera's own wall.
	body_cam.cull_mask = WEAPON_LAYER | _body_layer
	body_vp.add_child(body_cam)
	sync.pairs.append([body_marker, body_cam])
	_build_body_floor()

	var targets := BodyTargets.new()
	targets.name = "SayaBodyTargets"
	targets.combat = combat
	targets.sword = sword
	targets.body = body
	targets.process_priority = 5
	root.add_child(targets)

	# THE TWO VIEWPORTS THIS MODE DOES NOT READ ARE TURNED OFF. Each one is a full
	# 1920x1080 render per frame, and this file has already been bitten once by
	# spending its frame budget on pictures nobody looks at: the A4 act arrived as
	# three frames because the capture cost more than the act lasted. Leaving them
	# on would divide the delivery rate by three to produce two clips' worth of
	# pixels that are never saved.
	detail_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	eye_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


## How far the eye is above the floor, from the player's own collider.
func _measure_floor() -> float:
	_floor_source = ""
	var shape := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape == null:
		_fails.append("no `CollisionShape3D` under Player -- the body's legs cannot be placed")
		return 0.0
	var capsule := shape.shape as CapsuleShape3D
	if capsule == null:
		_fails.append("the player's collider is not a CapsuleShape3D -- the floor was not measured")
		return 0.0
	var rig := player.get_node_or_null("CameraRig") as Node3D
	if rig == null:
		return 0.0
	# Capsule height INCLUDES both caps, so the lower cap's surface is half a
	# height below the shape's own origin, and `position` puts that origin where
	# the designer put it.
	var bottom := shape.position.y - capsule.height * 0.5
	_floor_source = "CapsuleShape3D r %.2f h %.2f at y %+.2f" % [
		capsule.radius, capsule.height, shape.position.y]
	return rig.position.y - bottom


## The one piece of world §32's mode keeps: a plane at the measured floor.
##
## Parented under `CameraRig` rather than placed in the arena, because a flat plane
## rotated about Y is the same plane -- so the figure is always standing on it
## whichever way the player is facing, and it cannot be left behind by a take.
##
## Shaded, not unshaded, and that is a deliberate cost. An unshaded plane would be
## a constant tone from every camera, which is tidier, but it would also refuse the
## figure's own shadow -- and the shadow is the cheapest proof that the feet are on
## the floor rather than near it. A light albedo keeps it reading as ground.
func _build_body_floor() -> void:
	if _measured_floor <= 0.0:
		return
	var rig := player.get_node_or_null("CameraRig") as Node3D
	if rig == null:
		return
	var ground := MeshInstance3D.new()
	ground.name = "SayaReviewFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	# A DARK GROUND, ON PURPOSE, AND THE NUMBER COMES FROM THE LIGHTING.
	#
	# The floor's normal points up and the sun is above it, so the ground is always
	# at normal incidence while the figure's limbs are near grazing -- a mid-grey
	# floor therefore renders BRIGHTER than the body standing on it, and the third
	# body clip showed exactly that: a near-black figure on a pale plane, with the
	# measurements legible and the body not. At 0.165 the lit floor lands around a
	# sixth of white and every part of the figure clears it, so the silhouette reads
	# as LIGHT ON DARK from every camera -- and the saya's 0.052 lacquer still reads
	# as the darkest thing in the frame, which is the ordering the weapon passes
	# rely on.
	mat.albedo_color = Color(0.165, 0.170, 0.185)
	mat.roughness = 0.92
	mat.metallic = 0.0
	ground.material_override = mat
	# A plane facing +Y, one millimetre below the measured floor so the feet rest on
	# it rather than z-fighting with it.
	ground.position = Vector3(0.0, -_measured_floor - 0.001, 0.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.layers = _body_layer
	rig.add_child(ground)


# ===========================================================================
# THE SHOT CAMERA · solved from one act's own authored extent
# ===========================================================================

## Points that an act's own data says must be on screen, in `WeaponRoot` space.
##
## The blade's origin and tip and the saya's mouth and end, walked at 60 Hz for
## the four cuts and taken at the beats for the draw. 60 Hz because the sampled
## trajectory is a slerp and its extremes are not at the beats: A4's sweep
## between two beats passes outside both, and a frame solved from the beats alone
## cuts the tip off at the widest point of the one cut the whole pass is about.
func _act_points(move: SwordMove, steps: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if move == null:
		return out
	var blade := _blade_len()
	var body := SwordClasses.saya_body_len(SwordBasic.WEAPON_ID)
	if move.has_beats():
		# THERE ARE TWO WAYS A MOVE CAN DRIVE THE SCABBARD AND THE TABLE HAS TO
		# TAKE BOTH. `saya_positions` is where the mouth IS (the draw's seven
		# beats); `saya_ctrl_positions` is an offset from the LEFT HAND (A3's
		# anchor), and a move uses one or the other -- never both, and A3's
		# `saya_positions` is empty.
		#
		# Indexing it regardless crashed with "Out of bounds get index '0'" on
		# A3, returned an empty point list, and the framing solver then solved a
		# camera from nothing: `-inf x -inf` extents, a NaN transform and four
		# hundred lines of `!v.is_finite()` from the renderer. The check is on the
		# ARRAY's length rather than on the move, so a move that populates only
		# some of its beats is handled too.
		var has_saya_pose := move.saya_positions.size() == move.beat_times.size()
		var has_saya_rot := move.saya_rotations.size() == move.beat_times.size()
		for i in move.beat_times.size():
			var o: Vector3 = move.beat_positions[i]
			var b := Basis.from_euler(move.beat_rotations[i])
			out.append(o)
			out.append(o + b * Vector3.UP * blade)
			if not has_saya_pose:
				continue
			var m: Vector3 = move.saya_positions[i]
			var m_rot := Vector3.ZERO
			if has_saya_rot:
				m_rot = move.saya_rotations[i]
			out.append(m)
			out.append(m + Basis.from_euler(m_rot) * Vector3.UP * body)
	else:
		var total := move.total_time()
		for i in steps + 1:
			var snap := SwordPoseSampler.sample(move, total * float(i) / float(steps))
			var p: Vector3 = snap["position"]
			var b := Basis.from_euler(snap["rotation"] as Vector3)
			out.append(p)
			out.append(p + b * Vector3.UP * blade)
	# The saya's anchors are the other half of every act: A3 lifts the mouth to an
	# anchor the blade never visits, and A4's clear is a motion of the SAYA.
	#
	# `saya_ctrl_positions` are OFFSETS FROM THE HAND, not poses of their own --
	# see `SwordSayaRig.seat_home`, which builds the transform out of (hand,
	# offset). Appending them raw would put a point at the origin of WeaponRoot
	# -- the player's eye -- and the solver would then frame the entire room to
	# include a point that does not exist. They are added to the hand's own base,
	# which is what `seat_home` does.
	var base := SwordBasic.saya_home()
	var hand_basis := Basis.from_euler(SwordBasic.SAYA_MOUTH_R)
	out.append(base)
	out.append(base + hand_basis * Vector3.UP * body)
	for i in move.saya_ctrl_positions.size():
		var mouth: Vector3 = base + move.saya_ctrl_positions[i]
		out.append(mouth)
		out.append(mouth + hand_basis * Vector3.UP * 0.22)
	return out


## Places the detail camera for one act, perpendicular to the bore with the
## world's own up as its own up, so the assembly's travel maps across the frame
## and nothing important is hidden in depth. Roll is zero on purpose: a roll is a
## second, unstated piece of framing on top of a question that is already about a
## transform.
# ===========================================================================
# §32 · WHICH ACT IS FILMED FROM WHERE, AND WHAT THE FRAME SAYS
# ===========================================================================
#
# Keyed on the label the takes ALREADY pass to `_aim_detail`, because that label is
# the act's own name and re-deriving it from a title string would break the moment
# somebody rewords a caption. An act with no entry is a FAILURE rather than a
# silent reuse of the previous camera: a clip in which two acts were filmed from
# one position and nobody noticed is exactly the kind of thing a motion QA pass
# exists to not do.
const BODY_ACT_CAMS := {
	"idle": "front_left",
	"draw": "front_left",
	"put_away": "side_right",
	"cut 0": "front_left",
	"cut 1": "side_right",
	"cut 2": "front_wide",
	"cut 3": "side_wide",
	"iaido": "rear_left",
	"outro": "front_left",
}

## The words, per act. `title | caption | note-tail`. The note always ends with the
## two measurements this mode is for -- how far the arms fall short, and where the
## floor was taken from -- because both are statements about the picture that
## nothing in the picture can confirm on its own.
const BODY_SHOTS := {
	"idle": ["BODY MECHANICS · THE LEFT HAND ON THE SAYA",
		"§30: the left wrist is SOLVED onto the rig's own hand point every frame, so the arm cannot disagree with the scabbard -- a fix to one is a fix to both. §1: the hand is holding something, and this is the first take in the project where that is visible. THE BLUE LIMB IS THE LEFT ARM: §30 is a claim about one limb, and in a shot where a body does several things at once, finding it is the reviewer's first problem.",
		"With nothing asked of it, the arm should hang quiet and the scabbard should breathe in it."],
	"draw": ["DRAW · THE LEFT HAND LEADS THE MOUTH UP",
		"§4/§5: the hand carries the koiguchi up past the hip and the arm is ALIVE doing it. Watch the ELBOW: it stays under the wrist. When the arm is solved to the hand point, an elbow that flies out means the POLE, not the pose.",
		"§18/§20: the blade's orientation is continuous across the seat -- the seven beats are the reason."],
	"put_away": ["PUT AWAY · THE SAME HAND PUTS IT BACK",
		"§18: the return is the draw read backwards, so the orientation that was continuous on the way out is continuous on the way in.",
		"Side-on, because the seat is a relationship along the bore's axis and from the front that axis points at the lens."],
	"cut 0": ["A1 · COUNTER-PULL -- THE LEFT HAND GOES BACK",
		"§7-§9: 3-6 cm back and left, countering the draw, held 80-150 ms. THIS IS THE BEAT WHERE THE LEFT HAND MOVES AND THE RIGHT DOES NOT, and it is the first thing a third-person camera can settle that a tight shot cannot.",
		"The scabbard is being drawn from. If it travels WITH the blade, §7 is decorative."],
	"cut 1": ["A2 · CLEAR THE BLADE PATH",
		"§10-§11: LEFT / DOWN / IN, 3-8 cm. The hand is not waving -- it is vacating a line, and the line is visible from here as the gap between the two objects.",
		"Side-on, because 'cleared' is a distance and a distance needs a plane to be read against."],
	"cut 2": ["A3 · THE ANCHOR -- THE HAND HOLDS, THE SWORD CUTS",
		"§12-§15: the left hand holds the mouth at the anchor while three cuts happen in front of it. This is the act the whole pass is about: if the hand follows the sword here, §13 is broken and §1's 'controlled' has no content.",
		"§13's reciprocation is on the SWORD side of this pair -- the mouth receives it, it does not chase it."],
	"cut 3": ["A4 · GET OUT OF THE WAY",
		"§16-§17: the saya's only job in this act. Movement is the entire requirement and the direction is negotiable, which is why this is the one act where a large excursion is not a fault.",
		"Side-on, because the blade plane is the thing being vacated."],
	"iaido": ["IAIDO · ONE CONTROLLED ROTATION, FROM THE BODY",
		"§21-§26: TWO SPINS ARE DELETED. One rotation, 270-360 deg, whose job is to reset the EDGE ORIENTATION. From here the claim under test is about the BODY: the arm turns the blade, the body does not throw it, and the scabbard is not what is being turned.",
		"Rear three-quarter, because a yaw and a camera move are the same picture from the front."],
	"outro": ["CONTROLLED STILLNESS · MEASURED IN THIS TAKE",
		"The same instrument as the detail clip, plus the two numbers only a body can produce: how far the arm falls short of what it is holding, and how far the floor is from the eye. Neither is visible in the picture and both are statements about it. If the shortfall is not zero, the rig is asking for an arm longer than a human's -- and no amount of tuning the scabbard will change that, because the scabbard is being placed where the HAND is.",
		"§38's P0 is CONTROLLED SAYA BODY CONNECTION. This clip is the evidence for it."],
}


## Films the current act from outside the player. Called by `_aim_detail`, so the
## takes do not know this mode exists.
func _aim_body(label: String) -> void:
	if body_marker == null or body_cam == null or body == null:
		return
	_act_key = label
	var want: String = String(BODY_ACT_CAMS.get(label, ""))
	if want == "":
		_fails.append("no body camera is named for act `%s`" % label)
		want = String(BODY_CAMS[0][0])
	var eye_at := Vector3.ZERO
	var aim_at := Vector3.ZERO
	var fov := BODY_FOV
	var found := false
	for pair in BODY_CAMS:
		if String(pair[0]) != want:
			continue
		eye_at = pair[1]
		aim_at = pair[2]
		if pair.size() > 3:
			fov = float(pair[3])
		found = true
		break
	if not found:
		_fails.append("body camera `%s` is not in BODY_CAMS" % want)
		return
	body_cam.fov = fov
	_body_cam = want
	if not _body_cams_used.has(want):
		_body_cams_used.append(want)
	# `Basis.looking_at` puts the basis's -Z on the target direction, which is the
	# direction a `Camera3D` looks. Written as a local transform under `CameraRig`
	# so the camera rides the player's yaw and is deaf to everything below it.
	body_marker.transform = Transform3D(
		Basis.looking_at((aim_at - eye_at).normalized(), Vector3.UP), eye_at)
	print("   body cam `%s` for `%s`" % [want, label])


func _aim_detail(points: Array[Vector3], label: String) -> void:
	# THE SEAM. §32's mode films the same acts from outside the player, so the
	# solved framing is not used at all -- but the TAKE that is running, the order
	# it runs in and the requests it makes are the same code either way. One branch
	# here is the whole of the difference in the camera; `_shot` has the other one,
	# for the words.
	if body_mode:
		await _aim_body(label)
		return
	var bore: Vector3 = SwordBasic.NE_CARRY_DIR.normalized()
	var right := Vector3(bore.x, 0.0, bore.z).normalized()
	var up := Vector3.UP
	var back := right.cross(up)

	# ---- THE SAFE BAND, AND WHY THIS IS SOLVED IN CLOSED FORM -------------
	#
	# The composite's inset owns x 880-1264, y 456-688. `_diag()` put the saya's
	# mouth at (939, 437) and its butt at (989, 690) on the first take: the
	# scabbard was in frame and BEHIND the picture-in-picture, which is a fault
	# no reading of the code would have produced. So the frame the solver is
	# given is the part of the picture the inset does not own.
	#
	# Work in the frame's own normalised view coordinate `v`: 0 is the middle of
	# the frame, +1 is its top edge, and screen y = (VIEW.y/2)(1 - v). With
	# b = SAFE_H / VIEW.y the band is v in [1 - 2b, 1]: centre 1 - b, half b. So
	# `ky` is scaled by `b` and the subject's centre goes at `1 - b`.
	#
	# IT IS SOLVED IN ONE PASS, NOT ITERATED. The obvious loop -- shift the
	# target, re-solve the distance, repeat -- has TWO fixed points. Centring the
	# content on the camera axis and then correcting for the offset converges to
	# 6.64 m; centring it on the band's centre converges to 6.36 m; the answer is
	# 2.68 m and neither iteration finds it. The subject came out occupying 91 px
	# of a 456 px band, and every step of the arithmetic looked reasonable.
	#
	# The closed form is: pin the content's centre to the band's centre, and ask
	# each point how far back the camera must be for IT to project inside. A
	# point's own view depth is `d - (p - target).back`, so the constraint
	# `|lateral| <= k * depth` gives `d >= |lateral|/k + (p - target).back` --
	# exactly, per point, in one line, with no fixed point to miss.
	var tan_half := tan(deg_to_rad(DETAIL_FOV * 0.5))
	var band := float(SAFE_H) / float(VIEW.y)
	var safe_c := 1.0 - band
	var kx := tan_half * (float(VIEW.x) / float(VIEW.y))
	var ky := tan_half * band

	var up_mid := 0.0
	var right_mid := 0.0
	var back_mid := 0.0
	var lo_up := INF
	var hi_up := -INF
	var lo_right := INF
	var hi_right := -INF
	var lo_back := INF
	var hi_back := -INF
	for p in points:
		var u := p.dot(up)
		var r := p.dot(right)
		var b := p.dot(back)
		lo_up = minf(lo_up, u)
		hi_up = maxf(hi_up, u)
		lo_right = minf(lo_right, r)
		hi_right = maxf(hi_right, r)
		lo_back = minf(lo_back, b)
		hi_back = maxf(hi_back, b)
	up_mid = (lo_up + hi_up) * 0.5
	right_mid = (lo_right + hi_right) * 0.5
	back_mid = (lo_back + hi_back) * 0.5

	var distance := 0.2
	for p in points:
		var behind := p.dot(back) - back_mid
		# Vertical: the band's half-height is `b` in frame units, so `ky` is the
		# divisor and the content's own half-extent `E/2` is what has to fit.
		distance = maxf(distance, absf(p.dot(up) - up_mid) / ky + behind)
		# Horizontal: the full width, because the inset is at the bottom rather
		# than at the side.
		distance = maxf(distance, absf(p.dot(right) - right_mid) / kx + behind)
		# ...and the camera has to be in FRONT of every point, not merely far
		# enough away from the middle of them.
		distance = maxf(distance, behind + 0.25)
	distance *= DETAIL_MARGIN

	# The target's up coordinate carries the whole of the offset: the camera axis
	# points at the BAND's centre, which is `1 - b` up the frame from the
	# content's own centre.
	var target := right * right_mid \
		+ up * (up_mid - safe_c * tan_half * distance) \
		+ back * back_mid
	var position := target + back * distance
	# `Basis.looking_at()` rather than `look_at_from_position()`: the latter reads
	# its target in GLOBAL coordinates and this marker is set before it is in the
	# tree, so the target would be interpreted in the wrong frame.
	detail_marker.transform = Transform3D(
		Basis.looking_at(target - position, Vector3.UP), position)
	_shot_extent = Vector2(hi_right - lo_right, hi_up - lo_up)
	_place_backdrop(target, back, distance)
	_diag_pending = label
	print("   shot `%s`: extent %.3f x %.3f m, camera %.3f m back" % [
		label, _shot_extent.x, _shot_extent.y, distance])


## ===========================================================================
## THE REVIEW BACKDROP, AND WHY THE FIRST TAKE NEEDED ONE
## ===========================================================================
## Photographed from the weapon's own frame, this assembly sits in the middle of
## a staged arena with the sun behind it. The first take came out with the saya
## -- lacquer at albedo 0.052 -- drawn across a dark horizon band, so the one
## object the whole pass is about was a black shape on a black shape, and the
## sword's cast shadow lay across the frame as a second, phantom blade.
##
## None of that is the sword line's fault and all of it makes the clip unusable
## for judging motion. So the measurement view gets a card: an UNLIT mid-grey
## plane placed between the camera and the world, on its own render layer.
##
## It is unlit on purpose. `SHADING_MODE_UNSHADED` means the verdict cannot be
## changed by where the sun happens to be, and it cannot receive the weapon's own
## shadow -- which is the difference between a card and another surface that
## makes its own pictures. It is on `BACKDROP_LAYER` rather than `WEAPON_LAYER`
## so the eye inset, which has the weapon's bit, still shows the real world: the
## reader gets a clean card for the measurement and the real frame beside it.
func _build_backdrop() -> void:
	backdrop = MeshInstance3D.new()
	backdrop.name = "SayaReviewBackdrop"
	var quad := QuadMesh.new()
	# Generously larger than the frame at any solved distance. It is flat and
	# unshaded, so size costs nothing and a card that only just covers the frame
	# would show a corner of the arena at the extremes of A4.
	quad.size = Vector2(20.0, 12.0)
	backdrop.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# LIGHT, NOT MID, AND THE SAYA IS WHY. The card's first value was mid-grey
	# (0.21) and the object this whole pass is about -- lacquer at albedo 0.052 --
	# came out as a near-black bar on a dark-grey field, which is the same failure
	# the card was built to fix, one stop over. The blade is the light subject and
	# the saya is the dark one, so the card has to sit ABOVE both: at 0.40 the saya
	# reads as a solid dark shape and the blade still separates from the field.
	mat.albedo_color = Color(0.400, 0.420, 0.450)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	backdrop.material_override = mat
	# It must not enter the shadow pass either: an unshaded plane still casts one,
	# and a 20 m card dropping a shadow across the arena would be a change to the
	# scene rather than to the review.
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.layers = BACKDROP_LAYER
	backdrop.visible = false
	weapon_root.add_child(backdrop)


## Puts the card BEHIND the assembly, for this shot.
##
## BEHIND, not in front: `back` points from the target TOWARD the camera, so
## `target + back * distance` is the camera itself. The first version wrote
## `distance - 0.35` there, which is 35 cm in front of the lens and 2.8 m in
## front of the subject -- a card that covered the blade, the scabbard and the
## whole frame, and did it so thoroughly that the take looked like a rendering
## fault rather than a sign error.
func _place_backdrop(target: Vector3, back: Vector3, distance: float) -> void:
	backdrop.visible = true
	# A `QuadMesh` faces its own +Z, and the camera is further along `+back`, so
	# the quad's +Z has to point along `+back`: `Basis.looking_at(-back, up)` puts
	# its -Z on `-back`, which leaves +Z on `back`.
	#
	# 1.4 m beyond the subject is outside every solved extent (the widest act is
	# 1.83 m across and its deepest 0.3 m), so nothing the shot is about is
	# between the card and the lens.
	backdrop.transform = Transform3D(
		Basis.looking_at(-back, Vector3.UP), target - back * 1.4)


## Every mesh this camera can actually draw, largest-first, with the path that
## names it.
func _detail_intruders(cam: Camera3D) -> Array:
	var found: Array = []
	_collect_intruders(sandbox, sandbox, cam, found)
	found.sort_custom(func(a, b) -> bool: return float(a["size"]) > float(b["size"]))
	if found.size() > 14:
		found.resize(14)
	return found


func _collect_intruders(node: Node, root: Node, cam: Camera3D, out: Array) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.is_visible_in_tree() and (mesh_node.layers & cam.cull_mask) != 0:
			var aabb := mesh_node.get_aabb()
			var size := aabb.size.length()
			if size > 0.10:
				var centre := mesh_node.global_transform * aabb.get_center()
				out.append({
					"path": str(root.get_path_to(mesh_node)),
					"layers": mesh_node.layers,
					"size": size,
					"dist": centre.distance_to(cam.global_position),
				})
	for child in node.get_children():
		_collect_intruders(child, root, cam, out)


## WHAT IS IN THE FRAME, ASKED AT THE FRAME.
##
## `_diag` already asks this question and it is the right question -- but it is
## asked once per act, at the moment the act OPENS, and the thing being hunted is
## a transient that only exists inside an act. Two rounds of solo hiding had
## already narrowed it to "something about the sword during A3" and then failed to
## catch it, because every solo frame was taken a second after the still it was
## compared against.
##
## So this asks the same question at the one moment the answer is known to be
## live: inside `_copy_still`, where the PNG being written IS the frame in
## question. It costs nothing unless `SEKAI_VFX_DUMP` is set, and it prints at
## `push_warning` level so a normal delivery log stays readable.
##
## Three roots are walked rather than one. `sandbox` holds the scene, but the VFX
## layer is parented by `CombatController` into whatever it decided the world is,
## and this file does not get to assume those are the same node -- the whole point
## of the pass is that assumptions about who owns what have been wrong before.
func _dump_frame(tag: String) -> void:
	var cam := detail_cam
	print("   == frame dump at `%s` (frame %d, t=%.2fs) ==" % [tag, frame_index - 1, _t])
	var roots: Array = [["sandbox", sandbox]]
	var vfx: Variant = combat.get("sword_vfx")
	if vfx != null and is_instance_valid(vfx):
		roots.append(["vfx", vfx as Node])
	for pair in roots:
		var root: Node = pair[1]
		if root == null or not is_instance_valid(root):
			continue
		var found: Array = []
		_collect_intruders(root, root, cam, found)
		found.sort_custom(func(a, b) -> bool: return float(a["size"]) > float(b["size"]))
		print("      root `%s`: %d mesh(es) this camera can draw" % [pair[0], found.size()])
		for entry in found:
			print("        %-58s layers %-7d aabb %7.2f m  %6.2f m away" % [
				entry["path"], entry["layers"], entry["size"], entry["dist"]])
	# The counts the VFX layer keeps about itself. `scars` is the one that matters:
	# §15's switch was thrown and the count says whether it took -- a plane built
	# BEFORE the switch is still a plane in the frame, and this is the number that
	# distinguishes "the switch did not work" from "the band is not a scar".
	if vfx != null and is_instance_valid(vfx) and vfx.has_method("debug_readout"):
		var readout: Dictionary = vfx.call("debug_readout")
		print("      vfx readout: move=%s events=%s waves=%s scars=%s arc_bands=%s domain=%s" % [
			readout.get("move", ""), readout.get("events_fired", 0),
			readout.get("waves", 0), readout.get("scars", 0),
			readout.get("arc_bands", 0), readout.get("domain", false)])
	if sword != null and is_instance_valid(sword):
		var trail: Variant = sword.get("trail")
		var history: Variant = sword.get("trail_history")
		print("      sword: trail_enabled=%s trail_visible=%s history=%s exposure=%s" % [
			str(sword.get("trail_enabled")),
			str(trail != null and (trail as Node3D).visible),
			str((history as Array).size() if history != null else "?"),
			str(sword.get("void_exposure"))])


## WHERE THE TWO OBJECTS ACTUALLY LANDED, in pixels, printed once per shot.
##
## This exists because the first take of this clip shipped a frame in which the
## blade and the scabbard were drawn on top of each other, and reading the code
## said they were 0.92 m apart. The code was right about the inputs and wrong
## about the output, and the only way that gets settled is by asking the camera
## where it put them -- `unproject_position` is the composite's own arithmetic,
## so a disagreement between it and the picture is impossible.
##
## It is not a gate. It is the printout that makes a bad frame a number.
func _diag(label: String) -> void:
	var cam := detail_cam
	print("   diag `%s` · camera at %s looking %s (right %s)" % [
		label, _v3(cam.global_position), _v3(-cam.global_basis.z),
		_v3(cam.global_basis.x)])
	for pair in [["saya_mouth", SwordBasic.saya_home()],
			["saya_butt", SwordBasic.saya_home()
				+ Basis.from_euler(SwordBasic.SAYA_MOUTH_R) * Vector3.UP * 0.80],
			["sword_grip", sword.position]]:
		var local: Vector3 = pair[1]
		var world: Vector3 = weapon_root.global_transform * local
		var screen := cam.unproject_position(world)
		print("      %-11s local %s -> screen (%4.0f, %4.0f)%s" % [
			pair[0], _v3(local), screen.x, screen.y,
			"   BEHIND THE CAMERA" if cam.is_position_behind(world) else ""])
	# WHAT ELSE IS IN THIS FRAME. The measurement camera culls to two layers, and
	# a large pale band appeared across A3 that belonged to neither of the two
	# objects the shot is about -- with a 10 % VFX damping and the Spatial Cut
	# planes switched off. Reading the code could not say what it was; asking the
	# camera can, because a mesh either reaches this camera or it does not.
	for entry in _detail_intruders(cam):
		print("      in frame: %-44s layers %-7d aabb %.2f m  %.2f m away" % [
			entry["path"], entry["layers"], entry["size"], entry["dist"]])


## The sword's own VISUAL length, not `SwordClasses.blade_reach`.
##
## `blade_reach` is 0.7608 m: the distance from the tsuba to the tip, which is
## what a MOUNT inside a tube needs. The RENDERED sword is a different object --
## `TempSwordVisual.blade_length` comes from `Registry.visual_length()` and is
## what `_pose_tip()` uses -- and the first take of this clip cut the tip off the
## top of the frame by framing against the smaller of the two.
func _blade_len() -> float:
	var visual: Variant = sword.get("blade_length")
	if visual == null:
		return SwordClasses.blade_reach(SwordBasic.WEAPON_ID)
	return float(visual)


func _v3(v: Vector3) -> String:
	return "(%+.3f, %+.3f, %+.3f)" % [v.x, v.y, v.z]


# ===========================================================================
# THE TAKES
# ===========================================================================

func _take_idle() -> void:
	await _ensure_idle()
	_silence()
	await _aim_detail(_idle_points(), "idle")
	_shot("idle", "THE SAYA · CONTROLLED STILLNESS · PASS 02",
		"§1: it follows the LEFT HAND -- not the sword, and not nothing. §5: with the blade out it breathes 0.5-1.5 cm.",
		"Solved tight on the mouth: this frame is %.2f m across, so 9 mm of breath is %.0f px. | Inset: the player's own view." % [
			_shot_extent.x, 9.0 / maxf(_shot_extent.x, 0.001) * float(VIEW.x)])
	_set_note("Framed TIGHT on the mouth, because 9 mm of breath in a 2.6 m frame is two pixels.")
	await _capture_for(2.0)
	_set_note("")
	await _capture_for(0.2)

## The idle's own extent: the saya, the seated blade's stub, AND WHEREVER THE
## BLADE ACTUALLY IS.
##
## The last one is not decoration. The first version framed the saya alone, and
## the take shipped a frame with a 0.95 m blade shearing out of the top edge --
## because a drawn sword at `IDLE_POSITION` (x = +0.52) is a metre away from a
## scabbard held at (x = -0.40), and a frame that contains only the second of
## those is not a frame of anything a person would recognise.
##
## It is read LIVE rather than from the pose constants, so the shot frames the
## blade that is on screen rather than the blade the data says should be.
func _idle_points() -> Array[Vector3]:
	var body := SwordClasses.saya_body_len(SwordBasic.WEAPON_ID)
	var blade := _blade_len()
	var out: Array[Vector3] = [
		SwordBasic.saya_home(),
		SwordBasic.saya_home() + Basis.from_euler(SwordBasic.SAYA_MOUTH_R) * Vector3.UP * body,
		SwordBasic.saya_home() + Basis.from_euler(SwordBasic.SAYA_MOUTH_R) * Vector3.UP * 0.30,
	]
	var grip: Vector3 = sword.position
	var sb := Basis.from_euler(sword.rotation as Vector3)
	out.append(grip)
	out.append(grip + sb * Vector3.UP * blade)
	out.append(grip - sb * Vector3.UP * 0.24)
	return out


func _take_draw() -> void:
	await _ensure_sheathed()
	await _ensure_idle()
	_silence()
	await _aim_detail(_act_points(SwordBasic.equip(), 0), "draw")
	_shot("draw", "DRAW · 拔刀 · SEVEN BEATS",
		"§19-§20: beats 0-6, and the ORIENTATION between any two of them travels an ARC, never a straight line through angle space.",
		"§27: from Beat 1 to Beat 4 the mouth is HELD, because a blade with 1.75 mm of clearance is coming through it.")
	_arm_stills([
		{"tag": "draw_1_carry", "when": Callable(self, "_draw_past").bind(0.21)},
		{"tag": "draw_2_partial", "when": Callable(self, "_draw_past").bind(0.43)},
		{"tag": "draw_5_stance", "when": Callable(self, "_draw_home")},
	])
	_set_note("§4/§5: the hand is ALIVE here -- it carries the mouth up.")
	# CHECKED. `equip_weapon` on the weapon already held is a documented no-op
	# (§1: pressing 1 while holding the sword must not restart the sword), so an
	# unconditional call here films nothing and says it filmed a draw.
	var asked: bool = manager.call("equip_weapon", slot.SWORD)
	if not asked:
		_fails.append("the draw was refused (slot=%s, blend=%.3f)" % [
			str(slot.kind), float(combat.equip_blend)])
		return
	await _capture_until_drawn()
	_check_armed("draw")
	_set_note("")
	await _capture_for(0.5)


func _take_put_away() -> void:
	await _ensure_drawn()
	await _ensure_idle()
	_silence()
	# THE BODY MODE RE-AIMS HERE AND THE DETAIL MODE DOES NOT, and that asymmetry is
	# deliberate. The detail camera is solved from the act's authored extent, and the
	# put-away's extent IS the draw's -- the same seven beats, the clock reversed --
	# so re-solving would put the lens in the same place after a second of
	# arithmetic. §32's cameras are not solved from anything: they are named
	# positions, so an act that does not ask for one keeps the previous act's, and
	# `BODY_ACT_CAMS` would be claiming `side_right` while the clip filmed
	# `front_left`. A table nothing consults is worse than no table.
	if body_mode:
		await _aim_body("put_away")
	_shot("put_away", "PUT AWAY · 收刀",
		"The same seven beats, read BACKWARDS. One table, two directions -- so the two cannot drift apart.",
		"§20: the last segment is not special-cased. It is Beat 1 of the draw with the clock reversed.")
	_arm_stills([{"tag": "draw_reversed", "when": Callable(self, "_sheathing")}])
	var asked: bool = manager.call("equip_weapon", slot.CHAIN)
	if not asked:
		_fails.append("the put-away was refused (slot=%s)" % str(slot.kind))
		return
	# THE WAIT IS THE ACT'S OWN LENGTH, NOT A NUMBER SOMEBODY PICKED. This was a
	# flat `_capture_for(2.4)` against a 1.75 s sheathe -- a hope, and one that
	# stops being true the moment the act is re-timed.
	await _capture_until_sheathed()
	_check_armed("put away")
	_set_note("")
	await _capture_for(0.3)


## One act of the four-cut sentence. `index` selects the light chain, exactly as
## Pass 01 did; `slow` replays the reviewed beat at `SLOW_SCALE`.
func _take_cut(index: int, title: String, caption: String, still: String,
		slow: bool) -> void:
	await _ensure_drawn()
	await _ensure_idle()
	_silence()
	var expected: StringName = combat.moveset.light_chain[index]
	var move := combat.moveset.get_move(expected)
	await _aim_detail(_act_points(move, 96), "cut %d" % index)
	_shot("cut %d" % index, title, caption,
		"Solved from this act's own beats at 60 Hz: %.3f x %.3f m. Camera fixed for the whole shot." % [
			_shot_extent.x, _shot_extent.y])
	# Run the earlier beats of the sentence at full speed so the reviewed one
	# arrives on a body that has already committed, then slow ONLY the act.
	for i in index:
		if not combat.request(&"light"):
			_fails.append("A%d could not be reached: a light attack was refused" % (index + 1))
			return
		if not await _advance_to_cancel():
			# The cancel window was missed, so the sentence ended here. The
			# assertion below will say which move the last request produced; this
			# says why, and the two together are the whole diagnosis.
			print("    (A%d's chain ended at step %d -- the cancel window was missed)"
				% [index + 1, i + 1])
			break
	if slow:
		Engine.time_scale = SLOW_SCALE
		_set_note("0.25x. §14's reciprocation is 15 mm and four frames long at full speed.")
	# CHECKED. An unchecked `request` here is how four acts went missing: it
	# returned false, `_capture_until_idle` found the state it was waiting to
	# leave already true and returned on its first test, and the take reported a
	# complete run with nothing in it.
	if not combat.request(&"light"):
		_fails.append("A%d refused a light attack (blade out=%s, state=%d)" % [
			index + 1, str(_blade_is_out()), combat.state])
		Engine.time_scale = 1.0
		return
	# AND THE ANSWER IS CHECKED. `request` returning true says "a light attack
	# started"; it does not say WHICH, and the chain's index is the thing that
	# decides it. Asserting it here turns "three stills went missing" into "asked
	# for sb_a2 and got sb_a3", which is a diagnosis.
	if combat.active_move_id != expected:
		_fails.append("A%d: asked for the chain's %s and got %s" % [
			index + 1, str(expected), str(combat.active_move_id)])
		Engine.time_scale = 1.0
		return
	_arm_stills([{"tag": still, "when": func() -> bool:
		return combat.active_move_id == expected and _past_settle(expected)}])
	await _capture_until_idle()
	_check_armed("cut %d" % index)
	Engine.time_scale = 1.0
	_set_note("")
	await _capture_for(0.35)


## §21-§26. The ceremony, run through the REAL entrance, with the ONE ROTATION
## (§22) replayed at a quarter speed.
##
## The rotation is where the pass made its largest claim -- "TWO SPINS" deleted,
## replaced by one controlled rotation whose job is to RESET THE EDGE ORIENTATION
## -- and 1.0 s of ceremony time is 30 frames. Thirty frames is not enough to see
## whether the blade arrives on the bore's axis or merely near it.
func _take_recovery() -> void:
	await _ensure_drawn()
	await _ensure_idle()
	_silence()
	await _aim_detail(_iaido_points(), "iaido")
	_shot("iaido", "IAIDO · ONE CONTROLLED ROTATION · 0.25x",
		"§21-§26: TWO SPINS are DELETED. One rotation, 270-360 deg, out of the forearm and wrist, and the blade arrives ON the bore's axis.",
		"§25: Spine -> Saya Guide -> MOUTH CATCH -> Final Sheathe -> CLICK. HUMAN MOTION > NUMBER.")
	_arm_stills([
		{"tag": "iaido_rotation", "when": Callable(self, "_iaido_past").bind(6.90)},
		{"tag": "iaido_catch", "when": Callable(self, "_iaido_past").bind(7.55)},
		{"tag": "iaido_click", "when": Callable(self, "_iaido_past").bind(8.45)},
	])
	combat.set("iaido_ready_at", 0.0)
	player.set("stamina", 100.0)
	# ONLY THE TURN RUNS SLOW, AND THAT IS §33 SPENT CAREFULLY.
	#
	# The first version put the whole ceremony on `Engine.time_scale = 0.25`,
	# which is 9.9 s of ceremony time stretched over forty seconds of wall -- forty
	# seconds of clip, out of a brief that asks for twenty to thirty-five. The
	# turn is the claim (§22), it is 0.62 s of the nine, and slowing only it buys
	# the extra frames exactly where they are needed.
	#
	# THE WINDOW IS THE PROBE'S, TOO. `probe_iaido_recovery.gd` measures §22 over
	# `[spin_start, lerp(spin_start, spin_end, spin_turn_share)]` -- the turn and
	# not the catch §23 that follows it in the same phase. Slowing exactly the
	# window the number is taken over means the pictures and the figure are about
	# the same 0.62 s.
	#
	# Everything is read off the TUNING resource rather than typed in: a second
	# copy of `spin_start` here is a copy that goes stale the moment the ceremony
	# is re-timed. The 0.10 s of margin puts the entry and the exit INSIDE the
	# slow passage, so the ramp is not what the viewer sees at the boundary.
	var tuning: Resource = director.get("tuning")
	_turn_from = float(tuning.get("spin_start"))
	_turn_to = lerpf(_turn_from, float(tuning.get("spin_end")),
		float(tuning.get("spin_turn_share")))
	var spin_from := _turn_from - 0.10
	var spin_to := _turn_to + 0.10
	if not combat.request(&"iaido"):
		_fails.append("the iaido ceremony refused to start (blade out=%s, state=%d)" % [
			str(_blade_is_out()), combat.state])
		return
	_set_note("0.25x across the TURN (%.2f-%.2f s of the ceremony, the window §22 is measured over). Watch the EDGE, not the tip: a pure roll about the blade's own axis moves the tip 0.00 m."
		% [spin_from, spin_to])
	var slow := false
	var guard := 0
	while combat.state == CombatController.State.IAIDO and guard < 6000:
		var elapsed := -1.0
		if bool(director.get("active")):
			elapsed = float(director.get("elapsed"))
		var want := elapsed >= spin_from and elapsed <= spin_to
		if want != slow:
			slow = want
			Engine.time_scale = SLOW_SCALE if slow else 1.0
		await _capture_one()
		guard += 1
	Engine.time_scale = 1.0
	_check_armed("iaido")
	_set_note("")
	await _capture_for(0.8)


## The ceremony's extent, taken from the three places the blade is: the seat, the
## drawn pose, and the scabbard's own rest.
##
## `drawn_position` / `drawn_rotation` live on the TUNING resource, not on the
## director -- the director only ever holds them for the length of a phase -- and
## they are read through `director.tuning` rather than re-derived, because a
## second copy of the drawn pose is exactly the kind of copy that goes stale.
func _iaido_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var blade := _blade_len()
	var tuning: Resource = director.get("tuning")
	var seat: Vector3 = director.get("seat_origin")
	var basis: Basis = director.get("seat_basis")
	var drawn: Vector3 = tuning.get("drawn_position")
	var drawn_basis := Basis.from_euler(tuning.get("drawn_rotation") as Vector3)
	out.append(seat)
	out.append(seat + basis * Vector3.UP * blade)
	out.append(drawn)
	out.append(drawn + drawn_basis * Vector3.UP * blade)
	out.append(drawn - drawn_basis * Vector3.UP * 0.26)
	out.append(SwordBasic.saya_home())
	out.append(SwordBasic.saya_home()
		+ Basis.from_euler(SwordBasic.SAYA_MOUTH_R) * Vector3.UP
			* SwordClasses.saya_body_len(SwordBasic.WEAPON_ID))
	return out


func _outro() -> void:
	_act_key = "outro"
	if body_mode:
		var body_shot: Array = BODY_SHOTS.get("outro", [])
		if not body_shot.is_empty():
			shot_label.text = String(body_shot[0])
			caption_label.text = String(body_shot[1])
			note_label.text = "%s  ·  %s  ·  %s" % [
				String(body_shot[2]), _body_reach_line(), _body_floor_line()]
		await _capture_for(2.0)
		return
	shot_label.text = "CONTROLLED STILLNESS · MEASURED IN THIS TAKE"
	caption_label.text = _verdict_line()
	note_label.text = "Same instrument as probe_saya_control.gd. A frame carrying the mouth more than %.0f mm would have failed this run, and so would a mouth that never moved at all." % (JUMP_LIMIT * 1000.0)
	await _capture_for(2.0)


## The body's own two numbers, worded by the body itself so this file cannot
## re-derive them and disagree. It asks the node rather than reading `floor_drop`,
## for the same reason the detail clip reads the controller instead of the pose.
func _body_reach_line() -> String:
	if body == null or not is_instance_valid(body) or not body.has_method("reach_line"):
		return "no body in this take"
	return String(body.call("reach_line"))


func _body_floor_line() -> String:
	if body == null or not is_instance_valid(body) or not body.has_method("floor_line"):
		return "no floor in this take"
	return String(body.call("floor_line"))


# ===========================================================================
# CAPTURE
# ===========================================================================
#
# THERE WAS A SOLO PROBE HERE AND IT IS GONE ON PURPOSE. `_solo_frames()` hid
# `VoidRim`, `EdgeGlint`, `BladeTrail`, `Sword_FP` and the rig one at a time and
# kept a frame of each; it found nothing, five times, because every solo frame was
# taken a second after the still it was being compared against and the thing being
# hunted was a transient that did not survive the second. What found it was
# `_dump_frame`, which asks the camera the same question at the one moment the
# answer is known to be live -- inside `_copy_still`, where the PNG on disk IS the
# frame in question. Keeping a diagnostic that cannot reproduce the fault it was
# written for is worse than keeping nothing, because the next reader will trust it.
	print("    solo frames written: %s" % ", ".join(_written_stills))


func _capture_for(seconds: float) -> void:
	var hold := seconds / SMOKE_DIVISOR if smoke else seconds
	var until := float(Time.get_ticks_msec()) + hold * 1000.0
	while float(Time.get_ticks_msec()) < until:
		await _capture_one()


## Waits out an act. IT REFUSES TO BE A NO-OP, and that refusal is the fix for the
## failure that shipped the first draft: called after a `request` that had been
## turned down, it found `state == IDLE` -- the state it exists to wait to leave --
## and returned on its first test, so four acts and ten stills were reported
## complete while nothing had run.
##
## The caller now checks the `request` too. This is the second lock on the same
## door, because the first one is one line away from being deleted by somebody who
## does not know why it is there.
func _capture_until_idle() -> void:
	if combat.state == CombatController.State.IDLE:
		_fails.append("_capture_until_idle was called with nothing running")
		return
	var guard := 0
	while combat.state != CombatController.State.IDLE and guard < 900:
		await _capture_one()
		guard += 1
	await _capture_for(0.22)


## Waits out a put-away.
##
## `_pending_slot` is the manager's own "a put-away is in flight" flag, and it is
## read rather than inferred because `equip_blend` stays at 1.0 for the first
## frame of a sheathe: waiting on the blend alone would let the caller through
## before the act had begun.
func _capture_until_sheathed() -> void:
	var guard := 0
	while float(combat.equip_blend) > 0.001 and guard < 900:
		await _capture_one()
		guard += 1
	await _capture_for(0.22)


## Waits for the blade to be OUT, and refuses to be a no-op. `_blade_is_out()` is
## the same three-part predicate the §5 window uses, so "drawn" means the same
## thing to the wait and to the measurement.
func _capture_until_drawn() -> void:
	if _blade_is_out():
		_fails.append("_capture_until_drawn was called with the blade already out")
		return
	var guard := 0
	while not _blade_is_out() and guard < 900:
		await _capture_one()
		guard += 1
	await _capture_for(0.22)


func _capture_one() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var big: SubViewport = body_vp if body_mode else detail_vp
	if big == null:
		push_error("no capture viewport in this mode at frame %d" % frame_index)
		return
	var image := big.get_texture().get_image()
	if image == null:
		push_error("the capture viewport returned no image at frame %d" % frame_index)
		return
	# THE INSET IS NOT PASTED IN §32's MODE, AND THAT IS WHAT "FULL SCREEN" MEANS.
	# The detail clip's picture-in-picture is the player's own eye, which is half of
	# what a tight measurement shot is for. Here the frame is already the whole
	# world from outside the player, and a 384x216 eye view over the corner of it
	# would put a second camera into a shot whose entire claim is "≥2 机位, each one
	# named".
	if not body_mode:
		var small := eye_vp.get_texture().get_image()
		if small == null:
			push_error("the eye viewport returned no image at frame %d" % frame_index)
			return
		# COMPOSITED IN IMAGE SPACE, NOT WITH A TextureRect. A `TextureRect` holding
		# the root window's own texture inside the root window is a self-reference, and
		# the frame the composite is read from then depends on the order the canvas is
		# drawn in relative to the readback. Blitting two images that have already
		# been read is exact and cannot be half a frame wrong.
		_paste(image, small)
	if image.save_png("%s/frame_%04d.png" % [out_dir, frame_index]) != OK:
		push_error("save_png failed at frame %d" % frame_index)
		return
	# COUNTED ONLY WHEN A PICTURE REACHED THE DISK. `frame_index` is the NAME of
	# the file, not a count of attempts; the delivery tool had this increment one
	# indent out and wrote 700 frames to `frame_0000.png` while reporting success.
	frame_index += 1
	_sample()
	_pump_stills()
	if _diag_pending != "":
		_diag(_diag_pending)
		_diag_pending = ""
	if frame_index % 90 == 0:
		print("    frame %d  game=%.2fs  scale=%.2f" % [
			frame_index, combat.combat_time, Engine.time_scale])


func _paste(big: Image, small: Image) -> void:
	var origin := Vector2i(
		VIEW.x - INSET.x - INSET_PAD,
		VIEW.y - INSET.y - INSET_PAD - INSET_PAD)
	var frame := Rect2i(
		origin - Vector2i(INSET_BORDER, INSET_BORDER),
		INSET + Vector2i(INSET_BORDER * 2, INSET_BORDER * 2))
	big.fill_rect(frame, Color(0.05, 0.05, 0.07, 0.85))
	# `blit_rect` refuses a mismatched source with an error and an unchanged
	# rectangle, which would ship a clip whose inset silently is not there.
	if small.get_format() != big.get_format():
		small.convert(big.get_format())
	big.blit_rect(small, Rect2i(Vector2i.ZERO, INSET), origin)


# --- stills ----------------------------------------------------------------

func _arm_stills(rules: Array) -> void:
	_stills.clear()
	_seen_moves.clear()
	for rule in rules:
		rule["done"] = false
		_stills.append(rule)
		_want_still(String(rule["tag"]))


## Every move id the take actually played, in order.
##
## A still that never fires used to be reported as "stills missing: a4_clear" and
## nothing else -- which is a statement about the SHOT LIST, not about the take.
## The two things that can go wrong are "the act never ran" and "the act ran and
## its moment slipped between two captures", and they need opposite fixes. The
## list of ids the take played separates them in one line.
func _note_move() -> void:
	var id := str(combat.active_move_id)
	if id == "" or _seen_moves.has(id):
		return
	_seen_moves.append(id)


## Called at the end of a take. ANY still that was armed and did not fire is a
## FAILURE, not a note: the first draft shipped four acts with no stills and said
## so only in the log's last line, as a list of names with no explanation.
func _check_armed(take: String) -> void:
	for rule in _stills:
		if bool(rule["done"]):
			continue
		var played := "nothing"
		if not _seen_moves.is_empty():
			played = ", ".join(_seen_moves)
		_fails.append("no still for `%s` in `%s`: the take played %s" % [
			str(rule["tag"]), take, played])


func _want_still(tag: String) -> void:
	if not _wanted_stills.has(tag):
		_wanted_stills.append(tag)


func _pump_stills() -> void:
	_note_move()
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
	# Printed because a still is the only place a take's TIMING becomes visible.
	# Ten stills appeared at four points in the first draft and the frame numbers
	# said so in one line: an act that produces three frames cannot produce the
	# eight a shot list asks of it.
	print("    still '%s' at frame %d (t=%.2fs)" % [tag, frame_index - 1, _t])
	# THE BAND IS A TRANSIENT AND THIS IS THE ONLY FRAME THAT HAS IT.
	#
	# `_diag` asks the camera what it can draw, and asking it there was asking at
	# the wrong moment: `_diag` runs when an act OPENS, and the pale band over A3
	# was measured to be gone by the time anything else could look -- hiding
	# `VoidRim`, `EdgeGlint`, `BladeTrail`, `Sword_FP` and the whole rig one at a
	# time produced five clean frames, because those frames were 0.7 s late. A
	# still, by contrast, is a copy of a frame that has already been written to
	# disk, so asking here is asking about THE frame in question and not about a
	# frame a second after it.
	if OS.get_environment("SEKAI_VFX_DUMP") != "":
		_dump_frame(tag)


# ===========================================================================
# MEASUREMENT · the same figures the probe prints, from this take's own track
# ===========================================================================

func _sample() -> void:
	var delta := clock.total - _last_total
	_last_total = clock.total
	_t = clock.total
	var mouth := _mouth()
	_samples.append({
		"pos": mouth, "dt": delta, "t": _t,
		# `live` is "the blade is out"; `still` is "and nothing at all is being
		# asked of the sheath". §5's band only means anything over the second,
		# because during a cut the hand has been asked to move and its excursion
		# is the act's, not its own.
		"live": _blade_is_out(), "still": _nothing_asked(),
	})
	# §32's own bookkeeping: the body's reach, sampled every frame.
	#
	# A SINGLE FRAME'S SHORTFALL IS NOT THE CLAIM. §30 is about a body that has to
	# hold this rig for a whole performance, and the interesting number is the
	# WORST the geometry ever asks for -- the idle may be reachable while A3 is
	# not, and a caption reading "363 mm" from one instant would say nothing about
	# which act produced it. The peak is printed with the act it happened in.
	if body_mode and body != null and is_instance_valid(body) and body.has_method("reach_report"):
		var reach: Dictionary = body.call("reach_report")
		var l := float(reach.get("left_shortfall", 0.0))
		var r := float(reach.get("right_shortfall", 0.0))
		if l > _shortfall_l:
			_shortfall_l = l
			_shortfall_l_at = "%s at %.2fs" % [_act_key, _t]
		if r > _shortfall_r:
			_shortfall_r = r
			_shortfall_r_at = "%s at %.2fs" % [_act_key, _t]

	# §22, from the blade's own orientation.
	#
	# THE WINDOW IS THE POINT, AND IT IS `probe_iaido_recovery.gd`'s WINDOW.
	# §22 is a statement about the WRIST: "ONE controlled rotation, 270-360, whose
	# job is to reset the EDGE ORIENTATION". The phase it lives in contains two
	# movements -- the turn (§22, a ROLL about the blade's own axis, which barely
	# moves the tip at all) and §23's catch (a repoint onto the bore). Summed over
	# the whole ceremony the figure is dominated by neither: it is the blade being
	# lifted, turned upright, carried to the mouth and finally sheathed, and it
	# reads 466 deg -- with the roll's own 342.7 in there somewhere. Passing that
	# against a 360 ceiling fails a correct ceremony, and it was the number this
	# take printed as 906 before the sample window was time-gated at all.
	#
	# So it is measured where the turn is, exactly as the probe measures it: the
	# first `spin_turn_share` of the spin phase, as the geodesic path length of
	# the full orientation through `SwordPoseSampler.angle_between` (which is the
	# only well-conditioned way to add up rotations -- `Quaternion.angle_to`
	# reports 0.056 deg between a rotation and itself).
	if combat.state == CombatController.State.IAIDO:
		var q := Basis.from_euler(sword.rotation as Vector3).get_rotation_quaternion()
		var elapsed := 0.0
		if director != null:
			elapsed = float(director.get("elapsed"))
		if _ai_have_prev:
			var step := SwordPoseSampler.angle_between(_ai_rot_prev, q)
			_ai_rot_all += step
			if elapsed >= _turn_from and elapsed <= _turn_to:
				_ai_rot_deg += step
		_ai_rot_prev = q
		_ai_have_prev = true


## TRUE WHEN THE SHEATH HAS NO BUSINESS MOVING, which is the only window in which
## "the mouth did not move" is a claim rather than a restatement.
func _blade_is_out() -> bool:
	if float(combat.equip_blend) < 0.999:
		return false
	if bool(manager.get("drawing_in")):
		return false
	return float(manager.get("_sheathe_left")) <= 0.0


## TRUE WHILE THE SHEATH HAS NOTHING ASKED OF IT. The complement of the above
## PLUS "no move is running": this is §5's window, and §29's whole statement.
func _nothing_asked() -> bool:
	if not _blade_is_out():
		return false
	return combat.state == CombatController.State.IDLE


func _mouth() -> Vector3:
	if combat.saya_rig == null or not is_instance_valid(combat.saya_rig):
		return Vector3.ZERO
	return combat.saya_rig.mouth_point()


## The worst single-update step taken while the sheath has NO BUSINESS MOVING --
## §29's own window, `still`, not merely `live`.
##
## THIS WAS WRITTEN AS `live` AND ITS OWN DOCSTRING SAID OTHERWISE: "the worst
## step while the sheath has no business moving" is a sentence about `still`,
## which is "the blade is out AND nothing at all is being asked". Read over
## `live`, the figure included every cut -- where the mouth is AUTHORED to travel
## 3-8 cm (§10-§11 CLEAR THE BLADE PATH, §12-§13 the anchor) -- so once Pass 02
## made the saya do its job the gate went red on the acts it exists to reward. It
## reported 0.0926 m against a 20 mm limit, and it would have failed a rig that
## was right.
func _idle_drift() -> float:
	var worst := 0.0
	for i in range(1, _samples.size()):
		if not bool(_samples[i - 1]["still"]) or not bool(_samples[i]["still"]):
			continue
		worst = maxf(worst, (_samples[i - 1]["pos"] as Vector3).distance_to(
			_samples[i]["pos"] as Vector3))
	return worst


## §5's excursion, over the samples in which nothing at all was asked -- AND OVER
## A BREATH'S OWN LENGTH OF TIME, WHICH IS THE PART THE FIRST DRAFT GOT WRONG.
##
## The first version took the diameter of EVERY still sample in the take. That is
## not a measurement of breathing; it is a measurement of the take. The hand's
## three axes run at 1.90, 1.46 and 1.12 rad/s, so a sixty-second union lets all
## three visit both ends of their travel and the diameter of the cloud converges
## on the AUTHORED ENVELOPE -- 15.0 mm here, printed against a 15 mm ceiling. It
## was a number about the run's length, and the gate it tripped was correct about
## arithmetic and wrong about the object.
##
## §5 gives breathing a size and a breath has a period, so the excursion is the
## widest two samples can be APART while still being inside the same hold and
## inside `BREATH_WINDOW` seconds of one another. That does not grow with the
## length of the clip, and it is the instrument `probe_saya_motion.gd` already
## uses when it reports each `idle` leg as its own `span`: 9.6 / 6.0 / 7.3 / 7.0 /
## 7.0 / 8.5 mm, all inside the band, while the same track unioned over the run
## reads 15.0. Two instruments, one object, and the segmented one is right.
##
## (The envelope itself is real and is noted in `SayaHandDriver`: an axis summed
## against its jitter gives 2 x 9.97 mm = 19.9 mm of travel end to end. It is not
## what a hold shows because the phases are incommensurate on purpose, and it is
## above §5's ceiling for the same reason -- which is why the measurement has to
## say which window it was taken over.)
func _breath_excursion() -> Dictionary:
	var widest := 0.0
	var widest_at := 0.0
	var runs := 0
	var counted := 0
	var run_len := 0
	for i in _samples.size():
		var a: Dictionary = _samples[i]
		if not bool(a["live"]) or not bool(a["still"]):
			run_len = 0
			continue
		run_len += 1
		counted += 1
		if run_len == 1:
			runs += 1
		var ta: float = a["t"]
		var pa: Vector3 = a["pos"]
		# Forward only, and only while the hold lasts: the moment the sheath is
		# asked for something the pair stops being a breathing observation.
		for j in range(i + 1, _samples.size()):
			var b: Dictionary = _samples[j]
			if not bool(b["still"]):
				break
			if float(b["t"]) - ta > BREATH_WINDOW:
				break
			var d: float = pa.distance_to(b["pos"] as Vector3)
			if d > widest:
				widest = d
				widest_at = ta
	return {"span": widest, "at": widest_at, "count": counted, "runs": runs}


## The fastest the mouth is taken, over `SPEED_WINDOW` seconds. Filtered, because
## the two readings answer two different questions and only one of them has a
## ceiling: `still_only = false` is the whole take (CONTEXT -- A3 moves the mouth
## 4.2 cm on purpose, and a film about that motion would be a strange one to fail
## for containing it), `still_only = true` is §29's window and is what the gate
## looks at.
func _peak_speed(still_only: bool) -> Dictionary:
	var best := {"speed": 0.0, "t": 0.0}
	for i in _samples.size():
		if still_only and not bool(_samples[i]["still"]):
			continue
		var j := i + 1
		while j < _samples.size() \
				and float(_samples[j]["t"]) - float(_samples[i]["t"]) < SPEED_WINDOW:
			j += 1
		if j >= _samples.size():
			break
		if still_only and not bool(_samples[j]["still"]):
			continue
		var span: float = float(_samples[j]["t"]) - float(_samples[i]["t"])
		if span <= 0.0:
			continue
		var speed: float = (_samples[i]["pos"] as Vector3).distance_to(
			_samples[j]["pos"] as Vector3) / span
		if speed > float(best["speed"]):
			best = {"speed": speed, "t": _samples[i]["t"]}
	return best


func _report() -> void:
	var fastest := _peak_speed(false)
	var unasked := _peak_speed(true)
	var drift := _idle_drift()
	var breath := _breath_excursion()
	var live := 0
	for s in _samples:
		if bool(s["live"]):
			live += 1
	print("")
	print("   frames %d over %.2fs of engine time" % [_samples.size(), _t])
	print("   fastest mouth window, whole take  %.2f m/s = %.1f mm per 60 Hz frame (at t=%.2f)"
		% [fastest["speed"], float(fastest["speed"]) / 60.0 * 1000.0, fastest["t"]])
	print("   fastest mouth window, sheath unasked %.2f m/s = %.1f mm per 60 Hz frame (at t=%.2f)"
		% [unasked["speed"], float(unasked["speed"]) / 60.0 * 1000.0, unasked["t"]])
	print("   worst single-update step while the sheath is unasked %.4f m (limit %.4f)" % [
		drift, JUMP_LIMIT])
	print("   §5 idle excursion %.4f m in a %.1f s window over %d unasked samples in %d holds (band %.3f-%.3f)" % [
		breath["span"], BREATH_WINDOW, breath["count"], breath["runs"],
		BREATH_FLOOR, BREATH_CEIL])
	print("   §22 orientation over the TURN window %.1f deg  (whole ceremony %.1f deg)"
		% [_ai_rot_deg, _ai_rot_all])
	print("")
	# A. §35-A, the Pass01 regression alarm: the saya moving when nothing asked it
	# to. Both readings are printed above; only the second one is this claim.
	_judge(float(unasked["speed"]) < JUMP_LIMIT * 60.0,
		"§29: carrying nothing, the mouth never moves faster than %.0f mm per 60 Hz frame (worst %.1f mm/s at t=%.2f)"
			% [JUMP_LIMIT * 1000.0, float(unasked["speed"]) * 1000.0, unasked["t"]])
	_judge(drift < JUMP_LIMIT,
		"§29: and no single update while unasked carries it more than %.0f mm (worst %.1f mm)"
			% [JUMP_LIMIT * 1000.0, drift * 1000.0])
	# F. §35-F, and it is the NEW failure this pass exists for: a mouth that does
	# not move is a mouth welded to the camera. This is the half Pass 01 had no
	# gate for, and the reason 0.0000 m was ever reported as success.
	_judge(float(breath["span"]) >= BREATH_FLOOR,
		"§5: with nothing asked of it the mouth is ALIVE -- %.1f mm inside a %.1f s hold (floor %.0f mm)"
			% [float(breath["span"]) * 1000.0, BREATH_WINDOW, BREATH_FLOOR * 1000.0])
	_judge(float(breath["span"]) <= BREATH_CEIL,
		"§5: and it is CONTROLLED -- %.1f mm is inside the %.0f mm ceiling for the same %.1f s"
			% [float(breath["span"]) * 1000.0, BREATH_CEIL * 1000.0, BREATH_WINDOW])
	# E. §35-E, and §21: "TWO SPINS" is deleted. 2 turns is 720 deg; the brief's
	# own ceiling for the ONE rotation is 360. Measured over the turn, and about
	# the blade's own axis -- see `_sample` for why the whole ceremony is 466 and
	# why that number is not this claim.
	_judge(_ai_rot_deg >= 270.0 and _ai_rot_deg <= 380.0,
		"§21-§22: the recovery is ONE controlled rotation, %.1f deg over the turn (band 270-380; two spins is past 720)"
			% _ai_rot_deg)
	_judge(live > 0, "%d frames were captured with the blade out" % live)
	if body_mode:
		# §32: "全屏 Third Person >= 2 机位". Counted from the cameras that were
		# actually reached, not from the size of `BODY_CAMS`: the table is a
		# statement of intent and this is a statement of what the clip contains.
		_judge(_body_cams_used.size() >= 2,
			"§32: the clip is filmed from %d camera position(s) -- %s (at least 2 is the requirement)"
				% [_body_cams_used.size(), ", ".join(_body_cams_used)])
		# §30: the body is positioned from the floor, so a floor that could not be
		# measured is a body drawn at a guessed height. The sentence comes from the
		# body itself -- it already words the failure case with the band it was
		# given, and a second copy of that wording here is a second thing to drift.
		if body != null and is_instance_valid(body) and body.has_method("floor_is_plausible"):
			_judge(bool(body.call("floor_is_plausible")),
				"§30: %s" % String(body.call("floor_line")))
		# §30 · THE FINDING, AND IT IS NOT A GATE — ON PURPOSE.
		#
		# §35's six regression gates (A-F) name syncing, clipping, the A3 crossing,
		# the A4 collision, the two spins and world-locking. "The arm cannot reach
		# what it is holding" is none of them, so failing the run on it would be a
		# seventh gate invented by a tool. It IS printed as a claim with its own
		# number and the act it happened in, because it is §38's P0 and because a
		# measurement that only appears in a caption is a measurement nobody
		# aggregates.
		var worst := maxf(_shortfall_l, _shortfall_r)
		print("")
		print("   §30 the rig as a body: the LEFT hand is asked for %.0f mm more than a 0.57 m arm (worst %s)" % [
			_shortfall_l * 1000.0, _shortfall_l_at])
		print("   §30 the rig as a body: the RIGHT hand is asked for %.0f mm more (worst %s)" % [
			_shortfall_r * 1000.0, _shortfall_r_at])
		if worst <= 0.001:
			print("   §30 -> both hands reach their weapons. The rig is a body.")
		else:
			print("   §30 -> THE RIG IS NOT A BODY YET. The scabbard's home and the sword's poses sit where a FIRST-PERSON camera wants them, not where a shoulder can put a hand. Nothing about the saya's own motion changes this: the saya is placed where the HAND is, so the fix belongs to the hand point or to the anatomy, not to this pass.")


func _verdict_line() -> String:
	var fastest := _peak_speed(true)
	return "unasked frame %.1f mm · breath %.1f mm in %.1f s · turn %.0f deg · %d frames" % [
		float(fastest["speed"]) / 60.0 * 1000.0,
		float(_breath_excursion()["span"]) * 1000.0, BREATH_WINDOW,
		_ai_rot_deg, _samples.size()]


func _judge(condition: bool, reason: String) -> void:
	print("   %s %s" % ["ok  " if condition else "FAIL", reason])
	if not condition:
		_fails.append(reason)


# ===========================================================================
# HARNESS
# ===========================================================================

## Writes the frame's three lines of text.
##
## `act` is the act's own key and it is a PARAMETER rather than hidden state, so
## that the body captions cannot silently be looked up for the wrong act: the key
## is written at the call site, next to the words it belongs to. The two modes
## disagree about the words and about nothing else -- the title, the claim the act
## is under test for, and the note.
func _shot(act: String, title: String, caption: String, note: String) -> void:
	if not body_mode:
		shot_label.text = title
		caption_label.text = caption
		note_label.text = note
		return
	var body_shot: Array = BODY_SHOTS.get(act, [])
	if body_shot.is_empty():
		_fails.append("no body caption is written for act `%s`" % act)
		shot_label.text = title
		caption_label.text = caption
		note_label.text = note
		return
	shot_label.text = String(body_shot[0])
	caption_label.text = String(body_shot[1])
	note_label.text = "%s  ·  %s  ·  %s" % [
		String(body_shot[2]), _body_reach_line(), _body_floor_line()]


func _set_note(text: String) -> void:
	note_label.text = text


## Stands every zone target down. This clip is about the weapon and the sheath, so
## nothing else may move: a body walking through the frame is a second subject and
## a second clock.
func _silence() -> void:
	var zone := sandbox.get_node_or_null("SwordComboZone")
	if zone == null:
		return
	for node in zone.call("all_targets"):
		(node as Node3D).visible = false


## The draw's own predicate, as a METHOD taking the blend it is waiting for, and
## bound rather than written as a lambda.
##
## `--check-only` segfaults (signal 11, no diagnostic) on a multi-line lambda that
## declares a local and on a bare method reference used as a value inside a
## dictionary array literal. `Callable(self, "name").bind(...)` is neither, and it
## also lets one predicate serve three stills instead of three closures.
##
## The thresholds are `equip_blend`, which `CombatController.advance_draw` sets to
## `elapsed / DRAW_SECONDS` -- so the blend IS the draw's normalised clock and the
## beats land on it exactly: 0.35/1.75 = 0.20, 0.75/1.75 = 0.43, 1.40/1.75 = 0.80.
func _draw_past(blend: float) -> bool:
	var now := float(combat.equip_blend)
	return bool(manager.get("drawing_in")) and now >= blend and now < 0.999


## Beat 5, the instant the choreographed beats stop being asked for.
##
## THE DRAW IS NOT THE CONDITION. Written as "`drawing_in` and blend at home" it
## reports a missing still, because `WeaponManager` clears `drawing_in` in the same
## `_process` that pushes the blend to 1.0. "The draw has finished" is the honest
## predicate and it is what the still is actually of.
func _draw_home() -> bool:
	return float(combat.equip_blend) >= 0.999 and not bool(manager.get("drawing_in"))


func _past_settle(move_id: StringName) -> bool:
	var move := combat.moveset.get_move(move_id)
	if move == null or combat.active_move == null:
		return false
	return combat.state_time >= move.startup + move.strike * 0.55


## Put-away, mid-flight. A named method rather than a lambda for the reason
## `_draw_past` is: the parser will not take a lambda whose body wraps onto a
## second line, and a predicate that has to be flattened onto one line is a
## predicate nobody will dare to extend.
func _sheathing() -> bool:
	if not bool(manager.get("drawing_in")) and float(manager.get("_sheathe_left")) <= 0.0:
		return false
	var blend := float(combat.equip_blend)
	return blend > 0.05 and blend < 0.95


## §21-§26, gated on the director's own clock. `elapsed` is the ceremony's, not
## the controller's: the two are different clocks and only one of them knows where
## the rotation is.
func _iaido_past(t: float) -> bool:
	if director == null or not bool(director.get("active")):
		return false
	return float(director.get("elapsed")) >= t


## Ends whatever the previous take left running, AND ENDS ITS COMBO, which is the
## half that was missing.
##
## `finish_action()` alone clears the move and returns the state to IDLE. It
## deliberately does NOT clear `combo_index` / `chain_expires_at` -- for a player
## mid-sentence that memory is the feature. So a movie that ends each take with
## `finish_action()` and then asks for "one light attack each time" is asking a
## question whose answer depends on how long the previous take took. Measured, it
## played `sb_a3` for A2, `sb_a2` for A3 and `sb_a1` for A4, and three stills went
## missing with no explanation beyond their names.
##
## `stow()` is the real entrance for "the sword is no longer mid-sentence" -- it
## is what `WeaponManager` calls on a weapon change, and it clears the buffer, the
## follow-up promise and the combo memory before ending the action. A movie that
## restarts the sentence between acts is exactly that situation.
func _ensure_idle() -> void:
	combat.stow()
	await _capture_for(0.2)


## THE BLADE HAS TO BE OUT BEFORE ANY ACT THAT USES IT.
##
## `CombatController._start` returns false for `light` / `heavy` / `iaido` /
## `ultimate` while `equip_blend < 1.0`, so a take that follows a put-away
## silently produces nothing. Stating the precondition and satisfying it here
## means the takes do not have to be ordered correctly for the clip to exist --
## and the print makes a future re-ordering visible instead of invisible.
func _ensure_drawn() -> void:
	if _blade_is_out():
		return
	print("    (the blade was away -- drawing it back before this act)")
	var asked: bool = manager.call("equip_weapon", slot.SWORD)
	if not asked and float(combat.equip_blend) <= 0.001:
		_fails.append("the blade could not be drawn back (slot=%s)" % str(slot.kind))
		return
	await _capture_until_drawn()


## ...AND THE OTHER DIRECTION, WHICH IS THE SHOT THE DRAW TAKE ACTUALLY IS.
##
## The sandbox opens with the sword drawn, so `equip_weapon(&"sword")` is a no-op
## and the draw take films nothing -- which is exactly what happened, and it went
## into the still list as two missing frames rather than as an error. A draw take
## has to put the blade away first; that is not a workaround, it is what a draw
## is.
##
## The put-away is only ASKED FOR when none is in flight (`_pending_slot`). A
## second `_begin_sheathe` mid-flight restarts the act, which would be a visible
## hiccup in the middle of the shot this function exists to set up.
func _ensure_sheathed() -> void:
	if float(combat.equip_blend) <= 0.001 and not bool(manager.get("drawing_in")):
		return
	if not bool(manager.get("drawing_in")) \
			and str(manager.get("_pending_slot")) == "":
		print("    (the blade was out -- putting it away so this act has a draw to show)")
		var asked: bool = manager.call("equip_weapon", slot.CHAIN)
		if not asked:
			_fails.append("the blade could not be put away before the draw (slot=%s)"
				% str(slot.kind))
			return
	var guard := 0
	while float(combat.equip_blend) > 0.001 and guard < 900:
		await _capture_one()
		guard += 1
	if float(combat.equip_blend) > 0.001:
		_fails.append("the put-away before the draw never finished")


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
# OVERLAY · drawn into the DETAIL viewport, not the window
# ===========================================================================
#
# A `CanvasLayer` added to the root would be composited into the root window's
# texture -- the inset -- and the titles would end up 384 pixels wide, inside the
# picture they are titling. The composite's main image is the detail viewport, so
# the titles go where the main image is.

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DetailOverlay"
	layer.layer = 4
	# THE LABELS LIVE INSIDE THE CAPTURE VIEWPORT, not on the root canvas. A
	# `CanvasLayer` belongs to exactly one viewport, so §32's mode gets the same
	# three nodes in its own -- one set of labels, rewritten per act, in whichever
	# picture is about to be written to disk.
	var host: SubViewport = body_vp if body_mode else detail_vp
	host.add_child(layer)

	# THE TEXT IS AT THE BOTTOM-LEFT AND THAT IS A FRAMING DECISION, NOT TASTE.
	# At the top it sat across the blade: the assembly's tip reaches y = 0 by
	# construction, because the band's top edge is where the framing puts the
	# extreme high point, so a top-anchored caption is guaranteed to collide with
	# the subject on every shot. The lower-left card is empty in every act.
	#
	# The width is capped at the inset's left edge for the same reason: the inset
	# is at x 880 and a caption that ran under it would be captioned by a picture.
	# There is no inset in §32's mode, so the cap does not apply there.
	#
	# §32's MODE PUTS IT AT THE TOP, FOR THE SAME KIND OF REASON INVERTED. The
	# detail shot's composition is a metre-long object solved into a band of the
	# frame with empty card below it; the body shot is a standing figure centred in
	# a world, and the band across its feet is EXACTLY where the thing this mode
	# measures lives. Measured on the first frame: the caption covered both feet,
	# which is where §30's connection to the floor is either there or not. The top
	# of a standing-figure frame is sky in every act.
	var text_w := float(VIEW.x - INSET.x - INSET_PAD * 3)
	var text_x := 48.0
	var shot_y := 720.0 - 152.0
	var caption_y := 720.0 - 116.0
	var note_y := 720.0 - 52.0
	if body_mode:
		text_w = float(VIEW.x - 96)
		shot_y = 36.0
		caption_y = shot_y + 36.0
		note_y = caption_y + 68.0

	shot_label = _label(24)
	shot_label.position = Vector2(text_x, shot_y)
	shot_label.size = Vector2(text_w, 34.0)
	layer.add_child(shot_label)

	caption_label = _label(16)
	caption_label.position = Vector2(text_x, caption_y)
	caption_label.modulate = Color(0.86, 0.93, 0.97, 0.92)
	caption_label.size = Vector2(text_w, 62.0)
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(caption_label)

	note_label = _label(15)
	note_label.position = Vector2(text_x, note_y)
	note_label.modulate = Color(0.78, 0.88, 0.94, 0.92)
	note_label.size = Vector2(text_w, 44.0)
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(note_label)


func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	# Shadowed rather than panelled: this has to stay readable over a bright arena
	# without turning the review frame into an interface.
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


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
