extends Node
class_name IaidoDirector

@export var tuning: IaidoTuning = preload("res://resources/tuning/IaidoTuning.tres")

@onready var player: CharacterBody3D = get_parent().get_node("Player")
@onready var combat: CombatController = player.get_node("CombatController")
@onready var camera: Camera3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var sword: Node3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual")
@onready var iaido_fx: IaidoScreenFX = get_parent().get_node("IaidoScreenFX")
@onready var audio_state: AudioStateController = get_parent().get_node("AudioStateController")
@onready var time_effects: TimeEffectManager = get_parent().get_node("TimeEffectManager")
@onready var collector: IaidoTargetCollector = get_parent().get_node("IaidoTargetCollector")
@onready var tear: IaidoTear3D = get_parent().get_node("IaidoTear3D")
@onready var charge_audio: AudioStreamPlayer = get_parent().get_node("IaidoChargeAudio")
@onready var click_audio: AudioStreamPlayer = get_parent().get_node("IaidoClickAudio")
@onready var cut_audio: AudioStreamPlayer = get_parent().get_node("IaidoCutAudio")
@onready var glass_audio: AudioStreamPlayer = get_parent().get_node("IaidoGlassAudio")
@onready var sheathe_audio: AudioStreamPlayer = get_parent().get_node("IaidoSheatheAudio")

var active := false
var elapsed := 0.0
var target: Node3D
var targets: Array[Node3D] = []
var start_position := Vector3.ZERO
var previous_modes: Dictionary = {}
var events: Dictionary = {}
var hold_time := -1.0
var playback_speed := 1.0
var created_bus := false
var world_audio_frozen := false
var target_marks: Array[MeshInstance3D] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Iaido") == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Iaido")
		created_bus = true
	for cue in [charge_audio, click_audio, cut_audio, glass_audio, sheathe_audio]:
		cue.bus = "Iaido"
	click_audio.pitch_scale = 1.42
	sheathe_audio.pitch_scale = 0.82
	playback_speed = tuning.debug_speed


func start_iaido() -> void:
	if active:
		return
	time_effects.reset()
	targets = collector.collect_targets(player, camera)
	target = targets[0] if not targets.is_empty() else null
	start_position = player.global_position
	player.velocity = Vector3.ZERO
	elapsed = 0.0
	events.clear()
	world_audio_frozen = false
	active = true
	iaido_fx.reset_iaido_fx()
	tear.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * 2.5)
	tear.rotation.z += 0.56
	for node in [camera_feedback, sword]:
		previous_modes[node] = node.process_mode
		node.process_mode = Node.PROCESS_MODE_ALWAYS
	audio_state.pause_music()
	audio_state.duck_world_audio()
	get_tree().paused = true
	charge_audio.play()


func _process(delta: float) -> void:
	if not active:
		return
	if float(player.get("health")) <= 0.0:
		finish_iaido()
		return
	elapsed = hold_time if hold_time >= 0.0 else elapsed + delta * playback_speed
	combat.state_time = elapsed
	player.global_position = start_position
	player.velocity = Vector3.ZERO
	if elapsed >= 0.10 and not world_audio_frozen:
		world_audio_frozen = true
		audio_state.pause_world_audio()
	tear.stage(elapsed, tuning)
	_update_visuals()
	_fire_events()
	if elapsed >= tuning.restore_end and hold_time < 0.0:
		finish_iaido()


func _update_visuals() -> void:
	var focus := smoothstep(0.0, 0.18, elapsed) * (1.0 - smoothstep(tuning.final_click + 0.07, tuning.restore_end, elapsed))
	var wave := smoothstep(tuning.first_click, tuning.wave_end - 0.06, elapsed) * (1.0 - smoothstep(tuning.wave_end, tuning.first_tear_end, elapsed))
	var pre := smoothstep(tuning.wave_end, tuning.first_tear_end, elapsed) * (1.0 - smoothstep(tuning.draw_end, tuning.rupture_end, elapsed))
	var main := smoothstep(tuning.draw_end, tuning.rupture_end, elapsed) * (1.0 - smoothstep(tuning.final_click, tuning.restore_end, elapsed))
	var split := smoothstep(tuning.rupture_end, tuning.split_end, elapsed) * 5.0 * (1.0 - smoothstep(tuning.final_click, tuning.restore_end, elapsed))
	var fracture := smoothstep(tuning.split_end, tuning.glass_end, elapsed) * (1.0 - smoothstep(tuning.final_click, tuning.restore_end, elapsed))
	if elapsed > tuning.damage_time + 0.11:
		_clear_target_marks()
	var wave_phase := lerpf(-1.0, 1.0, smoothstep(tuning.first_click, tuning.wave_end, elapsed))
	iaido_fx.set_frame(focus, wave, pre, main, split, fracture, wave_phase)
	camera_feedback.fov_hold = 9.0 * focus
	camera_feedback.iaido_pitch = deg_to_rad(1.4) * smoothstep(tuning.focus_start, tuning.focus_end, elapsed) * (1.0 - smoothstep(tuning.draw_slow_end, tuning.draw_end, elapsed))
	if elapsed >= tuning.rupture_end and elapsed < tuning.split_end:
		camera_feedback.roll = lerpf(camera_feedback.roll, deg_to_rad(2.4), 0.18)
	if elapsed >= tuning.final_click:
		camera_feedback.roll = lerpf(camera_feedback.roll, 0.0, 0.15)


