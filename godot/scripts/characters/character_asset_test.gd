extends Node3D
## GENERIC CHARACTER ASSET INSPECTOR (SEKAI / CHARACTER line)
##
## Same harness idea as lia_character_test.gd, but parameterised so any GLB can be
## judged without writing a new scene: third-party packs, exports, WIP rigs.
##
## It is also the *verification* tool: with --report it dumps what Godot actually
## imported (bones, clips, materials, AABB, root scale) to JSON, so "it imported"
## becomes a checkable claim instead of a hope.
##
##   godot --path godot res://scenes/characters/CharacterAssetTest.tscn -- \
##        --glb res://assets/characters/x.glb --report out.json --capture a.png
##
## BATCH MODE: --report and --capture both exit on their own, so they can be
## dropped straight into a shell `for` loop. Add --stay only for hand inspection.
## For multi-view review sheets use --plan, which does every shot in ONE process:
##   --plan "idle:0.0:0.06:3.2:Idle:0.6;walk:0.75:0.08:3.2:Walk:0.5" \
##   --out-prefix /tmp/lpg_witch_w__
##
## CAST MODE renders a WHOLE ROSTER into one grid image in ONE process, so a
## 21-character overview costs one launch instead of twenty-one:
##   --cast-file cast.txt --cast-out /tmp/CAST.png --cast-cols 7 \
##   --resolution 360x480 --pivot-y 0.95 --dist 3.2 --cast-anim Idle
## cast.txt lines:  <name>|<res://path/to.glb>   (# comments and blanks ignored)
## The name is burnt into each cell via a Label, so the sheet is self-describing.
##
## BONE PROBE answers the one question every authored action has to answer:
## "is the foot actually on the ground?"  It plays the clip for real (no seeking),
## then prints the world-space Y of the contact bones plus the lowest bone overall.
##   --bone-probe "Idle:0.5;Sitting_Idle:0.6" --bones Hips,Foot.L,Toe.L
## A sit pose with hips at 0.59 m is sitting on a chair; at 0.20 m it is on the
## floor.  You cannot tell those apart from a screenshot -- you can from here.
##
## Interactive: LMB orbit / wheel zoom / SPACE skeleton / TAB next clip / R reset

const DEFAULT_GLB := "res://assets/characters/lia/lia_v3.glb"

# Contact-relevant bones, in the order a human would check them.  Feet first:
# if the feet are wrong nothing else matters.
const PROBE_BONES := [
	"Hips", "hips", "Pelvis", "Root",
	"Foot.L", "Foot.R", "Toe.L", "Toe.R",
	"LowerLeg.L", "LowerLeg.R", "UpperLeg.L", "UpperLeg.R",
	"Hand.L", "Hand.R", "Head",
]

var _glb := DEFAULT_GLB
var _report_path := ""
var _capture_path := ""
var _plan := ""
var _out_prefix := ""
var _capture_frames := 40
var _want_anim := ""
var _pivot_y := -1.0
var _cast_file := ""
var _cast_out := ""
var _cast_cols := 7
var _cast_anim := "Idle"
var _cast_phase := 0.45
var _bone_probe := ""
var _probe_bones := ""

var _rig: Node3D
var _skel: Skeleton3D
var _player: AnimationPlayer
var _cam: Camera3D
var _skel_mesh: MeshInstance3D
var _hud: Label
var _name_label: Label

var _yaw := 0.0
var _pitch := 0.08
var _dist := 3.0
var _stay := false
var _dragging := false
var _show_skel := false
var _anim_names: PackedStringArray = []
var _anim_idx := 0


func _ready() -> void:
	_parse_args()
	_build_environment()
	_build_camera()
	_build_hud()
	if _cast_file != "":
		_run_cast()
		return
	var ok := _load_asset()
	if _report_path != "":
		_write_report(ok)
	if _bone_probe != "":
		_run_bone_probe(ok)
		return
	if _plan != "":
		_run_plan()
		return
	if _capture_path != "":
		_run_capture()
		return
	# BATCH GUARD: without this the report run falls through to interactive mode and
	# never exits, deadlocking any `for` loop that calls it. `--stay` opts back in.
	if _report_path != "" and not _stay:
		get_tree().quit(0 if ok else 1)
		return
	if not ok:
		get_tree().quit(1)


