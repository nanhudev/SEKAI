extends Node
class_name CombatController

enum State { IDLE, ATTACK, BLOCK, DODGE, CAST, STAGGER, IAIDO }

signal state_changed(previous: State, current: State)

@export var tuning: CombatTuning = preload("res://resources/tuning/CombatTuning.tres")
@export var frost_ability: AbilityData = preload("res://resources/abilities/frost_stream.tres")
@export var fire_ability: AbilityData = preload("res://resources/abilities/fire_cast.tres")
@export var wind_ability: AbilityData = preload("res://resources/abilities/wind_burst.tres")

@onready var player: CharacterBody3D = get_parent()
@onready var hitbox: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/SwordHitbox")
@onready var frost_hitbox: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/FrostHitbox")
@onready var fire_hitbox: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/FireHitbox")
@onready var wind_hitbox: CombatHitbox = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/WindHitbox")
@onready var camera_feedback: CameraFeedbackController = player.get_node("CameraFeedbackController")
@onready var magic_circle: MagicCircle3D = player.get_node("CameraRig/LookPivot/MotionPivot/ShakePivot/VFXRoot/MagicCircle3D")
@onready var hurtbox: CombatHurtbox = player.get_node("Hurtbox")
@onready var screen_fx: CombatScreenFX = player.get_parent().get_node("CombatScreenFX")
@onready var time_effects: TimeEffectManager = player.get_parent().get_node("TimeEffectManager")

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
	hurtbox.hit_received.connect(_on_player_hit)
	_bind_mouse("light_attack", MOUSE_BUTTON_LEFT)
	_bind_mouse("block", MOUSE_BUTTON_RIGHT)


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
	elif event.is_action_pressed("cast_selected"):
		request(&"cast")
	elif event.is_action_pressed("block"):
		request(&"block")
	elif event.is_action_released("block") and state == State.BLOCK:
		finish_action()


func _process(delta: float) -> void:
	state_time += delta
	if state == State.ATTACK:
		var startup := 0.20 if attack_kind == &"heavy" else 0.09
		var active_end := startup + (0.17 if attack_kind == &"heavy" else 0.12)
		var recovery_end := active_end + (0.32 if attack_kind == &"heavy" else 0.2)
		var should_open := state_time >= startup and state_time < active_end
		if should_open != hitbox_open:
			hitbox_open = should_open
			hitbox.set_active(should_open)
		if state_time >= recovery_end:
			finish_action()
	elif state == State.CAST:
		var ability := _current_ability()
		var should_open := state_time >= ability.startup and state_time < ability.startup + ability.active
		if should_open != hitbox_open:
			hitbox_open = should_open
			_current_spell_hitbox().set_active(should_open)
		if state_time >= ability.startup + ability.active + ability.recovery:
			finish_action()
	elif state == State.DODGE and state_time >= 0.25:
		finish_action()
	elif state == State.IAIDO:
		screen_fx.set_iaido_focus(minf(0.65, state_time / 0.28 * 0.65))
		var should_open := state_time >= 0.35 and state_time < 0.5
		if should_open != hitbox_open:
			hitbox_open = should_open
			hitbox.set_active(should_open)
			if should_open:
				screen_fx.slash_flash(1.0)
				camera_feedback.roll_impulse(2.5)
		if state_time >= 0.54:
			screen_fx.slash_flash(maxf(0.0, 1.0 - (state_time - 0.54) / 0.22))
		if state_time >= 1.1:
			finish_action()


func request(action: StringName) -> bool:
	if state != State.IDLE:
		if state == State.ATTACK and attack_kind == &"light" and action in [&"dodge", &"block"] and state_time >= 0.12:
			hitbox.set_active(false)
			hitbox_open = false
			buffer.clear()
			set_state(State.IDLE)
			return _start(action)
		buffer.push(action, Time.get_ticks_msec() / 1000.0)
		return false
	return _start(action)


