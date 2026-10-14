# Stills of the imported town: the §61 overview, plus look-check shots at POIs.
#
# WHY A FREE CAMERA IS ALLOWED HERE AND NOT IN THE FILM: the brief asks for one
# slightly elevated view of the whole town STRUCTURE, which is a statement about
# layout rather than about what a player sees. The walk clip is the opposite --
# it must be first person through the real Player -- and tools/mistvale_walk_
# renderer.gd is what produces that. The two are not interchangeable.
#
# The look-check shots exist because "the town renders" is not the same claim as
# "the town reads at eye level". Each is taken from a real anchor's position and
# yaw, at the player's own eye height, so what they show is what the player sees
# standing there.
#
# Usage:
#   godot --path godot --resolution 1600x900 --audio-driver Dummy \
#         --script res://tools/mistvale_map_shot.gd -- <out_dir>

extends SceneTree

const SCENE := "res://scenes/world/MistvalePlayable.tscn"
const EYE := 1.65
## Actors that are not the town proper.
## The terrain is the ground the town sits on, so framing the town must not frame
## 700 m of valley. The route ribbons are worse: they run the full 650 m of the
## map, so including them framed the whole map and produced a still in which the
## town was a smudge in the middle of a lawn. The town STRUCTURE the brief asks
## for is the buildings and the plazas, so that is what gets framed.
const NOT_TOWN := ["ART_Graded_Terrain_Proxy", "River_Continuous", "Route_", "River"]

var out_dir := ""
var world: Node3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "F:/SEKAI/.render/mistvale_look"
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _run() -> void:
	var window: Window = root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var packed := load(SCENE) as PackedScene
	if packed == null:
		printerr("NO VERDICT: cannot load ", SCENE)
		quit(1)
		return
	world = packed.instantiate() as Node3D
	window.add_child(world)
	for _i in 30:
		await process_frame
		await physics_frame

	var art := world.get_node_or_null("Art") as Node3D
	if art == null:
		printerr("NO VERDICT: no Art")
		quit(1)
		return

	# The HUD and the Iaido/screen layers are CanvasLayers, so they draw from any
	# camera. A layout still with a weapon-select chip in the corner is a still
	# with something in the corner. Recursive, because CombatHUD is an instanced
	# scene and its panel is not necessarily a direct child of the world.
	_hide_canvas_layers(world)

	var boxes := _town_boxes(art)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for b in boxes:
		var aabb: AABB = b["aabb"]
		lo = lo.min(aabb.position)
		hi = hi.max(aabb.position + aabb.size)
	var centre := (lo + hi) * 0.5
	var size := hi - lo
	print("SHOT town bbox  x[%.1f, %.1f] y[%.1f, %.1f] z[%.1f, %.1f]  size=%s"
		% [lo.x, hi.x, lo.y, hi.y, lo.z, hi.z, str(size)])

	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 42.0
	camera.far = 4000.0

	# --- the §61 deliverable: whole-town structure, slightly elevated ---------
	# Oblique from the south-east, because the town runs north along the river and
	# a due-south camera would stack every roof behind the one in front of it.
	#
	# The elevation is a compromise with the sky. The graded terrain is a finite
	# 504 x 706 m proxy, so any high camera eventually looks past its edge at the
	# procedural sky's lower hemisphere; when that hemisphere was near-black it
	# read as a void and made the town look like it was floating. The scene now
	# carries a hazy lower hemisphere (see SkyMaterial_mistvale) and this angle
	# keeps the slab's edge low in frame, where the fog blurs it into distance.
	# Measured: 0.78 x diagonal gave a top-of-frame void, 0.60 x diagonal cropped
	# the town to its centre.
	var diag := size.length()
	var eye := centre + Vector3(0.42, 0.72, -0.95).normalized() * (diag * 0.90)
	camera.fov = 48.0
	camera.global_position = eye
	camera.look_at(centre + Vector3(0, -12, 0), Vector3.UP)
	await _shoot(camera, "mistvale_playable_map_v1", true)
	print("SHOT overview eye=%s look_at=%s" % [str(eye), str(centre)])

	# --- look-checks: what the player sees standing at each POI --------------
	var anchors := world.get_node_or_null("Anchors")
	if anchors != null:
		for spec in [
			{"name": "POI_SouthEntry", "look": "POI_MainBridge"},
			{"name": "POI_Riverside", "look": "POI_MainBridge"},
			{"name": "POI_MainBridge", "look": "POI_NorthGate"},
			{"name": "POI_Market", "look": "POI_Guild"},
			{"name": "POI_Guild", "look": "POI_Church"},
			{"name": "POI_Church", "look": "POI_NorthGate"},
			{"name": "POI_NorthGate", "look": "TRG_NorthGateExit"},
		]:
			var here := anchors.get_node_or_null(str(spec["name"])) as Node3D
			var there := anchors.get_node_or_null(str(spec["look"])) as Node3D
			if here == null or there == null:
				continue
			camera.global_position = here.position + Vector3(0, EYE, 0)
			var aim := there.position + Vector3(0, EYE * 0.6, 0)
			if camera.global_position.distance_to(aim) < 1.0:
				aim += Vector3(0, 0, 1)
			camera.look_at(aim, Vector3.UP)
			await _shoot(camera, "look_%s" % spec["name"], false)
			print("SHOT %s -> %s" % [spec["name"], spec["look"]])
	quit(0)


func _hide_canvas_layers(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	for child in node.get_children():
		_hide_canvas_layers(child)


func _town_boxes(art: Node3D) -> Array:
	var out: Array = []
	for node in art.find_children("*", "MeshInstance3D", true, false):
		var name := str(node.name)
		var skip := false
		for token in NOT_TOWN:
			if token in name:
				skip = true
				break
		if skip:
			continue
		var mi := node as MeshInstance3D
		out.append({"name": name, "aabb": mi.global_transform * mi.get_aabb()})
	return out


## Wait for the drawn frame, not for a timer: the camera has been moved, and a
## capture taken before the move lands in the render reads the previous view.
func _shoot(camera: Camera3D, name: String, jpg: bool) -> void:
	camera.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		push_error("no image for %s" % name)
		return
	if jpg:
		var path := "%s/%s.jpg" % [out_dir, name]
		var err := image.save_jpg(path, 0.92)
		if err != OK:
			push_error("save_jpg failed (%d) for %s" % [err, path])
		else:
			print("SHOT wrote %s  %dx%d" % [path, image.get_width(), image.get_height()])
	else:
		image.save_png("%s/%s.png" % [out_dir, name])
