extends Node3D

@export var shatter_scene: PackedScene = preload("res://scenes/combat/ShatterVFX.tscn")

@onready var dummy: Node3D = $TechnicalDummy
@onready var player: CharacterBody3D = $Player
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var screen_fx: CombatScreenFX = $CombatScreenFX
@onready var time_effects: TimeEffectManager = $TimeEffectManager


func _ready() -> void:
	dummy.shattered.connect(_on_shattered)
	screen_fx.reset()
	call_deferred("_check_visual_state")


func _on_shattered() -> void:
	var effect := shatter_scene.instantiate() as Node3D
	add_child(effect)
	effect.global_position = dummy.global_position
	camera_feedback.add_trauma(0.32)
	camera_feedback.add_impulse(Vector2(0.025, -0.035))
	screen_fx.flash_hit(0.22)
	time_effects.request_hitstop(0.085)

func _check_visual_state() -> void:
	var camera: Camera3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")
	if not camera.is_current():
		camera.make_current()
	var world_environment: WorldEnvironment = $WorldEnvironment
	print("SEKAI VISUAL camera_current=", camera.is_current(), " camera_pos=", camera.global_position, " camera_forward=", -camera.global_basis.z, " player_pos=", player.global_position, " environment=", world_environment.environment != null, " viewport=", get_viewport().get_visible_rect().size, " sandbox_visible=", is_visible_in_tree(), " fx_visible=", screen_fx.overlay.visible)