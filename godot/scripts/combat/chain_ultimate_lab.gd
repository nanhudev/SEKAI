extends Node3D
class_name ChainUltimateLab
# CHAIN ULTIMATE LAB — 缚星链 I 技能 / 大招的验收场.
#
# ---------------------------------------------------------------------------
# WHY A SEPARATE ROOM INSTEAD OF THE ARENA OR THE CHAIN DECK
# ---------------------------------------------------------------------------
#
# The chain arena answers "is the chain fun" and the chain deck answers "is the
# chain long enough". Neither can answer this skill's question, which is:
#
#     DOES IT LOOK LIKE A PIECE OF THE WORLD WAS TAKEN OFF IT?
#
# That needs three things the other two rooms do not have, and they are the only
# reasons this file exists:
#
#   1 · A SURFACE TO TAKE. The sheet is a picture of the world it was cut from,
#       so the world behind the anchor has to be WORTH PHOTOGRAPHING, and — this
#       is the part that is easy to get wrong — at least one hard edge in it has
#       to pass THROUGH the sheet's silhouette. A feature entirely outside the
#       film is a feature the film never had a copy of; a feature entirely inside
#       it is a feature the film hides. Only a feature that the film's outline
#       CROSSES puts a piece of the world on the film and leaves the rest of it
#       behind, and that split is the entire read. See `_crossing_columns`.
#
#   2 · DEPTH TO READ. The wall is 14m back and the columns are 9m away: when the
#       sheet is pulled toward the player it moves against a background it no
#       longer matches, and THAT parallax is half of "it came off".
#
#   3 · A TARGET THAT IS NOT IN THE PHOTOGRAPH. See `TARGET_STAND` below.
#
# Every measurement in this file is in units of the film's own projected size,
# because that is the only frame the composition question is actually asked in.
# The commentary records which of them were CHECKED AGAINST A RENDER and which
# are still reasoning — an unverified number written as confidently as a verified
# one is how a room ends up arranged around a fact nobody measured.
#
# ---------------------------------------------------------------------------
# IT HOSTS THE REAL WORLD LAYER, IT DOES NOT REBUILD IT
# ---------------------------------------------------------------------------
#
# The first version of this file built its own environment, its own light and its
# own player. It could not run at all: `CombatController` resolves
# `CombatScreenFX`, `TimeEffectManager` and `IaidoDirector` from its PARENT at
# `@onready` time, and `IaidoDirector` in turn drags ten more siblings behind it.
# A room that wants a Player therefore wants the whole world layer, and the only
# copy of that layer is `CombatSandbox.tscn`.
#
# So the room MOUNTS the sandbox and then takes the arena out of it: the props
# are retired in `_retire_arena`, the environment and the sun are re-dressed, and
# the stage is built on top. Nothing in `combat_sandbox.gd`, `chain_director.gd`
# or `chain_visual.gd` is touched, and the room can still be deleted without
# disturbing anybody's work.

const SANDBOX_SCENE := preload("res://scenes/combat/CombatSandbox.tscn")

# The player faces -Z. The sandbox's own floor tops out at y=0.25; this room's
# floor tops out at y=0 and the sandbox's is retired. The Player's origin is the
# CENTRE of its 1.8m capsule, so it RESTS at 0.9 and its eye lands at 1.55 —
# every composition number in this file is derived from that 1.55.
#
# AND IT IS PLACED AT ITS RESTING HEIGHT, not a tenth of a metre above it. The
# first version was 1.0, which meant the body spent the opening frames falling:
# a shot-list frame drawn three frames after the hold had the eye at 1.646 and
# the same frame inside a continuous take — by which time physics has settled —
# had it at 1.550. That is 0.024 of the frame's half-height of difference between
# two things that are supposed to be the same picture, and it is the exact class
# of error a shot list is not allowed to introduce.
const PLAYER_STAND := Vector3(0.0, 0.9, 6.0)

