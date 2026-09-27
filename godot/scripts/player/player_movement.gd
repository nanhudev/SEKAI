extends CharacterBody3D

@export var tuning: CombatTuning = preload("res://resources/tuning/CombatTuning.tres")
@export var mouse_sensitivity := 0.0024

var health := 100.0
var mana := 100.0
var stamina := 100.0
var unlimited_resources := false

@onready var look_pivot: Node3D = $CameraRig/LookPivot
@onready var hurtbox: CombatHurtbox = $Hurtbox
@onready var combat: CombatController = $CombatController
# The other weapon. Both always exist; only one is held. Movement asks the chain
# for a scale of its own because a chain attack does NOT lock movement (§28) while
# a sword attack scales it — that asymmetry is part of what makes them two
# weapons rather than one weapon with two skins.
@onready var chain: ChainDirector = get_node_or_null("ChainDirector")

# A decaying velocity rather than a position write. A hook that lands on something
# heavy pulls the PLAYER instead of the target (§18), and the body's own collision
# and the walk solver still have to get the last word on where that ends up.
var external_velocity := Vector3.ZERO

# How fast that velocity bleeds off. Because the integral of v * e^(-kt) is v / k,
# an impulse of v m/s travels v / PUSH_DECAY metres — which is why callers that
# want a DISPLACEMENT should say so through pull() instead of guessing a speed.
const PUSH_DECAY := 9.0


func push(velocity: Vector3) -> void:
	external_velocity += velocity


# Drag the player a specific distance. The chain is the weapon of SPACE: it knows
# how far it should move you and nothing about how velocity decays, so "0.8m
# toward the thing you hooked" is the interface and this file owns the conversion.
# Without this seam a pull tuned by speed is unreadable — 9.0 m/s through this
# decay is only 1.0m, and a "yank" that moves you a third of a metre is not a yank.
func pull(offset: Vector3) -> void:
	push(Vector3(offset.x, 0.0, offset.z) * PUSH_DECAY)


# Strip the transient back out of the body's own velocity — see _physics_process.
# A wall (or the floor) can ABSORB a push, and move_and_slide then reports a
# velocity that no longer contains it; subtracting anyway would invent motion in
# the opposite direction. So a result that crossed zero becomes a stop instead:
# the body was stopped, and stopped is what it should stay.
func _strip_push(value: float, push: float) -> float:
	var left := value - push
	if not is_zero_approx(value) and left * value < 0.0:
		return 0.0
	return left


func _ready() -> void:
	_bind_key("move_forward", KEY_W)
	_bind_key("move_back", KEY_S)
	_bind_key("move_left", KEY_A)
	_bind_key("move_right", KEY_D)
	_bind_key("jump", KEY_SPACE)
	_bind_key("sprint", KEY_SHIFT)
	_bind_key("dodge", KEY_Q)
	hurtbox.owner_actor = self
	# Anything that needs the player finds them here instead of assuming it lives
	# next to them, so a stage is free to own its own enemies.
	add_to_group(CombatTuning.PLAYER_GROUP)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _bind_key(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		$CameraFeedbackController.on_mouse_look(event.relative * mouse_sensitivity)
		look_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		look_pivot.rotation.x = clampf(look_pivot.rotation.x, -1.45, 1.45)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if unlimited_resources:
		mana = 100.0
		stamina = 100.0
	if not is_on_floor():
		velocity.y -= 14.0 * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = tuning.jump_velocity

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_vector.x, 0, input_vector.y)).normalized()
	if combat.state == combat.State.DODGE:
		velocity.x = combat.dodge_direction.x * combat.dodge_speed_now()
		velocity.z = combat.dodge_direction.z * combat.dodge_speed_now()
		move_and_slide()
		return
	if combat.state in [combat.State.IAIDO, combat.State.ULTIMATE]:
		velocity = Vector3.ZERO
		return
	# Attacks do not lock movement: they scale it, and they add a lunge whose
	# shape is authored per move. Styles that steer more (回风) simply feel freer.
	# 风步 multiplies on top: momentum magic changes how fast you can reposition,
	# it never teleports you.
	var speed := (
		(tuning.sprint_speed if Input.is_action_pressed("sprint") else tuning.walk_speed)
		* combat.movement_scale()
		* combat.speed_multiplier()
		* _weapon_movement_scale()
	)
	var target := direction * speed
	var lunge := combat.attack_lunge_velocity()
	if lunge != Vector3.ZERO:
		# A lunge is an impulse, not an acceleration ramp, or it never lands.
		velocity.x = target.x + lunge.x
		velocity.z = target.z + lunge.z
	else:
		velocity.x = move_toward(velocity.x, target.x, tuning.acceleration * delta)
		velocity.z = move_toward(velocity.z, target.z, tuning.acceleration * delta)
	# 曳 / 缚 on something too heavy to move drags the player toward it. This rides
	# on top of the walk solver rather than replacing it, so the player can still
	# resist, and it decays instead of being a teleport.
	#
	# THE PUSH IS A TRANSIENT AND IS TAKEN BACK OUT AFTER THE MOVE. Left in
	# `velocity`, it was re-spent by `move_and_slide` on every frame until the walk
	# solver's acceleration ramp bled it away — and that ramp removes a fixed
	# `acceleration * delta` per frame, so a push decayed far slower than it was
	# supposed to. Measured with a scratch probe: `pull(0.25)` moved the player
	# 3.75m, a factor of 15. Every distance this weapon states ("0.8m of forward
	# drag" for a heavy enemy) was therefore a lie by the same factor, and no
	# screenshot could show it because 3.75m of being dragged looks fine.
	# `external_velocity` is now the only thing that carries a push, so the sum of
	# the frames is exactly v / PUSH_DECAY = the displacement that was asked for.
	var push := external_velocity
	velocity.x += push.x
	velocity.z += push.z
	move_and_slide()
	velocity.x = _strip_push(velocity.x, push.x)
	velocity.z = _strip_push(velocity.z, push.z)
	external_velocity = external_velocity.lerp(Vector3.ZERO, minf(1.0, delta * PUSH_DECAY))


func _weapon_movement_scale() -> float:
	if chain == null:
		return 1.0
	return chain.movement_scale()
