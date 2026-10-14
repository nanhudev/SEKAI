extends Node3D
## LIA CHARACTER TEST -- technical harness for the first SEKAI character.
##
## Loads the exported GLB, plays its idle animation and exposes the inspection
## tools needed to judge a character without entering Mistvale:
##   * orbit / zoom camera around a fixed chest-height pivot
##   * toggle a skeleton overlay (bone positions + parent links)
##   * cycle every animation clip found in the file
##   * optional offscreen capture for review sheets
##
## Everything is created in code so the .tscn stays trivial and cannot drift
## out of sync with the asset.

const GLB_PATH := "res://assets/characters/lia/lia_v3.glb"
const PIVOT := Vector3(0.0, 0.95, 0.0)

var _rig: Node3D
var _skel: Skeleton3D
var _player: AnimationPlayer
var _cam: Camera3D
var _skel_mesh: MeshInstance3D
var _hud: Label

var _yaw := 0.55
var _pitch := 0.10
var _dist := 3.4
var _dragging := false
var _show_skel := false
var _anim_names: PackedStringArray = []
var _anim_idx := 0
var _capture_path := ""
var _capture_frames := 40


func _ready() -> void:
	_parse_args()
	_build_environment()
	_build_camera()
	_build_hud()
	if _load_rig():
		_report()
	if _capture_path != "":
		_run_capture()


# ---------------------------------------------------------------- setup

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--capture" and i + 1 < args.size():
			_capture_path = args[i + 1]
		elif args[i] == "--capture-frames" and i + 1 < args.size():
			_capture_frames = int(args[i + 1])
		elif args[i] == "--yaw" and i + 1 < args.size():
			_yaw = float(args[i + 1])
		elif args[i] == "--pitch" and i + 1 < args.size():
			_pitch = float(args[i + 1])
		elif args[i] == "--dist" and i + 1 < args.size():
			_dist = float(args[i + 1])
		elif args[i] == "--skeleton":
			_show_skel = true


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.118, 0.129, 0.149)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.63, 0.72)
	env.ambient_light_energy = 0.42
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_energy = 1.05
	key.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	key.shadow_enabled = true
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.name = "RimLight"
	rim.light_energy = 0.35
	rim.light_color = Color(0.72, 0.80, 1.0)
	rim.rotation_degrees = Vector3(-20.0, 200.0, 0.0)
	add_child(rim)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "Camera3D"
	_cam.fov = 42.0
	_cam.current = true
	add_child(_cam)
	_update_camera()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 14)
	_hud.add_theme_color_override("font_color", Color(0.88, 0.90, 0.94))
	layer.add_child(_hud)


func _load_rig() -> bool:
	if not ResourceLoader.exists(GLB_PATH):
		push_error("[LIA] missing %s" % GLB_PATH)
		return false
	var packed := load(GLB_PATH) as PackedScene
	if packed == null:
		push_error("[LIA] %s did not load as a PackedScene" % GLB_PATH)
		return false
	_rig = packed.instantiate()
	add_child(_rig)

	var skels := _rig.find_children("*", "Skeleton3D", true, false)
	if skels.size() > 0:
		_skel = skels[0] as Skeleton3D
	var players := _rig.find_children("*", "AnimationPlayer", true, false)
	if players.size() > 0:
		_player = players[0] as AnimationPlayer
		_anim_names = _player.get_animation_list()
		if _anim_names.size() > 0:
			_player.play(_anim_names[0])
			_anim_idx = 0

	_skel_mesh = MeshInstance3D.new()
	_skel_mesh.name = "SkeletonOverlay"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.35, 0.35)
	mat.no_depth_test = true
	_skel_mesh.material_override = mat
	_skel_mesh.visible = _show_skel
	add_child(_skel_mesh)
	return true


func _report() -> void:
	var lines: PackedStringArray = []
	lines.append("LIA v3  |  %s" % GLB_PATH.get_file())
	if _skel:
		lines.append("bones: %d" % _skel.get_bone_count())
	else:
		lines.append("bones: NONE  <-- skin did not import")
	if _anim_names.size() > 0:
		lines.append("animations: %s" % ", ".join(_anim_names))
	else:
		lines.append("animations: NONE")
	lines.append("")
	lines.append("LMB drag orbit   wheel zoom   SPACE skeleton   TAB next anim   R reset")
	_hud.text = "\n".join(lines)
	print("[LIA] %s" % _hud.text.replace("\n", " | "))


# ---------------------------------------------------------------- camera

func _update_camera() -> void:
	if _cam == null:
		return
	var dir := Vector3(cos(_pitch) * sin(_yaw), sin(_pitch), cos(_pitch) * cos(_yaw))
	_cam.position = PIVOT + dir * _dist
	_cam.look_at(PIVOT, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = max(0.6, _dist - 0.25)
			_update_camera()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = min(9.0, _dist + 0.25)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.008
		_pitch = clamp(_pitch + mm.relative.y * 0.006, -1.1, 1.2)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				_toggle_skeleton()
			KEY_TAB:
				_next_animation()
			KEY_R:
				_yaw = 0.55
				_pitch = 0.10
				_dist = 3.4
				_update_camera()


func _toggle_skeleton() -> void:
	_show_skel = not _show_skel
	if _skel_mesh:
		_skel_mesh.visible = _show_skel


func _next_animation() -> void:
	if _player == null or _anim_names.size() == 0:
		return
	_anim_idx = (_anim_idx + 1) % _anim_names.size()
	_player.play(_anim_names[_anim_idx])
	_report()


# ---------------------------------------------------------------- skeleton overlay

func _process(_delta: float) -> void:
	if _show_skel and _skel != null:
		_draw_skeleton()


func _draw_skeleton() -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var xf := _skel.global_transform
	for i in _skel.get_bone_count():
		var origin := xf * _skel.get_bone_global_pose(i).origin
		var parent := _skel.get_bone_parent(i)
		if parent >= 0:
			var ppos := xf * _skel.get_bone_global_pose(parent).origin
			im.surface_add_vertex(origin)
			im.surface_add_vertex(ppos)
	im.surface_end()
	_skel_mesh.mesh = im


# ---------------------------------------------------------------- capture

func _run_capture() -> void:
	for i in _capture_frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_capture_path)
	print("[LIA-CAPTURE] %s -> %s (err=%d)" % [_capture_path, img.get_size(), err])
	get_tree().quit()
