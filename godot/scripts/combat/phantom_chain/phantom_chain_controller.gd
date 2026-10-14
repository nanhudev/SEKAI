extends Node3D
class_name PhantomChainController
# PHANTOM CHAIN / 虚链 — RULE-BASED combat language.
# Independent of Sword and of Star-Bind Chain. Visual ≠ Hit.

enum State { STOWED, READY, ATTACK, BIND }

signal equipped_changed(on: bool)
signal move_started(move_id: StringName)
signal hit_landed(move_id: StringName, target: Node3D)
signal bound(target: Node3D)
signal rule_locked(target: Node3D, tension: float)
signal chain_event(event: StringName, data: Dictionary)
signal message(text: String)

const HURTBOX_MASK := 2
const HAND_PATH := "CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot"
const DEBUG_KEY := KEY_F6

var profile: PhantomChainProfile
var state := State.STOWED
var combo_index := 0
var combo_age := 0.0
var debug_draw := false

var _player: CharacterBody3D
var _slot: WeaponSlot
var _camera_fb: CameraFeedbackController
var _time_fx: TimeEffectManager
var _look: Node3D
var _weapon_root: Node3D
var _hand_pose: Node3D

var _renderer: PhantomChainRenderer
var _orbit_renderers: Array[PhantomChainRenderer] = []
var _vfx: PhantomChainVFX

var _move_id: StringName = &""
var _move_t := 0.0
var _move_phase := &""
var _hit_done: Dictionary = {}
var _hand_tween: Tween

var _bind_target: Node3D
var _bind_left := 0.0
var _bind_d0 := 0.0
var _bind_max := 0.0
var _bind_tension := 0.0
var _was_at_limit := false
var _pending_pull := false

var _audio: AudioStreamPlayer
var _equip_left := 0.0


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if _player == null:
		push_warning("PhantomChainController: parent must be the Player.")
		return
	_slot = _player.get_node_or_null("WeaponSlot") as WeaponSlot
	_camera_fb = _player.get_node_or_null("CameraFeedbackController") as CameraFeedbackController
	_look = _player.get_node_or_null("CameraRig/LookPivot") as Node3D
	_weapon_root = _player.get_node_or_null(HAND_PATH) as Node3D
	_time_fx = _player.get_parent().get_node_or_null("TimeEffectManager") as TimeEffectManager
	if profile == null:
		profile = PhantomChainProfile.new()
	if _slot != null:
		_slot.changed.connect(_on_slot_changed)
	_ensure_hand_pose()
	_build_visuals()
	_build_audio()
	reset()
	set_process(true)
	set_process_unhandled_input(true)


func is_equipped() -> bool:
	return _slot != null and _slot.has_method("is_phantom_chain") and _slot.is_phantom_chain()


func reset() -> void:
	_cancel_move(true)
	_clear_bind()
	combo_index = 0
	combo_age = 0.0
	_pending_pull = false
	_equip_left = 0.0
	if _renderer != null:
		_renderer.clear()
	for r in _orbit_renderers:
		r.clear()
	if _vfx != null:
		_vfx.set_equipped(false)
	_reset_hand()
	state = State.STOWED


func request(action: StringName) -> bool:
	if not is_equipped():
		return false
	if action == &"light" or action == &"attack_primary":
		return _request_light()
	if action == &"cancel":
		_cancel_move(true)
		return true
	return false


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == DEBUG_KEY:
		debug_draw = not debug_draw
		if _renderer != null:
			_renderer.debug_draw = debug_draw
		message.emit("虚链 DEBUG · %s" % ("ON" if debug_draw else "OFF"))
		get_viewport().set_input_as_handled()
		return
	if not is_equipped():
		return
	# INPUT CONTRACT: only light is implemented on 虚链 today. skill_1..ultimate = no-op.
	if event.is_action_pressed(&"light_attack") or event.is_action_pressed(&"attack_primary"):
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
	_equip_left = profile.equip_seconds
	if _vfx != null:
		_vfx.set_equipped(true)
		_vfx.play_equip()
	_play_hand(&"equip", profile.equip_seconds)
	_announce(&"MATERIALIZE", {})
	equipped_changed.emit(true)
	message.emit("虚链 · PHANTOM CHAIN")


