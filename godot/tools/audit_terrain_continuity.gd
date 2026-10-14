extends SceneTree
## Checks the gameplay field and the bridge reach's separate visual terrain.

func _initialize() -> void:
	var step := MistvaleTerrain.STEP
	var max_error := 0.0
	var max_at := Vector2.ZERO
	var over_half := 0
	var samples := 0
	var zone_worst := {}
	for iz in range(0, int((MistvaleHeights.MAX_Z - MistvaleHeights.MIN_Z) / step), 3):
		for ix in range(0, int((MistvaleHeights.MAX_X - MistvaleHeights.MIN_X) / step), 3):
			var x: float = MistvaleHeights.MIN_X + float(ix) * step + step * 0.5
			var z: float = MistvaleHeights.MIN_Z + float(iz) * step + step * 0.5
			var b := MistvaleHeights.height_at(x + step * 0.5, z - step * 0.5)
			var c := MistvaleHeights.height_at(x - step * 0.5, z + step * 0.5)
			var visual := (b + c) * 0.5
			var exact := MistvaleHeights.height_at(x, z)
			var err := absf(visual - exact)
			var zone := "forest" if z > 95.0 else ("town" if z > -140.0 else "mountain")
			zone_worst[zone] = maxf(float(zone_worst.get(zone, 0.0)), err)
			if err > max_error:
				max_error = err
				max_at = Vector2(x, z)
			if err > 0.5:
				over_half += 1
			samples += 1
	print("terrain %.1f m interpolation: max %.3f m at %v, >0.5 m %d/%d, zones=%s" % [step, max_error, max_at, over_half, samples, zone_worst])
	var worst_road := 0.0
	var worst_road_at := Vector2.ZERO
	for road in MistvaleHeights.ROADS:
		var pts: Array = road[0]
		var total := MistvaleHeights.route_length(pts)
		var t := 0.0
		while t + 2.0 <= total:
			var p := MistvaleHeights.route_at(pts, t)
			var q := MistvaleHeights.route_at(pts, t + 2.0)
			var rise := absf(MistvaleHeights.height_at(q.x, q.y) - MistvaleHeights.height_at(p.x, p.y))
			var slope := rad_to_deg(atan2(rise, 2.0))
			if slope > worst_road:
				worst_road = slope
				worst_road_at = p
			t += 2.0
	print("road grade: worst %.1f deg at %v" % [worst_road, worst_road_at])
	var slice := MistvaleTerrain._build_visual_slice()
	var slice_vertices: PackedVector3Array = slice.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var visual_delta := 0.0
	var seam_delta := 0.0
	for v in slice_vertices:
		var delta := absf(v.y - MistvaleHeights.height_at(v.x, v.z))
		visual_delta = maxf(visual_delta, delta)
		if is_equal_approx(v.x, MistvaleTerrain.SLICE_X.x) \
				or is_equal_approx(v.x, MistvaleTerrain.SLICE_X.y) \
				or is_equal_approx(v.z, MistvaleTerrain.SLICE_Z.x) \
				or is_equal_approx(v.z, MistvaleTerrain.SLICE_Z.y):
			seam_delta = maxf(seam_delta, delta)
	print("visual slice: %d vertices, maximum gameplay delta %.3f m, seam %.3f m"
		% [slice_vertices.size(), visual_delta, seam_delta])
	if max_error > 0.4 or over_half > 0 or visual_delta > 0.35 or seam_delta > 0.02:
		push_error("terrain continuity regression")
		quit(1)
	else:
		print("PASS: visual terrain follows the field within 0.4 m")
		quit(0)
