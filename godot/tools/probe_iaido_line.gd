extends SceneTree
##
## WHAT DOES THE CUT LINE ACTUALLY CROSS, AND IS ANY OF IT WORTH CROSSING?
##
## PASS 4 shipped a world that IS cut — the eat collar was narrowed and the two
## halves are displaced 8-14 real px either side of the slit — and the reviewer
## still could not read it in motion: 大脑更多还是通过那条 Void 判断 "这里裂了".
## The displacement is not too small. It is that a displacement is only legible
## where something ALREADY has an edge, and the shot runs this line across flat
## sky, a near-white floor and a white enemy.
##
## So this walks the screen line — the exact line `IaidoCutPlane.from_camera`
## turns into the cut plane — and for every sample prints
##
##   WHAT      the collision body and the visible mesh under it
##   ndot      how square-on that surface is to the eye
##
## `ndot` is the whole point. A surface facing the camera (ndot -> 1) with one
## colour has no edge in it: move it 15px and the picture is identical. A surface
## seen edge-on (ndot -> 0) is a SILHOUETTE, and every silhouette that crosses
## the wound steps by the full separation — which is the only thing the eye can
## actually measure. A shot whose line is all ndot ~ 0.9 is a shot with nothing
## to displace, however wide the slit is.
##
## The enemy block is the other half: how tall it is on screen at 720p and what
## one centimetre of misalignment is worth at its depth.
##
## TWO TRAPS THIS PROBE EXISTS TO WALK AROUND, both of which produced confident
## nonsense the first time it ran:
##   * `camera.project_position()` reports a 64x64 viewport in headless, so rays
##     built from it point somewhere else entirely. Directions are built from the
##     camera basis and fov here. Same trap as probe_iaido_enemy.gd.
##   * the cut line has its slope in PIXELS. Converting uv -> uv without the
##     aspect factor puts the sampled line 40px above the real one at the frame
##     edge, and every "the line crosses X" conclusion lands on the wrong face.
##
## Usage:
##   godot --headless --path . --script res://tools/probe_iaido_line.gd -- [t]
## ---------------------------------------------------------------------------

