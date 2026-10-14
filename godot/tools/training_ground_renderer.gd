extends SceneTree
## Renders the Training Ground so the review hub itself can be reviewed.
##
## Needs a REAL WINDOW - `--headless` disables rendering, so a headless run of
## this produces black frames. Run it as:
##
##   G:/Godot/Godot_v4.4.1-stable_win64_console.exe --path F:/SEKAI/godot \
##     --resolution 1600x900 --audio-driver Dummy \
##     --script res://tools/training_ground_renderer.gd
##
## Deliberately built on the first frame, not in _initialize(): a builder-based
## scene is still empty at _initialize() time, because _ready() has not been
## delivered yet.

const SCENE := "res://scenes/training/TrainingGround.tscn"
const OUT_DIR := "F:/SEKAI/assets_source/review/training/"
## Frames to let go by before the shutter may open, so the camera transform has been
## applied by the renderer and not merely set on the node.
const WARMUP := 8
## A gate that never comes true is a BUG IN THE GATE, and a renderer that waits forever
## on one produces no picture at all and no error either — the worst of both. Ten
## seconds is longer than every hold in the table by an order of magnitude, so hitting
## it means the fixture did not do what the gate describes, which is itself worth a line.
const GATE_TIMEOUT := 10.0
## Frames to let go by AFTER a gate comes true before reading the framebuffer back. The
## readback lags the state by one frame, and the frame before a gate is exactly the
## transition the gate was written to exclude. See the note in `_process`.
const CAPTURE_LAG := 2

