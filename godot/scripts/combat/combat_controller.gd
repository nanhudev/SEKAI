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
# --- magic, as data ----------------------------------------------------------
var schools: Dictionary = {}
var spell_id: StringName = &"frost_stream"
var active_spell: SpellDefinition
var active_field: ElementField
var blade_infusion_left := 0.0
var blade_element: StringName = &"physical"
var wind_step_left := 0.0
var iaido_ready_at := 0.0
var ultimate_ready_at := 0.0

# --- measure (白蔷庭) -------------------------------------------------------
# Distance is read live so the player can watch the state change while they move,
# but it is SAMPLED at commit time when a move begins: closing the gap mid-swing
# must not retrofit the reward onto a swing that was started out of position.
var measure_range := -1.0
var measure_state: StringName = &""
# Reach bonus carried into the hitbox for the move currently being committed.
var move_reach_bonus := 0.0
var measure_ideal_count := 0
var bind_until := 0.0
# 藏锋's loop closer: set by a perfect guard, waives the pre-sheath wait.
var sheath_waive_until := 0.0

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

# --- 势 / Flow (回风式) -------------------------------------------------------
# Resolved only when moveset.flow_enabled. Kept on the controller rather than
# in the moveset because it is per-fight state, not per-style data.
var flow := 0.0
var flow_idle_time := 0.0
var flow_peak := 0.0

# --- enhance state (纳息 / 惊鸿) ----------------------------------------------
var enhance_left := 0.0
var enhance_startup_scale := 1.0
var enhance_perfect_guard_bonus := 0.0
var enhance_first_hit_poise_scale := 1.0
var enhance_skill_id: StringName = &""
# 惊鸿's contribution: transitions and steering, not numbers.
var enhance_transition_bonus := 0.0
var enhance_steer_bonus := 1.0

# --- slip state (折柳) --------------------------------------------------------
var slip_until := 0.0
var slip_skill: SwordSkill
var slip_count := 0

# Sideways mirror for signatures the player aims themselves (长风). +1 = right.
var move_mirror := 1.0


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
	schools = MagicLibrary.all()
	set_style(starting_style, true)
	select_school(&"frost")


# ---------------------------------------------------------------- magic data

func select_school(school_id: StringName) -> bool:
	if not schools.has(school_id):
		return false
	var school: MagicSchool = schools[school_id]
	var primary := school.primary()
	if primary == null:
		return false
	selected_spell = school_id
	casting_spell = school_id
	spell_id = primary.id
	return true


func current_school() -> MagicSchool:
	# selected_spell is the school the Ability Wheel confirmed, so it — not the
	# in-flight cast — decides what "current" means. The cast snapshots its own
	# spell so a wheel change mid-cast cannot swap it underneath.
	return schools.get(selected_spell)


func current_spell() -> SpellDefinition:
	var school := current_school()
	if school == null:
		return null
	return school.get_spell(spell_id) if school.get_spell(spell_id) != null else school.primary()


func spell_by_id(wanted: StringName) -> SpellDefinition:
	for school in schools.values():
		var found := (school as MagicSchool).get_spell(wanted)
		if found != null:
			return found
	return null


func is_infused() -> bool:
	return blade_infusion_left > 0.0 and blade_element != &"physical"


func grant_infusion(element_id: StringName, duration: float) -> void:
	blade_infusion_left = maxf(blade_infusion_left, duration)
	blade_element = element_id


func _update_magic(delta: float) -> void:
	if blade_infusion_left > 0.0:
		blade_infusion_left = maxf(0.0, blade_infusion_left - delta)
		if blade_infusion_left == 0.0:
			blade_element = &"physical"
	if wind_step_left > 0.0:
		wind_step_left = maxf(0.0, wind_step_left - delta)
	# Carrying the blade through a live field lights it. The sword joins the
	# magic system by being moved through it, never by opening a menu.
	if active_field != null and is_instance_valid(active_field) and active_field.is_alive():
		var element := ElementLibrary.get_element(active_field.element_id)
		if element != null and element.infusion_duration > 0.0:
			if player.global_position.distance_to(active_field.global_position) <= active_field.radius:
				grant_infusion(element.id, element.infusion_duration)


func _spend_wind_step() -> void:
	wind_step_left = 2.6


