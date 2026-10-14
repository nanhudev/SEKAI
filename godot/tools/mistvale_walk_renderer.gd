# Render a RAW first-person walk of the imported UE5 town, south entry to north
# gate, for the integration brief's §59-§60.
#
# WHAT THIS IS NOT: a cinematic flythrough, a montage, or a camera on rails. The
# brief is explicit that the clip exists to SHOW whether the route connects, so
# the footage has to come from the real Player, driven through the real
# controller, over the real baked collision. So:
#
#   * the route walked is the centreline the level's own road surfaces define
#     (read from godot_walk_report.json), not a hand-typed path;
#   * the body is driven through the Player's own input actions, so
#     player_movement.gd does the walking -- its acceleration, its slope factor,
#     its move_and_slide against the baked mesh. Writing a position directly
#     would skip collision entirely and would prove nothing;
#   * the pace is walk_pace (0.55), i.e. 2.75 m/s, because the brief asks for a
#     natural walk of 3-6 minutes rather than a sprint;
#   * nothing is hidden except the debug overlays. The HUD stays, because a walk
#     that needs the UI removed to look right is a walk with something to hide.
#
# TIMING: captured in REAL TIME and the measured rate is written to fps.txt for
# the encoder, exactly as combat_movie_renderer.gd does. A pinned clock would
# desync the character controller from the physics it is walking on.
#
# Usage:
#   godot --path godot --resolution 1280x720 --audio-driver Dummy \
#         --script res://tools/mistvale_walk_renderer.gd -- <out_dir> [stride] [max_seconds]

extends SceneTree

const ROUTE_JSON := "F:/SEKAI/ue5_lab/Mistvale_Rebuild/_handoff/godot_walk_report.json"
const PLAYER_PATH := "Player"
const CAMERA_PATH := "Player/CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D"

## The walk starts this far in from the route's southern end, so frame 1 already
## shows the road ahead rather than the map's edge polygon.
const START_INSET := 6.0
## Advance to the next route sample within this radius.
const REACHED := 1.6
## Max yaw change per second. The route bends; the head should follow it, not
## snap to it.
const TURN_RATE := 140.0
## A frame is captured every `stride` drawn frames. Higher = smaller clip.
const DEFAULT_STRIDE := 2
const MAX_SECONDS_DEFAULT := 900.0

var output_dir := ""
var stride := DEFAULT_STRIDE
var max_seconds := MAX_SECONDS_DEFAULT
var frame_index := 0
var route: Array = []
var player: CharacterBody3D
var window: Window
var started_usec := 0
var walk_started_usec := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("NO VERDICT: needs an output dir as the first argument")
		quit(1)
		return
	output_dir = args[0]
	stride = int(args[1]) if args.size() > 1 else DEFAULT_STRIDE
	max_seconds = float(args[2]) if args.size() > 2 else MAX_SECONDS_DEFAULT
	DirAccess.make_dir_recursive_absolute(output_dir)
	_clear_existing_frames()
	_run()


func _clear_existing_frames() -> void:
	var dir := DirAccess.open(output_dir)
	if dir == null:
		return
	for file in dir.get_files():
		if file.get_extension().to_lower() == "png" or file == "fps.txt":
			dir.remove(file)


