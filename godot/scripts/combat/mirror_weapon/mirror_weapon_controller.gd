extends Node3D
class_name MirrorWeaponController
# MIRROR / 镜 — POSITION · ANGLE · TRAVEL prototype.
# Independent of Sword and Phantom Chain. Do not fold into combat_controller.

enum State { STOWED, READY, ATTACK, TRAVEL, EXIT_WINDOW }

signal mirror_event(event: StringName, data: Dictionary)
signal message(text: String)
signal equipped_changed(on: bool)

const HAND_PATH := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot"
const DEBUG_KEY := KEY_F9

const EV_MIRROR_EQUIP := &"EV_MIRROR_EQUIP"
const EV_MIRROR_PLACE := &"EV_MIRROR_PLACE"
const EV_MIRROR_BREAK := &"EV_MIRROR_BREAK"
const EV_MIRROR_A1 := &"EV_MIRROR_A1"
const EV_MIRROR_A1_ECHO := &"EV_MIRROR_A1_ECHO"
const EV_MIRROR_A2_RELEASE := &"EV_MIRROR_A2_RELEASE"
const EV_MIRROR_A2_REFLECT := &"EV_MIRROR_A2_REFLECT"
const EV_MIRROR_ENTER := &"EV_MIRROR_ENTER"
const EV_MIRROR_TRAVEL := &"EV_MIRROR_TRAVEL"
const EV_MIRROR_EXIT := &"EV_MIRROR_EXIT"
const EV_MIRROR_EXIT_ATTACK := &"EV_MIRROR_EXIT_ATTACK"
const EV_MIRROR_A4_SHIFT := &"EV_MIRROR_A4_SHIFT"

@export var config: MirrorConfig

var state := State.STOWED
var combo_index := 0
var combo_age := 0.0
var debug_draw := false
var last_a2_reflections := 0

var _player: CharacterBody3D
var _slot: WeaponSlot
var _camera_fb: CameraFeedbackController
var _look: Node3D
var _camera: Camera3D
var _weapon_root: Node3D
var _hand_card: Node3D
var _hand_mesh: MeshInstance3D
var _hand_tween: Tween

var manager: MirrorManager
var attacks: MirrorAttackLogic
var travel: MirrorTravel

var _move_id: StringName = &""
var _move_t := 0.0
var _hit_done := false
var _echo_armed := false
var _echo_left := 0.0
var _echo_mirror: MirrorNode
var _place_lock := 0.0
var _exit_window_left := 0.0
var _exit_cut_recover := 0.0
var _debug_layer: CanvasLayer
var _debug_label: Label
var _world_debug: ImmediateMesh
var _world_debug_mi: MeshInstance3D
var _slash_debug: Array[Dictionary] = []
var _invuln_was := false


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if _player == null:
		push_warning("MirrorWeaponController: parent must be the Player.")
		return
	_slot = _player.get_node_or_null("WeaponSlot") as WeaponSlot
	_camera_fb = _player.get_node_or_null("CameraFeedbackController") as CameraFeedbackController
	_look = _player.get_node_or_null("CameraRig/LookPivot") as Node3D
	_camera = _player.get_node_or_null("CameraRig/LookPivot/MotionPivot/ShakePivot/Camera3D") as Camera3D
	_weapon_root = _player.get_node_or_null(HAND_PATH) as Node3D
	if config == null:
		config = MirrorConfig.new()

	manager = MirrorManager.new()
	manager.name = "MirrorManager"
	add_child(manager)
	var host := _player.get_parent() as Node3D
	if host == null:
		host = _player
	manager.configure(config, host, _player, _camera)

	attacks = MirrorAttackLogic.new()
	attacks.configure(config, _player, manager)

	travel = MirrorTravel.new()
	travel.configure(config, _player, _camera_fb, manager, _look)
	travel.phase_changed.connect(_on_travel_phase)
	travel.exited.connect(_on_travel_exited)
	travel.travel_failed.connect(func(r: StringName): message.emit("镜 · 失败 %s" % String(r)))

	if _slot != null:
		_slot.changed.connect(_on_slot_changed)
	_ensure_hand_card()
	_bind_actions()
	_build_debug_ui()
	reset()
	set_process(true)
	set_process_unhandled_input(true)