# Wind crossing a live element carries it outward: fire spreads, frost chills
# whatever is standing nearby. This is the mechanical reason the two elements
# are worth combining instead of stacking.
func wind_spread() -> bool:
	var spread_any := false
	var parent := player.get_parent()
	for node in parent.get_children():
		if node is ElementField and (node as ElementField).is_alive():
			var field := node as ElementField
			var element := ElementLibrary.get_element(field.element_id)
			if element != null and element.spread_by_wind:
				field.spread()
				spread_any = true
	# The gust also has to reach the world, not only the actors: pushing a crate
	# is the visible proof that wind is force rather than damage.
	if parent.has_node("WindProps"):
		var props: WindProps = parent.get_node("WindProps")
		var blown := props.blow(
			player.global_position, -player.global_transform.basis.z, 7.0, 55.0, 6.0
		)
		if blown > 0:
			spread_any = true
	if spread_any:
		style_message.emit("风 · 扩散")
	return spread_any


func speed_multiplier() -> float:
	# 风步 is momentum, not a teleport: it changes how fast you can change where
	# you are, and it decays.
	if wind_step_left > 0.0:
		return 1.28
	return 1.0


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
		select_school(&"fire")
		request(&"cast")
	elif event.is_action_pressed("frost_cast"):
		select_school(&"frost")
		request(&"cast")
	elif event.is_action_pressed("wind_cast"):
		select_school(&"wind")
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
	_update_flow(delta)
	_update_magic(delta)
	measure_range = measure_distance_now()
	measure_state = measure_label()

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
	if ability == null:
		finish_action()
		return
	var should_open := state_time >= ability.startup and state_time < ability.startup + ability.active
	if should_open != hitbox_open:
		hitbox_open = should_open
		_current_spell_hitbox().set_active(should_open)
		if should_open:
			# Fires exactly once per cast, when the active window opens.
			_spend_spell()
	if state_time >= ability.startup + ability.active + ability.recovery:
		finish_action()


func _update_sheath(delta: float) -> void:
	if not moveset.sheath_enabled:
		sheath_amount = 0.0
		idle_time = 0.0
		return
	if state == State.IDLE:
		idle_time += delta
		# 截锋 shortens the wait before the sword starts going home: a clean
		# deflect IS 藏锋's moment, so it must also feed the style's own loop.
		var delay := moveset.sheath_delay
		if _now() <= sheath_waive_until:
			delay = 0.0
		if idle_time >= delay:
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


# ------------------------------------------------------------------ 势 / Flow

func _update_flow(delta: float) -> void:
	if not moveset.flow_enabled:
		flow = 0.0
		flow_peak = 0.0
		flow_idle_time = 0.0
		return
	# Standing still is what lets the momentum go. Attacking or being hit keeps
	# it alive; simply holding a guard does not.
	flow_peak = maxf(flow_peak, flow)
	if state in [State.IDLE, State.BLOCK]:
		flow_idle_time += delta
		if flow_idle_time > moveset.flow_decay_delay:
			_lose_flow(moveset.flow_decay * delta)
	else:
		flow_idle_time = 0.0


func flow_ratio() -> float:
	if not moveset.flow_enabled or moveset.flow_max <= 0.0:
		return 0.0
	return clampf(flow / moveset.flow_max, 0.0, 1.0)


func _gain_flow(amount: float) -> void:
	if not moveset.flow_enabled:
		return
	flow_idle_time = 0.0
	flow = clampf(flow + amount, 0.0, moveset.flow_max)
	flow_peak = maxf(flow_peak, flow)


func _lose_flow(amount: float) -> void:
	if not moveset.flow_enabled:
		return
	flow = maxf(0.0, flow - amount)


func reset_flow() -> void:
	flow = 0.0
	flow_peak = 0.0
	flow_idle_time = 0.0


# ------------------------------------------------------------------ requests

# ------------------------------------------------------- measure (白蔷庭)

# The nearest actor standing in the small cone in front of the player. Group
# membership is the entire contract — the controller never asks what kind of
# thing it found, exactly as it never asks what an element means.
func measure_target() -> Node3D:
	var best: Node3D = null
	var best_distance := moveset.measure_max_range
	var origin := player.global_position
	var forward := -player.global_transform.basis.z
	var cos_limit := cos(deg_to_rad(moveset.measure_cone_degrees))
	for node in get_tree().get_nodes_in_group(CombatTuning.TARGET_GROUP):
		var actor := node as Node3D
		if actor == null or not is_instance_valid(actor):
			continue
		if actor.has_method("is_alive") and not actor.call("is_alive"):
			continue
		var to_actor := actor.global_position - origin
		to_actor.y = 0.0
		var distance := to_actor.length()
		if distance <= 0.001 or distance > best_distance:
			continue
		if forward.dot(to_actor / distance) < cos_limit:
			continue
		best = actor
		best_distance = distance
	return best


