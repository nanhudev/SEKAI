extends SceneTree
#
# TOOL · FRAME SAMPLER — a rendered frame as a LUMINANCE MAP, in text.
#
# WHY THIS EXISTS. Reviewing these takes by looking at the PNG keeps producing the
# same class of mistake: a value judgement ("the wall reads the same as the sky", "the
# head is white paper") made by eye, in a conversation, twice. A luminance map turns
# that into a grid of characters that can be compared between two builds — and the
# question "did darkening the wall actually separate it from the sky" becomes a
# question about two rows of text rather than about a memory of a picture.
#
# It prints:
#   · a coarse luminance map of the whole frame (` ` darkest … `@` brightest)
#   · the value at a few named probes, if given as x,y in pixels or as fractions
#
# This is a developer tool, not a test: it asserts nothing and never fails.
#
# Usage:
#   godot --headless --path godot --script res://tools/sample_frame.gd -- \
#       <png path> [cols] [rows]

const RAMP := " .:-=+*#%@"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: --script res://tools/sample_frame.gd -- <png> [cols] [rows]")
		quit()
		return
	var path := args[0]
	var cols := int(args[1]) if args.size() > 1 else 72
	var rows := int(args[2]) if args.size() > 2 else 26

	# `load_from_file` is the STATIC one and hands back an Image (null on failure);
	# the method `load()` only reads `res://` and returns an Error. Mixing them up is a
	# parse error, not a runtime one.
	var img := Image.load_from_file(path)
	if img == null:
		print("!! could not read %s" % path)
		quit()
		return

	var w := img.get_width()
	var h := img.get_height()
	print("")
	print("%s   %d x %d" % [path.get_file(), w, h])
	print("  ` `=0.00  `@`=1.00      ramp \"%s\"" % RAMP)
	print("")

	# The overlay's own band is not the picture; the caller can see it in the map.
	for ry in rows:
		var line := ""
		for rx in cols:
			var x := clampi(int((float(rx) + 0.5) / float(cols) * float(w)), 0, w - 1)
			var y := clampi(int((float(ry) + 0.5) / float(rows) * float(h)), 0, h - 1)
			var lum := img.get_pixel(x, y).get_luminance()
			line += RAMP[clampi(int(lum * float(RAMP.length())), 0, RAMP.length() - 1)]
		print("  " + line)

	print("")
	_band(img, "top    band", 0.02, 0.10)
	_band(img, "upper  band", 0.28, 0.36)
	_band(img, "middle band", 0.48, 0.56)
	_band(img, "lower  band", 0.68, 0.76)
	quit()


# A horizontal strip's mean luminance, so "the wall" and "the sky" can be told apart
# by a number rather than by which one is remembered as lighter.
func _band(img: Image, label: String, top: float, bottom: float) -> void:
	var h := img.get_height()
	var w := img.get_width()
	var total := 0.0
	var n := 0
	for y in range(int(top * h), int(bottom * h)):
		for x in range(0, w, 4):
			total += img.get_pixel(x, y).get_luminance()
			n += 1
	print("  %-13s y %.0f..%.0f%%   mean luminance %.3f"
		% [label, top * 100.0, bottom * 100.0, total / maxf(1.0, float(n))])