# ---------------------------------------------------------------- process

func _process(delta: float) -> void:
	if not is_equipped():
		return
	if combo_index > 0:
		combo_age += delta
		if combo_age > profile.combo_window:
			combo_index = 0
			combo_age = 0.0
	if _equip_left > 0.0:
		_equip_left = maxf(0.0, _equip_left - delta)
	_tick_bind(delta)
	if state == State.ATTACK:
		_tick_attack(delta)
	_update_visuals(delta)
	if _vfx != null:
		_vfx.update_hand(_hand_world(), delta)


# ---------------------------------------------------------------- combo

func _request_light() -> bool:
	if state == State.ATTACK:
		return false
	if _bind_target != null and is_instance_valid(_bind_target) and _bind_left > 0.0:
		# Bind active → CHAIN PULL instead of advancing combo.
		return _do_pull()
	if combo_index >= 4:
		combo_index = 0
	var next := combo_index
	match next:
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
	_cancel_move(false)
	_move_id = id
	_move_t = 0.0
	_move_phase = &"startup"
	_hit_done.clear()
	_announced.clear()
	state = State.ATTACK
	combo_age = 0.0
	move_started.emit(id)
	match id:
		&"a1":
			_play_hand(&"sweep", profile.a1_startup + profile.a1_active)
			_announce(&"MATERIALIZE", {"move": id})
			_cam_nudge(Vector2(-0.012, 0.0), 0.03)
		&"a2":
			_play_hand(&"snap", profile.a2_startup + profile.a2_active)
			_announce(&"SNAP", {"move": id})
			_cam_nudge(Vector2(0.018, -0.004), 0.05)
		&"a3":
			_play_hand(&"bind", profile.a3_startup + profile.a3_active)
			_announce(&"MATERIALIZE", {"move": id})
		&"a4":
			_play_hand(&"orbit", profile.a4_startup + profile.a4_active)
			_announce(&"MATERIALIZE", {"move": id})
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


func _finish_move() -> void:
	var finished := _move_id
	_move_id = &""
	_move_phase = &""
	state = State.READY if _bind_left <= 0.0 else State.BIND
	match finished:
		&"a1":
			combo_index = 1
		&"a2":
			combo_index = 2
		&"a3":
			combo_index = 3
		&"a4":
			combo_index = 0
	combo_age = 0.0
	_reset_hand()


func _cancel_move(dissolve_now: bool) -> void:
	if dissolve_now and _renderer != null and _renderer.fade > 0.01:
		_renderer.dissolve_progress = 1.0
		_renderer.fade = 0.0
		_renderer.refresh()
	for r in _orbit_renderers:
		r.clear()
	_move_id = &""
	_move_phase = &""
	_hit_done.clear()
	if state == State.ATTACK:
		state = State.READY if is_equipped() else State.STOWED


# ---------------------------------------------------------------- A1 SWEEP

