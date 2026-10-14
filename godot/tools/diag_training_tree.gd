extends SceneTree
## Diagnostic: why did the training ground produce no meshes?
##
## Run:
##   G:/Godot/Godot_v4.4.1-stable_win64_console.exe --headless --path F:/SEKAI/godot \
##     --script res://tools/diag_training_tree.gd > F:/SEKAI/assets_source/review/diag_training.txt 2>&1

const SCENE := "res://scenes/training/TrainingGround.tscn"
const OUT := "F:/SEKAI/assets_source/review/diag_training.txt"

var _lines := PackedStringArray()


func _initialize() -> void:
	# See audit_art_import.gd: _initialize() runs before _ready(), so everything
	# that depends on a builder having run has to happen on the first frame.
	pass


func _process(_delta: float) -> bool:
	run()
	return true


func run() -> void:
	var packed: PackedScene = load(SCENE)
	_say("loaded: %s" % str(packed != null))
	if packed == null:
		flush()
		quit(1)
		return

	var inst := packed.instantiate()
	_say("instantiated: %s" % str(inst != null))
	root.add_child(inst)

	var ground := inst.get_node_or_null("Ground")
	_say("Ground node: %s" % str(ground))
	if ground != null:
		_say("Ground script: %s" % str(ground.get_script()))
		_say("Ground class: %s" % ground.get_class())
		_say("Ground is_tool: %s" % str(ground.is_processing()))
		_say("Ground child count: %d" % ground.get_child_count())

	# Does the script itself even compile and expose what we expect?
	var script: GDScript = load("res://scripts/training/training_ground.gd")
	_say("script loaded: %s" % str(script != null))
	if script != null:
		_say("can_instantiate: %s" % str(script.can_instantiate()))
		_say("has _build: %s  has zones: %s" % [
			str(script.has_method("_build")), str(script.has_method("zones"))])

	var tb: GDScript = load("res://scripts/training/training_build.gd")
	_say("training_build loaded: %s" % str(tb != null))
	if tb != null:
		_say("training_build has slab: %s" % str(tb.has_method("slab")))

	_say("")
	_say("--- tree (depth <= 3) ---")
	_dump(inst, 0, 3)

	_say("")
	_say("mesh count (deep): %d" % inst.find_children("*", "MeshInstance3D", true, false).size())

	flush()
	quit(0)


func _dump(node: Node, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		return
	_say("%s%s (%s)" % ["  ".repeat(depth), node.name, node.get_class()])
	if depth == max_depth:
		return
	for child in node.get_children():
		_dump(child, depth + 1, max_depth)


func _say(t: String) -> void:
	_lines.append(t)
	print(t)


func flush() -> void:
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
