extends Node
class_name IaidoDirector

@onready var player: CharacterBody3D = get_parent().get_node("Player")
@onready var combat: CombatController = player.get_node("CombatController")
@onready var camera: Camera3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var sword: Node3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual")
@onready var screen_fx: CombatScreenFX = get_parent().get_node("CombatScreenFX")
@onready var audio_state: AudioStateController = get_parent().get_node("AudioStateController")
@onready var time_effects: TimeEffectManager = get_parent().get_node("TimeEffectManager")
@onready var collector: IaidoTargetCollector = get_parent().get_node("IaidoTargetCollector")
@onready var tear: IaidoTear3D = get_parent().get_node("IaidoTear3D")
@onready var charge_audio: AudioStreamPlayer = get_parent().get_node("IaidoChargeAudio")
@onready var cut_audio: AudioStreamPlayer = get_parent().get_node("IaidoCutAudio")
@onready var sheathe_audio: AudioStreamPlayer = get_parent().get_node("IaidoSheatheAudio")

var active := false
var elapsed := 0.0
var target: Node3D
var start_position := Vector3.ZERO
var impacted := false
var cut_played := false
var sheathe_played := false
var previous_modes: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start_iaido() -> void:
	if active:
		return
	time_effects.reset()
	target = collector.collect(player, camera)
	start_position = player.global_position
	player.velocity = Vector3.ZERO
	elapsed = 0.0
	impacted = false
	cut_played = false
	sheathe_played = false
	active = true
	tear.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * 2.5)
	tear.rotation.z += 0.56
	for node in [camera_feedback, sword, screen_fx]:
		previous_modes[node] = node.process_mode
		node.process_mode = Node.PROCESS_MODE_ALWAYS
	audio_state.pause_world_audio()
	get_tree().paused = true
	charge_audio.play()


func _process(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	tear.stage(elapsed)
	screen_fx.set_distortion(smoothstep(0.49, 0.62, elapsed) * (1.0 - smoothstep(0.86, 1.16, elapsed)))
	combat.state_time = elapsed
	player.global_position = start_position
	player.velocity = Vector3.ZERO
	var focus := smoothstep(0.0, 0.18, elapsed) * 0.80
	if elapsed > 1.17:
		focus *= 1.0 - smoothstep(1.17, 1.48, elapsed)
	screen_fx.set_iaido_focus(focus)
	camera_feedback.fov_hold = 9.0 * smoothstep(0.0, 0.18, elapsed) * (1.0 - smoothstep(1.17, 1.48, elapsed))
	if elapsed >= 0.50 and elapsed < 0.65:
		screen_fx.slash_flash(1.0 - smoothstep(0.50, 0.65, elapsed))
	if elapsed >= 0.50 and not cut_played:
		cut_played = true
		cut_audio.play()
	if elapsed >= 0.76 and not impacted:
		impacted = true
		_apply_impact()
	if elapsed >= 1.17 and not sheathe_played:
		sheathe_played = true
		sheathe_audio.play()
	if elapsed >= 1.48:
		finish_iaido()


func _apply_impact() -> void:
	if is_instance_valid(target):
		var hurtbox := target.get_node_or_null("Hurtbox") as CombatHurtbox
		if hurtbox != null:
			hurtbox.receive_hit({"damage": 65.0, "poise_damage": 70.0, "element": &"physical", "impulse": 0.0, "source": player})
	camera_feedback.add_impulse(Vector2(0.018, -0.03))
	camera_feedback.roll_impulse(2.5)
	screen_fx.flash_hit(0.20)


func finish_iaido() -> void:
	if not active:
		return
	active = false
	tear.visible = false
	get_tree().paused = false
	player.global_position = start_position
	player.velocity = Vector3.ZERO
	screen_fx.reset()
	camera_feedback.fov_hold = 0.0
	for node in previous_modes:
		if is_instance_valid(node):
			node.process_mode = previous_modes[node]
	previous_modes.clear()
	audio_state.resume_world_audio()
	combat.finish_action()
	camera_feedback.add_impulse(Vector2(0.0, 0.014))


func _exit_tree() -> void:
	if active:
		get_tree().paused = false
		if is_instance_valid(audio_state):
			audio_state.resume_world_audio()