func _tick_a1() -> void:
	var start_t := profile.a1_startup
	var active_t := profile.a1_active
	var recover_t := profile.a1_recover
	var total := start_t + active_t + recover_t
	var hand := _hand_world()
	var facing := _facing()
	var right := facing.cross(Vector3.UP).normalized()
	# Leftward great arc: start right of player, end left.
	var yaw0 := deg_to_rad(profile.a1_arc_degrees * 0.5)
	var yaw1 := deg_to_rad(-profile.a1_arc_degrees * 0.5)
	var u := 0.0
	if _move_t < start_t:
		_move_phase = &"startup"
		u = 0.0
		_renderer.spawn_progress = clampf(_move_t / maxf(0.03, profile.materialize_ms), 0.0, 1.0)
		_renderer.dissolve_progress = 0.0
		_renderer.fade = 1.0
		_renderer.tension = 0.15
		_renderer.alpha = profile.travel_alpha
	elif _move_t < start_t + active_t:
		_move_phase = &"active"
		u = (_move_t - start_t) / active_t
		_renderer.spawn_progress = 1.0
		_renderer.dissolve_progress = 0.0
		_renderer.fade = 1.0
		_renderer.tension = 0.25
		_renderer.alpha = profile.travel_alpha
		_try_arc_hits(&"a1", hand, facing, right, yaw0, yaw1, u, profile.a1_range, profile.a1_damage, profile.a1_hitstop)
	else:
		_move_phase = &"recover"
		u = 1.0
		var rt := (_move_t - start_t - active_t) / maxf(0.01, recover_t)
		_renderer.dissolve_progress = clampf(rt, 0.0, 1.0)
		_renderer.fade = 1.0 - rt * 0.3
		_announce_once(&"DISSOLVE", {})
	var yaw := lerpf(yaw0, yaw1, clampf(u, 0.0, 1.0))
	var tip := hand + (facing.rotated(Vector3.UP, yaw) * profile.a1_range) + Vector3.UP * 0.15
	var ctrl := hand.lerp(tip, 0.45) + Vector3.UP * 0.55 + right * lerpf(0.8, -0.8, u) * 0.4
	_renderer.set_endpoints(hand, tip, ctrl)
	_renderer.flow = _move_t * 2.0
	_renderer.refresh()
	if _move_t >= total:
		_renderer.clear()
		_finish_move()


# ---------------------------------------------------------------- A2 SNAP

func _tick_a2() -> void:
	var start_t := profile.a2_startup
	var active_t := profile.a2_active
	var recover_t := profile.a2_recover
	var total := start_t + active_t + recover_t
	var hand := _hand_world()
	var facing := _facing()
	var right := facing.cross(Vector3.UP).normalized()
	# Continue from left finish → snap reverse to right (narrow, faster).
	var yaw0 := deg_to_rad(-profile.a1_arc_degrees * 0.45)
	var yaw1 := deg_to_rad(profile.a2_arc_degrees * 0.5)
	var u := 0.0
	if _move_t < start_t:
		_move_phase = &"startup"
		# Residue curve → straighten.
		u = 0.0
		_renderer.spawn_progress = 1.0
		_renderer.dissolve_progress = 0.0
		_renderer.fade = 1.0
		_renderer.tension = lerpf(0.2, 0.85, _move_t / maxf(0.01, start_t))
		_renderer.alpha = lerpf(profile.travel_alpha, profile.tension_alpha, _renderer.tension)
	elif _move_t < start_t + active_t:
		_move_phase = &"active"
		u = (_move_t - start_t) / active_t
		_renderer.tension = 1.0
		_renderer.alpha = profile.tension_alpha
		_renderer.hit_flash = 1.0 if u < 0.2 else maxf(0.0, 1.0 - (u - 0.2) * 4.0)
		_try_arc_hits(&"a2", hand, facing, right, yaw0, yaw1, u, profile.a2_range, profile.a2_damage, profile.a2_hitstop)
	else:
		_move_phase = &"recover"
		u = 1.0
		var rt := (_move_t - start_t - active_t) / maxf(0.01, recover_t)
		_renderer.tension = lerpf(1.0, 0.1, rt)
		_renderer.dissolve_progress = rt
		_renderer.hit_flash = 0.0
		_renderer.alpha = profile.idle_alpha
	var yaw := lerpf(yaw0, yaw1, clampf(u, 0.0, 1.0))
	var tip := hand + (facing.rotated(Vector3.UP, yaw) * profile.a2_range)
	# Curve → straight under tension.
	var bow := (1.0 - _renderer.tension) * 0.9
	var ctrl := hand.lerp(tip, 0.5) + Vector3.UP * bow + right * bow * 0.3
	_renderer.set_endpoints(hand, tip, ctrl if bow > 0.05 else null)
	_renderer.flow = _move_t * 4.0
	_renderer.refresh()
	if _move_t >= total:
		_renderer.clear()
		_finish_move()


# ---------------------------------------------------------------- A3 BIND

