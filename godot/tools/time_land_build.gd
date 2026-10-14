extends SceneTree
## Fast headless check for the LEVEL ART PASS 02 land layer.
##
## Catches the failures that would otherwise show up as a mysterious black or
## flat region render: a shader that does not compile, a field function that
## recurses, or a build slow enough that the editor feels broken.
##
## Run:
##   Godot --headless --path F:/SEKAI/godot --script res://tools/time_land_build.gd

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()

	# --- field ---------------------------------------------------------------
	var probe := [
		Vector2(0.0, 0.0), Vector2(200.0, 320.0), Vector2(10.0, 122.0),
		Vector2(0.0, -135.0), Vector2(-30.0, -410.0), Vector2(-200.0, 130.0),
	]
	print("--- field ---")
	for p in probe:
		var y := MistvaleHeights.height_at(p.x, p.y)
		var sl := MistvaleHeights.slope_deg(p.x, p.y)
		var pf := MistvaleHeights.path_factor(p.x, p.y)
		var sf := MistvaleHeights.settlement_factor(p.x, p.y)
		var vv := MistvaleHeights.variation(p.x, p.y)
		print("  (%7.1f,%7.1f)  y=%7.2f  slope=%5.1f  path=%.3f  town=%.3f  vary=%.3f"
			% [p.x, p.y, y, sl, pf, sf, vv])
	var t1 := Time.get_ticks_msec()
	print("  field ready in %d ms" % (t1 - t0))

	# --- shader --------------------------------------------------------------
	print("--- shader ---")
	var sh := load("res://resources/shaders/mistvale_terrain.gdshader") as Shader
	if sh == null:
		print("  FAIL: terrain shader did not load")
	else:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		print("  terrain shader loaded, uniforms=%d" % sh.get_shader_uniform_list().size())

	var wsh := load("res://resources/shaders/mistvale_water.gdshader") as Shader
	if wsh == null:
		print("  NOTE: water shader not present yet")
	else:
		print("  water shader loaded, uniforms=%d" % wsh.get_shader_uniform_list().size())

	# --- terrain mesh --------------------------------------------------------
	print("--- terrain mesh ---")
	var t2 := Time.get_ticks_msec()
	var mesh: ArrayMesh = MistvaleTerrain._build_mesh(MistvaleTerrain.STEP, true)
	var t3 := Time.get_ticks_msec()
	if mesh == null or mesh.get_surface_count() == 0:
		print("  FAIL: no surface")
	else:
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		print("  verts=%d tris=%d  built in %d ms" % [verts.size(), idx.size() / 3, t3 - t2])
		# The masks must actually be populated, or the ground loses its road
		# wear and settlement paving and silently looks like plain grass.
		var sum := Vector2.ZERO
		var mx := Vector2.ZERO
		for c in cols:
			sum += Vector2(c.r, c.g)
			mx.x = maxf(mx.x, c.r)
			mx.y = maxf(mx.y, c.g)
		print("  wear: mean=%.4f max=%.3f | town: mean=%.4f max=%.3f"
			% [sum.x / cols.size(), mx.x, sum.y / cols.size(), mx.y])
		if mx.x <= 0.0:
			print("  FAIL: no road wear painted")
		if mx.y <= 0.0:
			print("  FAIL: no settlement painted")

	print("total %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)
