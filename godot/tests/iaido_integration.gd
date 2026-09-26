extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	var world: Node3D = scene.instantiate()
	root.add_child(world)
	var player: CharacterBody3D = world.get_node("Player")
	var dummy: Node3D = world.get_node("TechnicalDummy")
	var combat: CombatController = player.get_node("CombatController")
	player.global_position = Vector3(0, 1.15, 0.0)
	await physics_frame
	await physics_frame
	var start: Vector3 = player.global_position
	if not combat.request(&"iaido"):
		push_error("Iaido request was rejected")
		quit(1)
		return
	for i in 190:
		await physics_frame
	if player.global_position.distance_to(start) < 1.5:
		push_error("Iaido did not perform a real forward step")
		quit(1)
		return
	if dummy.health >= dummy.max_health:
		push_error("Iaido active-frame Area3D did not hit dummy")
		quit(1)
		return
	if combat.state != CombatController.State.IDLE or Engine.time_scale != 1.0:
		push_error("Iaido did not restore combat and time state")
		quit(1)
		return
	print("PASS: Iaido step, active-frame hit, delayed damage and state restoration")
	quit(0)
