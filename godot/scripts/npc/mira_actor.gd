extends CharacterBody3D
class_name MiraActor
# ============================================================================
# MIRA — the first person the player meets. NOT the tutorial NPC.
# ============================================================================
#
# §4 IS EXPLICIT THAT SHE MUST NOT BE A MENTOR. So she has no lecture, no
# explanations, no quest-giver voice, and no line that begins with "welcome to".
# She is the person who happened to be standing there when someone fell over in
# the middle of the square, and every line she has was written to sound like a
# person deciding whether to get involved.
#
# ---------------------------------------------------------------- THE LAYERS
#
# §23 asks for the logic and the presentation to be separable, so the tree is
# built that way and this file only ever reaches into ONE of them:
#
#   Mira (CharacterBody3D)          logic: distance, facing, state, animation calls
#   ├── VisualRoot                  the replaceable artwork. EVERYTHING that is
#   │   └── <placeholder model>     a model goes in here and nothing else does.
#   ├── AnimationPlayer             looked up by name, never by path
#   ├── Interaction (Area3D)        the range in which E does something
#   ├── DialogueAnchor              where a speaker stands / where to look
#   └── CollisionShape3D            she is solid, so you cannot walk through her
#
# THE PLACEHOLDER IS THE PROJECT'S OWN CAST ENTRY, NOT A MODEL PATH. `mira` is
# already registered in `resources/cast/demo_cast.json` (skeleton_profile
# female_medium, animation_profile mira_demo) with `lpg_scifi_w.glb` as its
# rehearsal costume, so there is no string in this file that names a GLB. The
# day the real Mira arrives, `placeholder_model` changes in the manifest and
# this script plays her clips without being edited -- which is the only version
# of "asset-replaceable" that survives contact with a schedule.
#
# ------------------------------------------------- WHY THE CLIP NAMES ARE HERE
#
# The 37 clips in the placeholder library are a FIXED, KNOWN SET (measured with
# tools/probe_cast_clips.gd, not read off a manifest): Idle / Idle_Talking /
# Walk / Interact / Hit_Chest / PickUp_Table. This file names them because some
# file has to, and the alternative -- a per-actor action library -- would be a
# second cast system for one NPC. What this file does NOT do is assume the
# PLACEHOLDER will still be the actor: every clip request goes through
# `_play()` which checks the clip exists and falls back to Idle, so a real Mira
# whose rig ships three clips degrades to a standing person rather than to a
# T-posed one.

const DemoCast = preload("res://scripts/characters/demo_cast.gd")

## §4/§5: 2.2-2.6 m. The interaction range and the range at which she will turn
## her head are deliberately DIFFERENT: noticing is cheaper than talking, and an
## NPC that only ever reacts at exactly the conversation distance reads like a
## door with a keyhole.
const TALK_RANGE := 2.4
const NOTICE_RANGE := 7.0

const CLIP_IDLE := "Idle"
const CLIP_TALK := "Idle_Talking"
const CLIP_WALK := "Walk"
const CLIP_INTERACT := "Interact"
const CLIP_FLINCH := "Hit_Chest"

enum Mode { IDLE, NOTICED, TALKING, WALKING, GESTURE }

signal in_range_changed(in_range: bool)
signal walk_finished()
signal gesture_finished(kind: StringName)

var mode: int = Mode.IDLE
var speaker_name := "米拉"

var _player: Node3D = null
var _anim: AnimationPlayer = null
var _visual: Node3D = null
var _anchor: Node3D = null
var _yaw_target := 0.0
var _walk_until := 0.0
var _walk_speed := 2.0
var _walk_goal := Vector3.ZERO
var _gesture_left := 0.0
var _look_point := Vector3.ZERO
var _has_look_point := false
var _in_range := false
var _gravity := 0.0
var _told_missing := false


func _ready() -> void:
	# The interaction hub finds candidates by group, so an NPC that is not in this
	# group is an NPC you cannot talk to - which is a silent failure that looks
	# exactly like a broken prompt.
	add_to_group(&"interactable")
	_build_layers()
	_resolve_player()
	set_process(true)


## The interaction-hub contract, shared with `SwordPickup`. `interact_label()` is
## deliberately NOT the prompt text: what E says next to Mira depends on the story
## stage, and only the director knows that, so the world asks the director and the
## hub only asks THIS node where it is and how close you have to be.
func interact_label() -> String:
	return "[F]  交谈"


func interact_range() -> float:
	return TALK_RANGE


# ------------------------------------------------------------------- layers

