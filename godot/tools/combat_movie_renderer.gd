extends SceneTree
##
## Renders a scripted tour of the combat matrix into a PNG sequence, so the
## new systems can actually be WATCHED instead of inferred from green tests.
##
## The Iaido renderer pins its timeline with an explicit debug-hold because that
## ceremony is a fixed script. Combat is not: moves are driven by input, windows
## by wall clock (`CombatController._now()` reads Time.get_ticks_msec()), and a
## pinned clock would desync the two. So this one runs in REAL TIME and measures
## how much game time each captured frame actually covered, then hands the
## resulting frame rate to the encoder. That way the clip plays back at true
## speed no matter how fast this machine happens to render.
##
## Engine.time_scale is deliberately left alone: it scales `delta` (which drives
## animation and move progression) but NOT `_now()` (which drives riposte /
## bind / chain windows). Touching it would make the animation and the windows
## disagree on screen, which is exactly the kind of thing this video exists to
## expose, not to hide.
##
## Usage:
##   godot --path godot --resolution 1280x720 --audio-driver Dummy \
##         --script res://tools/combat_movie_renderer.gd -- <output_dir>

const OUT_DEFAULT := "res://../.render/combat"
const PLAYER_Y := 1.15
const DUMMY_DROP := 0.55      # dummy origin is below the player's eye line
const SETTLE := 0.7           # quiet beat at the top of every segment

var output_dir := ""
var frame_index := 0
var sandbox: Node3D
var player: CharacterBody3D
var combat: CombatController
var dummy: Node3D
var look_pivot: Node3D
var props: WindProps

var layer: CanvasLayer
var title_label: Label
var status_label: Label
var note_label: Label
# A first-person shot of a 1.8m placeholder cone from 2m away is a wall of white,
# which makes every claim about the blade unverifiable. This camera sits at three
# quarters and reads the pair from outside. It is safe to do because the sword is
# parented to the player's own camera rig, so the pose keys — which are written in
# camera space — still describe the player's view, not the review camera's.
var review_camera: Camera3D

var segments: Array = []
var seg_name := ""
var seg_note := ""
# Tight by default; the takes that have to show a wall or a thrown crate widen it.
var seg_fov := 38.0
var start_ms := 0
# Every bind segment reports whether the real hurtbox path actually produced a
# perfect guard. A demo that quietly faked it would be worse than no demo.
var parry_landed := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	output_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path(OUT_DEFAULT)
	# Rendering the whole tour to check one framing change costs a full minute,
	# so a take count and a start index make the loop short.
	var max_segments := int(args[1]) if args.size() > 1 else 999
	var start_segment := int(args[2]) if args.size() > 2 else 0
	DirAccess.make_dir_recursive_absolute(output_dir)
	_clear_existing_frames()

	var window: Window = root
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	# Same reason as the Iaido renderer: a covered window stops firing
	# frame_post_draw and the capture loop hangs forever.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)

	sandbox = load("res://scenes/combat/CombatSandbox.tscn").instantiate() as Node3D
	window.add_child(sandbox)

	await process_frame
	await process_frame
	await process_frame

	player = sandbox.get_node("Player") as CharacterBody3D
	combat = player.get_node("CombatController") as CombatController
	dummy = sandbox.get_node("TechnicalDummy") as Node3D
	look_pivot = player.get_node("CameraRig/LookPivot") as Node3D
	props = sandbox.get_node("WindProps") as WindProps

	# The Lab and the HUD belong to the person playing, not to the recording.
	_hide(&"DeveloperPanel")
	_hide(&"ParryDebugOverlay")
	_hide(&"CombatHUD")
	# The foreground weapon layer exists to keep the blade from clipping into the
	# world in first person. From three quarters it draws a second sword floating
	# over the shot, so it goes too.
	_hide(&"ForegroundWeaponLayer")
	player.unlimited_resources = true
	# The dummy attacking on its own would poison every take that is not about
	# being attacked.
	dummy.set("attack_cooldown", 9999.0)

	_build_overlay()
	_build_segments()
	_build_review_camera()

	print("window=", root.size, "  segments=", segments.size())
	print("rendering combat tour to: ", output_dir)

	start_ms = Time.get_ticks_msec()
	for i in range(start_segment, mini(segments.size(), start_segment + max_segments)):
		await _run_segment(segments[i])

	var elapsed := float(Time.get_ticks_msec() - start_ms) / 1000.0
	var fps := float(frame_index) / maxf(elapsed, 0.001)
	print("frames=%d  wall=%.2fs  -> ENCODE_FPS=%.3f" % [frame_index, elapsed, fps])
	_write_fps(fps)
	quit()


