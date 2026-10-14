# Verify the imported UE5 Mistvale GLB actually landed where Blender said it would.
#
# Blender exported this map with the promise  godot = (ue.x, ue.z, -ue.y)  and
# wrote the per-node expectation to ue5_lab/.../_handoff/glb_expected.json. This
# script reads the imported scene back out of Godot and dumps the same numbers,
# so the comparison is done by diffing two files rather than by looking at a
# frame and deciding it "looks about right". An axis flip here is exactly the
# bug that mirrored this terrain north/south once already, and it is invisible
# in a screenshot.
#
# Run: godot --headless --path godot --script res://tools/probe_mistvale_ue.gd

extends SceneTree

const GLB := "res://models/mistvale_ue/mistvale_rebuild.glb"
const OUT := "F:/SEKAI/ue5_lab/Mistvale_Rebuild/_handoff/glb_actual.json"


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame

	var packed := load(GLB) as PackedScene
	if packed == null:
		printerr("NO VERDICT: could not load ", GLB)
		quit(1)
		return

	var inst := packed.instantiate()
	get_root().add_child(inst)
	await process_frame

	var meshes: Array[MeshInstance3D] = []
	_collect(inst, meshes)

	var combined := AABB()
	var first := true
	var tris := 0
	var nodes: Array = []
	for m in meshes:
		var aabb: AABB = m.global_transform * m.get_aabb()
		if first:
			combined = aabb
			first = false
		else:
			combined = combined.merge(aabb)
		var mesh: Mesh = m.mesh
		if mesh != null:
			for s in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(s)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.size() > 0:
					tris += indices.size() / 3
				else:
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					tris += verts.size() / 3
		nodes.append({
			"name": m.name,
			"min": _r(aabb.position),
			"max": _r(aabb.position + aabb.size),
		})

	var report := {
		"mesh_nodes": meshes.size(),
		"tris": tris,
		"bbox_min": _r(combined.position),
		"bbox_max": _r(combined.position + combined.size),
		"size": _r(combined.size),
		"nodes": nodes,
	}
	var fh := FileAccess.open(OUT, FileAccess.WRITE)
	fh.store_string(JSON.stringify(report, " "))
	fh.close()

	print("UEMAP mesh_nodes=%d tris=%d size=%s" % [meshes.size(), tris, _r(combined.size)])
	print("UEMAP bbox_min=%s bbox_max=%s" % [_r(combined.position), _r(combined.position + combined.size)])
	quit(0)


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect(child, out)


func _r(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
