extends RefCounted
class_name MirrorAttackLogic
# Pure hit queries + reflection math. No state machine ownership.

const HURTBOX_MASK := 2
const ORIGIN_PLAYER := &"PLAYER"
const ORIGIN_MIRROR_NODE := &"MIRROR_NODE"
const ORIGIN_MIRROR_EXIT := &"MIRROR_EXIT"

var config: MirrorConfig
var player: CharacterBody3D
var manager: MirrorManager

## Last A2 debug rays for overlay / world draw.
var debug_segments: Array[Dictionary] = []


func configure(cfg: MirrorConfig, player_body: CharacterBody3D, mgr: MirrorManager) -> void:
	config = cfg
	player = player_body
	manager = mgr


func slash_query(origin: Vector3, forward: Vector3, range_m: float, half_width: float) -> Array[Node3D]:
	var f := forward
	f.y = 0.0
	if f.length_squared() < 0.0001:
		f = Vector3.FORWARD
	f = f.normalized()
	var center := origin + f * (range_m * 0.55) + Vector3.UP * 0.9
	var size := Vector3(half_width * 2.0, 1.6, range_m)
	return _box_query(center, size, f)


func sphere_query(center: Vector3, radius: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if player == null:
		return out
	var space := player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = HURTBOX_MASK
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for hit in space.intersect_shape(params, 16):
		var actor := _actor_from_hit(hit)
		if actor != null and not out.has(actor):
			out.append(actor)
	return out


func apply_damage(target: Node3D, damage: float, origin_kind: StringName, mirror: MirrorNode = null) -> void:
	if target == null or player == null:
		return
	var hit := {
		"damage": damage,
		"poise_damage": damage * 0.55,
		"element": &"physical",
		"element_scale": 1.0,
		"impulse": 1.1,
		"source": player,
		"target": target,
		"attack_origin": origin_kind,
		"mirror_id": mirror.mirror_id if mirror != null else -1,
	}
	var hurt: CombatHurtbox = target.get_node_or_null("Hurtbox") as CombatHurtbox
	if hurt != null:
		hurt.receive_hit(hit)
	elif target.has_method("receive_hit"):
		target.call("receive_hit", hit)


func a1_player_cut() -> Array[Node3D]:
	var origin := player.global_position
	var forward := _player_forward()
	return slash_query(origin, forward, config.a1_range, config.a1_half_width)


func a1_mirror_echo(mirror: MirrorNode) -> Array[Node3D]:
	if mirror == null:
		return []
	var origin := mirror.global_position
	var forward := mirror.get_mirror_normal()
	return slash_query(origin, forward, config.a1_echo_range, config.a1_half_width * 0.9)


func a3_all_mirrors_echo() -> Array[Dictionary]:
	# PLACEHOLDER — TODO CODEX: REPLACE WITH MIRROR CLONE
	var results: Array[Dictionary] = []
	if manager == null:
		return results
	for n in manager.get_nodes():
		var hits := a1_mirror_echo(n)
		results.append({"mirror": n, "hits": hits})
	return results


func a2_refract(aim_dir: Vector3) -> Dictionary:
	debug_segments.clear()
	var start := player.global_position + Vector3.UP * 1.35
	var dir := aim_dir.normalized()
	var remaining := config.a2_range
	var reflections := 0
	var used: Array[MirrorNode] = []
	var all_hits: Array[Node3D] = []
	var last_point := start

	while remaining > 0.05 and reflections <= config.a2_max_reflections:
		var end := last_point + dir * remaining
		var catch := _find_mirror_along(last_point, dir, remaining, used)
		var stop := end
		var hit_mirror: MirrorNode = null
		if catch.has("mirror"):
			hit_mirror = catch.mirror
			stop = catch.point

		# Damage along segment (near samples).
		var seg_hits := _segment_damage_samples(last_point, stop)
		for t in seg_hits:
			if not all_hits.has(t):
				all_hits.append(t)

		debug_segments.append({
			"from": last_point,
			"to": stop,
			"kind": &"incoming" if reflections == 0 else &"reflected",
			"mirror": hit_mirror,
		})

		if hit_mirror == null:
			break

		used.append(hit_mirror)
		var n := hit_mirror.get_mirror_normal()
		debug_segments.append({
			"from": hit_mirror.global_position,
			"to": hit_mirror.global_position + n * 1.2,
			"kind": &"normal",
			"mirror": hit_mirror,
		})

		# Classic reflection. Incoming dir points toward surface.
		var reflected := dir - 2.0 * dir.dot(n) * n
		if reflected.length_squared() < 0.0001:
			reflected = n
		reflected = reflected.normalized()
		reflected = _soft_assist(reflected, hit_mirror.global_position)

		var travelled := last_point.distance_to(stop)
		remaining = maxf(0.0, remaining - travelled - 0.05)
		last_point = stop + reflected * 0.08
		dir = reflected
		reflections += 1
		if reflections > config.a2_max_reflections:
			break

	return {
		"hits": all_hits,
		"reflections": mini(reflections, config.a2_max_reflections),
		"segments": debug_segments.duplicate(),
	}


func mirror_clone_placeholder() -> void:
	# Intentionally empty. Interface reserved for Codex clone / replay workstream.
	pass


func _find_mirror_along(from: Vector3, dir: Vector3, max_dist: float, skip: Array[MirrorNode]) -> Dictionary:
	if manager == null:
		return {}
	var best: Dictionary = {}
	var best_t := INF
	for n in manager.get_nodes():
		if n in skip:
			continue
		var to_m := n.global_position - from
		var t := to_m.dot(dir)
		if t < 0.15 or t > max_dist:
			continue
		var closest := from + dir * t
		var lateral := closest.distance_to(n.global_position)
		if lateral > config.a2_mirror_catch_radius:
			continue
		# Prefer hitting the front side.
		if dir.dot(n.get_mirror_normal()) > 0.15:
			# Approaching from behind — still allow for prototype readability.
			pass
		if t < best_t:
			best_t = t
			best = {"mirror": n, "point": closest, "t": t}
	return best


func _soft_assist(dir: Vector3, from: Vector3) -> Vector3:
	var best_dir := dir
	var best_dot := cos(deg_to_rad(config.a2_assist_degrees))
	for actor in _nearby_enemies(from, 14.0):
		var to := actor.global_position + Vector3.UP * 1.0 - from
		if to.length_squared() < 0.01:
			continue
		to = to.normalized()
		var d := dir.dot(to)
		if d > best_dot:
			best_dot = d
			best_dir = dir.slerp(to, 0.35).normalized()
	return best_dir


func _segment_damage_samples(a: Vector3, b: Vector3) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var len := a.distance_to(b)
	var steps := maxi(2, int(ceil(len / 1.2)))
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		for t in sphere_query(p, 0.75):
			if not out.has(t):
				out.append(t)
	return out


func _box_query(center: Vector3, size: Vector3, forward: Vector3) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if player == null:
		return out
	var space := player.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = size
	var f := forward
	if f.length_squared() < 0.0001:
		f = Vector3.FORWARD
	f = f.normalized()
	var up := Vector3.UP
	if absf(f.dot(up)) > 0.95:
		up = Vector3.RIGHT
	var basis := Basis.looking_at(f, up)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(basis, center)
	params.collision_mask = HURTBOX_MASK
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for hit in space.intersect_shape(params, 16):
		var actor := _actor_from_hit(hit)
		if actor != null and not out.has(actor):
			out.append(actor)
	return out


func _actor_from_hit(hit: Dictionary) -> Node3D:
	var area: Area3D = hit.get("collider")
	if area == null or not (area is CombatHurtbox):
		return null
	var actor: Node3D = (area as CombatHurtbox).owner_actor
	if actor == null or actor == player:
		return null
	return actor


func _nearby_enemies(from: Vector3, radius: float) -> Array[Node3D]:
	return sphere_query(from + Vector3.UP * 0.8, radius)


func _player_forward() -> Vector3:
	var look := player.get_node_or_null("CameraRig/LookPivot") as Node3D
	if look != null:
		var f := -look.global_transform.basis.z
		f.y = 0.0
		if f.length_squared() > 0.0001:
			return f.normalized()
	var f2 := -player.global_transform.basis.z
	f2.y = 0.0
	return f2.normalized() if f2.length_squared() > 0.0001 else Vector3.FORWARD
