# Bake walkable collision for the imported UE5 Mistvale map.
#
# One ConcavePolygonShape3D in WORLD space, saved as a binary .res. Baking is
# per-mesh work in GDScript, so it is slow; doing it once here means the scene
# only ever loads a resource. Building it at run time on every entry into the
# world would cost that same loop on the loading screen, every time.
#
# WHAT IS EXCLUDED, and why:
#
#   SM_River_Continuous -- the water. It is a flat visual proxy, not a floor.
#   Colliding with it lets the player walk across the river like ice, which
#   reads as a bug in a first-person view. With it excluded the player goes in
#   and is recovered by the fall/reset volume, which is the option the brief
#   allows ("soft blocking / shallow bank / reset volume") and the only one that
#   needs no swimming system.
#
# Nothing else is excluded. Buildings, walls, the gate, the bridge, its
# parapets, the terrain and the market props all block, which is what a player
# expects.
#
# WHY backface_collision IS ON -- MEASURED, not defensive:
#
#   With it off (the Godot default) only front-facing triangles stop a ray, so
#   any actor whose triangle winding is flipped is simultaneously VISIBLE and
#   NON-SOLID. That is exactly what happened: SM_Handoff_BridgeSouth, the ramp
#   from the south road up onto the main bridge, is wound the other way round
#   from SM_Handoff_BridgeNorth. With it off, the south approach read:
#
#       z=-114  5.733  ART_Surface_SM_Route_RiversideStreet
#       z=-110  5.706  ART_Graded_Terrain_Proxy        <- under the ramp
#       z=-107  5.613  ART_Graded_Terrain_Proxy
#       z=-105  5.267  ART_Graded_Terrain_Proxy
#       z=-101  6.374  MainStoneBridge_DECK            <- +1.17 m wall
#
#   With it on, the same casts read 6.028 / 6.150 / 6.242 / 6.303 onto the ramp
#   itself and the approach is continuous. The bug is invisible in a screenshot
#   (the ramp draws either way) and invisible to a bounding-box check (the mesh
#   is present and correctly placed), which is why the verification below names
#   what is underfoot instead of only measuring the extent.
#
# Run: godot --headless --path godot --script res://tools/bake_mistvale_collision.gd

extends SceneTree

const GLB := "res://models/mistvale_ue/mistvale_rebuild.glb"
const OUT := "res://models/mistvale_ue/mistvale_collision.res"
const EXCLUDE := ["River_Continuous"]

## Points that must be solid, and the actor that must be the surface there.
## These are the places a wrong collider costs the player the route. Kept short
## and named, so a failure says which part of the walk broke.
const REQUIRED := [
	{"z": -200.0, "actor": "ART_Surface_SM_Route_GoldenRoute_South"},
	{"z": -116.0, "actor": "ART_Surface_SM_Route_GoldenRoute_South"},
	{"z": -114.0, "actor": "SM_Handoff_BridgeSouth"},
	{"z": -110.0, "actor": "SM_Handoff_BridgeSouth"},
	{"z": -107.0, "actor": "SM_Handoff_BridgeSouth"},
	{"z": -105.0, "actor": "SM_Handoff_BridgeSouth"},
	{"z": -101.0, "actor": "MainStoneBridge_DECK"},
	{"z": -84.0, "actor": "MainStoneBridge_DECK"},
	{"z": -68.0, "actor": "MainStoneBridge_DECK"},
	{"z": -60.0, "actor": "SM_Handoff_BridgeNorth"},
	{"z": -50.0, "actor": "ART_Surface_SM_Route_GoldenRoute_Town"},
	{"z": 100.0, "actor": "MarketSquare_Well"},
]

## The south approach must not contain a rise the capsule cannot climb. The
## capsule radius is 0.35 m, so anything more than that between these samples is
## a wall. This is the assertion the flipped ramp failed.
const APPROACH := [-116.0, -114.0, -112.0, -110.0, -108.0, -106.0, -104.0, -102.0, -100.0]
const STEP_LIMIT := 0.35


func _init() -> void:
	_run()