func _build_layers() -> void:
	# VisualRoot is created if the scene did not carry one, so a designer who
	# drags a new model in by hand does not have to remember the layer name to
	# keep the script working.
	_visual = get_node_or_null("VisualRoot") as Node3D
	if _visual == null:
		_visual = Node3D.new()
		_visual.name = "VisualRoot"
		_visual.position = Vector3.ZERO
		add_child(_visual)
	# THE PLACEHOLDER IS ONLY SPAWNED IF THE SCENE DID NOT ALREADY PROVIDE ONE.
	# That is what lets the .tscn hold a hand-placed model for a review render
	# while the same scene still boots on a machine where the cast manifest is
	# missing - the fallback is a capsule, and a capsule is a person for every
	# purpose this round has (distance, facing, prompt, dialogue).
	if _visual.get_child_count() == 0:
		var node := DemoCast.spawn("mira")
		if node != null:
			_visual.add_child(node)
		else:
			_placeholder_body()
	_anim = _find_anim(_visual)
	if _anim == null and not _told_missing:
		_told_missing = true
		push_warning("MiraActor: the placeholder carries no AnimationPlayer, so she "
			+ "will stand still. The dialogue still runs - §24 forbids letting a "
			+ "missing animation stop the story - but the acting is a static body.")
	_anchor = get_node_or_null("DialogueAnchor") as Node3D
	if _anchor == null:
		_anchor = Node3D.new()
		_anchor.name = "DialogueAnchor"
		_anchor.position = Vector3(0.0, 1.35, 0.55)
		add_child(_anchor)
	await get_tree().process_frame
	_play(CLIP_IDLE)