func measure_distance_now() -> float:
	if not moveset.measure_enabled:
		return -1.0
	var target := measure_target()
	if target == null:
		return -1.0
	var to_target := target.global_position - player.global_position
	to_target.y = 0.0
	return to_target.length()


# &"" means "the style has no measure" or "nobody is in front of you". An empty
# lane is not "too far" — there is simply no fight to measure yet.
func measure_label() -> StringName:
	if not moveset.measure_enabled or measure_range < 0.0:
		return &""
	if measure_range < moveset.measure_close:
		return &"close"
	if measure_range > moveset.measure_far:
		return &"far"
	return &"ideal"


# Measure buys startup, reach and posture. It must never buy damage, or the style
# stops being about controlling distance and becomes about standing still in the
# right spot.
func _apply_measure_scale(move: SwordMove) -> void:
	move_reach_bonus = 0.0
	if not moveset.measure_enabled:
		return
	match measure_label():
		&"close":
			move_startup_scale *= moveset.measure_close_startup_scale
			move_poise_scale *= moveset.measure_close_poise_scale
		&"far":
			move_startup_scale *= moveset.measure_far_startup_scale
			move_poise_scale *= moveset.measure_far_poise_scale
		&"ideal":
			move_startup_scale *= moveset.measure_ideal_startup_scale
			move_poise_scale *= moveset.measure_ideal_poise_scale
			# Only a properly extended point is longer: 穿庭 and 白蔷刺 gain
			# reach, a short horizontal cut gains nothing.
			if move.hitbox_offset.z < -1.6:
				move_reach_bonus = moveset.measure_ideal_reach
			measure_ideal_count += 1


# ----------------------------------------------------------- bind (白蔷庭)

# The perfect guard did not push the attacker away; it trapped the blade. The
# player now has a very short window with three exits, and the choice is the
# reward — not a damage number.
func _bind_open(now: float) -> bool:
	return moveset.guard.bind_enabled and now <= bind_until and state == State.PARRY


func _start_bind_exit(move_id: StringName) -> bool:
	var move := moveset.get_move(move_id)
	if move == null:
		return false
	bind_until = 0.0
	riposte_until = 0.0
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	attack_kind = &"bind"
	_begin_move(move, State.RIPOSTE)
	return true


func request(action: StringName) -> bool:
	var now := _now()
	# 合围: Heavy inside the bind window cuts on the way back out. Light inside
	# the same window is the riposte and is handled immediately below, because
	# in a bind the deck window and the riposte window are the same window.
	if action == &"heavy" and _bind_open(now) and moveset.guard.bind_heavy_id != &"":
		return _start_bind_exit(moveset.guard.bind_heavy_id)
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
			# A bind adds one exit to the parry state: Heavy. Light and Dodge are
			# already the other two.
			if action == &"heavy":
				return _bind_open(_now()) and moveset.guard.bind_heavy_id != &""
			return action in [&"light", &"dodge", &"block"]
		State.ATTACK, State.RIPOSTE:
			if active_move == null:
				return true
			# 势 opens the exits earlier: at full Flow the style stops snagging
			# between cuts. Note this lowers the *threshold fraction*, because a
			# smaller fraction means the cancel unlocks sooner.
			var transition := 1.0
			if moveset.flow_enabled:
				transition = lerpf(1.0, maxf(0.15, 1.0 - moveset.flow_transition_bonus), flow_ratio())
			# 惊鸿 stacks on top of 势: while it is up, the style stops snagging
			# almost entirely, which is what "更自由衔接" has to mean in data.
			if enhance_left > 0.0 and enhance_transition_bonus > 0.0:
				transition *= maxf(0.12, 1.0 - enhance_transition_bonus)
			var cancel_at := (
				effective_startup()
				+ active_move.strike
				+ active_move.pose_span() * active_move.cancel_open * transition
			)
			# 假章: a feint is the ONE move whose exit opens during the wind-up.
			# The threat is the pose; taking the pose back is the technique.
			if active_move.feint_cancel_from < 1.0:
				cancel_at = minf(cancel_at, effective_startup() * active_move.feint_cancel_from)
			if state_time < cancel_at:
				return false
			if action == &"dodge":
				# Dodging out is allowed once the blade has actually been
				# committed past contact: the swing cannot be free, or attacks
				# stop meaning anything. 回风 opens earliest, 藏锋 latest.
				# A feint pulls this gate back with its wind-up, or the style
				# could bluff but not leave.
				var dodge_at := effective_startup() + active_move.strike * moveset.dodge_cancel_from * transition
				if active_move.feint_cancel_from < 1.0:
					dodge_at = minf(dodge_at, effective_startup() * active_move.feint_cancel_from)
				return state_time >= dodge_at
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
	active_spell = null
	# A whiff costs momentum. If missing were free, 回风 would just be a faster
	# Universal and the style would have no idea behind it.
	if (
		moveset.flow_enabled
		and not move_hit
		and attack_kind in [&"light", &"sprint", &"retreat", &"heavy", &"skill"]
	):
		_lose_flow(moveset.flow_loss_miss)
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
	move_reach_bonus = 0.0
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
	var school := current_school()
	var spell := current_spell()
	if spell == null or school == null:
		return false
	casting_spell = school.id
	spell_id = spell.id
	active_spell = spell
	var mana: float = player.get("mana")
	if not player.unlimited_resources and mana < spell.mana_cost:
		active_spell = null
		return false
	if not player.unlimited_resources:
		player.set("mana", mana - spell.mana_cost)
	camera_feedback.fov_kick(1.5 if spell.cast_mode == SpellDefinition.Cast.QUICK else 2.6)
	# Colour comes from the element definition, not from a ternary on a string.
	if school.element != null:
		magic_circle.circle_color = Color(
			school.element.tint.r, school.element.tint.g, school.element.tint.b, 0.85
		)
	_configure_spell_hitbox(spell)
	magic_circle.set_casting(true)
	set_state(State.CAST)
	return true