func _fire_events() -> void:
	if elapsed >= tuning.first_click and not events.has("click"):
		events["click"] = true
		click_audio.play()
		iaido_fx.set_frame(1.0, 0.1, 0.04, 0.0, 0.0, 0.0)
		camera_feedback.add_impulse(Vector2(0.0, -0.008))
	if elapsed >= tuning.draw_fast_end and not events.has("cut"):
		events["cut"] = true
		cut_audio.play()
		camera_feedback.add_impulse(Vector2(0.02, -0.018))
	if elapsed >= tuning.split_end and not events.has("glass"):
		events["glass"] = true
		glass_audio.play()
	if elapsed >= tuning.damage_time and not events.has("impact"):
		events["impact"] = true
		_apply_impact()
	if elapsed >= tuning.final_click and not events.has("sheathe"):
		events["sheathe"] = true
		sheathe_audio.play()


func _apply_impact() -> void:
	for i in targets.size():
		var actor := targets[i]
		if not is_instance_valid(actor) or not actor.visible:
			continue
		var hurtbox := actor.get_node_or_null("Hurtbox") as CombatHurtbox
		if hurtbox == null:
			continue
		hurtbox.receive_hit({"damage": 65.0 if i == 0 else 39.0, "poise_damage": 70.0 if i == 0 else 42.0, "element": &"physical", "impulse": 0.0, "source": player})
		_add_target_mark(actor)
	camera_feedback.add_impulse(Vector2(0.018, -0.03))
	camera_feedback.add_trauma(0.16)
	camera_feedback.roll_impulse(2.5)


func _add_target_mark(actor: Node3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.4, 0.018, 0.014)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color(1.0, 0.96, 0.82)
	mesh.material = material
	var mark := MeshInstance3D.new()
	mark.mesh = mesh
	get_parent().add_child(mark)
	mark.global_transform = Transform3D(camera.global_basis, actor.global_position + Vector3.UP * 1.05)
	mark.rotation.z += 0.56
	target_marks.append(mark)


func _clear_target_marks() -> void:
	for mark in target_marks:
		if is_instance_valid(mark):
			mark.queue_free()
	target_marks.clear()


func set_debug_hold(time: float) -> void:
	hold_time = time
	if not active:
		combat.iaido_ready_at = 0.0
		combat.request(&"iaido")
	if active:
		elapsed = time
		_process(0.0)


func release_debug_hold() -> void:
	hold_time = -1.0


func set_debug_speed(speed: float) -> void:
	playback_speed = clampf(speed, 0.25, 1.0)


func finish_iaido() -> void:
	if not active:
		iaido_fx.reset_iaido_fx()
		tear.visible = false
		_clear_target_marks()
		return
	active = false
	hold_time = -1.0
	tear.visible = false
	_clear_target_marks()
	iaido_fx.reset_iaido_fx()
	camera_feedback.fov_hold = 0.0
	camera_feedback.iaido_pitch = 0.0
	get_tree().paused = false
	player.global_position = start_position
	player.velocity = Vector3.ZERO
	for node in previous_modes:
		if is_instance_valid(node):
			node.process_mode = previous_modes[node]
	previous_modes.clear()
	audio_state.resume_world_audio()
	audio_state.restore_world_audio()
	audio_state.resume_music()
	combat.finish_action()
	camera_feedback.add_impulse(Vector2(0.0, 0.014))


func _exit_tree() -> void:
	_clear_target_marks()
	if active:
		get_tree().paused = false
		if is_instance_valid(audio_state):
			audio_state.resume_world_audio()
			audio_state.restore_world_audio()
			audio_state.resume_music()
	if is_instance_valid(iaido_fx):
		iaido_fx.reset_iaido_fx()
	if created_bus:
		var index := AudioServer.get_bus_index("Iaido")
		if index > 0:
			AudioServer.remove_bus(index)