func finish_action() -> void:
	hitbox.set_active(false)
	hitbox.hit_delay = 0.0
	frost_hitbox.set_active(false)
	fire_hitbox.set_active(false)
	wind_hitbox.set_active(false)
	magic_circle.set_casting(false)
	if state == State.IAIDO:
		screen_fx.reset()
		camera_feedback.fov_hold = 0.0
		time_effects.reset()
	hitbox_open = false
	set_state(State.IDLE)
	var next := buffer.take(Time.get_ticks_msec() / 1000.0)
	if next != &"":
		_start(next)


func set_state(next: State) -> void:
	if state == next:
		return
	var previous := state
	state = next
	state_time = 0.0
	state_changed.emit(previous, next)


func _start(action: StringName) -> bool:
	match action:
		&"light", &"heavy":
			attack_kind = action
			if action == &"light":
				var now := Time.get_ticks_msec() / 1000.0
				combo_index = combo_index % 3 + 1 if now - last_light_at <= tuning.combo_window else 1
				last_light_at = now
			else:
				combo_index = 0
			hitbox.damage = 36.0 if action == &"heavy" else 18.0
			hitbox.poise_damage = 45.0 if action == &"heavy" else 15.0
			var camera_x := 0.008 if action == &"heavy" else (0.005 if combo_index == 3 else 0.003)
			camera_feedback.add_impulse(Vector2(camera_x, 0.0))
			set_state(State.ATTACK)
		&"block": set_state(State.BLOCK)
		&"dodge":
			var stamina: float = player.get("stamina")
			if stamina < tuning.dodge_stamina_cost:
				return false
			player.set("stamina", stamina - tuning.dodge_stamina_cost)
			var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			var wish := Vector3(input_vector.x, 0, input_vector.y)
			dodge_direction = (player.transform.basis * (wish if wish.length_squared() > 0.01 else Vector3.FORWARD)).normalized()
			camera_feedback.fov_kick(3.0)
			set_state(State.DODGE)
		&"cast":
			casting_spell = selected_spell
			var mana: float = player.get("mana")
			var ability := _current_ability()
			if mana < ability.mana_cost:
				return false
			player.set("mana", mana - ability.mana_cost)
			camera_feedback.fov_kick(1.5)
			magic_circle.circle_color = Color(1.0, 0.55, 0.2, 0.85) if casting_spell == &"fire" else (Color(0.75, 0.8, 0.8, 0.8) if casting_spell == &"wind" else Color(0.55, 0.85, 1.0, 0.8))
			magic_circle.set_casting(true)
			set_state(State.CAST)
		&"iaido":
			var now := Time.get_ticks_msec() / 1000.0
			var stamina: float = player.get("stamina")
			if now < iaido_ready_at or stamina < 35.0:
				return false
			player.set("stamina", stamina - 35.0)
			iaido_ready_at = now + 5.0
			hitbox.damage = 65.0
			hitbox.poise_damage = 70.0
			hitbox.hit_delay = 0.08
			camera_feedback.fov_hold = 7.0
			time_effects.request_slow_motion(0.55, 1.2)
			set_state(State.IAIDO)
		_: return false
	return true


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


func _on_player_hit(hit: Dictionary) -> void:
	if state == State.DODGE and state_time < 0.2:
		return
	if state == State.BLOCK:
		if state_time <= tuning.perfect_guard_window:
			perfect_guard_count += 1
			camera_feedback.add_impulse(Vector2(0.02, -0.03))
			camera_feedback.add_trauma(0.24)
			var attacker: Node = hit.get("source")
			if attacker != null and attacker.has_method("on_perfect_guard"):
				attacker.call("on_perfect_guard")
		else:
			var stamina: float = player.get("stamina")
			player.set("stamina", maxf(0.0, stamina - 12.0))
		return
	var health: float = player.get("health")
	player.set("health", maxf(0.0, health - float(hit.get("damage", 0.0))))
	camera_feedback.add_trauma(0.12)
