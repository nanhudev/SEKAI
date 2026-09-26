extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var sandbox: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	var world: Node3D = sandbox.instantiate()
	root.add_child(world)
	var player: CharacterBody3D = world.get_node("Player")
	var dummy: Node3D = world.get_node("TechnicalDummy")
	var combat: CombatController = player.get_node("CombatController")
	var enemy_hitbox: CombatHitbox = dummy.get_node("AttackHitbox")
	player.global_position = Vector3(0, 1.15, -0.6)
	await physics_frame
	await physics_frame
	combat.set_state(CombatController.State.BLOCK)
	enemy_hitbox.set_active(true)
	await physics_frame
	await physics_frame
	if combat.perfect_guard_count != 1:
		push_error("Expected one perfect guard, got %s" % combat.perfect_guard_count)
		quit(1)
		return
	if dummy.state != dummy.State.STAGGER:
		push_error("Enemy did not stagger after perfect guard")
		quit(1)
		return
	print("PASS: Area3D enemy hit triggers perfect guard and stagger")
	quit(0)
