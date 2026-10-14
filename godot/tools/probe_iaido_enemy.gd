extends SceneTree
##
## WHY IS THE ENEMY NOT BEING CUT?
##
## The ceremony has a complete enemy contract — same cut plane, held pose,
## hairline trace, 1-3cm creep, split at the click — and the movie showed the
## dummy standing whole from t=0 to t=5.70 while the crack ran right past it.
##
## A cut plane is not a crack on the screen: it is a plane through the camera
## that CONTAINS the screen line. The world shader draws the line; the enemy is
## bisected by the preimage of that line. Unless a body actually straddles the
## plane, "cut in half" removes a sliver of its base and the body reads as
## whole — which is exactly what happened.
##
## This prints the whole chain at several instants instead of guessing:
##
##   1. who is in the `hostiles` group and where
##   2. what `IaidoTargetCollector.collect_targets()` returns for the real camera
##   3. what the director actually stored in `targets`
##   4. `ad`, in authored pixels, from the cut line to a lattice of points up
##      the body — 0 means the line runs through that point
##   5. the execution nodes that exist after `damage_time`, and what they hold
##
## THE PROJECTION IS COMPUTED HERE, NOT READ OFF THE VIEWPORT. Headless renders
## into a 64x64 window, so `unproject_position()` answers a question about a
## square viewport and its uv.x means nothing at 1280x720. The uv below comes
## from the camera's own basis and fov, so it is the uv the ceremony renders.
##
## Usage:
##   godot --headless --path . --script res://tools/probe_iaido_enemy.gd -- [t1,t2]
## ---------------------------------------------------------------------------

## The resolution the ceremony is actually rendered at.
const RENDER_RESOLUTION := Vector2(1280.0, 720.0)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var stamps: Array[float] = [5.10, 6.90, 8.60]
	if args.size() > 0 and args[0].strip_edges() != "":
		stamps.clear()
		for piece in args[0].split(","):
			stamps.append(float(piece))

	var window: Window = root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var sandbox: Node = load("res://scenes/combat/CombatSandbox.tscn").instantiate()
	window.add_child(sandbox)
	for _i in 4:
		await process_frame

	var director: Node = sandbox.get_node("IaidoDirector")
	var collector: Node = sandbox.get_node("IaidoTargetCollector")
	var combat: Node = director.get("combat")
	combat.set("iaido_ready_at", 0.0)
	var player: Node3D = director.get("player")
	player.set("stamina", 100.0)

	director.set_debug_hold(0.0)
	for _i in 3:
		await process_frame

	var camera: Camera3D = director.get("camera")
	var tuning: Resource = director.get("tuning")
	var hostiles := get_nodes_in_group("hostiles")

	print("=== 0 · SCENE ===")
	print("  headless viewport   = ", camera.get_viewport().get_visible_rect().size)
	print("  RENDER resolution   = ", RENDER_RESOLUTION)
	print("  camera at           = ", camera.global_position, " fov=", camera.fov)
	print("  cut_center          = ", tuning.get("cut_center"))
	print("  cut_angle_degrees   = ", tuning.get("cut_angle_degrees"))

	print("=== 1 · hostiles GROUP (count %d) ===" % hostiles.size())
	for node in hostiles:
		if not node is Node3D:
			continue
		var actor := node as Node3D
		var profile = actor.call("iaido_execution_profile") if actor.has_method("iaido_execution_profile") else null
		print("  - ", actor.get_path(), "  pos=", actor.global_position,
			" visible=", actor.visible, " health=", actor.get("health"),
			" type=", profile.get("execution_type") if profile != null else "-")

	print("=== 2 · COLLECTOR (live camera) ===")
	var found: Array = collector.collect_targets(player, camera)
	print("  collect_targets() -> ", found.size())
	for actor in found:
		print("  - ", (actor as Node3D).get_path())

	print("=== 3 · DIRECTOR targets ===")
	var director_targets: Array = director.get("targets")
	print("  director.targets.size() = ", director_targets.size())
	for actor in director_targets:
		print("  - ", (actor as Node3D).get_path())

	# MEASURED AT THE INSTANT THE PLANE IS ACTUALLY CUT, not at t=0. The camera's
	# FOV is ramping until `fov_pull_end` and constant thereafter, so a uv read
	# at t=0 answers a question about a different camera than the one the slash
	# was taken from.
	director.set_debug_hold(5.10)
	for _i in 2:
		await process_frame

	print("=== 4 · THE CUT LINE vs EVERY BODY ===")
	var plane = director.get("cut_plane")
	var aspect: float = RENDER_RESOLUTION.x / RENDER_RESOLUTION.y
	# One authored pixel of a 1080-tall frame, in the shader's `rel` units.
	var px_s: float = (RENDER_RESOLUTION.y / 1080.0) / RENDER_RESOLUTION.y
	var angle: float = deg_to_rad(float(tuning.get("cut_angle_degrees")))
	var nrm := Vector2(-sin(angle), cos(angle))
	var centre_uv: Vector2 = tuning.get("cut_center")
	for node in hostiles:
		if not node is Node3D:
			continue
		var actor := node as Node3D
		print("  ", actor.get_path(), "  origin=", actor.global_position)
		for step in [0.0, 0.4, 0.8, 1.2, 1.6]:
			var point: Vector3 = actor.global_position + Vector3.UP * float(step)
			var uv := uv_of(camera, point)
			var rel := (uv - centre_uv) * Vector2(aspect, 1.0)
			var ad := absf(rel.dot(nrm)) / px_s
			print("      +%.1fm  uv=(%.4f, %.4f)  ad=%7.1f authored px  %s"
				% [step, uv.x, uv.y, ad, "<-- ON THE CUT" if ad < 10.0 else ""])
		if plane != null and plane.is_valid():
			print("      signed_dist  origin=%.3f m  head=%.3f m"
				% [plane.signed_distance(actor.global_position),
					plane.signed_distance(actor.global_position + Vector3.UP * 1.2)])

	for stamp in stamps:
		director.set_debug_hold(float(stamp))
		for _i in 2:
			await process_frame
		var executions: Array = director.get("executions")
		print("=== 5 · t = %.2f · executions = %d ===" % [float(stamp), executions.size()])
		for node in hostiles:
			if not node is Node3D:
				continue
			var actor := node as Node3D
			print("  ", actor.get_path(), " visible=", actor.visible,
				" state=", actor.get("state"), " health=", actor.get("health"))
		for execution in executions:
			print("  execution: mode=", execution.get("mode"),
				" built=", execution.get("built"),
				" pieces=", execution.call("piece_count"),
				" separation=%.4f m" % float(execution.call("separation")),
				" released=", execution.call("is_released", float(stamp)))

	quit()


## The uv the ceremony renders at, computed from the camera itself. See the note
## in the header about headless's 64x64 viewport.
func uv_of(camera: Camera3D, world_point: Vector3) -> Vector2:
	var local: Vector3 = camera.global_transform.affine_inverse() * world_point
	# In front of the camera `local.z` is negative; the divisor is its depth.
	var depth: float = -local.z
	if depth < 0.0001:
		return Vector2(-1.0, -1.0)
	var half_h: float = tan(deg_to_rad(camera.fov) * 0.5)
	var aspect: float = RENDER_RESOLUTION.x / RENDER_RESOLUTION.y
	# `fov` is the VERTICAL fov under KEEP_HEIGHT, which is Godot's default.
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		half_h = tan(deg_to_rad(camera.fov) * 0.5) / aspect
	return Vector2(
		0.5 + (local.x / depth) / (half_h * aspect),
		0.5 - (local.y / depth) / half_h)
