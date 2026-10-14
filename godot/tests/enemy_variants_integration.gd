extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	var world: Node3D = scene.instantiate()
	root.add_child(world)
	var player: CharacterBody3D = world.get_node("Player")
	var dummy: Node3D = world.get_node("TechnicalDummy")
	player.global_position = Vector3(0, 1.15, -0.5)
	var seen: Array[int] = []
	dummy.attack_started.connect(func(variant: int) -> void: seen.append(variant))
	dummy.attack_cooldown = 0.0
	var start_z: float = dummy.global_position.z
	for i in 390:
		await physics_frame
	if seen.size() < 3 or seen.slice(0, 3) != [0, 1, 2]:
		push_error("Enemy did not cycle sweep, heavy and lunge: %s" % seen)
		quit(1)
		return
	if dummy.global_position.z <= start_z + 0.5:
		push_error("Enemy lunge did not reposition the body")
		quit(1)
		return
	print("PASS: telegraphed sweep, heavy and physical lunge cycle")
	quit(0)