func _hide(node_name: StringName) -> void:
	var node := sandbox.get_node_or_null(NodePath(String(node_name)))
	if node is CanvasLayer or node is Control:
		(node as Node).set("visible", false)


# --- segments ---------------------------------------------------------------

func _build_segments() -> void:
	# A take is: name, setup, [time, action] pairs, duration.
	segments = [
		{
			"name": "通用剑 · 四段连击",
			"setup": func() -> void:
				_clean_arena(&"universal")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.1),
			"events": [
				[SETTLE + 0.10, _req.bind(&"light")],
				[SETTLE + 0.55, _req.bind(&"light")],
				[SETTLE + 1.00, _req.bind(&"light")],
				[SETTLE + 1.45, _req.bind(&"light")],
				[SETTLE + 2.60, _req.bind(&"heavy")],
			],
			"duration": SETTLE + 4.4,
		},
		{
			"name": "回风式 · 四段链 + 势(Flow)",
			"setup": func() -> void:
				_clean_arena(&"flowing_wind")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.2),
			"events": [
				[SETTLE + 0.10, _req.bind(&"light")],
				[SETTLE + 0.50, _req.bind(&"light")],
				[SETTLE + 0.90, _req.bind(&"light")],
				[SETTLE + 1.30, _req.bind(&"light")],
				[SETTLE + 2.60, _req.bind(&"light")],
			],
			"duration": SETTLE + 4.4,
		},
		{
			"name": "藏锋流 · 拔刀红利 → 截锋",
			"note": "纳刀状态下出刀更快、更重；完美格挡后归鞘前摇被免除",
			"setup": func() -> void:
				_clean_arena(&"hidden_edge")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 1.9),
			"events": [
				[SETTLE + 0.10, _req.bind(&"light")],
				[SETTLE + 1.60, _req.bind(&"light")],
				[SETTLE + 2.00, _req.bind(&"light")],
				[SETTLE + 3.30, _guard_up],
				[SETTLE + 3.36, _enemy_hit_on],
				[SETTLE + 3.44, _enemy_hit_off],
			],
			"duration": SETTLE + 5.0,
		},
		{
			"name": "白蔷庭 · Measure 近 / 理想 / 远",
			"note": "同一招「穿庭」在三个距离上的削势差异 —— 伤害完全相同",
			"setup": func() -> void:
				_clean_arena(&"white_rose")
				_move_pair(Vector3(0.0, PLAYER_Y, -0.6), 1.1),
			"events": [
				[SETTLE + 0.20, _req.bind(&"heavy")],
				[SETTLE + 1.60, _move_pair.bind(Vector3(0.0, PLAYER_Y, -0.6), 2.3)],
				[SETTLE + 2.30, _req.bind(&"heavy")],
				[SETTLE + 3.70, _move_pair.bind(Vector3(0.0, PLAYER_Y, -0.6), 4.0)],
				[SETTLE + 4.40, _req.bind(&"heavy")],
			],
			"duration": SETTLE + 6.2,
		},
		{
			"name": "白蔷庭 · 缠剑 BIND → 轻 = 合围刺",
			"note": "完美格挡不弹开、不侧移；剑被锁住 0.3s，之后由玩家决定",
			"setup": func() -> void:
				_clean_arena(&"white_rose")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.0),
			"events": [
				[SETTLE + 0.60, _guard_up],
				[SETTLE + 0.66, _enemy_hit_on],
				[SETTLE + 0.74, _enemy_hit_off],
				[SETTLE + 1.05, _req.bind(&"light")],
			],
			"duration": SETTLE + 3.6,
		},
		{
			"name": "白蔷庭 · 缠剑 BIND → 重 = 脱手斩",
			"note": "同一个缠剑，另一个答案：向后脱离，不在原地换血",
			"setup": func() -> void:
				_clean_arena(&"white_rose")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.0),
			"events": [
				[SETTLE + 0.60, _guard_up],
				[SETTLE + 0.66, _enemy_hit_on],
				[SETTLE + 0.74, _enemy_hit_off],
				[SETTLE + 1.05, _req.bind(&"heavy")],
			],
			"duration": SETTLE + 3.6,
		},
		{
			"name": "白蔷庭 · 假章（起手里收回的假动作）",
			"note": "上半段是假章被提前取消，下半段是真招穿庭，两者起手应当难以分辨",
			"setup": func() -> void:
				_clean_arena(&"white_rose")
				_place(Vector3(0.0, PLAYER_Y, -0.6), 2.3),
			"events": [
				[SETTLE + 0.20, _trigger_skill.bind(0)],
				[SETTLE + 0.42, _req.bind(&"light")],
				[SETTLE + 2.30, _req.bind(&"heavy")],
			],
			"duration": SETTLE + 4.0,
		},
		{
			"name": "火 · 火场与燃烧",
			"note": "火不是一发伤害：它留下一片区域，并让目标持续、不规则地烧",
			"setup": func() -> void:
				_clean_arena(&"universal")
				combat.select_school(&"fire")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.4),
			"events": [
				[SETTLE + 0.20, _req.bind(&"cast")],
			],
			"duration": SETTLE + 4.0,
		},
		{
			"name": "冰 · 累积四阶 → 冻结",
			"note": "普通 / 冰寒 / 霜覆 / 冻结：冰要打三下才到顶，冻结很短，但目标变脆",
			"setup": func() -> void:
				_clean_arena(&"universal")
				combat.select_school(&"frost")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.2),
			"events": [
				[SETTLE + 0.20, _req.bind(&"cast")],
				[SETTLE + 1.60, _req.bind(&"cast")],
				[SETTLE + 3.00, _req.bind(&"cast")],
			],
			"duration": SETTLE + 4.6,
		},
		{
			"name": "剑 × 魔法 · 冻结 → 重击 → Shatter",
			"note": "参考连击：冻结 + 重击 = 碎裂",
			"setup": func() -> void:
				_clean_arena(&"universal")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 1.8),
			"events": [
				[SETTLE + 0.20, _dummy_state.bind(&"frozen")],
				[SETTLE + 1.10, _req.bind(&"heavy")],
			],
			"duration": SETTLE + 3.6,
		},
		{
			"name": "风 · 轻物被推 vs 重物不动",
			"note": "同一个阵风：布箱被扔出去，遗迹哨兵几乎不动 —— 风是力，不是伤害",
			"fov": 54.0,
			"setup": func() -> void:
				_clean_arena(&"universal")
				combat.select_school(&"wind")
				_release_props()
				_move_pair(WindProps.WALL_TEST_PLAYER, 3.3),
			"events": [
				[SETTLE + 0.20, _req.bind(&"cast")],
			],
			"duration": SETTLE + 4.0,
		},
		{
			"name": "风 × 火 · 火场被风扩散",
			"note": "风不点燃东西，它把已经在烧的东西推出去",
			"fov": 46.0,
			"setup": func() -> void:
				_clean_arena(&"universal")
				combat.select_school(&"fire")
				_place(Vector3(0.0, PLAYER_Y, 0.0), 2.4),
			"events": [
				[SETTLE + 0.20, _req.bind(&"cast")],
				[SETTLE + 2.10, _school.bind(&"wind")],
				[SETTLE + 2.30, _req.bind(&"cast")],
			],
			"duration": SETTLE + 4.2,
		},
		{
			"name": "风推 · 撞墙",
			"note": "被推的对象撞上实体才会产生冲击 —— 没有环境，风只是一个击退数字",
			"fov": 58.0,
			"setup": func() -> void:
				_clean_arena(&"universal")
				combat.select_school(&"wind")
				_release_props()
				_move_pair(WindProps.WALL_TEST_PLAYER, 1.5),
			"events": [
				[SETTLE + 0.20, _req.bind(&"cast")],
			],
			"duration": SETTLE + 4.0,
		},
	]