# ---------------------------------------------------------------------------
# THE TARGET STANDS INSIDE THE PICTURE, AND THAT IS NOW UNAVOIDABLE.
#
# The film is the whole frame (see `sheet_radius`), so there is no position in
# this room that is not on it: whatever the player can see is part of the world
# being taken off, and its picture goes with it. The previous version of this note
# spent a paragraph finding a place "beside the film", which was the right
# question while the film was a patch and is now an empty one.
#
# WHAT STOPS IT READING AS A GHOST IS THE VOID, NOT THE PLACEMENT. The wound covers
# the world from the pull onward, so from about 1.40s there is only ever ONE copy
# of the dummy on screen — the one travelling on the film. It is swallowed by the
# void and it takes the damage there.
#
# It stands 4.5m to the side, inside the frame: 0.72 of the half-width at its own
# depth, which is 5.0m from the camera.
# ---------------------------------------------------------------------------
const TARGET_STAND := Vector3(4.5, 0.05, 1.0)

# The stage. One directional light and a sky, per the project's standing rule.
const WALL_Z := -8.5
const WALL_HEIGHT := 9.0
const WALL_WIDTH := 30.0
# The two free-standing verticals the film's edge is meant to cut across. Nearer
# than the wall on purpose: they have to be BEHIND the film but not so far that
# the parallax between the printed half and the real half stops reading.
const COLUMN_Z := -3.0
const FLOOR_TINT := Color(0.305, 0.298, 0.285)
const WALL_TINT := Color(0.400, 0.388, 0.368)
const COLUMN_TINT := Color(0.335, 0.325, 0.310)
const DARK_TINT := Color(0.055, 0.062, 0.075)

const BEAT_LABEL := "I · CHAIN ULTIMATE        R · reset"

var sandbox: Node3D
var player: CharacterBody3D
var camera: Camera3D
var dummy: Node3D
var screen_fx: CombatScreenFX
var director: ChainUltimateDirector
var audio: ChainUltimateAudioTimeline
var room: Node3D
var label: Label
# The only piece of the room that is nearer to the camera than the wound, and
# therefore the only piece that can show in front of it. See `_process`.
var floor: MeshInstance3D

# ONE tuning for the room. The stage is derived from it (see `_build_stage`), the
# director is driven by it and the audio timeline is laid out from it, and three
# readers of three copies of a number is how a room ends up dressed for a film
# nobody is making.
var tuning: ChainUltimateTuning

var _last_beat := -1


func _ready() -> void:
	# The signature key is 聚合斩 everywhere else and this room is not about
	# 聚合斩. Unbinding it here rather than in `combat_controller.gd` keeps the
	# change inside a file that only this room uses.
	if InputMap.has_action(&"iaido"):
		InputMap.action_erase_events(&"iaido")
	_bind(&"chain_ultimate", KEY_I)
	_bind(&"chain_ultimate_reset", KEY_R)

	sandbox = $Sandbox as Node3D
	if sandbox == null:
		push_error("ChainUltimateLab: no Sandbox child — the world layer is missing")
		return
	screen_fx = sandbox.get_node_or_null("CombatScreenFX") as CombatScreenFX
	tuning = ChainUltimateTuning.new()

	_retire_arena()
	_dress_world()
	# THE CAST IS SEATED BEFORE THE STAGE IS BUILT, and that order is the point:
	# the room is dressed to the film's projected size (see `_beside_the_film`),
	# and the projection needs the real camera and the real viewport. Built first,
	# every derived x in `_build_stage` would be an assumption.
	_seat_actors()
	_build_stage()
	_add_director()
	_build_label()