func _configure_spell_hitbox(spell: SpellDefinition) -> void:
	var target := _current_spell_hitbox()
	target.configure(spell.hitbox_size, spell.hitbox_offset)
	target.damage = spell.hitbox_damage
	target.poise_damage = spell.hitbox_poise
	target.impulse = spell.hitbox_impulse
	target.element = spell.element_id


func _spend_spell() -> void:
	# Called once per cast, when the active window opens, so a spell that leaves
	# something behind does it exactly once.
	var spell := active_spell if active_spell != null else current_spell()
	if spell == null:
		return
	if spell.infuses_blade:
		for school in schools.values():
			var element: ElementDefinition = (school as MagicSchool).element
			if element != null and element.id == spell.element_id:
				grant_infusion(element.id, element.infusion_duration)
				break
	if spell.field_radius > 0.0:
		_spawn_field(spell)
	if spell.id == &"wind_step":
		_spend_wind_step()
	if spell.element_id == ElementLibrary.WIND:
		wind_spread()


func _spawn_field(spell: SpellDefinition) -> void:
	if active_field != null and is_instance_valid(active_field):
		active_field.queue_free()
	var field := ElementField.new()
	field.element_id = spell.element_id
	field.radius = spell.field_radius
	field.duration = spell.field_duration
	field.tick_interval = spell.field_tick_interval
	var element := ElementLibrary.get_element(spell.element_id)
	field.setup(element, player)
	field.position = Vector3(0.0, 0.0, -spell.field_offset)
	player.get_parent().add_child(field)
	field.global_position = player.global_position + (-player.global_transform.basis.z * spell.field_offset)
	active_field = field
	if element != null:
		style_message.emit("%s · 区域封锁" % spell.display_name)


func _start_signature() -> bool:
	# A SIGNATURE is style identity, not the ultimate slot. 聚合斩 is a ceremony
	# (a director takes over); 长风 is a short sequence the player keeps driving.
	if moveset.signature_id == &"":
		style_message.emit("此流派尚无 Signature")
		return false
	if _now() < iaido_ready_at:
		style_message.emit("Signature · 冷却中")
		return false
	if moveset.signature_id == &"iaido":
		return _start_iaido_ceremony()
	return _start_move_signature()


func _start_iaido_ceremony() -> bool:
	var now := _now()
	var stamina: float = player.get("stamina")
	if float(player.get("health")) <= 0.0 or iaido_director.active:
		return false
	if not is_instance_valid(player.get_node_or_null("CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot/TempSwordVisual")):
		return false
	if not player.unlimited_resources and stamina < 35.0:
		style_message.emit("聚合斩 · 体力不足")
		return false
	if not player.unlimited_resources:
		player.set("stamina", stamina - 35.0)
	# SIGNATURE technique: its own cooldown, and it never occupies Ultimate.
	iaido_ready_at = now + iaido_director.tuning.restore_end + 2.0
	buffer.clear()
	set_state(State.IAIDO)
	iaido_director.start_iaido()
	return true