func _build_review_camera() -> void:
	review_camera = Camera3D.new()
	review_camera.name = "ReviewCamera"
	review_camera.fov = seg_fov
	review_camera.near = 0.05
	review_camera.far = 120.0
	sandbox.add_child(review_camera)
	_update_camera()
	review_camera.make_current()


# Everything in every take happens in front of the player, so one framing rule
# covers the whole tour: sit behind and to the side, and keep the player's own
# position inside the shot. The blade is parented to the player's camera rig, so
# a camera that looks past the player is a camera with no sword in it.
#
# The lens is tight on purpose. At a wide angle a 1.8m placeholder cone 5m away
# is a thumbnail, and the blade — the thing every claim is about — disappears.
func _update_camera() -> void:
	if review_camera == null:
		return
	review_camera.fov = seg_fov
	var basis := player.global_transform.basis
	var forward := -basis.z
	# Aim between the player and the enemy, not at the enemy: the blade is drawn at
	# the player's own eye, so a camera that centres the enemy puts the sword at the
	# bottom edge.
	var focus := player.global_position + forward * 1.0 + Vector3(0.0, 0.15, 0.0)
	# Steep three-quarter, high and off the shoulder. Sitting level behind the
	# player looks *along* the blade, and a blade pointing away from the camera is
	# a blade pointing away from the camera — an 80cm sword renders as a sliver.
	# From above and to the side the swing has to cross the frame to happen.
	#
	# It also has to stay near the centre line: ArenaDressing flanks the arena with
	# pillars from |x| 2.7 outward and keeps the middle deliberately clear, so a
	# camera parked at x=3 films the inside of a pillar. That was the first take.
	var eye := (
		player.global_position
		+ basis.x * 2.2
		- forward * 3.0
		+ Vector3(0.0, 3.8, 0.0)
	)
	review_camera.global_position = eye
	review_camera.look_at(focus, Vector3.UP)
	# The sandbox re-asserts the player's camera once during startup, so claim
	# the viewport back only if it was taken.
	if not review_camera.is_current():
		review_camera.make_current()