func _tick_a3() -> void:
	var start_t := profile.a3_startup
	var active_t := profile.a3_active
	var recover_t := profile.a3_recover
	var total := start_t + active_t + recover_t
	var hand := _hand_world()
	var facing := _facing()
	var aim := hand + facing * profile.a3_range + Vector3.UP * 0.2
	if _move_t < start_t:
		_move_phase = &"startup"
		_renderer.spawn_progress = clampf(_move_t / maxf(0.03, profile.materialize_ms), 0.0, 1.0)
		_renderer.dissolve_progress = 0.0
		_renderer.fade = 1.0
		_renderer.tension = 0.2
		_renderer.alpha = profile.travel_alpha
		_renderer.set_endpoints(hand, hand.lerp(aim, 0.35), null)
	elif _move_t < start_t + active_t:
		_move_phase = &"active"
		_renderer.spawn_progress = 1.0
		var target := _query_forward_target(profile.a3_range)
		if target != null and not _hit_done.has(target):
			_hit_done[target] = true
			_apply_damage(target, profile.a3_damage)
			_establish_bind(target)
			_hitstop(profile.a3_hitstop)
			hit_landed.emit(&"a3", target)
		var tip := aim
		if _bind_target != null and is_instance_valid(_bind_target):
			tip = _bind_target.global_position + Vector3.UP * 0.95
		_renderer.set_endpoints(hand, tip, null)
		_renderer.tension = 0.55 if _bind_target != null else 0.25
		_renderer.alpha = profile.travel_alpha
	else:
		_move_phase = &"recover"
		# Bind chain stays if lock succeeded; otherwise dissolve.
		if _bind_target == null:
			var rt := (_move_t - start_t - active_t) / maxf(0.01, recover_t)
			_renderer.dissolve_progress = rt
		else:
			_renderer.dissolve_progress = 0.0
			_renderer.fade = 1.0
	_renderer.refresh()
	if _move_t >= total:
		if _bind_target == null:
			_renderer.clear()
		_finish_move()


func _establish_bind(target: Node3D) -> void:
	_bind_target = target
	_bind_left = profile.a3_bind_seconds
	_bind_d0 = _player.global_position.distance_to(target.global_position)
	_bind_max = _bind_d0 + profile.a3_slack
	_bind_tension = 0.35
	_was_at_limit = false
	state = State.BIND
	if _vfx != null:
		_vfx.show_bind_ring(target.global_position)
	_announce(&"LOCK", {"target": target})
	bound.emit(target)
	if _camera_fb != null:
		var to := target.global_position - _player.global_position
		to.y = 0.0
		if to.length_squared() > 0.01:
			var side := signf(to.normalized().dot(_facing().cross(Vector3.UP)))
			_camera_fb.add_impulse(Vector2(side * 0.01, -0.006), 0.8)
			_camera_fb.add_trauma(0.04)
	message.emit("规则成立 · RULE BIND")


func _tick_bind(delta: float) -> void:
	if _bind_target == null or not is_instance_valid(_bind_target):
		if _bind_left > 0.0:
			_clear_bind()
		return
	_bind_left = maxf(0.0, _bind_left - delta)
	if _bind_left <= 0.0:
		_clear_bind()
		return
	var hand := _hand_world()
	var tip := _bind_target.global_position + Vector3.UP * 0.95
	var dist := _player.global_position.distance_to(_bind_target.global_position)
	# Tension rises as distance approaches the rule edge.
	var span := maxf(0.15, _bind_max - _bind_d0)
	var over := clampf((dist - _bind_d0) / span, 0.0, 1.0)
	_bind_tension = lerpf(0.25, 1.0, over * over)
	# MAX DISTANCE rule — gameplay control, not Joint physics.
	if dist > _bind_max:
		var from_player := _bind_target.global_position - _player.global_position
		from_player.y = 0.0
		if from_player.length_squared() > 0.0001:
			var clamped := _player.global_position + from_player.normalized() * _bind_max
			clamped.y = _bind_target.global_position.y
			var correction := clamped - _bind_target.global_position
			if _bind_target.has_method("chain_pull"):
				_bind_target.call("chain_pull", correction)
			else:
				_bind_target.global_position = clamped
		_bind_tension = 1.0
		if not _was_at_limit:
			_was_at_limit = true
			if _vfx != null:
				_vfx.play_tension_wave(hand, tip)
			_announce(&"TENSION", {"tension": 1.0})
			rule_locked.emit(_bind_target, 1.0)
			_announce(&"LOCK", {"limit": true})
			if _camera_fb != null:
				_camera_fb.add_trauma(0.05)
			message.emit("到此为止 · LIMIT")
	else:
		_was_at_limit = dist > _bind_max * 0.92
	if state != State.ATTACK and _renderer != null:
		_renderer.set_endpoints(hand, tip, null)
		_renderer.spawn_progress = 1.0
		_renderer.dissolve_progress = 0.0
		_renderer.fade = 1.0
		_renderer.tension = _bind_tension
		_renderer.alpha = lerpf(profile.travel_alpha, profile.tension_alpha, _bind_tension)
		_renderer.flow += delta * (1.0 + _bind_tension * 3.0)
		_renderer.refresh()


