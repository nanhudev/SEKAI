extends SceneTree
#
# PROBE · 缚星链 WALL FRAME — does the wall a bite lands on actually reach the frame?
#
# WHY THIS EXISTS. `chain_v4_slice` says the anchor is exact: the head lands on
# z = −42.25 and does not drift a millimetre over forty frames. §18 is therefore
# satisfied AS A NUMBER and the take still does not read, because the frame it was
# photographed in showed the trident resting against nothing — a pale head floating in
# grey. "The head is pinned to the contact transform" and "the player can see that it
# bit something" are two different claims, and only the first one had a test.
#
# So this measures the second one the only way it can be measured: by projecting the
# wall's own box into the take's camera and printing the rectangle it occupies, in the
# same pixels and with the same arithmetic as `probe_chain_framing.gd`.
#
# It also prints the SUN, because a 0.24-albedo box that renders the same value as the
# sky is a lighting question and not a geometry one, and a lighting question answered
# by eye is the kind that gets answered wrongly twice.
#
# This is a developer probe, not a test: it asserts nothing and never fails.
#
# Usage:
#   godot --headless --path godot --script res://tools/probe_wall_frame.gd

const VIEW := Vector2(1280.0, 720.0)
# The D take's own numbers. Kept identical to `_build_chain_v4_segments` on purpose:
# a probe that stages the shot differently measures a shot that does not exist.
const PITCH_DEG := -13.0
const STAND_STANDOFF := 3.35