func _bind(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


# ===========================================================================
# TAKING THE ARENA OUT OF THE SANDBOX
# ===========================================================================

## Everything in `CombatSandbox.tscn` that is the ARENA rather than the world
## layer, plus the four stages the sandbox script builds in code. They are
## hidden and switched off rather than freed, so a crashed take can still be
## inspected and so nothing the sandbox holds a reference to becomes invalid.
func _retire_arena() -> void:
	for path in [
		"ArenaDressing", "Floor", "RaisedPlatform", "CutWitness",
		"WindProps", "MovementLane", "ChainLab", "ExecutionLab",
		"DeveloperPanel", "ParryDebugOverlay",
	]:
		_retire(sandbox.get_node_or_null(path))


func _retire(node: Node) -> void:
	if node == null:
		return
	if node is Node3D:
		(node as Node3D).visible = false
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	for child in node.get_children():
		_retire(child)


# ===========================================================================
# THE WORLD
# ===========================================================================

func _dress_world() -> void:
	# The sandbox's environment and sun are REUSED, not duplicated: two
	# `WorldEnvironment`s in one viewport is undefined, and the project's standing
	# rule is one effective directional light plus sky ambient.
	var world_environment := sandbox.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment != null:
		world_environment.environment = _make_environment()
	var sun := sandbox.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		# A `DirectionalLight3D` shines along its own `-basis.z`, so the rotation
		# is chosen by working backwards from the wall: the wall's visible face
		# has normal +Z, so the light has to TRAVEL toward -Z. Y-30 / X-45 puts it
		# high, behind the camera's right shoulder, which lights every face the
		# player can see and throws the shadows to the left where the composition
		# has room for them.
		#
		# The first version of this was yawed 138 degrees the other way and the
		# wall rendered as a black slab: only the floor, which faces up, caught
		# anything, so the "dark doorway in a lit wall" the whole sheet depends on
		# was a dark doorway in a dark wall.
		sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
		sun.light_energy = 1.35
		sun.light_color = Color(1.0, 0.965, 0.915)
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 46.0


func _make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	# A dull, high sun and a low-contrast horizon on purpose: the sheet carries
	# the picture, and a dramatic sky would compete with it for the eye.
	sky_mat.sky_top_color = Color(0.32, 0.42, 0.56)
	sky_mat.sky_horizon_color = Color(0.52, 0.55, 0.58)
	sky_mat.ground_bottom_color = Color(0.12, 0.12, 0.13)
	sky_mat.ground_horizon_color = Color(0.30, 0.30, 0.31)
	sky_mat.sun_angle_max = 24.0
	sky.sky_material = sky_mat
	env.sky = sky
	# The project's standing lighting rule: ONE effective directional light plus
	# sky ambient. `gl_compatibility` does not implement AGX, so FILMIC.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ssao_enabled = false
	env.glow_enabled = false
	return env


# ===========================================================================
# THE FRAME — every staging number in this file is a conversion through here
# ===========================================================================
#
# The composition question ("where does the film's edge fall?") is asked in the
# FRAME; every position in this file is a distance in the ROOM. Converting one to
# the other by hand is how the first version of this room ended up dressed around
# a film that was later retuned to 1.5x its size: every number was right when it
# was typed and nothing re-checked it, so the columns stopped being crossed by the
# edge they were placed for.
#
# So they are not typed any more. They are computed, from the LIVE camera and from
# the same `ChainUltimateTuning` the director is running on.
#
# (The fov is the CAMERA's, and the camera's fov is `base_fov + fov_hold`. The
# ceremony closes it 5 degrees and holds it there through the whole haul, so the
# room has to be dressed for 70 degrees and not for the 75 it idles at.)

## The camera's fov for the ceremony, which is the only fov the film is ever seen
## at: `fov_close` lands 0.15s in and holds until the tear.
func _ceremony_fov() -> float:
	var feedback := player.get_node_or_null("CameraFeedbackController") as CameraFeedbackController
	var base := feedback.base_fov if feedback != null else 75.0
	return base + tuning.fov_close


## Half the frame's width, in metres, at `depth` in front of the camera.
func _half_width_at(depth: float) -> float:
	var size := camera.get_viewport().get_visible_rect().size if camera != null else Vector2(1280, 720)
	var aspect := size.x / maxf(size.y, 1.0)
	return depth * tan(deg_to_rad(_ceremony_fov() * 0.5)) * aspect


## A world offset at `depth`, as a fraction of the frame's half-width.
func _to_half_units(x: float, depth: float) -> float:
	return x / maxf(_half_width_at(depth), 0.0001)


## THE PATCH, AS A FRACTION OF THE FRAME'S AREA. This replaced a function called
## `film_covers_frame`, and the two are worth reading together because the answer
## flipped the whole effect:
##
##   V1 asked  "does the film reach past the frame's corners?"
##   V2 asks   "does the film clearly NOT reach them, while still being big?"
##
## Both numbers are the user's own. V1's was 「把整个画面拉进来」; V2's verdict on
## that render was 「黑色不规则 Iris」, and its replacement is 「前方约 35–55% 视野面积
## 的一块现实」. Same mesh, opposite question — which is exactly why this is a
## measurement and not a comment.
##
## MEASURED AS AN ELLIPSE, which is an UPPER BOUND: the outline is modulated down
## by up to 19% on its short lobes, so the true silhouette area is a little under
## this. The tight measurement is taken off the built mesh, in
## `tests/chain_ultimate_integration.gd` §3.
func film_frame_coverage(freed: bool) -> float:
	var depth := tuning.anchor_distance
	if freed:
		depth = maxf(depth - tuning.sheet_pull_distance, 0.5)
	var ext := tuning.sheet_extent()
	var half_h := depth * tan(deg_to_rad(_ceremony_fov() * 0.5))
	var half_w := half_h * _frame_aspect()
	return (PI * ext.x * ext.y) / maxf(4.0 * half_w * half_h, 0.0001)


## The patch's width as a fraction of the frame's half-width — the cheap sibling
## of the area, and the one that answers "does it run off the side".
func film_edge_fraction(freed: bool) -> float:
	var depth := tuning.anchor_distance
	if freed:
		depth = maxf(depth - tuning.sheet_pull_distance, 0.5)
	return _to_half_units(tuning.sheet_extent().x, depth)


func _frame_aspect() -> float:
	var size := camera.get_viewport().get_visible_rect().size \
		if camera != null else Vector2(1280, 720)
	return size.x / maxf(size.y, 1.0)


## A world x at `depth` that lands exactly on `frac` of the frame's half-width.
func _x_at(frac: float, depth: float) -> float:
	return frac * _half_width_at(depth)


## DOES THE FILM COVER THE FRAME? It must not — see `film_frame_coverage`. Kept as
## the negative form because the guard below reads better as "the thing that would
## make this an iris is not happening".
func film_covers_frame() -> bool:
	return film_frame_coverage(false) >= 1.0


# ===========================================================================
# THE STAGE
# ===========================================================================

func _build_stage() -> void:
	room = Node3D.new()
	room.name = "Room"
	add_child(room)

	var wall_depth := PLAYER_STAND.z - WALL_Z

	var floor_mesh := _box(Vector3(46.0, 0.5, 46.0), FLOOR_TINT, 0.95)
	floor = _solid("Floor", Vector3(0.0, -0.25, -2.0), floor_mesh)
	# Ground does not cast: the project's own rule, and it is the difference
	# between a lit room and a room with a black band under everything.
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# ---- THE WALL --------------------------------------------------------
	var wall := _solid("Wall", Vector3(0.0, WALL_HEIGHT * 0.5 - 0.25, WALL_Z),
		_box(Vector3(WALL_WIDTH, WALL_HEIGHT, 0.6), WALL_TINT, 0.92))
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# THE DOORWAYS. A hole in a wall is a hard dark rectangle, and a hard dark
	# rectangle is the best thing a photograph of a room can have in it.
	#
	# THEY ARE PLACED AGAINST THE FRAME, NOT AGAINST THE FILM. The old version put
	# each doorway where the film's edge would cross it, which was the right idea
	# while the film was a patch — and became meaningless the moment the film
	# started covering the whole picture, because a feature "outside the film" is
	# now simply off screen. What the room has to do now is spread hard edges
	# across the picture; the film carries all of them.
	for frac in [-0.62, 0.62]:
		_solid("Doorway", Vector3(_x_at(frac, wall_depth), 2.55, WALL_Z + 0.34),
			_box(Vector3(3.0, 5.1, 0.35), DARK_TINT, 0.98))
	# TWO VERTICALS ON THE PICTURE. The film stretches as it is peeled and pulled
	# in, and the way the eye reads that stretch is by watching something rigid ON
	# it deform. A wall beam well inside the frame is on the film and nowhere else,
	# so it is a ruler that has to bend.
	for frac in [-0.34, 0.34]:
		_solid("Beam", Vector3(_x_at(frac, wall_depth), 4.6, WALL_Z + 0.55),
			_box(Vector3(0.44, 9.6, 0.44), COLUMN_TINT, 0.88))
	# A LEDGE, for a horizontal across the upper third. Its width is derived from
	# the FRAME so its ends run off both sides of the picture rather than stopping
	# in mid-air, which is what a ledge of some round number of metres does as soon
	# as the fov moves.
	_solid("Ledge", Vector3(0.0, 8.0, WALL_Z + 0.62),
		_box(Vector3(_x_at(1.05, wall_depth) * 2.0, 0.30, 0.5), COLUMN_TINT, 0.86))

	_crossing_columns()

	# ---- THE STEP AND THE FLOOR ------------------------------------------
	var step := _solid("Step", Vector3(0.0, 0.14, -3.6),
		_box(Vector3(15.0, 0.28, 5.2), Color(0.27, 0.262, 0.25), 0.9))
	step.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Two floor inlays, so the floor in the photograph is tiled rather than flat.
	for x in [-2.1, 2.1]:
		var inlay := _solid("Inlay", Vector3(x, 0.012, -2.0),
			_box(Vector3(0.16, 0.024, 30.0), Color(0.42, 0.40, 0.36), 0.7))
		inlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## ---------------------------------------------------------------------------
## THE TWO FREE-STANDING COLUMNS.
##
## They are nearer than the wall on purpose, so that when the world comes off
## there is something with a hard edge standing INSIDE the picture — a vertical
## the film carries, at a depth the wall does not have. Parallax against a flat
## wall is weak; parallax against a column 5m in front of it is not.
##
## Placed against the FRAME (there is no film edge in view to cross any more — see
## `_build_stage`) and symmetric, so the picture has a left and a right rather than
## a middle.
## ---------------------------------------------------------------------------
func _crossing_columns() -> void:
	var depth := PLAYER_STAND.z - COLUMN_Z
	var x := _x_at(0.56, depth)
	for sign_x in [-1.0, 1.0]:
		_solid("CrossingColumn", Vector3(sign_x * x, 4.0, COLUMN_Z),
			_box(Vector3(0.72, 8.5, 0.72), COLUMN_TINT, 0.88))


func _box(size: Vector3, tint: Color, roughness: float) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = roughness
	# Metal with no reflection source renders black — the project has paid for
	# that one already. Nothing in this room is metallic.
	material.metallic = 0.0
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance


## A box that is also solid: the player walks on it and the anchor's geometry is
## honest about what is there.
func _solid(name: String, at: Vector3, visual: MeshInstance3D) -> MeshInstance3D:
	var body := StaticBody3D.new()
	body.name = name
	body.position = at
	room.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (visual.mesh as BoxMesh).size
	shape.shape = box
	body.add_child(shape)
	body.add_child(visual)
	visual.position = Vector3.ZERO
	return visual


# ===========================================================================
# THE CAST
# ===========================================================================

func _seat_actors() -> void:
	player = sandbox.get_node_or_null("Player") as CharacterBody3D
	dummy = sandbox.get_node_or_null("TechnicalDummy")
	if player == null or dummy == null:
		push_error("ChainUltimateLab: the sandbox has no Player or no TechnicalDummy")
		return
	player.global_position = PLAYER_STAND
	camera = player.get_node_or_null(
		"CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D") as Camera3D
	if camera != null:
		camera.current = true
	# THE ONE THING ABOUT THIS ROOM THAT HAS TO BE TRUE, AND IT IS NOW THE
	# OPPOSITE OF WHAT IT WAS. Two ends, both of them the user's numbers:
	#
	#   NOT AN IRIS   the film must not reach the frame's corners, or what is left
	#                 around it is a border and the whole effect is a window.
	#   35-55%        and it must still be BIG — a small patch reads as "a hole
	#                 appeared", a large one as "a piece of the world came off".
	#
	# The band below is widened past that on purpose, because the user's 35-55%
	# is measured at the HOLD while the rip is legitimately smaller (the film
	# grows as it comes toward the player). Warned rather than clamped: the fix is
	# a decision about the effect, not a number in a room.
	var rip_cover := film_frame_coverage(false)
	var hold_cover := film_frame_coverage(true)
	if film_covers_frame():
		push_warning(
			"ChainUltimateLab: the film covers %.0f%% of the frame at the rip — it must stay well under 100%% or the void around it is a border and the effect is an iris" % (rip_cover * 100.0))
	elif rip_cover < 0.15 or hold_cover > 0.60:
		push_warning(
			"ChainUltimateLab: the film is %.0f%% of the frame at the rip and %.0f%% at the hold — the band is 15-60%%, targeting ~24%% then ~41%%" % [rip_cover * 100.0, hold_cover * 100.0])
	dummy.global_position = TARGET_STAND
	# It stands there and takes it. An enemy that is attacking during a ceremony
	# about the world coming apart is a second story in the same shot.
	dummy.set("attack_cooldown", 9999.0)
	# The chain is the weapon this room is about.
	var manager := player.get_node_or_null("WeaponManager")
	if manager != null and manager.has_method("equip_weapon"):
		manager.call("equip_weapon", &"chain")


func _add_director() -> void:
	if player == null:
		return
	director = ChainUltimateDirector.new()
	director.name = "ChainUltimateDirector"
	# A child of the SANDBOX, not of this node: `configure` resolves the screen
	# effects from its own parent, and the screen effects are the sandbox's.
	sandbox.add_child(director)
	# The enemy is handed to the director as a CAPTURE EXCLUSION, not left in the
	# room. See `ChainUltimateDirector.configure`: the film is a picture of the
	# world's surface, and the enemy is the thing standing in the world this skill
	# is aimed at. Printed on the film it doubles itself the moment the picture
	# pulls in — a photograph of the enemy travelling in with the film plus the
	# enemy still standing where it was.
	if not director.configure(player, tuning, [dummy]):
		push_error("ChainUltimateLab: the director refused to configure")
		director = null
		return
	director.ultimate_event.connect(_on_ultimate_event)

	# The audio is a SIBLING of the room, not of the director: the director emits
	# events and names no file, and this node is the one place a cue time is
	# written down. See the header of `chain_ultimate_audio_timeline.gd`.
	audio = ChainUltimateAudioTimeline.new()
	audio.name = "ChainUltimateAudioTimeline"
	audio.configure(tuning)
	add_child(audio)


func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LabStrip"
	layer.layer = 120
	add_child(layer)
	var holder := PanelContainer.new()
	holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE, true)
	holder.offset_top = -56.0
	holder.offset_bottom = -14.0
	holder.offset_left = 220.0
	holder.offset_right = -220.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.05, 0.55)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	holder.add_theme_stylebox_override("panel", style)
	layer.add_child(holder)
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.text = BEAT_LABEL
	holder.add_child(label)


# ===========================================================================
# PLAY
# ===========================================================================

func trigger() -> bool:
	if director == null or director.active:
		return false
	if audio != null:
		audio.reset()
	return director.start()


func abort() -> void:
	if director == null:
		return
	if director.active:
		director.finish()
	if audio != null:
		audio.reset()
	# Put the room back exactly as it started, so a second take is the same take.
	# A lab that drifts between attempts cannot be used to compare two.
	if player != null:
		player.global_position = PLAYER_STAND
	if dummy != null:
		dummy.global_position = TARGET_STAND
		dummy.set("health", 100.0)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	if Input.is_action_just_pressed(&"chain_ultimate"):
		trigger()
		get_viewport().set_input_as_handled()
		return
	if Input.is_action_just_pressed(&"chain_ultimate_reset"):
		abort()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if director != null and director.active and audio != null:
		# `now()` and not `elapsed`: a deterministic render pins the picture to
		# `debug_hold` and leaves `elapsed` standing at 0.00s, so reading `elapsed`
		# here would mute the whole take.
		audio.update(director.now())

	# ---- AND THE WORLD STAYS ---------------------------------------------
	#
	# IT USED TO LEAVE, AND THAT WAS THE BUG. The first version hid the whole
	# room for the length of the breach, on the argument that the film carried a
	# photograph of all of it — which is true, and which made the picture read as
	# a black frame with a window in the middle of it. The user's verdict on that
	# render was 「黑色不规则 Iris / Screen Mask」, and that is the correct reading of
	# what those three mechanisms add up to: room off + film covering the frame +
	# film contracting = every pixel outside the contracted film is void. Three
	# reasonable lines of reasoning that sum to an iris, and the iris is precisely
	# the thing the skill must not look like.
	#
	# THE WOUND IS A PATCH, NOT A FRAME. It is the piece of world the film came
	# off, so it is exactly as big as the film and exactly where the film was. The
	# world is behind it, around it and in front of it, and the only thing missing
	# is the patch. Nothing leaves the room any more: the room is what proves the
	# part that is gone is gone.
	#
	# (The one exception is the object the film is a photograph OF, and it is
	# already handled where it belongs: the enemy is a capture exclusion, so it is
	# not printed on the film and stands in the wound instead. See `_add_director`.)
	if label == null:
		return
	if director != null and director.active:
		var beat := director.beat_at(director.now())
		if beat != _last_beat:
			_last_beat = beat
			label.text = "I · CHAIN ULTIMATE   ·   %s   ·   t = %.2fs" % [
				director.phase_name(director.now()), director.now()]
	elif _last_beat != -1:
		_last_beat = -1
		label.text = BEAT_LABEL


func _on_ultimate_event(_event: StringName, _data: Dictionary) -> void:
	# The room's own feedback belongs here if it ever needs any. The AUDIO does
	# not: this file is a room, not the audio contract, and the combat line never
	# names a sound file.
	pass