func _do_pull() -> bool:
	if _bind_target == null or not is_instance_valid(_bind_target):
		return false
	var toward := _player.global_position - _bind_target.global_position
	toward.y = 0.0
	if toward.length_squared() < 0.0001:
		return false
	var pull := toward.normalized() * profile.a3_pull_distance
	if _bind_target.has_method("chain_pull"):
		_bind_target.call("chain_pull", pull)
	else:
		_bind_target.global_position += pull
	_renderer.tension = 1.0
	_renderer.hit_flash = 1.0
	_hitstop(profile.a3_pull_hitstop)
	_announce(&"PULL", {})
	_cam_nudge(Vector2(0.0, -0.01), 0.06)
	message.emit("链拉 · PULL")
	_play_hand(&"bind", 0.18)
	return true


func _clear_bind() -> void:
	_bind_target = null
	_bind_left = 0.0
	_bind_tension = 0.0
	_was_at_limit = false
	if state == State.BIND:
		state = State.READY if is_equipped() else State.STOWED
	if _renderer != null and (_move_id == &"" or _move_id == &"a3"):
		_renderer.dissolve_progress = 1.0
		_renderer.fade = 0.0
		_renderer.refresh()
		_renderer.clear()


# ---------------------------------------------------------------- A4 ORBIT

func _tick_a4() -> void:
	var start_t := profile.a4_startup
	var active_t := profile.a4_active
	var recover_t := profile.a4_recover
	var total := start_t + active_t + recover_t
	var origin := _player.global_position + Vector3.UP * 1.0
	var count := profile.a4_arc_count
	_ensure_orbit_renderers(count)
	if _move_t < start_t:
		_move_phase = &"startup"
		for i in count:
			var r := _orbit_renderers[i]
			r.spawn_progress = clampf(_move_t / maxf(0.05, start_t), 0.0, 1.0)
			r.dissolve_progress = 0.0
			r.fade = 1.0
			r.tension = 0.2
			r.alpha = profile.idle_alpha
			_place_orbit_arc(r, origin, i, count, 0.0)
			r.refresh()
	elif _move_t < start_t + active_t:
		_move_phase = &"active"
		var u := (_move_t - start_t) / active_t
		var spin := deg_to_rad(profile.a4_spin_degrees) * u
		var taut := smoothstep(0.55, 0.85, u)
		for i in count:
			var r := _orbit_renderers[i]
			r.spawn_progress = 1.0
			r.tension = lerpf(0.25, 0.95, taut)
			r.alpha = lerpf(profile.idle_alpha, profile.tension_alpha, taut)
			r.hit_flash = 1.0 if taut > 0.9 and u < 0.95 else 0.0
			_place_orbit_arc(r, origin, i, count, spin)
			r.refresh()
		if taut > 0.7:
			_try_orbit_hits(origin, profile.a4_radius, profile.a4_damage, profile.a4_hitstop)
	else:
		_move_phase = &"recover"
		var rt := (_move_t - start_t - active_t) / maxf(0.01, recover_t)
		for r in _orbit_renderers:
			r.dissolve_progress = rt
			r.fade = 1.0 - rt
			r.tension = 0.1
			r.refresh()
		_announce_once(&"DISSOLVE", {"move": &"a4"})
	# Keep main renderer quiet during orbit — space itself owns the chains.
	if _renderer != null:
		_renderer.clear()
	if _move_t >= total:
		for r in _orbit_renderers:
			r.clear()
		_finish_move()


