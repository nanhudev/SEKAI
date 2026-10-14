extends SceneTree
##
## Dumps every VISIBLE MeshInstance3D in the ceremony scene at one or more
## exact timeline instants, with its node path, world position and world size.
##
## This exists to answer "what is that second object on screen" by NAME instead
## of by eye. Frame review can say an object is there; it cannot say which node
## put it there, and guessing has already cost one round.
##
## Usage:
##   godot --headless --path . --script res://tools/probe_iaido_frame.gd -- \
##         "5.77,8.27" [path_substring_filter]
##
## The filter is matched against the node path, case-insensitively; empty means
## everything.

const FPS := 30.0
const STEP := 1.0 / FPS

var times: Array[float] = []
var wanted := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].strip_edges() != "":
		for piece in args[0].split(","):
			times.append(float(piece.strip_edges()))
	if times.is_empty():
		times.append(5.77)
	wanted = args[1].strip_edges().to_lower() if args.size() > 1 else ""

	var sandbox: Node = load("res://scenes/combat/CombatSandbox.tscn").instantiate()
	root.add_child(sandbox)

	await process_frame
	await process_frame
	await process_frame

	var director: Node = sandbox.get_node("IaidoDirector")
	var player := director.get("player") as Node3D
	director.get("combat").set("iaido_ready_at", 0.0)
	player.set("stamina", 100.0)

	var camera := player.get_node(
		"CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D") as Camera3D

	for t in times:
		director.set_debug_hold(t)
		await process_frame
		await process_frame
		print("=== t = %.3f  (director.active=%s) ===" % [t, str(director.get("active"))])
		print("  main camera: name=%s cull_mask=%d (=0x%x)" % [
			camera.name, camera.cull_mask, camera.cull_mask])
		var fg := sandbox.get_node_or_null("ForegroundWeaponLayer")
		if fg != null:
			var fgc := fg.get("foreground_camera") as Camera3D
			print("  foreground layer %s  fg_camera.cull_mask=%d (=0x%x)  image_rect.visible=%s" % [
				str(fg.get("layer")),
				fgc.cull_mask if fgc != null else -1,
				fgc.cull_mask if fgc != null else -1,
				str((fg.get("image_rect") as Control).visible) if fg.get("image_rect") != null else "?"])
		_dump(sandbox, camera, 0)
	await process_frame
	quit()


func _dump(node: Node, camera: Camera3D, depth: int) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.is_visible_in_tree() and mi.mesh != null:
				var path := str(mi.get_path())
				if wanted == "" or wanted in path.to_lower():
					var scale := mi.global_transform.basis.get_scale()
					var size: Vector3 = mi.get_aabb().size * scale
					var world := mi.global_position
					var metres := world.distance_to(camera.global_position)
					var on_screen := camera.is_position_in_frustum(world)
					var drawn_by_main := (mi.layers & camera.cull_mask) != 0
					print("  %-62s m=%6.2f  size=%-26s pos=%-30s on_screen=%s layers=0x%x main_draws=%s" % [
						path.substr(maxi(path.length() - 62, 0)),
						metres,
						str(size.snapped(Vector3(0.01, 0.01, 0.01))),
						str(world.snapped(Vector3(0.01, 0.01, 0.01))),
						str(on_screen),
						mi.layers,
						str(drawn_by_main),
					])
		_dump(child, camera, depth + 1)
