extends Node3D
# TEMP combat visual. Replace with the approved Chat2Blender sword asset later.

@onready var combat: CombatController = get_node("../../../../../../CombatController")
@onready var player: CharacterBody3D = combat.get_parent()
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var iaido: IaidoDirector = player.get_parent().get_node("IaidoDirector")
var click_flash: MeshInstance3D

const IDLE_POSITION := Vector3(0.55, -0.52, -0.95)
const IDLE_ROTATION := Vector3(0.0, 0.0, -0.2)


func _ready() -> void:
	position = IDLE_POSITION
	rotation = IDLE_ROTATION
	_add_part("TEMP Grip", Vector3(0.10, 0.28, 0.10), Vector3(0, -0.18, 0), Color(0.16, 0.12, 0.09))
	_add_part("TEMP Guard", Vector3(0.36, 0.07, 0.11), Vector3(0, 0.01, 0), Color(0.72, 0.62, 0.35))
	_add_part("TEMP Blade", Vector3(0.09, 0.95, 0.045), Vector3(0, 0.52, 0), Color(0.84, 0.92, 1.0))
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.045
	flash_mesh.height = 0.09
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(1.0, 0.98, 0.86)
	click_flash = MeshInstance3D.new()
	click_flash.name = "Iaido Hilt Click"
	click_flash.mesh = flash_mesh
	click_flash.material_override = flash_material
	click_flash.position = Vector3(0.0, 0.02, 0.05)
	click_flash.visible = false
	add_child(click_flash)


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
	click_flash.visible = combat.state == CombatController.State.IAIDO and combat.state_time >= iaido.tuning.first_click and combat.state_time < iaido.tuning.first_click + 0.035
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
		CombatController.State.DODGE:
			var side := combat.dodge_direction.dot(player.global_basis.x)
			target_position = IDLE_POSITION + Vector3(-side * 0.16, -0.12, 0.1)
			target_rotation = Vector3(-0.2, 0.0, -0.2 - side * 0.25)
		CombatController.State.BLOCK:
			target_position = Vector3(0.22, -0.23, -0.75)
			target_rotation = Vector3(-0.25, 0.0, 0.45)
		CombatController.State.IAIDO:
			var t := combat.state_time
			var timing := iaido.tuning
			var sheath := Vector3(-0.24, -0.71, -0.80)
			var sheath_rotation := Vector3(-0.36, 0.0, -0.55)
			var drawn := Vector3(0.27, -0.24, -0.70)
			var drawn_rotation := Vector3(-0.91, 0.08, 0.73)
			if t < timing.focus_end:
				var entry := smoothstep(timing.focus_start, timing.focus_end, t)
				target_position = IDLE_POSITION.lerp(sheath, entry)
				target_rotation = IDLE_ROTATION.lerp(sheath_rotation, entry)
			elif t < timing.hold_end:
				target_position = sheath
				target_rotation = sheath_rotation
			elif t < timing.draw_slow_end:
				var release := smoothstep(timing.hold_end, timing.draw_slow_end, t)
				target_position = sheath.lerp(Vector3(-0.13, -0.63, -0.78), release)
				target_rotation = sheath_rotation.lerp(Vector3(-0.43, 0.0, -0.30), release)
			elif t < timing.draw_end:
				var sweep := smoothstep(timing.draw_slow_end, timing.draw_fast_end, t)
				target_position = Vector3(-0.13, -0.63, -0.78).lerp(drawn, sweep)
				target_rotation = Vector3(-0.43, 0.0, -0.30).lerp(drawn_rotation, sweep)
			elif t < timing.glass_end:
				target_position = drawn
				target_rotation = drawn_rotation
			elif t < timing.recovery_end:
				var recovery := smoothstep(timing.glass_end, timing.recovery_end, t)
				target_position = drawn.lerp(sheath, recovery)
				target_rotation = drawn_rotation.lerp(Vector3(-0.35, 0.24 * sin(recovery * PI), -0.55), recovery)
			else:
				target_position = sheath
				target_rotation = sheath_rotation
	if combat.state == CombatController.State.IDLE:
		target_position.x -= camera_feedback.look_lag.x * 0.3
		target_position.y += camera_feedback.look_lag.y * 0.22
	if Input.is_action_pressed("sprint") and player.velocity.length() > 2.0:
		target_position.y -= 0.13
		target_rotation.z -= 0.12
	var response := 48.0 if combat.state == CombatController.State.IAIDO and combat.state_time >= iaido.tuning.draw_slow_end and combat.state_time < iaido.tuning.draw_end else 10.0
	position = position.lerp(target_position, minf(1.0, delta * response))
	rotation = rotation.lerp(target_rotation, minf(1.0, delta * response * 1.5))
