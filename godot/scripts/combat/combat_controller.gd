extends Node
class_name CombatController
# SEKAI · Universal Sword Layer + sword styles.
#
# The controller owns the LANGUAGE (startup / strike / follow / recovery, guard,
# perfect guard, riposte, cancels, buffering). The SwordMoveset only overrides
# numbers and poses. No style gets its own CombatController.

enum State {
	IDLE,
	ATTACK,
	CHARGE,
	BLOCK,
	PARRY,
	RIPOSTE,
	DODGE,
	CAST,
	SKILL,
	STAGGER,
	IAIDO,
	ULTIMATE,
}

signal state_changed(previous: State, current: State)
signal style_changed(style_id: StringName)
signal move_started(move: SwordMove)
signal hit_landed(move: SwordMove, hit: Dictionary)
signal perfect_guard_landed()
signal style_message(text: String)

@export var tuning: CombatTuning = preload("res://resources/tuning/CombatTuning.tres")
@export var frost_ability: AbilityData = preload("res://resources/abilities/frost_stream.tres")
@export var fire_ability: AbilityData = preload("res://resources/abilities/fire_cast.tres")
@export var wind_ability: AbilityData = preload("res://resources/abilities/wind_burst.tres")
@export var starting_style: StringName = &"universal"

@onready var player: CharacterBody3D = get_parent()
@onready var hitbox: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/SwordHitbox")
@onready var frost_hitbox: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/FrostHitbox")
@onready var fire_hitbox: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/FireHitbox")
@onready var wind_hitbox: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/WindHitbox")
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var magic_circle: MagicCircle3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/MagicCircle3D")
@onready var hurtbox: CombatHurtbox = player.get_node("Hurtbox")
@onready var dodge_audio: AudioStreamPlayer = player.get_node("DodgeAudio")
@onready var screen_fx: CombatScreenFX = player.get_parent().get_node("CombatScreenFX")
@onready var time_effects: TimeEffectManager = player.get_parent().get_node("TimeEffectManager")
@onready var iaido_director: IaidoDirector = player.get_parent().get_node("IaidoDirector")
@onready var ultimate_director: Node = player.get_parent().get_node_or_null("MomentOfNoMoonDirector")

var state := State.IDLE
var state_time := 0.0
var buffer := CombatInputBuffer.new()
var attack_kind: StringName = &""
var hitbox_open := false
var dodge_direction := Vector3.FORWARD
var dodge_speed := 11.0
var perfect_guard_count := 0
var combo_index := 0
var last_light_at := -10.0
var selected_spell: StringName = &"frost"
var casting_spell: StringName = &"frost"
var iaido_ready_at := 0.0
var ultimate_ready_at := 0.0

# --- style state -------------------------------------------------------------
var movesets: Dictionary = {}
var moveset: SwordMoveset
var style_id: StringName = &"universal"
var active_move: SwordMove
var active_skill: SwordSkill
var active_move_id: StringName = &""
var move_hit := false
var move_startup_override := -1.0
var move_startup_scale := 1.0
var move_poise_scale := 1.0
var charge_ratio := 0.0
var chain_expires_at := 0.0
var chain_active := false
var riposte_until := 0.0
var followup_until := 0.0
var pending_followup_id: StringName = &""
var edge_glint := false
var next_move_startup_scale := 1.0
var skill_cooldowns: Dictionary = {}
var guard_recoil := 0.0
var parry_lateral := 0.0
var sheath_amount := 0.0
var idle_time := 0.0
var hitstop_scale := 1.0
var pose_time := 0.0
var hits_landed := 0
var last_hit_strength := 0.0

# --- enhance state (纳息) ----------------------------------------------------
var enhance_left := 0.0
var enhance_startup_scale := 1.0
var enhance_perfect_guard_bonus := 0.0
var enhance_first_hit_poise_scale := 1.0
var enhance_skill_id: StringName = &""


func _ready() -> void:
	buffer.duration = tuning.input_buffer
	hitbox.source = player
	frost_hitbox.source = player
	fire_hitbox.source = player
	wind_hitbox.source = player
	_bind_key("heavy_attack", KEY_F)
	_bind_key("fire_cast", KEY_Z)
	_bind_key("frost_cast", KEY_R)
	_bind_key("wind_cast", KEY_C)
	_bind_key("iaido", KEY_I)
	_bind_key("cast_selected", KEY_E)
	_bind_key("style_skill_1", KEY_1)
	_bind_key("style_skill_2", KEY_2)
	_bind_key("style_skill_3", KEY_3)
	_bind_key("ultimate", KEY_X)
	hurtbox.hit_received.connect(_on_player_hit)
	hitbox.hit_landed.connect(_on_hitbox_landed)
	_bind_mouse("light_attack", MOUSE_BUTTON_LEFT)
	_bind_mouse("block", MOUSE_BUTTON_RIGHT)
	movesets = SwordMovesetLibrary.build_all()
	set_style(starting_style, true)


