extends SceneTree
## Dumps the MistvaleHeight analytic field to CSV so review plots can be drawn
## from the SAME field the engine builds, rather than a Python re-implementation
## that would silently drift out of sync.
##
## Run:
##   Godot --headless --path godot --script res://tools/dump_height_field.gd

const STEP := 4.0
## Absolute, not res://../ — FileAccess will not escape the project root.
const OUT := "F:/SEKAI/assets_source/review/height_field.csv"


func _initialize() -> void:
	var nx := int((MistvaleHeights.MAX_X - MistvaleHeights.MIN_X) / STEP) + 1
	var nz := int((MistvaleHeights.MAX_Z - MistvaleHeights.MIN_Z) / STEP) + 1

	var lines := PackedStringArray()
	lines.append("x,z,y")
	for iz in nz:
		var z := MistvaleHeights.MIN_Z + float(iz) * STEP
		for ix in nx:
			var x := MistvaleHeights.MIN_X + float(ix) * STEP
			var y := MistvaleHeights.height_at(x, z)
			lines.append("%.1f,%.1f,%.3f" % [x, z, y])

	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("cannot open %s" % OUT)
		quit(1)
		return
	f.store_string("\n".join(lines))
	f.close()
	print("WROTE %d samples -> %s" % [lines.size() - 1, OUT])
	quit(0)
