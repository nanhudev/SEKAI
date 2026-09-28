extends SceneTree
## Depth profile along every forded road — where the water actually is, how deep
## it actually gets, and where the derived shoal landed.
##
## Run:
##   Godot --headless --path F:/SEKAI/godot --script res://tools/probe_fords.gd

func _initialize() -> void:
	print("--- derived ford sites ---")
	for s in MistvaleHeights.ford_sites():
		print("  (%7.2f, %7.2f)  radius %.0f" % [s[0], s[1], s[2]])
	print("")
	for ri in MistvaleHeights.FORDED_ROADS:
		var pts: Array = MistvaleHeights.ROADS[ri][0]
		var total := MistvaleHeights.route_length(pts)
		print("--- road %d  length %.1f m ---" % [ri, total])
		var d := 0.0
		var worst := 0.0
		var worst_d := 0.0
		while d <= total:
			var p := MistvaleHeights.route_at(pts, d)
			var dep := MistvaleHeights.water_depth(p.x, p.y)
			var centre := MistvaleHeights.river_center_z(p.x)
			if dep > worst:
				worst = dep
				worst_d = d
			if absf(p.y - centre) < 16.0:
				print("  d=%5.1f  (%7.2f,%7.2f)  centre z=%6.2f  offset=%6.2f  depth=%6.3f"
					% [d, p.x, p.y, centre, p.y - centre, dep])
			d += 2.0
		print("  WORST depth %.3f m at d=%.1f" % [worst, worst_d])
		print("")
	quit(0)