# name, eye, look-at. Chosen to answer "can I tell the zones apart".
#
# A FOURTH ELEMENT IS AN OPTIONAL ACTION, run one frame after the camera arrives. It
# exists for exactly one reason: the iaido post's whole claim is about a state, and a
# still of an intact post is a still of every other post in the project.
#
# THE FIFTH AND SIXTH ELEMENTS ARE `hold` AND `gate`, AND THE UNITS ARE THE WHOLE
# POINT. `hold` is SECONDS. It used to be FRAMES, and frames are not seconds: this loop
# runs as fast as the GPU lets it, and with vsync off that is several hundred frames a
# second, so "wait 240 frames" asked for about a fifth of a second while the fixture it
# was waiting on counts in seconds. The shutter opened on a post still in two pieces and
# the file was called `13_iaido_reformed`. A gate is the same correction taken further —
# instead of guessing a duration long enough to cover `RECOVER_DELAY + REFORM_TIME`, the
# shot waits on the FIXTURE'S OWN READING, so the picture cannot disagree with the claim
# in the filename.
const SHOTS := [
	["01_aerial", Vector3(0.0, 86.0, 30.0), Vector3(0.0, 0.0, -19.0)],
	["02_spawn_equipment", Vector3(0.0, 1.7, 7.0), Vector3(0.0, 1.4, -10.0)],
	["03_combat_court", Vector3(0.0, 1.7, -16.0), Vector3(0.0, 1.4, -30.0)],
	["04_movement_lane", Vector3(-2.0, 1.7, 14.0), Vector3(14.0, 1.4, 8.5)],
	["05_chain_lab", Vector3(-34.0, 3.2, 12.0), Vector3(-34.0, 1.0, -18.0)],
	["06_vfx_stage", Vector3(-32.0, 1.7, -14.0), Vector3(-32.0, 2.2, -35.0)],
	# The gallery overview. The eye is NORTH-WEST of the ring and the aim is past it, so
	# that the ring falls outside the 102 deg horizontal field instead of filling the near
	# half of the frame: an overview of F that is two thirds H is an overview of H.
	["07_showcase", Vector3(22.0, 11.0, -18.0), Vector3(38.0, 0.40, -44.0)],
	["08_gate", Vector3(0.0, 1.7, -42.0), Vector3(0.0, 1.8, -53.0)],
	["09_fixtures", Vector3(0.0, 2.4, -26.5), Vector3(0.0, 1.1, -38.5)],
	["10_iaido_post", Vector3(5.5, 1.6, -33.6), Vector3(5.5, 1.1, -38.5)],
	["11_iaido_cut", Vector3(5.5, 1.6, -33.6), Vector3(5.5, 1.1, -38.5), &"cut_post", 0.35, &"post_cut"],
	# LONG ENOUGH FOR THE SEVERED HALF TO ACTUALLY LAND. A cut photographed on the frame
	# it happens shows a seam, and the claim here is about a body that fell.
	["12_iaido_cut_fallen", Vector3(5.5, 2.8, -32.6), Vector3(5.5, 0.3, -39.5), &"", 1.20, &""],
	# SAME EYE AS 10, on purpose. 10 and 13 are the pair that answers "会恢复": if the
	# post really is put back then two frames from one camera are the same picture, and
	# if it is not, the difference is visible without anybody reading a log line.
	["13_iaido_reformed", Vector3(5.5, 1.6, -33.6), Vector3(5.5, 1.1, -38.5), &"", 0.2, &"post_intact"],
	# --- H / I / J, AND THE REBUILT GALLERY ------------------------------------------
	# EVERYTHING FROM HERE ON IS APPENDED, AND THAT IS A CONSTRAINT AND NOT A HABIT.
	# The shots above are a sequence against a live scene: 11 cuts the post, 12 waits
	# for the severed half to land, 13 gates on the post standing back up. Inserting a
	# camera anywhere in that run moves the clock the post reforms against, and the
	# 10 == 13 identity — the fixture's own proof that "会恢复" is true — stops holding.
	# New rooms go on the end.
	#
	# 14 AND 15 ARE EYE LEVEL ON PURPOSE. The claim about the ring is "you can walk onto
	# it", and an aerial cannot show that: from above, a deck with a ramp and a deck with
	# a 0.90 m wall are the same grey rectangle. 14 takes the bay's own review anchor — the
	# published position at the ring's only doorway — and 15 stands on the ramp itself,
	# looking through the gate the kerb opens for it, which is the one place a lip or a
	# misaligned opening is visible.
	["14_duel_ring", Vector3(25.0, 2.40, -13.0), Vector3(38.0, 1.60, -13.0), &"", 0.0, &"", &"Review_Duel"],
	# Aimed slightly north of the deck's centre line so that the ring's own nameplate —
	# which stands above the north kerb, 8 m away and 2 m up — is inside the frame instead
	# of straddling its edge. Half a nameplate reads as a defect in a sheet whose job is to
	# show that nothing here is half-built.
	["15_duel_ring_gate", Vector3(31.4, 1.45, -13.0), Vector3(36.8, 1.65, -14.6)],
	# THE HILL, FROM THE SOUTH-WEST. Every one of the four heights has to be a floor and
	# not a roofline, and that reads as "you can see the tops of three of them at once and
	# the fourth is reached by the stair in frame". Anchored, so that if the hill moves the
	# camera moves with it.
	["16_terrain_park", Vector3(23.0, 2.80, 19.5), Vector3(37.0, 1.25, 8.0), &"", 0.0, &"", &"Review_Terrain"],
	# DOWN THE LANE, FROM THE FIRING LINE. 58 m of floor with a mark every so often and
	# the 55 m frame at the end of it; the whole point is that nothing stands in it.
	["17_long_range", Vector3(6.0, 1.70, 15.0), Vector3(-52.0, 1.20, 15.0), &"", 0.0, &"", &"Review_Range"],
	# THE GALLERY, FROM INSIDE IT, TWICE. A hall of plinths photographed from outside is
	# photographed as a floor, because the things that make it a gallery — the placards,
	# the gaps, the fact that no two pieces share a base — are all sub-metre and all face
	# the aisles. These two run the aisles a visitor walks: 18 looks north up the gap
	# between columns 0 and 1, 19 looks east down the central row between rows 1 and 2.
	# Both eyes sit ABOVE the tallest piece on a plinth (1.44 + 0.30), because at 1.6 m the
	# aisle is a corridor between two walls and at 2.9 m it is a gallery.
	["18_gallery_aisle_ns", Vector3(40.67, 3.40, -22.5), Vector3(40.67, 0.50, -52.0)],
	["19_gallery_aisle_ew", Vector3(33.50, 2.90, -39.0), Vector3(55.0, 0.60, -39.0)],
]

var _scene: Node3D = null
var _cam: Camera3D = null
var _frame := 0
var _shot := 0
var _settle := 0
## Seconds since this shot's camera was placed. THE unit the holds are written in; see
## the note above `SHOTS`.
var _held := 0.0
## Consecutive frames this shot's gate has been satisfied. See CAPTURE_LAG.
var _ready_frames := 0
var _lines := PackedStringArray()


func _initialize() -> void:
	pass