func _run_segment(segment: Dictionary) -> void:
	seg_name = String(segment.get("name", ""))
	seg_note = String(segment.get("note", ""))
	seg_fov = float(segment.get("fov", 38.0))
	parry_landed = false
	var setup: Callable = segment["setup"]
	setup.call()
	await _frame()
	await _frame()
	combat.perfect_guard_count = 0

	var events: Array = segment.get("events", [])
	var duration := float(segment.get("duration", 4.0))
	var begin := Time.get_ticks_msec()
	var next_event := 0
	print("--- %s" % seg_name)

	while true:
		var t := float(Time.get_ticks_msec() - begin) / 1000.0
		while next_event < events.size() and t >= float(events[next_event][0]):
			var action: Callable = events[next_event][1]
			action.call()
			next_event += 1
		await _frame()
		_note_parry()
		_update_camera()
		_update_overlay(t)
		_save()
		if t >= duration and next_event >= events.size():
			break
	print("    %s  frames=%d  perfect_guards=%d"
		% [seg_name, frame_index, combat.perfect_guard_count])


# --- driving the systems ----------------------------------------------------

func _req(action: StringName) -> void:
	combat.request(action)


func _school(school_id: StringName) -> void:
	combat.select_school(school_id)


func _trigger_skill(index: int) -> void:
	combat.trigger_skill(index)


func _dummy_state(label: StringName) -> void:
	dummy.call("apply_debug_state", label)


func _guard_up() -> void:
	combat.finish_action()
	combat.set_state(CombatController.State.BLOCK)


func _enemy_hit_on() -> void:
	var hb: CombatHitbox = dummy.get_node("AttackHitbox")
	hb.set_active(true)


func _enemy_hit_off() -> void:
	var hb: CombatHitbox = dummy.get_node("AttackHitbox")
	hb.set_active(false)


func _note_parry() -> void:
	if not parry_landed and combat.perfect_guard_count > 0:
		parry_landed = true


func _clean_arena(style_id: StringName) -> void:
	combat.finish_action()
	combat.set_state(CombatController.State.IDLE)
	combat.set_style(style_id, true)
	combat.reset_skill_cooldowns()
	combat.reset_flow()
	combat.iaido_ready_at = 0.0
	combat.ultimate_ready_at = 0.0
	combat.perfect_guard_count = 0
	combat.select_school(&"fire")
	player.set("stamina", 100.0)
	player.set("health", 100.0)
	dummy.call("reset_dummy")
	dummy.set("attack_cooldown", 9999.0)
	_clear_fields()
	# The two movable crates start 3m in front of the player, which is exactly
	# where the review camera looks. They are parked out of the arena for every
	# take that is not about wind; the wind takes put them back on purpose.
	_park_props()


func _park_props() -> void:
	if props == null:
		return
	# Two distinct spots AND frozen. Stacked at one position the two rigid bodies
	# resolve their overlap by launching each other back across the arena, which
	# is how a "parked" crate ends up filling half the shot.
	var spots := [Vector3(12.0, 0.45, 12.0), Vector3(13.4, 0.45, 12.6)]
	for i in props.light_objects.size():
		var body := props.light_objects[i]
		if not is_instance_valid(body):
			continue
		body.freeze = true
		body.global_position = spots[i % spots.size()]
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO


# The wind takes need the crates back where the player can actually throw them.
func _release_props() -> void:
	if props == null:
		return
	for body in props.light_objects:
		if is_instance_valid(body):
			body.freeze = false
	props.reset()


func _clear_fields() -> void:
	for node in player.get_parent().get_children():
		if node is ElementField:
			node.queue_free()


func _place(player_pos: Vector3, distance: float) -> void:
	_move_pair(player_pos, distance)


# Aim at the target's y raised to the player's own, for the same reason the Lab
# does: looking down at a body below eye level tilts the whole rig and the shot
# reads as a stumble.
func _move_pair(player_pos: Vector3, distance: float) -> void:
	player.global_position = player_pos
	var dummy_pos := player_pos + Vector3(0.0, -DUMMY_DROP, -distance)
	dummy.global_position = dummy_pos
	player.look_at_from_position(
		player_pos, Vector3(dummy_pos.x, player_pos.y, dummy_pos.z), Vector3.UP
	)
	look_pivot.rotation.x = -0.06
	# The dummy's AttackHitbox sits at local +Z 1.3, so this thing attacks along
	# its own +Z. look_at would point -Z at the player and swing its hitbox away
	# from them, which is why every parry take silently produced no perfect guard.
	# Aim it at the mirror point instead.
	dummy.look_at_from_position(
		dummy_pos,
		Vector3(
			dummy_pos.x * 2.0 - player_pos.x,
			dummy_pos.y,
			dummy_pos.z * 2.0 - player_pos.z
		),
		Vector3.UP
	)
	combat.measure_range = combat.measure_distance_now()
	combat.measure_state = combat.measure_label()


# --- capture ----------------------------------------------------------------

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
	if frame_index % 60 == 0:
		print("    frame %d" % frame_index)


func _write_fps(fps: float) -> void:
	var file := FileAccess.open("%s/fps.txt" % output_dir, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("%.4f\n" % fps)
	file.close()


func _clear_existing_frames() -> void:
	var dir := DirAccess.open(output_dir)
	if dir == null:
		return
	var removed := 0
	for file in dir.get_files():
		# Leftover frames from a longer previous take end up in the encode.
		if file.get_extension().to_lower() == "png" or file == "fps.txt":
			dir.remove(file)
			removed += 1
	if removed > 0:
		print("cleared %d stale files" % removed)


# --- overlay ----------------------------------------------------------------

func _build_overlay() -> void:
	layer = CanvasLayer.new()
	layer.layer = 120
	root.add_child(layer)

	var holder := PanelContainer.new()
	# Top, not bottom: the blade and the player's own position sit low in this
	# shot, so a bottom strip would cover the one thing the video is about.
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE, true)
	holder.offset_top = 14.0
	holder.offset_bottom = 152.0
	holder.offset_left = 100.0
	holder.offset_right = -100.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.05, 0.70)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	holder.add_theme_stylebox_override("panel", style)
	layer.add_child(holder)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	holder.add_child(column)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 21)
	title_label.modulate = Color(0.94, 0.95, 0.98, 1.0)
	column.add_child(title_label)

	note_label = Label.new()
	note_label.add_theme_font_size_override("font_size", 14)
	note_label.modulate = Color(0.62, 0.72, 0.84, 0.95)
	column.add_child(note_label)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.modulate = Color(0.52, 0.88, 0.70, 0.95)
	column.add_child(status_label)


func _update_overlay(t: float) -> void:
	title_label.text = "%s      t = %.2f s" % [seg_name, t]
	note_label.text = seg_note
	status_label.text = "%s\n%s" % [combat.debug_state_line(), _enemy_line()]


func _enemy_line() -> String:
	if not dummy.has_method("element_stage"):
		return ""
	var parts: Array[String] = []
	for id in [ElementLibrary.FIRE, ElementLibrary.FROST, ElementLibrary.WIND]:
		var stage: StringName = dummy.call("element_stage", id)
		if stage != &"":
			parts.append("%s=%s" % [id, stage])
	var line := "敌人: %s" % str(dummy.get("state"))
	if not parts.is_empty():
		line += "  " + " ".join(parts)
	if bool(dummy.call("is_brittle")):
		line += "  [BRITTLE]"
	var bind_line := ""
	if combat.bind_until > Time.get_ticks_msec() / 1000.0:
		bind_line = "  >>> BIND 窗口开着 <<<"
	return line + bind_line
