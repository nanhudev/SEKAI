extends "res://scripts/enemies/technical_dummy.gd"
# Reuses the existing telegraphs, three attacks, guard opening and execution.
@export var approach_speed := 2.0
@export var engage_distance := 2.3

func _physics_process(delta: float) -> void:
	if player == null or state not in [State.IDLE, State.ALERT]:
		return
	var toward := player.global_position - global_position
	toward.y = 0.0
	var distance := toward.length()
	if distance < 0.05 or distance > 14.0:
		return
	var direction := toward / distance
	# TechnicalDummy's existing hitbox attacks along +Z.
	look_at(global_position - direction, Vector3.UP)
	if distance <= engage_distance:
		return
	var step := minf(approach_speed * delta, distance - engage_distance)
	var from := global_position + Vector3.UP * 0.8
	var ray := PhysicsRayQueryParameters3D.create(from, from + direction * (step + 0.5), 1, [get_rid(), player.get_rid()])
	if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		global_position += direction * step
		_set_phase(&"approach")
