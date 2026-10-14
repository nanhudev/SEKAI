extends Node
class_name MomentOfNoMoonDirector
# SEKAI · 无明一刻 / MOMENT OF NO-MOON — the 藏锋流 ULTIMATE.
#
# In-world, 无明一刻 is the instant in which the world has not yet realised it
# has been cut. It is a sword-technique term, not a religious rite.
#
# This is NOT an upgraded 聚合斩. 聚合斩 opens the world and breaks glass; the
# Moment does the opposite — it stops everything, marks several enemies with
# hair-thin white lines, performs ONE almost invisible draw, waits, sheathes,
# and only then lets every mark open at the same instant.
#
# One cut, many results. Never twenty teleporting slashes.
#
# The animation hooks below are deliberately separate assets from the signature
# ceremony: UltimateReady / UltimateHold / UltimateDraw / UltimateSheathe.
# See docs/COMBAT_ANIMATION_REQUIREMENTS.md.

signal moment_event(event: StringName)

# --- timeline (placeholder-grade, one place, do not scatter) -----------------
const T_ACTIVATION := 0.00
const T_SILENCE := 0.15
const T_MONO := 0.35
const T_MARK := 0.95
const T_READY := 1.55
const T_DRAW := 2.00
const T_DRAW_END := 2.09
const T_SHEATHE := 3.10
const T_SHEATHE_END := 3.85
const T_CLICK := 3.92
const T_ACTIVATE := 3.99
const T_RESTORE := 4.35
const T_END := 4.85

# --- ultimate numbers -------------------------------------------------------
const MAX_TARGETS := 5
const TARGET_RANGE := 16.0
const TARGET_CONE_DEGREES := 70.0
const TARGET_VERTICAL_TOLERANCE := 4.0
const MARK_DAMAGE := 82.0
const MARK_POISE := 120.0
const COOLDOWN := 26.0

# --- animation hooks (placeholder poses in camera space) --------------------
const POSE_READY := Vector3(-0.30, -0.66, -0.80)
const POSE_READY_ROT := Vector3(0.16, -0.10, 1.85)
const POSE_DRAWN := Vector3(-0.26, -0.62, -0.86)
const POSE_DRAWN_ROT := Vector3(0.14, -0.14, 1.72)
const POSE_SHEATH := Vector3(-0.50, -0.60, -0.74)
const POSE_SHEATH_ROT := Vector3(0.12, -0.16, 2.12)

@onready var player: CharacterBody3D = get_parent().get_node("Player")
@onready var camera: Camera3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")
@onready var sword: Node3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual")
@onready var combat: CombatController = player.get_node("CombatController")
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var screen_fx: CombatScreenFX = get_parent().get_node("CombatScreenFX")
@onready var audio_state: AudioStateController = get_parent().get_node("AudioStateController")
@onready var time_effects: TimeEffectManager = get_parent().get_node("TimeEffectManager")

var active := false
var elapsed := 0.0
var targets: Array[Node3D] = []
var marks: Array[ShadowCutMark] = []
var events: Dictionary = {}
var previous_modes: Dictionary = {}
var frozen_hostiles := false
var entry_pose := Vector3.ZERO
var entry_pose_rot := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func start_moment() -> bool:
	if active:
		return false
	active = true
	elapsed = 0.0
	events.clear()
	marks.clear()
	previous_modes.clear()
	frozen_hostiles = false
	entry_pose = sword.position
	entry_pose_rot = sword.rotation
	targets = _collect_targets()
	moment_event.emit(&"activation")
	return true


