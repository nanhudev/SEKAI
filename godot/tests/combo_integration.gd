extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _wait_frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	var world: Node3D = scene.instantiate()
	root.add_child(world)
	var player: CharacterBody3D = world.get_node("Player")
	var combat: CombatController = player.get_node("CombatController")
	await _wait_frames(2)
	combat.request(&"light")
	await _wait_frames(18)
	combat.request(&"light")
	await _wait_frames(12)
	if combat.combo_index != 2:
		push_error("Buffered second light attack did not start; index=%s" % combat.combo_index)
		quit(1)
		return
	await _wait_frames(10)
	combat.request(&"light")
	await _wait_frames(15)
	if combat.combo_index != 3:
		push_error("Third light attack did not start; index=%s" % combat.combo_index)
		quit(1)
		return
	print("PASS: buffered three-hit sword combo")
	quit(0)
