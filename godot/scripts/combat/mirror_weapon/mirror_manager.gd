extends Node
class_name MirrorManager
# Owns every placed MirrorNode. Weapon controller does not scatter node lists.

signal node_placed(node: MirrorNode)
signal node_removed(node: MirrorNode)
signal cleared()

const PLACE_MASK := 1  # world static geometry (project default layer 1)

var config: MirrorConfig
var host: Node3D
var player: CharacterBody3D
var camera: Camera3D

var _nodes: Array[MirrorNode] = []
var _next_id := 1
var _order := 0
var _labels_on := false
var _debug_on := false


func configure(cfg: MirrorConfig, host_node: Node3D, player_body: CharacterBody3D, cam: Camera3D) -> void:
	config = cfg
	host = host_node
	player = player_body
	camera = cam


func get_nodes() -> Array[MirrorNode]:
	_prune()
	return _nodes.duplicate()


func count() -> int:
	_prune()
	return _nodes.size()


func register_node(node: MirrorNode) -> void:
	_nodes.append(node)
	while _nodes.size() > config.mirror_max_count:
		remove_oldest()
	node_placed.emit(node)


func remove_node(node: MirrorNode) -> void:
	if node == null:
		return
	_nodes.erase(node)
	if is_instance_valid(node):
		node.queue_free()
	node_removed.emit(node)


func remove_oldest() -> void:
	_prune()
	if _nodes.is_empty():
		return
	var oldest: MirrorNode = _nodes[0]
	for n in _nodes:
		if n.creation_order < oldest.creation_order:
			oldest = n
	remove_node(oldest)


func clear_all() -> void:
	_prune()
	for n in _nodes.duplicate():
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	cleared.emit()


func get_last_created() -> MirrorNode:
	_prune()
	if _nodes.is_empty():
		return null
	var best: MirrorNode = _nodes[0]
	for n in _nodes:
		if n.creation_order > best.creation_order:
			best = n
	return best


func get_closest_node(from: Vector3) -> MirrorNode:
	_prune()
	var best: MirrorNode = null
	var best_d := INF
	for n in _nodes:
		var d := from.distance_squared_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func get_aim_selected_node() -> MirrorNode:
	_prune()
	if _nodes.is_empty() or camera == null:
		return null
	var best: MirrorNode = null
	var best_score := INF
	var vp := camera.get_viewport().get_visible_rect().size
	var center := vp * 0.5
	for n in _nodes:
		if not camera.is_position_behind(n.global_position):
			var screen := camera.unproject_position(n.global_position)
			var score := screen.distance_squared_to(center)
			# Prefer on-screen and in front.
			var to := (n.global_position - camera.global_position).normalized()
			var forward := -camera.global_transform.basis.z
			if to.dot(forward) < 0.15:
				score += 1.0e6
			if score < best_score:
				best_score = score
				best = n
	if best == null:
		return get_closest_node(player.global_position if player else Vector3.ZERO)
	return best


func update_selection() -> MirrorNode:
	var sel := get_aim_selected_node()
	for n in _nodes:
		n.set_selected(n == sel)
	return sel


func set_labels_visible(on: bool) -> void:
	_labels_on = on
	for n in _nodes:
		n.set_label_visible(on)


func set_debug_draw(on: bool) -> void:
	_debug_on = on
	for n in _nodes:
		n.set_debug_draw(on)


func try_place_from_aim() -> MirrorNode:
	if player == null or camera == null or host == null or config == null:
		return null
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		origin + dir * 0.2,
		origin + dir * config.mirror_place_max
	)
	query.collision_mask = PLACE_MASK
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	var dist := origin.distance_to(point)
	if dist < config.mirror_place_min or dist > config.mirror_place_max:
		return null
	return place_at(point, normal, dir)