func is_equipped() -> bool:
	return _slot != null and _slot.has_method("is_mirror") and _slot.is_mirror()


func reset() -> void:
	_cancel_move()
	if travel != null and travel.is_active():
		travel.cancel()
	combo_index = 0
	combo_age = 0.0
	_exit_window_left = 0.0
	_place_lock = 0.0
	_exit_cut_recover = 0.0
	_slash_debug.clear()
	_set_invuln(false)
	_hide_hand()
	state = State.STOWED
	if config != null and config.clear_nodes_on_unequip and manager != null:
		manager.clear_all()


func request(action: StringName) -> bool:
	if not is_equipped():
		return false
	match action:
		&"light", &"attack_primary":
			return _request_light()
		&"place":
			return _place_mirror()
		&"travel":
			return _begin_travel()
		&"cancel":
			_cancel_move()
			if travel != null:
				travel.cancel()
			return true
	return false


func _bind_actions() -> void:
	# INPUT CONTRACT: Place = skill_1 (E), Travel = skill_2 (X).
	# Keep mirror_place / mirror_travel action names as adapters so existing
	# travel-confirm paths still work; do not steal RMB (now global Parry).
	_alias_to(&"mirror_place", &"skill_1")
	_alias_to(&"mirror_travel", &"skill_2")


func _alias_to(action: StringName, source: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		InputMap.action_erase_event(action, ev)
	if not InputMap.has_action(source):
		return
	for ev in InputMap.action_get_events(source):
		InputMap.action_add_event(action, ev.duplicate())


func _bind_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).keycode == keycode:
			return
	InputMap.action_add_event(action, event)


func _bind_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == button:
			return
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == DEBUG_KEY:
		debug_draw = not debug_draw
		if manager != null:
			manager.set_debug_draw(debug_draw)
			manager.set_labels_visible(debug_draw)
		if _debug_layer != null:
			_debug_layer.visible = debug_draw
		message.emit("镜 DEBUG · %s" % ("ON" if debug_draw else "OFF"))
		get_viewport().set_input_as_handled()
		return

	if not is_equipped():
		return

	if travel != null and travel.is_in_select():
		if event.is_action_pressed(&"light_attack") or event.is_action_pressed(&"mirror_travel"):
			travel.confirm_exit(manager.get_aim_selected_node() if manager else null)
			get_viewport().set_input_as_handled()
			return

	if travel != null and travel.is_active() and not travel.is_in_select():
		if event.is_action_pressed(&"light_attack") or event.is_action_pressed(&"mirror_place"):
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed(&"mirror_place") or event.is_action_pressed(&"skill_1"):
		request(&"place")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"mirror_travel") or event.is_action_pressed(&"skill_2"):
		request(&"travel")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"light_attack") or event.is_action_pressed(&"attack_primary"):
		if _exit_window_left > 0.0 and state == State.EXIT_WINDOW:
			_do_exit_cut()
		else:
			request(&"light")
		get_viewport().set_input_as_handled()


func _on_slot_changed(_prev: StringName, _cur: StringName) -> void:
	if is_equipped():
		_begin_equip()
	else:
		reset()
		equipped_changed.emit(false)


func _begin_equip() -> void:
	state = State.READY
	combo_index = 0
	combo_age = 0.0
	_show_hand()
	_emit(EV_MIRROR_EQUIP, {})
	equipped_changed.emit(true)
	message.emit("镜 · MIRROR")


func _process(delta: float) -> void:
	if not is_equipped() and (travel == null or not travel.is_active()):
		_update_debug_label()
		return

	if _place_lock > 0.0:
		_place_lock = maxf(0.0, _place_lock - delta)

	if is_equipped() and manager != null and state != State.TRAVEL:
		manager.update_selection()

	if travel != null and travel.is_active():
		state = State.TRAVEL
		travel.tick(delta)
		_set_invuln(travel.invulnerable)
		_update_debug_label()
		_draw_world_debug()
		return

	if _exit_window_left > 0.0:
		_exit_window_left = maxf(0.0, _exit_window_left - delta)
		if _exit_window_left <= 0.0 and state == State.EXIT_WINDOW:
			state = State.READY

	if combo_index > 0:
		combo_age += delta
		if combo_age > config.combo_window:
			combo_index = 0
			combo_age = 0.0

	if _exit_cut_recover > 0.0:
		_exit_cut_recover = maxf(0.0, _exit_cut_recover - delta)
		if _exit_cut_recover <= 0.0 and _move_id == &"exit_cut":
			_end_move()

	if state == State.ATTACK and _move_id != &"exit_cut":
		_tick_attack(delta)

	if _echo_armed:
		_echo_left = maxf(0.0, _echo_left - delta)
		if _echo_left <= 0.0:
			_echo_armed = false
			_fire_a1_echo()

	_update_debug_label()
	_draw_world_debug()


