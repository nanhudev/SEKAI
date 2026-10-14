extends SceneTree

# Runs the real region and CharacterBody in a visible Godot window. An external
# keyboard can steer it; frames are saved from the live viewport because the
# host desktop does not expose reliable screen capture.
const OUT := "F:/SEKAI/.render/levelart/veg_v22_final/"

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load("res://scenes/world/MistvaleRegion.tscn") as PackedScene
	var world := scene.instantiate() as Node3D
	root.add_child(world)
	if OS.get_cmdline_user_args().has("--flat-terrain"):
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(0.5, 0.5, 0.5)
		flat.roughness = 1.0
		for child in world.get_node("Terrain").get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).material_override = flat
		print("PERF_DIAG flat terrain shader replacement enabled")
	for i in 60:
		await process_frame
	var walker := world.get_node("ReviewWalker") as CharacterBody3D
	print("LIVE_WINDOW_PID=", OS.get_process_id(), " WALK_START=", walker.global_position)
	if OS.get_cmdline_user_args().has("--measure-only"):
		var started := Time.get_ticks_usec()
		for i in 120:
			await process_frame
		_report(world, 120000000.0 / float(Time.get_ticks_usec() - started))
		quit()
		return
	_capture("visible_00.png")
	await create_timer(12.0).timeout
	print("WALK_12S=", walker.global_position)
	_capture("visible_12.png")
	await create_timer(12.0).timeout
	print("WALK_24S=", walker.global_position)
	_capture("visible_24.png")
	await create_timer(12.0).timeout
	print("WALK_36S=", walker.global_position)
	_capture("visible_36.png")
	await create_timer(12.0).timeout
	print("WALK_48S=", walker.global_position)
	_capture("visible_48.png")
	_report(world)
	quit()


func _report(world: Node3D, sampled_fps: float = -1.0) -> void:
	var instances := 0
	var multi_meshes := 0
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MultiMeshInstance3D:
			multi_meshes += 1
			instances += (node as MultiMeshInstance3D).multimesh.instance_count
		for child in node.get_children():
			stack.append(child)
	print("PERF instances=", instances, " multimsh=", multi_meshes,
		" fps=", Performance.get_monitor(Performance.TIME_FPS),
		" sampled_fps=", snappedf(sampled_fps, 0.1),
		" draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


func _capture(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(OUT + name)