func _place_orbit_arc(r: PhantomChainRenderer, origin: Vector3, index: int, count: int, spin: float) -> void:
	var base := TAU * float(index) / float(count)
	var radius := profile.a4_radius * lerpf(0.72, 1.0, float(index % 2))
	var height := lerpf(-0.35, 0.55, float(index) / float(maxi(count - 1, 1)))
	var a0 := base + spin
	var a1 := a0 + deg_to_rad(110.0)
	var p0 := origin + Vector3(cos(a0) * radius, height, sin(a0) * radius)
	var p1 := origin + Vector3(cos(a1) * radius, height * 0.85, sin(a1) * radius)
	var mid_a := (a0 + a1) * 0.5
	var ctrl := origin + Vector3(cos(mid_a) * radius * 1.05, height + 0.2, sin(mid_a) * radius * 1.05)
	r.set_endpoints(p0, p1, ctrl)


func _ensure_orbit_renderers(count: int) -> void:
	while _orbit_renderers.size() < count:
		var r := PhantomChainRenderer.new()
		r.name = "OrbitChain%d" % _orbit_renderers.size()
		add_child(r)
		r.configure(profile)
		r.debug_draw = debug_draw
		_orbit_renderers.append(r)


# ---------------------------------------------------------------- hits (geometry, not links)

func _try_arc_hits(
	move_id: StringName, hand: Vector3, facing: Vector3, _right: Vector3,
	yaw0: float, yaw1: float, u: float, range_m: float, damage: float, stop: float
) -> void:
	var yaw := lerpf(yaw0, yaw1, clampf(u, 0.0, 1.0))
	var tip := hand + facing.rotated(Vector3.UP, yaw) * range_m + Vector3.UP * 0.1
	# Sample a few spheres along the current arc segment.
	for s in 5:
		var p := hand.lerp(tip, float(s) / 4.0)
		for target in _query_sphere(p, 0.55):
			if _hit_done.has(target):
				continue
			_hit_done[target] = true
			_apply_damage(target, damage)
			_hitstop(stop)
			hit_landed.emit(move_id, target)
			_renderer.tension = 1.0
			_renderer.hit_flash = 1.0
			_announce(&"CLINK", {"move": move_id, "target": target})
			_cam_nudge(Vector2(0.0, -0.008), 0.04 if move_id == &"a1" else 0.055)


func _try_orbit_hits(origin: Vector3, radius: float, damage: float, stop: float) -> void:
	for target in _query_sphere(origin, radius):
		if _hit_done.has(target):
			continue
		var flat := target.global_position - origin
		flat.y = 0.0
		if flat.length() > radius + 0.5:
			continue
		_hit_done[target] = true
		_apply_damage(target, damage)
		_hitstop(stop)
		hit_landed.emit(&"a4", target)
		_announce(&"CLINK", {"move": &"a4", "target": target})


func _query_forward_target(range_m: float) -> Node3D:
	var hand := _hand_world()
	var facing := _facing()
	var best: Node3D = null
	var best_d := range_m + 0.01
	for target in _query_sphere(hand + facing * (range_m * 0.55), range_m * 0.65):
		var d := _player.global_position.distance_to(target.global_position)
		var to := target.global_position - _player.global_position
		to.y = 0.0
		if to.normalized().dot(facing) < 0.25:
			continue
		if d < best_d:
			best_d = d
			best = target
	return best