func _request_light() -> bool:
	if state == State.ATTACK or state == State.TRAVEL:
		return false
	if combo_index >= 4:
		combo_index = 0
	match combo_index:
		0:
			return _start_move(&"a1")
		1:
			return _start_move(&"a2")
		2:
			return _start_move(&"a3")
		3:
			return _start_move(&"a4")
	return false


func _start_move(id: StringName) -> bool:
	_cancel_move()
	_move_id = id
	_move_t = 0.0
	_hit_done = false
	state = State.ATTACK
	combo_age = 0.0
	match id:
		&"a1":
			_play_hand(&"slash", config.a1_startup + config.a1_active)
			_emit(EV_MIRROR_A1, {})
		&"a2":
			_play_hand(&"thrust", config.a2_startup + config.a2_active)
			_emit(EV_MIRROR_A2_RELEASE, {})
		&"a3":
			# PLACEHOLDER — TODO CODEX: REPLACE WITH MIRROR CLONE
			attacks.mirror_clone_placeholder()
			_play_hand(&"pulse", config.a3_startup + config.a3_active)
		&"a4":
			_play_hand(&"touch", config.a4_startup + config.a4_transit_ms)
	return true


func _tick_attack(delta: float) -> void:
	_move_t += delta
	match _move_id:
		&"a1":
			_tick_a1()
		&"a2":
			_tick_a2()
		&"a3":
			_tick_a3()
		&"a4":
			_tick_a4()


func _tick_a1() -> void:
	var active_start := config.a1_startup
	var active_end := active_start + config.a1_active
	var total := active_end + config.a1_recover
	if not _hit_done and _move_t >= active_start and _move_t <= active_end:
		_hit_done = true
		var hits := attacks.a1_player_cut()
		for t in hits:
			attacks.apply_damage(t, config.a1_damage, MirrorAttackLogic.ORIGIN_PLAYER)
		_record_slash_debug(_player.global_position + Vector3.UP * 1.0, _facing(), config.a1_range, &"PLAYER")
		_echo_mirror = manager.get_last_created() if manager else null
		if _echo_mirror != null:
			_echo_armed = true
			_echo_left = config.a1_echo_delay
		_bump_combo(1)
		_cam(Vector2(0.04, 0.0), 0.08)
	if _move_t >= total:
		_end_move()


func _fire_a1_echo() -> void:
	if _echo_mirror == null or not is_instance_valid(_echo_mirror):
		return
	var hits := attacks.a1_mirror_echo(_echo_mirror)
	var dmg := config.a1_damage * config.a1_echo_damage_scale
	for t in hits:
		attacks.apply_damage(t, dmg, MirrorAttackLogic.ORIGIN_MIRROR_NODE, _echo_mirror)
	_record_slash_debug(
		_echo_mirror.global_position,
		_echo_mirror.get_mirror_normal(),
		config.a1_echo_range,
		&"MIRROR"
	)
	_emit(EV_MIRROR_A1_ECHO, {"mirror_id": _echo_mirror.mirror_id})
	_echo_mirror = null


func _tick_a2() -> void:
	var active_start := config.a2_startup
	var active_end := active_start + config.a2_active
	var total := active_end + config.a2_recover
	if not _hit_done and _move_t >= active_start and _move_t <= active_end:
		_hit_done = true
		var aim := _aim_dir()
		var result := attacks.a2_refract(aim)
		last_a2_reflections = int(result.get("reflections", 0))
		for t in result.hits:
			attacks.apply_damage(t, config.a2_damage, MirrorAttackLogic.ORIGIN_PLAYER)
		if last_a2_reflections > 0:
			_emit(EV_MIRROR_A2_REFLECT, {"count": last_a2_reflections})
		_slash_debug.clear()
		for seg in result.segments:
			_slash_debug.append(seg)
		_bump_combo(2)
		_cam(Vector2(0.0, -0.03), 0.1)
	if _move_t >= total:
		_end_move()