func _run() -> void:
	# The tree is not live during _init(): get_root() exists but nodes are not
	# in it yet, so global_transform silently returns IDENTITY. MEASURED -- the
	# first bake wrote a 10 MB shape whose verts were all in node-local space,
	# with no error beyond a repeated "!is_inside_tree()" line, and the AABB
	# check below is what catches it. One frame must pass first.
	await process_frame

	var packed := load(GLB) as PackedScene
	if packed == null:
		printerr("NO VERDICT: cannot load ", GLB)
		quit(1)
		return
	var inst := packed.instantiate()
	get_root().add_child(inst)
	await process_frame

	var meshes: Array[MeshInstance3D] = []
	_collect(inst, meshes)
	var boxes: Array = []
	for m in meshes:
		boxes.append({"name": m.name, "aabb": m.global_transform * m.get_aabb()})

	var faces := PackedVector3Array()
	var excluded: Array[String] = []
	var empty: Array[String] = []
	for m in meshes:
		var skip := false
		for token in EXCLUDE:
			if token in m.name:
				skip = true
				break
		if skip:
			excluded.append(m.name)
			continue
		var mesh: Mesh = m.mesh
		if mesh == null:
			empty.append(m.name)
			continue
		var xf := m.global_transform
		for s in mesh.get_surface_count():
			var local := _surface_faces(mesh, s)
			if local.is_empty():
				empty.append("%s#%d" % [m.name, s])
				continue
			for v in local:
				faces.append(xf * v)

	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in faces:
		lo = lo.min(v)
		hi = hi.max(v)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	# See the header: with this off, a flipped-winding ramp is drawn but not
	# solid, and the only route onto the main bridge silently becomes a wall.
	shape.backface_collision = true
	var err := ResourceSaver.save(shape, OUT)

	print("COLLISION tris=%d verts=%d excluded=%s empty=%d save_err=%d"
		% [faces.size() / 3, faces.size(), excluded, empty.size(), err])
	print("COLLISION bbox_min=%s bbox_max=%s size=%s" % [lo, hi, hi - lo])
	if not empty.is_empty():
		print("COLLISION empty_surfaces=%s" % [empty.slice(0, 8)])

	# ---- verification: does the baked shape hold a body up where it must? ----
	# _verify contains await, so it is a coroutine and must be awaited here.
	var fails: Array = await _verify(shape, boxes)
	if fails.is_empty():
		print("COLLISION VERDICT: %d required points solid, approach continuous"
			% REQUIRED.size())
		quit(0)
	else:
		for f in fails:
			printerr("COLLISION FAIL: %s" % f)
		printerr("COLLISION VERDICT: FAILED (%d)" % fails.size())
		quit(1)


## Build a throwaway world with only the baked shape in it and interrogate it.
func _verify(shape: ConcavePolygonShape3D, boxes: Array) -> Array:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	get_root().add_child(body)
	await physics_frame
	await physics_frame

	var space := body.get_world_3d().direct_space_state
	var fails: Array = []
	var approach_y: Array = []
	for row in REQUIRED:
		var z: float = row["z"]
		var want: String = row["actor"]
		var hit := _cast(space, z)
		if hit.is_empty():
			fails.append("z=%.1f: nothing solid underfoot (wanted %s)" % [z, want])
			continue
		var p: Vector3 = hit["position"]
		var got := _name_at(boxes, p)
		if got != want:
			fails.append("z=%.1f: standing on %s, wanted %s" % [z, got, want])
		if z in APPROACH:
			approach_y.append({"z": z, "y": p.y})

	approach_y.sort_custom(func(a, b): return a["z"] < b["z"])
	for i in range(1, approach_y.size()):
		var d: float = approach_y[i]["y"] - approach_y[i - 1]["y"]
		if absf(d) > STEP_LIMIT:
			fails.append("approach z=%.1f: step of %+.3f m (limit %.2f)"
				% [approach_y[i]["z"], d, STEP_LIMIT])
	body.queue_free()
	return fails


func _cast(space: PhysicsDirectSpaceState3D, z: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(0.0, 60.0, z), Vector3(0.0, -60.0, z))
	q.collide_with_areas = false
	return space.intersect_ray(q)


## Name the surface by the point a hair below it: the smallest actor box
## containing that point is the most specific description of what holds us up.
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


func _surface_faces(mesh: Mesh, surface: int) -> PackedVector3Array:
	# get_faces() returns the whole mesh, so it is only usable when the mesh has
	# exactly one surface. Otherwise the surface's own vertex/index arrays are
	# used. Both paths stay in C++ except for the index expansion.
	var arrays: Array = mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		return verts
	var out := PackedVector3Array()
	out.resize(idx.size())
	for i in idx.size():
		out[i] = verts[idx[i]]
	return out


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect(child, out)
