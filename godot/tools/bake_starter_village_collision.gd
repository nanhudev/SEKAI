extends SceneTree

const ROOT := "res://models/starter_village/v078/"

func _initialize() -> void:
	call_deferred("_bake")

func _bake() -> void:
	var art := (load(ROOT + "starter_village.glb") as PackedScene).instantiate()
	root.add_child(art)
	var result := Node3D.new()
	result.name = "VillageCollision"
	root.add_child(result)
	var count := 0
	var pending: Array[Node] = [art]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		for child in n.get_children():pending.append(child)
		if not n is MeshInstance3D:continue
		var label := String(n.name)
		if label.begins_with("Forest_") or "Stream" in label or "Foliage" in label or "Planting" in label or "Fern" in label or "Ivy" in label or "RootDetails" in label or "Surroundings" in label:continue
		var mesh_node := n as MeshInstance3D
		var shape := mesh_node.mesh.create_trimesh_shape()
		shape.backface_collision = true
		var body := StaticBody3D.new()
		body.name = label
		result.add_child(body);body.owner = result
		body.global_transform = mesh_node.global_transform
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider);collider.owner = result
		count += 1
	var packed := PackedScene.new()
	assert(packed.pack(result) == OK)
	assert(ResourceSaver.save(packed, ROOT + "collision.scn") == OK)
	print("STARTER_COLLISION_BAKED ", count)
	quit()