## Direct place for tests / movie tools. `surface_n` is the hit normal.
func place_at(point: Vector3, surface_n: Vector3, prefer_face: Vector3 = Vector3.ZERO) -> MirrorNode:
	if host == null or config == null or player == null:
		return null
	var normal := surface_n
	if normal.length_squared() < 0.0001:
		normal = Vector3.UP
	normal = normal.normalized()
	var pos := point
	var face_n := normal
	if absf(normal.y) > 0.72:
		pos = point + Vector3.UP * (config.mirror_height * 0.5 + 0.05)
		face_n = player.global_position - pos
		face_n.y = 0.0
		if face_n.length_squared() < 0.001:
			face_n = prefer_face
			face_n.y = 0.0
		if face_n.length_squared() < 0.001:
			face_n = Vector3.FORWARD
		face_n = face_n.normalized()
	else:
		pos = point + normal * config.mirror_wall_offset + Vector3.UP * 0.05
		face_n = normal

	var node := MirrorNode.new()
	node.name = "MirrorNode_%d" % _next_id
	host.add_child(node)
	node.global_position = pos
	node.configure(config, _next_id, _order, face_n)
	_next_id += 1
	_order += 1
	node.set_label_visible(_labels_on)
	node.set_debug_draw(_debug_on)

	if absf(normal.y) > 0.72:
		var aim_at: Vector3 = node.global_position + face_n
		if aim_at.distance_squared_to(node.global_position) > 0.0001:
			node.look_at(aim_at, Vector3.UP)
		node.rotation.x = 0.0
		node.rotation.z = 0.0

	_compute_safe_exit(node)
	register_node(node)
	return node


func _compute_safe_exit(node: MirrorNode) -> void:
	var n := node.get_mirror_normal()
	if n.length_squared() < 0.0001:
		n = Vector3.FORWARD
	n = n.normalized()
	var origin := node.global_position
	var best_xf := Transform3D(_safe_basis(n), origin + n * config.exit_offset_min)
	var ok := false
	var steps := 8
	for i in range(steps):
		var t := float(i) / float(maxi(1, steps - 1))
		var dist := lerpf(config.exit_offset_min, config.exit_offset_max, t)
		var candidate: Vector3 = origin + n * dist
		candidate.y = _ground_y(candidate) + 0.05
		if _capsule_free(candidate):
			best_xf = Transform3D(_safe_basis(n), candidate)
			ok = true
			break
	# Fallback: search sideways if forward blocked.
	if not ok:
		var sides: Array[float] = [1.0, -1.0, 2.0, -2.0]
		for side in sides:
			var right: Vector3 = n.cross(Vector3.UP)
			if right.length_squared() < 0.001:
				right = Vector3.RIGHT
			right = right.normalized()
			var candidate: Vector3 = origin + n * config.exit_offset_min + right * side * 0.45
			candidate.y = _ground_y(candidate) + 0.05
			if _capsule_free(candidate):
				best_xf = Transform3D(_safe_basis(n), candidate)
				ok = true
				break
	node.set_safe_exit(best_xf, ok)


func _safe_basis(forward: Vector3) -> Basis:
	var f := forward
	if f.length_squared() < 0.0001:
		f = Vector3.FORWARD
	f = f.normalized()
	var up := Vector3.UP
	if absf(f.dot(up)) > 0.95:
		up = Vector3.RIGHT
	return Basis.looking_at(f, up)


func _ground_y(at: Vector3) -> float:
	if player == null:
		return at.y
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 6.0)
	q.collision_mask = PLACE_MASK
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return at.y
	return hit.position.y


func _capsule_free(at: Vector3) -> bool:
	if player == null:
		return true
	var space := player.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = config.exit_probe_radius
	shape.height = config.exit_probe_height
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (config.exit_probe_height * 0.5))
	params.collision_mask = PLACE_MASK
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.exclude = [player.get_rid()]
	var hits := space.intersect_shape(params, 4)
	return hits.is_empty()


func _prune() -> void:
	var alive: Array[MirrorNode] = []
	for n in _nodes:
		if is_instance_valid(n) and n.active:
			alive.append(n)
	_nodes = alive