func _start_move_signature() -> bool:
	var move := moveset.get_move(moveset.signature_id)
	if move == null:
		return false
	if not _can_act_now():
		return false
	if state != State.IDLE:
		_close_hitbox()
	apply_player_aimed_mirror()
	iaido_ready_at = _now() + tuning.signature_cooldown
	active_skill = null
	move_startup_scale = 1.0
	move_poise_scale = 1.0
	attack_kind = &"signature"
	buffer.clear()
	_begin_move(move, State.SKILL)
	style_message.emit("%s · SIGNATURE" % move.display_name)
	return true


func apply_player_aimed_mirror() -> void:
	# Signature cuts the player aims: the side comes from the movement input at
	# the moment the cut starts, so the sequence is steered, never scripted.
	var wish := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	move_mirror = -1.0 if wish.x < -0.3 else 1.0


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
	# A sequence the player drives (长风) opens its window immediately: whiffing
	# must not end the player's own combination. 燕返 still has to be earned.
	if move.followup_id != &"" and move.followup_from_start:
		pending_followup_id = move.followup_id
		followup_until = _now() + move.followup_window
	move_mirror = 1.0
	if move.player_aimed:
		apply_player_aimed_mirror()
	# Measure is sampled HERE, at the moment of commitment: walking forward during
	# the wind-up must not retrofit an ideal-measure reward onto a swing that was
	# started out of position.
	_apply_measure_scale(move)
	chain_active = attack_kind in [&"light", &"sprint", &"retreat"]
	_write_hitbox(move, 1.0)
	_emit_move_camera(move)
	_restart_state(next_state)
	move_started.emit(move)


func _write_hitbox(move: SwordMove, damage_scale: float) -> void:
	var offset := Vector3(
		move.hitbox_offset.x * move_mirror,
		move.hitbox_offset.y,
		move.hitbox_offset.z - move_reach_bonus
	)
	hitbox.configure(move.hitbox_size, offset)
	hitbox.damage = move.damage * damage_scale
	hitbox.poise_damage = move.poise_damage * move_poise_scale
	# An infused blade carries its element into the cut, which is how a sword
	# interacts with a state the magic system created.
	hitbox.element = blade_element if is_infused() else move.element
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
	# 折柳 opens its window the instant the skill starts: here the defence IS the
	# skill, so the window must not wait for the move to finish.
	if skill.kind == SwordSkill.Kind.SLIP:
		slip_skill = skill
		slip_until = _now() + skill.slip_window
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
		# 惊鸿 buys smoothness, not numbers.
		enhance_transition_bonus = skill.enhance_transition_bonus
		enhance_steer_bonus = skill.enhance_steer_bonus
		style_message.emit("%s · 生效" % skill.display_name)


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
	enhance_transition_bonus = 0.0
	enhance_steer_bonus = 1.0
	slip_until = 0.0
	slip_skill = null
	move_mirror = 1.0
	move_reach_bonus = 0.0
	bind_until = 0.0
	sheath_waive_until = 0.0
	measure_range = -1.0
	measure_state = &""
	measure_ideal_count = 0
	edge_glint = false
	guard_recoil = 0.0
	parry_lateral = 0.0
	sheath_amount = 0.0
	idle_time = 0.0
	reset_flow()
	style_changed.emit(style_id)
	style_message.emit(moveset.display_name)
	return true


# ------------------------------------------------------------------ movement