func _tick_a3() -> void:
	var active_start := config.a3_startup
	var active_end := active_start + config.a3_active
	var total := active_end + config.a3_recover
	if not _hit_done and _move_t >= active_start and _move_t <= active_end:
		_hit_done = true
		var batches := attacks.a3_all_mirrors_echo()
		for batch in batches:
			var mnode: MirrorNode = batch.mirror
			for t in batch.hits:
				attacks.apply_damage(t, config.a3_echo_damage, MirrorAttackLogic.ORIGIN_MIRROR_NODE, mnode)
			_record_slash_debug(mnode.global_position, mnode.get_mirror_normal(), config.a3_echo_range, &"A3")
		_bump_combo(3)
	if _move_t >= total:
		_end_move()


func _tick_a4() -> void:
	if _move_t < config.a4_startup:
		return
	if not _hit_done:
		_hit_done = true
		var preferred := manager.get_aim_selected_node() if manager else null
		if preferred == null and manager != null:
			preferred = manager.get_closest_node(_player.global_position)
		if travel.begin_shift(preferred):
			_emit(EV_MIRROR_A4_SHIFT, {"mirror_id": preferred.mirror_id if preferred else -1})
			_emit(EV_MIRROR_ENTER, {"mode": &"shift"})
			combo_index = 0
			combo_age = 0.0
			state = State.TRAVEL
			_move_id = &""
		else:
			message.emit("镜 · 无可用出口")
			_end_move()


func _bump_combo(expected_index: int) -> void:
	combo_index = expected_index
	if combo_index >= 4:
		combo_index = 0
	combo_age = 0.0


func _end_move() -> void:
	_move_id = &""
	_move_t = 0.0
	if state == State.ATTACK:
		state = State.READY


func _cancel_move() -> void:
	_move_id = &""
	_move_t = 0.0
	_hit_done = false
	_echo_armed = false
	_echo_left = 0.0
	_echo_mirror = null
	if state == State.ATTACK:
		state = State.READY if is_equipped() else State.STOWED


func _place_mirror() -> bool:
	if _place_lock > 0.0 or state == State.TRAVEL:
		return false
	if manager == null:
		return false
	var node := manager.try_place_from_aim()
	if node == null:
		message.emit("镜 · 无法放置")
		return false
	_place_lock = config.place_lock_ms
	_play_hand(&"place", 0.18)
	_emit(EV_MIRROR_PLACE, {"mirror_id": node.mirror_id, "safe": node.travel_exit_ok})
	message.emit("镜 · M%d%s" % [node.mirror_id, "" if node.travel_exit_ok else " (出口受限)"])
	return true


func _begin_travel() -> bool:
	if state == State.ATTACK:
		return false
	if travel == null:
		return false
	if travel.begin_travel():
		state = State.TRAVEL
		_emit(EV_MIRROR_ENTER, {"mode": &"travel"})
		_emit(EV_MIRROR_TRAVEL, {})
		message.emit("镜界 · 选择出口")
		return true
	return false


func _on_travel_phase(p: int) -> void:
	if p == int(MirrorTravel.Phase.SELECT) and manager != null:
		manager.update_selection()


func _on_travel_exited(mirror: MirrorNode) -> void:
	_emit(EV_MIRROR_EXIT, {"mirror_id": mirror.mirror_id if mirror else -1})
	_set_invuln(false)
	state = State.EXIT_WINDOW
	_exit_window_left = config.exit_attack_window
	message.emit("镜 · 出斩窗口")
	_cam(Vector2(0.0, -0.05), 0.12)


func _do_exit_cut() -> void:
	_exit_window_left = 0.0
	state = State.ATTACK
	_move_id = &"exit_cut"
	_move_t = 0.0
	_hit_done = true
	_play_hand(&"slash", 0.22)
	var f := _facing()
	if _player.has_method("pull"):
		_player.call("pull", f * config.exit_cut_dash)
	else:
		_player.global_position += f * config.exit_cut_dash
	var hits := attacks.slash_query(_player.global_position, f, config.exit_cut_range, 0.9)
	for t in hits:
		attacks.apply_damage(t, config.exit_cut_damage, MirrorAttackLogic.ORIGIN_MIRROR_EXIT)
	_record_slash_debug(_player.global_position + Vector3.UP, f, config.exit_cut_range, &"EXIT")
	_emit(EV_MIRROR_EXIT_ATTACK, {})
	_cam(Vector2(0.0, -0.08), 0.16)
	combo_index = 1
	combo_age = 0.0
	_exit_cut_recover = 0.22


