extends Node3D
# TEMP combat visual. Replace with the approved Chat2Blender sword asset later.

@onready var combat: CombatController = get_node("../../../../../../CombatController")
@onready var player: CharacterBody3D = combat.get_parent()
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")

const IDLE_POSITION := Vector3(0.55, -0.52, -0.95)
const IDLE_ROTATION := Vector3(0.0, 0.0, -0.2)


func _ready() -> void:
	position = IDLE_POSITION
	rotation = IDLE_ROTATION
	_add_part("TEMP Grip", Vector3(0.10, 0.28, 0.10), Vector3(0, -0.18, 0), Color(0.16, 0.12, 0.09))
	_add_part("TEMP Guard", Vector3(0.36, 0.07, 0.11), Vector3(0, 0.01, 0), Color(0.72, 0.62, 0.35))
	_add_part("TEMP Blade", Vector3(0.09, 0.95, 0.045), Vector3(0, 0.52, 0), Color(0.84, 0.92, 1.0))


func _add_part(part_name: String, size: Vector3, offset: Vector3, tint: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	mesh.material = material
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = offset
	add_child(part)


func _process(delta: float) -> void:
	var target_position := IDLE_POSITION
	var target_rotation := IDLE_ROTATION
	match combat.state:
		CombatController.State.ATTACK:
			if combat.attack_kind == &"heavy":
				var progress := clampf(combat.state_time / 0.38, 0.0, 1.0)
				target_rotation = Vector3(-0.45, 0.0, lerpf(-1.0, 0.8, progress))
				target_position = Vector3(0.42, -0.35, -0.8)
			else:
				var progress := clampf(combat.state_time / 0.23, 0.0, 1.0)
				var start_angle := 0.9 if combat.combo_index != 2 else -0.9
				var end_angle := -0.9 if combat.combo_index != 2 else 0.9
				target_rotation = Vector3(0.0, 0.0, lerpf(start_angle, end_angle, progress))
				target_position = Vector3(0.43, -0.37, -0.78)
		CombatController.State.BLOCK:
			target_position = Vector3(0.22, -0.23, -0.75)
			target_rotation = Vector3(-0.25, 0.0, 0.45)
		CombatController.State.IAIDO:
			target_position = Vector3(0.58, -0.65, -0.78)
			target_rotation = Vector3(0.0, 0.0, -1.1 if combat.state_time < 0.35 else 0.65)
	if combat.state == CombatController.State.IDLE:
		target_position.x -= camera_feedback.look_lag.x * 0.3
		target_position.y += camera_feedback.look_lag.y * 0.22
	if Input.is_action_pressed("sprint") and player.velocity.length() > 2.0:
		target_position.y -= 0.13
		target_rotation.z -= 0.12
	position = position.lerp(target_position, minf(1.0, delta * 10.0))
	rotation = rotation.lerp(target_rotation, minf(1.0, delta * 20.0))
