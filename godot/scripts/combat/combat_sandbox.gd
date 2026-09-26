extends Node3D

@export var shatter_scene: PackedScene = preload("res://scenes/combat/ShatterVFX.tscn")

@onready var dummy: Node3D = $TechnicalDummy
@onready var player: CharacterBody3D = $Player
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var screen_fx: CombatScreenFX = $CombatScreenFX
@onready var time_effects: TimeEffectManager = $TimeEffectManager


func _ready() -> void:
	dummy.shattered.connect(_on_shattered)


func _on_shattered() -> void:
	var effect := shatter_scene.instantiate() as Node3D
	add_child(effect)
	effect.global_position = dummy.global_position
	camera_feedback.add_trauma(0.32)
	camera_feedback.add_impulse(Vector2(0.025, -0.035))
	screen_fx.flash_hit(0.22)
	time_effects.request_hitstop(0.085)