# ---------------------------------------------------------------- args

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--glb":
				if i + 1 < args.size():
					_glb = args[i + 1]
			"--report":
				if i + 1 < args.size():
					_report_path = args[i + 1]
			"--capture":
				if i + 1 < args.size():
					_capture_path = args[i + 1]
			"--plan":
				if i + 1 < args.size():
					_plan = args[i + 1]
			"--out-prefix":
				if i + 1 < args.size():
					_out_prefix = args[i + 1]
			"--capture-frames":
				if i + 1 < args.size():
					_capture_frames = int(args[i + 1])
			"--anim":
				if i + 1 < args.size():
					_want_anim = args[i + 1]
			"--pivot-y":
				if i + 1 < args.size():
					_pivot_y = float(args[i + 1])
			"--yaw":
				if i + 1 < args.size():
					_yaw = float(args[i + 1])
			"--pitch":
				if i + 1 < args.size():
					_pitch = float(args[i + 1])
			"--dist":
				if i + 1 < args.size():
					_dist = float(args[i + 1])
			"--skeleton":
				_show_skel = true
			"--cast-file":
				if i + 1 < args.size():
					_cast_file = args[i + 1]
			"--cast-out":
				if i + 1 < args.size():
					_cast_out = args[i + 1]
			"--cast-cols":
				if i + 1 < args.size():
					_cast_cols = maxi(1, int(args[i + 1]))
			"--cast-anim":
				if i + 1 < args.size():
					_cast_anim = args[i + 1]
			"--cast-phase":
				if i + 1 < args.size():
					_cast_phase = float(args[i + 1])
			"--bone-probe":
				if i + 1 < args.size():
					_bone_probe = args[i + 1]
			"--bones":
				if i + 1 < args.size():
					_probe_bones = args[i + 1]
			"--stay":
				_stay = true


# ---------------------------------------------------------------- scene

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


func _pivot() -> Vector3:
	return Vector3(0.0, _pivot_y if _pivot_y >= 0.0 else 0.95, 0.0)


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

	# Cast-mode caption. Burnt into the frame by the viewport capture, so the
	# roster image needs no external labelling step (and cannot drift from it).
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	_name_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08))
	_name_label.add_theme_constant_override("outline_size", 6)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.visible = false
	layer.add_child(_name_label)


# ---------------------------------------------------------------- load

func _load_asset() -> bool:
	if not ResourceLoader.exists(_glb):
		push_error("[CHARTEST] missing %s" % _glb)
		return false
	var packed := load(_glb) as PackedScene
	if packed == null:
		push_error("[CHARTEST] %s is not a PackedScene" % _glb)
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
		_anim_idx = _pick_anim()
		if _anim_names.size() > 0:
			_player.play(_anim_names[_anim_idx])

	if _pivot_y < 0.0:
		var aabb := _visual_aabb()
		_pivot_y = aabb.position.y + aabb.size.y * 0.55
		_dist = max(1.8, aabb.size.y * 1.85)
		_update_camera()

	_skel_mesh = MeshInstance3D.new()
	_skel_mesh.name = "SkeletonOverlay"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.35, 0.35)
	mat.no_depth_test = true
	_skel_mesh.material_override = mat
	_skel_mesh.visible = _show_skel
	add_child(_skel_mesh)

	_report()
	return true


func _pick_anim() -> int:
	if _want_anim == "":
		# prefer a loop that reads as "alive"
		for want in ["Idle_Loop", "Idle", "A_TPose"]:
			var i := _anim_names.find(want)
			if i >= 0:
				return i
		return 0
	var idx := _anim_names.find(_want_anim)
	if idx >= 0:
		return idx
	if _want_anim.is_valid_int():
		return clampi(int(_want_anim), 0, maxi(0, _anim_names.size() - 1))
	return 0


func _visual_aabb() -> AABB:
	var out := AABB()
	var first := true
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var box := m.global_transform * m.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


