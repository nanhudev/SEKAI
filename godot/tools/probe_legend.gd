extends SceneTree
## Reads the training ground's KEY LEGEND back as numbers, because the review sheet says
## the rows overlap and a picture cannot say WHICH quantity is wrong.
##
## Prints, per Label: the position its container gave it, the size it was given, and the
## minimum height IT ASKED FOR. If `min` exceeds the distance between consecutive
## positions the container overlaps them, and the column is short by exactly the sum of
## those deficits — which is a number somebody can act on.
##
## Needs a REAL WINDOW, for the same reason the renderer does: a headless run has no
## CJK fallback font, so every Chinese row measures as zero-height here and the report
## would describe a layout that never appears on screen.
##
##   G:/Godot/Godot_v4.4.1-stable_win64_console.exe --path F:/SEKAI/godot \
##     --resolution 1600x900 --audio-driver Dummy --script res://tools/probe_legend.gd

const SCENE := "res://scenes/training/TrainingGround.tscn"

var _frame := 0
var _scene: Node3D = null


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var packed: PackedScene = load(SCENE)
		if packed == null:
			print("FAILED to load ", SCENE)
			return true
		_scene = packed.instantiate()
		root.add_child(_scene)
		return false
	if _frame == 8:
		_dump()
		# FREED EXPLICITLY, AND BEFORE THE QUIT. The scene owns a CanvasLayer with a live
		# font and a Label tree; letting the engine tear that down after `_process` returns
		# true is where this tool used to segfault — after the report had printed, so the
		# crash buried the answer it was run for.
		if _scene != null:
			root.remove_child(_scene)
			_scene.free()
			_scene = null
		return true
	return false


func _dump() -> void:
	var legend := _scene.find_child("TrainingLegend", true, false)
	if legend == null:
		print("NO TrainingLegend — every CanvasLayer in the tree:")
		for c in _scene.find_children("*", "CanvasLayer", true, false):
			print("  ", c.name)
		return
	var labels := legend.find_children("*", "Label", true, false)
	print("legend=%s  labels=%d" % [String(legend.name), labels.size()])
	print("%-5s %-8s %-10s %-10s %-8s %-8s %s" % ["#", "y", "size.y", "min.y", "gap", "deficit", "text"])
	var prev_y := 0.0
	var prev_min := 0.0
	var first := true
	var worst := 0.0
	for i in labels.size():
		var lb := labels[i] as Label
		var min_h := lb.get_combined_minimum_size().y
		var y := lb.global_position.y
		var gap := y - prev_y if not first else 0.0
		var deficit := (prev_min - gap) if not first else 0.0
		worst = maxf(worst, deficit)
		print("%-5d %-8.1f %-10.1f %-10.1f %-8.1f %-8.1f %s" % [
			i, y, lb.size.y, min_h, gap, deficit, lb.text])
		prev_y = y
		prev_min = min_h
		first = false
	print("WORST DEFICIT: %.1f px — a positive number means the container is stacking rows "
		% worst + "closer together than the rows say they need.")

	var column: VBoxContainer = null
	for c in legend.find_children("*", "VBoxContainer", true, false):
		column = c as VBoxContainer
		break
	if column != null:
		print("vbox size=%s min=%s separation=%d" % [
			str(column.size), str(column.get_combined_minimum_size()),
			column.get_theme_constant("separation")])
		var p := column.get_parent()
		while p != null and p != legend:
			print("  up: %s(%s) size=%s min=%s" % [
				String(p.name), p.get_class(), str(p.size), str(p.get_combined_minimum_size())])
			p = p.get_parent()

	var font := ThemeDB.fallback_font
	if font != null:
		print("fallback font h(15)=%.1f h(14)=%.1f h(7)=%.1f  cjk_probe='静'" % [
			font.get_height(15), font.get_height(14), font.get_height(7)])
