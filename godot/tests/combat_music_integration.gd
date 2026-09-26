extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
	var world: Node3D = scene.instantiate()
	root.add_child(world)
	await process_frame
	var music: AudioStreamPlayer = world.get_node("CombatMusic")
	if music.stream == null or not music.playing or AudioServer.get_bus_index("Music") == -1:
		push_error("Existing First Encounter track is not playing on Music bus")
		quit(1)
		return
	music.stop()
	music = null
	world.queue_free()
	await process_frame
	world = null
	scene = null
	await create_timer(0.35, true, false, true).timeout
	print("PASS: existing First Encounter track starts on Music bus")
	quit(0)
