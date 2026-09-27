extends Node
class_name IaidoTargetCollector

@export var tuning: CombatTuning = preload("res://resources/tuning/CombatTuning.tres")


func collect(player: CharacterBody3D, camera: Camera3D) -> Node3D:
	var best: Node3D
	var best_score := -INF
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var space := player.get_world_3d().direct_space_state
	for candidate in get_tree().get_nodes_in_group("hostiles"):
		if not candidate is Node3D or not candidate.visible:
			continue
		var actor := candidate as Node3D
		var health: Variant = actor.get("health")
		if health != null and float(health) <= 0.0:
			continue
		var target_point := actor.global_position + Vector3.UP
		var offset := target_point - origin
		var distance := offset.length()
		if distance > tuning.iaido_range or absf(offset.y) > tuning.iaido_vertical_tolerance:
			continue
		var horizontal := Vector2(offset.x, offset.z).normalized()
		var forward_horizontal := Vector2(forward.x, forward.z).normalized()
		var angle := rad_to_deg(acos(clampf(horizontal.dot(forward_horizontal), -1.0, 1.0)))
		if angle > tuning.iaido_cone_degrees:
			continue
		var query := PhysicsRayQueryParameters3D.create(origin, target_point)
		query.exclude = [player.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var collider: Object = hit.get("collider")
			if collider != actor and not (collider is Node and actor.is_ancestor_of(collider)):
				continue
		var screen_center := camera.get_viewport().get_visible_rect().size * 0.5
		var screen_offset := camera.unproject_position(target_point).distance_to(screen_center) / maxf(1.0, screen_center.length())
		var score := (1.0 - clampf(screen_offset, 0.0, 1.0)) * 0.55 + (1.0 - angle / tuning.iaido_cone_degrees) * 0.30 + (1.0 - distance / tuning.iaido_range) * 0.15
		if score > best_score:
			best_score = score
			best = actor
	return best