const RESOLUTION := Vector2(1280.0, 720.0)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var at := float(args[0]) if args.size() > 0 else 5.70
	print("PROBE-LINE start t=%.2f" % at)

	var window: Window = root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var sandbox: Node = load("res://scenes/combat/CombatSandbox.tscn").instantiate()
	window.add_child(sandbox)
	for _i in 4:
		await process_frame

	var director: Node = sandbox.get_node("IaidoDirector")
	director.get("combat").set("iaido_ready_at", 0.0)
	(director.get("player") as Node).set("stamina", 100.0)
	director.set_debug_hold(at)
	for _i in 3:
		await process_frame

	var camera: Camera3D = director.get("camera")
	var tuning: Resource = director.get("tuning")
	var angle: float = deg_to_rad(float(tuning.get("cut_angle_degrees")))
	var centre_uv: Vector2 = tuning.get("cut_center")
	var aspect := RESOLUTION.x / RESOLUTION.y

	print("=== THE SCREEN LINE · t=%.2f ===" % at)
	print("  cut_center=%s  angle=%.1f deg  fov=%.1f  aspect=%.3f"
		% [centre_uv, rad_to_deg(angle), camera.fov, aspect])
	print("  camera pos=%s" % camera.global_position)
	var plane = director.get("cut_plane")
	if plane != null and plane.is_valid():
		print("  cut plane: normal=%s offset=%.4f"
			% [plane.normal, plane.offset])
		print("  plane vs camera: %.4f m (0 = camera is ON the plane)"
			% plane.signed_distance(camera.global_position))

	var space: PhysicsDirectSpaceState3D = sandbox.get_world_3d().direct_space_state

	print("=== THE LINE, SAMPLE BY SAMPLE ===")
	print("  %-13s %-38s %-24s %6s %s" % ["px", "collider", "visible mesh", "ndot", "read"])
	var flat := 0
	var grazing := 0
	var none := 0
	var total := 0
	var sum_ndot := 0.0
	var flat_run := 0
	var longest_flat_run := 0
	var total_run := 0
	for i in 33:
		var u := 0.02 + 0.96 * (float(i) / 32.0)
		var uv := Vector2(
			u, centre_uv.y + (u - centre_uv.x) * tan(angle) * aspect)
		if uv.y < 0.0 or uv.y > 1.0:
			continue
		var px := uv * RESOLUTION
		var from: Vector3 = camera.global_position
		var dir := _ray_dir(camera, uv, aspect)
		var to: Vector3 = from + dir * 400.0
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		total += 1
		if hit.is_empty():
			none += 1
			flat_run = 0
			print("  (%4d,%4d)  %-38s %-24s %6s %s"
				% [int(px.x), int(px.y), "NO HIT", "-", "-", "backdrop"])
			continue
		var body := str(hit["collider"].get_path()).replace("/root/CombatSandbox/", "")
		var mesh_name := _nearest_visible_mesh(sandbox, from, to)
		var ndot := absf((hit["normal"] as Vector3).dot(dir))
		sum_ndot += ndot
		var read := ""
		if ndot > 0.72:
			read = "flat face — a step is invisible"
			flat += 1
			flat_run += 1
			longest_flat_run = maxi(longest_flat_run, flat_run)
		else:
			read = "EDGE / grazing — a step reads here"
			grazing += 1
			flat_run = 0
		total_run += 1
		print("  (%4d,%4d)  %-38s %-24s %6.2f %s"
			% [int(px.x), int(px.y), body, mesh_name, ndot, read])

	print("=== TALLY (%d samples on the line) ===" % total)
	print("  backdrop (nothing there) : %2d  (%3.0f%%)" % [none, 100.0 * none / total])
	print("  FLAT FACE  (invisible)   : %2d  (%3.0f%%)" % [flat, 100.0 * flat / total])
	print("  EDGE/grazing (legible)   : %2d  (%3.0f%%)" % [grazing, 100.0 * grazing / total])
	print("  mean ndot                : %.2f   (1.0 = every surface square on to the eye)"
		% (sum_ndot / maxf(float(total - none), 1.0)))
	print("  longest unbroken flat run: %d samples" % longest_flat_run)

	print("=== WHERE A POINT AT A GIVEN uv WOULD HAVE TO SIT TO BE ON THE PLANE ===")
	print("  (depth along the ray that satisfies n.p = d — use this to PLACE a thing)")
	for candidate in [
			Vector2(0.30, 0.60), Vector2(0.36, 0.64), Vector2(0.42, 0.60),
			Vector2(0.46, 0.56), Vector2(0.52, 0.62), Vector2(0.58, 0.66)]:
		var d := _plane_depth(camera, plane, candidate, aspect)
		var p := camera.global_position + _ray_dir(camera, candidate, aspect) * d
		print("  uv=%s -> depth %6.2f m  world %s"
			% [candidate, d, p.round()])

	print("=== THE ENEMY ON SCREEN ===")
	for node in get_nodes_in_group("hostiles"):
		var actor := node as Node3D
		if actor == null or actor.global_position.z < -20.0:
			continue
		var base := _uv(camera, actor.global_position, aspect)
		var crown := _uv(camera, actor.global_position + Vector3(0, 1.87, 0), aspect)
		var ppm := _px_per_metre(camera, actor.global_position)
		print("  %s  pos=%s  dist=%.1fm"
			% [actor.name, actor.global_position,
				actor.global_position.distance_to(camera.global_position)])
		print("      base px=(%d,%d) crown px=(%d,%d)  height %.0f px @720p"
			% [int(base.x * RESOLUTION.x), int(base.y * RESOLUTION.y),
				int(crown.x * RESOLUTION.x), int(crown.y * RESOLUTION.y),
				absf(crown.y - base.y) * RESOLUTION.y])
		print("      %.0f px per metre · 1cm = %.2f px · a 2-4cm creep = %.1f-%.1f px · an 8px step = %.0f cm"
			% [ppm, ppm * 0.01, ppm * 0.02, ppm * 0.04, 8.0 / maxf(ppm, 0.0001) * 100.0])
		if plane != null and plane.is_valid():
			print("      plane signed_dist: base %.3f m  head %.3f m"
				% [plane.signed_distance(actor.global_position),
					plane.signed_distance(actor.global_position + Vector3(0, 1.87, 0))])

	print("PROBE-LINE done")
	quit()