func _query_sphere(center: Vector3, radius: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var space := _player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = HURTBOX_MASK
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for hit in space.intersect_shape(params, 16):
		var area: Area3D = hit.get("collider")
		if area == null or not (area is CombatHurtbox):
			continue
		var actor: Node3D = (area as CombatHurtbox).owner_actor
		if actor == null or actor == _player:
			continue
		if not out.has(actor):
			out.append(actor)
	return out


func _apply_damage(target: Node3D, damage: float) -> void:
	var hit := {
		"damage": damage,
		"poise_damage": damage * 0.6,
		"element": &"physical",
		"element_scale": 1.0,
		"impulse": 1.2,
		"source": _player,
		"target": target,
	}
	var hurt: CombatHurtbox = target.get_node_or_null("Hurtbox") as CombatHurtbox
	if hurt != null:
		hurt.receive_hit(hit)
	elif target.has_method("receive_hit"):
		target.call("receive_hit", hit)


# ---------------------------------------------------------------- hand / camera / audio

func _ensure_hand_pose() -> void:
	if _weapon_root == null:
		return
	_hand_pose = _weapon_root.get_node_or_null("PhantomHandPose") as Node3D
	if _hand_pose == null:
		_hand_pose = Node3D.new()
		_hand_pose.name = "PhantomHandPose"
		_weapon_root.add_child(_hand_pose)
		# Right-hand pocket, camera space.
		_hand_pose.position = Vector3(0.28, -0.22, -0.45)


func _play_hand(kind: StringName, seconds: float) -> void:
	if _hand_pose == null:
		return
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	_hand_tween = create_tween()
	_hand_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var home := Vector3(0.28, -0.22, -0.45)
	var home_r := Vector3(0.15, 0.0, 0.0)
	match kind:
		&"equip":
			_hand_pose.position = home + Vector3(0.0, -0.12, 0.05)
			_hand_tween.tween_property(_hand_pose, "position", home + Vector3(0.02, 0.04, -0.08), seconds * 0.45)
			_hand_tween.parallel().tween_property(_hand_pose, "rotation", Vector3(-0.2, 0.15, 0.1), seconds * 0.45)
			_hand_tween.tween_property(_hand_pose, "position", home, seconds * 0.55)
			_hand_tween.parallel().tween_property(_hand_pose, "rotation", home_r, seconds * 0.55)
		&"sweep":
			_hand_pose.position = home + Vector3(0.25, 0.05, -0.1)
			_hand_pose.rotation = Vector3(0.1, 0.6, -0.2)
			_hand_tween.tween_property(_hand_pose, "position", home + Vector3(-0.35, 0.02, -0.2), seconds)
			_hand_tween.parallel().tween_property(_hand_pose, "rotation", Vector3(0.2, -0.9, 0.25), seconds)
		&"snap":
			_hand_pose.position = home + Vector3(-0.3, 0.0, -0.15)
			_hand_pose.rotation = Vector3(0.15, -0.7, 0.2)
			_hand_tween.tween_property(_hand_pose, "position", home + Vector3(0.32, -0.02, -0.18), seconds)
			_hand_tween.parallel().tween_property(_hand_pose, "rotation", Vector3(0.1, 0.85, -0.15), seconds)
		&"bind":
			_hand_pose.position = home
			_hand_tween.tween_property(_hand_pose, "position", home + Vector3(0.05, 0.08, -0.35), seconds * 0.55)
			_hand_tween.parallel().tween_property(_hand_pose, "rotation", Vector3(-0.45, 0.1, 0.0), seconds * 0.55)
			_hand_tween.tween_property(_hand_pose, "position", home + Vector3(0.02, 0.0, -0.2), seconds * 0.45)
		&"orbit":
			_hand_pose.position = home
			_hand_tween.tween_property(_hand_pose, "position", home + Vector3(0.15, 0.12, -0.15), seconds * 0.4)
			_hand_tween.parallel().tween_property(_hand_pose, "rotation", Vector3(-0.2, 0.0, 0.35), seconds * 0.4)
			_hand_tween.tween_property(_hand_pose, "position", home + Vector3(-0.12, 0.1, -0.12), seconds * 0.6)
			_hand_tween.parallel().tween_property(_hand_pose, "rotation", Vector3(-0.15, 0.0, -0.35), seconds * 0.6)
		_:
			_hand_tween.tween_property(_hand_pose, "position", home, seconds)
			_hand_tween.parallel().tween_property(_hand_pose, "rotation", home_r, seconds)


func _reset_hand() -> void:
	if _hand_pose == null:
		return
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
	_hand_pose.position = Vector3(0.28, -0.22, -0.45)
	_hand_pose.rotation = Vector3(0.15, 0.0, 0.0)


func _hand_world() -> Vector3:
	if _hand_pose != null:
		return _hand_pose.global_position
	if _weapon_root != null:
		return _weapon_root.global_position + Vector3(0.25, -0.15, -0.4)
	return _player.global_position + Vector3.UP * 1.2 + _facing() * 0.4


func _facing() -> Vector3:
	if _look != null:
		var f := -_look.global_transform.basis.z
		f.y = 0.0
		if f.length_squared() > 0.0001:
			return f.normalized()
	var f2 := -_player.global_transform.basis.z
	f2.y = 0.0
	return f2.normalized() if f2.length_squared() > 0.0001 else Vector3.FORWARD


func _cam_nudge(dir: Vector2, trauma: float) -> void:
	if _camera_fb == null:
		return
	_camera_fb.add_impulse(dir, 1.0)
	_camera_fb.add_trauma(trauma)


func _hitstop(seconds: float) -> void:
	if _time_fx != null and seconds > 0.0:
		_time_fx.request_hitstop(seconds)


func _update_visuals(delta: float) -> void:
	if _renderer != null and _renderer.hit_flash > 0.0 and state != State.ATTACK:
		_renderer.hit_flash = maxf(0.0, _renderer.hit_flash - delta * 5.0)
		_renderer.refresh()


func _build_visuals() -> void:
	_renderer = PhantomChainRenderer.new()
	_renderer.name = "PhantomChainRenderer"
	add_child(_renderer)
	_renderer.configure(profile)
	_vfx = PhantomChainVFX.new()
	_vfx.name = "PhantomChainVFX"
	add_child(_vfx)
	_vfx.configure(profile)


func _build_audio() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.name = "PhantomChainAudio"
	_audio.bus = &"Master"
	_audio.volume_db = -10.0
	add_child(_audio)
	# Tiny procedural click bank — metal+void without shipping assets.
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 0.1
	_audio.stream = gen


var _announced: Dictionary = {}


func _announce(event: StringName, data: Dictionary) -> void:
	chain_event.emit(event, data)
	_play_tone(event)


func _announce_once(event: StringName, data: Dictionary) -> void:
	var key := "%s:%s" % [String(_move_id), String(event)]
	if _announced.has(key):
		return
	_announced[key] = true
	_announce(event, data)


func _play_tone(event: StringName) -> void:
	if _audio == null or not (_audio.stream is AudioStreamGenerator):
		return
	if not _audio.playing:
		_audio.play()
	var playback := _audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var freq := 880.0
	var dur := 0.04
	var amp := 0.18
	match event:
		&"MATERIALIZE":
			freq = 1240.0
			dur = 0.05
			amp = 0.12
		&"CLINK", &"LOCK":
			freq = 1560.0
			dur = 0.06
			amp = 0.22
		&"SNAP", &"TENSION":
			freq = 620.0
			dur = 0.07
			amp = 0.16
		&"PULL":
			freq = 480.0
			dur = 0.08
			amp = 0.18
		&"DISSOLVE":
			freq = 980.0
			dur = 0.05
			amp = 0.08
	var frames := int(dur * 22050.0)
	for i in mini(frames, playback.get_frames_available()):
		var t := float(i) / 22050.0
		var env := exp(-t * 28.0)
		var s := sin(TAU * freq * t) * amp * env
		# Soft void under-tone.
		s += sin(TAU * (freq * 0.33) * t) * amp * 0.35 * env
		playback.push_frame(Vector2(s, s))


# Debug helpers for movie / tests.
func debug_state() -> Dictionary:
	return {
		"state": State.keys()[state],
		"combo": combo_index,
		"move": String(_move_id),
		"bind": _bind_target != null,
		"tension": _bind_tension if _bind_target != null else (_renderer.tension if _renderer else 0.0),
		"max_dist": _bind_max,
		"target": _bind_target,
	}