func _ensure_hand_card() -> void:
	if _weapon_root == null:
		return
	_hand_card = _weapon_root.get_node_or_null("MirrorHandCard") as Node3D
	if _hand_card == null:
		_hand_card = Node3D.new()
		_hand_card.name = "MirrorHandCard"
		_weapon_root.add_child(_hand_card)
		_hand_card.position = Vector3(-0.32, -0.28, -0.42)
		_hand_card.rotation_degrees = Vector3(12, 18, -8)
		_hand_mesh = MeshInstance3D.new()
		_hand_mesh.name = "CardMesh"
		var box := BoxMesh.new()
		box.size = Vector3(0.18, 0.32, 0.02)
		_hand_mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = config.card_color
		mat.metallic = 0.9
		mat.roughness = 0.18
		mat.emission_enabled = true
		mat.emission = config.card_fresnel * 0.4
		mat.emission_energy_multiplier = 0.6
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hand_mesh.material_override = mat
		_hand_card.add_child(_hand_mesh)
	_hand_card.visible = false


func _show_hand() -> void:
	if _hand_card != null:
		_hand_card.visible = true
		_play_hand(&"equip", 0.25)


func _hide_hand() -> void:
	if _hand_card != null:
		_hand_card.visible = false


func _play_hand(kind: StringName, seconds: float) -> void:
	if _hand_card == null:
		return
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	_hand_tween = create_tween()
	_hand_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var home := Vector3(-0.32, -0.28, -0.42)
	var home_r := Vector3(deg_to_rad(12), deg_to_rad(18), deg_to_rad(-8))
	match kind:
		&"equip":
			_hand_card.position = home + Vector3(0.0, -0.1, 0.05)
			_hand_tween.tween_property(_hand_card, "position", home, seconds)
		&"slash":
			_hand_card.position = home + Vector3(0.2, 0.05, -0.05)
			_hand_tween.tween_property(_hand_card, "position", home + Vector3(-0.15, 0.02, -0.12), seconds)
			_hand_tween.parallel().tween_property(_hand_card, "rotation", home_r + Vector3(0.2, -0.8, 0.3), seconds)
		&"thrust":
			_hand_card.position = home
			_hand_tween.tween_property(_hand_card, "position", home + Vector3(0.05, 0.05, -0.28), seconds)
		&"touch":
			_hand_card.position = home
			_hand_tween.tween_property(_hand_card, "position", home + Vector3(0.1, 0.08, -0.2), seconds * 0.6)
			_hand_tween.tween_property(_hand_card, "position", home, seconds * 0.4)
		&"place":
			_hand_card.position = home
			_hand_tween.tween_property(_hand_card, "position", home + Vector3(-0.05, 0.12, -0.1), seconds * 0.5)
			_hand_tween.tween_property(_hand_card, "position", home, seconds * 0.5)
		&"pulse":
			_hand_card.position = home
			_hand_tween.tween_property(_hand_card, "scale", Vector3.ONE * 1.15, seconds * 0.4)
			_hand_tween.tween_property(_hand_card, "scale", Vector3.ONE, seconds * 0.6)
		_:
			_hand_tween.tween_property(_hand_card, "position", home, seconds)
			_hand_tween.parallel().tween_property(_hand_card, "rotation", home_r, seconds)


func _facing() -> Vector3:
	if _look != null:
		var f := -_look.global_transform.basis.z
		f.y = 0.0
		if f.length_squared() > 0.0001:
			return f.normalized()
	return Vector3.FORWARD


func _aim_dir() -> Vector3:
	if _camera != null:
		return -_camera.global_transform.basis.z
	return _facing()


func _cam(dir: Vector2, trauma: float) -> void:
	if _camera_fb == null:
		return
	_camera_fb.add_impulse(dir, 1.0)
	_camera_fb.add_trauma(trauma)


