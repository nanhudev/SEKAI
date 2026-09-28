extends SceneTree
## Headless build smoke test for the whole MistvaleRegion scene.
##
## Catches the class of failure that a render pass wastes five minutes on:
## a builder that throws, a shader that will not compile, a mesh that comes back
## null. A build with no window still runs every line of builder code.
##
## Run:
##   Godot --headless --path F:/SEKAI/godot --script res://tools/build_smoke.gd

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var packed: PackedScene = load("res://scenes/world/MistvaleRegion.tscn")
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	print("--- built in %d ms ---" % (Time.get_ticks_msec() - t0))
	_dump(scene, 0)
	print("total %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)


func _dump(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var line := pad + String(node.name)
	if node is MultiMeshInstance3D:
		line += "  [multimesh %d]" % (node as MultiMeshInstance3D).multimesh.instance_count
	elif node is MeshInstance3D:
		var m := (node as MeshInstance3D).mesh
		if m == null:
			line += "  [NO MESH]"
		elif m.get_surface_count() == 0:
			line += "  [EMPTY]"
		else:
			var ar := m.surface_get_arrays(0)
			var v: PackedVector3Array = ar[Mesh.ARRAY_VERTEX]
			# ARRAY_INDEX is null on a non-indexed mesh (SurfaceTool.commit()
			# with add_vertex only). Assigning null to a typed PackedInt32Array
			# throws and aborts the dump, hiding every node after it.
			var idx_any = ar[Mesh.ARRAY_INDEX]
			var tris: int = (idx_any.size() / 3 if idx_any != null else v.size() / 3)
			line += "  verts=%d tris=%d" % [v.size(), tris]
	elif node is StaticBody3D:
		line += "  [shapes=%d]" % node.get_child_count()
	print(line)
	for c in node.get_children():
		_dump(c, depth + 1)
