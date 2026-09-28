extends SceneTree
##
## NORMAL-ARRAY AUDIT — does a built mesh actually carry normals?
##
## WHY THIS EXISTS: mistvale_town.gd emits its geometry through a SurfaceTool
## with add_vertex() and set_color() and NO set_normal() call. If SurfaceTool
## writes a NORMAL array of zeros in that case, then every triangle of every
## house fails N.L against every light in the scene: the town is lit by ambient
## alone, does not change when the sun moves, and cannot receive a highlight.
## A house that is always ambient-only is exactly what a "flat and gloomy lower
## town" looks like.
##
## This cannot be seen in the code. It can be measured in one run.
##
## Usage (headless is fine, nothing is rendered):
##   godot --path godot --headless --script res://tools/probe_mesh_normals.gd

const PATHS := ["Town", "Landmarks", "Land", "Ascent", "Flora"]


func _initialize() -> void:
	print("--- MESH NORMAL AUDIT ---")
	var packed: PackedScene = load("res://scenes/world/MistvaleRegion.tscn")
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	# The builder nodes fill in on their own _ready(), one frame after this
	# function starts running.
	await process_frame
	await process_frame
	await process_frame

	for path in PATHS:
		var n := scene.get_node_or_null(NodePath(path))
		if n == null:
			print("%-10s MISSING" % path)
			continue
		_audit(path, n)
	print("--- END ---")
	quit(0)


func _audit(label: String, root_n: Node) -> void:
	var meshes := 0
	var no_array := 0
	var zero_frac := 0.0
	var samples := 0
	var examples: Array = []
	var stack: Array = [root_n]
	while not stack.is_empty():
		var m: Node = stack.pop_back()
		for c in m.get_children():
			stack.append(c)
		if not (m is MeshInstance3D):
			continue
		var mesh: Mesh = (m as MeshInstance3D).mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		meshes += 1
		var ar := mesh.surface_get_arrays(0)
		var nrm = ar[Mesh.ARRAY_NORMAL]
		if nrm == null:
			no_array += 1
			if examples.size() < 4:
				examples.append("no-array:" + String(m.name))
			continue
		var z := 0
		var step := maxi(1, nrm.size() / 64)
		var seen := 0
		var i := 0
		while i < nrm.size():
			if (nrm[i] as Vector3).length_squared() < 1e-6:
				z += 1
			seen += 1
			i += step
		zero_frac += float(z) / float(maxi(1, seen))
		samples += 1
		if z > 0 and examples.size() < 4:
			examples.append("%s %d/%d zero" % [m.name, z, seen])
	var avg_pct := 100.0 * zero_frac / float(maxi(1, samples))
	print("%-10s meshes=%-4d no-normal-array=%-3d  mean zero-normal=%5.1f%%   %s"
			% [label, meshes, no_array, avg_pct, ", ".join(examples)])
