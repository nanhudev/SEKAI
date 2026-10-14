extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := (load("res://scenes/world/StarterVillagePlayable.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 35:await physics_frame
	assert(world.ready_for_exploration)
	assert(world.water_materials.size() >= 2, "Water surfaces not bound")
	var player := world.get_node("Player") as CharacterBody3D
	assert(player.is_on_floor(), "Player is not grounded at entrance")
	var samples: Array = []
	for i in world.route.size():
		var p := Vector3(world.route[i][0], world.route[i][1], world.route[i][2])
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p - Vector3.UP * 5.0))
		assert(not hit.is_empty(), "Missing route collision " + str(i))
		assert(absf(hit["position"].y - p.y) < 2.0, "Route collider too far from authored surface " + str(i))
		samples.append({"route": i, "height": hit["position"].y, "body": String(hit["collider"].name)})
	var start := player.global_position
	Input.action_press("move_forward")
	for frame in 120:await physics_frame
	Input.action_release("move_forward")
	var travelled := player.global_position.distance_to(start)
	assert(travelled > 2.0, "Player movement did not advance")
	assert(player.is_on_floor(), "Entrance movement left the floor")
	var receipt := {"ready": true, "spawn": [start.x,start.y,start.z], "travelled_m": travelled, "water_materials": world.water_materials.size(), "flow_seconds": world.flow_time, "route_samples": samples, "scope": "Entrance physical movement and route floor rays; full manual traversal and water appearance still required"}
	var f := FileAccess.open("E:/SEKAI_Environment_Runtime/v071_godot_probe.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(receipt,"\t"));f.close()
	player.set_physics_process(false)
	for frame in 3:await physics_frame
	for frame in 3:await process_frame
	current_scene = null
	root.remove_child(world)
	world.free()
	for frame in 3:await physics_frame
	for frame in 3:await process_frame
	print("STARTER_VILLAGE_PROBE_OK ", travelled)
	quit()
