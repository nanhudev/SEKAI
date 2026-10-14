extends SceneTree
## Minimal probe for the render pipeline in this project.
##
## Always redirect stdout to a file: print() is block-buffered and is otherwise
## lost when piped, which makes a working run look like a hang.
##
## Usage: --script res://tools/frame_probe.gd -- [none|sandbox|shader]
##   none     just present frames
##   sandbox  load CombatSandbox first
##   shader   only a ColorRect wearing iaido_world_split.gdshader

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "none"
	print("mode=", mode, " display=", DisplayServer.get_name())
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()

	if mode == "sandbox":
		print("loading CombatSandbox ...")
		var scene: PackedScene = load("res://scenes/combat/CombatSandbox.tscn")
		print("loaded, instantiating ...")
		root.add_child(scene.instantiate())
		print("added")
	elif mode == "shader":
		print("compiling iaido_world_split.gdshader ...")
		var mat := ShaderMaterial.new()
		mat.shader = load("res://vfx/iaido_world_split.gdshader")
		print("shader resource assigned")
		var rect := ColorRect.new()
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.material = mat
		var layer := CanvasLayer.new()
		layer.add_child(rect)
		root.add_child(layer)
		print("rect added; presenting frames")
		mat.set_shader_parameter("resolution", Vector2(640.0, 360.0))
		mat.set_shader_parameter("void_open", 1.0)
		mat.set_shader_parameter("gap_px", 13.0)
		mat.set_shader_parameter("separation_px", 10.0)
		mat.set_shader_parameter("shatter", 0.5)

	var frames := 0
	for i in 10:
		var t0 := Time.get_ticks_msec()
		await process_frame
		await RenderingServer.frame_post_draw
		frames += 1
		print("presented frame %d  (%d ms)" % [frames, Time.get_ticks_msec() - t0])

	var img := root.get_texture().get_image()
	print("readback: ", "NULL" if img == null else str(img.get_size()))
	quit()
