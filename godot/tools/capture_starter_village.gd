extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var world := (load("res://scenes/world/StarterVillagePlayable.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for frame in 35:await physics_frame
	assert(world.ready_for_exploration)
	world.get_node("Player").set_physics_process(false)
	world.get_node("Player").visible = false
	world.get_node("CombatHUD").visible = false
	world.get_node("ForegroundWeaponLayer").visible = false
	var camera := Camera3D.new();camera.fov = 67.0;world.add_child(camera);camera.make_current()
	var folder: String = "E:/SEKAI_Environment_Runtime/GodotReview/"+world.MAP_ROOT.trim_suffix("/").get_file()
	DirAccess.make_dir_recursive_absolute(folder)
	var views := [
		["entrance", Vector3(-58,3.7,93),Vector3(-44,5.0,43)],
		["houses",Vector3(22,10.3,-3),Vector3(38,12.0,-15)],
		["bridge_left",Vector3(-50,4.8,60),Vector3(-46,3.2,44)],
		["bridge_water",Vector3(-41,3.8,59),Vector3(-40,1.4,32)]
	]
	for row in views:
		camera.global_position=row[1];camera.look_at(row[2])
		for frame in 15:await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(folder+"/"+row[0]+".png") == OK)
	# Only the water clock changes between these captures. This isolates the
	# effect from camera, sky, player and world motion.
	world.set_process(false)
	for index in 4:
		for mat in world.water_materials:mat.set_shader_parameter("flow_time", float(index)*0.8)
		for frame in 8:await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(folder+"/water_%02d.png"%index) == OK)
	print("STARTER_NATIVE_CAPTURES_COMPLETE")
	world.process_mode=Node.PROCESS_MODE_DISABLED
	for frame in 3:await physics_frame
	quit()
