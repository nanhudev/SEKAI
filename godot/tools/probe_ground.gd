extends SceneTree
##
## GROUND PROBE — what does the field actually do under a footprint?
##
## WHY THIS EXISTS: a procedural building is placed by sampling ONE height at its
## centre and standing on it. If the ground under the footprint is not flat, the
## building floats on the high side or buries itself on the low side, and the fix
## is to make the plinth deep enough to swallow the range. That number cannot be
## guessed from the code — the field is the sum of a base surface, a route carve,
## arena flattening and relief — so it gets measured before the plinth is sized.
##
## Usage (headless is fine):
##   godot --path godot --headless --script res://tools/probe_ground.gd \
##         -- --at=12,-58;-26,-95;0,-135 --radius=14

var _pts: Array = []
var _radius := 14.0
var _step := 2.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			for chunk in a.substr(5).split(";"):
				var xy := chunk.split(",")
				if xy.size() == 2:
					_pts.append(Vector2(float(xy[0]), float(xy[1])))
		elif a.begins_with("--radius="):
			_radius = float(a.substr(9))
		elif a.begins_with("--step="):
			_step = float(a.substr(7))

	print("--- GROUND PROBE  radius=", _radius, " ---")
	print("%-18s %8s %8s %8s %8s %8s" % ["point", "centre", "min", "max", "range", "slope"])
	for p in _pts:
		var lo := 1e9
		var hi := -1e9
		var d := -_radius
		while d <= _radius:
			var e := -_radius
			while e <= _radius:
				var h := MistvaleHeights.height_at(p.x + d, p.y + e)
				lo = minf(lo, h)
				hi = maxf(hi, h)
				e += _step
			d += _step
		var c := MistvaleHeights.height_at(p.x, p.y)
		print("%-18s %8.2f %8.2f %8.2f %8.2f %8.1f"
			% ["(%.0f, %.0f)" % [p.x, p.y], c, lo, hi, hi - lo,
			   MistvaleHeights.slope_deg(p.x, p.y)])
	print("--- END ---")
	quit(0)