func _process(delta: float) -> bool:
	_frame += 1

	if _frame == 1:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
		DisplayServer.window_move_to_foreground()
		var packed: PackedScene = load(SCENE)
		if packed == null:
			_say("FAILED to load " + SCENE)
			flush()
			return true
		_scene = packed.instantiate()
		root.add_child(_scene)
		# Hide the player. It is a first-person rig: the only thing it contributes
		# to a frame is the viewmodel, which parks a sword across the right third
		# of every shot and hides the zone being reviewed. Zone review anchors
		# (racks, plinths, zone labels) carry the position reference instead.
		var hidden := 0
		var player := _scene.get_node_or_null("Player")
		if player != null:
			(player as Node3D).visible = false
			hidden += 1
		# Hide any leftover marker/debug meshes so they do not litter the frames.
		for node in _scene.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var nm := String(mi.name)
			if nm.begins_with("wp_") or mi.get_parent().name == "Routes":
				mi.visible = false
				hidden += 1
		_say("scene ready, hidden nodes: %d" % hidden)
		_review_exposure()
		return false

	# Camera has to be created after the scene so it can be made current.
	if _cam == null and _frame > 2:
		_cam = Camera3D.new()
		_cam.name = "TrainingReviewCam"
		_cam.fov = 70.0
		_cam.near = 0.1
		_cam.far = 4000.0
		root.add_child(_cam)
		_cam.make_current()
		_say("camera created")
		return false

	if _cam == null:
		return false

	if _shot >= SHOTS.size():
		_say("done, %d shots" % SHOTS.size())
		flush()
		return true

	if _settle == 0:
		var shot: Array = SHOTS[_shot]
		var eye: Vector3 = shot[1]
		var look: Vector3 = shot[2]
		# A SEVENTH ELEMENT NAMES A REVIEW ANCHOR, AND WHEN IT IS THERE THE ANCHOR WINS.
		#
		# `training_ground.gd` already publishes one camera per zone as a `Marker3D` with
		# the aim baked into its basis; that is what the `Review_*` nodes are, and every
		# zone's vantage is defined there. Writing the same eye and target again in this
		# table would make those numbers a COPY, and the copy is the one that goes stale:
		# the room moves, this file does not, and the sheet then documents a vantage that
		# no longer exists — which is worse than documenting none, because it looks like
		# evidence. The literal stays as the fallback for when the marker is missing, and
		# the log line says which of the two was actually used.
		var anchor := _anchor(shot)
		if anchor != null:
			_cam.global_position = anchor.global_position
			_cam.global_rotation = anchor.global_rotation
			_say("shot %s <- %s eye=%s" % [shot[0], anchor.name, str(_cam.global_position)])
		else:
			if shot.size() > 6:
				_say("  ! no anchor %s in the scene — falling back to the literal for %s"
					% [shot[6], shot[0]])
			_cam.global_position = eye
			_cam.look_at(look, Vector3.UP)
			_say("shot %s eye=%s" % [shot[0], str(eye)])
		_held = 0.0
	if _settle == 1 and SHOTS[_shot].size() > 3:
		_run_action(SHOTS[_shot][3] as StringName)
	_settle += 1
	_held += delta

	var now: Array = SHOTS[_shot]
	var hold: float = float(now[4]) if now.size() > 4 else 0.0
	var gate: StringName = now[5] as StringName if now.size() > 5 else &""
	if _settle < WARMUP or _held < hold:
		_ready_frames = 0
		return false

	if not _gate_satisfied(gate):
		_ready_frames = 0
		if _held > GATE_TIMEOUT:
			# See GATE_TIMEOUT. Captured anyway so the run still produces a full sheet,
			# but the line says so rather than leaving a silent wrong picture.
			_say("  ! gate %s never satisfied after %.1f s — capturing anyway" % [gate, _held])
			_capture(now[0])
		return false

	# THE READBACK IS ONE FRAME BEHIND, AND THAT IS NOT A DETAIL.
	#
	# `root.get_texture()` hands back the render target AS IT STANDS when `_process` runs,
	# and this frame has not been drawn yet — so a capture taken on the very frame a gate
	# comes true contains the frame BEFORE it. For `post_intact` that earlier frame is the
	# last step of the reform animation: the severed half is still a real body, posed 90%
	# of the way home and plainly visible against the shaft it is about to disappear into.
	# The state was right, the gate was right, the readback was a frame of film of a moment
	# that had already passed. Two frames of lag is what it costs to photograph the state
	# instead of the transition into it.
	_ready_frames += 1
	if _ready_frames >= CAPTURE_LAG:
		_capture(now[0])
	return false


func _capture(name_v: Variant) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		_say("  ! null image at %s" % String(name_v))
	else:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
		# Explicit type: SHOTS is an untyped Array, so `:=` cannot infer here.
		var path: String = OUT_DIR + str(name_v) + ".png"
		var err := img.save_png(path)
		_say("  saved %s (err=%d) %dx%d" % [path, err, img.get_width(), img.get_height()])
	_shot += 1
	_settle = 0
	_ready_frames = 0


