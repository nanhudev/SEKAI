# Cast straight down at chosen points and report exactly what the BAKED
# collision returns there.
#
# Written to settle one question that the walk's profile could not: the walk sits
# 0.2-0.6 m BELOW SM_Handoff_BridgeSouth the whole way across the south approach,
# and a ray starting at prev_y + 1.65 m cannot pass through a floor that is
# above it. Either the ramp is not a floor, or it is not in the collision.
#
# Run: godot --headless --path godot --script res://tools/probe_bridge.gd

extends SceneTree

const GLB := "res://models/mistvale_ue/mistvale_rebuild.glb"
const COLLISION := "res://models/mistvale_ue/mistvale_collision.res"

## (label, x, z, what the art says should be underfoot)
const POINTS := [
	["south road, mid", 0.0, -200.0],
	["south road, north end", 0.0, -116.0],
	["south approach 1", 0.0, -114.0],
	["south approach 2", 0.0, -110.0],
	["south approach 3", 0.0, -107.0],
	["south approach 4", 0.0, -105.0],
	["bridge deck south", 0.0, -101.0],
	["bridge deck middle", 0.0, -84.0],
	["bridge deck north", 0.0, -68.0],
	["north approach", 0.0, -60.0],
	["town road start", 0.0, -50.0],
	["market square", 0.0, 100.0],
	["north gate road", 0.0, 283.0],
]


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame

	# Art, for naming.
	var packed := load(GLB) as PackedScene
	var art := packed.instantiate()
	get_root().add_child(art)
	await process_frame
	var boxes: Array = []
	for node in art.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		boxes.append({"name": mi.name, "aabb": mi.global_transform * mi.get_aabb()})

	# Collision only, so nothing here can be confused with the art meshes.
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = load(COLLISION)
	body.add_child(cs)
	get_root().add_child(body)
	await physics_frame
	await physics_frame

	var shape := cs.shape as ConcavePolygonShape3D
	print("COLLISION faces=%d  backface_collision=%s"
		% [shape.get_faces().size() / 3, shape.backface_collision])

	var space := body.get_world_3d().direct_space_state
	for pass_name in ["as shipped", "with backface_collision"]:
		if pass_name.begins_with("with"):
			# A ConcavePolygonShape3D with backface_collision off only reports
			# front faces, so an actor whose triangle winding is flipped is
			# invisible to a raycast while still being drawn. If this pass starts
			# hitting the south ramp, that is the whole story.
			shape.backface_collision = true
			await physics_frame
			await physics_frame
		print("-- %s --" % pass_name)
		for row in POINTS:
			var label: String = row[0]
			var x: float = row[1]
			var z: float = row[2]
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(x, 60.0, z), Vector3(x, -60.0, z))
			q.collide_with_areas = false
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				print("  %-22s x=%6.1f z=%8.1f  NO HIT" % [label, x, z])
				continue
			var p: Vector3 = hit["position"]
			print("  %-22s x=%6.1f z=%8.1f  hit y=%7.3f   actor=%s"
				% [label, x, z, p.y, _name_at(boxes, p)])
	quit(0)


func _name_at(boxes: Array, p: Vector3) -> String:
	var q := Vector3(p.x, p.y - 0.10, p.z)
	var best := ""
	var best_v := INF
	for b in boxes:
		var aabb: AABB = b["aabb"]
		if aabb.has_point(q):
			var v: float = aabb.size.x * aabb.size.y * aabb.size.z
			if v < best_v:
				best_v = v
				best = b["name"]
	return best if best != "" else "(none)"