func _report() -> void:
	var lines: PackedStringArray = []
	lines.append("%s" % _glb.get_file())
	lines.append("bones: %s" % (_skel.get_bone_count() if _skel else "NONE  <-- skin did not import"))
	if _anim_names.size() > 0:
		lines.append("clips: %d  (TAB to cycle)" % _anim_names.size())
		lines.append("now: %s" % _anim_names[_anim_idx])
	else:
		lines.append("clips: NONE")
	if _skel:
		var longest := ""
		var best := 0
		for i in _skel.get_bone_count():
			var n := _skel.get_bone_name(i)
			if n.length() > best:
				best = n.length()
				longest = n
		lines.append("longest bone name: %s" % longest)
	lines.append("")
	lines.append("LMB orbit  wheel zoom  SPACE skeleton  TAB clip  R reset")
	_hud.text = "\n".join(lines)
	print("[CHARTEST] %s" % _hud.text.replace("\n", " | "))


func _write_report(ok: bool) -> void:
	var bones: Array = []
	if _skel:
		for i in _skel.get_bone_count():
			bones.append(_skel.get_bone_name(i))
	var clips: Array = []
	for n in _anim_names:
		var a := _player.get_animation(n)
		clips.append({"name": n, "length": a.length, "tracks": a.get_track_count()})
	var meshes: Array = []
	for mi in _rig.find_children("*", "MeshInstance3D", true, false) if _rig else []:
		var m := mi as MeshInstance3D
		if m.mesh:
			meshes.append({"name": m.name, "surfaces": m.mesh.get_surface_count(),
					"tris": m.mesh.get_faces().size() / 3})
	var aabb := _visual_aabb() if _rig else AABB()
	var nodes: Array = []
	if _rig:
		for mi in _rig.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			nodes.append({"name": String(m.name), "pos": [m.global_position.x, m.global_position.y, m.global_position.z],
					"visible": m.visible, "visible_in_tree": m.is_visible_in_tree(),
					"scale": [m.global_transform.basis.x.length(), m.global_transform.basis.y.length(), m.global_transform.basis.z.length()]})
	var out := {
		"glb": _glb,
		"loaded": ok,
		"bones": bones.size(),
		"bone_names": bones,
		"clips": clips,
		"meshes": meshes,
		"aabb_pos": [aabb.position.x, aabb.position.y, aabb.position.z],
		"aabb_size": [aabb.size.x, aabb.size.y, aabb.size.z],
		"camera_pos": [_cam.global_position.x, _cam.global_position.y, _cam.global_position.z] if _cam else [],
		"pivot_y": _pivot_y,
		"dist": _dist,
		"mesh_nodes": nodes,
	}
	var f := FileAccess.open(_report_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
		print("[CHARTEST-REPORT] %s  bones=%d clips=%d" % [_report_path, bones.size(), clips.size()])


# ---------------------------------------------------------------- camera / input

func _update_camera() -> void:
	if _cam == null:
		return
	var dir := Vector3(cos(_pitch) * sin(_yaw), sin(_pitch), cos(_pitch) * cos(_yaw))
	_cam.position = _pivot() + dir * _dist
	_cam.look_at(_pivot(), Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = max(0.5, _dist - 0.25)
			_update_camera()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = min(12.0, _dist + 0.25)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.008
		_pitch = clamp(_pitch + mm.relative.y * 0.006, -1.1, 1.2)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				_show_skel = not _show_skel
				if _skel_mesh:
					_skel_mesh.visible = _show_skel
			KEY_TAB:
				if _player and _anim_names.size() > 0:
					_anim_idx = (_anim_idx + 1) % _anim_names.size()
					_player.play(_anim_names[_anim_idx])
					_report()
			KEY_R:
				_yaw = 0.0
				_pitch = 0.08
				_update_camera()


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
			im.surface_add_vertex(origin)
			im.surface_add_vertex(xf * _skel.get_bone_global_pose(parent).origin)
	im.surface_end()
	_skel_mesh.mesh = im


# ---------------------------------------------------------------- bone probe

# World-space bone heights for one or more (clip, phase) pairs.
#
# Ground contact is the only thing that separates "sitting on a crate" from
# "sitting on a chair", and a still image cannot tell you which you have -- but a
# number can.  Always probe a standing clip FIRST: that gives the rig's own
# contact baseline (these rigs put the foot bone ~7 cm above the sole), and every
# later number is read as a delta against it.
func _run_bone_probe(ok: bool) -> void:
	if not ok or _skel == null:
		print("[CHARTEST-BONE] no skeleton loaded; cannot probe")
		get_tree().quit(1)
		return

	var wanted: PackedStringArray = PackedStringArray(PROBE_BONES)
	if _probe_bones != "":
		wanted = PackedStringArray()
		for n in _probe_bones.split(",", false):
			wanted.append(n.strip_edges())

	var idx_of := {}
	for i in _skel.get_bone_count():
		idx_of[_skel.get_bone_name(i)] = i
	var present: Array = []
	for n in wanted:
		if idx_of.has(n):
			present.append(n)
	if present.is_empty():
		print("[CHARTEST-BONE] none of the requested bones exist; rig has %d bones" % _skel.get_bone_count())
		get_tree().quit(1)
		return

	var scale := _skel.global_transform.basis.get_scale()
	print("[CHARTEST-BONE] %s  skeleton_scale=%.4f" % [_glb.get_file(), scale.y])

	for spec in _bone_probe.split(";", false):
		var f := spec.split(":")
		var clip := f[0]
		var phase := float(f[1]) if f.size() > 1 else 0.0
		var played: String = await _play_and_advance(clip, phase)
		await get_tree().process_frame

		var xf := _skel.global_transform
		var lowest_name := ""
		var lowest_y := 1e9
		for i in _skel.get_bone_count():
			var p: Vector3 = xf * _skel.get_bone_global_pose(i).origin
			if p.y < lowest_y:
				lowest_y = p.y
				lowest_name = _skel.get_bone_name(i)

		var parts: Array = []
		for n in present:
			var p: Vector3 = xf * _skel.get_bone_global_pose(idx_of[n]).origin
			parts.append("%s y=%+.4f" % [n, p.y])
		print("[CHARTEST-BONE] req=%-20s played=%-20s t=%.2f" % [spec, played, _player.current_animation_position])
		print("[CHARTEST-BONE]    %s" % "  ".join(parts))
		print("[CHARTEST-BONE]    lowest_bone=%s y=%+.4f" % [lowest_name, lowest_y])
	get_tree().quit(0)


# ---------------------------------------------------------------- capture

func _run_capture() -> void:
	for i in _capture_frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_capture_path)
	print("[CHARTEST-CAPTURE] %s %s err=%d" % [_capture_path, img.get_size(), err])
	get_tree().quit()


# Batch mode: one process, one asset load, N camera/clip combinations. Launching
# Godot per view costs ~85 s of startup + first-frame compile each, so a 6-view
# review sheet drops from ~9 min to well under one.
#
#   --plan "name:yaw:pitch:dist:clip:phase;name2:..."
#   --out-prefix /path/to/<char>__
#
# `phase` is the time in seconds the clip must PLAY to before the shot. It is
# reached by honest frame stepping, not by seeking -- jumping the clock produces
# a pose the game would never actually show.
func _run_plan() -> void:
	var specs := _plan.split(";", false)
	var shot := 0
	var bad := 0
	for spec in specs:
		var f := spec.split(":")
		if f.size() < 5:
			push_warning("[CHARTEST] bad plan entry (want name:yaw:pitch:dist:clip[:phase]): %s" % spec)
			bad += 1
			continue
		var view_name := f[0]
		_yaw = float(f[1])
		_pitch = float(f[2])
		_dist = float(f[3])
		var clip := f[4]
		var phase := float(f[5]) if f.size() > 5 else 0.0
		_update_camera()

		var played: String = await _play_and_advance(clip, phase)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s%s.png" % [_out_prefix, view_name]
		var err := img.save_png(path)
		print("[CHARTEST-PLAN] %-14s clip=%-16s played=%-5s %s err=%d"
				% [view_name, clip, played, img.get_size(), err])
		if err != OK:
			bad += 1
		else:
			shot += 1
	print("[CHARTEST-PLAN-DONE] %d/%d views -> %s" % [shot, specs.size(), _out_prefix])
	get_tree().quit(0 if bad == 0 and shot > 0 else 1)


# Returns the clip name actually played, or "<none>" if the request missed.
func _play_and_advance(clip: String, phase: float) -> String:
	if _player == null or _anim_names.size() == 0:
		push_warning("[CHARTEST] no AnimationPlayer/clips on this asset")
		return "<none>"
	var idx := _anim_names.find(clip)
	if idx < 0 and clip.is_valid_int():
		idx = clampi(int(clip), 0, _anim_names.size() - 1)
	if idx < 0:
		# Never silently keep the previous clip -- that is how a review sheet ends
		# up showing the same idle six times while claiming six different clips.
		push_warning("[CHARTEST] no clip named '%s'" % clip)
		return "<none>"
	_anim_idx = idx
	var name := _anim_names[idx]
	_player.play(name)
	var guard := 0
	while _player.current_animation_position < phase and guard < 900:
		await get_tree().process_frame
		guard += 1
	return name


# ---------------------------------------------------------------- cast (roster sheet)

# One process, N assets, one grid PNG. The cell size IS the viewport size, and the
# sheet is assembled with Image.blit_rect, so the grid is composited without any
# image library and without a second tool that could disagree with the renders.
func _run_cast() -> void:
	var entries := _read_cast_list()
	if entries.is_empty():
		# stdout as well as push_error: the calling shell pipeline filters stdout,
		# so a push_error alone leaves the operator with "FAILED" and no reason.
		print("[CHARTEST-CAST-FAIL] no entries in '%s'  (FileAccess resolves a relative path against the PROJECT ROOT, not the shell CWD)" % _cast_file)
		push_error("[CHARTEST-CAST] no entries in %s" % _cast_file)
		get_tree().quit(1)
		return
	_hud.visible = false

	var cw := int(get_viewport().get_visible_rect().size.x)
	var ch := int(get_viewport().get_visible_rect().size.y)
	if cw <= 0 or ch <= 0:
		print("[CHARTEST-CAST-FAIL] viewport has no size; pass --resolution WxH")
		push_error("[CHARTEST-CAST] viewport has no size; pass --resolution WxH")
		get_tree().quit(1)
		return
	var cols := mini(_cast_cols, entries.size())
	var rows := int(ceil(float(entries.size()) / float(cols)))
	var sheet := Image.create(cols * cw, rows * ch, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.09, 0.10, 0.118))

	_name_label.size = Vector2(cw, 34)
	_name_label.position = Vector2(0, ch - 40)
	_name_label.visible = true

	var drawn := 0
	var failed: PackedStringArray = []
	for i in entries.size():
		var e: Dictionary = entries[i]
		_cast_drop_rig()
		_glb = e["path"]
		var ok := _load_asset()
		if not ok:
			failed.append("%s (load)" % e["name"])
			continue
		var played: String = await _play_and_advance(_cast_anim, _cast_phase)
		if played == "<none>":
			failed.append("%s (%s)" % [e["name"], _cast_anim])
		_name_label.text = str(e["name"])
		# Two frames: one for the rig swap to settle, one for the label to lay out.
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img.get_width() != cw or img.get_height() != ch:
			img.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, cw, ch), Vector2i((i % cols) * cw, (i / cols) * ch))
		drawn += 1
		print("[CHARTEST-CAST] %2d/%d  %-18s clips=%-3d %s" %
				[i + 1, entries.size(), e["name"], _anim_names.size(), played])

	var err := sheet.save_png(_cast_out)
	print("[CHARTEST-CAST-DONE] %d/%d drawn  grid=%dx%d cell=%dx%d  %s  err=%d"
			% [drawn, entries.size(), cols, rows, cw, ch, _cast_out, err])
	if failed.size() > 0:
		print("[CHARTEST-CAST-FAILED] %s" % ", ".join(failed))
	get_tree().quit(0 if drawn == entries.size() and err == OK else 1)


func _read_cast_list() -> Array:
	var out: Array = []
	if not FileAccess.file_exists(_cast_file):
		return out
	var f := FileAccess.open(_cast_file, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var parts := line.split("|", false, 1)
		if parts.size() < 2:
			continue
		out.append({"name": parts[0].strip_edges(), "path": parts[1].strip_edges()})
	f.close()
	return out


func _cast_drop_rig() -> void:
	for n in [_skel_mesh, _rig]:
		if n != null and is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_rig = null
	_skel = null
	_player = null
	_skel_mesh = null
	_anim_names = PackedStringArray()
