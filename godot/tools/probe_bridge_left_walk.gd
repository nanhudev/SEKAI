extends SceneTree

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main);current_scene=main
	await process_frame
	main.start_region()
	for frame in 35:await physics_frame
	var world: Node=main.active_world()
	assert(world.ready_for_exploration)
	var player := world.get_node("Player") as CharacterBody3D
	player.set_physics_process(false)
	player.global_position=Vector3(-48,3.575,58)
	player.velocity=Vector3.ZERO
	player.set_physics_process(true)
	for frame in 15:await physics_frame
	assert(player.is_on_floor())
	var start := player.global_position
	var samples: Array=[]
	var targets := [Vector3(-46,0,45),Vector3(-40,0,44.357)]
	for target in targets:
		Input.action_press("move_forward")
		var reached := false
		for frame in 420:
			var delta: Vector3=target-player.global_position;delta.y=0
			if delta.length()<0.55:
				reached=true;break
			player.rotation.y=atan2(-delta.x,-delta.z)
			await physics_frame
			if frame%6==0:samples.append({"position":[player.global_position.x,player.global_position.y,player.global_position.z],"grounded":player.is_on_floor()})
		Input.action_release("move_forward")
		assert(reached,"Failed to physically reach bridge target")
	for frame in 15:await physics_frame
	assert(player.is_on_floor())
	assert(player.global_position.y>3.6,"Player ended below the bridge")
	var receipt={"map":world.MAP_ROOT,"start":[start.x,start.y,start.z],"end":[player.global_position.x,player.global_position.y,player.global_position.z],"samples":samples,"scope":"Real Player input and collision movement from the left road onto the bridge; not full route or manual acceptance"}
	var version: String=world.MAP_ROOT.trim_suffix("/").get_file()
	var file:=FileAccess.open("E:/SEKAI_Environment_Runtime/"+version+"_bridge_left_walk.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt,"\t"));file.close()
	player.set_physics_process(false)
	for frame in 3:await physics_frame
	for frame in 3:await process_frame
	main.return_to_title()
	for frame in 3:await physics_frame
	for frame in 3:await process_frame
	assert(main.active_world()==null)
	current_scene=null
	for child in root.get_children():
		root.remove_child(child);child.free()
	for frame in 3:await physics_frame
	for frame in 3:await process_frame
	print("BRIDGE_LEFT_PHYSICAL_WALK_OK")
	quit()
