extends Node
class_name CameraFeedbackController

enum Preset { NORMAL, EXAGGERATED, OFF }

@export var base_fov := 75.0
@export var settle_speed := 9.0
@export var trauma_decay := 1.8

@onready var motion_pivot: Node3D = get_parent().get_node("CameraRig/LookPivot/MotionPivot")
@onready var shake_pivot: Node3D = get_parent().get_node("CameraRig/LookPivot/MotionPivot/ShakePivot")
@onready var camera: Camera3D = get_parent().get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D")

var impulse := Vector2.ZERO
var trauma := 0.0
var fov_offset := 0.0
var fov_hold := 0.0
var roll := 0.0
var noise_time := 0.0
var preset := Preset.NORMAL


func cycle_preset() -> String:
	preset = (preset + 1) % 3
	return preset_name()


func preset_name() -> String:
	match preset:
		Preset.EXAGGERATED: return "Exaggerated"
		Preset.OFF: return "Off"
		_: return "Normal"


func add_impulse(direction: Vector2, strength: float = 1.0) -> void:
	impulse += direction * strength


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func fov_kick(degrees: float) -> void:
	fov_offset += degrees


func roll_impulse(degrees: float) -> void:
	roll += deg_to_rad(degrees)


func landing_impulse(strength: float = 1.0) -> void:
	add_impulse(Vector2(0.0, 0.035), strength)
	add_trauma(0.08 * strength)


func _process(delta: float) -> void:
	noise_time += delta * 27.0
	var decay := minf(1.0, settle_speed * delta)
	impulse = impulse.lerp(Vector2.ZERO, decay)
	fov_offset = lerpf(fov_offset, 0.0, decay)
	roll = lerpf(roll, 0.0, decay)
	trauma = maxf(0.0, trauma - trauma_decay * delta)
	var feedback_scale := 3.0 if preset == Preset.EXAGGERATED else (0.0 if preset == Preset.OFF else 1.0)
	motion_pivot.rotation = Vector3(impulse.y, impulse.x, roll) * feedback_scale
	var shake := trauma * trauma * 0.018
	shake_pivot.position = Vector3(sin(noise_time * 1.7), cos(noise_time * 2.1), 0.0) * shake * feedback_scale
	camera.fov = base_fov + (fov_hold + fov_offset) * feedback_scale
