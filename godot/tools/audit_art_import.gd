extends SceneTree
## ART IMPORT AUDIT.
##
## WHAT THIS IS FOR (brief §5, §26)
## The manifest used to say "GLB copied" and call it Integrated. A copied file is
## a file. This tool measures what is actually inside the project, from the
## engine's own importer: live AABB in metres, triangle count, and the material
## names that survived the import. Nothing in the manifest is quoted from memory
## once this has run.
##
## It also instantiate-tests the training ground, because a scene that fails to
## load is the one failure mode a file listing cannot see.
##
## Run (redirect stdout to a file - print() is block buffered and is otherwise
## lost when piped, which makes a working run look like a hang):
##
##   G:/Godot/Godot_v4.4.1-stable_win64_console.exe --headless --path F:/SEKAI/godot \
##     --script res://tools/audit_art_import.gd > F:/SEKAI/assets_source/review/art_import_audit.txt 2>&1

const OUT := "F:/SEKAI/assets_source/review/art_import_audit.txt"
const SCAN_ROOT := "res://models"
const SCENES_TO_TEST := [
	"res://scenes/training/TrainingGround.tscn",
	"res://scenes/weapons/Sword_FP.tscn",
	"res://scenes/world/MistvaleRegion.tscn",
]

var _lines := PackedStringArray()
var _glb_count := 0
var _failures := 0


func _initialize() -> void:
	# Deliberately empty. SceneTree._initialize() runs BEFORE _ready() is
	# delivered to nodes added during it, so a builder-based scene is still empty
	# at this point. Inspecting here made the audit report "builder did not run"
	# for scenes whose builders were fine - the instrument was wrong, not the
	# scene. The work happens on the first frame instead.
	pass


func _process(_delta: float) -> bool:
	run()
	return true


func run() -> void:
	_say("SEKAI ART IMPORT AUDIT")
	_say("engine: %s" % Engine.get_version_info().get("string", "?"))
	_say("")

	_say("== PART 1: every GLB in the project, measured by the importer ==")
	_say("%-46s %10s %10s %10s %10s %6s  %s" % ["asset", "X(m)", "Y(m)", "Z(m)", "tris", "mats", "materials"])
	_scan(SCAN_ROOT)
	_say("")
	_say("GLB files measured: %d" % _glb_count)
	_say("")

	_say("== PART 2: scene instantiation test ==")
	for path in SCENES_TO_TEST:
		_test_scene(path)
	_say("")
	_say("Failures: %d" % _failures)

	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	_say("")
	_say("written: %s" % OUT)


func _say(text: String) -> void:
	_lines.append(text)
	print(text)


# ------------------------------------------------------------------------------

func _scan(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_say("  ! cannot open %s" % dir_path)
		return
	for sub in dir.get_directories():
		_scan(dir_path.path_join(sub))
	for file_name in dir.get_files():
		if not file_name.ends_with(".glb"):
			continue
		_measure(dir_path.path_join(file_name))


func _measure(res_path: String) -> void:
	var packed: PackedScene = load(res_path)
	if packed == null:
		_say("%-46s  FAILED TO LOAD" % res_path.get_file())
		_failures += 1
		return

	var inst: Node3D = packed.instantiate()
	# AABB and tri counts are only meaningful once the node is parented, because
	# get_global_transform() has to walk a parent chain that a free node has not.
	root.add_child(inst)

	var box := AABB()
	var first := true
	var tris := 0
	var mats := {}
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var local := mi.mesh.get_aabb()
		var world := mi.global_transform * local
		if first:
			box = world
			first = false
		else:
			box = box.merge(world)
		tris += mi.mesh.get_faces().size() / 3
		for si in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(si)
			if mat != null:
				mats[mat.resource_name if mat.resource_name != "" else mat.get_class()] = true

	var names := PackedStringArray(mats.keys())
	names.sort()
	_say("%-46s %10.3f %10.3f %10.3f %10d %6d  %s" % [
		res_path.get_file(), box.size.x, box.size.y, box.size.z, tris, names.size(),
		", ".join(names) if names.size() > 0 else "(none)",
	])

	if names.size() == 0:
		_say("    ! no material survived the import - this will render untextured")

	_glb_count += 1
	root.remove_child(inst)
	inst.free()


func _test_scene(res_path: String) -> void:
	if not ResourceLoader.exists(res_path):
		_say("  MISSING  %s" % res_path)
		_failures += 1
		return
	var packed: PackedScene = load(res_path)
	if packed == null:
		_say("  PARSE FAILED  %s" % res_path)
		_failures += 1
		return
	var inst := packed.instantiate()
	if inst == null:
		_say("  INSTANTIATE FAILED  %s" % res_path)
		_failures += 1
		return
	root.add_child(inst)
	# Builders run in _ready(), which fires on add_child, so the node tree is
	# whole by here.
	var meshes := inst.find_children("*", "MeshInstance3D", true, false).size()
	var nodes := _count(inst)
	_say("  OK  %-44s nodes=%d meshes=%d" % [res_path.get_file(), nodes, meshes])
	if meshes == 0:
		_say("      ! scene instantiated but produced no meshes - a builder probably did not run")
	root.remove_child(inst)
	inst.free()


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total