## Whether a shot's gate has come true. Gates are read off the FIXTURE rather than off a
## timer, because the fixture's clock is in seconds and a frame counter is not.
##
## This is the fix for a real defect, not a tidy-up: `13_iaido_reformed` was captured
## after a FRAME count that, at this loop's actual rate, added up to well under
## `RECOVER_DELAY`, and the sheet went out with a picture of a post still in two pieces
## under a filename that claimed otherwise. A hold alone cannot fix that — any number
## picked for it is a guess about a clock the renderer cannot see. Asking the fixture
## makes the shutter and the claim the same fact.
func _gate_satisfied(gate: StringName) -> bool:
	match gate:
		&"post_intact":
			var post := _post()
			return post != null and not bool(post.call("is_cut"))
		&"post_cut":
			var post := _post()
			return post != null and bool(post.call("is_cut"))
		_:
			return true


func _post() -> Node3D:
	if _scene == null:
		return null
	return _scene.find_child("IaidoPost", true, false) as Node3D


## The `Review_*` marker a shot names as its seventh element, or null when the shot does
## not name one. Kept deliberately dumb: a shot either has an anchor or it has literals,
## and a shot that names an anchor which does not exist says so out loud (see `_process`)
## rather than silently photographing a stale vantage.
func _anchor(shot: Array) -> Node3D:
	if shot.size() <= 6 or _scene == null:
		return null
	return _scene.find_child(String(shot[6]), true, false) as Node3D


## Render-only exposure override.
##
## The compound's ground plane is albedo 0.62 lit by sun 1.2 + ambient 0.5,
## which lands around 0.95 linear. The scene was authored against the AGX curve,
## where that reads as a bright grey. This project runs the COMPATIBILITY
## renderer (see BLACK_SCREEN_DIAGNOSIS.md), and the tells are unmistakable:
## the high aerial shot of the same floor reads correctly while every eye-level
## shot comes back with the floor clipped to pure white and only the sky
## legible. That is a tonemap being ignored, not a scene that is too bright.
##
## So the override does both: name the curve explicitly for whatever renderer
## does honour it, and pull the light down far enough that the image is correct
## even if nothing honours it. This is review-only — the scene file is untouched
## and the game still renders what the game renders.
func _review_exposure() -> void:
	var we := _scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		we.environment.tonemap_exposure = 0.72
		we.environment.tonemap_white = 3.5
		we.environment.ambient_light_energy = 0.32
	var sun := _scene.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_energy = 0.9
	_say("review exposure applied")


func _say(t: String) -> void:
	_lines.append(t)
	print(t)


# ------------------------------------------------------------------------------
# Shot actions
# ------------------------------------------------------------------------------

func _run_action(action: StringName) -> void:
	match action:
		&"cut_post":
			_cut_the_post()
		&"":
			pass


## Cuts the post with the plane 聚合斩 actually cuts with, DERIVED rather than typed.
##
## For a level camera the ceremony's plane has normal `(sin θ, cos θ, 0)` where θ is
## `IaidoTuning.cut_angle_degrees`: the screen line runs through the screen centre, so
## the plane contains the view axis, and the two facts that follow from that are the
## normal above and — the reason the post is 2.30 m tall — a wound at the CAMERA'S OWN
## HEIGHT. Both derivations live in `iaido_post.gd`'s header.
func _cut_the_post() -> void:
	var post := _scene.find_child("IaidoPost", true, false) as Node3D
	if post == null:
		_say("  ! no IaidoPost in the scene")
		return
	var hurtbox := post.get_node_or_null("Hurtbox")
	if hurtbox == null:
		_say("  ! the IaidoPost has no Hurtbox")
		return
	var theta := deg_to_rad(-30.0)
	var director := _scene.find_child("IaidoDirector", true, false)
	if director != null:
		var tuning: Variant = director.get("tuning")
		if tuning != null:
			theta = deg_to_rad(float(tuning.get("cut_angle_degrees")))
	var normal := Vector3(sin(theta), cos(theta), 0.0).normalized()
	hurtbox.call("receive_hit", {
		"damage": 240.0, "poise_damage": 70.0, "element": &"physical",
		"iaido": true,
		"cut_normal": normal,
		"cut_line": Vector3(cos(theta), sin(theta), 0.0),
	})
	_say("  cut %s at %.2f m (theta %.1f deg)" % [String(post.name),
		float(post.call("cut_height")), rad_to_deg(theta)])


func flush() -> void:
	var f := FileAccess.open("F:/SEKAI/assets_source/review/training_render.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