func _find_anim(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for c in root.get_children():
		var found := _find_anim(c)
		if found != null:
			return found
	return null


func _placeholder_body() -> void:
	# The honest fallback: a person-shaped capsule announced as a placeholder,
	# not an invented model. Project rule -- an empty stand with a label beats a
	# fabricated object.
	var body := MeshInstance3D.new()
	body.name = "PlaceholderBody"
	var cap := CapsuleMesh.new()
	cap.height = 1.70
	cap.radius = 0.26
	body.mesh = cap
	body.position = Vector3(0.0, 0.85, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.44, 0.50)
	mat.roughness = 0.85
	body.material_override = mat
	_visual.add_child(body)
	var head := MeshInstance3D.new()
	head.name = "PlaceholderHead"
	var sph := SphereMesh.new()
	sph.radius = 0.13
	sph.height = 0.26
	head.mesh = sph
	head.position = Vector3(0.0, 1.58, 0.0)
	head.material_override = mat
	_visual.add_child(head)


func _resolve_player() -> void:
	_player = get_tree().get_first_node_in_group(&"player") as Node3D


# ------------------------------------------------------------------ the clips

func _play(clip: String, from_start := true) -> void:
	if _anim == null:
		return
	if not _anim.has_animation(clip):
		# A missing clip is a DEGRADATION, not a failure. Reported once per clip
		# so a log is readable, and it never stops the scene.
		if not _anim.has_animation(CLIP_IDLE):
			return
		if clip != CLIP_IDLE and _anim.current_animation != CLIP_IDLE:
			_anim.play(CLIP_IDLE)
		return
	if from_start or _anim.current_animation != clip:
		_anim.play(clip)
	else:
		_anim.play(clip)


func _play_once(clip: String, seconds: float) -> void:
	if _anim == null or not _anim.has_animation(clip):
		# NO CLIP, STILL A BEAT. A gesture with no animation must still take the
		# same amount of time, or the dialogue written around it (she points,
		# then speaks) would have the speech arrive before the point.
		_gesture_left = seconds
		return
	_anim.play(clip)
	_gesture_left = maxf(seconds, 0.15)


# ================================================================ public API

func dialogue_anchor() -> Node3D:
	return _anchor


## §4's LookAtPlayer. Called every frame while the player is near, and it is a
## YAW TARGET rather than a snap: she turns at a human rate, so walking a circle
## around her does not make her spin like a turret.
func look_at_point(point: Vector3) -> void:
	_look_point = point
	_has_look_point = true


func clear_look() -> void:
	_has_look_point = false


func talk_start() -> void:
	if mode == Mode.TALKING:
		return
	mode = Mode.TALKING
	_play(CLIP_TALK)


func talk_stop() -> void:
	if mode != Mode.TALKING:
		return
	mode = Mode.NOTICED
	_play(CLIP_IDLE)


## The Talk gesture. `kind` is a NAME, not an animation, so the real Mira's
## action set (`mira_inspect`, `mira_point_finding` -- already in her
## animation_profile backlog) can be wired in one place later.
func gesture(kind: StringName, seconds := 1.6) -> void:
	mode = Mode.GESTURE
	match kind:
		&"point":
			# PLACEHOLDER, AND NAMED AS ONE. No point clip exists in the shared
			# library (base_motions.json: Point = "missing", plan = upper-body
			# additive), so the reach-out of `Interact` stands in. It reads as
			# indicating something, which is all §5's "她指向旁边" needs.
			_play_once(CLIP_INTERACT, seconds)
		&"inspect":
			_play_once(CLIP_INTERACT, seconds)
		&"pickup":
			_play_once("PickUp_Table", seconds)
		_:
			_play_once(CLIP_INTERACT, seconds)


func gesture_done() -> void:
	gesture_finished.emit(&"done")


func point_at(point: Vector3) -> void:
	look_at_point(point)
	gesture(&"point", 1.8)


func react() -> void:
	# A flinch, plus a step that she does not take. `Hit_Chest` is the only
	# authored recoil in the library and it is the right SHAPE for "she heard
	# something behind her"; the real beat is her head, and the head is what the
	# yaw target already moves.
	_play_once(CLIP_FLINCH, 0.6)
	mode = Mode.GESTURE


## §14/§19: she walks to a spot and stops there. `seconds` is the DIRECTOR's
## duration, and the speed is derived from it rather than chosen, so a line of
## dialogue written against "2.6 s" stays true if the distance changes.
func walk_to(goal: Vector3, seconds: float) -> void:
	_walk_goal = Vector3(goal.x, global_position.y, goal.z)
	var distance := global_position.distance_to(_walk_goal)
	_walk_speed = distance / maxf(seconds, 0.2)
	_walk_until = seconds
	mode = Mode.WALKING
	_play(CLIP_WALK)
	look_at_point(_walk_goal)


func mode_name() -> String:
	match mode:
		Mode.IDLE: return "IDLE"
		Mode.NOTICED: return "NOTICED"
		Mode.TALKING: return "TALK"
		Mode.WALKING: return "WALK"
		Mode.GESTURE: return "GESTURE"
	return "?"


# ================================================================== runtime

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_resolve_player()
	if _player != null:
		var d := global_position.distance_to(_player.global_position)
		var now_in := d <= TALK_RANGE
		if now_in != _in_range:
			_in_range = now_in
			in_range_changed.emit(_in_range)
		# Notice before talking: between the two ranges she simply looks up.
		if mode == Mode.IDLE and d <= NOTICE_RANGE:
			mode = Mode.NOTICED
		# Facing follows the player whenever she is not busy walking away.
		if mode != Mode.WALKING and d <= NOTICE_RANGE:
			look_at_point(_player.global_position)
		if _in_range and mode == Mode.NOTICED:
			look_at_point(_player.global_position)

	if _gesture_left > 0.0:
		_gesture_left = maxf(0.0, _gesture_left - delta)
		if _gesture_left == 0.0 and mode == Mode.GESTURE:
			mode = Mode.NOTICED
			_play(CLIP_IDLE)

	if mode == Mode.WALKING:
		_walk_until = maxf(0.0, _walk_until - delta)
		var to_goal := _walk_goal - global_position
		to_goal.y = 0.0
		if to_goal.length() > 0.08 and _walk_until > 0.0:
			# We are NOT using NavigationAgent3D here on purpose. Mira walks a
			# straight line across a square she is already standing on, and an
			# agent would need a baked navmesh for 4 m of pavement. The day an
			# NPC has to path around a building, that decision changes - and the
			# seam for it is this one branch.
			var step := minf(_walk_speed * delta, to_goal.length())
			global_position += to_goal.normalized() * step
			velocity = Vector3.ZERO
		else:
			mode = Mode.NOTICED
			_play(CLIP_IDLE)
			walk_finished.emit()

	_apply_gravity(delta)
	_turn_toward_target(delta)


func _apply_gravity(delta: float) -> void:
	# She stands on a town square that has a slope on it, so she has to fall
	# like everything else or she floats a hand's width above the paving on one
	# side of the plaza and sinks into it on the other.
	if is_on_floor():
		_gravity = 0.0
	else:
		_gravity -= 22.0 * delta
	velocity.y = _gravity
	move_and_slide()
	if is_on_floor():
		_gravity = 0.0


func _turn_toward_target(delta: float) -> void:
	if not _has_look_point:
		return
	var d := _look_point - global_position
	d.y = 0.0
	if d.length_squared() < 0.0004:
		return
	# THE CHARACTER'S FRONT IS +Z.
	#
	# Measured, not assumed: the placeholder rigs face +Z once imported, so the
	# yaw that points the body at a direction is atan2(x, z) and NOT the
	# atan2(-x, -z) that a -Z-facing model needs. Getting this wrong is a
	# 180-degree error that reads as "the NPC is rude" rather than as a bug,
	# because every test of "does she look at you" still passes at the wrong sign.
	_yaw_target = atan2(d.x, d.z)
	rotation.y = lerp_angle(rotation.y, _yaw_target, clampf(delta * 3.2, 0.0, 1.0))
