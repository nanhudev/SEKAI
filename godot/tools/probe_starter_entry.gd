extends SceneTree

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main.start_region()
	for frame in 45:await physics_frame
	var world: Node = main.active_world()
	assert(world != null and world.name == "StarterVillagePlayable")
	assert(world.ready_for_exploration)
	main.pause_game()
	await process_frame
	assert(world.process_mode == Node.PROCESS_MODE_DISABLED)
	main.resume_game()
	await process_frame
	assert(world.process_mode == Node.PROCESS_MODE_PAUSABLE)
	main.return_to_title()
	for frame in 3:await process_frame
	assert(main.active_world() == null)
	root.remove_child(main);main.free()
	for frame in 3:await process_frame
	print("STARTER_MENU_ENTRY_PAUSE_RETURN_OK")
	quit()
