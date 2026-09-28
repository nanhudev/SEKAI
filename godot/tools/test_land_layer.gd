extends SceneTree
## Headless smoke test for the LEVEL ART PASS 02 land layer.
##
## Builds MistvaleLand without a window and reports the structure, the planned
## bridges and the mesh budgets. This is the check that catches "the road is
## invisible" / "the bridge spans the wrong place" before spending a render pass
## on it — a build with no window still runs every line of builder code.
##
## Run:
##   Godot --headless --path F:/SEKAI/godot --script res://tools/test_land_layer.gd

var _land: Node3D
var _t0: int


func _initialize() -> void:
	# NOTE: the build and the dump happen in _process(), not here. During
	# _initialize() the tree root is not ready yet, so a node added here has not
	# had _ready() called and the dump walks an empty shell. Measured the hard
	# way: the first version of this tool printed a root with no children while
	# the builder's own prints appeared afterwards on the same run.
	_t0 = Time.get_ticks_msec()

	# Loaded by path, not by class_name: a newly declared class_name is not in
	# .godot/global_script_class_cache.cfg until the editor has reimported, and
	# running the editor to regenerate it collides with the other live sessions.
	var script: GDScript = load("res://scripts/world/mistvale_land.gd")
	if script == null:
		print("FAIL: cannot load mistvale_land.gd")
		quit(1)
		return
	_land = script.new()
	if _land == null:
		print("FAIL: cannot instantiate MistvaleLand")
		quit(1)
		return
	_land.name = "Land"
	get_root().add_child(_land)


func _process(_delta: float) -> bool:
	print("--- built in %d ms ---" % (Time.get_ticks_msec() - _t0))
	_dump(_land, 0)
	print("total %d ms" % (Time.get_ticks_msec() - _t0))
	quit(0)
	return true


func _dump(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var m := mi.mesh
		if m != null and m.get_surface_count() > 0:
			var ar := m.surface_get_arrays(0)
			var v: PackedVector3Array = ar[Mesh.ARRAY_VERTEX]
			var ix: PackedInt32Array = ar[Mesh.ARRAY_INDEX]
			print("%s%s  [%s] verts=%d tris=%d" % [pad, mi.name,
				"" if mi.material_override == null else mi.material_override.get_class(),
				v.size(), ix.size() / 3])
		else:
			print("%s%s  [empty mesh]" % [pad, mi.name])
	elif node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		print("%s%s  [multimesh instances=%d]" % [pad, mmi.name, mmi.multimesh.instance_count])
	elif node is StaticBody3D:
		print("%s%s  [collision shapes=%d]" % [pad, node.name, node.get_child_count()])
	else:
		print("%s%s" % [pad, node.name])
	for c in node.get_children():
		_dump(c, depth + 1)