func _process(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	_fire_events()
	_update_weapon_pose()
	if elapsed >= T_END:
		finish_moment()


func _fire_events() -> void:
	var t := elapsed
	if t >= T_SILENCE and not events.has("silence"):
		events["silence"] = true
		# The soundtrack of the world is switched off. It comes back on the click.
		audio_state.pause_world_audio()
		audio_state.pause_music()
		moment_event.emit(&"silence")
	if t >= T_MONO and not events.has("mono"):
		events["mono"] = true
		_freeze_hostiles(true)
		moment_event.emit(&"monochrome")
	if t >= T_MARK and not events.has("mark"):
		events["mark"] = true
		_spawn_marks()
		moment_event.emit(&"mark")
	if t >= T_READY and not events.has("ready"):
		events["ready"] = true
		moment_event.emit(&"ultimate_ready")
	if t >= T_DRAW and not events.has("draw"):
		events["draw"] = true
		moment_event.emit(&"ultimate_draw")
	if t >= T_DRAW_END and not events.has("hold"):
		events["hold"] = true
		moment_event.emit(&"ultimate_hold")
	if t >= T_SHEATHE and not events.has("sheathe"):
		events["sheathe"] = true
		moment_event.emit(&"ultimate_sheathe")
	if t >= T_CLICK and not events.has("click"):
		events["click"] = true
		audio_state.restore_world_audio()
		audio_state.resume_music()
		screen_fx.flash_hit(0.10)
		camera_feedback.add_impulse(Vector2(0.0, -0.008))
		moment_event.emit(&"click")
	if t >= T_ACTIVATE and not events.has("activate"):
		events["activate"] = true
		_activate_marks()
		moment_event.emit(&"marks_activate")
	if t >= T_RESTORE and not events.has("restore"):
		events["restore"] = true
		screen_fx.set_world_drain(0.0)
		moment_event.emit(&"restore")


func _update_weapon_pose() -> void:
	var t := elapsed
	var p := entry_pose
	var r := entry_pose_rot
	if t < T_READY - 0.35:
		pass
	elif t < T_READY:
		var u := SwordPoseSampler.ease_out((t - (T_READY - 0.35)) / 0.35, 2.0)
		p = entry_pose.lerp(POSE_READY, u)
		r = entry_pose_rot.lerp(POSE_READY_ROT, u)
	elif t < T_DRAW:
		p = POSE_READY
		r = POSE_READY_ROT
	elif t < T_DRAW_END:
		# The draw is 90 ms and travels about five centimetres. Almost nothing
		# happens; that is the entire idea.
		var u := SwordPoseSampler.ease_in((t - T_DRAW) / (T_DRAW_END - T_DRAW), 2.0)
		p = POSE_READY.lerp(POSE_DRAWN, u)
		r = POSE_READY_ROT.lerp(POSE_DRAWN_ROT, u)
	elif t < T_SHEATHE:
		p = POSE_DRAWN
		r = POSE_DRAWN_ROT
	elif t < T_SHEATHE_END:
		var u := SwordPoseSampler.ease_in_out((t - T_SHEATHE) / (T_SHEATHE_END - T_SHEATHE))
		p = POSE_DRAWN.lerp(POSE_SHEATH, u)
		r = POSE_DRAWN_ROT.lerp(POSE_SHEATH_ROT, u)
	elif t < T_RESTORE:
		p = POSE_SHEATH
		r = POSE_SHEATH_ROT
	else:
		var u := SwordPoseSampler.ease_out((t - T_RESTORE) / (T_END - T_RESTORE), 1.6)
		p = POSE_SHEATH.lerp(sword.IDLE_POSITION, u)
		r = POSE_SHEATH_ROT.lerp(sword.IDLE_ROTATION, u)
	sword.position = p
	sword.rotation = r
	# Monochrome grade: the world drains while nothing is happening.
	if t >= T_MONO and t < T_RESTORE:
		var drain := clampf((t - T_MONO) / 0.45, 0.0, 1.0)
		if t > T_ACTIVATE:
			drain *= 1.0 - clampf((t - T_ACTIVATE) / (T_RESTORE - T_ACTIVATE), 0.0, 1.0)
		screen_fx.set_world_drain(drain * 0.92)


# ------------------------------------------------------------ target handling

func _collect_targets() -> Array[Node3D]:
	var scored: Array[Dictionary] = []
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var space := player.get_world_3d().direct_space_state
	for candidate in get_tree().get_nodes_in_group("hostiles"):
		if not candidate is Node3D or not candidate.visible:
			continue
		var actor := candidate as Node3D
		var health: Variant = actor.get("health")
		if health != null and float(health) <= 0.0:
			continue
		var target_point := actor.global_position + Vector3.UP
		var offset := target_point - origin
		var distance := offset.length()
		if distance > TARGET_RANGE or absf(offset.y) > TARGET_VERTICAL_TOLERANCE:
			continue
		var horizontal := Vector2(offset.x, offset.z).normalized()
		var forward_horizontal := Vector2(forward.x, forward.z).normalized()
		var angle := rad_to_deg(acos(clampf(horizontal.dot(forward_horizontal), -1.0, 1.0)))
		if angle > TARGET_CONE_DEGREES:
			continue
		# Line of sight: you cannot cut what you cannot see.
		var query := PhysicsRayQueryParameters3D.create(origin, target_point)
		query.exclude = [player.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var collider: Object = hit.get("collider")
			if collider != actor and not (collider is Node and actor.is_ancestor_of(collider)):
				continue
		if not camera.is_position_in_frustum(target_point):
			continue
		var screen_center := camera.get_viewport().get_visible_rect().size * 0.5
		var screen_offset := camera.unproject_position(target_point).distance_to(screen_center) / maxf(1.0, screen_center.length())
		scored.append({
			"actor": actor,
			"score": (1.0 - clampf(screen_offset, 0.0, 1.0)) * 0.6 + (1.0 - distance / TARGET_RANGE) * 0.4,
		})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	var results: Array[Node3D] = []
	for entry in scored:
		if results.size() >= MAX_TARGETS:
			break
		results.append(entry["actor"])
	return results


func _spawn_marks() -> void:
	var tilt := 0.42
	for target in targets:
		if not is_instance_valid(target):
			continue
		var mark := ShadowCutMark.new()
		add_child(mark)
		mark.global_position = target.global_position + Vector3.UP * 1.05
		mark.setup(1.7, tilt, Color(1.0, 1.0, 1.0))
		# Alternate the tilt so a group of marks reads as several cuts, not one.
		tilt = -tilt if tilt > 0.0 else absf(tilt)
		marks.append(mark)


func _activate_marks() -> void:
	_freeze_hostiles(false)
	for mark in marks:
		if is_instance_valid(mark):
			mark.activate()
	for target in targets:
		if not is_instance_valid(target):
			continue
		var hurtbox := target.get_node_or_null("Hurtbox") as CombatHurtbox
		if hurtbox == null:
			continue
		hurtbox.receive_hit({
			"damage": MARK_DAMAGE,
			"poise_damage": MARK_POISE,
			"element": &"physical",
			"impulse": 0.0,
			"source": player,
			"target": target,
			"interrupt": true,
		})
	camera_feedback.add_trauma(0.34)
	camera_feedback.add_impulse(Vector2(0.016, -0.014))
	screen_fx.flash_hit(0.24)
	if combat.hitstop_scale > 0.0:
		time_effects.request_hitstop(0.11 * combat.hitstop_scale)


func _freeze_hostiles(freeze: bool) -> void:
	if freeze:
		if frozen_hostiles:
			return
		for hostile in get_tree().get_nodes_in_group("hostiles"):
			if hostile is Node:
				previous_modes[hostile] = hostile.process_mode
				hostile.process_mode = Node.PROCESS_MODE_DISABLED
		frozen_hostiles = true
	else:
		if not frozen_hostiles:
			return
		for node in previous_modes:
			if is_instance_valid(node):
				node.process_mode = previous_modes[node]
		previous_modes.clear()
		frozen_hostiles = false


# ---------------------------------------------------------------- lifecycle

func finish_moment() -> void:
	if not active:
		_hard_reset()
		return
	active = false
	_hard_reset()
	combat.ultimate_ready_at = Time.get_ticks_msec() / 1000.0 + COOLDOWN
	combat.notify_ultimate_finished()


func _hard_reset() -> void:
	_freeze_hostiles(false)
	for mark in marks:
		if is_instance_valid(mark):
			mark.queue_free()
	marks.clear()
	targets.clear()
	if is_instance_valid(screen_fx):
		screen_fx.set_world_drain(0.0)
	if is_instance_valid(time_effects):
		time_effects.reset()
	if is_instance_valid(audio_state):
		audio_state.restore_world_audio()
	if is_instance_valid(sword):
		sword.position = sword.IDLE_POSITION
		sword.rotation = sword.IDLE_ROTATION
	elapsed = 0.0


func _exit_tree() -> void:
	_hard_reset()