func _bind_key(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func _bind_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("light_attack"):
		request(&"light")
	elif event.is_action_pressed("heavy_attack"):
		request(&"heavy")
	elif event.is_action_released("heavy_attack") and state == State.CHARGE:
		release_heavy()
	elif event.is_action_pressed("style_skill_1"):
		trigger_skill(0)
	elif event.is_action_pressed("style_skill_2"):
		trigger_skill(1)
	elif event.is_action_pressed("style_skill_3"):
		trigger_skill(2)
	elif event.is_action_pressed("fire_cast"):
		selected_spell = &"fire"
		request(&"cast")
	elif event.is_action_pressed("frost_cast"):
		selected_spell = &"frost"
		request(&"cast")
	elif event.is_action_pressed("wind_cast"):
		selected_spell = &"wind"
		request(&"cast")
	elif event.is_action_pressed("dodge"):
		request(&"dodge")
	elif event.is_action_pressed("iaido"):
		request(&"iaido")
	elif event.is_action_pressed("ultimate"):
		request(&"ultimate")
	elif event.is_action_pressed("cast_selected"):
		request(&"cast")
	elif event.is_action_pressed("block"):
		request(&"block")
	elif event.is_action_released("block") and state in [State.BLOCK, State.PARRY]:
		finish_action()


# ---------------------------------------------------------------- lifecycle

func _process(delta: float) -> void:
	state_time += delta
	pose_time += delta
	guard_recoil = maxf(0.0, guard_recoil - delta * 3.2)
	if enhance_left > 0.0:
		enhance_left = maxf(0.0, enhance_left - delta)
		if enhance_left == 0.0:
			style_message.emit("纳息 · 结束")
	_update_sheath(delta)

	match state:
		State.ATTACK, State.RIPOSTE, State.SKILL:
			_process_move()
		State.CHARGE:
			_process_charge(delta)
		State.CAST:
			_process_cast()
		State.DODGE:
			if state_time >= 0.36:
				finish_action()


func _process_move() -> void:
	if active_move == null:
		finish_action()
		return
	var startup := effective_startup()
	var strike_end := startup + active_move.strike
	var should_open := (
		active_move.damage > 0.0
		and state_time >= startup
		and state_time < strike_end
	)
	if should_open != hitbox_open:
		hitbox_open = should_open
		hitbox.set_active(should_open)
	if state_time >= _move_end_time():
		finish_action()


func _process_charge(delta: float) -> void:
	if active_move == null:
		finish_action()
		return
	if Input.is_action_pressed("heavy_attack"):
		charge_ratio = minf(1.0, charge_ratio + delta / maxf(tuning.heavy_charge_time, 0.05))
		return
	# Programmatic or released: a short press is a tap Heavy, never a stuck state.
	if state_time >= tuning.heavy_tap_grace or charge_ratio >= 1.0:
		release_heavy()


func _process_cast() -> void:
	var ability := _current_ability()
	var should_open := state_time >= ability.startup and state_time < ability.startup + ability.active
	if should_open != hitbox_open:
		hitbox_open = should_open
		_current_spell_hitbox().set_active(should_open)
	if state_time >= ability.startup + ability.active + ability.recovery:
		finish_action()


func _update_sheath(delta: float) -> void:
	if not moveset.sheath_enabled:
		sheath_amount = 0.0
		idle_time = 0.0
		return
	if state == State.IDLE:
		idle_time += delta
		if idle_time >= moveset.sheath_delay:
			var speed := 1.0 / maxf(moveset.sheath_time * _sheathe_time_scale(), 0.05)
			sheath_amount = minf(1.0, sheath_amount + delta * speed)
	else:
		idle_time = 0.0
		# Drawing is never slow: the strike itself covers the motion.
		sheath_amount = maxf(0.0, sheath_amount - delta / 0.08)


func _sheathe_time_scale() -> float:
	if enhance_left <= 0.0 or enhance_skill_id == &"":
		return 1.0
	var skill := moveset.get_skill(enhance_skill_id)
	if skill == null or skill.kind != SwordSkill.Kind.ENHANCE:
		return 1.0
	return skill.enhance_sheathe_scale


# ------------------------------------------------------------------ requests

func request(action: StringName) -> bool:
	var now := _now()
	# Riposte is a real reward window: Light inside it always wins.
	if action == &"light" and _riposte_open(now):
		return _start_riposte()
	# 燕返 follow-up: only exists after the first cut connected.
	if action in [&"light", &"skill"] and _followup_open(now):
		return _start_followup()
	if state == State.IDLE:
		return _start(action)
	if _can_cancel(action):
		return _start(action)
	# Buffering a 7-second ceremony would be a trap; drop it instead.
	if action in [&"iaido", &"ultimate"]:
		return false
	buffer.push(action, now)
	return false


func _can_cancel(action: StringName) -> bool:
	match state:
		State.PARRY:
			return action in [&"light", &"dodge", &"block"]
		State.ATTACK, State.RIPOSTE:
			if active_move == null:
				return true
			var cancel_at := effective_startup() + active_move.strike + active_move.pose_span() * active_move.cancel_open
			if state_time < cancel_at:
				return false
			if action == &"dodge":
				# Dodging out is allowed once the blade has actually been
				# committed past contact: the swing cannot be free, or attacks
				# stop meaning anything. 回风 opens earliest, 藏锋 latest.
				return state_time >= effective_startup() + active_move.strike * moveset.dodge_cancel_from
			return action in [&"light", &"heavy", &"block"]
		State.SKILL:
			return action == &"dodge" and state_time >= 0.12
		State.CHARGE:
			return action in [&"dodge", &"block"]
		_:
			return false


func _can_act_now() -> bool:
	return state == State.IDLE or _can_cancel(&"light")


func finish_action() -> void:
	if state == State.SKILL:
		_finish_skill()
	_close_hitbox()
	magic_circle.set_casting(false)
	if state == State.IAIDO:
		screen_fx.reset()
		camera_feedback.fov_hold = 0.0
		time_effects.reset()
	hitbox_open = false
	active_move = null
	active_skill = null
	active_move_id = &""
	move_startup_override = -1.0
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	charge_ratio = 0.0
	chain_active = false
	# The chain stays open for the style's grace window even if nothing was
	# buffered: the next cut is a continuation, not a restart.
	if attack_kind in [&"light", &"sprint", &"retreat"]:
		chain_expires_at = _now() + moveset.combo_window
	elif buffer.pending != &"":
		chain_expires_at = _now() + moveset.combo_window
	# A follow-up window must not expire before the cut it belongs to has even
	# finished animating, or the player is punished for watching their own move.
	if pending_followup_id != &"":
		followup_until = maxf(followup_until, _now() + tuning.followup_grace)
	set_state(State.IDLE)
	var next := buffer.take(_now())
	if next != &"":
		_start(next)


func set_state(next: State) -> void:
	if state == next:
		return
	var previous := state
	state = next
	state_time = 0.0
	state_changed.emit(previous, next)


func _restart_state(next: State) -> void:
	# Cancelling one attack straight into the next one keeps the same State, so
	# set_state() would skip the reset and the new move would inherit the old
	# move's clock.
	set_state(next)
	state_time = 0.0


# -------------------------------------------------------------------- starts

func _start(action: StringName) -> bool:
	match action:
		&"light":
			return _start_light()
		&"heavy":
			return _start_charge()
		&"block":
			set_state(State.BLOCK)
			return true
		&"dodge":
			return _start_dodge()
		&"cast":
			return _start_cast()
		&"iaido":
			return _start_signature()
		&"ultimate":
			return _start_ultimate()
		_:
			return false


func _start_light() -> bool:
	if not moveset.has_light_chain():
		return false
	var now := _now()
	var chain := moveset.light_chain
	var chosen := false
	if moveset.sprint_light_id != &"" and Input.is_action_pressed("sprint") and player.velocity.length() > 4.0:
		active_move_id = moveset.sprint_light_id
		combo_index = 0
		attack_kind = &"sprint"
		chosen = true
	elif moveset.retreat_light_id != &"" and _retreating():
		active_move_id = moveset.retreat_light_id
		combo_index = 0
		attack_kind = &"retreat"
		chosen = true
	if not chosen:
		# A chain continues while the previous light is still swinging (a cancel
		# into the next cut) or within the style's combo grace after it ended.
		if combo_index > 0 and (chain_active or now <= chain_expires_at):
			combo_index = (combo_index % chain.size()) + 1
		else:
			combo_index = 1
		active_move_id = chain[combo_index - 1]
		attack_kind = &"light"
	var move := moveset.get_move(active_move_id)
	if move == null:
		return false
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	# Sheathed draw bonus: the 藏锋 rhythm pays off only if you actually waited.
	if moveset.sheath_enabled and combo_index == 1 and sheath_amount >= 0.82:
		move_startup_scale *= moveset.sheathed_startup_scale
		move_poise_scale *= moveset.sheathed_poise_scale
		style_message.emit("纳刀 · 拔刀强化")
	if edge_glint and move.id == moveset.guard.glint_move_id:
		edge_glint = false
		move_startup_scale *= moveset.guard.glint_startup_scale
		move_poise_scale *= moveset.guard.glint_poise_scale
	if enhance_left > 0.0:
		move_startup_scale *= enhance_startup_scale
		if combo_index == 1:
			move_poise_scale *= enhance_first_hit_poise_scale
	if next_move_startup_scale != 1.0:
		move_startup_scale *= next_move_startup_scale
		next_move_startup_scale = 1.0
	chain_expires_at = 0.0
	last_light_at = now
	_begin_move(move, State.ATTACK)
	return true


func _start_charge() -> bool:
	var move := moveset.get_move(moveset.heavy_id)
	if move == null:
		return false
	active_move = move
	active_move_id = move.id
	attack_kind = &"heavy"
	move_hit = false
	charge_ratio = 0.0
	move_startup_override = -1.0
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	idle_time = 0.0
	sheath_amount = 0.0
	chain_active = false
	_restart_state(State.CHARGE)
	return true


func release_heavy() -> void:
	if state != State.CHARGE or active_move == null:
		return
	var move := active_move
	var ratio := charge_ratio
	# The wind-up already happened during CHARGE, so the strike is immediate.
	move_startup_override = 0.0
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	move_hit = false
	followup_until = 0.0
	pending_followup_id = &""
	idle_time = 0.0
	sheath_amount = 0.0
	var damage_scale := 1.0
	if ratio > 0.08:
		var t := clampf((ratio - 0.08) / 0.92, 0.0, 1.0)
		move_poise_scale = lerpf(1.0, move.charged_poise_bonus, t)
		damage_scale = lerpf(1.0, move.charged_damage_bonus, t)
		camera_feedback.add_trauma(0.05 * t)
		camera_feedback.fov_kick(-1.2 * t)
	_write_hitbox(move, damage_scale)
	charge_ratio = ratio
	_restart_state(State.ATTACK)
	move_started.emit(move)
	_emit_move_camera(move)


func _start_riposte() -> bool:
	var move := moveset.get_move(moveset.guard.riposte_id)
	if move == null:
		return false
	riposte_until = 0.0
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	# 截锋 lit the edge: the answer out of a perfect guard is faster and heavier.
	if edge_glint and move.id == moveset.guard.glint_move_id:
		edge_glint = false
		move_startup_scale *= moveset.guard.glint_startup_scale
		move_poise_scale *= moveset.guard.glint_poise_scale
	attack_kind = &"riposte"
	_begin_move(move, State.RIPOSTE)
	return true


func _start_followup() -> bool:
	var follow := moveset.get_move(pending_followup_id)
	if follow == null:
		return false
	followup_until = 0.0
	pending_followup_id = &""
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	buffer.clear()
	attack_kind = &"followup"
	_begin_move(follow, State.SKILL)
	return true


func _start_dodge() -> bool:
	var stamina: float = player.get("stamina")
	if not player.unlimited_resources and stamina < tuning.dodge_stamina_cost:
		return false
	if not player.unlimited_resources:
		player.set("stamina", stamina - tuning.dodge_stamina_cost)
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Vector3(input_vector.x, 0, input_vector.y)
	dodge_direction = (player.transform.basis * (wish if wish.length_squared() > 0.01 else Vector3.FORWARD)).normalized()
	camera_feedback.fov_kick(10.0)
	var side := dodge_direction.dot(player.global_basis.x)
	camera_feedback.roll_impulse(side * 3.5)
	camera_feedback.add_impulse(Vector2(0.0, 0.025))
	dodge_audio.play()
	set_state(State.DODGE)
	return true


func _start_cast() -> bool:
	casting_spell = selected_spell
	var mana: float = player.get("mana")
	var ability := _current_ability()
	if not player.unlimited_resources and mana < ability.mana_cost:
		return false
	if not player.unlimited_resources:
		player.set("mana", mana - ability.mana_cost)
	camera_feedback.fov_kick(1.5)
	magic_circle.circle_color = Color(1.0, 0.55, 0.2, 0.85) if casting_spell == &"fire" else (Color(0.75, 0.8, 0.8, 0.8) if casting_spell == &"wind" else Color(0.55, 0.85, 1.0, 0.8))
	magic_circle.set_casting(true)
	set_state(State.CAST)
	return true


func _start_signature() -> bool:
	var now := _now()
	var stamina: float = player.get("stamina")
	if float(player.get("health")) <= 0.0 or iaido_director.active:
		return false
	if not is_instance_valid(player.get_node_or_null("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual")):
		return false
	if now < iaido_ready_at or (not player.unlimited_resources and stamina < 35.0):
		style_message.emit("聚合斩 · 冷却中")
		return false
	if not player.unlimited_resources:
		player.set("stamina", stamina - 35.0)
	# SIGNATURE technique: its own cooldown, and it never occupies Ultimate.
	iaido_ready_at = now + iaido_director.tuning.restore_end + 2.0
	buffer.clear()
	set_state(State.IAIDO)
	iaido_director.start_iaido()
	return true


func _start_ultimate() -> bool:
	if ultimate_director == null or moveset.ultimate_id == &"":
		style_message.emit("此流派尚未习得 Ultimate")
		return false
	if not ultimate_director.has_method("start_moment"):
		return false
	if _now() < ultimate_ready_at:
		style_message.emit("无明一刻 · 冷却中")
		return false
	buffer.clear()
	active_move = null
	_close_hitbox()
	set_state(State.ULTIMATE)
	if not ultimate_director.call("start_moment"):
		set_state(State.IDLE)
		return false
	return true


func _begin_move(move: SwordMove, next_state: State) -> void:
	active_move = move
	active_move_id = move.id
	move_hit = false
	move_startup_override = -1.0
	idle_time = 0.0
	sheath_amount = 0.0
	followup_until = 0.0
	pending_followup_id = &""
	chain_active = attack_kind in [&"light", &"sprint", &"retreat"]
	_write_hitbox(move, 1.0)
	_emit_move_camera(move)
	_restart_state(next_state)
	move_started.emit(move)


func _write_hitbox(move: SwordMove, damage_scale: float) -> void:
	hitbox.configure(move.hitbox_size, move.hitbox_offset)
	hitbox.damage = move.damage * damage_scale
	hitbox.poise_damage = move.poise_damage * move_poise_scale
	hitbox.element = move.element
	hitbox.hit_delay = 0.0


func _emit_move_camera(move: SwordMove) -> void:
	if move.camera_impulse != Vector2.ZERO:
		camera_feedback.add_impulse(move.camera_impulse)
	if move.camera_roll != 0.0:
		camera_feedback.roll_impulse(move.camera_roll)
	if move.fov_kick != 0.0:
		camera_feedback.fov_kick(move.fov_kick)
	if move.trauma > 0.0:
		camera_feedback.add_trauma(move.trauma)


# ------------------------------------------------------------------- skills

func trigger_skill(index: int) -> bool:
	if index < 0 or index >= moveset.skills.size():
		return false
	var skill: SwordSkill = moveset.skills[index]
	if _now() < float(skill_cooldowns.get(skill.id, 0.0)):
		style_message.emit("%s · 冷却中" % skill.display_name)
		return false
	var move := moveset.get_move(skill.move_id)
	if move == null:
		return false
	if not _can_act_now():
		return false
	if state != State.IDLE:
		_close_hitbox()
	active_skill = skill
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	if enhance_left > 0.0:
		move_startup_scale *= enhance_startup_scale
	attack_kind = &"skill"
	_begin_move(move, State.SKILL)
	skill_cooldowns[skill.id] = _now() + skill.cooldown
	style_message.emit(skill.display_name)
	return true


func _finish_skill() -> void:
	var skill := active_skill
	if skill == null:
		return
	if skill.kind == SwordSkill.Kind.ENHANCE:
		enhance_left = skill.enhance_duration
		enhance_startup_scale = skill.enhance_startup_scale
		enhance_perfect_guard_bonus = skill.enhance_perfect_guard_bonus
		enhance_first_hit_poise_scale = skill.enhance_first_hit_poise_scale
		enhance_skill_id = skill.id
		style_message.emit("纳息 · 生效")


func skill_cooldown_left(index: int) -> float:
	if index < 0 or index >= moveset.skills.size():
		return 0.0
	var skill: SwordSkill = moveset.skills[index]
	return maxf(0.0, float(skill_cooldowns.get(skill.id, 0.0)) - _now())


func reset_skill_cooldowns() -> void:
	skill_cooldowns.clear()
	iaido_ready_at = 0.0
	ultimate_ready_at = 0.0


func signature_cooldown_left() -> float:
	return maxf(0.0, iaido_ready_at - _now())


func ultimate_cooldown_left() -> float:
	return maxf(0.0, ultimate_ready_at - _now())


func notify_ultimate_finished() -> void:
	set_state(State.IDLE)


# -------------------------------------------------------------------- styles

func set_style(wanted: StringName, force: bool = false) -> bool:
	if movesets.is_empty():
		movesets = SwordMovesetLibrary.build_all()
	if not movesets.has(wanted):
		return false
	if not force and wanted == style_id:
		return false
	if not force and state != State.IDLE:
		style_message.emit("切换流派需要先站稳")
		return false
	moveset = movesets[wanted]
	style_id = moveset.style_id
	active_move = null
	active_move_id = &""
	combo_index = 0
	chain_expires_at = 0.0
	enhance_left = 0.0
	enhance_skill_id = &""
	edge_glint = false
	guard_recoil = 0.0
	parry_lateral = 0.0
	sheath_amount = 0.0
	idle_time = 0.0
	style_changed.emit(style_id)
	style_message.emit(moveset.display_name)
	return true


# ------------------------------------------------------------------ movement

func movement_scale() -> float:
	match state:
		State.IDLE:
			return 1.0
		State.ATTACK, State.RIPOSTE, State.SKILL:
			return active_move.steer if active_move != null else 0.2
		State.CHARGE:
			return 0.22
		State.BLOCK:
			return moveset.guard.move_scale
		State.PARRY:
			return 0.12
		State.CAST:
			return 0.35
		State.STAGGER:
			return 0.10
		_:
			return 0.0


func attack_lunge_velocity() -> Vector3:
	if state == State.PARRY:
		# 回风's perfect guard can leave the line immediately.
		if is_zero_approx(parry_lateral):
			return Vector3.ZERO
		return player.global_transform.basis.x * parry_lateral * 4.0
	if active_move == null or is_zero_approx(active_move.lunge):
		return Vector3.ZERO
	if state not in [State.ATTACK, State.RIPOSTE, State.SKILL]:
		return Vector3.ZERO
	var duration := active_move.strike
	var base := 0.0 if move_startup_override >= 0.0 else effective_startup()
	var start := maxf(0.0, base - duration * active_move.lunge_lead)
	var end := start + duration * (1.0 + active_move.lunge_lead)
	if state_time < start or state_time >= end:
		return Vector3.ZERO
	var span := maxf(end - start, 0.0001)
	var u := (state_time - start) / span
	# sin() shape: peak speed mid-window, whole displacement == move.lunge.
	var amplitude := active_move.lunge * PI / (2.0 * span)
	var forward := -player.global_transform.basis.z
	return forward * signf(active_move.lunge) * amplitude * sin(u * PI)


func is_sheathed() -> bool:
	return moveset.sheath_enabled and sheath_amount >= 0.82


func dodge_speed_now() -> float:
	if state_time < 0.05:
		return 0.0
	if state_time < 0.12:
		return dodge_speed * smoothstep(0.05, 0.12, state_time)
	if state_time < 0.20:
		return dodge_speed
	var tail := clampf((state_time - 0.20) / 0.16, 0.0, 1.0)
	return dodge_speed * (1.0 - tail) * (1.0 - tail)


# ---------------------------------------------------------------------- pose

func effective_startup() -> float:
	if active_move == null:
		return 0.0
	if move_startup_override >= 0.0:
		return move_startup_override
	return active_move.startup * move_startup_scale


func recovery_scale() -> float:
	if active_move == null:
		return 1.0
	var scale := active_move.recovery_scale
	if move_hit:
		scale *= active_move.hit_recovery_scale
		if moveset.flow_on_hit_recovery < 1.0:
			scale *= moveset.flow_on_hit_recovery
	else:
		scale *= active_move.miss_recovery_scale
	if scale < 1.0:
		var floor_scale := moveset.flow_min_recovery / maxf(active_move.recovery, 0.001)
		scale = maxf(scale, floor_scale)
	return scale


func _move_end_time() -> float:
	if active_move == null:
		return 0.0
	return effective_startup() + active_move.strike + active_move.pose_span() * recovery_scale()


func pose_snapshot() -> Dictionary:
	var position := moveset.idle_pose
	var rotation := moveset.idle_pose_rot
	var intensity := 0.0
	var stiffness := moveset.pose_stiffness
	match state:
		State.ATTACK, State.RIPOSTE, State.SKILL:
			if active_move != null:
				var sampled := SwordPoseSampler.sample(active_move, state_time, recovery_scale())
				position = sampled.position
				rotation = sampled.rotation
				intensity = sampled.intensity
		State.CHARGE:
			if active_move != null:
				# The anticipation is stretched across the whole charge.
				var t := minf(state_time / maxf(tuning.heavy_charge_time, 0.05), 1.0) * active_move.startup * 0.985
				var sampled := SwordPoseSampler.sample(active_move, t)
				position = sampled.position
				rotation = sampled.rotation
				intensity = 0.35 + charge_ratio * 0.4
				stiffness = moveset.pose_stiffness * 1.15
		State.BLOCK:
			position = moveset.guard.pose
			rotation = moveset.guard.pose_rot
			if guard_recoil > 0.0:
				var k := clampf(guard_recoil, 0.0, 1.0)
				position = position.lerp(moveset.guard.parry_pose, k)
				rotation = rotation.lerp(moveset.guard.parry_pose_rot, k)
			intensity = 0.2
		State.PARRY:
			var guard := moveset.guard
			var u := clampf(state_time / maxf(guard.parry_duration, 0.01), 0.0, 1.0)
			if u < 0.35:
				var k := SwordPoseSampler.ease_in(u / 0.35, 1.6)
				position = guard.pose.lerp(guard.parry_pose, k)
				rotation = guard.pose_rot.lerp(guard.parry_pose_rot, k)
			else:
				var k := SwordPoseSampler.ease_out((u - 0.35) / 0.65, 2.0)
				position = guard.parry_pose.lerp(moveset.idle_pose, k)
				rotation = guard.parry_pose_rot.lerp(moveset.idle_pose_rot, k)
			intensity = 0.6
		State.DODGE:
			var side := dodge_direction.dot(player.global_basis.x)
			position = moveset.idle_pose + Vector3(-side * 0.16, -0.12, 0.1)
			rotation = moveset.idle_pose_rot + Vector3(-0.2, 0.0, -side * 0.28)
			intensity = 0.3
		State.STAGGER:
			position = moveset.idle_pose + Vector3(0.0, -0.16, 0.10)
			rotation = moveset.idle_pose_rot + Vector3(0.30, 0.0, 0.0)
			intensity = 0.15
		State.CAST:
			position = moveset.idle_pose + Vector3(-0.04, -0.05, -0.06)
			intensity = 0.25
		_:
			pass
	# 归鞘 is a pose, not an effect on top: the whole weapon travels to the hip
	# so the next draw reads as an actual draw.
	if moveset.sheath_enabled and sheath_amount > 0.0 and state in [State.IDLE, State.STAGGER]:
		var s := SwordPoseSampler.ease_out(sheath_amount, 1.5)
		position = position.lerp(moveset.sheath_pose, s)
		rotation = rotation.lerp(moveset.sheath_pose_rot, s)
	if Input.is_action_pressed("sprint") and player.velocity.length() > 2.0 and state == State.IDLE:
		position.y -= 0.13
		rotation.z -= 0.12
	else:
		# Look-lag keeps the weapon attached to a body, not bolted to the camera.
		position.x -= camera_feedback.look_lag.x * 0.30
		position.y += camera_feedback.look_lag.y * 0.22
	return {
		"position": position,
		"rotation": rotation,
		"stiffness": stiffness,
		"damping": moveset.pose_damping,
		"tremor": moveset.tremor,
		"intensity": intensity,
		"trail_width": moveset.trail_width,
		"sheath": sheath_amount,
		"style": style_id,
		"move_id": active_move_id,
	}


# ----------------------------------------------------------------- enemy hit

func _on_hitbox_landed(hit: Dictionary) -> void:
	if active_move == null:
		return
	move_hit = true
	hits_landed += 1
	var target = hit.get("target")
	# 断章: only meaningful against an enemy that was mid-action.
	if active_move.interrupt_bonus > 1.0 and target != null and target.has_method("is_telegraphing") and target.call("is_telegraphing"):
		hit["damage"] = float(hit.get("damage", 0.0)) * active_move.interrupt_bonus
		hit["poise_damage"] = float(hit.get("poise_damage", 0.0)) * active_move.interrupt_bonus
		hit["interrupt"] = true
		time_effects.request_hitstop(0.075 * hitstop_scale)
		screen_fx.flash_hit(0.16)
		style_message.emit("断章 · INTERRUPT")
	else:
		if active_move.frozen_bonus != 1.0:
			hit["frozen_bonus"] = active_move.frozen_bonus
		if hitstop_scale > 0.0:
			time_effects.request_hitstop(active_move.hitstop * hitstop_scale)
	hit_landed.emit(active_move, hit)
	last_hit_strength = clampf(float(hit.get("damage", 0.0)) / 40.0, 0.2, 1.6)
	camera_feedback.add_impulse(active_move.camera_impulse * 1.7 + Vector2(0.0, 0.004))
	camera_feedback.add_trauma(0.06 + active_move.trauma)
	screen_fx.flash_hit(0.09 * hitstop_scale if hitstop_scale > 0.0 else 0.045)
	if active_move.on_hit_next_startup_scale != 1.0:
		next_move_startup_scale = active_move.on_hit_next_startup_scale
	if active_move.followup_id != &"":
		pending_followup_id = active_move.followup_id
		followup_until = _now() + active_move.followup_window


func _on_player_hit(hit: Dictionary) -> void:
	if state == State.DODGE and state_time < 0.2:
		return
	if state in [State.BLOCK, State.PARRY]:
		var guard := moveset.guard
		var heavy := float(hit.get("poise_damage", 0.0)) >= 35.0
		var window := guard.perfect_guard_window
		if enhance_left > 0.0:
			window += enhance_perfect_guard_bonus
		if state == State.BLOCK and state_time <= window:
			_perfect_guard(hit)
			return
		var stamina: float = player.get("stamina")
		var cost := guard.stamina_per_hit * (guard.heavy_stamina_multiplier if heavy else 1.0)
		if not player.unlimited_resources:
			player.set("stamina", maxf(0.0, stamina - cost))
		var block_scale := 1.0 + (0.9 if heavy else 0.0)
		guard_recoil = minf(1.0, guard_recoil + 0.55 * block_scale)
		camera_feedback.add_trauma(0.10 * block_scale)
		camera_feedback.add_impulse(Vector2(-0.012, -0.010) * block_scale)
		return
	var damage := float(hit.get("damage", 0.0))
	var health: float = player.get("health")
	player.set("health", maxf(0.0, health - damage))
	camera_feedback.add_trauma(0.12)
	camera_feedback.add_impulse(Vector2(0.01, -0.016))
	if damage >= tuning.player_stagger_threshold and state not in [State.IAIDO, State.ULTIMATE]:
		# You cannot spam through an enemy heavy: this is what makes Guard a
		# decision instead of decoration.
		_close_hitbox()
		active_move = null
		buffer.clear()
		set_state(State.STAGGER)
		get_tree().create_timer(0.26).timeout.connect(func() -> void:
			if is_instance_valid(self) and state == State.STAGGER:
				set_state(State.IDLE)
		)


func _perfect_guard(hit: Dictionary) -> void:
	var guard := moveset.guard
	perfect_guard_count += 1
	_close_hitbox()
	var attacker: Node = hit.get("source")
	if attacker != null and attacker.has_method("on_perfect_guard"):
		attacker.call("on_perfect_guard")
	if hitstop_scale > 0.0:
		time_effects.request_hitstop(guard.perfect_guard_hitstop * hitstop_scale)
	camera_feedback.add_impulse(guard.perfect_guard_impulse)
	camera_feedback.add_trauma(guard.perfect_guard_trauma)
	camera_feedback.fov_kick(-2.0)
	screen_fx.flash_hit(0.18)
	guard_recoil = 1.0
	edge_glint = true
	riposte_until = _now() + guard.riposte_window
	if guard.parry_steer > 0.0:
		var side := 1.0 if not Input.is_action_pressed("move_left") else -1.0
		parry_lateral = side * guard.parry_steer
		get_tree().create_timer(guard.parry_duration + 0.12).timeout.connect(func() -> void:
			if is_instance_valid(self):
				parry_lateral = 0.0
		)
	set_state(State.PARRY)
	state_time = 0.0
	perfect_guard_landed.emit()
	style_message.emit("截锋 · RIPOSTE 窗口")


# -------------------------------------------------------------------- helpers

func _close_hitbox() -> void:
	hitbox.set_active(false)
	hitbox.hit_delay = 0.0
	frost_hitbox.set_active(false)
	fire_hitbox.set_active(false)
	wind_hitbox.set_active(false)
	hitbox_open = false


func _riposte_open(now: float) -> bool:
	return now <= riposte_until and state in [State.IDLE, State.PARRY]


func _followup_open(now: float) -> bool:
	return now <= followup_until and pending_followup_id != &""


func _retreating() -> bool:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return input_vector.y > 0.4


func _current_ability() -> AbilityData:
	match casting_spell:
		&"fire": return fire_ability
		&"wind": return wind_ability
		_: return frost_ability


func _current_spell_hitbox() -> CombatHitbox:
	match casting_spell:
		&"fire": return fire_hitbox
		&"wind": return wind_hitbox
		_: return frost_hitbox


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func debug_state_line() -> String:
	var move_name := active_move.display_name if active_move != null else "-"
	return "%s · %s · %.2fs · glint=%s · sheathed=%.2f · chain=%d" % [
		moveset.display_name, move_name, state_time, str(edge_glint), sheath_amount, combo_index,
	]


func cycle_hitstop_preset() -> String:
	var presets := [0.0, 1.0, 1.8]
	var index := presets.find(hitstop_scale)
	hitstop_scale = presets[(index + 1) % presets.size()] if index >= 0 else 1.0
	if hitstop_scale <= 0.0:
		return "Off"
	if hitstop_scale > 1.4:
		return "Exaggerated"
	return "Normal"


func _exit_tree() -> void:
	time_effects.reset()