## The world-space ray direction through a uv, built from the camera's basis and
## fov. See the header about headless's 64x64 viewport.
func _ray_dir(camera: Camera3D, uv: Vector2, aspect: float) -> Vector3:
	var half_h: float = tan(deg_to_rad(camera.fov) * 0.5)
	var local := Vector3(
		(uv.x - 0.5) * half_h * aspect,
		(0.5 - uv.y) * half_h,
		-1.0)
	return (camera.global_basis * local).normalized()


## How far along the ray through `uv` the cut plane is. -1 when the ray never
## meets it. This is how a prop or a body gets placed ON the blade's own plane
## without re-deriving the plane by hand.
func _plane_depth(camera: Camera3D, plane, uv: Vector2, aspect: float) -> float:
	if plane == null or not plane.is_valid():
		return -1.0
	var origin: Vector3 = camera.global_position
	var dir := _ray_dir(camera, uv, aspect)
	var denom: float = plane.normal.dot(dir)
	if absf(denom) < 0.00001:
		return -1.0
	return (plane.offset - plane.normal.dot(origin)) / denom


## The nearest MeshInstance3D whose world AABB the segment passes through, by
## name. Collision proxies and meshes are different nodes, and the point of this
## probe is to name what the EYE sees on the line rather than what the physics
## happens to report.
func _nearest_visible_mesh(root_node: Node, from: Vector3, to: Vector3) -> String:
	var best := ""
	var best_d := INF
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		var mi := node as MeshInstance3D
		if mi == null or not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var t := _ray_box(from, to, mi.global_transform, mi.get_aabb())
		if t < best_d:
			best_d = t
			best = str(mi.get_path()).replace("/root/CombatSandbox/", "")
	return best


## Slab test against a transformed AABB. Entry distance in metres, or INF.
func _ray_box(from: Vector3, to: Vector3, xform: Transform3D, box: AABB) -> float:
	var inv := xform.affine_inverse()
	var o := inv * from
	var d := (inv * to) - o
	var lo := box.position
	var hi := box.position + box.size
	var tmin := 0.0
	var tmax := 1.0
	for axis in 3:
		var od: float = d[axis]
		var oo: float = o[axis]
		if absf(od) < 0.000001:
			if oo < lo[axis] or oo > hi[axis]:
				return INF
			continue
		var t1: float = (lo[axis] - oo) / od
		var t2: float = (hi[axis] - oo) / od
		if t1 > t2:
			var swap := t1
			t1 = t2
			t2 = swap
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return INF
	return from.distance_to(from.lerp(to, tmin))


func _uv(camera: Camera3D, point: Vector3, aspect: float) -> Vector2:
	var local: Vector3 = camera.global_transform.affine_inverse() * point
	var depth: float = -local.z
	if depth < 0.0001:
		return Vector2(-1.0, -1.0)
	var half_h: float = tan(deg_to_rad(camera.fov) * 0.5)
	return Vector2(
		0.5 + (local.x / depth) / (half_h * aspect),
		0.5 - (local.y / depth) / half_h)


## 720p pixels per world metre at this depth.
##
## ONE `half_h`, NOT `2 * half_h`. `uv.y = 0.5 - (local.y / depth) / half_h`, so a
## metre of height is `1 / (depth * half_h)` of the frame — the factor of two
## would halve every size this probe reports and make a 174px enemy look like 87.
func _px_per_metre(camera: Camera3D, point: Vector3) -> float:
	var local: Vector3 = camera.global_transform.affine_inverse() * point
	var depth: float = maxf(-local.z, 0.0001)
	var half_h: float = tan(deg_to_rad(camera.fov) * 0.5)
	return RESOLUTION.y / (half_h * depth)
