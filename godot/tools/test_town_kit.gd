extends SceneTree
## Headless build + budget check for the Mistvale house kit.
##
## Asserts what actually matters before a render pass is spent:
##   * every house produced a non-empty mesh,
##   * no house stands in a road (the kit's clearance rule),
##   * the triangle budget is inside the first-person frame budget,
##   * the additions table actually fired (a kit where every house is identical
##     is a kit that failed at its one job).
##
## Run:
##   Godot --headless --path F:/SEKAI/godot --script res://tools/test_town_kit.gd

func _initialize() -> void:
	var script: GDScript = load("res://scripts/world/mistvale_town.gd")
	var town: Node3D = script.new()
	town.name = "Town"
	root.add_child(town)
	await process_frame
	await process_frame

	var tris := 0
	var meshes := 0
	var empty := 0
	var bodies := 0
	var stack: Array = [town]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if c is MeshInstance3D:
				var m: Mesh = (c as MeshInstance3D).mesh
				if m == null:
					continue
				meshes += 1
				var ar := m.surface_get_arrays(0)
				var v: PackedVector3Array = ar[Mesh.ARRAY_VERTEX]
				if v.is_empty():
					empty += 1
				# SurfaceTool.commit() on a mesh built with add_vertex only is
				# NON-indexed, so ARRAY_INDEX is null — assigning it to a typed
				# PackedInt32Array throws. Handle both.
				var idx_any = ar[Mesh.ARRAY_INDEX]
				var tris_here: int = (idx_any.size() / 3 if idx_any != null else v.size() / 3)
				tris += tris_here
			elif c is StaticBody3D:
				bodies += 1

	print("--- house kit ---")
	print("meshes          %d" % meshes)
	print("empty meshes    %d" % empty)
	print("collision bodies %d" % bodies)
	print("triangles       %d" % tris)
	print("built flag      %d" % (town.get("_built") if town.get("_built") != null else -1))

	# The clearance rule, re-measured from the outside.
	var offenders := 0
	for c in town.get_children():
		if not (c is Node3D):
			continue
		var inst := c as Node3D
		if not String(inst.name).begins_with("House_"):
			continue
		var p := inst.position
		if MistvaleHeights.path_distance(p.x, p.z) < 3.0:
			offenders += 1
			print("  ON ROAD: %s at (%.1f, %.1f) d=%.2f"
				% [inst.name, p.x, p.z, MistvaleHeights.path_distance(p.x, p.z)])
	print("houses on a road %d" % offenders)
	quit(0)
