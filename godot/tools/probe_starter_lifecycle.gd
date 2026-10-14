extends SceneTree

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "res://models/starter_village/v078/" + ("collision.scn" if args[0] == "collision" else "starter_village.glb")
	var world := (load(path) as PackedScene).instantiate()
	root.add_child(world)
	for frame in 4:await physics_frame
	world.queue_free()
	for frame in 4:await physics_frame
	print("MAP_LIFECYCLE_OK ",args[0]);quit()