func movement_scale() -> float:
	match state:
		State.IDLE:
			return 1.0
		State.ATTACK, State.RIPOSTE, State.SKILL:
			var steer := active_move.steer if active_move != null else 0.2
			# 顺势: at full Flow the sword stops dragging you out of your line.
			if moveset.flow_enabled:
				steer *= lerpf(1.0, moveset.flow_steer_bonus, flow_ratio())
			if enhance_left > 0.0:
				steer *= enhance_steer_bonus
			return steer
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
	# A sidestep in progress (perfect-guard steer, or a 折柳 slip) overrides the
	# move's own forward lunge: leaving the line is the point of both.
	if not is_zero_approx(parry_lateral) and state in [State.PARRY, State.SKILL, State.IDLE]:
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
		# 势 only pays out on connected cuts. A whiff must stay slow, or the
		# style stops punishing the thing it is built to punish.
		if moveset.flow_enabled:
			scale *= lerpf(1.0, moveset.flow_recovery_at_max, flow_ratio())
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
	# A player-aimed cut is the same authored pose taken from the other side,
	# because the player chose the side. Mirroring keeps one authored move able
	# to answer "he is on my left" without a second animation.
	if move_mirror < 0.0 and state in [State.ATTACK, State.RIPOSTE, State.SKILL]:
		position.x = -position.x
		rotation.y = -rotation.y
		rotation.z = -rotation.z
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
	# 势: connecting is what keeps the style alive, and connecting *while moving*
	# feeds it faster. That is the loop 回风 asks the player to chase.
	if moveset.flow_enabled:
		var on_the_move := attack_kind in [&"sprint", &"retreat"] or player.velocity.length() > 3.0
		_gain_flow(moveset.flow_gain_movement_hit if on_the_move else moveset.flow_gain_hit)
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
	# 折柳: the attack is allowed to pass by. Deliberately checked before dodge
	# and before guard — declining the exchange is the fastest answer available,
	# and it is the exact opposite of what Perfect Guard does.
	if _slip_open():
		_resolve_slip(hit)
		return
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


func _slip_open() -> bool:
	return slip_until > 0.0 and _now() <= slip_until


func _resolve_slip(hit: Dictionary) -> void:
	var skill := slip_skill
	slip_until = 0.0
	slip_skill = null
	slip_count += 1
	var counter_window := 0.9
	var distance := 1.7
	var flow_gain := 0.0
	if skill != null:
		counter_window = skill.slip_counter_window
		distance = skill.slip_distance
		flow_gain = skill.slip_flow_gain
	if flow_gain > 0.0:
		_gain_flow(flow_gain)
	# Step off the line. The player's own input decides the side; failing that,
	# slip away from whoever swung, which is always the correct answer.
	var wish := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var side := 0.0
	if absf(wish.x) > 0.1:
		side = signf(wish.x)
	else:
		var attacker: Node = hit.get("source")
		if attacker is Node3D:
			var away: Vector3 = player.global_position - (attacker as Node3D).global_position
			side = signf(away.dot(player.global_basis.x))
		if is_zero_approx(side):
			side = 1.0
	parry_lateral = side * distance
	get_tree().create_timer(0.30).timeout.connect(func() -> void:
		if is_instance_valid(self):
			parry_lateral = 0.0
	)
	camera_feedback.roll_impulse(side * 4.0)
	camera_feedback.add_impulse(Vector2(side * 0.010, 0.004))
	camera_feedback.fov_kick(2.4)
	# The opening the slip left behind is the whole reward.
	riposte_until = _now() + counter_window
	style_message.emit("折柳 · 落空")


func _perfect_guard(hit: Dictionary) -> void:
	var guard := moveset.guard
	perfect_guard_count += 1
	# A clean deflect is the strongest single source of 势: reading the attack
	# should feel like the most "in the flow" answer available.
	if moveset.flow_enabled:
		_gain_flow(moveset.flow_gain_deflect)
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
	if guard.parry_sheath_waiver > 0.0:
		sheath_waive_until = _now() + guard.parry_sheath_waiver
	if guard.bind_enabled:
		# 合围: nothing is flung away and the player does not leave the line. The
		# blade is trapped; the next 0.3s belong to whoever decides fastest.
		bind_until = _now() + maxf(guard.bind_deck_window, guard.riposte_window)
	else:
		bind_until = 0.0
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
	style_message.emit(guard.bind_message if guard.bind_enabled else "截锋 · RIPOSTE 窗口")


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
	# During a cast the snapshot wins, so changing the wheel mid-cast cannot
	# swap the spell's timings out from under it.
	if state == State.CAST and active_spell != null:
		return active_spell
	var spell := current_spell()
	if spell != null:
		return spell
	# Fallback to the original resources if the school table is ever empty.
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
	var flow_text := " · 势=%.0f%%" % (flow_ratio() * 100.0) if moveset.flow_enabled else ""
	var measure_text := ""
	if moveset.measure_enabled:
		var label := measure_state
		if label == &"":
			label = &"-"
		measure_text = " · 距离=%.2fm/%s" % [measure_range, label]
	var bind_text := " · BIND" if _bind_open(_now()) else ""
	return "%s · %s · %.2fs · glint=%s · sheathed=%.2f · chain=%d%s%s%s" % [
		moveset.display_name, move_name, state_time, str(edge_glint), sheath_amount,
		combo_index, flow_text, measure_text, bind_text,
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