func _set_invuln(on: bool) -> void:
	if _invuln_was == on:
		return
	_invuln_was = on
	var hurt := _player.get_node_or_null("Hurtbox") as Area3D
	if hurt != null:
		hurt.monitoring = not on
		hurt.monitorable = not on


func _emit(ev: StringName, data: Dictionary) -> void:
	mirror_event.emit(ev, data)


func _record_slash_debug(origin: Vector3, forward: Vector3, range_m: float, kind: StringName) -> void:
	_slash_debug.append({
		"from": origin,
		"to": origin + forward.normalized() * range_m,
		"kind": kind,
		"mirror": null,
	})
	while _slash_debug.size() > 12:
		_slash_debug.pop_front()


func _build_debug_ui() -> void:
	_debug_layer = CanvasLayer.new()
	_debug_layer.name = "MirrorDebugOverlay"
	_debug_layer.layer = 6
	_debug_layer.visible = false
	add_child(_debug_layer)
	_debug_label = Label.new()
	_debug_label.position = Vector2(16, 120)
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_debug_label.add_theme_constant_override("shadow_offset_x", 1)
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_layer.add_child(_debug_label)

	_world_debug = ImmediateMesh.new()
	_world_debug_mi = MeshInstance3D.new()
	_world_debug_mi.name = "MirrorWorldDebug"
	_world_debug_mi.mesh = _world_debug
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.5, 0.95, 1.0, 1.0)
	mat.vertex_color_use_as_albedo = true
	_world_debug_mi.material_override = mat
	add_child(_world_debug_mi)


func _update_debug_label() -> void:
	if _debug_label == null or not debug_draw:
		return
	var sel := manager.get_aim_selected_node() if manager else null
	var travel_state := "IDLE"
	if travel != null:
		match travel.phase:
			MirrorTravel.Phase.ENTER:
				travel_state = "ENTER"
			MirrorTravel.Phase.TRANSIT:
				travel_state = "TRANSIT"
			MirrorTravel.Phase.SELECT:
				travel_state = "SELECT"
			MirrorTravel.Phase.EXIT:
				travel_state = "EXIT"
			_:
				travel_state = "IDLE"
	var state_name := "STOWED"
	match state:
		State.READY:
			state_name = "READY"
		State.ATTACK:
			state_name = "ATTACK"
		State.TRAVEL:
			state_name = "TRAVEL"
		State.EXIT_WINDOW:
			state_name = "EXIT_WINDOW"
	var travel_target := "-"
	if travel != null and travel.target != null and is_instance_valid(travel.target):
		travel_target = "M%d" % travel.target.mirror_id
	_debug_label.text = "\n".join([
		"Weapon: MIRROR",
		"Combo: %d" % combo_index,
		"State: %s" % state_name,
		"Mirror Count: %d" % (manager.count() if manager else 0),
		"Selected: %s" % (("M%d" % sel.mirror_id) if sel else "-"),
		"Mirror State: %s" % travel_state,
		"Travel Target: %s" % travel_target,
		"A2 Reflections: %d" % last_a2_reflections,
		"Exit Window: %.2f" % _exit_window_left,
		"F9 toggle · RMB place · Q travel",
	])


func _draw_world_debug() -> void:
	if _world_debug == null:
		return
	_world_debug.clear_surfaces()
	if not debug_draw or _slash_debug.is_empty():
		return
	_world_debug.surface_begin(Mesh.PRIMITIVE_LINES)
	var added := 0
	for seg in _slash_debug:
		var c := Color(1.0, 0.85, 0.3)
		match String(seg.get("kind", "")):
			"normal":
				c = Color(0.3, 0.9, 1.0)
			"reflected":
				c = Color(0.4, 1.0, 0.55)
			"incoming":
				c = Color(1.0, 0.7, 0.2)
			"MIRROR", "A3":
				c = Color(0.55, 0.85, 1.0)
			"EXIT":
				c = Color(1.0, 0.45, 0.7)
		_world_debug.surface_set_color(c)
		_world_debug.surface_add_vertex(seg.from)
		_world_debug.surface_add_vertex(seg.to)
		added += 2
	if added > 0:
		_world_debug.surface_end()
	else:
		_world_debug.clear_surfaces()