var world: Node3D
var player: CharacterBody3D
var chain: ChainDirector
var weapon: WeaponSlot
var camera: Camera3D
var lab: ChainLab


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	world = (load("res://scenes/combat/CombatSandbox.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await _wait(12)
	player = world.get_node("Player")
	chain = player.get_node("ChainDirector")
	weapon = player.get_node("WeaponSlot")
	camera = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D") as Camera3D
	lab = world.get_node_or_null("ChainLab") as ChainLab

	var wall_face_z := ChainLab.WALL_Z + 0.35
	var wall_stand_z := wall_face_z + STAND_STANDOFF

	weapon.equip(WeaponSlot.CHAIN)
	chain.reset()
	player.global_position = Vector3(0.0, 0.9, wall_stand_z)
	player.velocity = Vector3.ZERO
	player.rotation = Vector3.ZERO
	(player.get_node("CameraRig/LookPivot") as Node3D).rotation.x = deg_to_rad(PITCH_DEG)
	await _wait(24)

	print("")
	print("缚星链 · WALL FRAME PROBE   frame %d x %d   fov %.1f (vertical)"
		% [int(VIEW.x), int(VIEW.y), camera.fov])
	print("  player   %s   pitch %+.1f°" % [_v3(player.global_position), PITCH_DEG])
	print("  eye      %s" % _v3(camera.global_position))
	print("  wall face z %.2f   →  %.2f m in front of the eye"
		% [wall_face_z, camera.global_position.z - wall_face_z])
	print("  horizon sits at y = %.0f px" % _project(
		camera.global_position - camera.global_transform.basis.z * 30.0
		+ Vector3(0.0, -camera.global_position.y + camera.global_position.y, 0.0)
	).y)

	# ---- 1 · THE WALL, AS A RECTANGLE IN THE FRAME -------------------------
	var wall := _find_wall()
	if wall == null:
		print("  !! no wall body found under ChainLab — nothing to photograph")
	else:
		var mesh := _first_mesh(wall)
		print("")
		print("  wall body  %s" % _v3(wall.global_position))
		if mesh != null:
			var box := (mesh.mesh as BoxMesh).size
			print("  wall box   %.2f x %.2f x %.2f   visible=%s  layers=%d"
				% [box.x, box.y, box.z, mesh.is_visible_in_tree(), mesh.layers])
			var mat := mesh.material_override as StandardMaterial3D
			if mat != null:
				print("  wall mat   albedo %s  rough %.2f  metallic %.2f"
					% [_c(mat.albedo_color), mat.roughness, mat.metallic])
			_rect("wall box", mesh.global_transform, box)
		else:
			print("  wall body has no MeshInstance3D — it blocks but does not draw")

	# ---- 2 · THE SUN THE WALL IS LIT BY ------------------------------------
	var sun := _find_sun(world)
	if sun == null:
		print("")
		print("  !! no DirectionalLight3D in the sandbox")
	else:
		print("")
		print("  sun  %s  energy %.2f  shadows=%s"
			% [_v3(-sun.global_transform.basis.z), sun.light_energy, sun.shadow_enabled])
		print("  sun  direction · into the wall (0,0,-1) = %+.2f"
			% (sun.global_transform.basis.z.normalized().dot(Vector3.FORWARD)))

	# ---- 3 · FIRE A1 AND SEE WHERE THE BITE LANDS --------------------------
	chain.request(&"light")
	var anchored_frame := -1
	for i in 240:
		chain.step(1.0 / 60.0)
		if anchored_frame < 0 and chain.is_anchored():
			anchored_frame = i
		if anchored_frame >= 0 and i - anchored_frame >= 30:
			break
	print("")
	if anchored_frame < 0:
		print("  !! A1 never anchored in 240 frames — the D take's wall is not on the arc")
	else:
		print("  A1 anchored at frame %d (%.2fs)" % [anchored_frame, anchored_frame / 60.0])
	var head := chain.chain_visual.get_node_or_null("TerminalHead") as Node3D
	if head != null:
		_rect("trident", head.global_transform, Vector3(0.9, 0.9, 0.9))
		print("  trident at %s → px %s" % [_v3(head.global_position), _p2(_project(head.global_position))])

	quit()


# ============================================================================
func _find_wall() -> StaticBody3D:
	if lab == null:
		return null
	var best: StaticBody3D = null
	var best_d := 1.2
	for child in lab.get_children():
		if child is not StaticBody3D:
			continue
		var body := child as StaticBody3D
		var d := absf(body.global_position.z - ChainLab.WALL_Z)
		if d < best_d:
			best_d = d
			best = body
	return best


func _find_sun(node: Node) -> DirectionalLight3D:
	if node is DirectionalLight3D:
		return node as DirectionalLight3D
	for child in node.get_children():
		var found := _find_sun(child)
		if found != null:
			return found
	return null


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


## The projected bounding rectangle of a box, in pixels. Eight corners rather than the
## centre and a radius: a wall is a box, and its extent is not a sphere.
func _rect(label: String, xform: Transform3D, size: Vector3) -> void:
	var half := size * 0.5
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var behind := 0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var corner := xform * Vector3(half.x * sx, half.y * sy, half.z * sz)
				var p := _project(corner)
				if p.x < 0.0 and p.y < 0.0:
					behind += 1
					continue
				lo = lo.min(p)
				hi = hi.max(p)
	if behind == 8:
		print("  %-10s entirely behind the lens" % label)
		return
	print("  %-10s px x %.0f..%.0f   y %.0f..%.0f   (%s)"
		% [label, lo.x, hi.x, lo.y, hi.y, "%d corners off-lens" % behind if behind > 0 else "all in front"])


func _project(world_point: Vector3) -> Vector2:
	var local := camera.global_transform.affine_inverse() * world_point
	if local.z >= -0.02:
		return Vector2(-1.0, -1.0)
	var half := tan(deg_to_rad(camera.fov * 0.5))
	var aspect := VIEW.x / VIEW.y
	var nx := local.x / (-local.z * half * aspect)
	var ny := local.y / (-local.z * half)
	return Vector2((nx * 0.5 + 0.5) * VIEW.x, (0.5 - ny * 0.5) * VIEW.y)


func _p2(p: Vector2) -> String:
	return "(%.0f, %.0f)" % [p.x, p.y]


func _v3(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _c(c: Color) -> String:
	return "(%.2f, %.2f, %.2f)" % [c.r, c.g, c.b]


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame
