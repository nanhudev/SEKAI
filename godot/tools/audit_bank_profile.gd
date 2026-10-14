extends SceneTree

func _initialize() -> void:
	for x in [-30.0, 0.0, 30.0]:
		var center := MistvaleHeights.river_center_z(x)
		for side in [-1.0, 1.0]:
			var samples: Array[String] = []
			for offset in [13.0, 16.0, 20.0, 24.0, 30.0, 36.0]:
				var z: float = center + side * offset
				samples.append("%.0fm:%.2fy/%.1froad" % [offset,
					MistvaleHeights.height_at(x, z), MistvaleHeights.path_distance(x, z)])
			print("BANK x=%.0f side=%+.0f %s" % [x, side, ", ".join(samples)])
	quit()
