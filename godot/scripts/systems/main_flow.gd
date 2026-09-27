extends Node

@export var combat_scene: PackedScene = preload("res://scenes/combat/CombatSandbox.tscn")

@onready var main_menu: Control = $MainMenu
@onready var pause_menu: Control = $PauseMenu
@onready var settings_menu: Control = $SettingsMenu

var combat_sandbox: Node3D
var settings_return_to_pause := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main_menu.start_pressed.connect(start_game)
	main_menu.settings_pressed.connect(func() -> void: _open_settings(false))
	main_menu.exit_pressed.connect(exit_game)
	pause_menu.resume_pressed.connect(resume_game)
	pause_menu.settings_pressed.connect(func() -> void: _open_settings(true))
	pause_menu.title_pressed.connect(return_to_title)
	pause_menu.exit_pressed.connect(exit_game)
	settings_menu.back_pressed.connect(_close_settings)
	settings_menu.fov_slider.value_changed.connect(_apply_settings)
	settings_menu.sensitivity_slider.value_changed.connect(_apply_settings)
	settings_menu.motion_slider.value_changed.connect(_apply_settings)
	settings_menu.shake_slider.value_changed.connect(_apply_settings)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and combat_sandbox != null and not settings_menu.visible:
		if pause_menu.visible:
			resume_game()
		else:
			pause_game()
		get_viewport().set_input_as_handled()


func start_game() -> void:
	if combat_sandbox != null:
		return
	combat_sandbox = combat_scene.instantiate() as Node3D
	add_child(combat_sandbox)
	move_child(combat_sandbox, 0)
	main_menu.visible = false
	pause_menu.visible = false
	settings_menu.visible = false
	_apply_settings(0.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func pause_game() -> void:
	if combat_sandbox == null:
		return
	var iaido: IaidoDirector = combat_sandbox.get_node("IaidoDirector")
	if iaido.active:
		iaido.finish_iaido()
	combat_sandbox.get_node("AudioStateController").pause_world_audio()
	combat_sandbox.process_mode = Node.PROCESS_MODE_DISABLED
	pause_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume_game() -> void:
	if combat_sandbox == null:
		return
	combat_sandbox.process_mode = Node.PROCESS_MODE_INHERIT
	combat_sandbox.get_node("AudioStateController").resume_world_audio()
	pause_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func return_to_title() -> void:
	if combat_sandbox != null:
		var iaido: IaidoDirector = combat_sandbox.get_node("IaidoDirector")
		if iaido.active:
			iaido.finish_iaido()
		combat_sandbox.get_node("AudioStateController").resume_world_audio()
		combat_sandbox.queue_free()
		combat_sandbox = null
	Engine.time_scale = 1.0
	pause_menu.visible = false
	settings_menu.visible = false
	main_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func exit_game() -> void:
	get_tree().quit()


func _open_settings(from_pause: bool) -> void:
	settings_return_to_pause = from_pause
	main_menu.visible = false
	pause_menu.visible = false
	settings_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_settings() -> void:
	settings_menu.visible = false
	pause_menu.visible = settings_return_to_pause
	main_menu.visible = not settings_return_to_pause


func _apply_settings(_value: float) -> void:
	if combat_sandbox == null:
		return
	var player: CharacterBody3D = combat_sandbox.get_node("Player")
	var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
	camera_feedback.base_fov = settings_menu.fov_slider.value
	camera_feedback.camera_motion_strength = settings_menu.motion_slider.value
	camera_feedback.camera_shake_strength = settings_menu.shake_slider.value
	player.set("mouse_sensitivity", settings_menu.sensitivity_slider.value)