func _run() -> void:
	window = root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# A covered window stops firing frame_post_draw and the capture loop hangs
	# forever -- the same trap the combat and Iaido renderers document.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	# --- the real door ------------------------------------------------------
	var packed := load("res://scenes/main/Main.tscn") as PackedScene
	if packed == null:
		printerr("NO VERDICT: cannot load Main.tscn")
		quit(1)
		return
	var main := packed.instantiate()
	window.add_child(main)
	await process_frame
	main.main_menu.region_pressed.emit()

	# Wait for the STATE, not a frame count: start_region() awaits two process
	# frames and the world's _ready() awaits two physics frames before it places
	# the player, so "the world exists" is not "the player is on the road".
	var world: Node3D = null
	for _i in 600:
		await process_frame
		await physics_frame
		var candidate: Node3D = main.region_world
		if candidate == null or not candidate.has_node("Anchors"):
			continue
		var seen: Dictionary = candidate.call("report")
		if (seen.get("spawn_audit", {}) as Dictionary).is_empty():
			continue
		world = candidate
		break
	if world == null:
		printerr("NO VERDICT: the town never settled")
		quit(1)
		return
	player = world.get_node(PLAYER_PATH) as CharacterBody3D
	var camera := world.get_node_or_null(CAMERA_PATH) as Camera3D
	if player == null or camera == null:
		printerr("NO VERDICT: no player or camera in the mounted world")
		quit(1)
		return
	camera.current = true

	# --- the route the level defines ---------------------------------------
	route = _load_route()
	if route.size() < 10:
		printerr("NO VERDICT: route has only %d samples (is the walk report present?)"
			% route.size())
		quit(1)
		return
	var spawn: Dictionary = world.call("report")["spawn_audit"]
	print("WALK-FILM route=%d samples  spawn=(%.2f, %.2f, %.2f)"
		% [route.size(), spawn["x"], spawn["y"], spawn["z"]])

	# Start the route list at the first sample beyond the spawn, so the body is
	# not asked to walk backwards to a point it is already standing on.
	var index := 0
	while index < route.size() - 1 and route[index].z < float(spawn["z"]) + START_INSET:
		index += 1

	Input.action_press("move_forward")
	# walk_pace 0.55 of walk_speed 5.0 -> 2.75 m/s, i.e. ~4 minutes of footage for
	# the 667 m route. The brief asks for a 3-6 minute natural walk.
	Input.action_press("walk")

	started_usec = Time.get_ticks_usec()
	walk_started_usec = started_usec
	var travelled := 0.0
	var last_pos := player.global_position
	var drawn := 0
	var max_drift := 0.0

	while index < route.size():
		var elapsed := float(Time.get_ticks_usec() - walk_started_usec) / 1_000_000.0
		if elapsed > max_seconds:
			# This is the configured guard, not necessarily a failure: a short
			# max_seconds is how a smoke take is asked for. Say so, and let the
			# percentage below be the thing that says whether the walk worked.
			print("WALK-FILM stopping at the %.0f s guard, route index %d/%d"
				% [max_seconds, index, route.size()])
			break

		# Steer toward the current sample, then step. Physics does the movement.
		var target: Vector3 = route[index]
		var to := target - player.global_position
		to.y = 0.0
		if to.length() < REACHED:
			index += 1
			continue
		var want_yaw := atan2(-to.x, -to.z)
		player.rotation.y = _approach_angle(player.rotation.y, want_yaw,
			deg_to_rad(TURN_RATE) / 60.0)

		await _frame()
		drawn += 1

		var now_pos := player.global_position
		travelled += Vector2(now_pos.x - last_pos.x, now_pos.z - last_pos.z).length()
		last_pos = now_pos
		# How far the body wandered SIDEWAYS off the route it is following,
		# measured against the nearest sample in a window rather than against the
		# current target. Against the target it would report the START_INSET gap as
		# a 6 m deviation on frame one, which is not drift -- it is the distance to
		# the first waypoint.
		var lateral := INF
		for k in range(maxi(index - 12, 0), mini(index + 12, route.size())):
			var r: Vector3 = route[k]
			lateral = minf(lateral, Vector2(now_pos.x - r.x, now_pos.z - r.z).length())
		max_drift = maxf(max_drift, lateral)

		if drawn % stride == 0:
			await _save()
			if frame_index % 60 == 0:
				print("    frame %d  route %d/%d  %.0f s  travelled %.0f m"
					% [frame_index, index, route.size(), elapsed, travelled])

	# --- report and hand the true rate to the encoder ----------------------
	var seconds := float(Time.get_ticks_usec() - walk_started_usec) / 1_000_000.0
	var fps := float(frame_index) / maxf(seconds, 0.001)
	_write_fps(fps)
	var route_length := _polyline_length()
	print("WALK-FILM frames=%d  wall=%.1f s  measured_fps=%.4f" % [frame_index, seconds, fps])
	print("WALK-FILM travelled=%.1f m of %.1f m route (%.1f%%)  max_drift=%.2f m"
		% [travelled, route_length, 100.0 * travelled / maxf(route_length, 0.001), max_drift])
	print("WALK-FILM end=(%.2f, %.2f, %.2f)  index=%d/%d"
		% [player.global_position.x, player.global_position.y, player.global_position.z,
			index, route.size()])
	quit(0)


# Two frames: one to let physics land, one to land the drawn pose.
func _frame() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save() -> void:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("viewport returned no image at frame %d" % frame_index)
		return
	var err := image.save_png("%s/frame_%04d.png" % [output_dir, frame_index])
	if err != OK:
		push_error("save_png failed (%d) at frame %d" % [err, frame_index])
	frame_index += 1


## The centreline the walk tool derived from the level's own road surfaces. Read,
## never re-derived: the film and the audit must be looking at the same line, or
## the film cannot corroborate the audit.
func _load_route() -> Array:
	var text := FileAccess.get_file_as_string(ROUTE_JSON)
	if text.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return []
	var raw: Array = (parsed as Dictionary).get("centreline", [])
	var out: Array = []
	for item in raw:
		# JSON.stringify writes a Vector3 as "(x, y, z)".
		var s := String(item).replace("(", "").replace(")", "").replace(" ", "")
		var parts := s.split(",", false)
		if parts.size() != 3:
			continue
		out.append(Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float()))
	return out


func _polyline_length() -> float:
	var total := 0.0
	for i in range(1, route.size()):
		total += (route[i] - route[i - 1]).length()
	return total


## Shortest way round, so the head does not spin the long way at the +/-PI seam.
func _approach_angle(from: float, to: float, max_step: float) -> float:
	var diff := wrapf(to - from, -PI, PI)
	return from + clampf(diff, -max_step, max_step)


func _write_fps(fps: float) -> void:
	var file := FileAccess.open("%s/fps.txt" % output_dir, FileAccess.WRITE)
	if file == null:
		push_error("cannot write fps.txt -- the encoder will refuse this take")
		return
	file.store_string("%.4f\n" % fps)
	file.close()
